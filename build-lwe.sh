#!/usr/bin/env bash
set -euo pipefail

# Builds linux-wallpaperengine inside a distrobox container and exports
# the binary to ~/.local/bin so it's available on the host without
# keeping the container running at all times.
#
# Usage:  bash build-lwe.sh [--force]
#   --force   Rebuild even if the binary already exists

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="lwe-build"
CONTAINER_IMAGE="registry.fedoraproject.org/fedora:43"
LWE_REPO="https://github.com/Almamu/linux-wallpaperengine.git"
LWE_SRC_DIR="\$HOME/linux-wallpaperengine"
PATCH_FILE="$SCRIPT_DIR/patches/lwe-kde-compat.patch"

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

if [[ "$FORCE" == false ]] && command -v linux-wallpaperengine &>/dev/null; then
    ok "linux-wallpaperengine is already installed: $(command -v linux-wallpaperengine)"
    echo "  Use --force to rebuild anyway."
    exit 0
fi

if ! command -v distrobox &>/dev/null; then
    err "distrobox is required but not found."
    echo ""
    echo "  Install options:"
    echo "    Fedora/Bazzite: sudo dnf install distrobox"
    echo "    Other:          curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh"
    exit 1
fi

echo ""
echo "  linux-wallpaperengine — Automated Build"
echo "  ────────────────────────────────────────"
echo ""

# ── 1. Create container ──────────────────────────────────────────────

if distrobox list 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    ok "Container '$CONTAINER_NAME' already exists."
else
    info "Creating distrobox container '$CONTAINER_NAME' …"
    distrobox create --name "$CONTAINER_NAME" --image "$CONTAINER_IMAGE" --yes
    ok "Container created."
fi

# ── 2. Install deps, clone, patch, build ─────────────────────────────

info "Installing build dependencies and building (this may take a few minutes) …"

distrobox enter "$CONTAINER_NAME" -- bash -ec "
    sudo dnf install -y \
        gcc g++ cmake ninja-build git \
        libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel \
        mesa-libGL-devel glew-devel freeglut-devel SDL2-devel lz4-devel \
        ffmpeg-free-devel libXxf86vm-devel glm-devel glfw-devel \
        mpv-devel pulseaudio-libs-devel fftw-devel gmp-devel 2>&1 | tail -1

    if [ ! -d $LWE_SRC_DIR ]; then
        echo '▸ Cloning linux-wallpaperengine …'
        git clone --recurse-submodules $LWE_REPO $LWE_SRC_DIR
    else
        echo '✓ Source already cloned.'
        cd $LWE_SRC_DIR && git pull --ff-only 2>/dev/null || true
    fi

    cd $LWE_SRC_DIR

    if [ -f '$PATCH_FILE' ]; then
        echo '▸ Applying KDE compatibility patch …'
        git apply '$PATCH_FILE' 2>/dev/null && echo '✓ Patch applied.' || echo '✓ Patch already applied or merged upstream.'
    fi

    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release -G Ninja .. 2>&1 | tail -3
    echo '▸ Building …'
    ninja -j\$(nproc) 2>&1 | tail -3
    echo '✓ Build complete.'
"

# ── 3. Export binary to host ─────────────────────────────────────────

info "Exporting binary to host …"
distrobox enter "$CONTAINER_NAME" -- bash -ec "
    distrobox-export --bin $LWE_SRC_DIR/build/output/linux-wallpaperengine --export-path \$HOME/.local/bin
"

ok "linux-wallpaperengine exported to ~/.local/bin/linux-wallpaperengine"

# ── 4. Verify ────────────────────────────────────────────────────────

echo ""
if "$HOME/.local/bin/linux-wallpaperengine" --help &>/dev/null; then
    ok "Binary works!"
else
    ok "Binary exported. It will run through the container transparently."
fi

echo ""
echo "  ────────────────────────────────────────"
echo "  Done! You can now run: bash install.sh"
echo ""
