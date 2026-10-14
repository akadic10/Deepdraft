param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$animalRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$animalOutput = Join-Path $animalRoot 'tmp/animal_pilot_20261013'
New-Item -ItemType Directory -Force $animalOutput | Out-Null
$animalAppData = $env:APPDATA
$animalArgs = @('--path',('"'+$animalRoot+'"'),'res://scenes/studies/animal_pilot.tscn','--resolution','1600x1000')
if ($Capture) { $animalArgs += @('--','--capture') }
$animalLabel = if ($Capture) { 'capture' } else { 'interactive' }
try {
    $env:APPDATA = Join-Path $animalOutput 'profile'
    $animalStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $animalProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $animalArgs -WindowStyle $animalStyle -RedirectStandardOutput (Join-Path $animalOutput ($animalLabel+'.out')) -RedirectStandardError (Join-Path $animalOutput ($animalLabel+'.err')) -PassThru
    $null = $animalProcess.Handle
} finally { $env:APPDATA = $animalAppData }
if (-not $Capture) { Write-Output "Animal pilot started (PID $($animalProcess.Id))."; exit 0 }
if (-not $animalProcess.WaitForExit(90000)) { $animalProcess.Kill(); throw 'Animal pilot capture timed out.' }
Get-Content (Join-Path $animalOutput 'capture.err')
Get-Content (Join-Path $animalOutput 'capture.out') -Tail 4
if ($animalProcess.ExitCode -ne 0) { exit $animalProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $animalOutput 'capture.err') -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $animalOutput 'capture.out') -Pattern '^ANIMAL_PILOT_CAPTURE_OK' -Quiet)) { exit 1 }
exit 0
