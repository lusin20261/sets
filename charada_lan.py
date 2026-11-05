#!/usr/bin/env python3
"""Modo multijugador LAN para Quiz Escolar.

Uso interno: python3 charada_lan.py /ruta/al/charada.sh
El servidor escucha en todas las interfaces IPv4, puerto 50555 por defecto.
"""

from __future__ import annotations

import concurrent.futures
import ipaddress
import json
import os
import random
import re
import socket
import subprocess
import socketserver
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PORT = int(os.environ.get("QUIZ_LAN_PORT", "50555"))
COUNTDOWN_SECONDS = 120
QUESTIONS_PER_GAME = 20
MAX_PLAYERS = 60
CATEGORY_NAMES = {
    "CG": "Cultura general",
    "MA": "Matemática",
    "EN": "Inglés",
    "ZH": "Chino básico",
}
LETTERS = "abcd"


def read_bank(script_path: Path) -> list[dict[str, str]]:
    """Read the original BANCO heredoc so there is only one source of questions."""
    try:
        source = script_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"No se pudo abrir el banco de preguntas: {script_path}\n{exc}") from exc

    marker = "mapfile -t BANCO_CRUDO <<'FIN_BANCO'"
    if marker not in source:
        raise RuntimeError("No se encontró el bloque FIN_BANCO en el script original.")
    bank_text = source.split(marker, 1)[1].split("FIN_BANCO", 1)[0]

    bank: list[dict[str, str]] = []
    for line in bank_text.splitlines():
        if not re.match(r"^(CG|MA|EN|ZH)\|", line):
            continue
        fields = line.split("|")
        if len(fields) != 6:
            continue
        category, question, correct, *wrong = fields
        bank.append({
            "category": category,
            "question": question,
            "correct": correct,
            "wrong": wrong,
        })

    if len(bank) < QUESTIONS_PER_GAME:
        raise RuntimeError(
            f"El banco solo tiene {len(bank)} preguntas válidas; se necesitan {QUESTIONS_PER_GAME}."
        )
    return bank


def clean_name(value: str) -> str:
    value = "".join(ch for ch in value if ch.isprintable() and ch not in "|\r\n")
    return " ".join(value.split())[:24]


def valid_password(value: str) -> bool:
    # Una sola palabra: letras Unicode, sin espacios, guiones ni símbolos.
    return bool(value) and value.isalpha() and len(value) <= 32


def send_json(sock: socket.socket, lock: threading.Lock, payload: dict[str, Any]) -> bool:
    try:
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
        with lock:
            sock.sendall(data.encode("utf-8"))
        return True
    except (OSError, UnicodeError):
        return False


def receive_json(reader: Any) -> dict[str, Any] | None:
    line = reader.readline()
    if not line:
        return None
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


@dataclass
class Player:
    name: str
    sock: socket.socket
    send_lock: threading.Lock = field(default_factory=threading.Lock)
    start_event: threading.Event = field(default_factory=threading.Event)
    ready: bool = False
    done: bool = False
    disconnected: bool = False
    correct: int = 0

    def send(self, payload: dict[str, Any]) -> bool:
        return send_json(self.sock, self.send_lock, payload)


class RoomState:
    def __init__(self, password: str, questions: list[dict[str, str]]) -> None:
        self.password = password
        self.questions = random.sample(questions, QUESTIONS_PER_GAME)
        self.created_at = time.monotonic()
        self.start_at = self.created_at + COUNTDOWN_SECONDS
        self.started = False
        self.players: list[Player] = []
        self.condition = threading.Condition()

    def snapshot_names(self) -> list[str]:
        with self.condition:
            return [p.name for p in self.players if not p.disconnected]

    def discovery_info(self) -> dict[str, Any] | None:
        """Return public room data only while the lobby is still accepting players."""
        with self.condition:
            remaining = self.start_at - time.monotonic()
            if self.started or remaining <= 0:
                return None
            players = [p.name for p in self.players if not p.disconnected]
            return {
                "remaining": max(0, int(remaining + 0.999)),
                "players": players,
            }

    def register(self, name: str, password: str, conn: socket.socket) -> tuple[Player | None, str | None, int]:
        with self.condition:
            now = time.monotonic()
            if password != self.password:
                return None, "Contraseña incorrecta.", 0
            if self.started or now >= self.start_at:
                return None, "La partida ya comenzó. No se admiten más jugadores.", 0
            if len(self.players) >= MAX_PLAYERS:
                return None, f"La sala alcanzó el máximo de {MAX_PLAYERS} jugadores.", 0
            if any(p.name.casefold() == name.casefold() and not p.disconnected for p in self.players):
                return None, "Ese nombre ya está en uso en esta sala. Elige otro.", 0
            player = Player(name=name, sock=conn)
            self.players.append(player)
            remaining = max(0, int(self.start_at - now + 0.999))
            return player, None, remaining

    def mark_ready(self, player: Player) -> None:
        start_now = False
        with self.condition:
            player.ready = True
            start_now = self.started
        if start_now:
            # El mensaje debe llegar antes de liberar al hilo que envía preguntas.
            player.send({"type": "start"})
            player.start_event.set()

    def mark_disconnected(self, player: Player) -> None:
        with self.condition:
            player.disconnected = True
            player.start_event.set()
            self.condition.notify_all()

    def mark_done(self, player: Player, correct: int) -> None:
        with self.condition:
            player.correct = correct
            player.done = True
            self.condition.notify_all()

    def countdown_tick(self) -> bool:
        """Broadcast countdown; return False once the game has started."""
        with self.condition:
            if self.started:
                return False
            remaining = self.start_at - time.monotonic()
            if remaining <= 0:
                self.started = True
                ready_players = [p for p in self.players if p.ready and not p.disconnected]
                start_payload = {"type": "start"}
                countdown_payload = None
            else:
                ready_players = [p for p in self.players if p.ready and not p.disconnected]
                start_payload = None
                countdown_payload = {
                    "type": "countdown",
                    "remaining": max(0, int(remaining + 0.999)),
                    "players": [p.name for p in self.players if not p.disconnected],
                }

        if start_payload is not None:
            for player in ready_players:
                player.send(start_payload)
                player.start_event.set()
            return False

        for player in ready_players:
            player.send(countdown_payload or {})
        return True

    def all_finished(self) -> bool:
        return all(p.done or p.disconnected for p in self.players)

    def results(self) -> list[dict[str, Any]]:
        with self.condition:
            completed = [p for p in self.players if p.done]
            completed.sort(key=lambda p: (-p.correct, p.name.casefold()))
            return [
                {"name": p.name, "correct": p.correct, "score": p.correct}
                for p in completed
            ]

    def wait_for_results(self) -> list[dict[str, Any]]:
        with self.condition:
            while not self.all_finished():
                self.condition.wait()
            completed = [p for p in self.players if p.done]
            completed.sort(key=lambda p: (-p.correct, p.name.casefold()))
            return [
                {"name": p.name, "correct": p.correct, "score": p.correct}
                for p in completed
            ]


class QuizTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address: tuple[str, int], handler: type["QuizHandler"], room: RoomState):
        self.room = room
        super().__init__(address, handler)


class QuizHandler(socketserver.BaseRequestHandler):
    server: QuizTCPServer

    def handle(self) -> None:
        player: Player | None = None
        reader = None
        try:
            self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            reader = self.request.makefile("r", encoding="utf-8", newline="\n")
            hello = receive_json(reader)
            if hello and hello.get("type") == "discover":
                room_info = self.server.room.discovery_info()
                if room_info is not None:
                    send_json(self.request, threading.Lock(), {"type": "room_found", **room_info})
                return

            if not hello or hello.get("type") != "join":
                send_json(self.request, threading.Lock(), {"type": "error", "message": "Solicitud de conexión no válida."})
                return

            name = clean_name(str(hello.get("name", "")))
            password = str(hello.get("password", ""))
            if not name:
                send_json(self.request, threading.Lock(), {"type": "error", "message": "Escribe un nombre válido."})
                return

            player, error, remaining = self.server.room.register(name, password, self.request)
            if error:
                send_json(self.request, threading.Lock(), {"type": "error", "message": error})
                return

            player.send({
                "type": "joined",
                "remaining": remaining,
                "players": self.server.room.snapshot_names(),
            })
            self.server.room.mark_ready(player)
            player.start_event.wait()

            # Si se desconectó durante la cuenta regresiva, no participa.
            if player.disconnected:
                return

            correct_count = 0
            for index, question in enumerate(self.server.room.questions, start=1):
                options = [question["correct"], *question["wrong"]]
                random.shuffle(options)
                correct_letter = LETTERS[options.index(question["correct"])]
                if not player.send({
                    "type": "question",
                    "index": index,
                    "total": QUESTIONS_PER_GAME,
                    "category": CATEGORY_NAMES.get(question["category"], question["category"]),
                    "question": question["question"],
                    "options": options,
                }):
                    raise ConnectionError("No se pudo enviar la pregunta.")

                answer = receive_json(reader)
                if not answer or answer.get("type") != "answer":
                    raise ConnectionError("El jugador se desconectó.")
                selected = str(answer.get("value", "")).lower().strip()
                is_correct = selected == correct_letter
                if is_correct:
                    correct_count += 1

                if not player.send({
                    "type": "feedback",
                    "correct": is_correct,
                    "right_answer": question["correct"],
                    "score": correct_count,
                }):
                    raise ConnectionError("No se pudo enviar el resultado de la respuesta.")

            self.server.room.mark_done(player, correct_count)
            player.send({"type": "waiting_results"})
            final_results = self.server.room.wait_for_results()
            player.send({"type": "results", "players": final_results})

        except (OSError, ConnectionError, UnicodeError):
            pass
        finally:
            if player is not None and not player.done:
                self.server.room.mark_disconnected(player)
            try:
                if reader is not None:
                    reader.close()
            except OSError:
                pass


def countdown_worker(room: RoomState) -> None:
    while room.countdown_tick():
        time.sleep(1)


def local_ipv4_networks() -> tuple[list[ipaddress.IPv4Network], set[str]]:
    """Detect connected IPv4 networks; keep scans bounded on unusually large subnets."""
    networks: set[ipaddress.IPv4Network] = set()
    local_addresses: set[str] = set()

    try:
        result = subprocess.run(
            ["ip", "-j", "-4", "addr", "show", "up"],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        interfaces = json.loads(result.stdout)
        for interface in interfaces:
            if interface.get("ifname") == "lo":
                continue
            for address in interface.get("addr_info", []):
                if address.get("family") != "inet":
                    continue
                local = str(address.get("local", ""))
                if not local or local.startswith(("127.", "169.254.")):
                    continue
                try:
                    iface = ipaddress.ip_interface(f"{local}/{address['prefixlen']}")
                except (KeyError, ValueError):
                    continue
                local_addresses.add(local)
                network = iface.network
                # A /16 or larger can contain tens of thousands of addresses.
                # In that case scan the /24 containing this machine instead.
                if network.num_addresses > 4096 or network.prefixlen >= 31:
                    network = ipaddress.ip_network(f"{local}/24", strict=False)
                networks.add(network)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        pass

    # Fallback for systems where the `ip` utility is unavailable.
    if not networks:
        try:
            for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
                local = item[4][0]
                if local.startswith(("127.", "169.254.")):
                    continue
                local_addresses.add(local)
                networks.add(ipaddress.ip_network(f"{local}/24", strict=False))
        except (OSError, ValueError):
            pass

    # Last resort: ask the routing table which local address reaches an external test IP.
    if not networks:
        try:
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                probe.connect(("192.0.2.1", 9))
                local = probe.getsockname()[0]
                if not local.startswith(("127.", "169.254.")):
                    local_addresses.add(local)
                    networks.add(ipaddress.ip_network(f"{local}/24", strict=False))
            finally:
                probe.close()
        except (OSError, ValueError):
            pass

    return sorted(networks, key=lambda net: (int(net.network_address), net.prefixlen)), local_addresses


def probe_room(host: str) -> dict[str, Any] | None:
    """Ask a host whether it is running an open Quiz Escolar lobby."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    reader = None
    try:
        sock.settimeout(0.35)
        sock.connect((host, PORT))
        sock.settimeout(0.8)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        reader = sock.makefile("r", encoding="utf-8", newline="\n")
        if not send_json(sock, threading.Lock(), {"type": "discover"}):
            return None
        response = receive_json(reader)
        if response and response.get("type") == "room_found":
            return {
                "host": host,
                "remaining": int(response.get("remaining", 0)),
                "players": response.get("players", []),
            }
    except (OSError, TimeoutError, UnicodeError):
        return None
    finally:
        try:
            if reader is not None:
                reader.close()
        except OSError:
            pass
        sock.close()
    return None


def discover_rooms() -> list[dict[str, Any]]:
    """Scan detected local subnets for Quiz Escolar rooms on the configured port."""
    networks, local_addresses = local_ipv4_networks()
    if not networks:
        print("No pude detectar una red IPv4 activa en este equipo.")
        return []

    targets: set[str] = set()
    for network in networks:
        for address in network.hosts():
            host = str(address)
            if host not in local_addresses:
                targets.add(host)

    if not targets:
        print("No se encontraron equipos que pueda revisar en la red local.")
        return []

    print("\nEscaneando la red local en busca de salas activas...", flush=True)
    rooms: list[dict[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=128) as executor:
        futures = [executor.submit(probe_room, host) for host in targets]
        for future in concurrent.futures.as_completed(futures):
            room = future.result()
            if room is not None:
                rooms.append(room)

    rooms.sort(key=lambda room: tuple(int(part) for part in room["host"].split(".")))
    return rooms


def ask_name() -> str:
    while True:
        name = clean_name(input("Tu nombre: "))
        if name:
            return name
        print("Escribe al menos un carácter para tu nombre.")


def ask_password(create: bool) -> str:
    while True:
        prompt = "Crea una contraseña de una sola palabra (solo letras, sin espacios): " if create else "Contraseña de la sala: "
        password = input(prompt).strip()
        if create and not valid_password(password):
            print("La contraseña debe ser una sola palabra, formada únicamente por letras (máximo 32).")
            continue
        if not password:
            print("La contraseña no puede estar vacía.")
            continue
        return password


def read_answer() -> str:
    while True:
        value = input("Tu respuesta (a, b, c o d): ").strip().lower()
        if value in LETTERS:
            return value
        print("Escribe únicamente a, b, c o d.")


def render_lobby(remaining: int, players: list[str]) -> None:
    """Redraw the lobby in place instead of printing a new line every second."""
    minutes, seconds = divmod(max(0, remaining), 60)
    names = players or ["Esperando jugadores..."]
    if sys.stdout.isatty():
        sys.stdout.write("\033[2J\033[H")
        print("╔══════════════════════════════════════════════════════╗")
        print("║                 QUIZ ESCOLAR · SALA LAN              ║")
        print("╚══════════════════════════════════════════════════════╝")
        print(f"\n  La partida comienza en: {minutes:02d}:{seconds:02d}")
        print(f"  Jugadores conectados ({len(players)}):")
        for player_name in names:
            print(f"    • {player_name}")
        print("\n  Puedes seguir ingresando mientras el contador esté activo.")
        sys.stdout.flush()
    else:
        line = f"Sala LAN | Empieza en {minutes:02d}:{seconds:02d} | Jugadores ({len(players)}): {', '.join(names)}"
        sys.stdout.write("\r\033[2K" + line[:200])
        sys.stdout.flush()


def play_as_client(host: str, password: str, name: str) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    reader = None
    try:
        sock.settimeout(8)
        sock.connect((host, PORT))
        sock.settimeout(None)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        reader = sock.makefile("r", encoding="utf-8", newline="\n")
        send_json(sock, threading.Lock(), {
            "type": "join",
            "name": name,
            "password": password,
        })

        first = receive_json(reader)
        if not first:
            print("El servidor cerró la conexión sin responder.")
            return
        if first.get("type") == "error":
            print(f"\nNo se pudo entrar: {first.get('message', 'error desconocido')}")
            return
        if first.get("type") != "joined":
            print("Respuesta inesperada del servidor.")
            return

        print("\nConectado a la sala. La cuenta regresiva comenzó al crearla.")
        render_lobby(int(first.get("remaining", COUNTDOWN_SECONDS)), first.get("players", []))
        started = False
        while not started:
            message = receive_json(reader)
            if not message:
                print("\nSe perdió la conexión con la sala.")
                return
            kind = message.get("type")
            if kind == "countdown":
                render_lobby(int(message.get("remaining", 0)), message.get("players", []))
            elif kind == "start":
                started = True
            elif kind == "error":
                print(f"\n{message.get('message', 'Error de sala.')}")
                return
        if sys.stdout.isatty():
            sys.stdout.write("\033[2J\033[H")
        print("\n¡Comienza la partida! Son 20 preguntas. Cada acierto vale 1 punto.\n")

        for _ in range(QUESTIONS_PER_GAME):
            message = receive_json(reader)
            if not message or message.get("type") != "question":
                print("Se perdió la conexión mientras se recibía una pregunta.")
                return

            index = int(message["index"])
            total = int(message["total"])
            print("\n" + "═" * 66)
            print(f"PREGUNTA {index}/{total}   |   {message.get('category', '')}")
            print("─" * 66)
            print(message.get("question", ""))
            print()
            options = message.get("options", [])
            for pos, option in enumerate(options[:4]):
                print(f"  {LETTERS[pos]}) {option}")

            selected = read_answer()
            send_json(sock, threading.Lock(), {"type": "answer", "value": selected})
            feedback = receive_json(reader)
            if not feedback or feedback.get("type") != "feedback":
                print("No se pudo recibir la corrección de la respuesta.")
                return
            if feedback.get("correct"):
                print(f"\n  ✓ ¡Correcto! Puntaje: {feedback.get('score', 0)}/20")
            else:
                print(f"\n  ✗ Respuesta correcta: {feedback.get('right_answer', '')}. Puntaje: {feedback.get('score', 0)}/20")

        waiting = receive_json(reader)
        if waiting and waiting.get("type") == "waiting_results":
            print("\nTerminaste las 20 preguntas. Esperando a los demás jugadores...")

        final = receive_json(reader)
        if not final or final.get("type") != "results":
            print("No se pudo recibir la tabla final de resultados.")
            return
        show_results(final.get("players", []), name)

    except (OSError, TimeoutError) as exc:
        print(f"\nNo se pudo conectar con {host}:{PORT}. Verifica la IP, la red y el puerto.\nDetalle: {exc}")
    finally:
        try:
            if reader is not None:
                reader.close()
        except OSError:
            pass
        sock.close()


def show_results(players: list[dict[str, Any]], own_name: str) -> None:
    print("\n" + "═" * 66)
    print("                 RESULTADOS FINALES")
    print("═" * 66)
    if not players:
        print("No hay resultados para mostrar.")
        return
    print(f"{'Puesto':<9}{'Jugador':<28}{'Puntaje':>12}")
    print("─" * 52)
    for place, player in enumerate(players, start=1):
        marker = "  ← tú" if str(player.get("name", "")).casefold() == own_name.casefold() else ""
        print(f"{place:<9}{str(player.get('name', '')):<28}{str(player.get('score', 0)) + '/20':>12}{marker}")
    own = next((p for p in players if str(p.get("name", "")).casefold() == own_name.casefold()), None)
    if own:
        print("\n" + "─" * 52)
        print(f"Tu resultado: {own.get('score', 0)}/20 respuestas correctas.")
        if players[0].get("name", "").casefold() == own_name.casefold():
            print("¡Felicidades! Obtuviste el primer puesto.")


def create_room(bank: list[dict[str, str]]) -> None:
    print("\n══ CREAR SALA LAN ══")
    password = ask_password(create=True)
    name = ask_name()
    room = RoomState(password, bank)
    try:
        server = QuizTCPServer(("0.0.0.0", PORT), QuizHandler, room)
    except OSError as exc:
        print(f"No se pudo abrir el puerto {PORT}: {exc}")
        print("Cierra otra sala o cambia QUIZ_LAN_PORT antes de ejecutar el juego.")
        return

    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    timer_thread = threading.Thread(target=countdown_worker, args=(room,), daemon=True)
    timer_thread.start()

    print("\nSala creada correctamente.")
    print("Los demás equipos pueden encontrarla desde 'Unirse a una sala'.")
    print(f"Contraseña de la sala: {password}")
    print("El contador de 02:00 ya está en marcha.\n")

    try:
        play_as_client("127.0.0.1", password, name)
    finally:
        server.shutdown()
        server.server_close()


def join_room(bank: list[dict[str, str]]) -> None:
    del bank  # El banco lo administra el servidor para que todos reciban las mismas preguntas.
    print("\n══ UNIRSE A UNA SALA LAN ══")
    rooms = discover_rooms()
    if not rooms:
        print("\nNo se encontraron salas disponibles.")
        print("Comprueba que todos estén en la misma red y que el anfitrión haya creado la sala.")
        return

    print(f"\nSe encontraron {len(rooms)} sala(s):\n")
    for index, room in enumerate(rooms, start=1):
        remaining = int(room["remaining"])
        minutes, seconds = divmod(remaining, 60)
        names = room.get("players", [])
        print(f"  {index}) {room['host']}  |  {len(names)} jugador(es)  |  empieza en {minutes:02d}:{seconds:02d}")
        if names:
            print(f"     {', '.join(names)}")

    if len(rooms) == 1:
        selected = rooms[0]
    else:
        while True:
            choice = input("\nElige la sala a la que deseas entrar: ").strip()
            if choice.isdigit() and 1 <= int(choice) <= len(rooms):
                selected = rooms[int(choice) - 1]
                break
            print("Selecciona uno de los números de la lista.")

    password = ask_password(create=False)
    name = ask_name()
    play_as_client(selected["host"], password, name)


def main() -> int:
    script_path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).with_name("charada.sh")
    try:
        bank = read_bank(script_path)
    except RuntimeError as exc:
        print(f"\nError: {exc}")
        return 1

    while True:
        print("\n" + "═" * 46)
        print("           MULTIJUGADOR · RED LOCAL")
        print("═" * 46)
        print("  1) Crear sala")
        print("  2) Unirse a una sala")
        print("  0) Volver al juego principal")
        option = input("\nElige una opción: ").strip()
        if option == "1":
            create_room(bank)
        elif option == "2":
            join_room(bank)
        elif option == "0":
            return 0
        else:
            print("Opción no válida.")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nModo multijugador cerrado.")
        raise SystemExit(130)
