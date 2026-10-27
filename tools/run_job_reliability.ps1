# Runs headless Godot tests, each in its own throwaway user-data profile, several at a time.
# With no selection it runs the job gate from tools/test_suite.json, plus tools/lint_project.py
# (also run with -All).
#   -Tests  names or wildcards (Hauling*, LadderTest)   -Area  groups from test_suite.json
#   -All    every *Test.gd in scripts/tests              -List  print the selection and stop
# A test passes when it exits 0, prints its pass marker and logs no SCRIPT ERROR to stderr.
# Output is one summary line plus details for failures; -ShowPasses lists passes too.
# On full success the run's logs, profiles and new tmp/ output are deleted unless -KeepOutput.
param(
    [string]$Godot = 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string[]]$Tests = @(),
    [string[]]$Area = @(),
    [switch]$All,
    [int]$Parallel = 8,
    [switch]$ShowPasses,
    [switch]$KeepOutput,
    [switch]$List,
    [string]$LogDirectory = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$suite = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test_suite.json') -Raw | ConvertFrom-Json
$available = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts\tests') -Filter '*Test.gd' | ForEach-Object { $_.BaseName } | Sort-Object)

function Expand-Patterns([string[]]$patterns) {
    $found = @()
    foreach ($pattern in $patterns) {
        $hits = @($available | Where-Object { $_ -like $pattern })
        if ($hits.Count -eq 0) { throw "No test matches '$pattern'" }
        $found += $hits
    }
    return $found
}

$selected = @()
if ($All) { $selected = $available }
foreach ($name in $Area) {
    $group = $suite.areas.PSObject.Properties[$name]
    if (-not $group) { throw "Unknown area '$name'. Areas: " + (($suite.areas.PSObject.Properties | ForEach-Object Name) -join ', ') }
    $selected += Expand-Patterns $group.Value
}
if ($Tests.Count -gt 0) { $selected += Expand-Patterns $Tests }
if (-not $All -and $Area.Count -eq 0 -and $Tests.Count -eq 0) { $selected = Expand-Patterns $suite.gate }
$selected = @($selected | Select-Object -Unique)
if ($List) { $selected; return }

# The gate and full runs also check the mechanical code rules (tools/lint_project.py).
$lintFailed = $false
if ($All -or ($Area.Count -eq 0 -and $Tests.Count -eq 0)) {
    $lint = @(& py (Join-Path $PSScriptRoot 'lint_project.py'))
    $lintFailed = $LASTEXITCODE -ne 0
    $lint | ForEach-Object { Write-Output $_ }
}

# Returns nothing for a missing entry, so @(Get-Setting ...) is empty rather than @($null).
function Get-Setting($table, [string]$test) {
    if ($null -eq $table) { return }
    $entry = $table.PSObject.Properties[$test]
    if ($entry) { return $entry.Value }
}
function Find-Group($table, [string]$test) {
    if ($null -eq $table) { return $null }
    foreach ($entry in $table.PSObject.Properties) { if ($entry.Value -contains $test) { return $entry.Name } }
    return $null
}

$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$tmpRoot = Join-Path $projectRoot 'tmp'
$tmpBefore = @(Get-ChildItem -LiteralPath $tmpRoot -Directory | ForEach-Object Name)
if (-not $LogDirectory) { $LogDirectory = Join-Path $tmpRoot ('test_run_' + $stamp) }
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$LogDirectory = (Resolve-Path -LiteralPath $LogDirectory).Path
$git = Get-Command git -ErrorAction SilentlyContinue
$gitBefore = if ($git) { @(& git -C $projectRoot status --porcelain) } else { @() }

# Tests whose guard checks the profile path get a profile under that folder; the rest share the run folder.
$profileRuns = @()
$index = 0
$jobs = foreach ($test in $selected) {
    $root = Find-Group $suite.profile_roots $test
    $profileBase = if ($root) { Join-Path $tmpRoot "$root\run_$stamp" } else { Join-Path $LogDirectory 'profiles' }
    if ($root) { $profileRuns += $profileBase }
    $phases = Get-Setting $suite.phases $test
    if ($null -eq $phases) { $phases = @(,@()) }
    $timeout = Get-Setting $suite.timeouts $test
    [pscustomobject]@{
        test = $test; index = $index++; phases = @($phases); phase = 0; profile = Join-Path $profileBase $test; out = ''; err = ''
        lock = Find-Group $suite.shared_output $test; timeout = $(if ($timeout) { [int]$timeout } else { 180 })
        process = $null; timer = $null; passed = $false; exit = $null; timedOut = $false; seconds = 0; scriptErrors = 0; failure = ''
        allowed = @(Get-Setting $suite.expected_errors $test)
    }
}
# Long tests first so they don't finish last on their own.
$pending = [Collections.Generic.List[object]]::new()
$jobs | Sort-Object -Property @{Expression='timeout';Descending=$true}, @{Expression='index';Ascending=$true} | ForEach-Object { $pending.Add($_) }

function Start-Phase($job) {
    $suffix = if ($job.phases.Count -gt 1) { ".p$($job.phase + 1)" } else { '' }
    $job.out = Join-Path $LogDirectory ($job.test + $suffix + '.out')
    $job.err = Join-Path $LogDirectory ($job.test + $suffix + '.err')
    $arguments = @('--headless','--path',('"'+$projectRoot+'"'),'--script',('res://scripts/tests/'+$job.test+'.gd'))
    $extra = @($job.phases[$job.phase])
    if ($extra.Count -gt 0) { $arguments += @('--') + $extra }
    $roaming = Join-Path $job.profile 'Roaming'
    $local = Join-Path $job.profile 'Local'
    New-Item -ItemType Directory -Path $roaming, $local -Force | Out-Null
    $savedAppData, $savedLocal = $env:APPDATA, $env:LOCALAPPDATA
    try {
        # Start-Process copies this process's environment, so the override reaches only this child.
        $env:APPDATA, $env:LOCALAPPDATA = $roaming, $local
        $job.process = Start-Process -FilePath $godotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $job.out -RedirectStandardError $job.err
    } finally { $env:APPDATA, $env:LOCALAPPDATA = $savedAppData, $savedLocal }
    $null = $job.process.Handle  # hold the handle: Windows PowerShell 5.1 otherwise loses ExitCode
    $job.timer = [Diagnostics.Stopwatch]::StartNew()
}

function Complete-Phase($job) {
    $output = [string](Get-Content -LiteralPath $job.out -Raw)
    $errors = [string](Get-Content -LiteralPath $job.err -Raw)
    # A test that exercises an error path lists the error lines it expects.
    foreach ($text in $job.allowed) {
        $errors = (($errors -split "`r?`n") | Where-Object { -not ($_ -match '^(SCRIPT )?ERROR:' -and $_.Contains($text)) }) -join "`n"
    }
    # A runtime error ends only the coroutine it happens in, so the test can still print its
    # marker and exit 0 with its later checks skipped: any SCRIPT ERROR fails it. ERROR and
    # WARNING lines (audio drivers, push_warning backtraces) don't. Each match keeps its "at:" line.
    $scriptErrors = @([regex]::Matches($errors, '(?m)^SCRIPT ERROR:.*(?:\r?\n\s+at: .*)?') | ForEach-Object Value)
    $job.scriptErrors = $scriptErrors.Count
    $job.exit = $job.process.ExitCode
    $job.seconds += [math]::Round($job.timer.Elapsed.TotalSeconds, 1)
    $final = $job.phase -eq $job.phases.Count - 1
    $marker = '_OK\b|_PASS\b|' + [regex]::Escape($job.test) + ': PASS\b'
    $ok = -not $job.timedOut -and $job.exit -eq 0 -and $scriptErrors.Count -eq 0 -and (-not $final -or $output -match $marker)
    if (-not $ok) {
        # Up to 8 error lines, distinct script errors first, then up to 5 FAIL lines.
        $errorLines = @($scriptErrors | Select-Object -Unique | ForEach-Object { $_ -split "`r?`n" })
        $errorLines += @(($errors -split "`r?`n") | Where-Object { $_ -match '^ERROR:' })
        $lines = @($errorLines | Select-Object -First 8)
        $lines += @(($output -split "`r?`n") | Where-Object { $_ -match 'FAIL' } | Select-Object -First 5)
        if ($lines.Count -eq 0) { $lines = @(($output -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 8) }
        $job.failure = ($lines | ForEach-Object { '    ' + $_.Trim() }) -join "`n"
        return $false
    }
    if (-not $final) { $job.phase++; Start-Phase $job; return $null }
    $job.passed = $true
    return $true
}

$clock = [Diagnostics.Stopwatch]::StartNew()
$running = [Collections.Generic.List[object]]::new()
$heldLocks = @{}
$finished = @()
while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    while ($running.Count -lt [math]::Max(1, $Parallel)) {
        $next = $pending | Where-Object { -not $_.lock -or -not $heldLocks.ContainsKey($_.lock) } | Select-Object -First 1
        if (-not $next) { break }
        [void]$pending.Remove($next)
        if ($next.lock) { $heldLocks[$next.lock] = $true }
        Start-Phase $next
        $running.Add($next)
    }
    Start-Sleep -Milliseconds 250
    foreach ($job in @($running)) {
        if (-not $job.process.HasExited) {
            if ($job.timer.Elapsed.TotalSeconds -le $job.timeout) { continue }
            $job.process.Kill(); $job.timedOut = $true
        }
        $job.process.WaitForExit()
        $result = Complete-Phase $job
        if ($null -eq $result) { continue }
        [void]$running.Remove($job)
        if ($job.lock) { $heldLocks.Remove($job.lock) }
        $finished += $job
        if (-not $job.passed) {
            $why = if ($job.timedOut) { "timed out after $($job.timeout)s" } else { "exit $($job.exit), $($job.seconds)s" }
            if ($job.scriptErrors -gt 0) { $why += ", script errors: $($job.scriptErrors)" }
            Write-Output "FAIL $($job.test) ($why)"
            if ($job.failure) { Write-Output $job.failure }
        } elseif ($ShowPasses) { Write-Output "PASS $($job.test) ($($job.seconds)s)" }
    }
}

$results = @($finished | ForEach-Object { [ordered]@{test=$_.test;passed=$_.passed;exit=$_.exit;seconds=$_.seconds;timeout=$_.timedOut;scriptErrors=$_.scriptErrors} })
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LogDirectory 'results.json')
$failed = @($finished | Where-Object { -not $_.passed })
Write-Output ('{0}/{1} passed in {2}s ({3} parallel)' -f ($finished.Count - $failed.Count), $finished.Count, [math]::Round($clock.Elapsed.TotalSeconds), $Parallel)

if ($git) {
    $gitAfter = @(& git -C $projectRoot status --porcelain)
    $touched = @($gitAfter | Where-Object { $gitBefore -notcontains $_ })
    if ($touched.Count -gt 0) { Write-Output 'WARNING: the run changed tracked files:'; $touched | ForEach-Object { Write-Output "    $_" } }
}

if ($failed.Count -eq 0 -and -not $KeepOutput) {
    # Remove profiles and the review folders tests created in tmp/; leave folders that existed before.
    foreach ($folder in $profileRuns | Select-Object -Unique) { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }
    Get-ChildItem -LiteralPath $tmpRoot -Directory | Where-Object { $tmpBefore -notcontains $_.Name } | Remove-Item -Recurse -Force
} else {
    Write-Output ('Logs: ' + $LogDirectory)
}
if ($failed.Count -gt 0 -or $lintFailed) { exit 1 }
exit 0
