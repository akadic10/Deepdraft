param([switch]$Capture, [switch]$Import, [string]$Godot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
$ErrorActionPreference = 'Stop'
$studyRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$studyOutput = Join-Path $studyRoot 'tmp/voxel_shadow_study'
New-Item -ItemType Directory -Force $studyOutput | Out-Null
$studyArgs = @('--path',('"'+$studyRoot+'"'),'--windowed','--resolution','1600x1000','--audio-driver','Dummy')
if ($Import) { $studyArgs += @('--headless','--editor','--import') }
else { $studyArgs += 'res://scenes/studies/micro_voxel_study.tscn' }
if ($Capture) { $studyArgs += @('--','--capture') }
$studyLabel = if ($Import) { 'import' } elseif ($Capture) { 'capture' } else { 'interactive' }
$studyAppData = $env:APPDATA
$studyLocalData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $studyOutput 'profile/roaming'
    $env:LOCALAPPDATA = Join-Path $studyOutput 'profile/local'
    $studyStyle = if ($Capture -or $Import) { 'Hidden' } else { 'Normal' }
    $studyProcess = Start-Process -FilePath $Godot -ArgumentList $studyArgs -WindowStyle $studyStyle -PassThru -RedirectStandardOutput (Join-Path $studyOutput ($studyLabel+'.out')) -RedirectStandardError (Join-Path $studyOutput ($studyLabel+'.err'))
    $null = $studyProcess.Handle
} finally { $env:APPDATA = $studyAppData; $env:LOCALAPPDATA = $studyLocalData }
if (-not ($Capture -or $Import)) { Write-Output "Micro-voxel study started (PID $($studyProcess.Id))."; exit 0 }
$studyTimer = [Diagnostics.Stopwatch]::StartNew()
while (-not $studyProcess.WaitForExit(1000)) {
    if ($studyTimer.Elapsed.TotalSeconds -gt 180) { $studyProcess.Kill(); throw 'Study timed out' }
}
Get-Content (Join-Path $studyOutput ($studyLabel+'.err')) -Tail 25
Get-Content (Join-Path $studyOutput ($studyLabel+'.out')) -Tail 8
if ($studyProcess.ExitCode -ne 0) { exit $studyProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $studyOutput ($studyLabel+'.err')) -Pattern '^ERROR:|SCRIPT ERROR:' -Quiet) { exit 1 }
if ($Capture -and -not (Select-String -LiteralPath (Join-Path $studyOutput 'capture.out') -Pattern '^MICRO_VOXEL_STUDY_CAPTURE_OK' -Quiet)) { exit 1 }
exit 0
