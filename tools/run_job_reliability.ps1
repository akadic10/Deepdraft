param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string[]]$Tests = @('JobLifecycleTest','JobPlanningTest','JobMixedWorldTest',
        'FurnitureAssignmentTest','FurniturePlacementAnimationTest','FurnitureMoveTest','HearthRoomTest','SettlementFlagMoveTest','WallMountHeightTest',
        'LadderSchedulingTest','LadderTest','LadderMiningTest',
        'CraftingSelectionTest','WorkerCraftingTest','WorkerCraftingWoodTest','RudimentaryRecreationTest','RecreationSoloTest',
        'HaulingSelectionTest','HaulingAnimationTest','HaulingCapacityTest','FruitHaulingTest','SurfaceWorkSelectionTest',
        'TreeFellingTest','AppleHarvestTest','JuniperHarvestTest','MinerProfessionTest','MiningHiddenAirTest','MiningDragLimitTest','PlacementHaulPriorityTest',
        'ShrubMoveHandoffTest','DwarfSupportTest','DwarfIdleBehaviorTest','DwarfIdlePlanningTest','DwarfFoodTest','DwarfDiningTest','ShrubRegrowthTest',
        'BridgeCornerWalkingTest','NavigationRegressionTest','ConstructionTest','ConstructionStagingTest','ConstructionContinuityTest','ConstructionDevTest','ConstructionInputTest','FloorConstructionTest','RetiredStoneMigrationTest','SaveManagerRoundTripTest'),
    [string]$LogDirectory = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
if (-not $LogDirectory) { $LogDirectory = Join-Path $projectRoot ('tmp/job_gate_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$LogDirectory = (Resolve-Path -LiteralPath $LogDirectory).Path
$results = @()
foreach ($case in $Tests) {
    if ($case -notmatch '^[A-Za-z0-9_]+Test$') { throw "Invalid fixture name: $case" }
    $outFile = Join-Path $LogDirectory ($case + '.out')
    $errFile = Join-Path $LogDirectory ($case + '.err')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $godotPath -ArgumentList @('--headless','--path',('"'+$projectRoot+'"'),'--script',('res://scripts/tests/'+$case+'.gd')) -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $process.Handle  # hold the handle: Windows PowerShell 5.1 otherwise loses ExitCode
    $limit = if ($case -eq 'SaveManagerRoundTripTest') { 360 } else { 180 }
    $timedOut = $false
    while (-not $process.WaitForExit(1000)) {
        if ($timer.Elapsed.TotalSeconds -gt $limit) { $process.Kill(); $process.WaitForExit(); $timedOut=$true; break }
    }
    $output = Get-Content -LiteralPath $outFile -Raw
    $errors = [string](Get-Content -LiteralPath $errFile -Raw)
    $marker = '_OK\b|_PASS\b|' + [regex]::Escape($case) + ': PASS\b'
    $passed = -not $timedOut -and $process.ExitCode -eq 0 -and $output -match $marker -and $errors -notmatch '(?m)^SCRIPT ERROR:|^ERROR:'
    $entry = [ordered]@{test=$case;passed=$passed;exit=$process.ExitCode;seconds=[math]::Round($timer.Elapsed.TotalSeconds,2);timeout=$timedOut}
    $results += $entry
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LogDirectory 'results.json')
    Write-Output (('{0} {1} ({2}s)' -f $(if($passed){'PASS'}else{'FAIL'}),$case,$entry.seconds))
}
Write-Output ('Logs: '+$LogDirectory)
if ($results.Where({-not $_.passed}).Count -gt 0) { exit 1 }
exit 0
