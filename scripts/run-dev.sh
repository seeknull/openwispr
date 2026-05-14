#!/usr/bin/env bash
# One-stop dev script. Figures out which steps are needed and runs them.
#
# Usage:
#   ./scripts/run-dev.sh             # auto: bootstrap if needed, model if missing, build, launch
#   ./scripts/run-dev.sh --logs      # also tail Console logs after launching
#   ./scripts/run-dev.sh --no-build  # skip the build step, just relaunch the existing .app
#   ./scripts/run-dev.sh --no-models # don't prompt to download models (uses fallback tiny-en)
#   ./scripts/run-dev.sh --reset     # tccutil reset, then build + launch (re-prompts permissions)
#   ./scripts/run-dev.sh --clean     # nuke .build/ and build/, then rebuild from scratch
#
# What it autodetects:
#   - Moonshine.xcframework missing  → runs scripts/bootstrap.sh
#   - Model directory missing        → offers to run scripts/download-models.sh
#   - Whisp already running          → kills it before relaunch
#   - First run after a fresh build  → nudges you to verify Accessibility / Input Monitoring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$WHISP_DIR")"
MOONSHINE_DIR="$WORKSPACE_ROOT/moonshine"
cd "$WHISP_DIR"

DO_BUILD=1
DO_LOGS=0
DO_RESET=0
DO_CLEAN=0
DO_MODELS=1
for arg in "$@"; do
    case "$arg" in
        --no-build)  DO_BUILD=0 ;;
        --logs)      DO_LOGS=1 ;;
        --reset)     DO_RESET=1 ;;
        --clean)     DO_CLEAN=1 ;;
        --no-models) DO_MODELS=0 ;;
        -h|--help)
            awk '/^# Usage:/,/^set -euo/' "$0" | sed '/^set -euo/d; s/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# ---- 1. Bootstrap: ensure Moonshine.xcframework exists ----
XCFRAMEWORK="$MOONSHINE_DIR/swift/Moonshine.xcframework"
if [ ! -d "$XCFRAMEWORK" ]; then
    echo "==> Moonshine.xcframework missing — running bootstrap.sh"
    "$SCRIPT_DIR/bootstrap.sh"
fi

# ---- 2. Models: detect missing default model ----
MODEL_DIR="$WHISP_DIR/Sources/Whisp/Resources/models/medium-streaming-en/quantized"
if [ "$DO_MODELS" = 1 ] && [ ! -d "$MODEL_DIR" ]; then
    echo
    echo "==> No bundled STT model found at:"
    echo "    Sources/Whisp/Resources/models/medium-streaming-en/quantized"
    echo
    echo "    Whisp will fall back to MoonshineVoice's bundled tiny-en model,"
    echo "    which works but is lower accuracy than medium-streaming-en (~280 MB)."
    echo
    read -p "    Download medium-streaming-en now? [y/N] " yn
    case "$yn" in
        [Yy]*) "$SCRIPT_DIR/download-models.sh" ;;
        *)     echo "    Skipped. Pass --no-models to silence this prompt." ;;
    esac
    echo
fi

# ---- 3. Clean build artifacts if requested ----
if [ "$DO_CLEAN" = 1 ]; then
    echo "==> Cleaning .build/ and build/"
    rm -rf .build build
fi

# ---- 4. Kill any running Whisp so the new build can claim the menu-bar slot ----
if pgrep -x Whisp >/dev/null; then
    echo "==> Killing running Whisp instance"
    pkill -x Whisp || true
    sleep 0.3
fi

# ---- 5. Reset TCC grants if requested ----
if [ "$DO_RESET" = 1 ]; then
    echo "==> Resetting TCC grants for ai.whisp.app"
    tccutil reset Microphone     ai.whisp.app 2>/dev/null || true
    tccutil reset Accessibility  ai.whisp.app 2>/dev/null || true
    tccutil reset ListenEvent    ai.whisp.app 2>/dev/null || true
fi

# ---- 6. Build ----
APP="$WHISP_DIR/build/Whisp.app"
# Track whether the build produced a new signature so we can nudge about TCC.
PREV_HASH=""
if [ -d "$APP" ]; then
    PREV_HASH="$(codesign -dvvv "$APP" 2>&1 | awk -F'=' '/^CDHash=/{print $2; exit}')"
fi

if [ "$DO_BUILD" = 1 ]; then
    echo "==> Building..."
    "$SCRIPT_DIR/build-release.sh"
fi

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Run without --no-build first." >&2
    exit 1
fi

# ---- 7. Launch via `open` so LaunchServices registers the bundle ----
echo "==> Launching $APP"
open "$APP"

NEW_HASH="$(codesign -dvvv "$APP" 2>&1 | awk -F'=' '/^CDHash=/{print $2; exit}')"

# ---- 8. Re-grant nudge ----
# We don't have an API to query TCC for "was this signature trusted?", so
# heuristic: if the CDHash changed AND this isn't the first launch, the
# permissions you previously granted are likely stale.
if [ -n "$PREV_HASH" ] && [ "$PREV_HASH" != "$NEW_HASH" ]; then
    cat <<EOF

==> Note: Whisp's code signature changed from the previous build:
       was: $PREV_HASH
       now: $NEW_HASH

    macOS may treat this as a "new app" and ignore your previous Accessibility
    / Input Monitoring grants. If the hotkey or paste stops working:
      • Open System Settings → Privacy & Security → Accessibility
        → toggle Whisp off and back on (do the same for Input Monitoring).
      • Or run: ./scripts/run-dev.sh --reset   to start fresh.

EOF
fi

# ---- 9. Tail Whisp logs if requested ----
if [ "$DO_LOGS" = 1 ]; then
    echo "==> Streaming Whisp logs (Ctrl+C to stop)"
    exec log stream --predicate 'subsystem == "ai.whisp.app"' --level=debug
fi
