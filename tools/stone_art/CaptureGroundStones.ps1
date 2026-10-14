param([string]$Label = 'final', [switch]$Baseline, [switch]$GalleryOnly)
$ErrorActionPreference = 'Stop'
if ($Baseline) { throw 'Legacy model comparisons were retired; use the dated art reports for historical captures.' }
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid capture label' }
$stoneRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$stoneOutput = Join-Path $stoneRoot ('tmp/ground_stones_20261013/'+$Label)
New-Item -ItemType Directory -Force $stoneOutput | Out-Null
$stoneAppData = $env:APPDATA
$stoneArgs = @('--path',('"'+$stoneRoot+'"'),'--script','res://tools/stone_art/CaptureGroundStones.gd','--',('--output=res://tmp/ground_stones_20261013/'+$Label))
if ($GalleryOnly) { $stoneArgs += '--gallery-only' }
try {
    $env:APPDATA = Join-Path $stoneOutput 'profile'
    $stoneProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $stoneArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $stoneOutput 'run.out') -RedirectStandardError (Join-Path $stoneOutput 'run.err') -PassThru
    $null = $stoneProcess.Handle
} finally { $env:APPDATA = $stoneAppData }
$stoneProcess.WaitForExit()
Get-Content (Join-Path $stoneOutput 'run.err')
Get-Content (Join-Path $stoneOutput 'run.out') -Tail 5
if ($stoneProcess.ExitCode -ne 0) { exit $stoneProcess.ExitCode }
if (-not (Select-String -LiteralPath (Join-Path $stoneOutput 'run.out') -Pattern '^GROUND_STONES_CAPTURE_PASS' -Quiet)) { exit 1 }
exit 0
