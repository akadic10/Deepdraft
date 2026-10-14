param([string]$Label = 'current_1', [switch]$Pilot, [switch]$Quick, [switch]$Small, [string]$RestoreFrom = '')
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid benchmark label' }
$benchmarkRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$benchmarkOutput = Join-Path $benchmarkRoot ('tmp/settlement_art_20261013/'+$Label)
New-Item -ItemType Directory -Force $benchmarkOutput | Out-Null
$benchmarkAppData = $env:APPDATA
$benchmarkArgs = @('--path',('"'+$benchmarkRoot+'"'),'--fixed-fps','60','--disable-vsync','--audio-driver','Dummy','--script','res://tools/settlement_art/BenchmarkSettlement.gd','--',('--output=res://tmp/settlement_art_20261013/'+$Label))
if ($Pilot) { $benchmarkArgs += '--pilot' }
if ($Quick) { $benchmarkArgs += '--quick' }
if ($Small) { $benchmarkArgs += '--small' }
if ($RestoreFrom) {
    if ($RestoreFrom -notmatch '^[a-zA-Z0-9_-]+$' -or $RestoreFrom -eq $Label) { throw 'Use a distinct source benchmark label' }
    $benchmarkSaveSuffix = 'profile/Godot/app_userdata/Deepdraft/settlement_benchmark/quicksave.json'
    $benchmarkSourceSave = Join-Path $benchmarkRoot ('tmp/settlement_art_20261013/'+$RestoreFrom+'/'+$benchmarkSaveSuffix)
    $benchmarkTargetSave = Join-Path $benchmarkOutput $benchmarkSaveSuffix
    New-Item -ItemType Directory -Force (Split-Path $benchmarkTargetSave) | Out-Null
    Copy-Item -LiteralPath $benchmarkSourceSave -Destination $benchmarkTargetSave
    $benchmarkArgs += '--restore-only'
}
try {
    $env:APPDATA = Join-Path $benchmarkOutput 'profile'
    $benchmarkProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $benchmarkArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $benchmarkOutput 'run.out') -RedirectStandardError (Join-Path $benchmarkOutput 'run.err') -PassThru
    $null = $benchmarkProcess.Handle
} finally { $env:APPDATA = $benchmarkAppData }
Write-Output "Settlement benchmark $($benchmarkProcess.Id): $benchmarkOutput"
if (-not $benchmarkProcess.WaitForExit(600000)) {
    Stop-Process -Id $benchmarkProcess.Id
    throw 'Settlement benchmark exceeded ten-minute timeout'
}
Get-Content (Join-Path $benchmarkOutput 'run.err') -Tail 18
Get-Content (Join-Path $benchmarkOutput 'run.out') -Tail 3
if ($benchmarkProcess.ExitCode -ne 0) { exit $benchmarkProcess.ExitCode }
if (Select-String -LiteralPath (Join-Path $benchmarkOutput 'run.err') -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { exit 1 }
if (-not (Select-String -LiteralPath (Join-Path $benchmarkOutput 'run.out') -Pattern '^SETTLEMENT_BENCHMARK_PASS' -Quiet)) { exit 1 }
exit 0
