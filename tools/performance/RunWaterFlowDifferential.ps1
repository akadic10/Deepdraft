param([string]$Label='differential')
$ErrorActionPreference='Stop'
if($Label -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Invalid label'}
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runRoot=Join-Path $projectRoot ('tmp/water_loop_20261014/'+$Label)
if(Test-Path -LiteralPath $runRoot){throw 'Use a new label to preserve results'}
New-Item -ItemType Directory -Force $runRoot | Out-Null
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
try {
    $env:APPDATA=$runRoot+'/profile'
    $env:LOCALAPPDATA=$env:APPDATA
    $arguments=@('--headless','--path',('"'+$projectRoot+'"'),'--audio-driver','Dummy','--script','res://tools/performance/WaterFlowDifferential.gd','--',('--output='+$runRoot+'/result.json'))
    $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($runRoot+'/run.out') -RedirectStandardError ($runRoot+'/run.err')
    $null=$p.Handle
    if(-not $p.WaitForExit(300000)){Stop-Process -Id $p.Id; throw 'Differential timeout'}
    Get-Content ($runRoot+'/run.out') -Tail 3
    if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($runRoot+'/run.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content ($runRoot+'/run.err') -Tail 30; throw 'Differential failed'}
    if(-not (Select-String -LiteralPath ($runRoot+'/run.out') -Pattern '^WATER_FLOW_DIFFERENTIAL ' -Quiet)){throw 'Missing differential result'}
} finally {$env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData}
