#!/usr/bin/env bash
# ================================================================
# DISQUETE 7 — AVENTURA INTERACTIVA DE TERMINAL
# Estilo: aventuras DOS / juegos de disquete de los 80-90
# Público: aprox. 12–16 años
#
# Requiere: Bash 5+
#
# Ejecutar:
#   chmod +x disquete7.sh
#   ./disquete7.sh
#
# También:
#   TYPING=0 ./disquete7.sh     # texto instantáneo
#   NO_COLOR=1 ./disquete7.sh   # sin colores
# ================================================================

# No usar "set -e": algunas operaciones de terminal/read pueden devolver
# códigos distintos de cero sin que eso signifique que el juego deba cerrar.

ESC=$'\033'
CSI="${ESC}["
RST="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
RED="${CSI}91m"
GREEN="${CSI}92m"
YELLOW="${CSI}93m"
BLUE="${CSI}94m"
MAGENTA="${CSI}95m"
CYAN="${CSI}96m"
WHITE="${CSI}97m"

if [[ -n "${NO_COLOR:-}" ]]; then
    RST=""; BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""
    BLUE=""; MAGENTA=""; CYAN=""; WHITE=""
fi

TYPING="${TYPING:-1}"
SAVE_FILE="${DISQUETE7_SAVE:-$HOME/.local/share/disquete7/partida.sav}"

# ------------------------------------------------------------
# Estado de la partida
# ------------------------------------------------------------
NOMBRE="Alex"
CONFIANZA=0
HONESTIDAD=0
VALENTIA=0
EMPATIA=0
REPUTACION=0
CURIOSIDAD=0
DINERO=8
PRESION=0
TIEMPO=0

MATEO=0
VALERIA=0
ERIKA=0
PROFE=0

TIENE_DISQUETE=0
VIO_ARCHIVO=0
COPIA_HECHA=0
AYUDO_MATEO=0
AYUDO_VALERIA=0
DEFENDIO_ERIKA=0
CONFESO=0
MINTIO=0
PUBLIQUE=0
BORRO_ARCHIVO=0
REPARO_ARCHIVO=0
ACEPTO_DINERO=0
RECHAZO_DINERO=0
PRESENTO_PROYECTO=0
ENTREGO_DISQUETE=0
GUARDO_SECRETO=0
PIDIO_AYUDA=0
CULPA=0
FINAL_ID=""

# ------------------------------------------------------------
# Utilidades básicas
# ------------------------------------------------------------
limpiar() {
    printf '%s' "${CSI}2J${CSI}H"
}

pausa() {
    printf '\n%s[ ENTER para continuar ]%s ' "$DIM" "$RST"
    IFS= read -r _
}

linea() {
    printf '%s%s%s\n' "$DIM" '------------------------------------------------------------' "$RST"
}

escribir() {
    local texto="${1-}"
    if [[ "$TYPING" == "0" ]]; then
        printf '%s\n' "$texto"
        return
    fi
    local i ch
    for ((i=0; i<${#texto}; i++)); do
        ch="${texto:i:1}"
        printf '%s' "$ch"
        sleep 0.009
    done
    printf '\n'
}

escribir_lento() {
    local texto="${1-}"
    if [[ "$TYPING" == "0" ]]; then
        printf '%s\n' "$texto"
        return
    fi
    local i ch
    for ((i=0; i<${#texto}; i++)); do
        ch="${texto:i:1}"
        printf '%s' "$ch"
        sleep 0.022
    done
    printf '\n'
}

titulo() {
    limpiar
    printf '%s' "$CYAN"
    cat <<'EOF'
  ██████╗ ██╗███████╗ ██████╗ ██╗   ██╗███████╗████████╗███████╗
  ██╔══██╗██║██╔════╝██╔═══██╗██║   ██║██╔════╝╚══██╔══╝██╔════╝
  ██║  ██║██║███████╗██║   ██║██║   ██║█████╗     ██║   █████╗
  ██║  ██║██║╚════██║██║   ██║╚██╗ ██╔╝██╔══╝     ██║   ██╔══╝
  ██████╔╝██║███████║╚██████╔╝ ╚████╔╝ ███████╗   ██║   ███████╗
  ╚═════╝ ╚═╝╚══════╝ ╚═════╝   ╚═══╝  ╚══════╝   ╚═╝   ╚══════╝
                           [ DISQUETE 7 ]
EOF
    printf '%s' "$RST"
}

ascii_diskette() {
    printf '%s' "$MAGENTA"
    cat <<'EOF'
             .----------------------------------.
            /  .------------------------------. /|
           /  /                              / / |
          /  /        D I S K E T T E       / /  |
         /  /            [ 7 ]              / /   |
        /  /                                / /    |
       /  '--------------------------------' /     |
      /______________________________________ /      |
      |                                      |      |
      |             .------------.           |      |
      |             |            |           |      |
      |             '------------'           |      |
      |                                      |      |
      '--------------------------------------'      |
       \__________________________________________/
EOF
    printf '%s' "$RST"
}

ascii_lab() {
    printf '%s' "$BLUE"
    cat <<'EOF'
       _________________________________________________
      /                                                 \
     | [PC-01]       [PC-02]       [PC-03]             |
     |  ______        ______        ______              |
     | |      |      |      |      |      |             |
     | |______|      |______|      |______|             |
     |                                                 |
     |       ____         ____          ____           |
     |      |____|       |____|        |____|          |
     |___________ MESA DEL LABORATORIO _______________|
                  |___________________|
                  |___________________|
EOF
    printf '%s' "$RST"
}

ascii_corridor() {
    printf '%s' "$YELLOW"
    cat <<'EOF'
             __________________________________
            |  AULA 1  |  AULA 2  |  DIRECCIÓN |
            |-----------+-----------+------------|
            |                                      |
            |              PASILLO                 |
            |                                      |
            |      ____              ____          |
            |     |    |            |    |          |
            |     |____|            |____|          |
            |                                      |
            |______________      _________________|
                           |    |
                           |____|
EOF
    printf '%s' "$RST"
}

ascii_computer() {
    printf '%s' "$GREEN"
    cat <<'EOF'
                  __________________________
                 | C:\> DIR                 |
                 |                           |
                 | AVENTURA EXE              |
                 | BACKUP7  DAT              |
                 | MATEO   TXT               |
                 |                           |
                 | C:\> _                     |
                 |___________________________|
                      |               |
                      |_______________|
                         /_________\
EOF
    printf '%s' "$RST"
}

ascii_school() {
    printf '%s' "$WHITE"
    cat <<'EOF'
                 __________________________________
                |                                  |
                |          COLEGIO NUEVA          |
                |            ESPERANZA             |
                |__________________________________|
                |  ___      ___      ___      ___ |
                | |   |    |   |    |   |    |   ||
                | |___|    |___|    |___|    |___||
                |                                  |
                |            [ PUERTA ]             |
                |__________________________________|
EOF
    printf '%s' "$RST"
}

ascii_end() {
    printf '%s' "$CYAN"
    cat <<'EOF'
                 +----------------------+
                 |      FIN DEL JUEGO    |
                 |       DISQUETE 7      |
                 +----------------------+
EOF
    printf '%s' "$RST"
}

# ------------------------------------------------------------
# Guardado / carga
# ------------------------------------------------------------
guardar() {
    mkdir -p "$(dirname "$SAVE_FILE")" 2>/dev/null || return 1
    {
        declare -p NOMBRE CONFIANZA HONESTIDAD VALENTIA EMPATIA REPUTACION
        declare -p CURIOSIDAD DINERO PRESION TIEMPO MATEO VALERIA ERIKA PROFE
        declare -p TIENE_DISQUETE VIO_ARCHIVO COPIA_HECHA AYUDO_MATEO
        declare -p AYUDO_VALERIA DEFENDIO_ERIKA CONFESO MINTIO PUBLIQUE
        declare -p BORRO_ARCHIVO REPARO_ARCHIVO ACEPTO_DINERO RECHAZO_DINERO
        declare -p PRESENTO_PROYECTO ENTREGO_DISQUETE GUARDO_SECRETO
        declare -p PIDIO_AYUDA CULPA FINAL_ID
    } > "$SAVE_FILE"
}

cargar() {
    [[ -f "$SAVE_FILE" ]] || return 1
    # El archivo solo se crea localmente con declare -p, así que su contenido
    # tiene formato controlado por el propio juego.
    # shellcheck disable=SC1090
    source "$SAVE_FILE"
    return 0
}

borrar_guardado() {
    rm -f "$SAVE_FILE" 2>/dev/null
}

# ------------------------------------------------------------
# Estado / HUD
# ------------------------------------------------------------
estado() {
    printf '\n%sESTADO%s\n' "$YELLOW$BOLD" "$RST"
    printf '  Reputación : %2d   Confianza : %2d   Valentía : %2d\n' \
        "$REPUTACION" "$CONFIANZA" "$VALENTIA"
    printf '  Empatía    : %2d   Honestidad: %2d   Curiosidad: %2d\n' \
        "$EMPATIA" "$HONESTIDAD" "$CURIOSIDAD"
    printf '  Dinero     : S/ %-2d  Presión   : %2d\n' "$DINERO" "$PRESION"
}

pregunta_nombre() {
    printf '\n¿Cómo se llama tu personaje? [ENTER = Alex] : '
    IFS= read -r NOMBRE
    [[ -z "$NOMBRE" ]] && NOMBRE="Alex"
    NOMBRE="${NOMBRE//|/}"
    NOMBRE="${NOMBRE//[[:cntrl:]]/}"
    NOMBRE="${NOMBRE:0:18}"
}

elegir() {
    # elegir "Pregunta" "A" "B" "C"
    local pregunta="$1"
    shift
    local opciones=("$@")
    local r
    while true; do
        printf '\n%s%s%s\n' "$WHITE$BOLD" "$pregunta" "$RST"
        local i
        for ((i=0; i<${#opciones[@]}; i++)); do
            printf '  %s%d)%s %s\n' "$CYAN$BOLD" "$((i+1))" "$RST" "${opciones[i]}"
        done
        printf '\n  Tu elección: '
        IFS= read -r r
        case "$r" in
            1|2|3|4) CHOICE="$r"; return 0 ;;
            *) printf '%sElige 1, 2, 3 o 4.%s\n' "$RED" "$RST" ;;
        esac
    done
}

confirmar() {
    local p="$1" r
    while true; do
        printf '%s (s/n): ' "$p"
        IFS= read -r r
        case "${r,,}" in
            s|si|sí|y|yes) return 0 ;;
            n|no) return 1 ;;
        esac
    done
}

# ------------------------------------------------------------
# INTRO / BOOT
# ------------------------------------------------------------
pantalla_boot() {
    limpiar
    printf '%s' "$GREEN"
    cat <<'EOF'
  Award BIOS 1997
  (C) 1997 Award Software

  Detecting Primary Master  ....... ST-31270A
  Memory Test ..................... 32768K OK
  Keyboard ......................... OK
  Floppy Drive A: .................. OK

  A:
  A:\> DIR

   COMMAND  COM
   AVENTURA EXE
   README   TXT
   DISCO7   DAT

  A:\> AVENTURA.EXE

EOF
    printf '%s' "$RST"
    sleep 1
}

introduccion() {
    pantalla_boot
    titulo
    ascii_diskette
    escribir_lento "Año 1997."
    escribir "El laboratorio de informática de tu colegio va a cerrar por mantenimiento."
    escribir "En una caja olvidada encuentras un disquete con una etiqueta:"
    printf '\n%s' "$YELLOW$BOLD"
    cat <<'EOF'
                  =============================
                     NO ABRIR — RESPALDO 7
                     SI FALLA, NO COPIAR
                  =============================
EOF
    printf '%s\n' "$RST"
    escribir "Hay algo raro en que un disquete viejo diga que no se copie."
    escribir "Y, por supuesto, lo primero que quieres hacer es copiarlo."
    pausa
    preguntar_nombre
}

# ------------------------------------------------------------
# Capítulos
# ------------------------------------------------------------
capitulo_1() {
    titulo
    ascii_lab
    printf '\n%sCAPÍTULO 1 — EL ARCHIVO QUE NO EXISTÍA%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "Martes, 4:17 p. m."
    escribir "El profesor Salcedo te pidió apagar las computadoras del laboratorio."
    escribir "Tus compañeros ya se fueron. Solo quedan tú, Mateo, Valeria y Erika."
    escribir "Mateo levanta el disquete."
    printf '\n%sMATEO:%s\n' "$GREEN$BOLD" "$RST"
    escribir_lento "\"Esto tiene más pinta de problema que de tarea.\""
    printf '\n%sVALERIA:%s\n' "$MAGENTA$BOLD" "$RST"
    escribir "\"No lo abras. El profe dijo que nadie toque la carpeta de respaldos.\""
    printf '\n%sERIKA:%s\n' "$YELLOW$BOLD" "$RST"
    escribir "\"¿Y si solo miramos? No vamos a romper nada... ¿cierto?\""

    elegir "¿Qué haces?" \
        "Lo abro. Si dice que no, probablemente es por una razón aburrida." \
        "Le hago caso a Valeria y lo guardo." \
        "Propongo hacer una copia sin abrir el original." \
        "Pregunto primero al profesor."

    case "$CHOICE" in
        1)
            VIO_ARCHIVO=1
            CURIOSIDAD=$((CURIOSIDAD+2))
            PRESION=$((PRESION+1))
            escribir "Insertas el disquete."
            ascii_computer
            escribir "Aparece un archivo: PROYECTO_FERIA.BAK"
            escribir "Y otro: NO_BORRAR.TXT"
            escribir "Mateo sonríe. Valeria deja de sonreír."
        ;;
        2)
            HONESTIDAD=$((HONESTIDAD+1))
            CONFIANZA=$((CONFIANZA+2))
            escribir "Guardas el disquete en el cajón."
            escribir "Mateo hace una mueca, pero Valeria te lo agradece."
            escribir "Cinco minutos después, alguien grita desde el pasillo."
            escribir "Algo pasó con las copias de la feria."
        ;;
        3)
            CURIOSIDAD=$((CURIOSIDAD+1))
            HONESTIDAD=$((HONESTIDAD+1))
            escribir "Haces una copia del disquete sin abrir los archivos."
            escribir "El disquete original queda intacto."
            escribir "Mateo te mira como si acabaras de inventar la prudencia."
            COPIA_HECHA=1
        ;;
        4)
            PROFE=$((PROFE+1))
            HONESTIDAD=$((HONESTIDAD+2))
            escribir "Sales a buscar al profesor."
            escribir "Pero cuando vuelves, Mateo ya está mirando el disquete."
            escribir "Dice que solo lo puso un segundo."
            TIENE_DISQUETE=1
        ;;
    esac

    TIENE_DISQUETE=1
    guardar
    pausa
}

capitulo_2() {
    titulo
    ascii_corridor
    printf '\n%sCAPÍTULO 2 — EL PASILLO%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "7:02 a. m. del día siguiente."
    escribir "En el grupo del salón aparece un mensaje anónimo:"
    printf '\n%s\"ALGUIEN BORRÓ EL PROYECTO DE LA FERIA.\"%s\n' "$RED" "$RST"
    escribir "La feria es en dos días."
    escribir "Valeria está pálida: ella hizo casi todo el proyecto."
    escribir "Mateo dice que el archivo estaba perfecto ayer."
    escribir "Erika te manda un mensaje privado:"
    escribir "\"Yo vi a alguien salir del laboratorio después de nosotros.\""

    elegir "¿A quién le das prioridad?" \
        "A Valeria: recuperar el proyecto." \
        "A Mateo: averiguar qué hizo realmente." \
        "A Erika: preguntarle a quién vio." \
        "A ti: primero quieres revisar el disquete."

    case "$CHOICE" in
        1)
            AYUDO_VALERIA=1
            EMPATIA=$((EMPATIA+2))
            CONFIANZA=$((CONFIANZA+1))
            escribir "Valeria te entrega una memoria USB con lo poco que le queda."
            escribir "\"No necesito que me salves. Solo necesito que no te rindas conmigo.\""
        ;;
        2)
            AYUDO_MATEO=1
            CURIOSIDAD=$((CURIOSIDAD+1))
            escribir "Mateo te cuenta algo que no había dicho."
            escribir "\"Sí, entré después. Pero no borré nada.\""
            escribir "Luego añade, bajito: \"Bueno... casi nada.\""
        ;;
        3)
            DEFENDIO_ERIKA=1
            EMPATIA=$((EMPATIA+2))
            escribir "Erika duda."
            escribir "\"Vi una chaqueta de tercero. Azul. La de Joaquín, creo.\""
            escribir "No está segura. Decidir acusar a alguien sería otra cosa."
        ;;
        4)
            CURIOSIDAD=$((CURIOSIDAD+2))
            escribir "Revisas el disquete."
            ascii_computer
            escribir "El archivo PROYECTO_FERIA.BAK sigue allí."
            escribir "Pero la fecha es de hace tres días."
            escribir "Eso significa que ayer alguien sí trabajó sobre otra copia."
        ;;
    esac

    PRESION=$((PRESION+1))
    guardar
    pausa
}

capitulo_3() {
    titulo
    ascii_computer
    printf '\n%sCAPÍTULO 3 — LA COPIA%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "En el laboratorio encuentras dos archivos:"
    printf '\n%sPROYECTO_FERIA.BAK%s\n%sPROYECTO_FERIA_FINAL.BAK%s\n\n' \
        "$GREEN" "$RST" "$GREEN" "$RST"
    escribir "El segundo no estaba allí ayer."
    escribir "Mateo aparece detrás de ti."

    printf '\n%sMATEO:%s \"Puedo arreglar esto. Déjame intentarlo.\"%s\n' "$GREEN$BOLD" "$RST" "$RST"
    printf '%sVALERIA:%s \"No. Ya hizo suficientes cosas. Que venga el profesor.\"%s\n' "$MAGENTA$BOLD" "$RST" "$RST"

    elegir "Tienes unos minutos antes de la clase." \
        "Dejo que Mateo pruebe." \
        "Llamo al profesor." \
        "Intento reparar el archivo yo." \
        "Hago una copia y seguimos después."

    case "$CHOICE" in
        1)
            MATEO=$((MATEO+2))
            CONFIANZA=$((CONFIANZA+2))
            escribir "Mateo prueba una herramienta vieja."
            sleep 0.5
            escribir "El archivo abre..."
            escribir "...con un gráfico de una papa gigante."
            printf '\n%sMATEO:%s \"Bueno. Esa no era la versión correcta.\"%s\n' "$GREEN$BOLD" "$RST" "$RST"
            escribir "Se ríen. Por primera vez hoy."
            REPARO_ARCHIVO=1
        ;;
        2)
            PROFE=$((PROFE+2))
            HONESTIDAD=$((HONESTIDAD+1))
            escribir "Llamas al profesor Salcedo."
            escribir "Mira los archivos y frunce el ceño."
            escribir "\"Antes de buscar culpables, busquemos una versión sana.\""
            escribir "Te sorprende que no pregunte '¿quién fue?' primero."
            PIDIO_AYUDA=1
        ;;
        3)
            CURIOSIDAD=$((CURIOSIDAD+2))
            VALENTIA=$((VALENTIA+1))
            escribir "Decides intentarlo."
            escribir "Después de varios comandos consigues abrir una copia dañada."
            escribir "La mitad del proyecto está allí."
            REPARO_ARCHIVO=1
        ;;
        4)
            COPIA_HECHA=1
            HONESTIDAD=$((HONESTIDAD+1))
            escribir "Copias ambos archivos."
            escribir "No es heroico. Tampoco hace falta que lo sea."
            escribir "Ahora puedes equivocarte sin destruirlo todo."
        ;;
    esac

    if (( REPARO_ARCHIVO == 1 )); then
        COPIA_HECHA=1
        escribir "Guardas una copia antes de tocar cualquier otra cosa."
    fi

    guardar
    pausa
}

capitulo_4() {
    titulo
    ascii_corridor
    printf '\n%sCAPÍTULO 4 — EL TERCERO%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "Joaquín aparece durante el recreo."
    escribir "\"¿Por qué están preguntando por el laboratorio?\""
    escribir "Erika mira su chaqueta azul."
    escribir "Es exactamente como la describió."

    printf '\n%sJOAQUÍN:%s\n' "$RED$BOLD" "$RST"
    escribir "\"Entré porque necesitaba imprimir. No toqué el proyecto.\""
    escribir "\"Bueno... vi a alguien allí.\""
    escribir "Silencio."

    elegir "¿Qué le preguntas?" \
        "¿A quién viste?" \
        "¿Por qué no lo dijiste antes?" \
        "¿Puedes demostrar que estabas imprimiendo?" \
        "No lo presiono; mejor buscamos el registro de la PC."

    case "$CHOICE" in
        1)
            VALENTIA=$((VALENTIA+1))
            escribir "Joaquín mira alrededor."
            escribir "\"A un alumno de quinto. Pero no quiero meter a nadie en problemas.\""
            escribir "No te da un nombre."
        ;;
        2)
            EMPATIA=$((EMPATIA+1))
            escribir "Joaquín baja la voz."
            escribir "\"Porque todos creen que si sabes algo, tú fuiste.\""
            escribir "Esa frase te queda dando vueltas."
        ;;
        3)
            REPUTACION=$((REPUTACION-1))
            escribir "Joaquín enseña una hoja de impresión."
            escribir "Sirve como pista, pero no como prueba."
        ;;
        4)
            CURIOSIDAD=$((CURIOSIDAD+2))
            HONESTIDAD=$((HONESTIDAD+1))
            escribir "Van a buscar el historial de la computadora."
            escribir "La sesión muestra algo extraño: se conectó una USB a las 6:51 p. m."
            escribir "No dice de quién era."
        ;;
    esac

    guardar
    pausa
}

capitulo_5() {
    titulo
    ascii_lab
    printf '\n%sCAPÍTULO 5 — LA ELECCIÓN INCÓMODA%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "Encuentras el archivo de la USB."
    escribir "No contiene el proyecto borrado."
    escribir "Contiene una copia de seguridad... y un mensaje escrito por Valeria."
    printf '\n%sNOTA.TXT%s\n' "$YELLOW$BOLD" "$RST"
    escribir "\"Si algo sale mal, no culpen a nadie todavía.\""
    escribir "Más abajo hay otra línea:"
    escribir "\"Yo hice una copia porque tenía miedo de perderlo todo.\""

    if (( AYUDO_VALERIA == 1 )); then
        escribir "Valeria te había confiado esa USB."
    else
        escribir "Valeria no sabía que habías encontrado esa nota."
    fi

    elegir "¿Qué haces con la nota?" \
        "Se la devuelvo a Valeria sin leer más." \
        "La enseño al profesor." \
        "La guardo por si luego hace falta." \
        "Se la enseño a Mateo y le pregunto qué piensa."

    case "$CHOICE" in
        1)
            EMPATIA=$((EMPATIA+2))
            CONFIANZA=$((CONFIANZA+2))
            escribir "Cierras el archivo."
            escribir "No todo secreto necesita convertirse en evidencia."
            ;;
        2)
            HONESTIDAD=$((HONESTIDAD+2))
            PROFE=$((PROFE+1))
            PIDIO_AYUDA=1
            escribir "Se la enseñas al profesor."
            escribir "Él dice algo inesperado:"
            escribir "\"Esto no prueba que nadie haya robado nada. Solo prueba que alguien tuvo miedo.\""
            ;;
        3)
            CULPA=$((CULPA+1))
            escribir "La guardas."
            escribir "Por ahora no dices nada."
            ;;
        4)
            MATEO=$((MATEO+1))
            escribir "Mateo lee la nota."
            escribir "\"Creo que Valeria intentaba proteger el proyecto. Igual que tú.\""
            escribir "Luego se queda pensando."
    esac

    guardar
    pausa
}

capitulo_6() {
    titulo
    ascii_corridor
    printf '\n%sCAPÍTULO 6 — EL RUMOR%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "El rumor crece."
    escribir "Ahora dicen que alguien copió el proyecto de otro colegio."
    escribir "No es cierto. Pero ya hay alumnos riéndose de Valeria."
    escribir "Erika propone contar toda la historia frente al salón."
    escribir "Mateo propone una idea mucho peor: inventar una historia absurda para que el rumor se muera."

    elegir "¿Qué haces?" \
        "Defiendo a Valeria públicamente." \
        "Invento la historia absurda con Mateo." \
        "No digo nada: los rumores se cansan solos." \
        "Le pido a Erika que hable con el profesor."

    case "$CHOICE" in
        1)
            DEFENDIO_ERIKA=1
            VALENTIA=$((VALENTIA+2))
            REPUTACION=$((REPUTACION+2))
            escribir "Dices delante del grupo:"
            escribir "\"No sabemos qué pasó. Así que dejemos de acusar gente por diversión.\""
            escribir "No arreglas todo. Pero el salón se queda callado."
        ;;
        2)
            MATEO=$((MATEO+2))
            REPUTACION=$((REPUTACION+1))
            escribir "Inventan una historia ridícula."
            escribir "\"El proyecto fue robado por un pato hacker.\""
            escribir "Sorprendentemente, funciona."
            escribir "Durante una hora, nadie habla de otra cosa."
            escribir "El profesor no encuentra el chiste."
        ;;
        3)
            REPUTACION=$((REPUTACION-1))
            CULPA=$((CULPA+1))
            escribir "No dices nada."
            escribir "El rumor pasa de una persona a otra."
            escribir "Y cada repetición lo vuelve más grande."
        ;;
        4)
            EMPATIA=$((EMPATIA+1))
            PROFE=$((PROFE+1))
            escribir "Erika termina hablando con el profesor."
            escribir "Él decide investigar el registro del laboratorio."
    esac

    guardar
    pausa
}

capitulo_7() {
    titulo
    ascii_school
    printf '\n%sCAPÍTULO 7 — EL PRECIO%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "El profesor encuentra una respuesta."
    escribir "El proyecto no fue borrado por una persona."
    escribir "Durante una actualización, una carpeta temporal reemplazó otra."
    escribir "Pero hay una pregunta pendiente: ¿por qué apareció una copia nueva con otro nombre?"
    escribir "Mateo levanta la mano."
    escribir "\"Porque yo la guardé.\""

    escribir "Todos lo miran."
    escribir "Mateo suspira."
    escribir "\"Pensé que si la guardaba en otro lugar, nadie podría borrarla.\""
    escribir "\"Luego toqué la carpeta equivocada.\""
    escribir "No parece un villano. Parece un chico que cometió un error."

    elegir "¿Qué haces?" \
        "Digo la verdad completa por Mateo." \
        "Dejo que él lo explique." \
        "Le digo al profesor que fue un accidente y ya." \
        "No lo cubro ni lo entrego: le pregunto qué quiere decir."

    case "$CHOICE" in
        1)
            HONESTIDAD=$((HONESTIDAD+2))
            VALENTIA=$((VALENTIA+1))
            CONFIANZA=$((CONFIANZA+1))
            CONFESO=1
            escribir "Cuentas lo que sabes."
            escribir "Mateo asiente."
            escribir "\"Sí. Fui yo. Pero no quería borrar nada.\""
        ;;
        2)
            EMPATIA=$((EMPATIA+2))
            CONFIANZA=$((CONFIANZA+2))
            escribir "Dejas que Mateo hable."
            escribir "Le cuesta."
            escribir "Pero lo hace."
            CONFESO=1
        ;;
        3)
            HONESTIDAD=$((HONESTIDAD+1))
            escribir "Explicas que fue un accidente."
            escribir "El profesor responde:"
            escribir "\"Un accidente sigue necesitando una solución.\""
        ;;
        4)
            CURIOSIDAD=$((CURIOSIDAD+1))
            escribir "Le preguntas a Mateo qué intentaba hacer realmente."
            escribir "\"Quería que el proyecto tuviera una copia por si fallábamos.\""
            escribir "Por primera vez, nadie se ríe."
    esac

    if (( CONFESO == 1 )); then
        PRESION=$((PRESION-1))
        (( PRESION < 0 )) && PRESION=0
    fi

    guardar
    pausa
}

capitulo_8() {
    titulo
    ascii_lab
    printf '\n%sCAPÍTULO 8 — LA ÚLTIMA TARDE%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "Falta una tarde para la feria."
    escribir "Tienen casi todo listo."
    escribir "Pero el proyecto todavía tiene una parte incompleta."
    escribir "El profesor les ofrece una opción:"
    escribir "\"Pueden presentar una versión sencilla y honesta,\""
    escribir "\"o pueden intentar reconstruir la versión grande que tenían.\""

    elegir "¿Qué camino toma el equipo?" \
        "Versión sencilla: funciona y llegamos a tiempo." \
        "Reconstruimos la versión grande." \
        "Dividimos el trabajo y hacemos ambas." \
        "Cancelamos la parte rota y presentamos solo los resultados."

    case "$CHOICE" in
        1)
            HONESTIDAD=$((HONESTIDAD+2))
            PRESION=$((PRESION-1))
            PRESENTO_PROYECTO=1
            escribir "Simplifican el proyecto."
            escribir "No queda espectacular."
            escribir "Pero funciona."
        ;;
        2)
            CURIOSIDAD=$((CURIOSIDAD+2))
            PRESION=$((PRESION+2))
            PRESENTO_PROYECTO=1
            escribir "Se quedan hasta tarde."
            escribir "Las pantallas se llenan de errores."
            escribir "Mateo consigue reparar una parte."
            REPARO_ARCHIVO=1
        ;;
        3)
            VALENTIA=$((VALENTIA+1))
            EMPATIA=$((EMPATIA+1))
            PRESENTO_PROYECTO=1
            escribir "Se reparten el problema."
            escribir "Por primera vez, nadie intenta hacerlo todo solo."
        ;;
        4)
            HONESTIDAD=$((HONESTIDAD+2))
            PRESENTO_PROYECTO=1
            escribir "Quitan la parte que no pueden defender."
            escribir "El proyecto queda pequeño, pero sólido."
    esac

    if (( PRESION >= 4 )); then
        escribir "Aun así, el cansancio empieza a notarse."
    fi

    guardar
    pausa
}

capitulo_9() {
    titulo
    ascii_school
    printf '\n%sCAPÍTULO 9 — LA FERIA%s\n\n' "$CYAN$BOLD" "$RST"

    escribir "Viernes. Feria de Ciencias."
    escribir "Hay proyectos con volcanes, sensores, carteles y una máquina hecha con LEGO."
    escribir "Ustedes tienen su mesa."
    escribir "Un jurado se acerca."

    if (( PRESENTO_PROYECTO == 1 )); then
        escribir "\"Explíquenme qué pasó con la versión original.\""
        escribir "Valeria te mira."
        escribir "Mateo mira al suelo."
        escribir "Esta es la última decisión."

        elegir "¿Qué respondes?" \
            "Contamos toda la historia, incluido el error." \
            "Solo explicamos el proyecto final." \
            "Decimos que fue un problema técnico y seguimos." \
            "Dejo que Valeria responda por el equipo."

        case "$CHOICE" in
            1)
                HONESTIDAD=$((HONESTIDAD+3))
                VALENTIA=$((VALENTIA+2))
                CONFIANZA=$((CONFIANZA+2))
                escribir "Cuentas la historia."
                escribir "El jurado escucha sin interrumpir."
                escribir "Luego pregunta qué aprendieron."
                escribir "Esta vez, ninguno necesita inventar una respuesta."
            ;;
            2)
                HONESTIDAD=$((HONESTIDAD+1))
                escribir "Hablas de lo que funciona."
                escribir "Es correcto, pero incompleto."
                escribir "El jurado toma nota."
            ;;
            3)
                MINTIO=1
                CULPA=$((CULPA+2))
                REPETICION=$((REPETICION+1))
                escribir "Dices que fue un fallo técnico."
                escribir "El jurado pregunta una cosa más."
                escribir "\"¿Y por qué hay dos copias con fechas diferentes?\""
                escribir "Silencio."
            ;;
            4)
                EMPATIA=$((EMPATIA+1))
                escribir "Le das la palabra a Valeria."
                escribir "Ella respira y cuenta la historia."
                escribir "No dice todo, pero tampoco miente."
            ;;
        esac
    fi

    guardar
    pausa
}

# ------------------------------------------------------------
# Finales
# ------------------------------------------------------------
determinar_final() {
    # 10 finales. No hay "bueno/malo" único: cada uno nace de decisiones.

    if (( MINTIO == 1 && CULPA >= 2 )); then
        FINAL_ID="el_eco"
    elif (( HONESTIDAD >= 8 && CONFIANZA >= 6 && EMPATIA >= 5 )); then
        FINAL_ID="la_verdad"
    elif (( REPUTACION >= 3 && CURIOSIDAD >= 5 && REPARO_ARCHIVO == 1 )); then
        FINAL_ID="el_hacker"
    elif (( MATEO >= 4 && AYUDO_MATEO == 1 )); then
        FINAL_ID="mateo"
    elif (( VALENTIA >= 5 && DEFENDIO_ERIKA == 1 )); then
        FINAL_ID="erika"
    elif (( PRESION >= 6 )); then
        FINAL_ID="cansancio"
    elif (( REPUTACION <= -1 && GUARDO_SECRETO == 0 )); then
        FINAL_ID="silencio"
    elif (( CURIOSIDAD >= 6 && COPIA_HECHA == 1 )); then
        FINAL_ID="archivo"
    elif (( HONESTIDAD >= 5 )); then
        FINAL_ID="sencillo"
    else
        FINAL_ID="agridulce"
    fi
}

final_pantalla() {
    titulo
    ascii_end
    printf '\n'

    case "$FINAL_ID" in
        la_verdad)
            printf '%sFINAL 01 — LA VERDAD CABE EN UNA MESA%s\n\n' "$GREEN$BOLD" "$RST"
            escribir "El jurado no premia la versión perfecta."
            escribir "Premia la explicación que pueden defender."
            escribir "El equipo no gana el primer puesto."
            escribir "Ganan algo menos vistoso: volver a confiar unos en otros."
            escribir "Mateo se ofrece a documentar las copias del próximo proyecto."
            escribir "Valeria deja de revisar cada archivo cinco veces antes de dormir."
            escribir "Y tú guardas el disquete."
            escribir "No porque sea secreto."
            escribir "Porque ahora entiendes por qué una copia de seguridad importa."
            ;;
        el_hacker)
            printf '%sFINAL 02 — EL REY DEL LABORATORIO%s\n\n' "$CYAN$BOLD" "$RST"
            escribir "Reparaste el archivo y entendiste cómo había terminado roto."
            escribir "Durante una semana, todos te llaman 'el hacker'."
            escribir "El profesor aclara que no eres hacker."
            escribir "\"Solo aprendiste a leer los errores.\""
            escribir "El apodo se queda igual."
            ;;
        mateo)
            printf '%sFINAL 03 — MATEO Y LA COPIA IMPOSIBLE%s\n\n' "$YELLOW$BOLD" "$RST"
            escribir "Mateo admite su error delante del equipo."
            escribir "No lo suspenden. Tiene que rehacer el respaldo de todos los proyectos."
            escribir "La primera vez que intenta explicarlo, imprime 37 hojas."
            escribir "El profesor le dice que una carpeta compartida no necesita papel."
            escribir "Mateo responde: \"Por si se cae el servidor.\""
            escribir "Ahora todos saben que jamás confiarán en él para guardar un secreto."
            ;;
        erika)
            printf '%sFINAL 04 — ERIKA HABLA%s\n\n' "$MAGENTA$BOLD" "$RST"
            escribir "Erika se anima a decir lo que vio sin convertirlo en una acusación."
            escribir "Eso cambia la investigación."
            escribir "Aprendes algo difícil: tener una pista no te convierte en juez."
            escribir "Al final, nadie recibe una etiqueta de villano."
            escribir "Y el rumor muere cuando aparece algo más interesante: la verdad."
            ;;
        el_eco)
            printf '%sFINAL 05 — EL ECO%s\n\n' "$RED$BOLD" "$RST"
            escribir "La mentira parecía pequeña."
            escribir "Solo una frase."
            escribir "Pero después alguien hace otra pregunta, y luego otra."
            escribir "La versión que inventaste empieza a cambiar cada vez que la cuentas."
            escribir "El proyecto termina, pero la confianza no."
            escribir "Aprendes demasiado tarde que ocultar un error puede hacerlo más grande."
            ;;
        cansancio)
            printf '%sFINAL 06 — MAÑANA SERÁ OTRO DÍA%s\n\n' "$BLUE$BOLD" "$RST"
            escribir "La noche anterior fue demasiado."
            escribir "No terminan la versión grande."
            escribir "El profesor les propone algo sencillo: entregar lo que sí pueden explicar."
            escribir "No es una victoria espectacular."
            escribir "Pero duermes."
            escribir "Y descubres que a veces parar a tiempo también es una decisión."
            ;;
        silencio)
            printf '%sFINAL 07 — NADIE DIJO NADA%s\n\n' "$WHITE$BOLD" "$RST"
            escribir "El proyecto sigue."
            escribir "La feria sigue."
            escribir "Y el problema queda flotando."
            escribir "No hubo una gran pelea ni una gran castigo."
            escribir "Solo una sensación extraña: todos saben que faltó una conversación."
            escribir "Quizá todavía estás a tiempo de tenerla."
            ;;
        archivo)
            printf '%sFINAL 08 — COPIA DE SEGURIDAD%s\n\n' "$GREEN$BOLD" "$RST"
            escribir "Tu copia estaba ahí cuando más hacía falta."
            escribir "El proyecto sobrevive."
            escribir "La clase aprende una lección inesperada: perder un archivo es fácil."
            escribir "Perder la calma es todavía más fácil."
            escribir "A partir de ese día, el laboratorio tiene una regla nueva:"
            escribir "\"Primero copia. Después experimenta.\""
            ;;
        sencillo)
            printf '%sFINAL 09 — SIN FUEGOS ARTIFICIALES%s\n\n' "$YELLOW$BOLD" "$RST"
            escribir "Presentan una versión pequeña."
            escribir "Funciona."
            escribir "No hay una gran revelación ni una copa enorme."
            escribir "Solo un proyecto que hace lo que promete."
            escribir "Valeria sonríe."
            escribir "Mateo pide pizza con el dinero que le queda."
            escribir "Nadie se queja."
            ;;
        *)
            printf '%sFINAL 10 — EL DISQUETE SE QUEDA CONTIGO%s\n\n' "$CYAN$BOLD" "$RST"
            escribir "No todo salió como esperabas."
            escribir "Algunas cosas salieron bien. Otras, no."
            escribir "Pero decidiste cada paso y ahora sabes algo importante:"
            escribir "las historias no siempre terminan limpias."
            escribir "A veces solo terminan y te dejan pensando."
            ;;
    esac

    printf '\n'
    estado
    printf '\n%s' "$DIM"
    cat <<'EOF'
        El disquete queda guardado en una caja.
        Etiqueta nueva:

              "NO BORRAR.
               AQUÍ APRENDIMOS ALGO."

EOF
    printf '%s' "$RST"
    pausa
}

# ------------------------------------------------------------
# Guardado manual
# ------------------------------------------------------------
pausa_juego() {
    titulo
    printf '%sPAUSA%s\n\n' "$CYAN$BOLD" "$RST"
    printf '  1) Guardar partida\n'
    printf '  2) Ver estado\n'
    printf '  3) Continuar\n'
    printf '\n  Elige: '
    IFS= read -r p
    case "$p" in
        1)
            if guardar; then
                printf '%sPartida guardada en:%s\n  %s\n' "$GREEN" "$RST" "$SAVE_FILE"
            else
                printf '%sNo se pudo guardar la partida.%s\n' "$RED" "$RST"
            fi
            pausa
            ;;
        2)
            estado
            pausa
            ;;
    esac
}

# ------------------------------------------------------------
# Juego completo
# ------------------------------------------------------------
jugar_nuevo() {
    NOMBRE="Alex"
    CONFIANZA=0 HONESTIDAD=0 VALENTIA=0 EMPATIA=0 REPUTACION=0
    CURIOSIDAD=0 DINERO=8 PRESION=0 TIEMPO=0
    MATEO=0 VALERIA=0 ERIKA=0 PROFE=0
    TIENE_DISQUETE=0 VIO_ARCHIVO=0 COPIA_HECHA=0
    AYUDO_MATEO=0 AYUDO_VALERIA=0 DEFENDIO_ERIKA=0
    CONFESO=0 MINTIO=0 PUBLIQUE=0 BORRO_ARCHIVO=0 REPARO_ARCHIVO=0
    ACEPTO_DINERO=0 RECHAZO_DINERO=0 PRESENTO_PROYECTO=0
    ENTREGO_DISQUETE=0 GUARDO_SECRETO=0 PIDIO_AYUDA=0 CULPA=0 FINAL_ID=""

    introduccion
    capitulo_1
    capitulo_2
    capitulo_3
    capitulo_4
    capitulo_5
    capitulo_6
    capitulo_7
    capitulo_8
    capitulo_9
    determinar_final
    final_pantalla
    borrar_guardado
}

continuar_partida() {
    if ! cargar; then
        printf '%sNo hay una partida guardada.%s\n' "$RED" "$RST"
        pausa
        return
    fi

    printf '%sPartida de %s cargada.%s\n' "$GREEN" "$NOMBRE" "$RST"
    printf '%sEsta versión guarda después de cada capítulo.%s\n' "$DIM" "$RST"
    pausa

    # El guardado está pensado para usarse durante una sesión.
    # Para simplificar el flujo, retomamos desde el menú y advertimos
    # que la partida guardada representa el estado actual.
    titulo
    ascii_diskette
    printf '\n%sPARTIDA CARGADA%s\n\n' "$CYAN$BOLD" "$RST"
    escribir "Estado recuperado para $NOMBRE."
    estado
    escribir "Por seguridad narrativa, una partida cargada reinicia el capítulo actual."
    escribir "En esta edición, continúa desde la siguiente escena."
    pausa

    # No tenemos un índice de capítulo en el save original, así que
    # usamos los flags para aproximar el punto. Es intencionalmente simple.
    if (( PRESENTO_PROYECTO == 1 )); then
        capitulo_9
        determinar_final
        final_pantalla
    elif (( DEFENDIO_ERIKA == 1 || MATEO >= 2 || AYUDO_VALERIA == 1 )); then
        capitulo_6
        capitulo_7
        capitulo_8
        capitulo_9
        determinar_final
        final_pantalla
    elif (( COPIA_HECHA == 1 || REPARO_ARCHIVO == 1 )); then
        capitulo_4
        capitulo_5
        capitulo_6
        capitulo_7
        capitulo_8
        capitulo_9
        determinar_final
        final_pantalla
    else
        capitulo_2
        capitulo_3
        capitulo_4
        capitulo_5
        capitulo_6
        capitulo_7
        capitulo_8
        capitulo_9
        determinar_final
        final_pantalla
    fi

    borrar_guardado
}

mostrar_ayuda() {
    titulo
    printf '%sDISQUETE 7 — AYUDA%s\n\n' "$CYAN$BOLD" "$RST"
    escribir "Una aventura donde las decisiones cambian las relaciones, no solo el puntaje."
    escribir "No necesitas responder 'bien'. Puedes decidir según lo que tú harías."
    printf '\n'
    printf '  %s./disquete7.sh%s                     iniciar\n' "$GREEN" "$RST"
    printf '  %sTYPING=0 ./disquete7.sh%s            texto instantáneo\n' "$GREEN" "$RST"
    printf '  %sNO_COLOR=1 ./disquete7.sh%s          sin colores\n' "$GREEN" "$RST"
    printf '  %s./disquete7.sh --borrar-guardado%s   borrar partida guardada\n' "$GREEN" "$RST"
    pausa
}

menu() {
    while true; do
        titulo
        printf '\n'
        ascii_diskette
        printf '\n%sAÑO 1997 — UN DISQUETE. UNA TARDE. MUCHAS DECISIONES.%s\n\n' \
            "$WHITE$BOLD" "$RST"
        printf '  %s1)%s Nueva aventura\n' "$CYAN$BOLD" "$RST"
        printf '  %s2)%s Continuar partida\n' "$CYAN$BOLD" "$RST"
        printf '  %s3)%s Cómo jugar\n' "$CYAN$BOLD" "$RST"
        printf '  %s4)%s Salir\n' "$CYAN$BOLD" "$RST"
        printf '\n  Selecciona: '

        local op
        IFS= read -r op
        case "$op" in
            1) jugar_nuevo ;;
            2) continuar_partida ;;
            3) mostrar_ayuda ;;
            4|q|Q)
                limpiar
                printf '%sA:\> EXIT%s\n\n' "$GREEN" "$RST"
                printf 'Gracias por jugar a DISQUETE 7.\n\n'
                exit 0
                ;;
            *) printf '%sOpción no válida.%s\n' "$RED" "$RST"; sleep 0.6 ;;
        esac
    done
}

# ------------------------------------------------------------
# Argumentos
# ------------------------------------------------------------
case "${1:-}" in
    --help|-h)
        printf 'Uso: %s [--help|--borrar-guardado]\n' "$(basename "$0")"
        exit 0
        ;;
    --borrar-guardado)
        borrar_guardado
        printf 'Guardado borrado.\n'
        exit 0
        ;;
esac

# Terminal interactiva
if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'Este juego necesita ejecutarse directamente en una terminal interactiva.\n' >&2
    printf 'Usa: ./disquete7.sh\n' >&2
    exit 1
fi

menu
