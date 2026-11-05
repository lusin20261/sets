#!/usr/bin/env python3
"""Modo multijugador LAN para Quiz Escolar.

Uso interno: python3 charada_lan.py /ruta/al/charada.sh
El servidor escucha en todas las interfaces IPv4, puerto 50555 por defecto.
"""

from __future__ import annotations

import json
import os
import random
import re
import socket
import socketserver
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PORT = int(os.environ.get("QUIZ_LAN_PORT", "50555"))
COUNTDOWN_SECONDS = 60
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


def local_ipv4_addresses() -> list[str]:
    addresses: set[str] = set()
    try:
        for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = item[4][0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("192.0.2.1", 9))
            address = probe.getsockname()[0]
            if not address.startswith("127."):
                addresses.add(address)
        finally:
            probe.close()
    except OSError:
        pass
    return sorted(addresses)


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
        started = False
        while not started:
            message = receive_json(reader)
            if not message:
                print("\nSe perdió la conexión con la sala.")
                return
            kind = message.get("type")
            if kind == "countdown":
                remaining = int(message.get("remaining", 0))
                names = message.get("players", [])
                names_text = ", ".join(names) if names else "Esperando jugadores"
                line = f"\r  Empieza en {remaining:02d} s  |  Jugadores ({len(names)}): {names_text}"
                print(line[:180].ljust(180), end="", flush=True)
            elif kind == "start":
                started = True
            elif kind == "error":
                print(f"\n{message.get('message', 'Error de sala.')}")
                return
        print("\n\n¡Comienza la partida! Son 20 preguntas. Cada acierto vale 1 punto.\n")

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
    addresses = local_ipv4_addresses()
    if addresses:
        print("Comparte una de estas direcciones con los demás jugadores:")
        for address in addresses:
            print(f"  IP: {address}   Puerto: {PORT}")
    else:
        print(f"No pude detectar la IP automáticamente. Puerto: {PORT}")
        print("En Linux puedes consultarla con: hostname -I")
    print(f"Contraseña de la sala: {password}")
    print("El contador de 60 segundos ya está en marcha.\n")

    try:
        play_as_client("127.0.0.1", password, name)
    finally:
        server.shutdown()
        server.server_close()


def join_room(bank: list[dict[str, str]]) -> None:
    del bank  # El banco lo administra el servidor para que todos reciban las mismas preguntas.
    print("\n══ UNIRSE A UNA SALA LAN ══")
    host = input("IP del equipo que creó la sala: ").strip()
    if not host:
        print("Debes escribir la IP del equipo anfitrión.")
        return
    password = ask_password(create=False)
    name = ask_name()
    play_as_client(host, password, name)


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
