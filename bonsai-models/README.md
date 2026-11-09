# Bonsai 2 Small example: local chat window

A minimal chat window for [Bonsai 2 Small](https://huggingface.co/collections/prism-ml/bonsai-2-small) from PrismML. These are ternary-weight models (about 2 bits per weight), so a 4B model fits in about 1 GB. The whole app is one HTML page that talks to a local OpenAI-compatible server.

## Quick start (any OS)

```bash
python start.py               # 4B. Downloads everything on first run, then opens the chat window
python start.py --size 2B     # 2B | 4B | 9B
```

`start.py` needs only the Python standard library for GGUF. On Apple Silicon it uses MLX automatically if you've run `pip install -r mlx/requirements.txt`. To pick one yourself, add `--runtime gguf` or `--runtime mlx`. On Windows, `--gpu cuda-12.4` downloads the CUDA build instead of Vulkan. Run `python start.py --help` for all options.

The folders below also have plain `start.ps1` / `start.sh` scripts that do the same thing.

```
bonsai-models/
├── start.py            cross-platform launcher (GGUF or MLX)
├── shared/index.html   the chat window (plain HTML + JS, no build step)
├── gguf/               Windows / Linux / Intel or Apple Mac: PrismML llama.cpp fork + llama-server
└── mlx/                Apple Silicon only: mlx-vlm + mlx_vlm.server
```

## Which version should I use?

- **Windows or Linux:** [`gguf/`](gguf/README.md)
- **Apple Silicon Mac:** either works. [`mlx/`](mlx/README.md) is the native Apple path. `gguf/` also runs well on Metal.

Both versions do the same thing in three steps: download a runtime, download the model, and start a server on `localhost:8080`.

## Models

| Size | GGUF (PQ2_0) | MLX (2-bit) | Good for |
|---|---|---|---|
| `2B` | [Ternary-Bonsai-2-2B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf) | [Ternary-Bonsai-2-2B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-mlx-2bit) | Laptops, fastest replies |
| `4B` (default) | [Ternary-Bonsai-2-4B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-4B-gguf) | [Ternary-Bonsai-2-4B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-2-4B-mlx-2bit) | Best balance (~1.2 GB GGUF) |
| `9B` | [Ternary-Bonsai-2-9B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-9B-gguf) | [Ternary-Bonsai-2-9B-mlx-2bit](https://huggingface.co/prism-ml/Ternary-Bonsai-2-9B-mlx-2bit) | Best quality |

Choose the size when you start the server, for example `start.ps1 -Size 9B` or `./start.sh 9B`. The server loads one model at a time. The page shows which model is loaded.

## The chat window

- Replies stream in from `/v1/chat/completions`.
- **Thinking** checkbox: turns the model's reasoning on or off (`chat_template_kwargs.enable_thinking`). It also switches between the two sampling presets from the model card. Reasoning appears in a collapsible "Thinking…" block and is not sent back in the chat history.
  - Thinking on: `temperature 1.0, top_p 0.95, top_k 20, presence_penalty 1.0`, with up to 8192 tokens, since reasoning can take 3k+ tokens
  - Thinking off: `temperature 0.7, top_p 0.8, top_k 20, presence_penalty 1.5`
- The server URL box lets you point the page at a different port or machine.

Every sampling setting is sent on every request. Neither server reads `presence_penalty` or `min_p` from the model files, and the presets are tuned to stop ternary models from repeating themselves.

## Not covered here

These models can also read images (they need the `mmproj` file for GGUF, and work out of the box in mlx-vlm). They also support faster speculative decoding (MTP / DFlash2). See the model cards and [PrismML-Eng/Bonsai-demo](https://github.com/PrismML-Eng/Bonsai-demo) for both.
