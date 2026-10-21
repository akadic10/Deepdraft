param([string]$Label = 'voxel_import')
$ErrorActionPreference='Stop'
$migrationRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$migrationOutput=Join-Path $migrationRoot ('tmp/settlement_art_20261013/'+$Label)
New-Item -ItemType Directory -Force $migrationOutput | Out-Null
$migrationRoaming=$env:APPDATA
$migrationLocal=$env:LOCALAPPDATA
try {
    $env:APPDATA=Join-Path $migrationOutput 'profile'
    $env:LOCALAPPDATA=Join-Path $migrationOutput 'local'
    $migrationProcess=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList @('--headless','--editor','--path',('"'+$migrationRoot+'"'),'--import') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $migrationOutput 'run.out') -RedirectStandardError (Join-Path $migrationOutput 'run.err')
    if ($migrationProcess.ExitCode -ne 0) { throw "Import failed: $($migrationProcess.ExitCode)" }
    Write-Output "Import complete: $migrationOutput"
} finally { $env:APPDATA=$migrationRoaming; $env:LOCALAPPDATA=$migrationLocal }
