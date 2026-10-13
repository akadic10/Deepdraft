param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$studyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$studyOutput = Join-Path $studyRoot 'tmp/visual_study_20261012'
New-Item -ItemType Directory -Force $studyOutput | Out-Null
$studyGodot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
if (-not (Test-Path -LiteralPath $studyGodot)) {
    $studyGodot = (Get-Command godot -ErrorAction Stop).Source
}
$studyArguments = @('--path', ('"' + $studyRoot + '"'))
if ($Capture) {
    $studyArguments += @('--script', 'res://tools/visual_study/CaptureStudy.gd')
} else {
    $studyArguments += @('res://scenes/studies/visual_study.tscn', '--resolution', '1600x1000')
}
# Dedicated user-data profile, inherited only by this new Godot process.
$studyAppData = $env:APPDATA
$studyLogName = if ($Capture) { 'run' } else { 'interactive' }
$studyStdout = Join-Path $studyOutput ($studyLogName + '.out')
$studyStderr = Join-Path $studyOutput ($studyLogName + '.err')
try {
    $env:APPDATA = Join-Path $studyOutput 'profile'
    # Captures are unattended; the player-launched study must be visible.
    $studyWindowStyle = if ($Capture) { 'Hidden' } else { 'Normal' }
    $studyProcess = Start-Process -FilePath $studyGodot -ArgumentList $studyArguments -WindowStyle $studyWindowStyle -RedirectStandardOutput $studyStdout -RedirectStandardError $studyStderr -PassThru
} finally {
    $env:APPDATA = $studyAppData
}
if ($Capture) {
    $studyProcess.WaitForExit()
    Get-Content -LiteralPath $studyStderr -Encoding UTF8
    Get-Content -LiteralPath $studyStdout -Encoding UTF8 -Tail 3
    if (Select-String -LiteralPath $studyStderr -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { exit 1 }
    if (-not (Select-String -LiteralPath $studyStdout -Pattern '^VISUAL_STUDY_OK' -Quiet)) { exit 1 }
    exit $studyProcess.ExitCode
}
# Report success only once the actual study, rather than merely its process,
# has started. Leave a slow but live process running for diagnosis on timeout.
$studyDeadline = [DateTime]::UtcNow.AddSeconds(45)
while ([DateTime]::UtcNow -lt $studyDeadline) {
    $studyProcess.Refresh()
    if ($studyProcess.HasExited) {
        Get-Content -LiteralPath $studyStderr -Encoding UTF8
        throw 'The visual study closed during startup. See tmp/visual_study_20261012/interactive.err.'
    }
    if (Select-String -LiteralPath $studyStderr -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) {
        Get-Content -LiteralPath $studyStderr -Encoding UTF8
        throw 'The visual study reported a startup error.'
    }
    if (Select-String -LiteralPath $studyStdout -Pattern '^VISUAL_STUDY_READY:' -Quiet) {
        Write-Output "Visual study ready (process $($studyProcess.Id)). Close its window or press Esc to exit."
        exit 0
    }
    Start-Sleep -Milliseconds 200
}
throw 'The visual study is still starting. See tmp/visual_study_20261012/interactive.out.'
