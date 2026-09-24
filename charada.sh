#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
#  QUIZ ESCOLAR  —  Cultura general · Matemática · Inglés · Chino básico
# ══════════════════════════════════════════════════════════════════════════
#  Uso:        chmod +x quiz_escolar.sh && ./quiz_escolar.sh
#  Opciones:   --reset   borra la tabla de puntajes (pide confirmación)
#              --help    muestra esta ayuda
#  Variables:  QUIZ_SCORES=/ruta/puntajes.txt   dónde se guardan los puntajes
#              NO_COLOR=1                       desactiva los colores
#  Requiere:   bash 4+, coreutils (shuf) y una terminal en UTF-8.
#              Para ver bien los caracteres chinos:  sudo apt install fonts-noto-cjk
#
#  AGREGAR PREGUNTAS: añade una línea en el BANCO (al final de este archivo):
#      MATERIA|Pregunta|Respuesta correcta|Incorrecta 1|Incorrecta 2|Incorrecta 3
#  MATERIA = CG (cultura general) · MA (matemática) · EN (inglés) · ZH (chino)
#  No uses el símbolo | dentro del texto. Las alternativas se barajan solas,
#  así que la respuesta correcta siempre se escribe primero en el banco.
# ══════════════════════════════════════════════════════════════════════════

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Este juego necesita bash 4 o superior." >&2
  exit 1
fi

SCORE_FILE="${QUIZ_SCORES:-${XDG_DATA_HOME:-$HOME/.local/share}/quiz-escolar/puntajes.txt}"

# ─── 1. Colores ───────────────────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RST=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[91m'; GRN=$'\033[92m'; YEL=$'\033[93m'
  BLU=$'\033[94m'; MAG=$'\033[95m'; CYN=$'\033[96m'; WHT=$'\033[97m'
else
  RST=""; BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; MAG=""; CYN=""; WHT=""
fi

declare -A CAT_NOMBRE=( [TODAS]="Todas las materias" [CG]="Cultura general"
                        [MA]="Matemática" [EN]="Inglés" [ZH]="Chino básico" )
declare -A CAT_COLOR=(  [TODAS]="$GRN" [CG]="$CYN" [MA]="$YEL" [EN]="$MAG" [ZH]="$RED" )

LETRAS=(a b c d)
FRASES_OK=("¡Excelente!" "¡Muy bien!" "¡Genial!" "¡Correcto!" "¡Bien hecho!" "¡Eres un crack!" "¡Así se hace!")
FRASES_MAL=("¡Ups!" "¡Casi!" "No te rindas." "Sigue intentando." "¡La próxima será!" "Aprendiendo se llega lejos.")

# ─── 2. Utilidades de pantalla ────────────────────────────────────────────
limpiar() { [[ -t 1 ]] && printf '\033[H\033[2J'; }

salir() {
  printf '\n\n  %s¡Hasta pronto! Gracias por jugar.%s\n\n' "$CYN" "$RST"
  exit 0
}
trap salir INT TERM

pausa_enter() {
  printf '\n  %sPresiona ENTER para continuar...%s' "$DIM" "$RST"
  IFS= read -r _ || salir
}

banner() {
  limpiar
  printf '\n'
  printf '  %s╔═══════════════════════════════════════════════╗%s\n' "$CYN" "$RST"
  printf '  %s║                                               ║%s\n' "$CYN" "$RST"
  printf '  %s║%s%s      ★   Q U I Z   E S C O L A R   ★          %s%s║%s\n' "$CYN" "$RST" "$YEL$BOLD" "$RST" "$CYN" "$RST"
  printf '  %s║                                               ║%s\n' "$CYN" "$RST"
  printf '  %s║%s  Cultura general · Mate · Inglés · Chino      %s║%s\n' "$CYN" "$RST" "$CYN" "$RST"
  printf '  %s║%s  by Profe Luis :3                             %s║%s\n' "$CYN" "$RST" "$CYN" "$RST"
  printf '  %s╚═══════════════════════════════════════════════╝%s\n\n' "$CYN" "$RST"
}

# Barra de progreso: barra <actual> <total>
barra() {
  local act=$1 tot=$2 ancho=20 llenos i out=""
  (( tot < 1 )) && tot=1
  llenos=$(( act * ancho / tot ))
  for (( i = 0; i < ancho; i++ )); do
    if (( i < llenos )); then out+="█"; else out+="░"; fi
  done
  printf '%s' "$out"
}

# ─── 3. Entrada del jugador ───────────────────────────────────────────────
# Deja en RESP la letra elegida (a/b/c/d) o "s" si quiere terminar.
leer_respuesta() {
  local r
  while true; do
    printf '\n  %sTu respuesta%s (a, b, c o d)  %s[s = terminar]%s : ' "$BOLD" "$RST" "$DIM" "$RST"
    IFS= read -r r || salir
    r="${r,,}"; r="${r//[[:space:]]/}"
    case "$r" in
      a|b|c|d) RESP="$r"; return ;;
      s)
        printf '  %s¿Terminar la partida? (s = sí, otra tecla = no)%s : ' "$YEL" "$RST"
        IFS= read -r r || salir
        r="${r,,}"; r="${r//[[:space:]]/}"
        if [[ "$r" == "s" || "$r" == "si" || "$r" == "sí" ]]; then RESP="s"; return; fi
        ;;
      *) printf '  %sEscribe solo la letra a, b, c o d.%s\n' "$YEL" "$RST" ;;
    esac
  done
}

# ─── 4. Puntajes ──────────────────────────────────────────────────────────
# Formato del archivo:  fecha|nombre|puntos|aciertos|total|materia
guardar_puntaje() {
  mkdir -p "$(dirname "$SCORE_FILE")" 2>/dev/null || return 1
  printf '%s|%s|%s|%s|%s|%s\n' "$(date +%F)" "$1" "$2" "$3" "$4" "$5" 2>/dev/null >> "$SCORE_FILE"
}

mostrar_puntajes() {
  local pos=0 fecha nombre pts ac tot mat col
  limpiar
  printf '\n  %s%s══════════  TABLA DE PUNTAJES  ·  Top 10  ══════════%s\n\n' "$YEL" "$BOLD" "$RST"
  if [[ ! -s "$SCORE_FILE" ]]; then
    printf '  Aún no hay puntajes guardados. ¡Sé el primero en jugar!\n'
    return
  fi
  printf '  %s%-4s %-20s %7s  %9s   %s%s\n' "$DIM" "#" "Nombre" "Puntos" "Aciertos" "Materia" "$RST"
  printf '  %s%s%s\n' "$DIM" "──────────────────────────────────────────────────────────────" "$RST"
  while IFS='|' read -r fecha nombre pts ac tot mat; do
    (( pos++ ))
    case $pos in
      1) col="$YEL$BOLD" ;;
      2) col="$WHT$BOLD" ;;
      3) col="$MAG$BOLD" ;;
      *) col="$RST" ;;
    esac
    printf '  %s%-4s %-20s %7s  %5s/%-3s   %s%s\n' "$col" "$pos" "$nombre" "$pts" "$ac" "$tot" "$mat" "$RST"
  done < <(sort -t'|' -k3,3nr -k1,1r "$SCORE_FILE" | head -n 10)
}

# ─── 5. Fin de la partida ─────────────────────────────────────────────────
# fin_juego <cat> <puntos> <aciertos> <respondidas> <mejor_racha>
fin_juego() {
  local cat="$1" puntos="$2" aciertos="$3" total="$4" mejor="$5"
  local pct titulo tcol nombre puesto

  limpiar
  if (( total == 0 )); then
    printf '\n  %sNo respondiste ninguna pregunta esta vez. ¡Vuelve pronto!%s\n' "$YEL" "$RST"
    pausa_enter
    return
  fi

  pct=$(( aciertos * 100 / total ))
  if   (( pct == 100 )); then titulo="★ ¡PERFECTO! Eres un genio ★"; tcol="$YEL"
  elif (( pct >= 80 ));  then titulo="¡Excelente trabajo!";           tcol="$GRN"
  elif (( pct >= 60 ));  then titulo="¡Muy bien!";                    tcol="$CYN"
  elif (( pct >= 40 ));  then titulo="Nada mal, ¡sigue practicando!"; tcol="$MAG"
  else                        titulo="¡Ánimo! La práctica hace al maestro."; tcol="$RED"
  fi

  printf '\n  %s%s══════════  FIN DE LA PARTIDA  ══════════%s\n\n' "$BOLD" "$CYN" "$RST"
  printf '  %s%s%s\n\n' "$tcol$BOLD" "$titulo" "$RST"
  printf '  Materia ........ %s%s%s\n' "${CAT_COLOR[$cat]}" "${CAT_NOMBRE[$cat]}" "$RST"
  printf '  Aciertos ....... %s%d de %d%s  (%d%%)\n' "$GRN" "$aciertos" "$total" "$RST" "$pct"
  printf '  Mejor racha .... %s%d%s\n' "$YEL" "$mejor" "$RST"
  printf '  %sPUNTAJE ....... %d puntos%s\n\n' "$BOLD$YEL" "$puntos" "$RST"

  printf '  %s¿Cómo te llamas?%s (para la tabla de puntajes) : ' "$BOLD$CYN" "$RST"
  IFS= read -r nombre || salir
  nombre="${nombre//[[:cntrl:]]/}"
  nombre="${nombre//|/}"
  nombre="${nombre#"${nombre%%[![:space:]]*}"}"
  nombre="${nombre%"${nombre##*[![:space:]]}"}"
  nombre="${nombre:0:20}"
  [[ -z "$nombre" ]] && nombre="Anónimo"

  if guardar_puntaje "$nombre" "$puntos" "$aciertos" "$total" "${CAT_NOMBRE[$cat]}"; then
    puesto=$(awk -F'|' -v p="$puntos" '$3 + 0 > p + 0 { c++ } END { print c + 1 }' "$SCORE_FILE")
    printf '\n  %s¡Listo, %s! Tu puntaje quedó guardado.%s\n' "$GRN" "$nombre" "$RST"
    printf '  %sPuesto en la tabla: #%s%s\n' "$YEL$BOLD" "$puesto" "$RST"
  else
    printf '\n  %sNo se pudo guardar el puntaje (revisa permisos de: %s).%s\n' "$RED" "$SCORE_FILE" "$RST"
  fi
  pausa_enter
  mostrar_puntajes
  pausa_enter
}

# ─── 6. El juego ──────────────────────────────────────────────────────────
# jugar <cat|TODAS> <cantidad>
jugar() {
  local cat="$1" n="$2"
  local -a elig=() sel=() op=()
  local i k qcat texto ok m1 m2 m3 correcta color
  local total puntos=0 aciertos=0 racha=0 mejor=0 resp=0 num=0 bonus ganado

  for i in "${!BANCO[@]}"; do
    if [[ "$cat" == "TODAS" || "${BANCO[$i]%%|*}" == "$cat" ]]; then elig+=("$i"); fi
  done
  (( n > ${#elig[@]} )) && n=${#elig[@]}
  mapfile -t sel < <(printf '%s\n' "${elig[@]}" | shuf -n "$n")
  total=${#sel[@]}

  for i in "${sel[@]}"; do
    (( num++ ))
    IFS='|' read -r qcat texto ok m1 m2 m3 <<< "${BANCO[$i]}"
    mapfile -t op < <(shuf -e -- "$ok" "$m1" "$m2" "$m3")
    correcta=""
    for k in 0 1 2 3; do
      if [[ -z "$correcta" && "${op[$k]}" == "$ok" ]]; then correcta="${LETRAS[$k]}"; fi
    done
    color="${CAT_COLOR[$qcat]:-$WHT}"

    limpiar
    printf '\n  %sPregunta %d de %d%s   %s%s%s\n' "$BOLD" "$num" "$total" "$RST" "$GRN" "$(barra "$((num - 1))" "$total")" "$RST"
    printf '  %sMateria:%s %s%s%s     %sPuntos:%s %s%d%s   %sRacha:%s %s%d%s\n' \
      "$DIM" "$RST" "$color$BOLD" "${CAT_NOMBRE[$qcat]:-?}" "$RST" \
      "$DIM" "$RST" "$YEL$BOLD" "$puntos" "$RST" \
      "$DIM" "$RST" "$MAG$BOLD" "$racha" "$RST"
    printf '  %s%s%s\n\n' "$DIM" "──────────────────────────────────────────────────────" "$RST"
    printf '  %s%s%s\n\n' "$BOLD$WHT" "$texto" "$RST"
    for k in 0 1 2 3; do
      printf '     %s%s)%s  %s\n' "$BLU$BOLD" "${LETRAS[$k]}" "$RST" "${op[$k]}"
    done

    leer_respuesta
    if [[ "$RESP" == "s" ]]; then (( num-- )); break; fi
    (( resp++ ))

    if [[ "$RESP" == "$correcta" ]]; then
      (( aciertos++, racha++ ))
      (( racha > mejor )) && mejor=$racha
      bonus=0
      (( racha >= 3 )) && bonus=$(( (racha - 2) * 2 ))
      (( bonus > 10 )) && bonus=10
      ganado=$(( 10 + bonus ))
      (( puntos += ganado ))
      printf '\n  %s✔ %s%s  %s+%d puntos%s' "$GRN$BOLD" "${FRASES_OK[RANDOM % ${#FRASES_OK[@]}]}" "$RST" "$YEL" "$ganado" "$RST"
      (( bonus > 0 )) && printf '  %s(racha de %d: +%d de bonus)%s' "$MAG" "$racha" "$bonus" "$RST"
      printf '\n'
      sleep 0.9
    else
      racha=0
      printf '\n  %s✘ %s%s  La respuesta correcta era: %s%s) %s%s\n' \
        "$RED$BOLD" "${FRASES_MAL[RANDOM % ${#FRASES_MAL[@]}]}" "$RST" \
        "$GRN$BOLD" "$correcta" "$ok" "$RST"
      pausa_enter
    fi
  done

  fin_juego "$cat" "$puntos" "$aciertos" "$resp" "$mejor"
}

# ─── 7. Menús ─────────────────────────────────────────────────────────────
elegir_cantidad() {
  local cat="$1" op n
  while true; do
    banner
    printf '  %sMateria:%s %s%s%s\n\n' "$BOLD" "$RST" "${CAT_COLOR[$cat]}$BOLD" "${CAT_NOMBRE[$cat]}" "$RST"
    printf '  ¿Cuántas preguntas quieres?\n\n'
    printf '     %s1)%s  10 preguntas  %s(rápido, opción por defecto)%s\n' "$BLU$BOLD" "$RST" "$DIM" "$RST"
    printf '     %s2)%s  20 preguntas\n' "$BLU$BOLD" "$RST"
    printf '     %s3)%s  30 preguntas\n' "$BLU$BOLD" "$RST"
    printf '     %s4)%s  50 preguntas  %s(maratón)%s\n' "$BLU$BOLD" "$RST" "$DIM" "$RST"
    printf '     %s0)%s  Volver\n\n' "$BLU$BOLD" "$RST"
    printf '  Elige una opción : '
    IFS= read -r op || salir
    case "${op//[[:space:]]/}" in
      ""|1) n=10 ;;
      2) n=20 ;;
      3) n=30 ;;
      4) n=50 ;;
      0) return ;;
      *) continue ;;
    esac
    jugar "$cat" "$n"
    return
  done
}

menu_materias() {
  local op
  while true; do
    banner
    printf '  %sElige una materia:%s\n\n' "$BOLD" "$RST"
    printf '     %s1)%s  %s%-16s%s %s(%d preguntas)%s\n' "$BLU$BOLD" "$RST" "${CAT_COLOR[CG]}" "${CAT_NOMBRE[CG]}" "$RST" "$DIM" "${CUENTA[CG]:-0}" "$RST"
    printf '     %s2)%s  %s%-16s%s %s(%d preguntas)%s\n' "$BLU$BOLD" "$RST" "${CAT_COLOR[MA]}" "${CAT_NOMBRE[MA]}" "$RST" "$DIM" "${CUENTA[MA]:-0}" "$RST"
    printf '     %s3)%s  %s%-16s%s %s(%d preguntas)%s\n' "$BLU$BOLD" "$RST" "${CAT_COLOR[EN]}" "${CAT_NOMBRE[EN]}" "$RST" "$DIM" "${CUENTA[EN]:-0}" "$RST"
    printf '     %s4)%s  %s%-16s%s %s(%d preguntas)%s\n' "$BLU$BOLD" "$RST" "${CAT_COLOR[ZH]}" "${CAT_NOMBRE[ZH]}" "$RST" "$DIM" "${CUENTA[ZH]:-0}" "$RST"
    printf '     %s0)%s  Volver\n\n' "$BLU$BOLD" "$RST"
    printf '  Elige una opción : '
    IFS= read -r op || salir
    case "${op//[[:space:]]/}" in
      1) elegir_cantidad CG; return ;;
      2) elegir_cantidad MA; return ;;
      3) elegir_cantidad EN; return ;;
      4) elegir_cantidad ZH; return ;;
      0) return ;;
    esac
  done
}

instrucciones() {
  banner
  printf '  %s¿CÓMO SE JUEGA?%s\n\n' "$BOLD$YEL" "$RST"
  printf '   • Te haremos preguntas de %sCultura general%s, %sMatemática%s,\n' "$CYN" "$RST" "$YEL" "$RST"
  printf '     %sInglés%s y %sChino básico%s.\n' "$MAG" "$RST" "$RED" "$RST"
  printf '   • Responde escribiendo la letra %sa%s, %sb%s, %sc%s o %sd%s y presiona ENTER.\n' \
    "$BLU$BOLD" "$RST" "$BLU$BOLD" "$RST" "$BLU$BOLD" "$RST" "$BLU$BOLD" "$RST"
  printf '   • Cada acierto suma %s10 puntos%s.\n' "$YEL$BOLD" "$RST"
  printf '   • %s¡Racha!%s Con 3 o más aciertos seguidos ganas puntos extra\n' "$MAG$BOLD" "$RST"
  printf '     (+2, +4, +6... hasta +10 por pregunta).\n'
  printf '   • Si fallas, la racha vuelve a cero, pero verás la respuesta correcta.\n'
  printf '   • Escribe %ss%s en cualquier momento para terminar la partida.\n' "$BLU$BOLD" "$RST"
  printf '   • Al final escribe tu %snombre%s y entrarás a la tabla de puntajes.\n' "$CYN$BOLD" "$RST"
  pausa_enter
}

menu_principal() {
  local op
  while true; do
    banner
    printf '     %s1)%s  %sJugar%s  %s(todas las materias mezcladas)%s\n' "$BLU$BOLD" "$RST" "$GRN$BOLD" "$RST" "$DIM" "$RST"
    printf '     %s2)%s  Elegir una materia\n' "$BLU$BOLD" "$RST"
    printf '     %s3)%s  Tabla de puntajes\n' "$BLU$BOLD" "$RST"
    printf '     %s4)%s  Instrucciones\n' "$BLU$BOLD" "$RST"
    printf '     %s5)%s  Salir\n\n' "$BLU$BOLD" "$RST"
    printf '  Elige una opción : '
    IFS= read -r op || salir
    case "${op//[[:space:]]/}" in
      1) elegir_cantidad TODAS ;;
      2) menu_materias ;;
      3) mostrar_puntajes; pausa_enter ;;
      4) instrucciones ;;
      5|s|S|q|Q) salir ;;
    esac
  done
}

ayuda() {
  cat <<EOF
Quiz Escolar — juego de preguntas para la terminal

Uso: $(basename "$0") [opción]
  --reset   borra la tabla de puntajes
  --help    muestra esta ayuda

Variables:
  QUIZ_SCORES=/ruta/puntajes.txt   archivo de puntajes
                                   (por defecto: $SCORE_FILE)
  NO_COLOR=1                       desactiva los colores
EOF
}

# ─── 8. Banco de preguntas ────────────────────────────────────────────────
# Formato:  MATERIA|Pregunta|Correcta|Incorrecta 1|Incorrecta 2|Incorrecta 3
# (las líneas vacías o que empiezan con # se ignoran)
mapfile -t BANCO_CRUDO <<'FIN_BANCO'
# ── CULTURA GENERAL ──────────────────────────────────────────────────────
CG|¿Cuál es el planeta más grande del Sistema Solar?|Júpiter|Saturno|Neptuno|Marte
CG|¿Cuántos planetas tiene el Sistema Solar?|8|9|7|10
CG|¿Qué planeta es conocido como el "planeta rojo"?|Marte|Venus|Mercurio|Júpiter
CG|¿Cuál es la estrella más cercana a la Tierra?|El Sol|Alfa Centauri|Sirio|La Estrella Polar
CG|¿Cómo se llama el satélite natural de la Tierra?|La Luna|Fobos|Titán|Europa
CG|¿En qué año llegó el ser humano a la Luna por primera vez?|1969|1959|1979|1985
CG|¿Cómo se llama la capa de gases que rodea la Tierra?|Atmósfera|Litosfera|Hidrosfera|Biosfera
CG|¿Cuál es el océano más grande del mundo?|Océano Pacífico|Océano Atlántico|Océano Índico|Océano Ártico
CG|¿Cuál es el río más caudaloso del mundo?|Amazonas|Nilo|Misisipi|Yangtsé
CG|¿Cuál es la montaña más alta del mundo?|Monte Everest|K2|Aconcagua|Kilimanjaro
CG|¿Cuál es el desierto cálido más grande del mundo?|Sahara|Gobi|Atacama|Kalahari
CG|¿Qué cordillera atraviesa Sudamérica de norte a sur?|Los Andes|Los Alpes|El Himalaya|Las Rocosas
CG|¿En qué continente está Egipto?|África|Asia|Europa|Oceanía
CG|¿Cuál es el continente más pequeño?|Oceanía|Europa|Antártida|África
CG|¿Cuál es la capital de Australia?|Canberra|Sídney|Melbourne|Perth
CG|¿Cuál es la capital de Japón?|Tokio|Kioto|Osaka|Seúl
CG|¿Cuál es la capital de Brasil?|Brasilia|Río de Janeiro|São Paulo|Salvador
CG|¿Qué país tiene forma de bota?|Italia|España|Grecia|Portugal
CG|¿Cuál es el país más grande del mundo por superficie?|Rusia|China|Canadá|Estados Unidos
CG|¿Cuál es el país con más habitantes del mundo?|India|China|Estados Unidos|Indonesia
CG|¿Cuál es el país más pequeño del mundo?|Ciudad del Vaticano|Mónaco|Malta|Liechtenstein
CG|¿Qué idioma tiene más hablantes nativos en el mundo?|Chino mandarín|Inglés|Español|Hindi
CG|¿Cuál es el animal terrestre más rápido?|El guepardo|El león|El caballo|El leopardo
CG|¿Cuál es el mamífero más grande del mundo?|La ballena azul|El elefante africano|El tiburón ballena|La jirafa
CG|¿Cuál es el ave más grande del mundo?|El avestruz|El cóndor andino|El águila real|El pingüino emperador
CG|¿Qué tipo de animal es la ballena?|Mamífero|Pez|Reptil|Anfibio
CG|¿Qué animal es símbolo de la paz?|La paloma|El águila|El búho|El cisne
CG|¿Qué gas absorben las plantas para hacer la fotosíntesis?|Dióxido de carbono|Oxígeno|Nitrógeno|Hidrógeno
CG|¿Cómo se llama el proceso por el que las plantas fabrican su alimento con la luz del Sol?|Fotosíntesis|Respiración|Digestión|Germinación
CG|¿Qué parte de la planta absorbe el agua del suelo?|La raíz|La hoja|La flor|El fruto
CG|¿Qué gas del aire necesitamos para respirar?|Oxígeno|Helio|Nitrógeno|Hidrógeno
CG|¿Cuántos huesos tiene aproximadamente el cuerpo de un adulto?|206|106|306|156
CG|¿Cuál es el hueso más largo del cuerpo humano?|El fémur|El húmero|La tibia|El radio
CG|¿Qué órgano bombea la sangre por todo el cuerpo?|El corazón|Los pulmones|El hígado|El estómago
CG|¿Cómo se llama el proceso por el que el agua pasa de líquido a gas?|Evaporación|Condensación|Solidificación|Fusión
CG|¿A qué temperatura hierve el agua a nivel del mar?|100 °C|50 °C|80 °C|120 °C
CG|¿Cuál es la fórmula química del agua?|H2O|CO2|O2|NaCl
CG|¿Cuál es el símbolo químico del oro?|Au|Ag|Fe|Or
CG|¿Qué metal es líquido a temperatura ambiente?|Mercurio|Hierro|Aluminio|Cobre
CG|¿Qué instrumento se usa para medir la temperatura?|Termómetro|Barómetro|Cronómetro|Brújula
CG|¿Qué tipo de energía se obtiene directamente de la luz del Sol?|Energía solar|Energía eólica|Energía hidráulica|Energía nuclear
CG|¿Cuál es el resultado de mezclar los colores azul y amarillo?|Verde|Naranja|Morado|Marrón
CG|¿Cuántos colores tiene el arcoíris?|7|5|6|8
CG|¿Cuántos días tiene un año bisiesto?|366|365|364|367
CG|¿Cuántos meses del año tienen 31 días?|7|6|8|5
CG|¿Quién pintó la Mona Lisa?|Leonardo da Vinci|Pablo Picasso|Vincent van Gogh|Miguel Ángel
CG|¿Quién pintó "La noche estrellada"?|Vincent van Gogh|Claude Monet|Pablo Picasso|Salvador Dalí
CG|¿Quién escribió "Don Quijote de la Mancha"?|Miguel de Cervantes|Gabriel García Márquez|Mario Vargas Llosa|Pablo Neruda
CG|¿Quién formuló la teoría de la relatividad?|Albert Einstein|Isaac Newton|Galileo Galilei|Charles Darwin
CG|¿A qué científico se asocia la leyenda de la manzana y la gravedad?|Isaac Newton|Albert Einstein|Thomas Edison|Nikola Tesla
CG|¿Quién inventó el teléfono?|Alexander Graham Bell|Thomas Edison|Nikola Tesla|Guglielmo Marconi
CG|¿Quién fue el primer presidente de Estados Unidos?|George Washington|Abraham Lincoln|Thomas Jefferson|John Adams
CG|¿En qué país se originaron los Juegos Olímpicos antiguos?|Grecia|Italia|Egipto|China
CG|¿Cuántos jugadores de un equipo están en la cancha en un partido de fútbol?|11|10|9|12
CG|¿Cuántos jugadores de un equipo están en la cancha en baloncesto?|5|6|7|11
CG|¿En qué deporte se puede anotar un jonrón?|Béisbol|Fútbol|Tenis|Baloncesto
CG|¿Qué instrumento musical tiene teclas blancas y negras?|El piano|La guitarra|El violín|La flauta
CG|¿Qué civilización construyó Machu Picchu?|Los incas|Los mayas|Los aztecas|Los romanos
CG|¿En qué año se declaró la independencia del Perú?|1821|1810|1824|1879
CG|¿Qué ciudad del Perú es conocida como "la Ciudad Blanca"?|Arequipa|Cusco|Trujillo|Piura
CG|¿Cómo se llama el lago navegable más alto del mundo, compartido por Perú y Bolivia?|Titicaca|Junín|Poopó|Nicaragua
CG|¿Qué héroe peruano comandó el monitor Huáscar?|Miguel Grau|Francisco Bolognesi|Andrés Avelino Cáceres|José de San Martín
CG|¿Cuál es el plato peruano hecho con pescado crudo, limón y ají?|Ceviche|Lomo saltado|Ají de gallina|Anticuchos
CG|¿Qué animal andino aparece en el escudo del Perú?|La vicuña|La llama|La alpaca|El guanaco
CG|¿Cómo se llama el sistema de numeración que usan las computadoras (solo 0 y 1)?|Sistema binario|Sistema decimal|Sistema romano|Sistema métrico
CG|¿Cómo se llama la parte física de una computadora, la que se puede tocar?|Hardware|Software|Internet|Navegador
CG|¿Cuál de estos es un sistema operativo?|Linux|Brave|Excel|Google
CG|¿Cómo se llama la mascota pingüino de Linux?|Tux|Pingu|Gnu|Puffy
CG|¿Qué dispositivo se usa para mover el cursor en la pantalla?|El mouse (ratón)|El monitor|El parlante|El micrófono

# ── MATEMÁTICA ───────────────────────────────────────────────────────────
MA|¿Cuánto es 15 × 12?|180|170|190|160
MA|¿Cuánto es 144 ÷ 12?|12|11|13|14
MA|¿Cuánto es 25 × 4?|100|90|125|75
MA|¿Cuánto es 13 × 13?|169|139|156|163
MA|¿Cuánto es 1000 - 457?|543|553|643|533
MA|¿Cuánto es 7 + 3 × 5?|22|50|25|35
MA|¿Cuánto es 6 × (4 + 2)?|36|26|30|48
MA|¿Cuánto es 2³ (dos elevado al cubo)?|8|6|9|5
MA|¿Cuánto es 5² + 3²?|34|16|64|30
MA|¿Cuál es la raíz cuadrada de 81?|9|8|7|11
MA|¿Cuánto es 25% de 80?|20|25|16|40
MA|¿Cuánto es 15% de 200?|30|15|20|35
MA|¿Cuánto es el 10% de 350?|35|3.5|70|30
MA|¿Cuánto es 3/4 + 1/4?|1|4/8|3/8|2/4
MA|¿Cuánto es 2/3 + 1/6?|5/6|3/9|1/2|2/9
MA|¿Cuál es una fracción equivalente a 1/2?|3/6|2/3|1/3|3/4
MA|¿Cuánto es 3/5 de 100?|60|35|53|80
MA|¿Cuánto es 0.5 + 0.25?|0.75|0.7|0.8|0.55
MA|¿Cuánto es la mitad de 1.5?|0.75|0.5|1|0.25
MA|¿Cuánto es 3.5 × 2?|7|6.5|5.5|8
MA|¿Cuánto es 100 ÷ 0.5?|200|50|20|2
MA|¿Cuál es el área de un rectángulo de 8 cm de largo y 5 cm de ancho?|40 cm²|13 cm²|26 cm²|80 cm²
MA|¿Cuál es el perímetro de un cuadrado de lado 7 cm?|28 cm|14 cm|49 cm|21 cm
MA|¿Cuál es el área de un triángulo de base 10 cm y altura 6 cm?|30 cm²|60 cm²|16 cm²|36 cm²
MA|¿Cuántos lados tiene un hexágono?|6|5|7|8
MA|¿Cómo se llama un polígono de 5 lados?|Pentágono|Hexágono|Octógono|Cuadrilátero
MA|¿Cuántos vértices tiene un cubo?|8|6|12|4
MA|¿Cuántos grados suman los ángulos interiores de un triángulo?|180°|90°|360°|270°
MA|¿Cuánto mide un ángulo recto?|90°|45°|180°|60°
MA|¿Cuál de estos es un número primo?|17|15|21|27
MA|Si x + 9 = 20, ¿cuánto vale x?|11|29|10|12
MA|Si 6 × n = 84, ¿cuánto vale n?|14|12|13|15
MA|¿Cuál es el MCM (mínimo común múltiplo) de 4 y 6?|12|24|10|2
MA|¿Cuál es el MCD (máximo común divisor) de 12 y 18?|6|3|9|12
MA|¿Cuánto es -5 + 8?|3|-13|-3|13
MA|¿Cuánto es (-3) × (-4)?|12|-12|7|-7
MA|¿Cuál es el siguiente número de la serie 2, 4, 8, 16, ...?|32|24|30|20
MA|¿Cuál es el siguiente número de la serie 1, 1, 2, 3, 5, 8, ...?|13|11|12|10
MA|¿Cuál es el promedio de 4, 8 y 12?|8|6|12|9
MA|¿Cuántos centímetros hay en 2.5 metros?|250|25|2500|205
MA|¿Cuántos gramos hay en 3 kilogramos?|3000|300|30|30000
MA|¿Cuántos minutos hay en 3 horas y media?|210|190|180|200
MA|¿Cuántas horas hay en una semana?|168|144|180|120
MA|Un tren viaja a 60 km/h. ¿Cuántos km recorre en 3 horas?|180 km|63 km|120 km|240 km
MA|Un libro cuesta S/ 40 y tiene 20% de descuento. ¿Cuánto pagas?|S/ 32|S/ 20|S/ 36|S/ 38
MA|Si 3 cuadernos cuestan S/ 15, ¿cuánto cuestan 7 cuadernos?|S/ 35|S/ 30|S/ 21|S/ 45
MA|Ana reparte 24 caramelos en partes iguales entre 6 amigos. ¿Cuántos recibe cada uno?|4|3|5|6

# ── INGLÉS ───────────────────────────────────────────────────────────────
EN|¿Cómo se dice "manzana" en inglés?|Apple|Orange|Banana|Grape
EN|¿Cómo se dice "escuela" en inglés?|School|House|Store|Street
EN|¿Cómo se dice "azul" en inglés?|Blue|Red|Green|Yellow
EN|¿Cómo se dice "lunes" en inglés?|Monday|Sunday|Tuesday|Friday
EN|¿Cómo se dice "diez" en inglés?|Ten|Two|Twelve|Eleven
EN|¿Qué significa "book"?|Libro|Mesa|Lápiz|Puerta
EN|¿Qué significa "rabbit"?|Conejo|Rana|Ratón|Pato
EN|¿Qué significa "library"?|Biblioteca|Librería|Libro|Laboratorio
EN|¿Qué significa "beautiful"?|Hermoso|Feo|Grande|Rápido
EN|¿Qué significa "yesterday"?|Ayer|Hoy|Mañana|Siempre
EN|¿Qué significa "always"?|Siempre|Nunca|A veces|Ahora
EN|¿Qué significa "sometimes"?|A veces|Siempre|Nunca|Ayer
EN|¿Qué significa "Good morning"?|Buenos días|Buenas noches|Buenas tardes|Hasta luego
EN|¿Qué significa "Thank you"?|Gracias|Por favor|Perdón|Hola
EN|¿Qué significa "Where are you from?"|¿De dónde eres?|¿Cómo estás?|¿Cuántos años tienes?|¿Cómo te llamas?
EN|¿Qué significa "I'm hungry"?|Tengo hambre|Tengo sed|Estoy cansado|Tengo frío
EN|¿Cuál de estas palabras es un color?|Purple|Pencil|Window|Monday
EN|¿Cuál es el opuesto de "big"?|Small|Tall|Long|Fast
EN|¿Cuál es el opuesto de "hot"?|Cold|Warm|Wet|Dry
EN|¿Cuál es el plural de "child"?|Children|Childs|Childes|Childrens
EN|¿Cuál es el plural de "mouse"?|Mice|Mouses|Mices|Mousees
EN|¿Cuál es el plural de "box"?|Boxes|Boxs|Boxies|Boxen
EN|¿Cuál es el pasado de "go"?|Went|Goed|Gone|Going
EN|¿Cuál es el pasado de "eat"?|Ate|Eated|Eaten|Eating
EN|¿Cuál es el superlativo de "good"?|Best|Goodest|Most good|Better
EN|Completa: "She ___ a student."|is|are|am|be
EN|Completa: "They ___ playing football."|are|is|am|be
EN|Completa: "I ___ breakfast every day."|eat|eats|eating|eated
EN|Completa: "He ___ to school by bus."|goes|go|going|gone
EN|Completa: "She ___ TV every night."|watches|watch|watchs|watching
EN|Completa: "There ___ three apples on the table."|are|is|am|be
EN|Completa: "What time ___ it?"|is|are|do|does
EN|Completa: "I have two ___."|brothers|brother|a brother|brotherses
EN|Completa: "My brother ___ a bike."|has|have|haves|is have
EN|¿Cuál de estas preguntas está bien escrita?|Do you like music?|You like music do?|Like you music?|Does you like music?
EN|¿Cómo se dice "Me gusta la pizza" en inglés?|I like pizza|I am pizza|I have pizza|I go pizza
EN|¿Cómo se dice "Tengo doce años" en inglés?|I am twelve years old|I have twelve years|I am twelve years|I have twelve years old

# ── CHINO BÁSICO (con pinyin) ────────────────────────────────────────────
ZH|¿Qué significa 你好 (nǐ hǎo)?|Hola|Adiós|Gracias|Por favor
ZH|¿Qué significa 谢谢 (xièxie)?|Gracias|Hola|Perdón|Adiós
ZH|¿Qué significa 再见 (zàijiàn)?|Adiós|Hola|Gracias|Buenos días
ZH|¿Qué significa 对不起 (duìbuqǐ)?|Lo siento / perdón|Gracias|De nada|Buenas noches
ZH|¿Qué significa 不客气 (bú kèqi)?|De nada|Gracias|Hola|Adiós
ZH|¿Qué significa 早上好 (zǎoshang hǎo)?|Buenos días|Buenas noches|Adiós|Gracias
ZH|¿Qué significa 晚安 (wǎn'ān)?|Buenas noches|Buenos días|Hola|Gracias
ZH|¿Qué significa 你好吗 (nǐ hǎo ma)?|¿Cómo estás?|¿Cómo te llamas?|¿Dónde vives?|¿Cuántos años tienes?
ZH|¿Qué significa 我叫 (wǒ jiào)?|Me llamo|Tengo años|Soy de|Me gusta
ZH|¿Qué significa 我爱你 (wǒ ài nǐ)?|Te quiero / te amo|Te veo|Te ayudo|Te llamo
ZH|¿Qué número es 一 (yī)?|1|2|3|10
ZH|¿Qué número es 二 (èr)?|2|1|3|12
ZH|¿Qué número es 三 (sān)?|3|2|4|5
ZH|¿Qué número es 四 (sì)?|4|3|5|14
ZH|¿Qué número es 五 (wǔ)?|5|4|6|9
ZH|¿Qué número es 六 (liù)?|6|5|7|16
ZH|¿Qué número es 七 (qī)?|7|6|8|17
ZH|¿Qué número es 八 (bā)?|8|6|7|9
ZH|¿Qué número es 九 (jiǔ)?|9|6|8|5
ZH|¿Qué número es 十 (shí)?|10|7|1|100
ZH|¿Qué significa 水 (shuǐ)?|Agua|Fuego|Árbol|Montaña
ZH|¿Qué significa 火 (huǒ)?|Fuego|Agua|Tierra|Viento
ZH|¿Qué significa 山 (shān)?|Montaña|Río|Sol|Casa
ZH|¿Qué significa 人 (rén)?|Persona|Perro|Casa|Grande
ZH|¿Qué significa 大 (dà)?|Grande|Pequeño|Bueno|Alto
ZH|¿Qué significa 小 (xiǎo)?|Pequeño|Grande|Alto|Nuevo
ZH|¿Qué significa 月 (yuè)?|Luna / mes|Sol|Estrella|Nube
ZH|¿Qué significa 日 (rì)?|Sol / día|Luna|Agua|Montaña
ZH|¿Qué significa 我 (wǒ)?|Yo|Tú|Él|Nosotros
ZH|¿Qué significa 你 (nǐ)?|Tú|Yo|Ella|Ellos
ZH|¿Qué significa 好 (hǎo)?|Bueno|Malo|Grande|Rápido
ZH|¿Qué significa 爱 (ài)?|Amor / amar|Comer|Beber|Dormir
ZH|¿Qué animal es 猫 (māo)?|Gato|Perro|Pez|Pájaro
ZH|¿Qué animal es 狗 (gǒu)?|Perro|Gato|Pez|Pájaro
ZH|¿Qué significa 吃 (chī)?|Comer|Beber|Dormir|Correr
ZH|¿Qué significa 喝 (hē)?|Beber|Comer|Dormir|Leer
ZH|¿Qué significa 书 (shū)?|Libro|Mesa|Escuela|Lápiz
ZH|¿Qué significa 学校 (xuéxiào)?|Escuela|Casa|Libro|Ciudad
ZH|¿Qué significa 老师 (lǎoshī)?|Profesor(a)|Estudiante|Médico|Amigo
ZH|¿Qué significa 学生 (xuésheng)?|Estudiante|Profesor(a)|Médico|Amigo
ZH|¿Qué significa 朋友 (péngyou)?|Amigo(a)|Familia|Maestro|Hermano
ZH|¿Qué significa 妈妈 (māma)?|Mamá|Papá|Hermano|Abuelo
ZH|¿Qué significa 爸爸 (bàba)?|Papá|Mamá|Abuela|Amigo
ZH|¿Qué significa 红色 (hóngsè)?|Rojo|Azul|Verde|Amarillo
ZH|¿Qué significa 中国 (Zhōngguó)?|China|Japón|Perú|Corea
FIN_BANCO

# Se quedan solo las líneas válidas (MATERIA|...) y se cuentan por materia
BANCO=()
declare -A CUENTA=()
for linea in "${BANCO_CRUDO[@]}"; do
  if [[ "$linea" =~ ^(CG|MA|EN|ZH)\| ]]; then
    BANCO+=("$linea")
    (( CUENTA[${BASH_REMATCH[1]}]++ ))
  fi
done

# ─── 9. Inicio ────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help|--ayuda) ayuda; exit 0 ;;
  --reset)
    read -r -p "¿Borrar TODOS los puntajes? Escribe SI para confirmar: " resp_reset
    if [[ "$resp_reset" == "SI" ]]; then rm -f "$SCORE_FILE" && echo "Puntajes borrados."; else echo "Cancelado."; fi
    exit 0 ;;
esac

if (( ${#BANCO[@]} == 0 )); then
  echo "El banco de preguntas está vacío." >&2
  exit 1
fi

menu_principal
