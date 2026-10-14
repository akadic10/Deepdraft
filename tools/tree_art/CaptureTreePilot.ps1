param([ValidatePattern('^[a-z0-9_]+$')][string]$Label = 'pilot', [switch]$Baseline, [switch]$FruitTrees)
$ErrorActionPreference = 'Stop'
if ($Baseline) { throw 'Legacy model comparisons were retired; use the dated art reports for historical captures.' }
$treeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$treeOutput = Join-Path $treeRoot ('tmp/tree_pilot_20261013/'+$Label)
New-Item -ItemType Directory -Force $treeOutput | Out-Null
$treeAppData = $env:APPDATA
$treeArgs = @('--path',('"'+$treeRoot+'"'),'--script','res://tools/tree_art/CaptureTreePilot.gd','--',('--output=res://tmp/tree_pilot_20261013/'+$Label))
if ($FruitTrees) { $treeArgs += '--fruit-trees' }
try {
    $env:APPDATA = Join-Path $treeOutput 'profile'
    $treeProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $treeArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $treeOutput 'run.out') -RedirectStandardError (Join-Path $treeOutput 'run.err') -PassThru
    $null = $treeProcess.Handle
} finally { $env:APPDATA = $treeAppData }
$treeProcess.WaitForExit()
Get-Content (Join-Path $treeOutput 'run.err')
Get-Content (Join-Path $treeOutput 'run.out') -Tail 4
if ($treeProcess.ExitCode -ne 0) { exit $treeProcess.ExitCode }
if (-not (Select-String -LiteralPath (Join-Path $treeOutput 'run.out') -Pattern '^TREE_PILOT_CAPTURE_PASS' -Quiet)) { exit 1 }
