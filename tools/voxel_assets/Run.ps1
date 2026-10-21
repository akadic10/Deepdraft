param(
    [string]$Script = 'res://tools/voxel_assets/WorldBenchmark.gd',
    [string]$Label = 'voxel_before_bounded',
    [switch]$Headless,
    [string[]]$UserArgs = @(),
    [string]$Godot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid run label' }
$migrationRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$migrationOutput = Join-Path $migrationRoot ('tmp/settlement_art_20261013/'+$Label)
New-Item -ItemType Directory -Force $migrationOutput | Out-Null
$migrationArgs = @('--path',('"'+$migrationRoot+'"'),'--windowed','--resolution','1600x1000','--audio-driver','Dummy')
if ($Headless) { $migrationArgs += '--headless' }
if ($Script -like '*WorldBenchmark.gd') { $migrationArgs += @('--fixed-fps','60','--disable-vsync') }
$migrationArgs += @('--script',$Script,'--',('--output=res://tmp/settlement_art_20261013/'+$Label),'--small')
$migrationArgs += $UserArgs
$migrationRoaming = $env:APPDATA
$migrationLocal = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $migrationOutput 'profile'
    $env:LOCALAPPDATA = Join-Path $migrationOutput 'local'
    $migrationProcess = Start-Process -FilePath $Godot -ArgumentList $migrationArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $migrationOutput 'run.out') -RedirectStandardError (Join-Path $migrationOutput 'run.err')
    @{pid=$migrationProcess.Id; script=$Script; output=$migrationOutput; started=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $migrationOutput 'process.json')
    Write-Output "Started $Label (PID $($migrationProcess.Id)); logs: $migrationOutput"
} finally { $env:APPDATA=$migrationRoaming; $env:LOCALAPPDATA=$migrationLocal }
