param([string]$Label='cpu_uncached')
$ErrorActionPreference='Stop'
$cpuRoot='P:/Deepdraft/tmp/room_rebuild_20261014'
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
try {
    $env:APPDATA=$cpuRoot+'/'+$Label+'_profile'
    $env:LOCALAPPDATA=$env:APPDATA
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    $args=@('--headless','--path','P:/Deepdraft','--audio-driver','Dummy','--script','res://tools/performance/RoomRebuildBenchmark.gd','--',('--output=res://tmp/room_rebuild_20261014/'+$Label+'.json'))
    $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput ($cpuRoot+'/'+$Label+'.out') -RedirectStandardError ($cpuRoot+'/'+$Label+'.err')
    $null=$p.Handle
    if(-not $p.WaitForExit(120000)){Stop-Process -Id $p.Id; throw 'CPU benchmark timeout'}
    if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($cpuRoot+'/'+$Label+'.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content ($cpuRoot+'/'+$Label+'.err') -Tail 25; throw 'CPU benchmark failed'}
    if(-not (Select-String -LiteralPath ($cpuRoot+'/'+$Label+'.out') -Pattern '^ROOM_CPU_BENCHMARK_PASS' -Quiet)){throw 'Missing pass marker'}
    Write-Output ('CPU_BENCHMARK_PASS '+$Label)
} finally {$env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData}
