$ErrorActionPreference='Stop'
$base='P:/Deepdraft/tmp/duck_updates_20261015'
$package=Get-Content -LiteralPath ($base+'/package.json') -Raw | ConvertFrom-Json
$packed=$base+'/packed'
New-Item -ItemType Directory -Force -Path ($packed+'/profile/Godot/app_userdata/Deepdraft/saves') | Out-Null
Copy-Item -LiteralPath ($base+'/input_quicksave.json') -Destination ($packed+'/profile/Godot/app_userdata/Deepdraft/saves/quicksave.json')
$priorApp=$env:APPDATA; $priorLocal=$env:LOCALAPPDATA
try{
 $env:APPDATA=$packed+'/profile'; $env:LOCALAPPDATA=$env:APPDATA
 $arguments=@('--path',('"'+$package.directory+'"'),'--main-pack',('"'+$package.directory+'/Deepdraft.pck"'),'--disable-vsync','--audio-driver','Dummy','--script','P:/Deepdraft/tools/performance/SmokeDuckUpdatesExport.gd','--',('--output='+$packed))
 $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -WorkingDirectory $package.directory -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($packed+'/run.out') -RedirectStandardError ($packed+'/run.err')
 $null=$p.Handle
 if(-not $p.WaitForExit(210000)){Stop-Process -Id $p.Id; throw 'Packed duck timeout'}
 if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($packed+'/run.err') -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)){Get-Content -LiteralPath ($packed+'/run.err') -Tail 30; throw 'Packed duck failure'}
 if(-not (Select-String -LiteralPath ($packed+'/run.out') -Pattern '^DUCK_UPDATES_EXPORT_PASS' -Quiet)){throw 'Missing packed PASS'}
 Get-Content -LiteralPath ($packed+'/run.out') -Tail 3
 $env:APPDATA=$base+'/startup_profile'; $env:LOCALAPPDATA=$env:APPDATA
 New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
 $p=Start-Process -FilePath $package.exe -WorkingDirectory $package.directory -ArgumentList @('--disable-vsync','--max-fps','60','--audio-driver','Dummy','--quit-after','2400') -WindowStyle Hidden -PassThru -RedirectStandardOutput ($base+'/startup.out') -RedirectStandardError ($base+'/startup.err')
 $null=$p.Handle
 if(-not $p.WaitForExit(180000)){Stop-Process -Id $p.Id; throw 'Release startup timeout'}
 if($p.ExitCode -ne 0 -or (Select-String -LiteralPath ($base+'/startup.err') -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)){Get-Content -LiteralPath ($base+'/startup.err') -Tail 25; throw 'Release startup failure'}
 if(-not (Select-String -LiteralPath ($base+'/startup.out') -Pattern 'built block-face overview tiles \(1024 tiles' -Quiet)){throw 'Release did not finish world overview'}
 Get-Content -LiteralPath ($base+'/startup.out') -Tail 5
}finally{
 $env:APPDATA=$priorApp; $env:LOCALAPPDATA=$priorLocal
}
