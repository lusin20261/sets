#!/usr/bin/env bash
# ================================================================
# FUERA DE CONTEXTO — Aventura narrativa interactiva
# Público recomendado: 15–17 años
# Requiere: Bash 5+
#
# Ejecutar:
#   chmod +x fuera_de_contexto.sh
#   ./fuera_de_contexto.sh
#
# Opciones:
#   TYPING=0 ./fuera_de_contexto.sh   # texto instantáneo
#   NO_COLOR=1 ./fuera_de_contexto.sh # sin colores
#   ./fuera_de_contexto.sh --borrar-guardado
# ================================================================

# No usar set -e: algunas lecturas y pausas pueden devolver códigos
# distintos de cero sin que eso deba cerrar la aventura.

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
SAVE_FILE="${FUERA_CONTEXTO_SAVE:-$HOME/.local/share/fuera-de-contexto/partida.sav}"
SAVE_VERSION=2
EXPECTED_SAVE_VERSION=2
CHAPTER=1

# ------------------------------------------------------------
# Variables de la partida
# ------------------------------------------------------------
NOMBRE="Alex"
INTEGRIDAD=0
EMPATIA=0
CRITERIO=0
CORAJE=0
LEALTAD=0
PRUDENCIA=0
PRESION=0
REPUTACION=0

MIA=0
GAEL=0
ABRIL=0

VIO_PUBLICACION=0
PIDIO_DATOS=0
GAEL_HABLO=0
CULPO_GAEL=0
ACCESO_CONSENTIDO=0
ACCESO_SIN_PERMISO=0
RECONSTRUYO=0
PIDIO_ADULTO=0
PIDIO_ORIGEN=0
PRESIONO_BRUNO=0
SOLICITO_CORRECCION=0
CONSERVA_AUDIO=0
AUDIO_CONSENTIDO=0
PUBLICO_AUDIO=0
ABRIL_CONFESO=0
ESCUCHO_ABRIL=0
GUARDO_ORIGEN=0
REVELO_ABRIL=0
INFORME_COMPLETO=0
EXPUSO_CHAT=0
OCULTO_FALLOS=0
PIDIO_AUDITORIA=0
PRESENTO_HONESTO=0
PRESENTO_COLECTIVO=0
MINTIO=0
RETIRAR=0
FINAL_ID=""

# ------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------
limpiar() {
    printf '%s' "${CSI}2J${CSI}H"
}

pausa() {
    printf '\n%s[ ENTER para continuar ]%s ' "$DIM" "$RST"
    IFS= read -r _
}

linea() {
    printf '%s%s%s\n' "$DIM" '================================================================' "$RST"
}

escribir() {
    local texto="${1-}" i ch
    if [[ "$TYPING" == "0" ]]; then
        printf '%s\n' "$texto"
        return
    fi
    for ((i=0; i<${#texto}; i++)); do
        ch="${texto:i:1}"
        printf '%s' "$ch"
        sleep 0.006
    done
    printf '\n'
}

escribir_lento() {
    local texto="${1-}" i ch
    if [[ "$TYPING" == "0" ]]; then
        printf '%s\n' "$texto"
        return
    fi
    for ((i=0; i<${#texto}; i++)); do
        ch="${texto:i:1}"
        printf '%s' "$ch"
        sleep 0.014
    done
    printf '\n'
}

banner() {
    printf '%s' "$CYAN$BOLD"
    cat <<'EOF_BANNER'
  ███████╗██╗   ██╗███████╗██████╗  █████╗     ██████╗ ███████╗
  ██╔════╝██║   ██║██╔════╝██╔══██╗██╔══██╗    ██╔══██╗██╔════╝
  █████╗  ██║   ██║█████╗  ██████╔╝███████║    ██║  ██║█████╗
  ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██╔══██╗██╔══██║    ██║  ██║██╔══╝
  ███████╗ ╚████╔╝ ███████╗██║  ██║██║  ██║    ██████╔╝███████╗
  ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═════╝ ╚══════╝
                     [ UNA HISTORIA INTERACTIVA ]
EOF_BANNER
    printf '%s' "$RST"
}

pantalla_titulo() {
    limpiar
    banner
    printf '\n%s%s' "$WHITE$BOLD" '              NO TODO LO QUE SE VUELVE VIRAL ES CIERTO'
    printf '%s\n' "$RST"
    linea
}

capitulo_titulo() {
    pantalla_titulo
    printf '\n%s%s%s\n\n' "$MAGENTA$BOLD" "$1" "$RST"
}

chat() {
    local hora="$1" persona="$2" mensaje="$3" color="${4:-$WHITE}"
    printf '%s[%s]%s %s%-12s%s %s\n' "$DIM" "$hora" "$RST" "$color$BOLD" "$persona" "$RST" "$mensaje"
}

estado() {
    printf '\n%sPERFIL DE DECISIONES (provisional)%s\n' "$YELLOW$BOLD" "$RST"
    printf '  Integridad: %-2d  Empatía: %-2d  Criterio: %-2d\n' "$INTEGRIDAD" "$EMPATIA" "$CRITERIO"
    printf '  Coraje:     %-2d  Lealtad: %-2d  Prudencia: %-2d\n' "$CORAJE" "$LEALTAD" "$PRUDENCIA"
    printf '  Presión acumulada: %d\n' "$PRESION"
}

preguntar_nombre() {
    local entrada
    printf '\n¿Cómo se llama tu personaje? [ENTER = Alex]: '
    IFS= read -r entrada
    [[ -z "$entrada" ]] && entrada="Alex"
    entrada="${entrada//|/}"
    entrada="${entrada//[$'\r\n\t']/}"
    NOMBRE="${entrada:0:18}"
}

elegir() {
    local pregunta="$1" r i
    shift
    local opciones=("$@")
    while true; do
        printf '\n%s%s%s\n' "$WHITE$BOLD" "$pregunta" "$RST"
        for ((i=0; i<${#opciones[@]}; i++)); do
            printf '  %s%d)%s %s\n' "$CYAN$BOLD" "$((i+1))" "$RST" "${opciones[i]}"
        done
        printf '\n  Tu decisión: '
        IFS= read -r r
        case "$r" in
            1|2|3|4) CHOICE="$r"; return 0 ;;
            *) printf '%sEscribe 1, 2, 3 o 4.%s\n' "$RED" "$RST" ;;
        esac
    done
}

# ------------------------------------------------------------
# Guardado: se conserva el siguiente capítulo, no una aproximación.
# El archivo se genera localmente con declare -p.
# ------------------------------------------------------------
guardar() {
    local temporal variable
    mkdir -p "$(dirname "$SAVE_FILE")" 2>/dev/null || return 1
    temporal="${SAVE_FILE}.tmp.$$"
    local variables=(SAVE_VERSION CHAPTER NOMBRE INTEGRIDAD EMPATIA CRITERIO CORAJE LEALTAD PRUDENCIA PRESION REPUTACION MIA GAEL ABRIL VIO_PUBLICACION PIDIO_DATOS GAEL_HABLO CULPO_GAEL ACCESO_CONSENTIDO ACCESO_SIN_PERMISO RECONSTRUYO PIDIO_ADULTO PIDIO_ORIGEN PRESIONO_BRUNO SOLICITO_CORRECCION CONSERVA_AUDIO AUDIO_CONSENTIDO PUBLICO_AUDIO ABRIL_CONFESO ESCUCHO_ABRIL GUARDO_ORIGEN REVELO_ABRIL INFORME_COMPLETO EXPUSO_CHAT OCULTO_FALLOS PIDIO_AUDITORIA PRESENTO_HONESTO PRESENTO_COLECTIVO MINTIO RETIRAR FINAL_ID)
    : > "$temporal" || return 1
    for variable in "${variables[@]}"; do
        # %q produce una asignación escapada que puede recuperarse con source.
        # A diferencia de declare -p, la asignación no queda limitada al ámbito
        # local de la función cargar().
        printf '%s=%q\n' "$variable" "${!variable}" >> "$temporal" || {
            rm -f "$temporal"
            return 1
        }
    done
    mv -f "$temporal" "$SAVE_FILE"
}

cargar() {
    [[ -r "$SAVE_FILE" ]] || return 1
    # Guardado creado por este mismo juego en el equipo local.
    # shellcheck disable=SC1090
    source "$SAVE_FILE"
    [[ "${SAVE_VERSION:-0}" == "$EXPECTED_SAVE_VERSION" ]] || return 1
    [[ "${CHAPTER:-0}" =~ ^[1-9]$ ]] || return 1
    return 0
}

borrar_guardado() {
    rm -f "$SAVE_FILE" "${SAVE_FILE}.tmp."* 2>/dev/null
}

# ------------------------------------------------------------
# Introducción
# ------------------------------------------------------------
introduccion() {
    pantalla_titulo
    printf '%s\n' "$BLUE$BOLD"
    cat <<'EOF_FEED'
  ┌─────────────────────────────── CAMPUS / TENDENCIAS ─────────────────────────┐
  │  #ExpoJoven        #ProyectoLumen       1.842 publicaciones                 │
  │                                                                              │
  │  @pasillo_404  ·  hace 3 min                                                 │
  │  "¿CIENCIA O FRAUDE? Una integrante del equipo Lumen admite que cambió      │
  │   los datos. Mañana compiten por una beca y fondos para su colegio."         │
  │                                                                              │
  │  ▶ audio adjunto: 00:11                                                      │
  │  ████████████████████████████████████████████████████████████████████████   │
  └──────────────────────────────────────────────────────────────────────────────┘
EOF_FEED
    printf '%s\n' "$RST"
    escribir_lento "Lunes, 7:12 a. m. Colegio Horizonte."
    escribir "El audio dura once segundos. La voz parece ser la de Mía, tu compañera y responsable de datos del Proyecto Lumen."
    escribir 'La frase que se escucha es contundente: «Sí, yo cambié los datos. No podíamos presentar eso así».'
    escribir "En menos de una hora, el clip ya está en varios grupos. Algunos exigen que expulsen al equipo; otros defienden a Mía sin saber qué ocurrió."
    escribir "Lumen es un proyecto de sensores económicos que mide la temperatura de las aulas y propone mejoras para reducir el calor. Si gana Expo Joven, el colegio recibirá equipos y el equipo podrá acceder a una beca de innovación."
    escribir "La presentación es pasado mañana. Tienes 48 horas para decidir qué hacer con una historia que nadie conoce completa."
    printf '\n%sPERSONAS INVOLUCRADAS%s\n' "$YELLOW$BOLD" "$RST"
    chat "07:14" "MÍA" 'No compartas el audio. Está cortado. Te voy a explicar.' "$MAGENTA"
    chat "07:15" "GAEL" 'Tenemos un problema real con las mediciones. No es tan simple.' "$GREEN"
    chat "07:16" "ABRIL" 'Alguien del equipo envió eso. Lo sé.' "$YELLOW"
    chat "07:17" "TÚ" 'Todavía no sabes qué pensar.' "$CYAN"
    printf '\n'
    preguntar_nombre
    escribir "Tu personaje será $NOMBRE. No hay una opción perfecta: cada decisión puede proteger a alguien y perjudicar a otra persona."
    escribir "Tus decisiones no solo cambian el final. También construyen la forma en que afrontas los conflictos."
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 1 — La versión de once segundos
# ------------------------------------------------------------
capitulo_1() {
    capitulo_titulo "CAPÍTULO 1 — LA VERSIÓN DE ONCE SEGUNDOS"
    escribir "El primer recreo todavía no termina. En el grupo de clase hay más de cien mensajes nuevos."
    chat "08:03" "BRUNO" 'Si no tienen nada que ocultar, ¿por qué no muestran los archivos?' "$RED"
    chat "08:04" "MÍA" 'No voy a defenderme en un chat lleno de gente que ya decidió.' "$MAGENTA"
    escribir "Gael te escribe por privado. Dice que la tabla publicada no representa todas las mediciones, pero pide que no lo menciones todavía."
    escribir "Abril, encargada de comunicación, insiste en que el equipo debe responder antes de que la historia se vuelva irreversible."

    elegir "¿Cuál es tu primera reacción?" \
        "No publico nada. Primero quiero escuchar las versiones y medir el daño." \
        "Escribo a Mía en privado y le doy la oportunidad de explicar el audio." \
        "Busco la publicación original, su contexto y cualquier evidencia verificable." \
        "Defiendo al equipo públicamente: no voy a dejar que lo condenen sin pruebas."

    case "$CHOICE" in
        1) PRUDENCIA=$((PRUDENCIA+2)); EMPATIA=$((EMPATIA+1)); escribir "Te apartas del ruido. Algunos interpretan tu silencio como indiferencia, pero evitas amplificar una acusación sin comprobarla." ;;
        2) EMPATIA=$((EMPATIA+2)); LEALTAD=$((LEALTAD+1)); MIA=$((MIA+2)); escribir "Mía responde casi de inmediato: «Gracias por preguntar antes de compartir». No te cuenta todo, pero acepta hablar contigo." ;;
        3) CRITERIO=$((CRITERIO+2)); INTEGRIDAD=$((INTEGRIDAD+1)); VIO_PUBLICACION=1; escribir "Comparas la hora de publicación con la del mensaje que aparece en la captura. Hay un detalle: la imagen del gráfico es de dos días antes." ;;
        4) CORAJE=$((CORAJE+2)); LEALTAD=$((LEALTAD+1)); REPUTACION=$((REPUTACION+1)); VIO_PUBLICACION=1; escribir "Tu mensaje recibe apoyos y también críticas. Ahora formas parte de la discusión: será más difícil retroceder sin dar explicaciones." ;;
    esac
    PRESION=$((PRESION+1))
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 2 — Los números que faltan
# ------------------------------------------------------------
capitulo_2() {
    capitulo_titulo "CAPÍTULO 2 — LOS NÚMEROS QUE FALTAN"
    escribir "Después de clases, el equipo se reúne en el laboratorio. Mía llega con una carpeta de mediciones; Gael, con el prototipo abierto sobre la mesa."
    chat "15:42" "MÍA" 'Convertí las lecturas del sensor tres: estaba configurado en Fahrenheit.' "$MAGENTA"
    chat "15:43" "GAEL" 'Y yo completé un tramo sin datos con una estimación. El sensor se apagó.' "$GREEN"
    escribir "La estimación aparece en el panel como si fuera una medición normal. No hay una marca que la distinga. Mía sabía que existía el problema, pero pensó que Gael lo documentaría. Gael creyó que todos estaban de acuerdo en corregirlo después."
    escribir "No parece una conspiración. Tampoco es un detalle menor: una gráfica presentada como medición real puede llevar a conclusiones equivocadas."

    elegir "¿Cómo abordas lo que acaba de salir a la luz?" \
        "Pido a Gael que explique exactamente qué estimó y por qué." \
        "Lo confronto delante del equipo: alguien tiene que asumir la responsabilidad." \
        "Escucho a ambos antes de decidir quién debe responder." \
        "Solicito la base completa de datos y separo mediciones reales de estimaciones."

    case "$CHOICE" in
        1) CRITERIO=$((CRITERIO+1)); INTEGRIDAD=$((INTEGRIDAD+1)); GAEL=$((GAEL+1)); GAEL_HABLO=1; escribir "Gael explica el procedimiento sin adornos. Reconoce que debió etiquetar los valores estimados." ;;
        2) CORAJE=$((CORAJE+2)); INTEGRIDAD=$((INTEGRIDAD+1)); GAEL=$((GAEL-1)); CULPO_GAEL=1; escribir "Gael se cierra. «¿Quieres un culpable o quieres arreglarlo?», responde. Mía no parece cómoda con la discusión." ;;
        3) EMPATIA=$((EMPATIA+2)); LEALTAD=$((LEALTAD+1)); MIA=$((MIA+1)); GAEL=$((GAEL+1)); escribir "La conversación baja de intensidad. Ambos admiten que dejaron cosas sin explicar, aunque todavía no coinciden sobre quién debía revisar el panel." ;;
        4) CRITERIO=$((CRITERIO+2)); INTEGRIDAD=$((INTEGRIDAD+2)); PIDIO_DATOS=1; escribir "Pides el registro original, no una captura del gráfico. Es la primera vez que alguien plantea reconstruir el proceso completo." ;;
    esac
    PRESION=$((PRESION+1))
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 3 — Acceso concedido
# ------------------------------------------------------------
capitulo_3() {
    capitulo_titulo "CAPÍTULO 3 — ACCESO CONCEDIDO"
    escribir "El proyecto tiene una carpeta compartida. Incluye lecturas originales, versiones del panel y documentos personales del equipo. En una computadora del laboratorio quedó abierta una sesión de Gael."
    escribir "Podrías revisar el historial técnico, pero también hay conversaciones privadas y archivos que no tienen relación con el proyecto. Nadie te ha dado permiso para entrar."
    escribir "Mientras lo piensas, Mía te manda una foto de su cuaderno: anotó las horas en que el sensor se apagó. La información podría servir para reconstruir el tramo perdido."

    elegir "¿Cómo consigues evidencia?" \
        "Pido que compartan formalmente los registros técnicos con todo el equipo." \
        "Aprovecho la sesión abierta y reviso la carpeta sin pedir autorización." \
        "Reconstruyo las mediciones con el cuaderno y repito las pruebas." \
        "Pido al profesor que solicite una copia verificable y supervise la revisión."

    case "$CHOICE" in
        1) ACCESO_CONSENTIDO=1; PRUDENCIA=$((PRUDENCIA+2)); INTEGRIDAD=$((INTEGRIDAD+1)); escribir "El equipo habilita una carpeta solo con los datos del proyecto. El proceso es más lento, pero nadie tiene que entregar sus conversaciones privadas." ;;
        2) ACCESO_SIN_PERMISO=1; CRITERIO=$((CRITERIO+2)); PRUDENCIA=$((PRUDENCIA-2)); escribir "Encuentras el historial de versiones y confirmas que hubo una estimación. También ves mensajes privados que no necesitabas leer. La evidencia puede ayudar, pero cruzaste un límite." ;;
        3) RECONSTRUYO=1; CRITERIO=$((CRITERIO+2)); PRESION=$((PRESION+1)); escribir "Repiten una parte de las pruebas. El nuevo resultado no coincide exactamente con el anterior: ahora saben cuánto margen de error debieron reconocer." ;;
        4) PIDIO_ADULTO=1; PRUDENCIA=$((PRUDENCIA+1)); INTEGRIDAD=$((INTEGRIDAD+1)); escribir "El profesor acepta supervisar la revisión. Aclara que no leerá chats privados y que la prioridad será preservar los datos originales." ;;
    esac
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 4 — El administrador
# ------------------------------------------------------------
capitulo_4() {
    capitulo_titulo "CAPÍTULO 4 — EL ADMINISTRADOR"
    escribir "A la salida encuentras a Bruno, quien administra la cuenta estudiantil Pasillo_404. No es un periodista: publica rumores, avisos y denuncias anónimas."
    chat "16:28" "BRUNO" 'El audio me llegó por mensaje. No lo grabé yo.' "$RED"
    escribir "Te muestra el archivo que recibió: el audio original dura cuarenta y siete segundos. La publicación usa solo once. Bruno admite que añadió el texto «admite fraude» porque pensó que así más personas prestarían atención."
    escribir "No quiere revelar quién se lo envió. Dice que prometió mantener la fuente en secreto. También acepta que no verificó la acusación antes de publicarla."

    elegir "¿Qué haces con Bruno?" \
        "Le pido el audio completo y la hora de recepción, sin exigir el nombre de la fuente." \
        "Lo presiono y amenazo con exponerlo si no revela quién se lo envió." \
        "Le exijo que publique una corrección visible y deje de llamar fraude al proyecto." \
        "Me retiro. Su fuente también puede tener miedo y no voy a convertir esto en una cacería."

    case "$CHOICE" in
        1) PIDIO_ORIGEN=1; CRITERIO=$((CRITERIO+2)); PRUDENCIA=$((PRUDENCIA+1)); escribir "Bruno acepta mostrarte el audio completo, pero no el contacto. La voz de Mía aparece en una conversación mucho más larga." ;;
        2) PRESIONO_BRUNO=1; CORAJE=$((CORAJE+2)); PRESION=$((PRESION+1)); REPUTACION=$((REPUTACION-1)); escribir "Bruno se niega. «Ahora quieres investigar la publicación usando otra amenaza», te dice. La conversación termina mal." ;;
        3) SOLICITO_CORRECCION=1; INTEGRIDAD=$((INTEGRIDAD+2)); CORAJE=$((CORAJE+1)); escribir "Bruno acepta retirar la palabra fraude mientras revisa el audio. No promete disculparse, pero cambia la descripción." ;;
        4) EMPATIA=$((EMPATIA+1)); PRUDENCIA=$((PRUDENCIA+2)); escribir "No obtienes el nombre. A cambio, Bruno te deja escuchar el archivo completo en su teléfono, sin copiarlo." ;;
    esac
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 5 — Los cuarenta y siete segundos
# ------------------------------------------------------------
capitulo_5() {
    capitulo_titulo "CAPÍTULO 5 — LOS CUARENTA Y SIETE SEGUNDOS"
    escribir "Con el audio completo, la frase cambia de sentido. Mía no estaba hablando de inventar resultados. Estaba explicando una corrección de unidades y, después, una estimación que no había sido señalada."
    printf '\n%sTRANSCRIPCIÓN DEL AUDIO COMPLETO%s\n' "$YELLOW$BOLD" "$RST"
    chat "00:18" "MÍA" 'Sí, cambié los datos del sensor tres: los pasé de Fahrenheit a Celsius.' "$MAGENTA"
    chat "00:26" "MÍA" 'Eso no es inventar mediciones. Pero el miércoles el sensor se apagó...' "$MAGENTA"
    chat "00:34" "MÍA" '...y completamos ese tramo con una estimación. Debimos marcarlo.' "$MAGENTA"
    chat "00:41" "VOZ" '¿Y el panel ya está corregido?' "$WHITE"
    chat "00:44" "MÍA" 'Todavía no. No quiero que parezca que escondimos el problema.' "$MAGENTA"
    escribir "Hay una segunda pieza: un mensaje del profesor Soria al equipo, enviado la noche anterior a la grabación: «Para la demo quiero una gráfica limpia. No llenen las diapositivas de advertencias; luego dejamos el método en anexos»."
    escribir "El mensaje no ordena falsificar datos, pero sí transmite una prioridad peligrosa: que la presentación se vea bien antes de explicar sus límites."
    escribir "Mía reconoce que debió detener la entrega. Gael admite que no documentó la estimación. El profesor tendrá que explicar por qué no exigió que el panel distinguiera los datos medidos de los calculados."

    elegir "¿Qué haces con el audio y el mensaje?" \
        "Conservo ambos como evidencia, pero no los publico sin permiso." \
        "Pido autorización a Mía para presentar el audio completo al jurado." \
        "Publico el audio completo ahora mismo para desmontar el clip viral." \
        "No los uso: pueden exponer conversaciones privadas y empeorar el daño."

    case "$CHOICE" in
        1) CONSERVA_AUDIO=1; PRUDENCIA=$((PRUDENCIA+2)); CRITERIO=$((CRITERIO+1)); escribir "Guardas la evidencia sin difundirla. Ahora puedes distinguir entre verificar un hecho y convertirlo en contenido público." ;;
        2) CONSERVA_AUDIO=1; AUDIO_CONSENTIDO=1; INTEGRIDAD=$((INTEGRIDAD+2)); EMPATIA=$((EMPATIA+1)); MIA=$((MIA+1)); escribir "Mía acepta que el jurado escuche el audio completo, siempre que no se publique en redes ni se difundan los mensajes personales." ;;
        3) CONSERVA_AUDIO=1; PUBLICO_AUDIO=1; CORAJE=$((CORAJE+1)); REPUTACION=$((REPUTACION+1)); PRESION=$((PRESION+2)); escribir "El clip completo se comparte y la acusación pierde fuerza. Pero Mía no te había autorizado a exponer su voz. La verdad también puede vulnerar a alguien." ;;
        4) EMPATIA=$((EMPATIA+2)); PRUDENCIA=$((PRUDENCIA+1)); escribir "Decides no difundir las conversaciones. Sin embargo, todavía necesitas una forma de demostrar qué ocurrió con las mediciones." ;;
    esac
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 6 — La fuente
# ------------------------------------------------------------
capitulo_6() {
    capitulo_titulo "CAPÍTULO 6 — LA FUENTE"
    escribir "Abril pide hablar contigo a solas. Está agotada y lleva horas evitando al grupo."
    chat "18:06" "ABRIL" 'Yo envié el audio a Pasillo_404. No pensé que Bruno lo publicaría recortado.' "$YELLOW"
    escribir "Abril explica que escuchó a Mía decir que las estimaciones no estaban marcadas. Sintió que el equipo iba a ocultarlo para no perder la beca. Envió el audio a la cuenta porque creyó que una pregunta pública obligaría al colegio a revisar los datos."
    escribir "No pidió que llamaran fraude a Mía. Pero sabía que el audio era privado y no pidió permiso. Bruno decidió recortarlo y añadió una acusación que no podía demostrar. Cada uno tomó una decisión distinta y el daño terminó siendo colectivo."
    escribir "Abril te mira: «No quería destruir el proyecto. Quería que alguien nos obligara a decir la verdad. ¿Eso me convierte en una traidora?»"

    elegir "¿Cómo respondes a su confesión?" \
        "Le digo que hizo daño y debe asumirlo, aunque entiendo por qué actuó así." \
        "Le pregunto qué quería conseguir y la escucho antes de juzgarla." \
        "Guardo su identidad por ahora; no quiero romper al equipo antes de la presentación." \
        "Informo al profesor, pero pido que se trate su responsabilidad sin convertirla en chivo expiatorio."

    case "$CHOICE" in
        1) CORAJE=$((CORAJE+1)); INTEGRIDAD=$((INTEGRIDAD+1)); ABRIL=$((ABRIL-1)); ABRIL_CONFESO=1; escribir "Abril no intenta justificarse. «Lo sé. Debí hablar con ustedes primero», responde." ;;
        2) EMPATIA=$((EMPATIA+2)); LEALTAD=$((LEALTAD+1)); ABRIL=$((ABRIL+2)); ABRIL_CONFESO=1; ESCUCHO_ABRIL=1; escribir "Abril cuenta que también temía que el colegio perdiera una oportunidad por esconder errores. La escuchas sin absolverla." ;;
        3) LEALTAD=$((LEALTAD+2)); PRUDENCIA=$((PRUDENCIA+1)); GUARDO_ORIGEN=1; ABRIL_CONFESO=1; escribir "No revelas su nombre. El secreto protege a Abril de una reacción inmediata, pero dificulta reconstruir públicamente cómo empezó la filtración." ;;
        4) INTEGRIDAD=$((INTEGRIDAD+2)); PRUDENCIA=$((PRUDENCIA+1)); REVELO_ABRIL=1; ABRIL_CONFESO=1; escribir "El profesor escucha la historia completa y promete no usar a Abril como única responsable. También le dice que compartir un audio privado tuvo consecuencias reales." ;;
    esac
    PRESION=$((PRESION+1))
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 7 — La reunión
# ------------------------------------------------------------
capitulo_7() {
    capitulo_titulo "CAPÍTULO 7 — LA REUNIÓN"
    escribir "Martes, 4:30 p. m. Dirección convoca al equipo. Están el profesor Soria, la coordinadora de Expo Joven y los cuatro integrantes. La evaluación final será al día siguiente."
    escribir "Soria no niega su mensaje. Dice que quería que el proyecto se entendiera en una exposición breve. «No les pedí que mintieran», afirma. Mía responde: «Pero tampoco nos pidió que distinguiéramos lo medido de lo estimado»."
    escribir "La coordinadora explica que el jurado puede aceptar una corrección metodológica, abrir una revisión formal o retirar la candidatura. Pero necesita una decisión del equipo, no cuatro versiones distintas."

    elegir "¿Qué postura llevas a la reunión?" \
        "Entregar un informe completo: datos originales, estimaciones, errores y responsabilidades." \
        "Publicar capturas y conversaciones para que todos vean quién dijo qué." \
        "Corregir el panel discretamente y evitar que el problema crezca." \
        "Solicitar una auditoría independiente y pausar la candidatura hasta verificar todo."

    case "$CHOICE" in
        1) INFORME_COMPLETO=1; INTEGRIDAD=$((INTEGRIDAD+2)); CRITERIO=$((CRITERIO+1)); escribir "Propones un informe con tres columnas: medición real, estimación y dato descartado. También incluyes quién revisó cada versión." ;;
        2) EXPUSO_CHAT=1; CORAJE=$((CORAJE+2)); PRESION=$((PRESION+2)); escribir "La transparencia se vuelve exposición total. La coordinadora pregunta por qué deben difundirse mensajes personales si basta con presentar los registros técnicos." ;;
        3) OCULTO_FALLOS=1; PRUDENCIA=$((PRUDENCIA+1)); INTEGRIDAD=$((INTEGRIDAD-2)); escribir "La propuesta reduce el escándalo inmediato, pero no explica por qué la versión anterior mostraba estimaciones como mediciones. Mía se niega a firmarla." ;;
        4) PIDIO_AUDITORIA=1; CRITERIO=$((CRITERIO+2)); PRUDENCIA=$((PRUDENCIA+1)); PRESION=$((PRESION+1)); escribir "Pides una revisión independiente. Puede costarles la beca, pero impediría que el equipo o el colegio decidan por sí solos qué evidencia mostrar." ;;
    esac
    pausa
}

# ------------------------------------------------------------
# CAPÍTULO 8 — Lo que queda en pantalla
# ------------------------------------------------------------
capitulo_8() {
    capitulo_titulo "CAPÍTULO 8 — LO QUE QUEDA EN PANTALLA"
    escribir "Miércoles. Faltan diez minutos para presentar. En la pantalla aparece el mapa de temperaturas. El sensor tres sigue marcado en rojo, pero ahora la leyenda distingue las lecturas reales de las estimaciones."
    escribir "Mía te pregunta si vas a hablar. Gael sostiene el prototipo. Abril tiene el guion de exposición, aunque ya no está segura de querer leerlo."
    escribir "La coordinadora ofrece cuatro caminos. Ninguno garantiza ganar. Todos tendrán consecuencias después de que se apaguen las cámaras."

    elegir "¿Cuál será tu decisión final?" \
        "Presentamos los resultados corregidos y explicamos con claridad sus límites." \
        "Presentamos la versión más vistosa y decimos que todas las cifras fueron medidas." \
        "Nos retiramos de la competencia y publicamos los datos para que otros puedan revisarlos." \
        "Presentamos como equipo: contamos los errores, la filtración y cómo vamos a reparar el proyecto."

    case "$CHOICE" in
        1) PRESENTO_HONESTO=1; INTEGRIDAD=$((INTEGRIDAD+2)); CRITERIO=$((CRITERIO+1)); escribir "El jurado ve un proyecto menos espectacular, pero puede distinguir qué saben y qué todavía necesitan comprobar." ;;
        2) MINTIO=1; OCULTO_FALLOS=1; REPUTACION=$((REPUTACION+2)); PRESION=$((PRESION+2)); escribir "La presentación fluye y el público aplaude. Cuando preguntan por las lecturas del miércoles, Gael y Mía no se miran." ;;
        3) RETIRAR=1; INTEGRIDAD=$((INTEGRIDAD+1)); PRUDENCIA=$((PRUDENCIA+2)); escribir "Anuncian que no competirán con resultados que todavía requieren revisión. La decisión decepciona a algunos, pero el repositorio de datos queda abierto y documentado." ;;
        4) PRESENTO_COLECTIVO=1; EMPATIA=$((EMPATIA+1)); CORAJE=$((CORAJE+1)); LEALTAD=$((LEALTAD+1)); INTEGRIDAD=$((INTEGRIDAD+1)); escribir "Cada integrante asume una parte distinta. No buscan un culpable único ni convierten la filtración en excusa para evitar los errores." ;;
    esac
    pausa
}

# ------------------------------------------------------------
# Finales
# ------------------------------------------------------------
determinar_final() {
    # El orden importa: se priorizan las consecuencias más específicas.
    if (( EXPUSO_CHAT == 1 && ACCESO_SIN_PERMISO == 1 )); then
        FINAL_ID="pantalla_abierta"
    elif (( MINTIO == 1 || (OCULTO_FALLOS == 1 && INTEGRIDAD <= 1) )); then
        FINAL_ID="trofeo_vacio"
    elif (( CULPO_GAEL == 1 && GAEL <= 0 && PIDIO_AUDITORIA == 0 && RETIRAR == 0 )); then
        FINAL_ID="chivo_expiatorio"
    elif (( RETIRAR == 1 )); then
        FINAL_ID="salida_con_proposito"
    elif (( PIDIO_AUDITORIA == 1 )); then
        FINAL_ID="revision_independiente"
    elif (( PRESENTO_COLECTIVO == 1 && ABRIL_CONFESO == 1 && ESCUCHO_ABRIL == 1 )); then
        FINAL_ID="equipo_reparado"
    elif (( INFORME_COMPLETO == 1 && (PRESENTO_HONESTO == 1 || PRESENTO_COLECTIVO == 1) )); then
        FINAL_ID="datos_a_la_luz"
    elif (( GUARDO_ORIGEN == 1 && INFORME_COMPLETO == 0 )); then
        FINAL_ID="secreto_pendiente"
    elif (( PUBLICO_AUDIO == 1 )); then
        FINAL_ID="verdad_sin_permiso"
    elif (( INTEGRIDAD >= 7 && CRITERIO >= 5 && PRUDENCIA >= 3 )); then
        FINAL_ID="reconstruccion"
    else
        FINAL_ID="final_abierto"
    fi
}

mostrar_final() {
    pantalla_titulo
    printf '\n%s' "$GREEN$BOLD"
    case "$FINAL_ID" in
        pantalla_abierta)
            printf 'FINAL 01 — TODO QUEDÓ EXPUESTO\n\n'
            escribir "La publicación de conversaciones privadas y el acceso sin permiso se convierten en el nuevo centro del conflicto. Algunas pruebas son útiles, pero ahora también deben responder por la forma en que las obtuvieron y difundieron."
            escribir "La candidatura queda suspendida. Mía deja de hablarte por un tiempo. Aprendes que defender la transparencia no significa que cualquier medio sea válido."
            ;;
        trofeo_vacio)
            printf 'FINAL 02 — EL TROFEO VACÍO\n\n'
            escribir "Lumen recibe reconocimiento por su presentación. Durante unos días parece que todo salió bien. Luego una revisión externa detecta que se presentaron estimaciones como mediciones reales."
            escribir "El premio se retira y el equipo pierde credibilidad. Lo más difícil no es devolver el trofeo: es explicar por qué decidieron sostener una versión que sabían incompleta."
            ;;
        chivo_expiatorio)
            printf 'FINAL 03 — UN CULPABLE PARA TODOS\n\n'
            escribir "Gael termina cargando con casi toda la responsabilidad. El colegio da el caso por cerrado, pero el informe técnico demuestra que las decisiones fueron compartidas: hubo estimaciones sin marcar, supervisión insuficiente y presión por presentar una gráfica perfecta."
            escribir "El proyecto continúa sin Gael. El equipo conserva la candidatura, pero no recupera la confianza. Resolver un problema señalando a una sola persona fue más sencillo que hacerse cargo."
            ;;
        salida_con_proposito)
            printf 'FINAL 04 — SALIR TAMBIÉN ES DECIDIR\n\n'
            escribir "Se retiran de Expo Joven. No hay escenario, beca ni fotografía con un diploma. En cambio, publican las mediciones con sus límites, el procedimiento y las correcciones pendientes."
            escribir "Un laboratorio universitario se ofrece a revisar el prototipo. No es el premio que esperaban, pero el trabajo puede servir para algo más que ganar una competencia."
            ;;
        revision_independiente)
            printf 'FINAL 05 — QUE LO REVISE ALGUIEN MÁS\n\n'
            escribir "La coordinadora pausa la candidatura y encarga una revisión independiente. El informe confirma que las conversiones de unidades eran válidas, pero que el tramo estimado debió identificarse claramente."
            escribir "El equipo no recibe el premio principal. Obtiene una oportunidad para corregir el método y presentar una nueva versión. La decisión de no controlar la investigación termina siendo su mayor acierto."
            ;;
        datos_a_la_luz)
            printf 'FINAL 06 — LOS DATOS A LA LUZ\n\n'
            escribir "Presentan los datos originales, las estimaciones y los errores de documentación. El jurado hace preguntas difíciles, pero puede seguir el rastro de cada decisión."
            escribir "Lumen recibe una mención por transparencia y utilidad social. El profesor Soria reconoce que debió exigir mejores controles. El equipo acuerda publicar también los resultados que no confirman su hipótesis."
            ;;
        equipo_reparado)
            printf 'FINAL 07 — NO ÉRAMOS UNA SOLA HISTORIA\n\n'
            escribir "En la exposición, Abril reconoce que filtró el audio. Bruno admite que lo recortó y lo tituló sin verificarlo. Mía y Gael explican los errores de los datos; el profesor reconoce su parte en la presión por simplificar."
            escribir "No todos se perdonan ese día. Pero dejan de fingir que el conflicto tuvo un único responsable. El proyecto sigue con reglas nuevas: permisos, registro de cambios y revisión cruzada."
            ;;
        secreto_pendiente)
            printf 'FINAL 08 — EL SECRETO SIGUE AHÍ\n\n'
            escribir "El equipo presenta una versión corregida, pero la filtración nunca se aclara oficialmente. Abril sigue cargando con lo que hizo y Bruno conserva una versión de la historia que nadie ha corregido del todo."
            escribir "La competencia termina, aunque el grupo queda dividido. Guardar un secreto puede proteger a alguien durante un día y complicar las cosas durante meses."
            ;;
        reconstruccion)
            printf 'FINAL 09 — VOLVER A CONSTRUIR\n\n'
            escribir "Las pruebas nuevas y el registro de cambios permiten rehacer el panel. No consiguen borrar el rumor, pero pueden responder cada pregunta con evidencia y reconocer lo que todavía no saben."
            escribir "La confianza vuelve lentamente. Esta vez el equipo prefiere una gráfica incómoda y honesta a una presentación impecable que nadie pueda defender."
            ;;
        verdad_sin_permiso)
            printf 'FINAL 10 — LA VERDAD SIN PERMISO\n\n'
            escribir "El audio completo desmonta la acusación de fraude, y la publicación recibe miles de visitas. Sin embargo, Mía siente que le quitaron el control sobre su propia voz."
            escribir "La historia pública mejora; la relación privada queda dañada. Descubres que una explicación verdadera también necesita consentimiento y cuidado."
            ;;
        *)
            printf 'FINAL 11 — UNA HISTORIA INCOMPLETA\n\n'
            escribir "El proyecto llega a la presentación, pero las decisiones no terminan de encajar. Algunas personas sienten que las protegiste; otras creen que evitaste tomar una postura."
            escribir "No hay una gran victoria ni una catástrofe. Queda una conversación pendiente y la posibilidad de hacerlo mejor en el siguiente proyecto."
            ;;
    esac
    printf '%s' "$RST"
    printf '\n'
    linea
    printf '%sLECTURA DE TUS DECISIONES%s\n' "$CYAN$BOLD" "$RST"
    escribir "Este perfil describe cómo decidiste durante esta partida. No es un diagnóstico ni una etiqueta definitiva sobre tu personalidad: otras circunstancias podrían llevarte a elegir distinto."
    mostrar_perfil
    pausa
}

# ------------------------------------------------------------
# Perfil del jugador
# ------------------------------------------------------------
descripcion_rasgo() {
    local rasgo="$1" nivel="$2"
    case "$rasgo" in
        integridad)
            if (( nivel >= 6 )); then escribir "Integridad alta: priorizaste reconocer errores y evitar presentar como cierto algo que no estaba demostrado.";
            elif (( nivel >= 3 )); then escribir "Integridad media: buscaste ser honesto, aunque algunas veces pesaron la presión o la conveniencia.";
            else escribir "Integridad baja en esta partida: tendiste a proteger el resultado o a evitar explicaciones incómodas. Eso puede tener costos para la confianza."; fi ;;
        empatia)
            if (( nivel >= 6 )); then escribir "Empatía alta: consideraste cómo podían afectar tus decisiones a las personas, incluso a quienes se equivocaron.";
            elif (( nivel >= 3 )); then escribir "Empatía media: escuchaste algunas versiones y tuviste en cuenta el daño personal, aunque no siempre fue tu prioridad.";
            else escribir "Empatía baja en esta partida: te enfocaste más en resolver el conflicto que en cómo lo estaban viviendo los demás."; fi ;;
        criterio)
            if (( nivel >= 6 )); then escribir "Pensamiento crítico alto: buscaste contexto, registros y pruebas antes de sacar conclusiones.";
            elif (( nivel >= 3 )); then escribir "Pensamiento crítico medio: contrastaste parte de la información, aunque algunas decisiones se apoyaron en indicios incompletos.";
            else escribir "Pensamiento crítico bajo en esta partida: actuaste con información limitada o diste más peso a las primeras versiones."; fi ;;
        coraje)
            if (( nivel >= 6 )); then escribir "Coraje alto: aceptaste el costo de intervenir, confrontar o defender una postura.";
            elif (( nivel >= 3 )); then escribir "Coraje medio: hablaste cuando lo consideraste necesario, pero también elegiste evitar ciertas confrontaciones.";
            else escribir "Coraje bajo en esta partida: preferiste no exponerte o dejaste que otras personas llevaran el conflicto."; fi ;;
        lealtad)
            if (( nivel >= 6 )); then escribir "Lealtad alta: protegiste vínculos y compromisos; procuraste no abandonar a alguien en el momento difícil.";
            elif (( nivel >= 3 )); then escribir "Lealtad media: apoyaste al equipo, aunque no siempre pusiste la relación por encima de otros principios.";
            else escribir "Lealtad baja en esta partida: priorizaste la responsabilidad individual o la resolución del problema antes que mantener unido al grupo."; fi ;;
        prudencia)
            if (( nivel >= 6 )); then escribir "Prudencia alta: pensaste en permisos, privacidad y consecuencias antes de difundir información.";
            elif (( nivel >= 3 )); then escribir "Prudencia media: cuidaste algunos límites, aunque en ciertos momentos aceptaste riesgos para obtener respuestas.";
            else escribir "Prudencia baja en esta partida: asumiste riesgos o actuaste rápido sin medir del todo las consecuencias."; fi ;;
    esac
}

mostrar_perfil() {
    local principal secundario puntos
    local -a ranking
    mapfile -t ranking < <(printf '%s\t%d\n' \
        integridad "$INTEGRIDAD" empatia "$EMPATIA" criterio "$CRITERIO" \
        coraje "$CORAJE" lealtad "$LEALTAD" prudencia "$PRUDENCIA" \
        | sort -t $'\t' -k2,2nr)
    principal="${ranking[0]%%$'\t'*}"
    puntos="${ranking[0]#*$'\t'}"
    secundario="${ranking[1]%%$'\t'*}"

    printf '\n%sTU TENDENCIA PRINCIPAL: %s%s\n' "$YELLOW$BOLD" "${principal^^}" "$RST"
    case "$principal" in
        integridad) escribir "Tu patrón dominante fue sostener lo que consideras correcto, incluso cuando podía perjudicar el resultado." ;;
        empatia) escribir "Tu patrón dominante fue mirar el conflicto desde las personas involucradas y no solo desde el problema técnico." ;;
        criterio) escribir "Tu patrón dominante fue investigar, comparar versiones y desconfiar de las conclusiones rápidas." ;;
        coraje) escribir "Tu patrón dominante fue intervenir y asumir el costo de hacer visible un desacuerdo." ;;
        lealtad) escribir "Tu patrón dominante fue cuidar al equipo y no reducir a tus compañeros a sus errores." ;;
        prudencia) escribir "Tu patrón dominante fue medir el momento, los permisos y las consecuencias de cada acción." ;;
    esac
    printf '\n%sRASGO SECUNDARIO: %s%s\n' "$YELLOW$BOLD" "${secundario^^}" "$RST"
    case "$secundario" in
        integridad) escribir "Acompañó tus decisiones la necesidad de que los hechos y la presentación fueran coherentes." ;;
        empatia) escribir "También procuraste considerar el impacto emocional de lo que estaba ocurriendo." ;;
        criterio) escribir "Además, intentaste distinguir evidencia, sospecha y opinión." ;;
        coraje) escribir "También mostraste disposición a tomar posición cuando el conflicto lo exigió." ;;
        lealtad) escribir "Además, los vínculos y la responsabilidad con el grupo tuvieron peso en tus elecciones." ;;
        prudencia) escribir "También tuviste presente que conseguir información no justifica cualquier método." ;;
    esac

    printf '\n%sQUÉ REFLEJAN TUS OPCIONES%s\n' "$CYAN$BOLD" "$RST"
    descripcion_rasgo integridad "$INTEGRIDAD"
    descripcion_rasgo empatia "$EMPATIA"
    descripcion_rasgo criterio "$CRITERIO"
    descripcion_rasgo coraje "$CORAJE"
    descripcion_rasgo lealtad "$LEALTAD"
    descripcion_rasgo prudencia "$PRUDENCIA"

    printf '\n%sTUS INDICADORES%s\n' "$CYAN$BOLD" "$RST"
    printf '  Integridad %-2d  Empatía %-2d  Criterio %-2d\n' "$INTEGRIDAD" "$EMPATIA" "$CRITERIO"
    printf '  Coraje     %-2d  Lealtad %-2d  Prudencia %-2d\n' "$CORAJE" "$LEALTAD" "$PRUDENCIA"
    printf '\n%sUna última idea:%s tus elecciones muestran prioridades en una situación concreta; no determinan quién eres ni cómo actuarás siempre.\n' "$DIM" "$RST"
}

# ------------------------------------------------------------
# Flujo de capítulos y guardado automático
# ------------------------------------------------------------
jugar_desde_capitulo() {
    while (( CHAPTER <= 8 )); do
        case "$CHAPTER" in
            1) capitulo_1 ;;
            2) capitulo_2 ;;
            3) capitulo_3 ;;
            4) capitulo_4 ;;
            5) capitulo_5 ;;
            6) capitulo_6 ;;
            7) capitulo_7 ;;
            8) capitulo_8 ;;
        esac
        CHAPTER=$((CHAPTER+1))
        if ! guardar; then
            printf '%sAviso: no se pudo guardar automáticamente la partida.%s\n' "$RED" "$RST"
        fi
    done
    determinar_final
    mostrar_final
    borrar_guardado
}

reiniciar_variables() {
    SAVE_VERSION=2; CHAPTER=1; NOMBRE="Alex"
    INTEGRIDAD=0; EMPATIA=0; CRITERIO=0; CORAJE=0; LEALTAD=0; PRUDENCIA=0
    PRESION=0; REPUTACION=0; MIA=0; GAEL=0; ABRIL=0
    VIO_PUBLICACION=0; PIDIO_DATOS=0; GAEL_HABLO=0; CULPO_GAEL=0
    ACCESO_CONSENTIDO=0; ACCESO_SIN_PERMISO=0; RECONSTRUYO=0; PIDIO_ADULTO=0
    PIDIO_ORIGEN=0; PRESIONO_BRUNO=0; SOLICITO_CORRECCION=0; CONSERVA_AUDIO=0
    AUDIO_CONSENTIDO=0; PUBLICO_AUDIO=0; ABRIL_CONFESO=0; ESCUCHO_ABRIL=0
    GUARDO_ORIGEN=0; REVELO_ABRIL=0; INFORME_COMPLETO=0; EXPUSO_CHAT=0
    OCULTO_FALLOS=0; PIDIO_AUDITORIA=0; PRESENTO_HONESTO=0; PRESENTO_COLECTIVO=0
    MINTIO=0; RETIRAR=0; FINAL_ID=""
}

jugar_nuevo() {
    reiniciar_variables
    introduccion
    jugar_desde_capitulo
}

continuar_partida() {
    if ! cargar; then
        printf '%sNo hay una partida compatible para continuar.%s\n' "$RED" "$RST"
        pausa
        return
    fi
    pantalla_titulo
    printf '%sPARTIDA RECUPERADA%s\n\n' "$GREEN$BOLD" "$RST"
    escribir "Personaje: $NOMBRE"
    escribir "Continuarás desde el capítulo $CHAPTER. Las decisiones anteriores se mantienen."
    estado
    pausa
    jugar_desde_capitulo
}

mostrar_ayuda() {
    pantalla_titulo
    printf '%sCÓMO JUGAR%s\n\n' "$CYAN$BOLD" "$RST"
    escribir "FUERA DE CONTEXTO es una aventura narrativa sobre reputación, privacidad, amistad, presión y responsabilidad digital."
    escribir "En cada capítulo elige una de cuatro opciones. No existe una ruta perfecta: algunas decisiones protegen a una persona y complican otra parte del problema."
    escribir "Tus elecciones modifican seis dimensiones del perfil: integridad, empatía, criterio, coraje, lealtad y prudencia. Al final verás qué prioridades dominaron esta partida y cómo influyeron en el desenlace."
    escribir "La partida se guarda automáticamente al terminar cada capítulo. Puedes cerrar la terminal y continuar más tarde desde el menú."
    printf '\nComandos:\n'
    printf '  %sTYPING=0 ./fuera_de_contexto.sh%s   texto instantáneo\n' "$GREEN" "$RST"
    printf '  %sNO_COLOR=1 ./fuera_de_contexto.sh%s sin colores\n' "$GREEN" "$RST"
    printf '  %s./fuera_de_contexto.sh --borrar-guardado%s eliminar guardado\n' "$GREEN" "$RST"
    pausa
}

menu() {
    while true; do
        pantalla_titulo
        printf '\n%sUNA PUBLICACIÓN. CUARENTA Y SIETE SEGUNDOS. OCHO DECISIONES.%s\n\n' "$WHITE$BOLD" "$RST"
        printf '  %s1)%s Nueva historia\n' "$CYAN$BOLD" "$RST"
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
                printf '%sGracias por jugar FUERA DE CONTEXTO.%s\n\n' "$CYAN" "$RST"
                exit 0
                ;;
            *) printf '%sOpción no válida.%s\n' "$RED" "$RST"; sleep 0.5 ;;
        esac
    done
}

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

if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'Este juego necesita ejecutarse directamente en una terminal interactiva.\n' >&2
    printf 'Usa: ./fuera_de_contexto.sh\n' >&2
    exit 1
fi

menu
