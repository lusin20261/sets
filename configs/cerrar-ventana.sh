#!/bin/bash
zenity --question \
    --title="Cerrar ventana" \
    --text="¿Deseas cerrar esta ventana?" \
    --ok-label="Cerrar" \
    --cancel-label="Cancelar" 2>/dev/null && \
xdotool getactivewindow windowclose
