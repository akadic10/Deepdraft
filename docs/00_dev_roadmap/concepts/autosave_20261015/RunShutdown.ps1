$ErrorActionPreference='Stop'
$root='P:/Deepdraft/tmp/autosave_20261015/shutdown'
New-Item -ItemType Directory -Force $root | Out-Null
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
try {
 $env:APPDATA=$root+'/profile'
 $env:LOCALAPPDATA=$env:APPDATA
 New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
 $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList @('--headless','--path','P:/Deepdraft','--audio-driver','Dummy','--script','res://scripts/tests/SaveWorkerShutdownTest.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput ($root+'/run.out') -RedirectStandardError ($root+'/run.err')
 $null=$p.Handle
 if(-not $p.WaitForExit(60000)){Stop-Process -Id $p.Id; throw 'Shutdown test timed out'}
 if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($root+'/run.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content ($root+'/run.err'); throw 'Shutdown test failed'}
 if(-not (Select-String -LiteralPath ($root+'/run.out') -Pattern '^SAVE_SHUTDOWN_JOIN_REQUESTED' -Quiet)){throw 'Missing shutdown marker'}
 $saved=Get-Content -LiteralPath ($env:APPDATA+'/Godot/app_userdata/Deepdraft/shutdown_save/quicksave.json') -Raw | ConvertFrom-Json
 if($saved.schema_version -ne 1){throw 'Shutdown save missing or invalid'}
 @{exit_code=$p.ExitCode;completed_save_exists=$true;save_manager_sha256=(Get-FileHash 'P:/Deepdraft/scripts/systems/SaveManager.gd').Hash.ToLower()}|ConvertTo-Json|Set-Content ($root+'/result.json')
 Write-Output 'SHUTDOWN_JOIN_PASS'
} finally {$env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData}
