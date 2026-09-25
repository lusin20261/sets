#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
#  INVASORES DE PALABRAS  —  juego de mecanografía estilo "Galaga"
# ══════════════════════════════════════════════════════════════════════════
#  Las palabras caen lentamente desde arriba. Escríbelas correctamente
#  (con tildes y ñ incluidas) para hacerlas explotar antes de que toquen
#  el horizonte. La velocidad de caída sube siguiendo una curva
#  logarítmica: empieza lenta y se acelera cada vez más despacio, hasta
#  estabilizarse en un ritmo desafiante pero manejable.
#
#  Uso:      chmod +x invasores_de_palabras.sh && ./invasores_de_palabras.sh
#  Opciones: --reset   borra la tabla de puntajes (pide confirmación)
#            --help    muestra esta ayuda
#  Variables:
#            INVASORES_SCORES=/ruta/puntajes.txt   dónde guardar puntajes
#            NO_COLOR=1                            desactiva los colores
#
#  Requiere: bash 5+ (usa EPOCHREALTIME para medir el tiempo sin crear
#            procesos extra en cada fotograma), awk, tput, y una terminal
#            en UTF-8 (para que las tildes y la ñ se lean como un solo
#            carácter). En Linux Mint esto ya viene así por defecto.
#
#  Tildes: en LATAM normalmente se presiona la tecla de tilde (´) y luego
#  la vocal; el sistema operativo combina ambas pulsaciones en un único
#  carácter ("á") antes de que le llegue al juego, así que el juego lo
#  reconoce igual que cualquier otra letra: no resalta la "a" sola,
#  solo cuando ya se formó la "á" completa.
#
#  AGREGAR PALABRAS: añade una palabra por línea dentro del bloque
#  BANCO_PALABRAS más abajo (todo en minúsculas, sin espacios, máximo
#  15 letras). Las líneas vacías o que empiezan con # se ignoran y
#  sirven solo para organizar el banco en categorías.
# ══════════════════════════════════════════════════════════════════════════

if (( BASH_VERSINFO[0] < 5 )); then
  echo "Este juego necesita bash 5 o superior (usa EPOCHREALTIME)." >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Este juego necesita ejecutarse en una terminal interactiva." >&2
  exit 1
fi

SCORE_FILE="${INVASORES_SCORES:-${XDG_DATA_HOME:-$HOME/.local/share}/invasores-palabras/puntajes.txt}"

# ─── 1. Colores y códigos de escape (sin depender de tput en el bucle) ────
ESC=$'\033'
CSI="${ESC}["
ALT_ON="${CSI}?1049h"; ALT_OFF="${CSI}?1049l"
CUR_OFF="${CSI}?25l";  CUR_ON="${CSI}?25h"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RST="${CSI}0m"; BOLD="${CSI}1m"; DIM="${CSI}2m"
  RED="${CSI}91m"; GRN="${CSI}92m"; YEL="${CSI}93m"
  BLU="${CSI}94m"; MAG="${CSI}95m"; CYN="${CSI}96m"; WHT="${CSI}97m"
else
  RST=""; BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; MAG=""; CYN=""; WHT=""
fi

COLOR_HILITE="${GRN}${BOLD}"
COLOR_PALABRA="${WHT}"
COLOR_EXPLOSION="${YEL}${BOLD}"
COLOR_HORIZONTE="${RED}${BOLD}"

EXPLOSIONES=("¡PUM!" "¡BOOM!" "¡ZAS!" "¡CATAPUM!" "¡PLAF!")

# ─── 2. Configuración del juego ───────────────────────────────────────────
TICK_MS=90
TICK_US=$(( TICK_MS * 1000 ))

SPEED_V0_MRS=400      # velocidad inicial: 0.4 filas/seg (x1000) — arranque suave
SPEED_A_MRS=950        # coeficiente de crecimiento logarítmico (x1000)
SPEED_TAU_S=24         # constante de tiempo (segundos) — sube más despacio al inicio
SPEED_VMAX_MRS=3600    # velocidad máxima: 3.6 filas/seg (x1000) — techo más alto, sigue subiendo por más tiempo

SPAWN_INTERVAL_US=1600000   # intento de aparición cada 1.6s si hay carril libre
EXPLOSION_TICKS=3

LANE_WIDTH=20
LANE_PAD=2
MIN_LANES=3
MAX_LANES=8
LONGITUD_MAX_PALABRA=$(( LANE_WIDTH - LANE_PAD - 3 ))

RESERVED_TOP=2
RESERVED_BOTTOM=4
MIN_FIELD_HEIGHT=10
MIN_COLS=60
MIN_LINES=$(( RESERVED_TOP + RESERVED_BOTTOM + MIN_FIELD_HEIGHT + 2 ))

# ─── 3. Limpieza y señales ─────────────────────────────────────────────────
EN_MODO_JUEGO=0
RESIZED=0

entrar_modo_juego() {
  STTY_ORIG=$(stty -g)
  printf '%s' "${ALT_ON}${CUR_OFF}"
  stty -echo -icanon
  EN_MODO_JUEGO=1
}

salir_modo_juego() {
  stty "$STTY_ORIG" 2>/dev/null
  printf '%s' "${CUR_ON}${ALT_OFF}"
  EN_MODO_JUEGO=0
}

cleanup() {
  (( EN_MODO_JUEGO )) && salir_modo_juego
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap 'RESIZED=1' WINCH

# ─── 4. Reloj sin crear procesos (bash 5: EPOCHREALTIME) ──────────────────
actualizar_reloj() {   # deja el resultado en AHORA_US (variable global)
  local s u
  s="${EPOCHREALTIME%.*}"
  u="${EPOCHREALTIME#*.}"
  AHORA_US=$(( 10#$s * 1000000 + 10#$u ))
}

# ─── 5. Utilidades de pantalla (modo normal, para menús) ──────────────────
limpiar() { [[ -t 1 ]] && printf '\033[H\033[2J'; }

pausa_enter() {
  printf '\n  %sPresiona ENTER para continuar...%s' "$DIM" "$RST"
  IFS= read -r _ || exit 0
}

banner() {
  limpiar
  printf '\n'
  printf '  %s╔═══════════════════════════════════════════════╗%s\n' "$CYN" "$RST"
  printf '  %s║                                               ║%s\n' "$CYN" "$RST"
  printf '  %s║%s%s   👾 INVASORES DE PALABRAS 👾               %s%s║%s\n' "$CYN" "$RST" "$YEL$BOLD" "$RST" "$CYN" "$RST"
  printf '  %s║                                               ║%s\n' "$CYN" "$RST"
  printf '  %s║%s  Escribe rápido antes de que caigan al suelo  %s║%s\n' "$CYN" "$RST" "$CYN" "$RST"
  printf '  %s╚═══════════════════════════════════════════════╝%s\n' "$CYN" "$RST"
  printf '       %sby Profesor Luis para sus alumnos de Lusin.%s\n\n' "$DIM" "$RST"
}

instrucciones() {
  banner
  printf '  %s¿CÓMO SE JUEGA?%s\n\n' "$BOLD$YEL" "$RST"
  printf '   • Las palabras caen lentamente desde arriba.\n'
  printf '   • Escribe la palabra completa para hacerla %sexplotar%s.\n' "$GRN$BOLD" "$RST"
  printf '   • Si hay varias palabras en pantalla, no hace falta elegir:\n'
  printf '     cada letra que escribes se resalta en %stodas%s las palabras\n' "$BOLD" "$RST"
  printf '     que empiecen igual; en cuanto una deja de coincidir, deja\n'
  printf '     de resaltarse (aunque ya llevaras varias letras bien).\n'
  printf '   • Las tildes y la ñ cuentan: escribe "á", "é", "ñ", etc. tal\n'
  printf '     cual (presiona la tecla de tilde y luego la vocal, como\n'
  printf '     siempre); el juego espera la letra ya combinada.\n'
  printf '   • Si te equivocas, esa tecla simplemente no hace nada\n'
  printf '     (no rompe lo que ya escribiste bien).\n'
  printf '   • %sESC%s borra todo lo escrito. %sRetroceso%s borra una letra.\n' "$BLU$BOLD" "$RST" "$BLU$BOLD" "$RST"
  printf '   • Si una palabra llega al %shorizonte%s de abajo, pierdes.\n' "$RED$BOLD" "$RST"
  printf '   • La velocidad de caída sube poco a poco y luego se\n'
  printf '     estabiliza: al principio es fácil, después hay que\n'
  printf '     escribir cada vez más rápido.\n'
  printf '   • Al terminar, escribe tu nombre y entrarás a la tabla de\n'
  printf '     puntajes.\n'
  pausa_enter
}

# ─── 6. Banco de palabras (solo español) ──────────────────────────────────
mapfile -t BANCO_CRUDO <<'FIN_PALABRAS'
# ── Animales ─────────────────────────────────────────────────────────────
perro gato león tigre oso lobo zorro conejo ratón caballo
vaca cerdo oveja cabra pato pollo gallina pavo águila búho
loro paloma cisne delfín ballena tiburón pulpo cangrejo tortuga
serpiente lagarto rana sapo mariposa abeja araña hormiga mosca grillo
caracol elefante jirafa mono cebra rinoceronte hipopótamo canguro koala ardilla
murciélago erizo ñandú pez

# ── Naturaleza y clima ───────────────────────────────────────────────────
sol luna estrella cielo nube lluvia viento nieve hielo trueno
relámpago arcoíris montaña volcán río lago mar océano playa desierto
selva bosque árbol flor hoja raíz semilla piedra arena tierra
fuego aire

# ── Comida y bebida ──────────────────────────────────────────────────────
manzana plátano naranja uva fresa piña sandía melón pera durazno
mango papaya limón coco maíz papa arroz pan queso leche
huevo carne pescado sopa ensalada torta galleta chocolate helado jugo
café té azúcar sal miel mantequilla tomate cebolla

# ── Familia y personas ───────────────────────────────────────────────────
mamá papá hermano hermana abuelo abuela tío tía primo prima
hijo hija bebé niño niña amigo amiga vecino vecina maestro
maestra doctor doctora

# ── Casa y objetos ───────────────────────────────────────────────────────
casa puerta ventana mesa silla cama sofá cocina baño techo
pared piso lámpara espejo reloj teléfono televisor radio computadora libro
cuaderno lápiz lapicero borrador tijera mochila llave cepillo jabón toalla
plato vaso cuchara tenedor cuchillo

# ── Escuela ───────────────────────────────────────────────────────────────
escuela salón pizarra profesor alumno examen tarea lectura escritura número
letra pregunta respuesta

# ── Colores ───────────────────────────────────────────────────────────────
rojo azul verde amarillo morado rosado negro blanco gris
dorado plateado

# ── Cuerpo ────────────────────────────────────────────────────────────────
cabeza cara ojo oreja nariz boca diente lengua cuello hombro
brazo mano dedo pierna pie rodilla corazón cerebro pulmón estómago

# ── Transporte ────────────────────────────────────────────────────────────
carro bus tren avión barco bicicleta moto camión taxi metro

# ── Deportes y juegos ─────────────────────────────────────────────────────
fútbol básquet vóley tenis natación carrera pelota juego juguete muñeca
cometa rompecabezas

# ── Verbos comunes ────────────────────────────────────────────────────────
correr saltar comer beber dormir jugar leer escribir hablar escuchar
cantar bailar pintar dibujar cocinar limpiar estudiar aprender enseñar ayudar
compartir sonreír reír llorar caminar volar nadar soñar pensar

# ── Adjetivos ─────────────────────────────────────────────────────────────
grande pequeño alto bajo rápido lento fuerte débil feliz triste
bonito feo limpio sucio fácil difícil caliente frío nuevo viejo

# ── Números y tiempo ──────────────────────────────────────────────────────
uno dos tres cuatro cinco seis siete ocho nueve diez
lunes martes miércoles jueves viernes sábado domingo mañana tarde noche
hoy ayer año

# ── Palabras con tilde o ñ (práctica extra) ───────────────────────────────
canción cañón botón balón razón acción región médico música práctica
público cráneo país ataúd baúl según electricidad extraordinario compañero señor
señora
FIN_PALABRAS

BANCO_PALABRAS=()
for _linea in "${BANCO_CRUDO[@]}"; do
  _linea="${_linea%%$'\r'}"
  [[ -z "$_linea" || "$_linea" == \#* ]] && continue
  for _palabra in $_linea; do
    (( ${#_palabra} <= LONGITUD_MAX_PALABRA )) && BANCO_PALABRAS+=("$_palabra")
  done
done
unset _linea _palabra BANCO_CRUDO

# ─── 7. Puntajes ────────────────────────────────────────────────────────────
guardar_puntaje() {
  mkdir -p "$(dirname "$SCORE_FILE")" 2>/dev/null || return 1
  printf '%s|%s|%s|%s|%s|%s\n' "$(date +%F)" "$1" "$2" "$3" "$4" "$5" 2>/dev/null >> "$SCORE_FILE"
}

mostrar_puntajes() {
  local pos=0 fecha nombre pts palabras tiempo nivel col
  limpiar
  printf '\n  %s%s══════════  TABLA DE PUNTAJES  ·  Top 10  ══════════%s\n\n' "$YEL" "$BOLD" "$RST"
  if [[ ! -s "$SCORE_FILE" ]]; then
    printf '  Aún no hay puntajes guardados. ¡Sé el primero en jugar!\n'
    return
  fi
  printf '  %s%-4s %-20s %7s  %8s  %6s%s\n' "$DIM" "#" "Nombre" "Puntos" "Palabras" "Nivel" "$RST"
  printf '  %s%s%s\n' "$DIM" "──────────────────────────────────────────────────────" "$RST"
  while IFS='|' read -r fecha nombre pts palabras tiempo nivel; do
    (( pos++ ))
    case $pos in
      1) col="$YEL$BOLD" ;;
      2) col="$WHT$BOLD" ;;
      3) col="$MAG$BOLD" ;;
      *) col="$RST" ;;
    esac
    printf '  %s%-4s %-20s %7s  %8s  %6s%s\n' "$col" "$pos" "$nombre" "$pts" "$palabras" "$nivel" "$RST"
  done < <(sort -t'|' -k3,3nr -k1,1r "$SCORE_FILE" | head -n 10)
}

# ─── 8. Preparar el juego (tamaños, carriles) ─────────────────────────────
preparar_juego() {
  COLUMNAS=$(tput cols 2>/dev/null); COLUMNAS=${COLUMNAS:-${COLUMNS:-80}}
  LINEAS=$(tput lines 2>/dev/null); LINEAS=${LINEAS:-${LINES:-24}}

  if (( COLUMNAS < MIN_COLS || LINEAS < MIN_LINES )); then
    return 1
  fi

  PLAY_WIDTH=$COLUMNAS
  NUM_LANES=$(( PLAY_WIDTH / LANE_WIDTH ))
  (( NUM_LANES < MIN_LANES )) && NUM_LANES=$MIN_LANES
  (( NUM_LANES > MAX_LANES )) && NUM_LANES=$MAX_LANES
  MARGEN_IZQ=$(( (PLAY_WIDTH - NUM_LANES * LANE_WIDTH) / 2 ))
  (( MARGEN_IZQ < 0 )) && MARGEN_IZQ=0

  FIELD_HEIGHT=$(( LINEAS - RESERVED_TOP - RESERVED_BOTTOM ))

  printf -v LINEA_SEP '%*s' "$PLAY_WIDTH" ''
  LINEA_SEP="${LINEA_SEP// /─}"
  printf -v LINEA_HORIZONTE '%*s' "$PLAY_WIDTH" ''
  LINEA_HORIZONTE="${LINEA_HORIZONTE// /▔}"

  LANE_OCUPADO=(); LANE_TEXTO=(); LANE_ROW_SCALED=(); LANE_ROW_INT=()
  LANE_HILITE=(); LANE_EXPLOTANDO=(); LANE_EXPLOSION_TXT=()
  local l
  for (( l = 0; l < NUM_LANES; l++ )); do
    LANE_OCUPADO[l]=0; LANE_TEXTO[l]=""; LANE_ROW_SCALED[l]=0; LANE_ROW_INT[l]=0
    LANE_HILITE[l]=0; LANE_EXPLOTANDO[l]=0; LANE_EXPLOSION_TXT[l]=""
  done

  PUNTAJE=0; RACHA=0; MEJOR_RACHA=0; PALABRAS_DESTRUIDAS=0
  TYPED=""; ERROR_FLASH=0; JUEGO_TERMINADO=0; RESIZED=0
  PALABRA_PERDIDA=""

  actualizar_reloj; INICIO_US=$AHORA_US
  ULTIMO_SPAWN_US=$(( INICIO_US - SPAWN_INTERVAL_US ))
  ULTIMA_VELOCIDAD_US=-1
  CURRENT_SPEED_MRS=$SPEED_V0_MRS
  NIVEL=1
  return 0
}

# ─── 9. Lógica de palabras ─────────────────────────────────────────────────
elegir_palabra() {
  local intento palabra ya_activa l
  for (( intento = 0; intento < 5; intento++ )); do
    palabra="${BANCO_PALABRAS[RANDOM % ${#BANCO_PALABRAS[@]}]}"
    ya_activa=0
    for (( l = 0; l < NUM_LANES; l++ )); do
      if (( LANE_OCUPADO[l] )) && [[ "${LANE_TEXTO[l]}" == "$palabra" ]]; then
        ya_activa=1; break
      fi
    done
    (( ya_activa == 0 )) && { printf '%s' "$palabra"; return; }
  done
  printf '%s' "$palabra"
}

intentar_generar_palabra() {
  (( AHORA_US - ULTIMO_SPAWN_US < SPAWN_INTERVAL_US )) && return
  local libres=() l idx palabra
  for (( l = 0; l < NUM_LANES; l++ )); do
    (( LANE_OCUPADO[l] == 0 )) && libres+=("$l")
  done
  (( ${#libres[@]} == 0 )) && return
  idx=${libres[RANDOM % ${#libres[@]}]}
  palabra=$(elegir_palabra)
  LANE_OCUPADO[idx]=1
  LANE_TEXTO[idx]="$palabra"
  LANE_ROW_SCALED[idx]=0
  LANE_ROW_INT[idx]=0
  LANE_HILITE[idx]=0
  LANE_EXPLOTANDO[idx]=0
  ULTIMO_SPAWN_US=$AHORA_US
}

actualizar_velocidad() {
  if (( ULTIMA_VELOCIDAD_US >= 0 && AHORA_US - ULTIMA_VELOCIDAD_US < 1000000 )); then
    return
  fi
  local elapsed_us=$(( AHORA_US - INICIO_US ))
  CURRENT_SPEED_MRS=$(awk -v t_us="$elapsed_us" -v v0="$SPEED_V0_MRS" -v a="$SPEED_A_MRS" \
    -v tau="$SPEED_TAU_S" -v vmax="$SPEED_VMAX_MRS" 'BEGIN{
      t = t_us / 1000000.0
      v0f = v0 / 1000.0; af = a / 1000.0; vmaxf = vmax / 1000.0
      v = v0f + af * log(1 + t / tau)
      if (v > vmaxf) v = vmaxf
      printf "%d", (v * 1000) + 0.5
    }')
  NIVEL=$(( 1 + (CURRENT_SPEED_MRS - SPEED_V0_MRS) * 9 / (SPEED_VMAX_MRS - SPEED_V0_MRS) ))
  (( NIVEL < 1 )) && NIVEL=1
  (( NIVEL > 10 )) && NIVEL=10
  ULTIMA_VELOCIDAD_US=$AHORA_US
}

actualizar_posiciones() {
  local l fila incremento dt_us
  dt_us=$(( AHORA_US - ULTIMO_TICK_US ))
  (( dt_us < 0 )) && dt_us=0
  incremento=$(( CURRENT_SPEED_MRS * dt_us / 1000000 ))
  for (( l = 0; l < NUM_LANES; l++ )); do
    (( LANE_OCUPADO[l] == 0 )) && continue
    if (( LANE_EXPLOTANDO[l] > 0 )); then
      (( LANE_EXPLOTANDO[l]-- ))
      (( LANE_EXPLOTANDO[l] == 0 )) && LANE_OCUPADO[l]=0
      continue
    fi
    (( LANE_ROW_SCALED[l] += incremento ))
    fila=$(( LANE_ROW_SCALED[l] / 1000 ))
    LANE_ROW_INT[l]=$fila
    if (( fila >= FIELD_HEIGHT - 1 )); then
      JUEGO_TERMINADO=1
      PALABRA_PERDIDA="${LANE_TEXTO[l]}"
    fi
  done
}

actualizar_resaltado() {
  local l
  for (( l = 0; l < NUM_LANES; l++ )); do
    if (( LANE_OCUPADO[l] )) && [[ "${LANE_TEXTO[l]}" == "$TYPED"* ]]; then
      LANE_HILITE[l]=${#TYPED}
    else
      LANE_HILITE[l]=0
    fi
  done
}

completar_palabra() {
  local l="$1" palabra="${LANE_TEXTO[$1]}" bono ganados
  RACHA=$(( RACHA + 1 ))
  (( RACHA > MEJOR_RACHA )) && MEJOR_RACHA=$RACHA
  bono=$(( (RACHA - 1) * 2 ))
  (( bono < 0 )) && bono=0
  (( bono > 20 )) && bono=20
  ganados=$(( ${#palabra} * 10 + bono ))
  PUNTAJE=$(( PUNTAJE + ganados ))
  PALABRAS_DESTRUIDAS=$(( PALABRAS_DESTRUIDAS + 1 ))
  LANE_EXPLOTANDO[l]=$EXPLOSION_TICKS
  LANE_EXPLOSION_TXT[l]="${EXPLOSIONES[RANDOM % ${#EXPLOSIONES[@]}]}"
  TYPED=""
}

procesar_una_tecla() {
  local ch="$1" candidato l encontrado=0 completada=-1
  case "$ch" in
    $'\x7f'|$'\x08')
      [[ -n "$TYPED" ]] && TYPED="${TYPED%?}"
      return ;;
    $'\x1b')
      TYPED=""
      return ;;
  esac
  candidato="$TYPED$ch"
  for (( l = 0; l < NUM_LANES; l++ )); do
    if (( LANE_OCUPADO[l] )) && (( LANE_EXPLOTANDO[l] == 0 )) && [[ "${LANE_TEXTO[l]}" == "$candidato"* ]]; then
      encontrado=1
      [[ "${LANE_TEXTO[l]}" == "$candidato" ]] && completada=$l
    fi
  done
  if (( encontrado == 0 )); then
    ERROR_FLASH=2
    RACHA=0
    return
  fi
  TYPED="$candidato"
  (( completada >= 0 )) && completar_palabra "$completada"
}

procesar_entrada_del_tick() {
  local restante_us="$1" seg mic restante_s ch
  seg=$(( restante_us / 1000000 ))
  mic=$(( restante_us % 1000000 ))
  printf -v restante_s '%d.%06d' "$seg" "$mic"
  ch=""
  IFS= read -rsn1 -t "$restante_s" ch
  [[ -n "$ch" ]] && procesar_una_tecla "$ch"
  while IFS= read -rsn1 -t 0.001 ch; do
    [[ -n "$ch" ]] && procesar_una_tecla "$ch"
  done
}

# ─── 10. Dibujo ────────────────────────────────────────────────────────────
dibujar_pantalla() {
  local buf="" fila abs_fila l col_actual gap pad texto h ancho txt_explosion
  local min_seg seg_rest tiempo_fmt

  buf+="${CSI}1;1H"
  local elapsed_s=$(( (AHORA_US - INICIO_US) / 1000000 ))
  min_seg=$(( elapsed_s / 60 )); seg_rest=$(( elapsed_s % 60 ))
  printf -v tiempo_fmt '%02d:%02d' "$min_seg" "$seg_rest"
  buf+=" ${YEL}${BOLD}Puntaje:${RST} ${WHT}${PUNTAJE}${RST}   ${MAG}${BOLD}Racha:${RST} ${WHT}${RACHA}${RST}   ${CYN}${BOLD}Nivel:${RST} ${WHT}${NIVEL}/10${RST}   ${DIM}Tiempo:${RST} ${tiempo_fmt}${CSI}K"
  buf+="${CSI}2;1H${DIM}${LINEA_SEP}${RST}${CSI}K"

  for (( fila = 0; fila < FIELD_HEIGHT; fila++ )); do
    abs_fila=$(( RESERVED_TOP + fila + 1 ))
    buf+="${CSI}${abs_fila};1H"
    col_actual=0
    for (( l = 0; l < NUM_LANES; l++ )); do
      (( LANE_OCUPADO[l] == 0 )) && continue
      (( LANE_ROW_INT[l] != fila )) && continue
      local lane_col=$(( MARGEN_IZQ + l * LANE_WIDTH + LANE_PAD ))
      gap=$(( lane_col - col_actual ))
      if (( gap > 0 )); then
        printf -v pad '%*s' "$gap" ''
        buf+="$pad"
      fi
      if (( LANE_EXPLOTANDO[l] > 0 )); then
        txt_explosion="${LANE_EXPLOSION_TXT[l]}"
        buf+="${COLOR_EXPLOSION}${txt_explosion}${RST}"
        ancho=${#txt_explosion}
      else
        texto="${LANE_TEXTO[l]}"
        h=${LANE_HILITE[l]}
        buf+="${COLOR_HILITE}${texto:0:h}${RST}${COLOR_PALABRA}${texto:h}${RST}"
        ancho=${#texto}
      fi
      col_actual=$(( lane_col + ancho ))
    done
    buf+="${CSI}K"
  done

  local fila_horizonte=$(( RESERVED_TOP + FIELD_HEIGHT + 1 ))
  buf+="${CSI}${fila_horizonte};1H${COLOR_HORIZONTE}${LINEA_HORIZONTE}${RST}${CSI}K"
  buf+="${CSI}$(( fila_horizonte + 1 ));1H${CSI}K"

  buf+="${CSI}$(( fila_horizonte + 2 ));1H"
  if (( ERROR_FLASH > 0 )); then
    buf+="  ${RED}${BOLD}Escribiendo:${RST} ${RED}> ${TYPED}▌ ✗${RST}${CSI}K"
  else
    buf+="  ${CYN}${BOLD}Escribiendo:${RST} ${WHT}> ${TYPED}▌${RST}${CSI}K"
  fi
  buf+="${CSI}$(( fila_horizonte + 3 ));1H${DIM}  ESC borra lo escrito · Retroceso corrige · Ctrl+C sale${RST}${CSI}K"

  printf '%s' "$buf"
}

# ─── 11. Bucle principal del juego ─────────────────────────────────────────
jugar() {
  if ! preparar_juego; then
    banner
    printf '  %sLa terminal es muy pequeña para jugar.%s\n' "$RED$BOLD" "$RST"
    printf '  Se necesitan al menos %d columnas x %d líneas (tienes %sx%s).\n' \
      "$MIN_COLS" "$MIN_LINES" "${COLUMNAS:-?}" "${LINEAS:-?}"
    printf '  Agranda la ventana de la terminal e inténtalo de nuevo.\n'
    pausa_enter
    return
  fi

  entrar_modo_juego
  actualizar_reloj; ULTIMO_TICK_US=$AHORA_US

  while true; do
    actualizar_reloj
    local t_ini_us=$AHORA_US
    actualizar_velocidad
    actualizar_resaltado
    dibujar_pantalla

    if (( JUEGO_TERMINADO || RESIZED )); then break; fi

    actualizar_reloj
    local usado=$(( AHORA_US - t_ini_us ))
    local restante=$(( TICK_US - usado ))
    (( restante < 10000 )) && restante=10000
    procesar_entrada_del_tick "$restante"

    actualizar_reloj
    intentar_generar_palabra
    actualizar_posiciones
    ULTIMO_TICK_US=$AHORA_US

    (( ERROR_FLASH > 0 )) && ERROR_FLASH=$(( ERROR_FLASH - 1 ))
  done

  salir_modo_juego
  pantalla_fin
}

# ─── 12. Fin de la partida ─────────────────────────────────────────────────
pantalla_fin() {
  local elapsed_s=$(( (AHORA_US - INICIO_US) / 1000000 ))
  local min_seg=$(( elapsed_s / 60 )) seg_rest=$(( elapsed_s % 60 )) tiempo_fmt nombre puesto

  limpiar
  printf '\n  %s%s══════════  FIN DE LA PARTIDA  ══════════%s\n\n' "$BOLD" "$CYN" "$RST"

  if (( RESIZED )); then
    printf '  %sLa terminal cambió de tamaño; la partida terminó aquí.%s\n\n' "$YEL" "$RST"
  elif [[ -n "$PALABRA_PERDIDA" ]]; then
    printf '  %s¡La palabra "%s" llegó al suelo!%s\n\n' "$RED$BOLD" "$PALABRA_PERDIDA" "$RST"
  fi

  printf -v tiempo_fmt '%02d:%02d' "$min_seg" "$seg_rest"
  printf '  Tiempo sobrevivido .. %s%s%s\n' "$CYN" "$tiempo_fmt" "$RST"
  printf '  Palabras destruidas . %s%d%s\n' "$GRN" "$PALABRAS_DESTRUIDAS" "$RST"
  printf '  Mejor racha ......... %s%d%s\n' "$MAG" "$MEJOR_RACHA" "$RST"
  printf '  Nivel alcanzado ..... %s%d/10%s\n' "$YEL" "$NIVEL" "$RST"
  printf '  %sPUNTAJE ............. %d puntos%s\n\n' "$BOLD$YEL" "$PUNTAJE" "$RST"

  if (( PALABRAS_DESTRUIDAS == 0 )); then
    pausa_enter
    return
  fi

  printf '  %s¿Cómo te llamas?%s (para la tabla de puntajes) : ' "$BOLD$CYN" "$RST"
  IFS= read -r nombre || exit 0
  nombre="${nombre//[[:cntrl:]]/}"
  nombre="${nombre//|/}"
  nombre="${nombre#"${nombre%%[![:space:]]*}"}"
  nombre="${nombre%"${nombre##*[![:space:]]}"}"
  nombre="${nombre:0:20}"
  [[ -z "$nombre" ]] && nombre="Anónimo"

  if guardar_puntaje "$nombre" "$PUNTAJE" "$PALABRAS_DESTRUIDAS" "$tiempo_fmt" "$NIVEL"; then
    puesto=$(awk -F'|' -v p="$PUNTAJE" '$3 + 0 > p + 0 { c++ } END { print c + 1 }' "$SCORE_FILE")
    printf '\n  %s¡Listo, %s! Tu puntaje quedó guardado.%s\n' "$GRN" "$nombre" "$RST"
    printf '  %sPuesto en la tabla: #%s%s\n' "$YEL$BOLD" "$puesto" "$RST"
  else
    printf '\n  %sNo se pudo guardar el puntaje (revisa permisos de: %s).%s\n' "$RED" "$SCORE_FILE" "$RST"
  fi
  pausa_enter
  mostrar_puntajes
  pausa_enter
}

# ─── 13. Menú principal ─────────────────────────────────────────────────────
ayuda() {
  cat <<EOF
Invasores de palabras — mecanografía estilo Galaga en la terminal

Uso: $(basename "$0") [opción]
  --reset   borra la tabla de puntajes
  --help    muestra esta ayuda

Variables:
  INVASORES_SCORES=/ruta/puntajes.txt   archivo de puntajes
                                         (por defecto: $SCORE_FILE)
  NO_COLOR=1                            desactiva los colores
EOF
}

menu_principal() {
  local op
  while true; do
    banner
    printf '     %s1)%s  %sJugar%s\n' "$BLU$BOLD" "$RST" "$GRN$BOLD" "$RST"
    printf '     %s2)%s  Instrucciones\n' "$BLU$BOLD" "$RST"
    printf '     %s3)%s  Tabla de puntajes\n' "$BLU$BOLD" "$RST"
    printf '     %s4)%s  Salir\n\n' "$BLU$BOLD" "$RST"
    printf '  Elige una opción : '
    IFS= read -r op || exit 0
    case "${op//[[:space:]]/}" in
      1) jugar ;;
      2) instrucciones ;;
      3) mostrar_puntajes; pausa_enter ;;
      4|s|S|q|Q)
        printf '\n\n  %s¡Hasta pronto! Gracias por jugar.%s\n\n' "$CYN" "$RST"
        exit 0 ;;
    esac
  done
}

# ─── 14. Inicio ────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help|--ayuda) ayuda; exit 0 ;;
  --reset)
    read -r -p "¿Borrar TODOS los puntajes? Escribe SI para confirmar: " resp_reset
    if [[ "$resp_reset" == "SI" ]]; then rm -f "$SCORE_FILE" && echo "Puntajes borrados."; else echo "Cancelado."; fi
    exit 0 ;;
esac

if (( ${#BANCO_PALABRAS[@]} == 0 )); then
  echo "El banco de palabras está vacío." >&2
  exit 1
fi

case "$(locale charmap 2>/dev/null)" in
  *UTF-8*|*utf8*) ;;
  *)
    printf '%sAviso:%s tu terminal no parece estar en UTF-8; las tildes y la ñ\n' "$YEL" "$RST"
    printf 'podrían no reconocerse bien. Prueba: export LANG=es_PE.UTF-8\n\n'
    sleep 2 ;;
esac

menu_principal
