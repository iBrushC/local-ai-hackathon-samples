#!/usr/bin/env bash
# Start a Bonsai 2 Small chat on macOS or Linux (GGUF + PrismML llama.cpp fork).
#   ./start.sh            # 4B
#   ./start.sh 2B         # 2B | 4B | 9B
#   BACKEND=vulkan ./start.sh   # Linux only: cpu (default) | vulkan
# Then open http://localhost:8080
set -euo pipefail

SIZE="${1:-4B}"
PORT="${PORT:-8080}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

case "$SIZE" in 2B|4B|9B) ;; *) echo "Size must be 2B, 4B or 9B"; exit 1 ;; esac

# Pick the right prebuilt binary from the fork's releases.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  PLATFORM="macos-arm64" ;;
  Darwin-x86_64) PLATFORM="macos-x64" ;;
  Linux-x86_64)  [ "${BACKEND:-cpu}" = vulkan ] && PLATFORM="ubuntu-vulkan-x64" || PLATFORM="ubuntu-x64" ;;
  Linux-aarch64) PLATFORM="ubuntu-arm64" ;;
  *) echo "Unsupported platform: $(uname -s)-$(uname -m)"; exit 1 ;;
esac
BIN="$ROOT/bin/$PLATFORM"

# 1. Get the PrismML llama.cpp fork. Upstream llama.cpp can't run the PQ2_0 files.
if [ ! -x "$BIN/llama-server" ]; then
  URL=$(curl -s https://api.github.com/repos/PrismML-Eng/llama.cpp/releases/latest \
    | grep -o "\"browser_download_url\": *\"[^\"]*-bin-$PLATFORM\.tar\.gz\"" \
    | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
  echo "Downloading $URL"
  mkdir -p "$BIN"
  curl -L --fail "$URL" | tar xz -C "$BIN" --strip-components=1
fi

# 2. Get the model (PQ2_0 = the model card's default pack).
FILE="Ternary-Bonsai-2-$SIZE-PQ2_0.gguf"
MODEL="$ROOT/models/$FILE"
if [ ! -f "$MODEL" ]; then
  mkdir -p "$ROOT/models"
  echo "Downloading $FILE"
  curl -L --fail -o "$MODEL.part" "https://huggingface.co/prism-ml/Ternary-Bonsai-2-$SIZE-gguf/resolve/main/$FILE"
  mv "$MODEL.part" "$MODEL"
fi

# 3. Serve the model and the chat page together.
echo -e "\nOpen http://localhost:$PORT in your browser.\n"
exec "$BIN/llama-server" -m "$MODEL" -ngl 99 -fa on -c 32768 --port "$PORT" --path "$ROOT/../shared"
