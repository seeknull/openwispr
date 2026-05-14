#!/usr/bin/env bash
# Download the default Moonshine STT model that Whisp ships with.
#
# Usage:
#   ./scripts/download-models.sh [model]
#
# `model` defaults to `medium-streaming-en`. Other options: `tiny-en`,
# `small-streaming-en`, `medium-streaming-en`. The model files are placed
# under Sources/Whisp/Resources/models/<model>/quantized so the release
# build script picks them up automatically.
set -euo pipefail

MODEL="${1:-medium-streaming-en}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="$WHISP_DIR/Sources/Whisp/Resources/models/$MODEL/quantized"
BASE_URL="https://download.moonshine.ai/model/$MODEL/quantized"

# Components per model. medium-streaming-en is the default; the others have
# the same component layout.
COMPONENTS=(
    "adapter.ort"
    "cross_kv.ort"
    "decoder_kv.ort"
    "encoder.ort"
    "frontend.ort"
    "streaming_config.json"
    "tokenizer.bin"
    "decoder_kv_with_attention.ort"
)

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

for f in "${COMPONENTS[@]}"; do
    if [ -f "$f" ]; then
        echo "==> $f already present, skipping"
        continue
    fi
    echo "==> Downloading $f"
    curl -L --fail -o "$f" "$BASE_URL/$f"
done

echo
echo "Downloaded $MODEL into $TARGET_DIR"
echo "Total size: $(du -sh "$TARGET_DIR" | awk '{print $1}')"
