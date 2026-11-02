# Single entry point for building the Synesyn Hub (ADR 0018).
#
# The build is one-dir on purpose: packaging flattens dist/synesyn_hub/ into
# services/synesyn_hub/, which is the only location the Godot client probes.
# Build configuration lives in the PyInstaller flags below — packaging/synesyn_hub.spec
# is regenerated output (--specpath), not a source file. Do not hand-edit it, and
# do not add a second spec: two specs previously disagreed on one-file vs one-dir
# and produced a layout the client could not find.

param(
  [switch]$StopRunningHub
)

$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location ..

# A running hub holds dist/synesyn_hub/synesyn_hub.exe open, and PyInstaller's
# final COLLECT step deletes that directory. The failure therefore lands minutes
# into the build, so check before spending the time.
$runningHubs = @(Get-Process -Name "synesyn_hub" -ErrorAction SilentlyContinue)
if ($runningHubs.Count -gt 0) {
  $pidList = ($runningHubs | ForEach-Object { $_.Id }) -join ", "
  if ($StopRunningHub) {
    Write-Host ("Stopping running hub process(es): " + $pidList)
    $runningHubs | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 2
  } else {
    throw ("synesyn_hub.exe is running (pid $pidList) and holds the output exe open. " +
      "Close Synesyn (a running client autostarts the hub and will respawn it), " +
      "or re-run this script with -StopRunningHub.")
  }
}

Write-Host "Building Synesyn Hub (PyInstaller)..."
Write-Host ("CWD: " + (Get-Location).Path)
Write-Host "Pre-clean: removing stale non-canonical root artifacts (if present)..."

$staleRootExe = Join-Path (Get-Location).Path "synesyn_hub.exe"
$staleRootInternal = Join-Path (Get-Location).Path "_internal"
if (Test-Path $staleRootExe) {
  Write-Host ("Removing stale root exe: " + $staleRootExe)
  Remove-Item -Force $staleRootExe
}
if (Test-Path $staleRootInternal) {
  Write-Host ("Removing stale root _internal folder: " + $staleRootInternal)
  Remove-Item -Recurse -Force $staleRootInternal
}

Write-Host "Preflight: checking conda + env + pyinstaller..."
conda --version
conda run -n synesyn-hub python -c "import sys; print('python:', sys.version); print('exe:', sys.executable)"
conda run -n synesyn-hub python -c "import PyInstaller; print('PyInstaller:', PyInstaller.__version__)"

# Refuse to ship a CUDA torch. environment.yml asks for pytorch-cpu because the
# hub only ever runs Whisper on CPU (app/voice/stt.py pins device="cpu"), but a
# solver that resolves a cuda* build instead adds ~3.9 GB of GPU libraries that
# are never loaded. That bulk is what makes the hub slow to start and heavy on
# low-spec machines, so fail the build rather than package it.
$torchCuda = (conda run -n synesyn-hub python -c "import torch; print(torch.version.cuda)").Trim()
Write-Host ("torch CUDA build: " + $torchCuda)
if ($torchCuda -ne "None") {
  throw ("This env has a CUDA torch build (cuda=$torchCuda). Expected a CPU build. " +
    "Fix with: conda install -n synesyn-hub -c conda-forge pytorch-cpu numpy=2.1.3")
}

# Microsoft rejects edge-tts < 7.3.1 with HTTP 403 on wss://speech.platform.bing.com,
# which forces every character onto the Windows SAPI default voice. Refuse to
# package an environment whose edge-tts is older than requirements.txt.
$edgeTtsVer = ((conda run -n synesyn-hub python -c "import edge_tts; print(edge_tts.__version__)") -join "").Trim()
Write-Host ("edge-tts version: " + $edgeTtsVer)
if ([version]$edgeTtsVer -lt [version]"7.3.1") {
  throw ("This env has edge-tts $edgeTtsVer (< 7.3.1), which fails with HTTP 403 and falls back to SAPI. " +
    "Fix with: conda run -n synesyn-hub python -m pip install 'edge-tts>=7.3.1'")
}

# Whisper downloads its weights (~139 MB) on first use. In a --noconsole build
# that happens inside a request the client is already awaiting, with no console
# and no progress indicator, so a first-run user sees a hang instead of a
# transcript. Stage the weights and bundle them; app/voice/stt.py prefers them.
$modelName = "base"
$modelsDir = Join-Path (Get-Location).Path "models"
$modelPath = Join-Path $modelsDir "$modelName.pt"
if (-not (Test-Path $modelPath)) {
  New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null
  $cached = Join-Path $env:USERPROFILE ".cache\whisper\$modelName.pt"
  if (Test-Path $cached) {
    Write-Host ("Staging Whisper weights from local cache: " + $cached)
    Copy-Item -Force -Path $cached -Destination $modelPath
  } else {
    Write-Host "Downloading Whisper weights ($modelName) once, for bundling..."
    conda run -n synesyn-hub python -c "import whisper; whisper.load_model('$modelName', device='cpu', download_root=r'$modelsDir')"
  }
}
if (-not (Test-Path $modelPath)) {
  throw ("Whisper weights could not be staged: {0}" -f $modelPath)
}
Write-Host ("Whisper weights: {0} ({1:N1} MB)" -f $modelPath, ((Get-Item $modelPath).Length / 1MB))

Write-Host "Preflight OK. Starting PyInstaller build (this can take several minutes on first build)..."
$buildStartedAt = Get-Date

conda run -n synesyn-hub pyinstaller `
  --noconsole `
  --noconfirm `
  --clean `
  --log-level=INFO `
  --paths "." `
  --add-data "../app/app_adapters/verse_corpus.json;app/app_adapters" `
  --add-data "$modelPath;models" `
  --collect-data "whisper" `
  --name "synesyn_hub" `
  --distpath "dist" `
  --workpath "build" `
  --specpath "packaging" `
  app/main.py

# PowerShell's ErrorActionPreference does not trip on a native command's exit
# code, and the checks below only test that the output exists. A failed build
# leaves the previous exe in place, so without this the script reported success
# and the caller shipped a stale binary.
if ($LASTEXITCODE -ne 0) {
  throw ("PyInstaller failed with exit code {0}. The output below dist\ is from the previous build." -f $LASTEXITCODE)
}

$expectedExe = Join-Path (Get-Location).Path "dist\synesyn_hub\synesyn_hub.exe"
$expectedInternal = Join-Path (Get-Location).Path "dist\synesyn_hub\_internal"
if (-not (Test-Path $expectedExe)) {
  throw ("Build reported success but the one-dir output is missing: {0}" -f $expectedExe)
}
if (-not (Test-Path $expectedInternal)) {
  throw ("Build produced a one-file exe (no _internal/). Expected a one-dir bundle at: {0}" -f $expectedInternal)
}
# Existence alone does not prove this build produced it: a failed run leaves the
# previous output untouched. Require an exe newer than the moment we started.
$exeWrittenAt = (Get-Item $expectedExe).LastWriteTime
if ($exeWrittenAt -lt $buildStartedAt) {
  throw ("Output exe is older than this build ({0} < {1}); it is left over from a previous run." -f $exeWrittenAt, $buildStartedAt)
}

$bundleGB = (Get-ChildItem (Join-Path (Get-Location).Path "dist\synesyn_hub") -Recurse -File -Force |
  Measure-Object -Property Length -Sum).Sum / 1GB
Write-Host ("Bundle size: {0:N2} GB" -f $bundleGB)
Write-Host ("Done. Output: {0}" -f $expectedExe)
Write-Host "Next: package with synesyn_client\tools\package_windows.ps1 -ExportDir <godot export folder>"


