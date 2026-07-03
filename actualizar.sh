#!/bin/bash
# actualizar.sh
# Trae los últimos cambios del repo y corre la sincronización completa

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$REPO_DIR" || exit 1

echo "Actualizando repositorio..."
git pull origin main

echo "Ejecutando sincronización..."
"$REPO_DIR/sync-sets.sh"

notify-send -i software-update-available "Sistema actualizado" "La configuración del laboratorio se actualizó correctamente."
