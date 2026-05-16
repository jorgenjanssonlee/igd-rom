#!/usr/bin/env bash
# Guest-side reproduction helper for Linux (i915 / DRM / X11).
# Run *inside* the VM. Phases mirror dmar_fault_repro/PROTOCOL.md.
#
# Dependencies (install as needed):
#   - xorg-x11-xauth / X11 session (Phase A/B/C need DISPLAY)
#   - xset (Fedora: package `xset`; Debian/Ubuntu: package `x11-xserver-utils`)
#   Optional: mpv or ffplay (Phase B), xdotool (Phase C), modetest from intel-gpu-tools (optional tier)

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: repro.sh [command]

Commands:
  all          Run phases A, B, C in order (short pauses).
  phase-a      DPMS / display power cycling (X11).
  phase-b      Video / GPU VO stress (mpv or ffplay if available).
  phase-c      Cursor movement loop (xdotool if available).
  phase-d      Soak stub — prints instructions for long runs.
  probe        Print environment (DISPLAY, session, optional tools).

Environment:
  DISPLAY       e.g. :0 (required for phases A/B/C under X11)
  REPRO_CYCLES  Number of DPMS cycles for phase-a (default: 6)
  REPRO_VIDEO   Local path for mpv in phase-b when offline (optional)
EOF
}

log() {
    printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*"
}

require_x11() {
    if [[ -z "${DISPLAY:-}" ]]; then
        log "WARNING: DISPLAY is unset. For local X11 session try: export DISPLAY=:0"
        log "Wayland-native sessions may need XWayland or run phases manually."
        return 1
    fi
    return 0
}

phase_a() {
    log "Phase A — DPMS / power cycling"
    require_x11 || return 0
    if ! command -v xset >/dev/null 2>&1; then
        log "xset not found — Fedora: sudo dnf install xset ; Debian/Ubuntu: sudo apt install x11-xserver-utils"
        return 1
    fi
    local n="${REPRO_CYCLES:-6}"
    local i
    for ((i = 1; i <= n; i++)); do
        log "DPMS cycle $i / $n — force off"
        xset dpms force off || true
        sleep 3
        log "DPMS — force on"
        xset dpms force on || true
        xset s reset 2>/dev/null || true
        sleep 3
        log "DPMS — suspend then on"
        xset dpms force suspend || true
        sleep 2
        xset dpms force on || true
        sleep 2
    done
    log "Phase A complete"
}

phase_b() {
    log "Phase B — video / scanout stress"
    require_x11 || return 0
    if [[ -n "${REPRO_VIDEO:-}" && -f "$REPRO_VIDEO" ]] && command -v mpv >/dev/null 2>&1; then
        log "Playing local file REPRO_VIDEO=$REPRO_VIDEO"
        timeout 12s mpv --vo=gpu --force-window=yes "$REPRO_VIDEO" >/dev/null 2>&1 || true
    elif command -v mpv >/dev/null 2>&1; then
        log "Running mpv (10 s, windowed, --vo=gpu). Set REPRO_VIDEO=/path/to.mp4 when offline."
        timeout 10s mpv --vo=gpu --force-window=yes --loop-file=inf \
            "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4" 2>/dev/null \
            || log "mpv exited (network or codec); use REPRO_VIDEO for a local clip"
    elif command -v ffplay >/dev/null 2>&1; then
        log "Running ffplay test pattern (8 s)"
        timeout 8s ffplay -f lavfi -i testsrc=duration=8:size=1280x720:rate=30 -window_title dmar_repro -autoexit \
            >/dev/null 2>&1 || true
    else
        log "Neither mpv nor ffplay found. Install one: dnf install mpv   OR   apt install mpv ffmpeg"
        log "Or play any H.264 clip locally: mpv --vo=gpu /path/to/file.mp4"
    fi
    log "Phase B complete"
}

phase_c() {
    log "Phase C — cursor churn"
    require_x11 || return 0
    if command -v xdotool >/dev/null 2>&1; then
        local j
        for ((j = 1; j <= 200; j++)); do
            xdotool mousemove $((j % 800)) $((j % 600)) 2>/dev/null || true
            sleep 0.02
        done
    else
        log "xdotool not installed — skipping auto cursor loop."
        log "Install: dnf install xdotool   OR   apt install xdotool"
    fi
    log "Phase C complete"
}

phase_d() {
    cat <<'EOF'
Phase D — Soak / drift (manual)

Allocator drift may need 2–6+ hours. Example:

  while true; do
    ./repro.sh phase-a
    sleep 300
    ./repro.sh phase-b
    sleep 300
  done

On host, periodically:
  dmesg -T | grep -E 'DMAR|dmar_fault' | tail -40

See PROTOCOL.md Phase D.
EOF
}

probe() {
    log "Probe"
    echo "DISPLAY=${DISPLAY:-}"
    uname -a
    echo "Session: ${XDG_SESSION_TYPE:-unknown}"
    for c in xset xrandr mpv ffplay xdotool modetest; do
        command -v "$c" >/dev/null 2>&1 && echo "OK: $c -> $(command -v "$c")" || echo "MISSING: $c"
    done
    if command -v modetest >/dev/null 2>&1; then
        log "Optional: intel-gpu-tools modetest — run: modetest -M i915 -c"
    fi
}

cmd="${1:-all}"
case "$cmd" in
    -h|--help|help) usage ;;
    probe) probe ;;
    phase-a) phase_a ;;
    phase-b) phase_b ;;
    phase-c) phase_c ;;
    phase-d) phase_d ;;
    all)
        probe
        phase_a
        phase_b
        phase_c
        log "Done 'all'. For long soak see: $0 phase-d"
        ;;
    *) usage; exit 1 ;;
esac
