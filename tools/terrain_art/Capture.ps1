param([string]$Label = 'baseline', [switch]$Large, [switch]$Extended, [switch]$Profile)
$ErrorActionPreference = 'Stop'
$terrainRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$terrainSize = if ($Large) { '2560' } else { '1600' }
if ($Label -notmatch '^[a-z0-9_]+$') { throw 'Use a simple label.' }
$terrainRun = "$Label`_$terrainSize"
$terrainOutput = Join-Path $terrainRoot "tmp/terrain_art_20261013/$terrainRun"
New-Item -ItemType Directory -Force $terrainOutput | Out-Null
$terrainArgs = @('--path', ('"' + $terrainRoot + '"'), '--script', 'res://tools/terrain_art/CaptureTerrain.gd', '--', "--output=res://tmp/terrain_art_20261013/$terrainRun")
if ($Large) { $terrainArgs += '--large' }
if ($Extended) { $terrainArgs += '--extended' }
if ($Profile) { $terrainArgs += '--profile' }
$terrainPreviousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $terrainOutput 'profile'
    $terrainProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $terrainArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $terrainOutput 'run.out') -RedirectStandardError (Join-Path $terrainOutput 'run.err') -PassThru
    $null = $terrainProcess.Handle
} finally { $env:APPDATA = $terrainPreviousAppData }
Write-Output "Terrain capture process $($terrainProcess.Id): $terrainOutput"
$terrainProcess.WaitForExit()
Get-Content -LiteralPath (Join-Path $terrainOutput 'run.err')
Get-Content -LiteralPath (Join-Path $terrainOutput 'run.out') -Tail 3
if ($terrainProcess.ExitCode -ne 0) { exit $terrainProcess.ExitCode }
if (-not (Select-String -LiteralPath (Join-Path $terrainOutput 'run.out') -Pattern '^TERRAIN_CAPTURE_PASS' -Quiet)) { exit 1 }
