#!/usr/bin/env bash
# ==============================================================
# PIXEL LAB — Editor de Pixel Art para terminal
# Versión: 3
#
# Coordenadas: COLUMNA,FILA
# Ejemplo:    o,12
#
# Características:
#   - Solo pinta en blanco.
#   - Lienzo siempre cuadrado.
#   - Máximo: 26 x 26 (A-Z / 1-26).
#   - Flechas izquierda/derecha, Inicio/Fin, Backspace y Delete
#     funcionan mediante readline.
#   - Flechas arriba/abajo recorren el historial de entradas.
# ==============================================================

ESC=$'\033'
CSI="${ESC}["
RST="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
WHITE="${CSI}97m"
CYAN="${CSI}96m"
GREEN="${CSI}92m"
YELLOW="${CSI}93m"
RED="${CSI}91m"
MAGENTA="${CSI}95m"
BLUE="${CSI}94m"

SAVE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/pixel-lab"
PROJECT_FILE="$SAVE_DIR/proyecto.pixel"
TEMP_FILE="$SAVE_DIR/.pixel.tmp"

CELL_WIDTH=2
MAX_SIZE=26

SIZE=0
ROWS=0
COLS=0
RUNNING=1
MESSAGE="Listo. Escribe columna,fila para pintar."
declare -a PIXELS

ORIGINAL_STTY=""

terminal_lines() {
    local n
    n=$(tput lines 2>/dev/null || printf '30')
    [[ "$n" =~ ^[0-9]+$ ]] || n=30
    printf '%s' "$n"
}

terminal_cols() {
    local n
    n=$(tput cols 2>/dev/null || printf '100')
    [[ "$n" =~ ^[0-9]+$ ]] || n=100
    printf '%s' "$n"
}

setup_dimensions() {
    local tl tc available_rows available_cols n

    tl=$(terminal_lines)
    tc=$(terminal_cols)

    # La interfaz usa hasta 13 líneas fuera del lienzo.
    available_rows=$((tl - 13))
    available_cols=$(((tc - 6) / CELL_WIDTH))

    (( available_rows < 4 )) && available_rows=4
    (( available_cols < 4 )) && available_cols=4

    n=$available_rows
    (( available_cols < n )) && n=$available_cols
    (( n > MAX_SIZE )) && n=$MAX_SIZE

    SIZE=$n
    ROWS=$SIZE
    COLS=$SIZE
}

terminal_start() {
    ORIGINAL_STTY=$(stty -g 2>/dev/null || true)
    # No cambiamos a modo raw: Bash readline necesita manejar la línea.
    printf '%s?25l' "$CSI"
    clear_screen
}

terminal_restore() {
    if [[ -n "$ORIGINAL_STTY" ]]; then
        stty "$ORIGINAL_STTY" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
    printf '%s0m%s?25h' "$CSI" "$CSI"
}

cleanup() {
    terminal_restore
}

trap cleanup EXIT
trap 'RUNNING=0' INT TERM

move_cursor() {
    printf '%s%d;%dH' "$CSI" "$1" "$2"
}

clear_screen() {
    printf '%s2J%sH' "$CSI" "$CSI"
}

pixel_index() {
    printf '%d' $((($1 - 1) * COLS + ($2 - 1)))
}

reset_canvas() {
    PIXELS=()
    local i total=$((ROWS * COLS))
    for ((i = 0; i < total; i++)); do
        PIXELS[i]=""
    done
}

toggle_pixel() {
    local idx
    idx=$(pixel_index "$1" "$2")

    # Si ya está pintado, vuelve a dejar la celda vacía.
    # Si está vacía, la pinta de blanco.
    if [[ "${PIXELS[idx]-}" == "1" ]]; then
        PIXELS[idx]=""
        return 1
    else
        PIXELS[idx]=1
        return 0
    fi
}

number_to_column() {
    local n=$1 ch
    if ((n < 1 || n > 26)); then
        return 1
    fi
    printf -v ch '%b' "$(printf '\\%03o' $((96 + n)))"
    printf '%s' "$ch"
}

column_to_number() {
    local s="${1^^}" code
    [[ "$s" =~ ^[A-Z]$ ]] || return 1
    printf -v code '%d' "'$s"
    printf '%d' $((code - 64))
}

draw_title() {
    move_cursor 1 1
    printf '%s2K' "$CSI"
    printf '%s%s PIXEL LAB %s%s  Editor de Pixel Art%s' \
        "$BOLD" "$CYAN" "$RST" "$DIM" "$RST"

    move_cursor 2 1
    printf '%s2K%s  Lienzo %s×%s   |   Columnas a-%s   |   Filas 1-%s   |   Color: BLANCO%s' \
        "$CSI" "$WHITE" "$COLS" "$ROWS" "$(number_to_column "$COLS")" "$ROWS" "$RST"
}

draw_ruler() {
    local c label

    move_cursor 3 1
    printf '%s2K%4s ' "$CSI" ""

    for ((c = 1; c <= COLS; c++)); do
        label=$(number_to_column "$c")
        printf '%-2s' "$label"
    done
    printf '%s' "$RST"

    for ((c = 1; c <= ROWS; c++)); do
        move_cursor $((3 + c)) 1
        printf '%s%3d%s ' "$DIM" "$c" "$RST"
    done
}

draw_canvas() {
    local r c idx p start_line=4 start_col=5

    for ((r = 1; r <= ROWS; r++)); do
        move_cursor $((start_line + r - 1)) "$start_col"
        for ((c = 1; c <= COLS; c++)); do
            idx=$(( (r - 1) * COLS + (c - 1) ))
            p="${PIXELS[idx]-}"

            if [[ "$p" == "1" ]]; then
                # Bloque blanco.
                printf '%b' '\033[48;2;255;255;255m  \033[0m'
            else
                # Celda vacía.
                printf '%b' '\033[48;2;24;24;30m  \033[0m'
            fi
        done
    done
}

footer_line() {
    local line=$1 text=$2 width=78
    move_cursor "$line" 1
    printf '%s2K' "$CSI"
    printf '%s%-*.*s%s' "$WHITE" "$width" "$width" "$text" "$RST"
}

draw_footer() {
    local base=$((ROWS + 5))
    local max_col
    max_col=$(number_to_column "$COLS")

    footer_line "$base"     '┌─ ENTRADA ───────────────────────────────────────────────────────────────────┐'
    footer_line $((base + 1)) "│  columna,fila   →   ejemplo: o,12         Rango: a-${max_col}, 1-${ROWS}     │"
    footer_line $((base + 2)) '│  ↑ ↓ historial   ← → mover   Inicio/Fin   Retroceso/Supr editar             │'
    footer_line $((base + 3)) '│  Comandos: guardar  cargar  limpiar  nuevo  ayuda  salir                   │'
    footer_line $((base + 4)) "│  Estado: ${MESSAGE}"
    footer_line $((base + 5)) '└─────────────────────────────────────────────────────────────────────────────┘'

}

show_help() {
    clear_screen
    printf '%s%sPIXEL LAB — INSTRUCCIONES%s\n\n' "$BOLD" "$CYAN" "$RST"

    printf '%sCOORDENADAS%s\n' "$YELLOW$BOLD" "$RST"
    printf '  Se escribe primero la %scolumna%s y después la %sfila%s.\n' "$WHITE" "$RST" "$WHITE" "$RST"
    printf '  Ejemplo: %so,12%s  → pinta la columna o, fila 12.\n\n' "$GREEN" "$RST"

    printf '%sLIENZO%s\n' "$YELLOW$BOLD" "$RST"
    printf '  Siempre es cuadrado y puede tener entre 4×4 y 26×26 celdas.\n'
    printf '  Columnas: a, b, c ... z\n'
    printf '  Filas:    1, 2, 3 ... 26\n'
    printf '  Todos los píxeles pintados son %sblancos%s.\n\n' "$WHITE" "$RST"

    printf '%sEDICIÓN DE ENTRADA%s\n' "$YELLOW$BOLD" "$RST"
    printf '  ← →     mover el cursor dentro de lo escrito\n'
    printf '  Inicio/Fin, Retroceso/Supr también funcionan\n'
    printf '  ↑ ↓     recorrer las entradas anteriores\n\n'

    printf '%sCOMANDOS%s\n' "$YELLOW$BOLD" "$RST"
    printf '  guardar   guarda el proyecto\n'
    printf '  cargar    carga el último proyecto\n'
    printf '  limpiar   borra el lienzo\n'
    printf '  nuevo     crea un lienzo cuadrado nuevo\n'
    printf '  ayuda     muestra esta pantalla\n'
    printf '  salir     vuelve al menú\n\n'

    printf '%sENTER%s para volver...' "$DIM" "$RST"
    printf '%s?25h' "$CSI"
    IFS= read -r _
    printf '%s?25l' "$CSI"
}

confirmar_prompt() {
    local prompt=$1 answer
    printf '%s?25h' "$CSI"
    move_cursor $((ROWS + 13)) 1
    printf '%s2K%s%s (s/n): ' "$CSI" "$YELLOW" "$prompt"
    IFS= read -r answer
    printf '%s?25l' "$CSI"
    [[ "${answer,,}" == s || "${answer,,}" == si || "${answer,,}" == sí ]]
}

save_project() {
    mkdir -p "$SAVE_DIR" 2>/dev/null || return 1

    {
        printf 'PIXELLAB_VERSION=2\n'
        printf 'ROWS=%q\nCOLS=%q\n' "$ROWS" "$COLS"
        local i
        for ((i = 0; i < ROWS * COLS; i++)); do
            [[ -n "${PIXELS[i]-}" ]] && printf 'PIXELS[%d]=1\n' "$i"
        done
    } > "$TEMP_FILE" && mv "$TEMP_FILE" "$PROJECT_FILE"
}

load_project() {
    [[ -f "$PROJECT_FILE" ]] || return 1
    grep -q '^PIXELLAB_VERSION=2$' "$PROJECT_FILE" 2>/dev/null || return 1

    # shellcheck disable=SC1090
    source "$PROJECT_FILE"

    [[ "$ROWS" =~ ^[0-9]+$ && "$COLS" =~ ^[0-9]+$ ]] || return 1
    ((ROWS >= 4 && ROWS <= MAX_SIZE && COLS == ROWS)) || return 1

    SIZE=$ROWS
    local total=$((ROWS * COLS)) i
    for ((i = 0; i < total; i++)); do
        [[ -v "PIXELS[$i]" ]] || PIXELS[i]=""
    done
    return 0
}

parse_command() {
    local input="$1" col_str row col

    # Quitar espacios para aceptar tanto "a,1" como "a, 1".
    input="${input//[[:space:]]/}"

    case "${input,,}" in
        guardar)
            if save_project; then
                MESSAGE="Proyecto guardado en ${PROJECT_FILE}"
            else
                MESSAGE="No se pudo guardar el proyecto."
            fi
            return
            ;;
        cargar)
            if load_project; then
                MESSAGE="Proyecto cargado: ${ROWS}×${COLS}."
            else
                MESSAGE="No hay un proyecto válido de versión 2."
            fi
            return
            ;;
        limpiar)
            reset_canvas
            MESSAGE="Lienzo limpio."
            return
            ;;
        nuevo)
            if confirmar_prompt '¿Crear un lienzo nuevo y perder el actual?'; then
                setup_dimensions
                reset_canvas
                MESSAGE="Nuevo lienzo: ${ROWS}×${COLS}."
            else
                MESSAGE="Operación cancelada."
            fi
            return
            ;;
        ayuda|help)
            show_help
            MESSAGE="Volviste al editor."
            return
            ;;
        salir|exit|quit)
            RUNNING=0
            return
            ;;
        "")
            MESSAGE="Escribe una coordenada, por ejemplo: o,12"
            return
            ;;
    esac

    if [[ "$input" =~ ^([A-Za-z]),([0-9]+)$ ]]; then
        col_str="${BASH_REMATCH[1]}"
        row="${BASH_REMATCH[2]}"
        col=$(column_to_number "$col_str") || {
            MESSAGE="Columna inválida. Usa una letra entre a y z."
            return
        }
    else
        MESSAGE="Formato incorrecto. Usa columna,fila; por ejemplo: o,12"
        return
    fi

    row=$((10#$row))

    if ((row < 1 || row > ROWS || col < 1 || col > COLS)); then
        MESSAGE="Fuera del lienzo. Rango: a-$(number_to_column "$COLS"), 1-${ROWS}."
        return
    fi

    if toggle_pixel "$row" "$col"; then
        MESSAGE="Pintado: $(number_to_column "$col"),${row}  ·  blanco"
    else
        MESSAGE="Borrado: $(number_to_column "$col"),${row}"
    fi
}

show_splash() {
    clear_screen

    printf '%s%s' "$CYAN" "$BOLD"
    cat <<'ART'
╔══════════════════════════════════════════════════════════╗
║                       PIXEL LAB                         ║
║                 TERMINAL EDITION · v3                  ║
╚══════════════════════════════════════════════════════════╝
ART
    printf '%s\n' "$RST"

    printf '  %s1)%s  Nuevo proyecto\n' "$CYAN$BOLD" "$RST"
    printf '  %s2)%s  Continuar proyecto guardado\n' "$CYAN$BOLD" "$RST"
    printf '  %s3)%s  Instrucciones\n' "$CYAN$BOLD" "$RST"
    printf '  %s4)%s  Salir\n\n' "$CYAN$BOLD" "$RST"

    printf '  %sRegla:%s columna,fila  →  %so,12%s\n' "$DIM" "$RST" "$GREEN" "$RST"
    printf '  %sLienzo:%s cuadrado, máximo 26×26  ·  Color: %sBLANCO%s\n\n' "$DIM" "$RST" "$WHITE" "$RST"
    printf '  Selecciona: '
}

read_command() {
    local command=""

    # Bash readline se encarga de ←→, Backspace, Delete, Home, End y ↑↓.
    IFS= read -e -r command || return 1

    # Readline deja la entrada escrita en la terminal al pulsar Enter.
    # Volvemos a esa línea y la limpiamos inmediatamente.
    move_cursor $((ROWS + 12)) 1
    printf '%s2K' "$CSI"

    # Guardamos la entrada para que ↑ y ↓ la recuperen.
    [[ -n "$command" ]] && history -s "$command"
    REPLY=$command
    return 0
}

editor_loop() {
    terminal_start
    set -o history 2>/dev/null || true
    HISTCONTROL=ignoredups

    while ((RUNNING)); do
        draw_title
        draw_ruler
        draw_canvas
        draw_footer

        move_cursor $((ROWS + 12)) 1

        local command
        if ! read_command; then
            break
        fi

        parse_command "$REPLY"
    done

    terminal_restore
    RUNNING=1
}

new_project() {
    setup_dimensions
    reset_canvas
    MESSAGE="Lienzo ${ROWS}×${COLS}. Escribe columna,fila; ejemplo: o,12"
    editor_loop
}

continue_project() {
    if ! load_project; then
        printf '\n%sNo hay ningún proyecto v2 guardado todavía.%s\n' "$RED" "$RST"
        printf 'Pulsa ENTER... '
        IFS= read -r _
        return
    fi

    MESSAGE="Proyecto cargado. Continúa dibujando."
    editor_loop
}

main_menu() {
    while true; do
        show_splash
        local op
        IFS= read -r op
        case "$op" in
            1) new_project ;;
            2) continue_project ;;
            3) show_help ;;
            4|q|Q)
                clear_screen
                printf '%sGracias por crear con PIXEL LAB.%s\n\n' "$CYAN$BOLD" "$RST"
                printf '%sby Profe Luis para sus alumnos%s\n' "$WHITE" "$RST"
                return
                ;;
        esac
    done
}

if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'PIXEL LAB necesita una terminal interactiva.\n' >&2
    exit 1
fi

main_menu
