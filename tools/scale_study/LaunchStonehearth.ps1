param([switch]$Capture, [string]$Source = 'P:/stonehearth')
$ErrorActionPreference = 'Stop'
$studyRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$studyOutput = Join-Path $studyRoot 'tmp/stonehearth_scale_20261013'
$studyPython = 'C:/Users/akadi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $studyPython (Join-Path $PSScriptRoot 'stonehearth_reference.py') --source $Source --output (Join-Path $studyOutput 'reference')
if ($LASTEXITCODE -ne 0) { throw 'Stonehearth reference export failed' }
$studyArgs = @('--path',('"'+$studyRoot+'"'),'res://scenes/studies/stonehearth_scale_study.tscn','--resolution','1600x1000','--audio-driver','Dummy')
if ($Capture) { $studyArgs += @('--','--capture') }
$studyLabel = if ($Capture) { 'capture' } else { 'interactive' }
$studyAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $studyOutput 'appdata'
    $studyStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $studyProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $studyArgs -WindowStyle $studyStyle -PassThru -RedirectStandardOutput (Join-Path $studyOutput ($studyLabel+'.out')) -RedirectStandardError (Join-Path $studyOutput ($studyLabel+'.err'))
    $null = $studyProcess.Handle
} finally { $env:APPDATA = $studyAppData }
if (-not $Capture) { Write-Output "Stonehearth comparison started (PID $($studyProcess.Id))."; exit 0 }
$studyTimer = [Diagnostics.Stopwatch]::StartNew()
while (-not $studyProcess.WaitForExit(1000)) {
    if ($studyTimer.Elapsed.TotalSeconds -gt 120) { $studyProcess.Kill(); throw 'Stonehearth scale capture timed out' }
}
Get-Content (Join-Path $studyOutput 'capture.err') -Tail 20
Get-Content (Join-Path $studyOutput 'capture.out') -Tail 4
if ($studyProcess.ExitCode -ne 0) { exit $studyProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $studyOutput 'capture.err') -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $studyOutput 'capture.out') -Pattern '^STONEHEARTH_SCALE_OK' -Quiet)) { exit 1 }
exit 0
