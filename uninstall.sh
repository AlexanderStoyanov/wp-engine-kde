#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="com.github.wpEngineKde"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }

echo ""
echo "  Wallpaper Engine for KDE — Uninstaller"
echo "  ───────────────────────────────────────"
echo ""

# 1. Stop all scene renderer processes
info "Stopping scene renderer processes …"
pkill -u "$USER" -f "linux-wallpaperengine.*--screen-root" 2>/dev/null && ok "Processes stopped." || ok "No processes running."

# 2. Clean up PID files and logs
info "Cleaning up runtime files …"
rm -f "$RUNTIME_DIR"/wp-engine-kde-scene-*.pid 2>/dev/null
rm -f "$RUNTIME_DIR"/wp-engine-kde-scene-*.log 2>/dev/null
ok "Runtime files removed."

# 3. Remove the plugin
info "Removing wallpaper plugin …"
if kpackagetool6 -t Plasma/Wallpaper -s "$PLUGIN_ID" &>/dev/null; then
    kpackagetool6 -t Plasma/Wallpaper -r "$PLUGIN_ID" 2>/dev/null
    ok "Plugin removed."
else
    ok "Plugin was not installed."
fi

# 4. Restart Plasma
info "Restarting Plasma …"
systemctl --user restart plasma-plasmashell.service 2>/dev/null && ok "Plasma restarted." || warn "Could not restart Plasma. Log out/in to complete removal."

echo ""
echo "  ───────────────────────────────────────"
echo "  Plugin uninstalled."
echo ""
echo "  Optional manual cleanup:"
echo "    rm ~/.local/bin/linux-wallpaperengine       # Native wrapper"
echo "    rm -rf ~/.local/lib/linux-wallpaperengine/  # Bundled libraries"
echo "    distrobox rm lwe-build                      # Build container"
echo ""
