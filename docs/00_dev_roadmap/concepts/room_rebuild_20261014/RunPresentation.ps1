$ErrorActionPreference='Stop'
$nativeRoot='P:/Deepdraft/tmp/room_rebuild_20261014'
$nativeProfile='P:/Deepdraft/tmp/room_lighting_review/room_rebuild_20261014_profile'
New-Item -ItemType Directory -Force $nativeProfile | Out-Null
$oldAppData=$env:APPDATA
$oldLocalAppData=$env:LOCALAPPDATA
try {
    $env:APPDATA=$nativeProfile
    $env:LOCALAPPDATA=$nativeProfile
    $nativeArgs=@('--path','P:/Deepdraft','--audio-driver','Dummy','--script','res://scripts/tests/RoomLightingTest.gd','--','--output=res://tmp/room_rebuild_20261014/native')
    $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $nativeArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput ($nativeRoot+'/native.out') -RedirectStandardError ($nativeRoot+'/native.err')
    $null=$p.Handle
    if(-not $p.WaitForExit(210000)){Stop-Process -Id $p.Id; throw 'Native room timeout'}
    Get-Content ($nativeRoot+'/native.out') -Tail 4
    if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($nativeRoot+'/native.err') -Pattern '^SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content ($nativeRoot+'/native.err') -Tail 25; throw 'Native room errors'}
    if(-not (Select-String -LiteralPath ($nativeRoot+'/native.out') -Pattern '^ROOM_LIGHTING_TEST:' -Quiet)){throw 'Missing room result'}
    @{exit_code=$p.ExitCode;pass=$true;errors=$false}|ConvertTo-Json|Set-Content ($nativeRoot+'/native.json')
} finally {$env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData}
