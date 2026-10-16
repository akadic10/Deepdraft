$ErrorActionPreference='Stop'
$root='P:/Deepdraft'
$scratch=Join-Path $root 'tmp/duck_updates_20261015'
$runner=Join-Path $root 'tools/performance/RunSteadyRendering.ps1'
& $runner -Label duck_update_after_plain_a -SavePath ($scratch+'/input_quicksave.json') -NoMarkers -NoAblations
if($LASTEXITCODE -ne 0){throw 'After A failed'}
$targets=@{
 'scripts/components/AnimalNavigation.gd'='AnimalNavigation.gd.before.txt'
 'scripts/components/DuckNavigation.gd'='DuckNavigation.gd.before.txt'
}
$after=@{}; $before=@{}
foreach($path in $targets.Keys){
 $after[$path]=[IO.File]::ReadAllBytes((Join-Path $root $path))
 $before[$path]=[IO.File]::ReadAllBytes((Join-Path $scratch $targets[$path]))
 [IO.File]::WriteAllBytes((Join-Path $scratch ($targets[$path]+'.after')),$after[$path])
}
try{
 foreach($path in $targets.Keys){[IO.File]::WriteAllBytes((Join-Path $root $path),$before[$path])}
 & $runner -Label duck_update_before_plain -SavePath ($scratch+'/input_quicksave.json') -NoMarkers -NoAblations
 if($LASTEXITCODE -ne 0){throw 'Before control failed'}
}finally{
 foreach($path in $targets.Keys){
  $current=[IO.File]::ReadAllBytes((Join-Path $root $path))
  if([Convert]::ToBase64String($current) -ne [Convert]::ToBase64String($before[$path])){throw ('Concurrent source edit; retained snapshots: '+$path)}
 }
 foreach($path in $targets.Keys){[IO.File]::WriteAllBytes((Join-Path $root $path),$after[$path])}
 Write-Output 'DUCK_OPTIMIZED_SOURCES_RESTORED'
}
& $runner -Label duck_update_after_plain_b -SavePath ($scratch+'/input_quicksave.json') -NoMarkers -NoAblations
if($LASTEXITCODE -ne 0){throw 'After B failed'}
