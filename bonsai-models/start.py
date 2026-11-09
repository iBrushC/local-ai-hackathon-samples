"""Start a Bonsai 2 Small chat window. Works on Windows, macOS and Linux.

    python start.py                      # 4B. MLX on Apple Silicon if mlx-vlm is installed, otherwise GGUF
    python start.py --size 2B            # 2B | 4B | 9B
    python start.py --runtime gguf       # gguf | mlx
    python start.py --gpu cuda-12.4      # GGUF on Windows: vulkan (default) | cpu | cuda-12.4 | cuda-13.3
                                         # GGUF on Linux:   cpu (default) | vulkan

GGUF needs only the Python standard library. MLX needs: pip install -r mlx/requirements.txt
On first run this downloads the runtime and model, starts the server on localhost,
and opens the chat page (shared/index.html) when the model is ready.
"""

import argparse
import json
import platform
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import urllib.request
import webbrowser
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PAGE = ROOT / "shared" / "index.html"
FORK_RELEASE = "https://api.github.com/repos/PrismML-Eng/llama.cpp/releases/latest"
HEADERS = {"User-Agent": "bonsai-chat-sample"}


def download(url, dest):
    """Download url to dest with a simple progress readout. Writes to .part first."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS)) as res, open(part, "wb") as f:
        total = int(res.headers.get("Content-Length") or 0)
        done = 0
        while chunk := res.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r  {dest.name}: {done / total:6.1%} of {total / 1e9:.2f} GB", end="", flush=True)
    print()
    part.replace(dest)


def extract(archive, dest):
    """Unpack a .zip or .tar.gz into dest, dropping a single top-level folder if there is one."""
    tmp = dest / "_extract"
    shutil.rmtree(tmp, ignore_errors=True)
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as z:
            z.extractall(tmp)
    else:
        with tarfile.open(archive) as t:
            try:
                t.extractall(tmp, filter="data")  # Python 3.12+
            except TypeError:
                t.extractall(tmp)
    inner = list(tmp.iterdir())
    src = inner[0] if len(inner) == 1 and inner[0].is_dir() else tmp
    for item in src.iterdir():
        shutil.move(str(item), str(dest / item.name))
    shutil.rmtree(tmp)
    archive.unlink()


def fork_assets(gpu):
    """Which PrismML llama.cpp release files to fetch for this machine (name suffixes)."""
    system, machine = platform.system(), platform.machine().lower()
    arm = machine in ("arm64", "aarch64")
    if system == "Windows":
        if arm:
            return "win-cpu-arm64", ["-bin-win-cpu-arm64.zip"]
        gpu = gpu or "vulkan"
        assets = [f"-bin-win-{gpu}-x64.zip"]
        if gpu.startswith("cuda"):
            assets.append(f"cudart-llama-bin-win-{gpu}-x64.zip")  # CUDA runtime DLLs
        return f"win-{gpu}-x64", assets
    if system == "Darwin":
        name = "macos-arm64" if arm else "macos-x64"  # Metal is built in
        return name, [f"-bin-{name}.tar.gz"]
    if system == "Linux":
        name = "ubuntu-arm64" if arm else ("ubuntu-vulkan-x64" if gpu == "vulkan" else "ubuntu-x64")
        return name, [f"-bin-{name}.tar.gz"]
    sys.exit(f"Unsupported platform: {system} {machine}")


def setup_gguf(size, gpu):
    """Get the PrismML llama.cpp fork (upstream can't run PQ2_0) and the GGUF model."""
    name, wanted = fork_assets(gpu)
    bin_dir = ROOT / "gguf" / "bin" / name
    exe = bin_dir / ("llama-server.exe" if platform.system() == "Windows" else "llama-server")
    if not exe.exists():
        with urllib.request.urlopen(urllib.request.Request(FORK_RELEASE, headers=HEADERS)) as res:
            release = json.load(res)
        for suffix in wanted:
            # The CUDA runtime zip ends the same way as the llama zip, so match on the prefix too.
            prefix = "cudart-" if suffix.startswith("cudart-") else "llama-"
            asset = next(a for a in release["assets"] if a["name"].startswith(prefix) and a["name"].endswith(suffix))
            print(f"Downloading {asset['name']} ({release['tag_name']})")
            archive = bin_dir / asset["name"]
            download(asset["browser_download_url"], archive)
            extract(archive, bin_dir)

    file = f"Ternary-Bonsai-2-{size}-PQ2_0.gguf"
    model = ROOT / "gguf" / "models" / file
    if not model.exists():
        print(f"Downloading {file}")
        download(f"https://huggingface.co/prism-ml/Ternary-Bonsai-2-{size}-gguf/resolve/main/{file}", model)

    # llama-server also serves the chat page, so the browser opens http://localhost:<port>.
    cmd = [str(exe), "-m", str(model), "-ngl", "99", "-fa", "on", "-c", "32768", "--path", str(ROOT / "shared")]
    return cmd, None


def setup_mlx(size):
    """Get the MLX pack and serve it with mlx-vlm (the released mlx-lm can't load it yet)."""
    try:
        import mlx_vlm  # noqa: F401
        from huggingface_hub import snapshot_download
    except ImportError:
        sys.exit("MLX needs mlx-vlm: pip install -r mlx/requirements.txt")
    model = ROOT / "mlx" / "models" / f"bonsai2-{size.lower()}-mlx"
    if not (model / "model.safetensors").exists():
        print(f"Downloading prism-ml/Ternary-Bonsai-2-{size}-mlx-2bit")
        snapshot_download(f"prism-ml/Ternary-Bonsai-2-{size}-mlx-2bit", local_dir=model)
    # mlx_vlm.server allows CORS, so the page can be opened straight from disk.
    cmd = [sys.executable, "-m", "mlx_vlm.server", "--model", str(model)]
    return cmd, PAGE.as_uri()


def open_when_ready(port, page_url):
    """Open the chat page once the server answers /v1/models."""
    for _ in range(600):
        try:
            urllib.request.urlopen(f"http://localhost:{port}/v1/models", timeout=2)
            break
        except OSError:
            time.sleep(1)
    print(f"\nChat window: {page_url}  (Ctrl+C to stop)\n")
    webbrowser.open(page_url)


def main():
    p = argparse.ArgumentParser(description="Start a local Bonsai 2 Small chat.")
    p.add_argument("--size", default="4B", type=str.upper, choices=["2B", "4B", "9B"])
    p.add_argument("--runtime", choices=["gguf", "mlx"], help="default: mlx on Apple Silicon if installed, else gguf")
    p.add_argument("--gpu", choices=["vulkan", "cpu", "cuda-12.4", "cuda-13.3"], help="GGUF build to download")
    p.add_argument("--port", type=int, default=8080)
    args = p.parse_args()

    runtime = args.runtime
    if runtime is None:
        apple_silicon = platform.system() == "Darwin" and platform.machine() == "arm64"
        try:
            import mlx_vlm  # noqa: F401
            has_mlx = True
        except ImportError:
            has_mlx = False
        runtime = "mlx" if apple_silicon and has_mlx else "gguf"
    print(f"Bonsai 2 {args.size} via {runtime.upper()}")

    if runtime == "mlx":
        cmd, page_url = setup_mlx(args.size)
    else:
        cmd, page_url = setup_gguf(args.size, args.gpu)
    cmd += ["--port", str(args.port)]
    page_url = page_url or f"http://localhost:{args.port}"

    threading.Thread(target=open_when_ready, args=(args.port, page_url), daemon=True).start()
    server = subprocess.Popen(cmd)
    try:
        server.wait()
    except KeyboardInterrupt:
        server.terminate()
        server.wait()


if __name__ == "__main__":
    main()
