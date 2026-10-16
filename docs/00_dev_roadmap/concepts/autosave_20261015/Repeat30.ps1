$ErrorActionPreference='Stop'
$paths=@{
 'scripts/systems/SaveManager.gd'='SaveManager.gd.before.txt'
 'scripts/components/SaveSnapshotValidator.gd'='SaveSnapshotValidator.gd.before.txt'
 'scripts/systems/WaterManager.gd'='WaterManager.gd.before.txt'
 'scripts/systems/MiningDesignationController.gd'='MiningDesignationController.gd.before.txt'
 'scripts/systems/ItemDropManager.gd'='ItemDropManager.gd.before.txt'
}
$final=@{}
foreach($relative in $paths.Keys){$final[$relative]=[IO.File]::ReadAllBytes('P:/Deepdraft/'+$relative)}
try {
 foreach($relative in $paths.Keys){[IO.File]::WriteAllBytes('P:/Deepdraft/'+$relative,[IO.File]::ReadAllBytes('P:/Deepdraft/docs/00_dev_roadmap/concepts/autosave_20261015/'+$paths[$relative]))}
 & P:/Deepdraft/tools/performance/RunAutosave.ps1 -Population 30 -Label autosave_before_repeat_30 -SavePath P:/Deepdraft/tmp/autosave_20261015/input_quicksave.json -Seconds 24 -NoAblations -Weather base:weather:clear -ProfileBaseline
} finally {foreach($relative in $paths.Keys){[IO.File]::WriteAllBytes('P:/Deepdraft/'+$relative,$final[$relative])}}
& P:/Deepdraft/tools/performance/RunAutosave.ps1 -Population 30 -Label autosave_after_repeat_30 -SavePath P:/Deepdraft/tmp/autosave_20261015/input_quicksave.json -Seconds 24 -NoAblations -Weather base:weather:clear

