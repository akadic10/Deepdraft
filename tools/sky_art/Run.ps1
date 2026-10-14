param([string]$Label = 'current')
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid sky review label' }
$skyRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skyOutput = Join-Path $skyRoot ('tmp/sky_art_20261013/' + $Label)
New-Item -ItemType Directory -Force $skyOutput | Out-Null
$skyAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $skyOutput 'profile'
    $skyProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList @('--path', ('"' + $skyRoot + '"'), '--fixed-fps', '60', '--disable-vsync', '--audio-driver', 'Dummy', '--script', 'res://tools/sky_art/CaptureSky.gd', '--', ('--output=res://tmp/sky_art_20261013/' + $Label)) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $skyOutput 'run.out') -RedirectStandardError (Join-Path $skyOutput 'run.err') -PassThru
    $null = $skyProcess.Handle
} finally { $env:APPDATA = $skyAppData }
Write-Output "Sky review $($skyProcess.Id): $skyOutput"
if (-not $skyProcess.WaitForExit(360000)) { Stop-Process -Id $skyProcess.Id; throw 'Sky review timeout' }
Get-Content (Join-Path $skyOutput 'run.err') -Tail 12
Get-Content (Join-Path $skyOutput 'run.out') -Tail 2
if ($skyProcess.ExitCode -ne 0) { exit $skyProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $skyOutput 'run.err') -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $skyOutput 'run.out') -Pattern '^SKY_CAPTURE_PASS' -Quiet)) { exit 1 }
