$ErrorActionPreference='Stop'
$root='P:/Deepdraft'
$targets=@{
 'scripts/components/UndergroundLighting.gd'='UndergroundLighting.gd.before.txt'
 'scripts/shaders/underground_lighting.gdshader'='underground_lighting.gdshader.before.txt'
}
$scratch=Join-Path $root 'tmp/shared_atmosphere_20261015'
$after=@{}
$baseline=@{}
foreach($path in $targets.Keys){
 $after[$path]=[IO.File]::ReadAllBytes((Join-Path $root $path))
 $baseline[$path]=[IO.File]::ReadAllBytes((Join-Path $scratch $targets[$path]))
 [IO.File]::WriteAllBytes((Join-Path $scratch ($targets[$path]+'.after')),$after[$path])
}
try{
 foreach($path in $targets.Keys){[IO.File]::WriteAllBytes((Join-Path $root $path),$baseline[$path])}
 & (Join-Path $root 'tools/performance/RunSteadyRendering.ps1') -Label atmosphere_baseline_repeat -SavePath (Join-Path $scratch 'input_quicksave.json') -NoMarkers -NoAblations
 if($LASTEXITCODE -ne 0){throw 'Baseline repeat failed'}
}finally{
 foreach($path in $targets.Keys){
  $current=[IO.File]::ReadAllBytes((Join-Path $root $path))
  if([Convert]::ToBase64String($current) -ne [Convert]::ToBase64String($baseline[$path])){throw ('Concurrent source edit, retained snapshots: '+$path)}
 }
 foreach($path in $targets.Keys){[IO.File]::WriteAllBytes((Join-Path $root $path),$after[$path])}
 Write-Output 'ATMOSPHERE_AFTER_SOURCES_RESTORED'
}
