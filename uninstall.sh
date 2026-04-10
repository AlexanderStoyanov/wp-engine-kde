#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="com.github.wpEngineKde"

echo "Removing wallpaper plugin: $PLUGIN_ID"
kpackagetool6 -t Plasma/Wallpaper -r "$PLUGIN_ID"

echo ""
echo "Done! Restart Plasma to complete removal:"
echo "  systemctl --user restart plasma-plasmashell.service"
