param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$timberRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$timberOutput = Join-Path $timberRoot 'tmp/hand_hewn_study'
New-Item -ItemType Directory -Force $timberOutput | Out-Null
$timberArgs = @('--path',('"'+$timberRoot+'"'),'--windowed','--resolution','1600x1000','--audio-driver','Dummy','--script','res://tools/hand_hewn_study/Review.gd')
if ($Capture) { $timberArgs += @('--','--capture') }
$timberRoaming=$env:APPDATA
$timberLocal=$env:LOCALAPPDATA
try {
    $env:APPDATA=Join-Path $timberOutput 'profile/roaming'
    $env:LOCALAPPDATA=Join-Path $timberOutput 'profile/local'
    $timberStyle=if ($Capture) { 'Hidden' } else { 'Normal' }
    $timberProcess=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $timberArgs -WindowStyle $timberStyle -PassThru -RedirectStandardOutput (Join-Path $timberOutput 'viewer.out') -RedirectStandardError (Join-Path $timberOutput 'viewer.err')
    Write-Output "Timber preview started (PID $($timberProcess.Id))."
} finally { $env:APPDATA=$timberRoaming; $env:LOCALAPPDATA=$timberLocal }
