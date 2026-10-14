param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$scaleRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$scaleOutput = Join-Path $scaleRoot 'tmp/scale_study_20261013'
New-Item -ItemType Directory -Force $scaleOutput | Out-Null
$scaleArgs = @('--path',('"'+$scaleRoot+'"'),'res://scenes/studies/scale_study.tscn','--resolution','1600x1000','--audio-driver','Dummy')
if ($Capture) { $scaleArgs += @('--','--capture') }
$scaleLabel = if ($Capture) { 'capture' } else { 'interactive' }
$scaleAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $scaleOutput 'profile'
    $scaleStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $scaleProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $scaleArgs -WindowStyle $scaleStyle -PassThru -RedirectStandardOutput (Join-Path $scaleOutput ($scaleLabel+'.out')) -RedirectStandardError (Join-Path $scaleOutput ($scaleLabel+'.err'))
    $null = $scaleProcess.Handle
} finally { $env:APPDATA = $scaleAppData }
if (-not $Capture) { Write-Output "Scale study started (PID $($scaleProcess.Id))."; exit 0 }
$scaleTimer = [Diagnostics.Stopwatch]::StartNew()
while (-not $scaleProcess.WaitForExit(1000)) {
    if ($scaleTimer.Elapsed.TotalSeconds -gt 120) { $scaleProcess.Kill(); throw 'Scale capture timed out' }
}
Get-Content (Join-Path $scaleOutput 'capture.err') -Tail 20
Get-Content (Join-Path $scaleOutput 'capture.out') -Tail 5
if ($scaleProcess.ExitCode -ne 0) { exit $scaleProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $scaleOutput 'capture.err') -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $scaleOutput 'capture.out') -Pattern '^SCALE_STUDY_CAPTURE_OK' -Quiet)) { exit 1 }
exit 0
