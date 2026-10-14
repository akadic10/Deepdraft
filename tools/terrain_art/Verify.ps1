param([ValidateSet('Focused','Generation')][string]$Group = 'Focused', [string[]]$Only = @())
$ErrorActionPreference = 'Stop'
$terrainRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$terrainOutput = Join-Path $terrainRoot ('tmp/terrain_art_20261013/verify_' + $Group.ToLower())
New-Item -ItemType Directory -Force $terrainOutput | Out-Null
$terrainCases = if ($Group -eq 'Focused') {
    @('TerrainAppearanceTest','TerrainExplorerTest','WorldTerrainStartupTest','UndergroundLightingTest')
} else {
    @('WorldLayoutTest','WorldGenerationTest','WorldResourceDiagnosticsTest','CaveGenerationTest')
}
if ($Only.Count -gt 0) {
    foreach ($terrainRequested in $Only) { if ($terrainRequested -notin $terrainCases) { throw "Unknown $Group case: $terrainRequested" } }
    $terrainCases = @($terrainCases | Where-Object { $_ -in $Only })
}
$terrainResults = @()
if ($Only.Count -gt 0 -and (Test-Path -LiteralPath (Join-Path $terrainOutput 'results.json'))) {
    $terrainResults = @((Get-Content -LiteralPath (Join-Path $terrainOutput 'results.json') -Raw | ConvertFrom-Json) | Where-Object { $_.test -notin $Only })
}
foreach ($terrainCase in $terrainCases) {
    $terrainOut = Join-Path $terrainOutput ($terrainCase + '.out')
    $terrainErr = Join-Path $terrainOutput ($terrainCase + '.err')
    $terrainProfile = if ($terrainCase -eq 'UndergroundLightingTest') { 'tmp/underground_lighting_review/terrain_art_profile' } elseif ($Group -eq 'Generation') { 'tmp/world_layout_review/terrain_art_profile' } else { 'tmp/terrain_art_20261013/test_profile' }
    $terrainArgs = @('--path',('"'+$terrainRoot+'"'),'--script',('res://scripts/tests/'+$terrainCase+'.gd'))
    if ($terrainCase -ne 'UndergroundLightingTest') { $terrainArgs = @('--headless') + $terrainArgs }
    $terrainPreviousAppData = $env:APPDATA
    $terrainTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $env:APPDATA = Join-Path $terrainRoot $terrainProfile
        $terrainProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $terrainArgs -WindowStyle Hidden -RedirectStandardOutput $terrainOut -RedirectStandardError $terrainErr -PassThru
        $null = $terrainProcess.Handle
    } finally { $env:APPDATA = $terrainPreviousAppData }
    $terrainTimedOut = $false
    while (-not $terrainProcess.WaitForExit(1000)) {
        if ($terrainTimer.Elapsed.TotalSeconds -gt 360) { $terrainProcess.Kill(); $terrainProcess.WaitForExit(); $terrainTimedOut = $true; break }
    }
    $terrainText = [string](Get-Content -LiteralPath $terrainOut -Raw)
    $terrainErrors = [string](Get-Content -LiteralPath $terrainErr -Raw)
    $terrainMarkerOk = if ($terrainCase -eq 'UndergroundLightingTest') { $terrainText -match 'UNDERGROUND_LIGHTING_TEST: [^\r\n]*"failures":\[\]' } else { $terrainText -match 'PASS|_OK\b' }
    $terrainPassed = -not $terrainTimedOut -and $terrainProcess.ExitCode -eq 0 -and $terrainErrors -notmatch '(?m)^SCRIPT ERROR:|^ERROR:' -and $terrainMarkerOk
    $terrainResults += [ordered]@{test=$terrainCase;passed=$terrainPassed;seconds=[math]::Round($terrainTimer.Elapsed.TotalSeconds,2);exit=$terrainProcess.ExitCode;timeout=$terrainTimedOut}
    $terrainResults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $terrainOutput 'results.json')
    $terrainResultLabel = if ($terrainPassed) { 'PASS ' } else { 'FAIL ' }
    Write-Output ($terrainResultLabel + $terrainCase)
}
if ($terrainResults.Where({-not $_.passed}).Count -gt 0) { exit 1 }
