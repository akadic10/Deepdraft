param(
    [int]$Population = 5,
    [string]$Label = 'long_session_5',
    [string]$SavePath = '',
    [double]$Seconds = 24,
    [switch]$Small,
    [switch]$NoMarkers,
    [switch]$NoAblations,
    [switch]$RoomRebuilds,
    [string]$Weather = '',
    [string]$Godot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
if ($Population -notin 5,20,30 -or -not $SavePath) { throw 'Requires 5/20/30 dwarves and a copied save' }
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid benchmark label' }
$benchmarkRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$benchmarkOutput = Join-Path $benchmarkRoot ('tmp/performance_20261014/' + $Label)
if (Test-Path -LiteralPath $benchmarkOutput) { throw 'Use a new label to preserve prior measurements' }
New-Item -ItemType Directory -Path $benchmarkOutput -Force | Out-Null
$benchmarkProfile = Join-Path $benchmarkOutput 'profile'
New-Item -ItemType Directory -Path $benchmarkProfile -Force | Out-Null
$benchmarkArguments = @('--path',('"'+$benchmarkRoot+'"'),'--disable-vsync','--audio-driver','Dummy','--script','res://tools/performance/AutosaveBenchmark.gd','--',('--output=res://tmp/performance_20261014/'+$Label),('--seconds='+$Seconds),('--population='+$Population))
$sourceHash = $null
if ($SavePath) {
    $SavePath = (Resolve-Path -LiteralPath $SavePath).Path
    $sourceHash = (Get-FileHash -LiteralPath $SavePath -Algorithm SHA256).Hash
    $copiedSave = Join-Path $benchmarkProfile 'Godot/app_userdata/Deepdraft/saves/quicksave.json'
    New-Item -ItemType Directory -Path (Split-Path $copiedSave) -Force | Out-Null
    Copy-Item -LiteralPath $SavePath -Destination $copiedSave
    $benchmarkArguments += '--saved'
}
if ($Small) { $benchmarkArguments += '--small' }
if ($NoMarkers) { $benchmarkArguments += '--no-markers' }
if ($NoAblations) { $benchmarkArguments += '--no-ablations' }
if ($RoomRebuilds) { $benchmarkArguments += '--room-rebuilds' }
if ($Weather) {
    if($Weather -notmatch '^base:weather:[a-z_]+$'){throw 'Invalid weather id'}
    $benchmarkArguments += ('--weather='+$Weather)
}
$benchmarkOldAppData = $env:APPDATA
$benchmarkOldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $benchmarkProfile
    $env:LOCALAPPDATA = $benchmarkProfile
    $benchmarkProcess = Start-Process -FilePath $Godot -ArgumentList $benchmarkArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $benchmarkOutput 'run.out') -RedirectStandardError (Join-Path $benchmarkOutput 'run.err')
    $null = $benchmarkProcess.Handle
} finally {
    $env:APPDATA = $benchmarkOldAppData
    $env:LOCALAPPDATA = $benchmarkOldLocalAppData
}
Write-Output "Benchmark PID $($benchmarkProcess.Id): $benchmarkOutput"
if (-not $benchmarkProcess.WaitForExit([int](($Seconds+180)*1000))) {
    Stop-Process -Id $benchmarkProcess.Id
    throw 'Benchmark exceeded configured duration plus startup allowance'
}
$sourceUnchanged = -not $SavePath -or (Get-FileHash -LiteralPath $SavePath -Algorithm SHA256).Hash -eq $sourceHash
@{save_sha256=$sourceHash;source_save_unchanged=$sourceUnchanged;exit_code=$benchmarkProcess.ExitCode;arguments=$benchmarkArguments} | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $benchmarkOutput 'run.json')
Get-Content (Join-Path $benchmarkOutput 'run.err') -TotalCount 25
Get-Content (Join-Path $benchmarkOutput 'run.out') -Tail 3
if (-not $sourceUnchanged) { throw 'Source save changed during benchmark' }
if ($benchmarkProcess.ExitCode -ne 0) { exit $benchmarkProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $benchmarkOutput 'run.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $benchmarkOutput 'run.out') -Pattern '^CAMERA_BENCHMARK_PASS' -Quiet)) { exit 1 }
