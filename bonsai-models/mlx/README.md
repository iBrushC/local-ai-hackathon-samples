# Bonsai 2 Small: MLX (Apple Silicon)

This version runs the 2-bit MLX pack with [mlx-vlm](https://github.com/Blaizzy/mlx-vlm)'s OpenAI-compatible server. You need an M-series Mac and Python 3.10+.

## Run

```bash
chmod +x start.sh
./start.sh        # 4B
./start.sh 2B     # 2B | 4B | 9B
```

On first run, the script:
1. Creates `.venv/` and installs `mlx-vlm>=0.7.8`.
2. Downloads `prism-ml/Ternary-Bonsai-2-<size>-mlx-2bit` into `models/`.
3. Starts `python -m mlx_vlm.server --model models/bonsai2-<size>-mlx --port 8080`.
4. Opens [`../shared/index.html`](../shared/index.html) in your browser.

The page is opened as a local file and calls `http://localhost:8080`, which works because the server allows CORS. If the header says "no server", the model is still loading. Send a message once it's ready, or reload the page.

## Gotchas

- **Use mlx-vlm, not mlx-lm.** The released `mlx-lm` (0.32.0) can't load these packs yet, so the `mlx_lm.server` snippets on Hugging Face fail.
- **Always send sampling settings.** mlx-vlm decodes greedily by default and doesn't read `presence_penalty` or `min_p` from the model. The page sends the model card's presets on every request.

## Use it from code

```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8080/v1", api_key="none")
# The model id is the absolute path start.sh passed to --model. Take it from the loaded entry.
model = next(m.id for m in client.models.list().data if getattr(m, "loaded", False))
r = client.chat.completions.create(
    model=model,
    messages=[{"role": "user", "content": "Explain ternary weights in two sentences."}],
    temperature=0.7, top_p=0.8,
    extra_body={"top_k": 20, "min_p": 0, "presence_penalty": 1.5,
                "chat_template_kwargs": {"enable_thinking": False}},
)
print(r.choices[0].message.content)
```
