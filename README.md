# Wallpaper Engine for KDE

A KDE Plasma 6 wallpaper plugin that plays **Wallpaper Engine** backgrounds (video and scene) on your Linux desktop.

## Features

- **Video wallpapers** via Qt Multimedia (no external dependencies)
- **Scene wallpapers** via [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)
- **Per-screen wallpapers** — each monitor runs its own renderer process
- Right-click desktop context menu works (requires [patched renderer](#upstream-patch-for-linux-wallpaperengine))
- Configurable FPS, fill mode, volume, playback speed

## Quick start

```bash
git clone https://github.com/AlexanderStoyanov/wp-engine-kde.git
cd wp-engine-kde
bash install.sh
```

The installer will:
- Install the KDE wallpaper plugin
- Auto-detect your Steam library
- Check for `linux-wallpaperengine` — if missing and `distrobox` is available, offer to **build it automatically**
- Restart Plasma so the plugin is ready to use

Then right-click your desktop → **Configure Desktop and Wallpaper** → select **Wallpaper Engine for KDE**.

## Requirements

- **KDE Plasma 6** (tested on 6.6+)
- **Qt 6** (tested on 6.10+)
- **Steam** with Wallpaper Engine installed (for assets and workshop content)
- **linux-wallpaperengine** for scene wallpapers (video wallpapers work without it)

## Installing linux-wallpaperengine

Scene wallpapers need the [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) renderer. Video wallpapers work without it.

### Automatic (recommended for immutable distros)

If `distrobox` is available, the installer offers to build everything automatically. You can also run it standalone:

```bash
bash build-lwe.sh
```

This creates a distrobox container, installs build dependencies, clones the repo, applies the [KDE compatibility patch](#upstream-patch-for-linux-wallpaperengine), builds, and installs a native wrapper to `~/.local/bin/`. The wrapper runs the binary directly on the host with bundled libraries — this is important for GPU-accelerated rendering (running through the container falls back to software rendering). Re-run with `--force` to rebuild.

### Arch Linux (AUR)

```bash
yay -S linux-wallpaperengine-git
```

### Fedora (COPR)

```bash
sudo dnf copr enable jiashy/linux-wallpaperengine
sudo dnf install linux-wallpaperengine
```

### Build from source (manual)

```bash
git clone --recurse-submodules https://github.com/Almamu/linux-wallpaperengine.git
cd linux-wallpaperengine
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
sudo cp output/linux-wallpaperengine /usr/local/bin/
# or: cp output/linux-wallpaperengine ~/.local/bin/
```

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| Steam library path | Path to your Steam installation | Auto-detected |
| Fill mode | Scaled and cropped / Stretched / Fit | Scaled and cropped |
| Audio | Mute toggle + volume slider | Muted, 100% |
| Speed | Playback speed multiplier (0.25x – 2.00x) | 1.00x |
| Scene FPS | Target framerate for scene wallpapers (0 = unlimited) | 60 |
| Scene renderer | Custom path to `linux-wallpaperengine` binary | Auto-detect |

## Upstream patches for linux-wallpaperengine

We maintain a [fork](https://github.com/AlexanderStoyanov/linux-wallpaperengine) with fixes submitted as individual PRs:

1. **Wayland KDE compat** ([PR #528](https://github.com/Almamu/linux-wallpaperengine/pull/528)) — click-through input region + BOTTOM layer for KDE Plasma compatibility. Applied automatically by `build-lwe.sh` via `patches/lwe-kde-compat.patch`.
2. **Shader compilation fixes** — `#require` module resolution, HLSL `log10` macro conflict, implicit vector truncation. These fix gray/black scenes for ~30 wallpapers. See [SHADER_FIXES.md](SHADER_FIXES.md) for details, e2e test results, and the fix/test pipeline.

To apply manually:

```bash
cd linux-wallpaperengine
git apply /path/to/wp-engine-kde/patches/lwe-kde-compat.patch
cd build && cmake --build . -j$(nproc)
```

## Troubleshooting

**Scene wallpapers are choppy / high CPU** — the renderer may be software-rendering instead of using the GPU. Check with `nvidia-smi pmon -c 1` — you should see `linux-wallpaper` in the process list. If not, rebuild with `bash build-lwe.sh --force` to create a native wrapper (distrobox-exported wrappers don't have GPU access).

**Scene wallpaper shows black screen** — check the log:

```bash
cat ${XDG_RUNTIME_DIR}/wp-engine-kde-scene-DP-1.log
# Replace DP-1 with your output name (kscreen-doctor --outputs)
```

**Right-click doesn't work** — apply the upstream patch above and rebuild.

**Process leaks** — stop all scene renderers:

```bash
pkill -u $USER -f "linux-wallpaperengine.*--screen-root"
```

## Uninstalling

```bash
bash uninstall.sh
```

This stops all renderer processes, cleans up PID/log files, removes the plugin, and restarts Plasma. It will also list optional manual steps for removing the native binary and build container.

## Architecture

```
plugin/
├── metadata.json              # KDE plugin metadata
└── contents/
    ├── config/main.xml        # Config schema (kcfg)
    ├── scripts/
    │   ├── scan_wallpapers.py # Scans Workshop folder for wallpapers
    │   └── scene_manager.sh   # Manages per-screen renderer processes
    └── ui/
        ├── main.qml           # Wallpaper rendering logic
        └── config.qml         # Settings UI
```

**Video wallpapers** use Qt's `MediaPlayer` + `VideoOutput` — fully native, no external process.

**Scene wallpapers** shell out to `linux-wallpaperengine`, which renders via `wlr-layer-shell`. Each screen gets its own process managed by `scene_manager.sh` with PID files under `$XDG_RUNTIME_DIR/`.
