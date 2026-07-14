#!/bin/bash
# sync-sets.sh
# Sincroniza los archivos del repositorio sets a sus ubicaciones locales
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS="$REPO_DIR/configs"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "${RED}✘${NC} $1"; exit 1; }
echo "Sincronizando desde: $REPO_DIR"
echo "-----------------------------------"
# 1. Ejecutar comandos de notes.txt (primero que todo)
if [ -f "$REPO_DIR/notes.txt" ]; then
    echo "Ejecutando comandos de notes.txt..."
    export DEBIAN_FRONTEND=noninteractive
    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        echo "→ $cmd"
        eval "$cmd"
    done < "$REPO_DIR/notes.txt"
    ok "notes.txt ejecutado"
    echo "-----------------------------------"
fi
# 2. applications/ → ~/.local/share/applications/
SRC_APPS="$REPO_DIR/applications/"
DST_APPS="$HOME/.local/share/applications/"
rsync -a --delete "$SRC_APPS" "$DST_APPS"
ok "applications/ → $DST_APPS"
echo "-----------------------------------"
# 3. Archivos de usuario (sin sudo)
#    formato: "archivo_en_configs|destino_absoluto"
declare -a USER_FILES=(
    "blacklist|$HOME/.config/rofi/blacklist"
    "tint2rc|$HOME/.config/tint2/tint2rc"
    "thunarrc|$HOME/.config/Thunar/thunarrc"
    "gtk-bookmarks|$HOME/.config/gtk-3.0/bookmarks"
    "rc.xml|$HOME/.config/openbox/rc.xml"
    "cerrar-ventana.sh|$HOME/.local/bin/cerrar-ventana.sh"
    "reboot.sh|$HOME/.local/bin/reboot.sh"
)
echo "Sincronizando configuraciones de usuario..."
for entry in "${USER_FILES[@]}"; do
    src="$CONFIGS/${entry%%|*}"
    dst="${entry##*|}"
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    ok "$(basename "$src") → $dst"
done
# Permisos ejecutables para scripts desplegados
chmod +x "$HOME/.local/bin/cerrar-ventana.sh"
chmod +x "$HOME/.local/bin/reboot.sh"
echo "-----------------------------------"
# 4. Archivos de sistema (con sudo)
#    formato: "archivo_en_configs|destino_absoluto"
declare -a SYSTEM_FILES=(
    "whitelist.json|/etc/brave/policies/managed/whitelist.json"
    "default-search.json|/etc/brave/policies/managed/default-search.json"
    "10-disable-dpms.conf|/etc/X11/xorg.conf.d/10-disable-dpms.conf"
    "gpu-flags.json|/etc/brave/policies/managed/gpu-flags.json"
)
echo "Sincronizando configuraciones de sistema..."
for entry in "${SYSTEM_FILES[@]}"; do
    src="$CONFIGS/${entry%%|*}"
    dst="${entry##*|}"
    sudo mkdir -p "$(dirname "$dst")"
    sudo cp -f "$src" "$dst"
    ok "$(basename "$src") → $dst"
done
echo "-----------------------------------"
# 5. Validaciones y ajustes específicos de máquina maestra
echo "Verificando rol de máquina..."
if [ -f "$HOME/.local/isMaster" ]; then
    warn "Máquina maestra detectada"
    
    # 5.1 Quitar veyon-master.desktop de la blacklist
    sed -i '/^veyon-master\.desktop$/d' "$HOME/.config/rofi/blacklist"
    ok "veyon-master.desktop removido de blacklist"
    
    # 5.2 Eliminar whitelist.json para acceso libre a internet
    sudo rm -f "/etc/brave/policies/managed/whitelist.json"
    ok "whitelist.json eliminado (acceso libre a internet en máquina maestra)"
else
    ok "Máquina estudiante detectada"
fi
echo "-----------------------------------"
# 6. rofi-blacklist-sync → ~/.local/bin/  (+chmod +x)
SRC_RBS="$REPO_DIR/rofi-blacklist-sync"
DST_RBS="$HOME/.local/bin/rofi-blacklist-sync"
cp -f "$SRC_RBS" "$DST_RBS"
chmod +x "$DST_RBS"
ok "rofi-blacklist-sync → $DST_RBS"
echo "-----------------------------------"
# 7. Wrapper de actualizar-lab en PATH
if [ ! -f "$HOME/.local/bin/actualizar-lab" ]; then
    printf '%s\n' '#!/bin/bash' 'exec /home/lab/repositorios/sets/actualizar.sh "$@"' \
        > "$HOME/.local/bin/actualizar-lab"
    chmod +x "$HOME/.local/bin/actualizar-lab"
    ok "actualizar-lab creado → ~/.local/bin/actualizar-lab"
else
    ok "actualizar-lab ya existe → sin cambios"
fi
echo "-----------------------------------"
# 8. Recargar tint2
killall tint2 2>/dev/null || true
setsid tint2 &>/dev/null &
ok "tint2 recargado"
echo "-----------------------------------"
# 9. Regenerar menú de Rofi
"$HOME/.local/bin/rofi-blacklist-sync"
ok "Menú de Rofi regenerado"
echo "-----------------------------------"
# 10. Recargar Openbox
openbox --reconfigure
ok "Openbox recargado"
echo "-----------------------------------"
echo -e "${GREEN}¡Sincronización completada!${NC}"
