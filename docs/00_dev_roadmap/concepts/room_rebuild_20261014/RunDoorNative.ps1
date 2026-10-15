$ErrorActionPreference='Stop'
$nativeRoot='P:/Deepdraft/tmp/room_rebuild_20261014'
$nativeProfile='P:/Deepdraft/tmp/door_lighting_20261011/room_rebuild_20261014_profile'
New-Item -ItemType Directory -Force $nativeProfile | Out-Null
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
try {
    $env:APPDATA=$nativeProfile
    $env:LOCALAPPDATA=$nativeProfile
    $nativeArgs=@('--path','P:/Deepdraft','--audio-driver','Dummy','--script','res://tmp/room_rebuild_20261014/DoorLightingNative.gd','--','--output=res://tmp/room_rebuild_20261014/native')
    $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $nativeArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput ($nativeRoot+'/door_native.out') -RedirectStandardError ($nativeRoot+'/door_native.err')
    $null=$p.Handle
    if(-not $p.WaitForExit(210000)){Stop-Process -Id $p.Id; throw 'Native room timeout'}
    Get-Content ($nativeRoot+'/door_native.out') -Tail 4
    if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($nativeRoot+'/door_native.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content ($nativeRoot+'/door_native.err') -Tail 25; throw 'Native room errors'}
    if(-not (Select-String -LiteralPath ($nativeRoot+'/door_native.out') -Pattern 'DoorLightingTest: PASS' -Quiet)){throw 'Missing room result'}
    @{exit_code=$p.ExitCode;pass=$true;errors=$false}|ConvertTo-Json|Set-Content ($nativeRoot+'/door_native.json')
} finally {$env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData}

