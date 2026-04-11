#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/plugin" && pwd)"
PLUGIN_ID="com.github.wpEngineKde"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

detect_steam_library() {
    local candidates=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam"
        "$HOME/snap/steam/common/.local/share/Steam"
        "/usr/share/Steam"
    )
    for p in "${candidates[@]}"; do
        if [[ -d "$p/steamapps/common/wallpaper_engine" ]]; then
            echo "$p"
            return 0
        fi
    done
    for p in "${candidates[@]}"; do
        if [[ -d "$p/steamapps" ]]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

find_lwe_binary() {
    local candidates=(
        "$HOME/.local/bin/linux-wallpaperengine"
        "/usr/local/bin/linux-wallpaperengine"
        "/usr/bin/linux-wallpaperengine"
    )
    for c in "${candidates[@]}"; do
        [[ -x "$c" ]] && { echo "$c"; return 0; }
    done
    command -v linux-wallpaperengine 2>/dev/null && return 0
    return 1
}

# ── Main install ─────────────────────────────────────────────────────

main_install() {
    echo ""
    echo "  Wallpaper Engine for KDE — Installer"
    echo "  ─────────────────────────────────────"
    echo ""

    # 1. Install the plugin
    info "Installing wallpaper plugin …"
    if kpackagetool6 -t Plasma/Wallpaper -s "$PLUGIN_ID" &>/dev/null; then
        kpackagetool6 -t Plasma/Wallpaper -u "$PLUGIN_DIR" 2>/dev/null
        ok "Plugin updated."
    else
        kpackagetool6 -t Plasma/Wallpaper -i "$PLUGIN_DIR" 2>/dev/null
        ok "Plugin installed."
    fi

    # 2. Detect Steam library
    echo ""
    if steam_path=$(detect_steam_library); then
        ok "Steam library found: $steam_path"
        if [[ -d "$steam_path/steamapps/common/wallpaper_engine" ]]; then
            ok "Wallpaper Engine assets found."
        else
            warn "Wallpaper Engine not found in Steam library."
            warn "Install it via Steam, then set the path in plugin settings."
        fi
    else
        warn "Steam library not found."
        warn "Set the Steam library path manually in plugin settings."
    fi

    # 3. Check for linux-wallpaperengine (scene renderer)
    echo ""
    if lwe_path=$(find_lwe_binary); then
        ok "Scene renderer found: $lwe_path"
    else
        warn "Scene renderer (linux-wallpaperengine) not found."
        echo ""
        echo "  Video wallpapers will work, but scene wallpapers need the renderer."
        echo ""

        if command -v distrobox &>/dev/null; then
            echo "  distrobox detected — would you like to build it automatically?"
            echo ""
            read -r -p "  Build linux-wallpaperengine now? [Y/n] " answer
            if [[ "${answer,,}" != "n" ]]; then
                echo ""
                bash "$SCRIPT_DIR/build-lwe.sh"
                echo ""
                if lwe_path=$(find_lwe_binary); then
                    ok "Scene renderer ready: $lwe_path"
                fi
            fi
        else
            echo "  Install options:"
            echo "    Arch:    yay -S linux-wallpaperengine-git"
            echo "    Fedora:  sudo dnf copr enable jiashy/linux-wallpaperengine && sudo dnf install linux-wallpaperengine"
            echo "    Any:     bash build-lwe.sh  (requires distrobox)"
            echo "    Source:  See README.md for manual build instructions"
            echo ""
        fi
    fi

    # 4. Restart Plasma
    echo ""
    info "Restarting Plasma …"
    systemctl --user restart plasma-plasmashell.service 2>/dev/null && ok "Plasma restarted." || warn "Could not restart Plasma. Restart manually or log out/in."

    echo ""
    echo "  ─────────────────────────────────────"
    echo "  Next: Right-click desktop → Configure Desktop and Wallpaper"
    echo "        Select 'Wallpaper Engine for KDE' from the dropdown."
    if [[ -n "${steam_path:-}" ]]; then
        echo "        Steam library detected at: $steam_path"
    fi
    echo ""
}

# ── Entry point ──────────────────────────────────────────────────────

case "${1:-}" in
    --help|-h)
        echo "Usage:"
        echo "  bash install.sh    Install/update the KDE plugin (auto-builds renderer if needed)"
        ;;
    *)
        main_install
        ;;
esac
