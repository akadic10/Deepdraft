param([string]$Label='regressions', [string[]]$TestNames=@())
$ErrorActionPreference='Stop'
$checkRoot='P:/Deepdraft/tmp/shared_atmosphere_20261015/'+$Label
if(Test-Path -LiteralPath $checkRoot){throw 'Use a fresh label'}
New-Item -ItemType Directory -Force -Path $checkRoot | Out-Null
$results=@()
$specs=@(
 @{name='WeatherPersistenceTest';native=$false},
 @{name='SkySceneLifecycleTest';native=$false},
 @{name='TerrainAppearanceTest';native=$false},
 @{name='SaveManagerRoundTripTest';native=$false},
 @{name='UndergroundLightingTest';native=$true;guard='underground_lighting_review';capture='tmp/underground_lighting_review/entrance_fix'},
 @{name='TunnelEntranceTest';native=$true;guard='underground_lighting_review';capture='tmp/underground_lighting_review/entrance_fix'},
 @{name='RoomLightingTest';native=$true;guard='room_lighting_review'},
 @{name='DoorLightingTest';native=$true;guard='door_lighting_20261011';capture='tmp/door_lighting_20261011'},
 @{name='DwarfLimbLightingTest';native=$true;capture='tmp/dwarf_limb_lighting_20261013'}
)
foreach($spec in $specs){
 if($TestNames.Count -gt 0 -and $spec.name -notin $TestNames){continue}
 $dir=Join-Path $checkRoot $spec.name
 New-Item -ItemType Directory -Force -Path $dir | Out-Null
 $backup=@{}
 if($spec.capture){
  $captureRoot=Join-Path 'P:/Deepdraft' $spec.capture
  foreach($file in Get-ChildItem -LiteralPath $captureRoot -File -ErrorAction SilentlyContinue){
   if($file.Extension -in '.png','.json'){$backup[$file.FullName]=[IO.File]::ReadAllBytes($file.FullName)}
  }
 }
 $priorApp=$env:APPDATA; $priorLocal=$env:LOCALAPPDATA
 try{
  $profileBase=if($spec.guard){Join-Path $dir $spec.guard}else{$dir}; $env:APPDATA=Join-Path $profileBase 'profile'; $env:LOCALAPPDATA=$env:APPDATA
  New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
  $arguments=@('--path','P:/Deepdraft','--audio-driver','Dummy','--script',('res://scripts/tests/'+$spec.name+'.gd'))
  if(-not $spec.native){$arguments=@('--headless')+$arguments}
  if($spec.name -eq 'RoomLightingTest'){$arguments+=@('--',('--output='+$dir+'/captures'))}
  $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($dir+'/run.out') -RedirectStandardError ($dir+'/run.err')
  $null=$p.Handle
  if(-not $p.WaitForExit(240000)){Stop-Process -Id $p.Id; throw ('Timeout '+$spec.name)}
  $clean=$p.ExitCode -eq 0 -and -not (Select-String -LiteralPath ($dir+'/run.err') -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)
  $results+=@{test=$spec.name;exit=$p.ExitCode;clean=$clean;native=$spec.native}
  $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($checkRoot+'/results.json')
  if($spec.capture){
   New-Item -ItemType Directory -Force -Path ($dir+'/captures') | Out-Null
   Get-ChildItem -LiteralPath $captureRoot -File | Where-Object {$_.Extension -in '.png','.json'} | Copy-Item -Destination ($dir+'/captures')
  }
  Write-Output ($spec.name+' clean='+$clean)
  if(-not $clean){Get-Content -LiteralPath ($dir+'/run.err') -Tail 25; throw ('Failed '+$spec.name)}
 }finally{
  $env:APPDATA=$priorApp; $env:LOCALAPPDATA=$priorLocal
  foreach($path in $backup.Keys){[IO.File]::WriteAllBytes($path,$backup[$path])}
 }
}
