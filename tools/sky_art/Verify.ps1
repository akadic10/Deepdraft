param([string[]]$Tests = @('DioramaSkyTest', 'SkyDialTest', 'WeatherPersistenceTest', 'UndergroundLightingTest', 'RoomLightingTest', 'TunnelEntranceTest'), [switch]$ReadExisting)
$ErrorActionPreference = 'Stop'
$skyRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skyOutput = Join-Path $skyRoot 'tmp/sky_art_20261013/verification'
New-Item -ItemType Directory -Force $skyOutput | Out-Null
$skyResults = @()
foreach ($skyCase in $Tests) {
    if ($skyCase -notmatch '^[A-Za-z0-9_]+Test$') { throw 'Invalid test name' }
    if (-not $ReadExisting) {
    $skyProfile = if ($skyCase -eq 'RoomLightingTest') { 'room_lighting_review' } elseif ($skyCase -in @('UndergroundLightingTest', 'TunnelEntranceTest')) { 'underground_lighting_review' } else { 'sky_art_20261013' }
    $skyArgs = @('--path', ('"' + $skyRoot + '"'), '--audio-driver', 'Dummy', '--script', ('res://scripts/tests/' + $skyCase + '.gd'))
    if ($skyCase -in @('SkyDialTest', 'WeatherPersistenceTest')) { $skyArgs += '--headless' }
    $skyAppData = $env:APPDATA
    try {
        $env:APPDATA = Join-Path $skyRoot ('tmp/' + $skyProfile + '/sky_profile')
        $skyProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $skyArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $skyOutput ($skyCase + '.out')) -RedirectStandardError (Join-Path $skyOutput ($skyCase + '.err')) -PassThru
        $null = $skyProcess.Handle
    } finally { $env:APPDATA = $skyAppData }
    if (-not $skyProcess.WaitForExit(210000)) { Stop-Process -Id $skyProcess.Id; throw "$skyCase timeout" }
    $skyProcess.ExitCode | Set-Content (Join-Path $skyOutput ($skyCase + '.exit'))
    }
    $skyErrors = [string](Get-Content (Join-Path $skyOutput ($skyCase + '.err')) -Raw)
    $skyText = Get-Content (Join-Path $skyOutput ($skyCase + '.out')) -Raw
    $skyExit = [int](Get-Content (Join-Path $skyOutput ($skyCase + '.exit')))
    $skyMarker = $skyText -match '_PASS\b|_OK\b|: PASS\b'
    $skyStructured = [regex]::Matches($skyText, '(?m)^[A-Z_]+_TEST: (\{[^\r\n]+\})')
    if ($skyStructured.Count -gt 0) {
        $skyReport = $skyStructured[$skyStructured.Count - 1].Groups[1].Value | ConvertFrom-Json
        $skyMarker = $null -ne $skyReport.failures -and $skyReport.failures.Count -eq 0
    }
    $skyPassed = $skyExit -eq 0 -and $skyErrors -notmatch '(?m)^SCRIPT ERROR:|^ERROR:' -and $skyMarker
    $skyResults += [ordered]@{ test = $skyCase; passed = $skyPassed; exit = $skyExit }
    $skyResults | ConvertTo-Json | Set-Content (Join-Path $skyOutput 'results.json')
    Write-Output "$skyCase passed=$skyPassed"
    if (-not $skyPassed) { Get-Content (Join-Path $skyOutput ($skyCase + '.err')) -Tail 15 }
}
if ($skyResults.passed -contains $false) { exit 1 }
