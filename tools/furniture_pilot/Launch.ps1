param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$furnitureRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$furnitureOutput = Join-Path $furnitureRoot 'tmp/furniture_pilot_20261013'
New-Item -ItemType Directory -Force $furnitureOutput | Out-Null
$furnitureAppData = $env:APPDATA
$furnitureArgs = @('--path',('"'+$furnitureRoot+'"'),'res://scenes/studies/furniture_pilot.tscn','--resolution','1600x1000')
if ($Capture) { $furnitureArgs += @('--','--capture') }
$furnitureLabel = if ($Capture) { 'capture' } else { 'interactive' }
try {
    $env:APPDATA = Join-Path $furnitureOutput 'profile'
    $furnitureStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $furnitureProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $furnitureArgs -WindowStyle $furnitureStyle -RedirectStandardOutput (Join-Path $furnitureOutput ($furnitureLabel+'.out')) -RedirectStandardError (Join-Path $furnitureOutput ($furnitureLabel+'.err')) -PassThru
    $null = $furnitureProcess.Handle
} finally { $env:APPDATA = $furnitureAppData }
if (-not $Capture) { Write-Output "Furniture pilot started (PID $($furnitureProcess.Id))."; exit 0 }
if (-not $furnitureProcess.WaitForExit(90000)) { $furnitureProcess.Kill(); throw 'Furniture pilot capture timed out.' }
Get-Content (Join-Path $furnitureOutput 'capture.err')
Get-Content (Join-Path $furnitureOutput 'capture.out') -Tail 4
if ($furnitureProcess.ExitCode -ne 0) { exit $furnitureProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $furnitureOutput 'capture.err') -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $furnitureOutput 'capture.out') -Pattern '^FURNITURE_PILOT_CAPTURE_OK' -Quiet)) { exit 1 }
exit 0
