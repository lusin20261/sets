#!/bin/bash

# sync-sets.sh
# Sincroniza los archivos del repositorio sets a sus ubicaciones locales

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✔${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "${RED}✘${NC} $1"; exit 1; }

echo "Sincronizando desde: $REPO_DIR"
echo "-----------------------------------"

# 1. applications/ → ~/.local/share/applications/
#    rsync sincroniza el contenido directamente sin anidar la carpeta
SRC_APPS="$REPO_DIR/applications/"
DST_APPS="$HOME/.local/share/applications/"
rsync -a --delete "$SRC_APPS" "$DST_APPS"
ok "applications/ → $DST_APPS"

# 2. blacklist → ~/.config/rofi/blacklist
SRC_BL="$REPO_DIR/blacklist"
DST_BL="$HOME/.config/rofi/blacklist"
cp -f "$SRC_BL" "$DST_BL"
ok "blacklist → $DST_BL"

# 3. rofi-blacklist-sync → ~/.local/bin/rofi-blacklist-sync  (+chmod +x)
SRC_RBS="$REPO_DIR/rofi-blacklist-sync"
DST_RBS="$HOME/.local/bin/rofi-blacklist-sync"
cp -f "$SRC_RBS" "$DST_RBS"
sudo chmod +x "$DST_RBS"
ok "rofi-blacklist-sync → $DST_RBS (chmod +x)"

# 4. whitelist.json → /etc/brave/policies/managed/whitelist.json  (sudo)
SRC_WL="$REPO_DIR/whitelist.json"
DST_WL="/etc/brave/policies/managed/whitelist.json"
sudo cp -f "$SRC_WL" "$DST_WL"
ok "whitelist.json → $DST_WL"

echo "-----------------------------------"
echo -e "${GREEN}¡Sincronización completada!${NC}"
