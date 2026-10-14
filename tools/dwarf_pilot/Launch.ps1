param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$pilotRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$pilotOutput = Join-Path $pilotRoot 'tmp/dwarf_pilot_20261013'
New-Item -ItemType Directory -Force $pilotOutput | Out-Null
$pilotAppData = $env:APPDATA
$pilotArgs = @('--path',('"'+$pilotRoot+'"'),'res://scenes/studies/dwarf_pilot.tscn','--resolution','1600x1000')
if ($Capture) { $pilotArgs += @('--','--capture') }
$pilotLabel = if ($Capture) { 'capture' } else { 'interactive' }
try {
    $env:APPDATA = Join-Path $pilotOutput 'profile'
    $pilotStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $pilotProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $pilotArgs -WindowStyle $pilotStyle -RedirectStandardOutput (Join-Path $pilotOutput ($pilotLabel+'.out')) -RedirectStandardError (Join-Path $pilotOutput ($pilotLabel+'.err')) -PassThru
    $null = $pilotProcess.Handle
} finally { $env:APPDATA = $pilotAppData }
if (-not $Capture) { Write-Output "Dwarf pilot started (PID $($pilotProcess.Id))."; exit 0 }
if (-not $pilotProcess.WaitForExit(90000)) { $pilotProcess.Kill(); throw 'Dwarf pilot capture timed out.' }
Get-Content (Join-Path $pilotOutput 'capture.err')
Get-Content (Join-Path $pilotOutput 'capture.out') -Tail 4
if ($pilotProcess.ExitCode -ne 0) { exit $pilotProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $pilotOutput 'capture.err') -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $pilotOutput 'capture.out') -Pattern '^DWARF_PILOT_CAPTURE_OK' -Quiet)) { exit 1 }
exit 0
