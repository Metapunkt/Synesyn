# Verifies a staged or unzipped folder matches the canonical Synesyn release
# layout (ADR 0018):
#
#   <Root>/Synesyn*.exe
#   <Root>/services/synesyn_hub/synesyn_hub.exe
#   <Root>/services/synesyn_hub/_internal/
#
# This is the only layout HubLocator probes in a packaged build, so a pass here
# means autostart will find the hub.

param(
  [Parameter(Mandatory = $true)]
  [string]$Root
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path $Root).Path
$errors = New-Object System.Collections.Generic.List[string]

# Godot client. The export preset embeds the pck, so a sibling .pck is optional
# but must be reported when present so a mismatched pair is visible.
$clientExes = @(Get-ChildItem -Path $Root -Filter "Synesyn*.exe" -File -ErrorAction SilentlyContinue)
if ($clientExes.Count -eq 0) {
  $errors.Add(("No Synesyn*.exe at root: {0}" -f $Root))
} elseif ($clientExes.Count -gt 1) {
  $names = ($clientExes | ForEach-Object { $_.Name }) -join ", "
  $errors.Add(("Multiple Synesyn*.exe at root: {0}" -f $names))
}

# Hub at the one canonical path.
$hubDir = Join-Path $Root "services\synesyn_hub"
$hubExe = Join-Path $hubDir "synesyn_hub.exe"
$hubInternal = Join-Path $hubDir "_internal"

if (-not (Test-Path $hubExe)) {
  $errors.Add(("Missing hub executable: {0}" -f $hubExe))
}
if (-not (Test-Path $hubInternal)) {
  $errors.Add(("Missing hub _internal folder (one-dir bundle is incomplete): {0}" -f $hubInternal))
}

# A shipped dist/ or build/ means the PyInstaller wrapper was copied instead of
# flattened, which puts the exe one level deeper than the client looks.
foreach ($stray in @("dist", "build", ".venv", "tests", "__pycache__", ".pytest_cache")) {
  $strayPath = Join-Path $hubDir $stray
  if (Test-Path $strayPath) {
    $errors.Add(("Development folder must not ship inside the hub: {0}" -f $strayPath))
  }
}

if ($errors.Count -gt 0) {
  $joined = ($errors | ForEach-Object { "  - " + $_ }) -join "`n"
  throw ("Layout validation failed:`n{0}" -f $joined)
}

Write-Host ("OK: client    {0}" -f $clientExes[0].Name)
Write-Host ("OK: hub       {0}" -f $hubExe)
if (Test-Path (Join-Path $Root "Synesyn*.pck")) {
  Write-Host "Note: a separate .pck is present (export did not embed it)."
}
Write-Host "OK: layout matches HubLocator's packaged search path."
