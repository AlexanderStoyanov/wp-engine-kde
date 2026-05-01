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

# Derive the Fedora version from the host OS so the container always
# matches the host's shared-library ABIs.  Falls back to 44 if undetectable.
HOST_FEDORA_VERSION="44"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    HOST_FEDORA_VERSION="${VERSION_ID:-44}"
fi
CONTAINER_IMAGE="registry.fedoraproject.org/fedora:${HOST_FEDORA_VERSION}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# Check if the existing binary actually works (shared libs may have changed
# after an OS upgrade).  If it doesn't, treat it as a forced rebuild.
if [[ "$FORCE" == false && -x "$LWE_BIN" ]]; then
    if "$LWE_BIN" --help &>/dev/null; then
        ok "linux-wallpaperengine is already installed: $LWE_BIN"
        echo "  Use --force to rebuild anyway."
        exit 0
    else
        warn "Existing binary is broken (likely an OS upgrade changed shared libraries)."
        info "Triggering automatic rebuild …"
        FORCE=true
    fi
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

# ── 1. Create / recreate container ────────────────────────────────────

if distrobox list 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    # Check if the container image matches the host version
    CONTAINER_IMG="$(podman inspect --format '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$CONTAINER_IMG" == *":${HOST_FEDORA_VERSION}" ]]; then
        ok "Container '$CONTAINER_NAME' matches host (Fedora $HOST_FEDORA_VERSION)."
    else
        warn "Container is based on '${CONTAINER_IMG}' but host is Fedora $HOST_FEDORA_VERSION."
        info "Removing outdated container …"
        distrobox rm "$CONTAINER_NAME" --force
        info "Creating distrobox container '$CONTAINER_NAME' (Fedora $HOST_FEDORA_VERSION) …"
        distrobox create --name "$CONTAINER_NAME" --image "$CONTAINER_IMAGE" --yes
        ok "Container recreated."
    fi
else
    info "Creating distrobox container '$CONTAINER_NAME' (Fedora $HOST_FEDORA_VERSION) …"
    distrobox create --name "$CONTAINER_NAME" --image "$CONTAINER_IMAGE" --yes
    ok "Container created."
fi

# ── 2. Install deps, clone, patch, build ─────────────────────────────

info "Installing build dependencies and building (this may take a few minutes) …"

distrobox enter "$CONTAINER_NAME" -- bash -ec '
    sudo dnf install -y \
        gcc g++ cmake ninja-build git bzip2 tar \
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

    # Clean build to avoid stale cmake cache pointing at old library versions
    rm -rf build
    mkdir -p build && cd build

    echo "▸ Configuring …"
    # First pass: let cmake download CEF (may fail to extract on some systems)
    cmake -DCMAKE_BUILD_TYPE=Release -G Ninja .. 2>&1 || true

    # CMake'\''s built-in extractor can choke on the long CEF directory names.
    # If the CEF dir is missing, extract with tar and re-run cmake.
    CEF_TAR=(cef/cef_binary_*.tar.bz2)
    if [ -f "${CEF_TAR[0]}" ]; then
        CEF_DIR_NAME="${CEF_TAR[0]%.tar.bz2}"
        CEF_DIR_NAME="${CEF_DIR_NAME#cef/}"
        if [ ! -d "cef/${CEF_DIR_NAME}" ]; then
            echo "▸ Re-extracting CEF archive with tar …"
            tar xjf "${CEF_TAR[0]}" -C cef/
        fi
        if [ -d "cef/${CEF_DIR_NAME}" ] && [ ! -f build.ninja ]; then
            cmake -DCMAKE_BUILD_TYPE=Release -G Ninja .. || { echo "✗ CMake configuration failed"; exit 1; }
        fi
    fi

    [ -f build.ninja ] || { echo "✗ CMake configuration failed — no build.ninja generated"; exit 1; }

    echo "▸ Building …"
    ninja -j$(nproc)
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

# Build the host's library list BEFORE entering the container, so we compare
# against the host's ldconfig rather than the container's.
HOST_LIBS_LIST=$(mktemp)
ldconfig -p 2>/dev/null | awk -F' ' '/=>/{print $1}' | sort -u > "$HOST_LIBS_LIST"

distrobox enter "$CONTAINER_NAME" -- bash -ec '
    LIB_DIR="'"$LWE_LIB_DIR"'"
    HOST_LIBS="'"$HOST_LIBS_LIST"'"
    BINARY="'"$BUILD_OUTPUT"'/linux-wallpaperengine"
    copied=0
    for lib in $(ldd "$BINARY" 2>/dev/null | grep "=> /" | awk "{print \$3}" | sort -u); do
        lib_name="$(basename "$lib")"
        if ! grep -qx "$lib_name" "$HOST_LIBS" 2>/dev/null; then
            cp -L "$lib" "$LIB_DIR/" 2>/dev/null && copied=$((copied + 1))
        fi
    done
    echo "$copied"
' | while read -r n; do ok "Copied $n libraries to $LWE_LIB_DIR"; done
rm -f "$HOST_LIBS_LIST"

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
