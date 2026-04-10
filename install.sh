#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/plugin" && pwd)"
PLUGIN_ID="com.github.wpEngineKde"

echo "Installing wallpaper plugin from: $PLUGIN_DIR"

if kpackagetool6 -t Plasma/Wallpaper -s "$PLUGIN_ID" &>/dev/null; then
    echo "Plugin already installed, updating..."
    kpackagetool6 -t Plasma/Wallpaper -u "$PLUGIN_DIR"
else
    echo "Installing plugin..."
    kpackagetool6 -t Plasma/Wallpaper -i "$PLUGIN_DIR"
fi

echo ""
echo "Done! To activate:"
echo "  1. Restart Plasma:  systemctl --user restart plasma-plasmashell.service"
echo "  2. Right-click desktop -> Configure Desktop and Wallpaper"
echo "  3. Select 'Wallpaper Engine for KDE' from the wallpaper type dropdown"
