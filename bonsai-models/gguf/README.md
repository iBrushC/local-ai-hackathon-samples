# Bonsai 2 Small: GGUF (Windows / Linux / Mac)

This version runs the `PQ2_0` GGUF pack on [PrismML's llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp). `llama-server` also serves the chat page, so there's nothing else to install.

## Run

**Windows (PowerShell):**
```powershell
.\start.ps1                       # 4B on Vulkan
.\start.ps1 -Size 2B              # 2B | 4B | 9B
.\start.ps1 -Backend cuda-12.4    # vulkan | cpu | cuda-12.4 | cuda-13.3
```
If scripts are blocked, run `powershell -ExecutionPolicy Bypass -File .\start.ps1`.

**macOS / Linux:**
```bash
chmod +x start.sh
./start.sh                  # 4B (Metal on Mac, CPU on Linux)
./start.sh 9B
BACKEND=vulkan ./start.sh   # Linux GPU
```

Then open **http://localhost:8080**.

On first run, the script downloads two things:
1. The latest fork release for your platform into `bin/`. Vulkan is about 28 MB. CUDA is about 550 MB because it includes the CUDA runtime.
2. `Ternary-Bonsai-2-<size>-PQ2_0.gguf` into `models/`. That's about 1.2 GB for 4B.

It then starts:
```
llama-server -m models/<file>.gguf -ngl 99 -fa on -c 32768 --port 8080 --path ../shared
```

## Why the fork?

The model card says the `PQ2_0` and `PTQ1_0` packs run only on the PrismML fork. Upstream llama.cpp rejects them as unknown types. If you'd rather use upstream llama.cpp (release b11556 or newer), download the `Q2_0` file instead and use the same command. Older builds load it but give wrong output with no warning.

## Use it from code

`llama-server` is OpenAI-compatible, so any OpenAI SDK works with `base_url="http://localhost:8080/v1"`. Send the sampling settings and `chat_template_kwargs` on each request, like [`../shared/index.html`](../shared/index.html) does.
