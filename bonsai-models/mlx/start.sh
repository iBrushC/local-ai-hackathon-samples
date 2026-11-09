#!/usr/bin/env bash
# Start a Bonsai 2 Small chat on Apple Silicon (MLX via mlx-vlm).
#   ./start.sh        # 4B
#   ./start.sh 2B     # 2B | 4B | 9B
# Then open ../shared/index.html in your browser.
set -euo pipefail

SIZE="${1:-4B}"
PORT="${PORT:-8080}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

case "$SIZE" in 2B|4B|9B) ;; *) echo "Size must be 2B, 4B or 9B"; exit 1 ;; esac
[ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || { echo "MLX needs an Apple Silicon Mac. Use ../gguf instead."; exit 1; }

# 1. Python environment.
if [ ! -d "$ROOT/.venv" ]; then
  python3 -m venv "$ROOT/.venv"
  "$ROOT/.venv/bin/pip" install -q -r "$ROOT/requirements.txt"
fi
source "$ROOT/.venv/bin/activate"

# 2. Get the model pack.
MODEL="$ROOT/models/bonsai2-$(echo "$SIZE" | tr 'B' 'b')-mlx"  # macOS bash 3.2 has no ${x,,}
if [ ! -f "$MODEL/model.safetensors" ]; then
  hf download "prism-ml/Ternary-Bonsai-2-$SIZE-mlx-2bit" --local-dir "$MODEL"
fi

# 3. Serve it. The chat page sends sampling + thinking settings on each request.
echo -e "\nOpen $(cd "$ROOT/../shared" && pwd)/index.html in your browser.\n"
( sleep 5; open "$ROOT/../shared/index.html" ) &
exec python -m mlx_vlm.server --model "$MODEL" --port "$PORT"
