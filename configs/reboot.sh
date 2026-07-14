#!/bin/bash

if zenity --question \
    --title="Reiniciar Equipo" \
    --text="¿Está seguro de que desea reiniciar el equipo?" \
    --width=300; then
    systemctl reboot
fi
