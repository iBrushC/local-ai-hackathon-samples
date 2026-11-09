# Start a Bonsai 2 Small chat on Windows (GGUF + PrismML llama.cpp fork).
#   .\start.ps1                      # 4B on Vulkan (works on NVIDIA, AMD, Intel GPUs)
#   .\start.ps1 -Size 2B             # 2B | 4B | 9B
#   .\start.ps1 -Backend cuda-12.4   # vulkan | cpu | cuda-12.4 | cuda-13.3
# Then open http://localhost:8080
param(
    [ValidateSet("2B", "4B", "9B")] [string]$Size = "4B",
    [ValidateSet("vulkan", "cpu", "cuda-12.4", "cuda-13.3")] [string]$Backend = "vulkan",
    [int]$Port = 8080
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$bin = Join-Path $root "bin\$Backend"
$models = Join-Path $root "models"

# 1. Get the PrismML llama.cpp fork. Upstream llama.cpp can't run the PQ2_0 files.
$server = Join-Path $bin "llama-server.exe"
if (-not (Test-Path $server)) {
    $release = Invoke-RestMethod "https://api.github.com/repos/PrismML-Eng/llama.cpp/releases/latest"
    $want = @("llama-*-bin-win-$Backend-x64.zip")
    if ($Backend -like "cuda-*") { $want += "cudart-llama-bin-win-$Backend-x64.zip" }  # CUDA runtime DLLs
    New-Item -ItemType Directory -Force $bin | Out-Null
    foreach ($pattern in $want) {
        $asset = $release.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        Write-Host "Downloading $($asset.name) ($($release.tag_name))..."
        $zip = Join-Path $bin $asset.name
        curl.exe -L --fail -o $zip $asset.browser_download_url
        Expand-Archive -Force $zip $bin
        Remove-Item $zip
    }
}

# 2. Get the model (PQ2_0 = the model card's default pack).
$file = "Ternary-Bonsai-2-$Size-PQ2_0.gguf"
$model = Join-Path $models $file
if (-not (Test-Path $model)) {
    New-Item -ItemType Directory -Force $models | Out-Null
    Write-Host "Downloading $file..."
    curl.exe -L --fail -o "$model.part" "https://huggingface.co/prism-ml/Ternary-Bonsai-2-$Size-gguf/resolve/main/$file"
    Move-Item "$model.part" $model
}

# 3. Serve the model and the chat page together.
Write-Host "`nOpen http://localhost:$Port in your browser.`n"
& $server -m $model -ngl 99 -fa on -c 32768 --port $Port --path (Join-Path $root "..\shared")
