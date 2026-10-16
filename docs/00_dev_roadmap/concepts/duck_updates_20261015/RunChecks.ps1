param([string]$Label='checks', [string[]]$Names=@('DuckSolidBoundsTest','AnimalNavigationCacheTest','DuckQueryReuseTest','DuckWildlifeTest','DuckPopulationTest','ArrivalPreparationTest','ArrivalEventTest','HerdArrivalTest','RabbitWildlifeTest','DeerWildlifeTest','WolfWildlifeTest','SaveManagerRoundTripTest'))
$ErrorActionPreference='Stop'
$base='P:/Deepdraft/tmp/duck_updates_20261015/'+$Label
if(Test-Path -LiteralPath $base){throw 'Use a fresh label'}
New-Item -ItemType Directory -Force -Path $base | Out-Null
$results=@()
$tracked=@(& git ls-files tmp)
$backup=@{}
foreach($rel in $tracked){
 $path=Join-Path 'P:/Deepdraft' $rel
 if(Test-Path -LiteralPath $path -PathType Leaf){$backup[$path]=[IO.File]::ReadAllBytes($path)}
}
$priorApp=$env:APPDATA; $priorLocal=$env:LOCALAPPDATA
try{
 foreach($name in $Names){
  $dir=Join-Path $base $name
  $env:APPDATA=Join-Path $dir 'profile'; $env:LOCALAPPDATA=$env:APPDATA
  New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
  $p=Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList @('--headless','--path','P:/Deepdraft','--audio-driver','Dummy','--script',('res://scripts/tests/'+$name+'.gd')) -WindowStyle Hidden -PassThru -RedirectStandardOutput ($dir+'/run.out') -RedirectStandardError ($dir+'/run.err')
  $null=$p.Handle
  if(-not $p.WaitForExit(240000)){Stop-Process -Id $p.Id; throw ('Timeout '+$name)}
  $clean=$p.ExitCode -eq 0 -and -not (Select-String -LiteralPath ($dir+'/run.err') -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)
  $results+=@{test=$name;exit=$p.ExitCode;clean=$clean}
  $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($base+'/results.json')
  Write-Output ($name+' clean='+$clean)
  Get-Content -LiteralPath ($dir+'/run.out') -Tail 1
  if(-not $clean){Get-Content -LiteralPath ($dir+'/run.err') -Tail 30; throw ('Failed '+$name)}
 }
}finally{
 $env:APPDATA=$priorApp; $env:LOCALAPPDATA=$priorLocal
 New-Item -ItemType Directory -Force -Path ($base+'/changed_fixture_outputs') | Out-Null
 foreach($path in $backup.Keys){
  if(Test-Path -LiteralPath $path){
   $now=[IO.File]::ReadAllBytes($path)
   if([Convert]::ToBase64String($now) -ne [Convert]::ToBase64String($backup[$path])){
    $dest=Join-Path ($base+'/changed_fixture_outputs') $path.Substring('P:/Deepdraft/'.Length).Replace('\','_').Replace('/','_')
    [IO.File]::WriteAllBytes($dest,$now)
   }
  }
  [IO.File]::WriteAllBytes($path,$backup[$path])
 }
}
