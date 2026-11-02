# Assembles the canonical Synesyn Windows release layout (ADR 0018).
#
#   <AppFolderName>/
#     Synesyn*.exe            (Godot export; .pck embedded via binary_format/embed_pck)
#     services/synesyn_hub/
#       synesyn_hub.exe       (flattened contents of PyInstaller dist/synesyn_hub/)
#       _internal/
#
# The hub must end up at services/synesyn_hub/synesyn_hub.exe because that is the
# only path HubLocator probes in a packaged build. PyInstaller's dist/synesyn_hub/
# wrapper directory is flattened away here rather than shipped.

param(
  [string]$ExportDir = "",
  [string]$HubDistDir = "",
  [string]$OutDir = "",
  [string]$AppFolderName = "Synesyn",
  [string]$ZipName = "Synesyn_Windows.zip",
  [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

# tools/ -> Godot project root (synesyn_client)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
# The services tree is a SIBLING of the Godot project, not inside it.
$repoRoot = (Resolve-Path (Join-Path $projectRoot "..")).Path

if ($HubDistDir -eq "") {
  $HubDistDir = Join-Path $repoRoot "services\synesyn_hub\dist\synesyn_hub"
}
if (-not (Test-Path $HubDistDir)) {
  throw ("Hub build output not found: {0}`nRun services\synesyn_hub\packaging\build_windows.ps1 first." -f $HubDistDir)
}
$HubDistDir = (Resolve-Path $HubDistDir).Path

$hubSourceExe = Join-Path $HubDistDir "synesyn_hub.exe"
if (-not (Test-Path $hubSourceExe)) {
  throw ("synesyn_hub.exe not found in hub build output: {0}" -f $HubDistDir)
}

if ($ExportDir -eq "") {
  throw "Pass -ExportDir pointing at your Godot Windows export output folder (containing Synesyn*.exe)."
}
$ExportDir = (Resolve-Path $ExportDir).Path

# The export preset ships a versioned name (e.g. Synesyn_v0.0.5.1.exe) with the
# pck embedded, so match on prefix and treat a separate .pck as optional.
$exportExes = @(Get-ChildItem -Path $ExportDir -Filter "Synesyn*.exe" -File)
if ($exportExes.Count -eq 0) {
  throw ("No Synesyn*.exe found in ExportDir: {0}" -f $ExportDir)
}
if ($exportExes.Count -gt 1) {
  $names = ($exportExes | ForEach-Object { $_.Name }) -join ", "
  throw ("Multiple Synesyn*.exe found in ExportDir ({0}): {1}. Keep one export per folder." -f $ExportDir, $names)
}
Write-Host ("Godot export: " + $exportExes[0].Name)

if ($OutDir -eq "") {
  $OutDir = Join-Path $repoRoot "Exports\Synesyn"
}
if (-not (Test-Path $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
$OutDir = (Resolve-Path $OutDir).Path

$staging = Join-Path $OutDir "staging"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
$appRoot = Join-Path $staging $AppFolderName
New-Item -ItemType Directory -Force -Path $appRoot | Out-Null

# Godot export payload (exe, optional pck, any DLLs Godot emits).
Copy-Item -Force -Path (Join-Path $ExportDir "*") -Destination $appRoot

# Hub: flatten dist/synesyn_hub/* into services/synesyn_hub/.
$hubTarget = Join-Path $appRoot "services\synesyn_hub"
New-Item -ItemType Directory -Force -Path $hubTarget | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $HubDistDir "*") -Destination $hubTarget

# Hub writes its own logs here; ship the folder so first run never fails on it.
New-Item -ItemType Directory -Force -Path (Join-Path $hubTarget "logs") | Out-Null

# Optional hub config: the loader falls back to defaults when absent, so only
# ship it if the maintainer placed one beside the spec.
$hubConfigSource = Join-Path $repoRoot "services\synesyn_hub\config.yaml"
if (Test-Path $hubConfigSource) {
  Copy-Item -Force -Path $hubConfigSource -Destination $hubTarget
  Write-Host "Included hub config.yaml"
}

# Fail fast if the layout does not match what the client probes.
$validator = Join-Path $projectRoot "tools\validate_windows_layout.ps1"
if (-not (Test-Path $validator)) {
  throw ("Validator not found: {0}" -f $validator)
}
& $validator -Root $appRoot

Write-Host ("Layout:   {0}" -f $appRoot)

if ($SkipZip) {
  Write-Host "Skipping archive (-SkipZip). Layout is staged and validated."
  return
}

# The hub bundle carries torch/whisper and runs to several GB. Compress-Archive is
# single-threaded and becomes impractical at that size, so prefer 7-Zip when the
# payload is large and fall back only for small ones.
$payloadBytes = (Get-ChildItem -Path $appRoot -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum
$payloadGB = $payloadBytes / 1GB
Write-Host ("Payload:  {0:N2} GB" -f $payloadGB)

$zipPath = Join-Path $OutDir $ZipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

$sevenZip = Get-Command "7z.exe" -ErrorAction SilentlyContinue
if ($sevenZip) {
  Write-Host "Archiving with 7-Zip..."
  & $sevenZip.Source a -tzip -mx=5 $zipPath $appRoot | Out-Null
  if ($LASTEXITCODE -ne 0) { throw ("7-Zip failed with exit code {0}" -f $LASTEXITCODE) }
} elseif ($payloadGB -gt 2) {
  Write-Host ""
  Write-Host ("Staged layout is valid but NOT archived: payload is {0:N2} GB and 7z.exe was not found." -f $payloadGB)
  Write-Host "Compress-Archive is impractical at this size. Install 7-Zip and re-run, or"
  Write-Host "distribute the staged folder directly:"
  Write-Host ("  {0}" -f $appRoot)
  return
} else {
  Write-Host "Archiving with Compress-Archive..."
  Compress-Archive -Path $appRoot -DestinationPath $zipPath -Force
}

Write-Host ("Packaged: {0}" -f $zipPath)
