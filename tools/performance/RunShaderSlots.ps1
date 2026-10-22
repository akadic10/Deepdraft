param(
    [string]$SavePath = '',
    [string]$Label = '',
    [switch]$Mining,
    [string]$Godot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
# Runs ShaderSlotReview.gd headless against a COPY of a save, in a throwaway profile
# under tmp/shader_slots/<Label>/. The source save is only read; Godot never opens the
# real profile. Default source: the player's quicksave. -Mining also times mined blocks.
$ErrorActionPreference = 'Stop'
if (-not $Label) { $Label = Get-Date -Format 'yyyyMMdd_HHmmss' }
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid run label' }
if (-not $SavePath) { $SavePath = Join-Path $env:APPDATA 'Godot/app_userdata/Deepdraft/saves/quicksave.json' }
$SavePath = (Resolve-Path -LiteralPath $SavePath).Path
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out = Join-Path $root ('tmp/shader_slots/' + $Label)
if (Test-Path -LiteralPath $out) { throw 'Use a new label to keep earlier results' }
New-Item -ItemType Directory -Force (Join-Path $out 'source') | Out-Null
Copy-Item -LiteralPath $SavePath -Destination (Join-Path $out 'source/quicksave.json')
$godotArgs = @('--headless', '--path', ('"' + $root + '"'), '--script', 'res://tools/performance/ShaderSlotReview.gd', '--',
    ('--source=res://tmp/shader_slots/' + $Label + '/source/quicksave.json'), ('--output=res://tmp/shader_slots/' + $Label))
if ($Mining) { $godotArgs += '--mining' }
$roaming = $env:APPDATA
$local = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $out 'profile'
    $env:LOCALAPPDATA = Join-Path $out 'local'
    $process = Start-Process -FilePath $Godot -ArgumentList $godotArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $out 'run.out') -RedirectStandardError (Join-Path $out 'run.err')
    $null = $process.Handle  # Windows PowerShell 5.1 loses ExitCode unless the handle is cached now
    $process.WaitForExit()
    Write-Output ("exit " + $process.ExitCode + "; report: " + (Join-Path $out 'report.json'))
} finally {
    $env:APPDATA = $roaming
    $env:LOCALAPPDATA = $local
}
