#!/usr/bin/env bash
# Live-tail DMAR / vfio messages on the hypervisor.
#
# Do NOT rely on grep -c against the entire dmesg buffer for intermittent bursts —
# rate limiting ("callbacks suppressed") makes counts misleading. Prefer timestamped
# excerpts saved during repro phases (journalctl/dmesg slice), plus this watcher.

set -euo pipefail

TEE_FILE=""
USE_JOURNAL=true

usage() {
    cat <<'EOF'
Usage: watch_dmar.sh [--tee FILE] [--dmesg-only]

  --tee FILE      Append matched lines to FILE as well as stdout.
  --dmesg-only    Use `dmesg -w` instead of journalctl (works without systemd).

Environment:
  FILTER_REGEX    Extended regex for grep -E (default: DMAR|dmar_fault|vfio.*02\\.0)

Examples:
  ./watch_dmar.sh --tee artifacts/live-host.log
  FILTER_REGEX='DMAR|dmar_fault' ./watch_dmar.sh --dmesg-only
EOF
}

FILTER_REGEX="${FILTER_REGEX:-DMAR|dmar_fault|vfio.*00:02\\.0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tee)
            TEE_FILE="${2:?}"
            shift 2
            ;;
        --dmesg-only)
            USE_JOURNAL=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

mktee() {
    if [[ -n "$TEE_FILE" ]]; then
        mkdir -p "$(dirname "$TEE_FILE")"
        tee -a "$TEE_FILE"
    else
        cat
    fi
}

echo "$(date -Is 2>/dev/null || date)  watch_dmar.sh starting (FILTER_REGEX=$FILTER_REGEX)" | mktee

follow_journal() {
    journalctl -kf -o short-precise 2>/dev/null || journalctl -kf
}

if $USE_JOURNAL && command -v journalctl >/dev/null 2>&1; then
    follow_journal | grep -E --line-buffered "$FILTER_REGEX" | mktee
elif command -v dmesg >/dev/null 2>&1 && dmesg --help 2>&1 | grep -q '\-w'; then
    dmesg -w 2>/dev/null | grep -E --line-buffered "$FILTER_REGEX" | mktee
else
    echo "Neither usable journalctl nor dmesg -w found. Poll manually:" >&2
    echo "  watch -n 2 \"dmesg -T | grep -Ei '$FILTER_REGEX' | tail -40\"" >&2
    exit 1
fi
