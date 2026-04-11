#!/usr/bin/env bash
# Manages linux-wallpaperengine subprocesses for scene wallpapers.
# Each screen gets its own process and PID file so Plasma's per-screen
# wallpaper containments work independently.
#
# Usage:
#   scene_manager.sh start <workshop_id> <assets_dir> <fps> <screen_name> [lwe_binary]
#   scene_manager.sh stop [screen_name]       # omit screen_name to stop all
#   scene_manager.sh status [screen_name]

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PID_PREFIX="wp-engine-kde-scene"

pidfile_for() {
    local screen="${1:-all}"
    echo "${RUNTIME_DIR}/${PID_PREFIX}-${screen}.pid"
}

logfile_for() {
    local screen="${1:-all}"
    echo "${RUNTIME_DIR}/${PID_PREFIX}-${screen}.log"
}

find_lwe_binary() {
    local custom_path="${1:-}"
    if [[ -n "$custom_path" && -x "$custom_path" ]]; then
        echo "$custom_path"
        return 0
    fi

    local candidates=(
        "$HOME/.local/bin/linux-wallpaperengine"
        "/usr/local/bin/linux-wallpaperengine"
        "/usr/bin/linux-wallpaperengine"
    )

    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done

    if command -v linux-wallpaperengine &>/dev/null; then
        command -v linux-wallpaperengine
        return 0
    fi

    return 1
}

# Build the launch command array.
# Native wrappers (with LD_LIBRARY_PATH) are strongly preferred — they get
# direct GPU access. Distrobox-exported wrappers fall back to podman exec
# to avoid FIFO deadlocks, but lose GPU access (software rendering).
build_launch_cmd() {
    local binary="$1"
    shift

    if [[ -f "$binary" ]] && head -3 "$binary" 2>/dev/null | grep -q "distrobox_binary"; then
        echo "WARNING: $binary is a distrobox wrapper — GPU access may be unavailable (software rendering)." >&2
        echo "WARNING: Rebuild with 'bash build-lwe.sh --force' for native GPU-accelerated execution." >&2
        local container_name inner_binary
        container_name=$(grep -oP '(?<=# name: ).*' "$binary" | head -1)
        inner_binary=$(grep -oP "(?<=')/[^']+linux-wallpaperengine[^']*(?=')" "$binary" | head -1)
        if [[ -n "$container_name" && -n "$inner_binary" ]]; then
            podman start "$container_name" &>/dev/null || true
            sleep 1
            LAUNCH_CMD=(
                podman exec
                --user "$USER"
                --env "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}"
                --env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
                --env "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-wayland}"
                --env "DISPLAY=${DISPLAY:-:0}"
                "$container_name"
                "$inner_binary" "$@"
            )
            return 0
        fi
    fi

    LAUNCH_CMD=("$binary" "$@")
}

kill_pid() {
    local pid="$1"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6; do
            kill -0 "$pid" 2>/dev/null || return 0
            sleep 0.5
        done
        kill -9 "$pid" 2>/dev/null || true
    fi
}

stop_screen() {
    local screen="$1"
    local pf
    pf=$(pidfile_for "$screen")
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf" 2>/dev/null || true)
        kill_pid "${pid:-}"
        rm -f "$pf"
    fi
    # Also kill by pattern to catch the actual renderer when running through
    # distrobox/podman wrappers (killing the wrapper PID alone may leave the
    # real process orphaned).
    pkill -u "$USER" -f "linux-wallpaperengine.*--screen-root ${screen}( |$)" 2>/dev/null || true
}

stop_all() {
    for pf in "${RUNTIME_DIR}/${PID_PREFIX}"-*.pid; do
        [[ -f "$pf" ]] || continue
        local pid
        pid=$(cat "$pf" 2>/dev/null || true)
        kill_pid "${pid:-}"
        rm -f "$pf"
    done
    pkill -u "$USER" -f "linux-wallpaperengine.*--screen-root" 2>/dev/null || true
}

start_scene() {
    local workshop_id="$1"
    local assets_dir="$2"
    local fps="${3:-60}"
    local screen="$4"
    local custom_binary="${5:-}"
    local muted="${6:-true}"
    local volume="${7:-100}"
    local scaling="${8:-}"

    stop_screen "$screen"

    local lwe
    if ! lwe=$(find_lwe_binary "$custom_binary"); then
        echo '{"status":"error","message":"linux-wallpaperengine binary not found. Install it or set the path in plugin settings."}'
        return 1
    fi

    if [[ ! -d "$assets_dir" ]]; then
        echo '{"status":"error","message":"Wallpaper Engine assets directory not found: '"$assets_dir"'"}'
        return 1
    fi

    if [[ -z "$screen" ]]; then
        echo '{"status":"error","message":"No screen name provided"}'
        return 1
    fi

    local fps_args=()
    if [[ "$fps" -gt 0 ]]; then
        fps_args=(--fps "$fps")
    fi

    local audio_args=()
    if [[ "$muted" == "true" ]]; then
        audio_args=(--silent)
    else
        audio_args=(--noautomute --volume "$volume")
    fi

    local scaling_args=()
    if [[ -n "$scaling" && "$scaling" != "default" ]]; then
        scaling_args=(--scaling "$scaling")
    fi

    local logfile
    logfile=$(logfile_for "$screen")

    build_launch_cmd "$lwe" \
        --assets-dir "$assets_dir" \
        --disable-mouse \
        "${fps_args[@]}" \
        "${audio_args[@]}" \
        "${scaling_args[@]}" \
        --screen-root "$screen" \
        "$workshop_id"

    "${LAUNCH_CMD[@]}" >"$logfile" 2>&1 &

    local pid=$!
    echo "$pid" > "$(pidfile_for "$screen")"

    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
        echo '{"status":"running","pid":'"$pid"',"screen":"'"$screen"'","binary":"'"$lwe"'"}'
    else
        local log_tail
        log_tail=$(tail -5 "$logfile" 2>/dev/null | tr '\n' ' ' | tr '"' "'")
        echo '{"status":"error","message":"Process exited immediately ('"$screen"'): '"$log_tail"'"}'
        rm -f "$(pidfile_for "$screen")"
        return 1
    fi
}

get_status() {
    local screen="${1:-}"
    if [[ -n "$screen" ]]; then
        local pf
        pf=$(pidfile_for "$screen")
        if [[ -f "$pf" ]]; then
            local pid
            pid=$(cat "$pf" 2>/dev/null || true)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo '{"status":"running","pid":'"$pid"',"screen":"'"$screen"'"}'
                return 0
            fi
            rm -f "$pf"
        fi
        echo '{"status":"stopped","screen":"'"$screen"'"}'
    else
        local any_running=false
        for pf in "${RUNTIME_DIR}/${PID_PREFIX}"-*.pid; do
            [[ -f "$pf" ]] || continue
            local pid
            pid=$(cat "$pf" 2>/dev/null || true)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                any_running=true
            else
                rm -f "$pf"
            fi
        done
        if $any_running; then
            echo '{"status":"running"}'
        else
            echo '{"status":"stopped"}'
        fi
    fi
}

case "${1:-}" in
    start)
        start_scene \
            "${2:?workshop_id required}" \
            "${3:?assets_dir required}" \
            "${4:-60}" \
            "${5:?screen_name required}" \
            "${6:-}" \
            "${7:-true}" \
            "${8:-100}" \
            "${9:-}"
        ;;
    stop)
        if [[ -n "${2:-}" ]]; then
            stop_screen "$2"
        else
            stop_all
        fi
        echo '{"status":"stopped"}'
        ;;
    status)
        get_status "${2:-}"
        ;;
    *)
        echo '{"status":"error","message":"Usage: scene_manager.sh start|stop|status"}'
        exit 1
        ;;
esac
