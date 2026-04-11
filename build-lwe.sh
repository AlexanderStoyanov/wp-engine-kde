#!/usr/bin/env bash
set -euo pipefail

# Builds linux-wallpaperengine inside a distrobox container and creates
# a native wrapper at ~/.local/bin/linux-wallpaperengine that runs directly
# on the host (with GPU access) by bundling any missing shared libraries.
#
# Usage:  bash build-lwe.sh [--force]
#   --force   Rebuild even if the binary already exists

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="lwe-build"
CONTAINER_IMAGE="registry.fedoraproject.org/fedora:43"
LWE_REPO="https://github.com/Almamu/linux-wallpaperengine.git"
LWE_SRC="linux-wallpaperengine"
LWE_HOST_DIR="$HOME/$LWE_SRC"
LWE_LIB_DIR="$HOME/.local/lib/linux-wallpaperengine"
LWE_BIN="$HOME/.local/bin/linux-wallpaperengine"
PATCH_FILE="$SCRIPT_DIR/patches/lwe-kde-compat.patch"

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

if [[ "$FORCE" == false && -x "$LWE_BIN" ]]; then
    ok "linux-wallpaperengine is already installed: $LWE_BIN"
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

distrobox enter "$CONTAINER_NAME" -- bash -ec '
    sudo dnf install -y \
        gcc g++ cmake ninja-build git \
        libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel \
        mesa-libGL-devel glew-devel freeglut-devel SDL2-devel lz4-devel \
        ffmpeg-free-devel libXxf86vm-devel glm-devel glfw-devel \
        mpv-devel pulseaudio-libs-devel fftw-devel gmp-devel 2>&1 | tail -1

    SRC="$HOME/'"$LWE_SRC"'"
    if [ ! -d "$SRC" ]; then
        echo "▸ Cloning linux-wallpaperengine …"
        git clone --recurse-submodules '"$LWE_REPO"' "$SRC"
    else
        echo "✓ Source already cloned."
        cd "$SRC" && git pull --ff-only 2>/dev/null || true
    fi

    cd "$SRC"

    PATCH="'"$PATCH_FILE"'"
    if [ -f "$PATCH" ]; then
        echo "▸ Applying KDE compatibility patch …"
        git apply "$PATCH" 2>/dev/null && echo "✓ Patch applied." || echo "✓ Patch already applied or merged upstream."
    fi

    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release -G Ninja .. 2>&1 | tail -3
    echo "▸ Building …"
    ninja -j$(nproc) 2>&1 | tail -3
    echo "✓ Build complete."
'

# ── 3. Bundle missing libraries ──────────────────────────────────────

BUILD_OUTPUT="$LWE_HOST_DIR/build/output"
if [[ ! -x "$BUILD_OUTPUT/linux-wallpaperengine" ]]; then
    err "Build output not found at $BUILD_OUTPUT"
    exit 1
fi

info "Bundling shared libraries for native execution …"
mkdir -p "$LWE_LIB_DIR"

# Get list of shared libs from the container, copy ones missing on host
CONTAINER_ID=$(podman ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.ID}}' | head -1)
NEEDED_LIBS=$(distrobox enter "$CONTAINER_NAME" -- ldd "$BUILD_OUTPUT/linux-wallpaperengine" 2>/dev/null \
    | grep "=> /" | awk '{print $3}' | sort -u)

copied=0
for lib in $NEEDED_LIBS; do
    lib_name=$(basename "$lib")
    # Skip libs that exist on the host
    if ldconfig -p 2>/dev/null | grep -q "$lib_name" && [[ -e "$lib" ]]; then
        continue
    fi
    # Copy from container
    if podman cp "${CONTAINER_NAME}:${lib}" "$LWE_LIB_DIR/" 2>/dev/null; then
        ((copied++))
    fi
done
ok "Copied $copied libraries to $LWE_LIB_DIR"

# ── 4. Create native wrapper ─────────────────────────────────────────

info "Creating native wrapper …"
mkdir -p "$HOME/.local/bin"
cat > "$LWE_BIN" << WRAPPER
#!/bin/sh
LWE_DIR="$BUILD_OUTPUT"
export LD_LIBRARY_PATH="$LWE_LIB_DIR:\${LWE_DIR}:\${LD_LIBRARY_PATH:-}"
exec "\${LWE_DIR}/linux-wallpaperengine" "\$@"
WRAPPER
chmod +x "$LWE_BIN"

# ── 5. Verify ────────────────────────────────────────────────────────

echo ""
if "$LWE_BIN" --help &>/dev/null; then
    ok "Native binary works! Installed at: $LWE_BIN"
else
    warn "Binary may need additional libraries. Run: LD_LIBRARY_PATH=$LWE_LIB_DIR ldd $BUILD_OUTPUT/linux-wallpaperengine"
fi

echo ""
echo "  ────────────────────────────────────────"
echo "  Done! You can now run: bash install.sh"
echo ""
