#!/usr/bin/env bash
# ============================================================
#  Chat de Alumnos — chat por LAN desde la terminal
#  Requiere: socat (sudo apt install socat)
# ============================================================

set -u

PORT=45555
MAX_TITLE=25
MAX_MSG=255

command -v socat >/dev/null 2>&1 || {
  echo "Falta 'socat'. Instálalo con:  sudo apt install socat"
  exit 1
}

# IP local (interfaz por defecto) — para unirse al grupo multicast
LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
[ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$LOCAL_IP" ] && LOCAL_IP="0.0.0.0"

# ---------------- Menú ----------------
clear
cat <<'BANNER'
========================================
            CHAT DE ALUMNOS
========================================
BANNER
echo
echo "  1) Crear sala"
echo "  2) Unirse a sala"
echo
read -rp "  Opción [1/2]: " opt

NAME=""; ROOM=""; TITLE=""

case "$opt" in
  1)
    read -rp "  Título de la sala (máx $MAX_TITLE): " TITLE
    TITLE="${TITLE:0:$MAX_TITLE}"
    [ -z "$TITLE" ] && TITLE="Sala sin título"
    read -rp "  Tu nombre: " NAME
    ROOM=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n' | tr 'a-f' 'A-F')
    echo
    echo "  >>> Código de sala: $ROOM <<<"
    echo "  Compártelo con tus compañeros."
    read -rp "  Pulsa Enter para entrar al chat... " _
    ;;
  2)
    read -rp "  Código de sala: " ROOM
    read -rp "  Tu nombre: " NAME
    TITLE="Sala $ROOM"
    ;;
  *)
    echo "Opción inválida."; exit 1 ;;
esac

NAME="${NAME:-Anónimo}"
ROOM="${ROOM:-000000}"
ROOM="${ROOM^^}"
ROOM="${ROOM// /}"

# ---------------- Dirección multicast derivada del código ----------------
HASH=$(printf "%s" "$ROOM" | md5sum | cut -c1-6)
MCAST="239.$((16#${HASH:0:2})).$((16#${HASH:2:2})).$((16#${HASH:4:2}))"

# ---------------- Colores ----------------
R=$'\033[0m'; CY=$'\033[36m'; YE=$'\033[33m'; GR=$'\033[32m'; MG=$'\033[35m'; DM=$'\033[2m'

# ---------------- Cabecera de la sala ----------------
clear
printf '%s\n' "============================================================"
printf '  %sSala:%s %s\n'                    "$DM" "$R" "$TITLE"
printf '  %sCódigo:%s %s   %sTú:%s %s\n'     "$DM" "$R" "$ROOM" "$DM" "$R" "$NAME"
printf '%s\n' "============================================================"
printf '%sEscribe y pulsa Enter. Cierra la terminal (Ctrl+C) para salir.%s\n\n' "$DM" "$R"

# ---------------- Receptor (FIFO + socat) ----------------
FIFO="/tmp/chat_alumnos_$$.fifo"
mkfifo "$FIFO"

# Bucle que imprime lo que llega, con formato WhatsApp
(
  while IFS= read -r msg; do
    case "$msg" in
      "::JOIN::"*)
        printf '\r\033[K%s* %s se ha unido a la sala *%s\n' "$GR" "${msg#::JOIN::}" "$R"
        ;;
      "::LEAVE::"*)
        printf '\r\033[K%s* %s ha salido de la sala *%s\n' "$MG" "${msg#::LEAVE::}" "$R"
        ;;
      *)
        if [[ "$msg" == "$NAME: "* ]]; then
          printf '\r\033[K%s%s%s\n' "$CY" "$msg" "$R"   # los míos, cian
        else
          printf '\r\033[K%s%s%s\n' "$YE" "$msg" "$R"   # los demás, amarillo
        fi
        ;;
    esac
  done
) < "$FIFO" &
DISPLAY_PID=$!

# Un solo socat haciendo de "socket" del grupo multicast
socat -u UDP4-RECV:${PORT},reuseaddr,ip-add-membership=${MCAST}:${LOCAL_IP} - > "$FIFO" &
SOCAT_PID=$!

# ---------------- Limpieza ----------------
DONE=0
cleanup() {
  [ "$DONE" = 1 ] && return
  DONE=1
  printf '\n%sSaliendo del chat...%s\n' "$DM" "$R"
  printf '::LEAVE::%s\n' "$NAME" | \
    socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-if=${LOCAL_IP},ip-multicast-loop=0 2>/dev/null
  kill "$SOCAT_PID" "$DISPLAY_PID" 2>/dev/null
  rm -f "$FIFO"
  exit 0
}
trap cleanup EXIT INT TERM

# ---------------- Aviso de ingreso ----------------
printf '::JOIN::%s\n' "$NAME" | \
  socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-if=${LOCAL_IP},ip-multicast-loop=0

# ---------------- Bucle principal: siempre en modo escritura ----------------
while true; do
  if IFS= read -r -p "> " line; then
    [ -z "$line" ] && continue
    line="${line:0:$MAX_MSG}"
    # Reemplaza la línea cruda por el formato definitivo
    printf '\033[1A\r\033[K%s%s: %s%s\n' "$CY" "$NAME" "$line" "$R"
    # Difunde a todos los del grupo
    printf '%s: %s\n' "$NAME" "$line" | \
      socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-if=${LOCAL_IP},ip-multicast-loop=0
  fi
done