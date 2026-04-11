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

# 4. Remove native binary and bundled libraries
if [[ -x "$HOME/.local/bin/linux-wallpaperengine" ]]; then
    echo ""
    read -r -p "  Remove ~/.local/bin/linux-wallpaperengine? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -f "$HOME/.local/bin/linux-wallpaperengine"
        ok "Native wrapper removed."
    fi
fi

if [[ -d "$HOME/.local/lib/linux-wallpaperengine" ]]; then
    read -r -p "  Remove ~/.local/lib/linux-wallpaperengine/ (bundled libs)? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -rf "$HOME/.local/lib/linux-wallpaperengine"
        ok "Bundled libraries removed."
    fi
fi

# 5. Remove build container
if command -v distrobox &>/dev/null; then
    for container in lwe-build lwe-dev; do
        if distrobox list 2>/dev/null | grep -q "$container"; then
            read -r -p "  Remove distrobox container '$container'? [y/N] " answer
            if [[ "${answer,,}" == "y" ]]; then
                distrobox rm "$container" --force 2>/dev/null
                ok "Container '$container' removed."
            fi
        fi
    done
fi

# 6. Restart Plasma
echo ""
info "Restarting Plasma …"
systemctl --user restart plasma-plasmashell.service 2>/dev/null && ok "Plasma restarted." || warn "Could not restart Plasma. Log out/in to complete removal."

echo ""
echo "  ───────────────────────────────────────"
echo "  Uninstall complete."
echo ""
