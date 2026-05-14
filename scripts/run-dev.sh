#!/usr/bin/env bash
# Dev loop: kill any running Whisp, rebuild the .app, relaunch it.
#
# Usage:
#   ./scripts/run-dev.sh             # build + launch
#   ./scripts/run-dev.sh --logs      # build + launch + tail Console logs
#   ./scripts/run-dev.sh --no-build  # skip the build, just relaunch
#   ./scripts/run-dev.sh --reset     # also reset TCC grants (re-prompts permissions)
#
# Whisp's TCC permissions are keyed by bundle id (ai.whisp.app), so grants
# survive rebuilds. If macOS gets confused after several rebuilds and the
# hotkey or paste stops working, pass --reset and re-grant once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$WHISP_DIR"

DO_BUILD=1
DO_LOGS=0
DO_RESET=0
for arg in "$@"; do
    case "$arg" in
        --no-build) DO_BUILD=0 ;;
        --logs)     DO_LOGS=1 ;;
        --reset)    DO_RESET=1 ;;
        -h|--help)
            sed -n '2,/^set -euo/p' "$0" | sed -n '1,/^set -euo/{/^set -euo/!p;}'
            exit 0
            ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# 1. Kill any existing Whisp so the new build can claim the menu-bar slot.
if pgrep -x Whisp >/dev/null; then
    echo "==> Killing running Whisp instance"
    pkill -x Whisp || true
    # Give launchd a beat to clean up before relaunch.
    sleep 0.3
fi

# 2. Optionally clear TCC grants. Useful when permissions get into a
#    half-broken state across many rebuilds.
if [ "$DO_RESET" = 1 ]; then
    echo "==> Resetting TCC grants for ai.whisp.app"
    tccutil reset Microphone     ai.whisp.app 2>/dev/null || true
    tccutil reset Accessibility  ai.whisp.app 2>/dev/null || true
    tccutil reset ListenEvent    ai.whisp.app 2>/dev/null || true
fi

# 3. Build (unless --no-build).
APP="$WHISP_DIR/build/Whisp.app"
if [ "$DO_BUILD" = 1 ]; then
    echo "==> Building..."
    "$SCRIPT_DIR/build-release.sh"
fi

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Run without --no-build." >&2
    exit 1
fi

# 4. Launch via `open` so LaunchServices registers the bundle and TCC
#    keys grants to the bundle id, not the binary path.
echo "==> Launching $APP"
open "$APP"

# 5. Tail Whisp logs if requested.
if [ "$DO_LOGS" = 1 ]; then
    echo "==> Streaming logs (Ctrl+C to stop)"
    exec log stream --predicate 'subsystem == "ai.whisp.app"' --level=debug
fi
