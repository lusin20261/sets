#!/usr/bin/env bash
# ============================================================
#  Chat de Alumnos — chat por LAN desde la terminal
#  Requiere: socat  (sudo apt install socat)
# ============================================================

set -u

PORT=45555
MAX_TITLE=25
MAX_MSG=255

command -v socat >/dev/null 2>&1 || {
  echo "Falta 'socat'. Instálalo con:  sudo apt install socat"; exit 1
}

# ---------- Banco de palabras para el código de sala ----------
ANIMALS=(
  conejo abeja tigre leon leona zorro panda pulpo buho lobo loba
  gato gata perro perra pato pata rana sapo oso osa jirafa mono
  mona caballo yegua vaca toro cerdo oveja cabra gallina gallo
  pollo raton rata ardilla murcielago delfin ballena tiburon
  tortuga serpiente lagarto cocodrilo aguila halcon buitre
  pinguino koala puma lince nutria foca morsa hormiga mariposa
  libelula grillo saltamontes escarabajo cangrejo langosta
)
VEGGIES=(
  zapallo zanahoria papa tomate cebolla lechuga brocoli pepino
  maiz arveja frijol lenteja garbanzo ajo aji pimiento berenjena
  calabaza remolacha rabano espinaca acelga apio perejil cilantro
  coliflor repollo col kale alcachofa esparrago champinon
  yuca camote batata platano banano mango pina papaya guayaba
  granada higo uva pera manzana naranja limon mandarina durazno
)
ALL_WORDS=("${ANIMALS[@]}" "${VEGGIES[@]}")

# ---------- Banco de palabras ofensivas (básico, ampliable) ----------
BAD_WORDS=(
  puta puto putita putito mierda pendejo pendeja cabron cabrona
  verga joder jodete chinga chingada chingado coño marica maricon
  joto culero imbecil idiota estupido estupida tarado tarada
  gilipollas hijueputa hijueperra malparido carechimba gonorrea
  zorra perra ramera prostituta culo ano pito polla pija pinga
  culiar follar mamar concha chupar mamahuevo mamaguevo verguero
  malnacido pirobo careculo carepicha
)

pick_word() {
  local n=${#ALL_WORDS[@]}
  echo "${ALL_WORDS[$((RANDOM % n))]}"
}

contains_bad_word() {
  local msg="${1,,}"
  msg=$(printf '%s' "$msg" | tr -s '[:punct:]' ' ')
  local w bad
  for w in $msg; do
    for bad in "${BAD_WORDS[@]}"; do
      [ "$w" = "$bad" ] && return 0
    done
  done
  return 1
}

# ---------- IP local para unirse al grupo multicast ----------
LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
[ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$LOCAL_IP" ] && LOCAL_IP="127.0.0.1"

# ---------- Menú ----------
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
    ROOM=$(pick_word)
    echo
    echo "  >>> Tu código de sala es: $ROOM <<<"
    echo "  Compártelo con tus compañeros."
    read -rp "  Pulsa Enter para entrar al chat... " _
    ;;
  2)
    read -rp "  Código de sala (palabra): " ROOM
    ROOM="${ROOM,,}"; ROOM="${ROOM// /}"
    read -rp "  Tu nombre: " NAME
    TITLE="Sala $ROOM"
    ;;
  *) echo "Opción inválida."; exit 1 ;;
esac

NAME="${NAME:-Anónimo}"
[ -z "$ROOM" ] && { echo "Código vacío."; exit 1; }

# ---------- Dirección multicast derivada de la palabra ----------
HASH=$(printf "%s" "$ROOM" | md5sum | cut -c1-6)
MCAST="239.$((16#${HASH:0:2})).$((16#${HASH:2:2})).$((16#${HASH:4:2}))"

# ---------- Colores ----------
R=$'\033[0m' CY=$'\033[36m' YE=$'\033[33m' GR=$'\033[32m'
MG=$'\033[35m' DM=$'\033[2m' RD=$'\033[1;31m' BD=$'\033[1m'

# ---------- Preparar terminal y limpieza ----------
TERM_LINES=$(tput lines 2>/dev/null || echo 24)
SCROLL_TOP=5
FIFO="/tmp/chat_alumnos_$$.fifo"
mkfifo "$FIFO"

DONE=0
cleanup() {
  [ "$DONE" = 1 ] && return
  DONE=1
  printf '\033[r'
  printf '\033[%d;1H\033[?25h' "$TERM_LINES"
  printf '\n%sSaliendo del chat...%s\n' "$DM" "$R"
  printf '::LEAVE::%s\n' "$NAME" | \
    socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-loop=0 2>/dev/null
  kill "${SOCAT_PID:-}" "${DISPLAY_PID:-}" 2>/dev/null
  rm -f "$FIFO"
  exit 0
}
trap cleanup EXIT INT TERM

# ---------- Dibujar cabecera fija (líneas 1..4) ----------
clear
printf '\033[1;1H'
printf '%s════════════════════════════════════════════════════════════%s\n' "$CY" "$R"
printf '  %sSala:%s %s%s%s\n'   "$DM" "$R" "$BD" "$TITLE" "$R"
printf '  %sCódigo:%s %s%s%s    %sTú:%s %s\n' "$DM" "$R" "$GR" "$ROOM" "$R" "$DM" "$R" "$NAME"
printf '%s════════════════════════════════════════════════════════════%s\n' "$CY" "$R"

# Región de scroll: de SCROLL_TOP hasta la última línea (la cabecera queda FUERA)
printf '\033[%d;%dr' "$SCROLL_TOP" "$TERM_LINES"
printf '\033[%d;1H' "$SCROLL_TOP"
printf '%sEscribe y pulsa Enter. Cierra la terminal para salir.%s\n' "$DM" "$R"

# ---------- Receptor (FIFO + socat) ----------
(
  while IFS= read -r msg; do
    case "$msg" in
      "::JOIN::"*)
        printf '\r\033[K%s* %s se ha unido a la sala *%s\n> ' "$GR" "${msg#::JOIN::}" "$R" ;;
      "::LEAVE::"*)
        printf '\r\033[K%s* %s ha salido de la sala *%s\n> ' "$MG" "${msg#::LEAVE::}" "$R" ;;
      *)
        if [[ "$msg" == "$NAME: "* ]]; then
          printf '\r\033[K%s%s%s\n> ' "$CY" "$msg" "$R"    # los míos, cian
        else
          printf '\r\033[K%s%s%s\n> ' "$YE" "$msg" "$R"    # los demás, amarillo
        fi ;;
    esac
  done
) < "$FIFO" &
DISPLAY_PID=$!

socat -u UDP4-RECV:${PORT},reuseaddr,ip-add-membership=${MCAST}:${LOCAL_IP} - > "$FIFO" &
SOCAT_PID=$!

# ---------- Aviso de ingreso ----------
printf '::JOIN::%s\n' "$NAME" | \
  socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-loop=0

# ---------- Bucle principal ----------
printf '> '
while true; do
  if IFS= read -r line; then
    line="${line:0:$MAX_MSG}"
    printf '\r\033[K'                   # limpia la línea "> texto"
    if [ -z "$line" ]; then
      printf '> '
      continue
    fi
    if contains_bad_word "$line"; then
      printf '%s⚠  Mensaje bloqueado: contiene lenguaje ofensivo.%s\n> ' "$RD" "$R"
      continue
    fi
    # Muestra formateado al emisor (WhatsApp-style)
    printf '%s%s: %s%s\n> ' "$CY" "$NAME" "$line" "$R"
    # Difunde a todos los del grupo (loop=0 evita que te rebote)
    printf '%s: %s\n' "$NAME" "$line" | \
      socat -u - UDP4-DATAGRAM:${MCAST}:${PORT},ip-multicast-loop=0
  fi
done
