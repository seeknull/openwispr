#!/usr/bin/env bash
# Bootstrap a fresh checkout of Whisp.
#
# 1. Ensures ../moonshine exists (Whisp depends on it via local Swift package).
# 2. Builds Moonshine.xcframework once (needed by SwiftPM to resolve the dep).
# 3. Resolves Whisp's Swift package dependencies.
#
# Usage:
#   ./scripts/bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$WHISP_DIR")"
MOONSHINE_DIR="$WORKSPACE_ROOT/moonshine"

if [ ! -d "$MOONSHINE_DIR" ]; then
    cat <<EOF >&2
error: Moonshine repo not found at $MOONSHINE_DIR

Whisp depends on the in-tree Moonshine Swift package as a sibling directory.
Clone it next to whisp/:

    cd "$WORKSPACE_ROOT"
    git clone https://github.com/moonshine-ai/moonshine.git
EOF
    exit 1
fi

if [ ! -d "$MOONSHINE_DIR/swift/Moonshine.xcframework" ]; then
    echo "==> Building Moonshine.xcframework (this takes a few minutes)..."
    bash "$MOONSHINE_DIR/scripts/build-swift.sh"
else
    echo "==> Moonshine.xcframework already present"
fi

echo "==> Resolving Whisp Swift package..."
cd "$WHISP_DIR"
swift package resolve

echo
echo "Done. Next steps:"
echo "  swift test         # run unit + integration tests"
echo "  swift run Whisp    # launch the menu-bar app"
echo "  ./scripts/build-release.sh   # produce a packaged Whisp.app"
