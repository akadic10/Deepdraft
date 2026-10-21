param(
    [string]$Label = 'review',
    [string]$Resolution = '3840x1080',
    [string]$Godot = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
# Runs HearthblockLightingReview.gd against a recovery copy of a player save in a
# throwaway profile under tmp/hearthblock_lighting_20261020/<Label>/profile.
# The real %APPDATA% profile and player saves are never opened.
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid run label' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$out = Join-Path $root ('tmp/hearthblock_lighting_20261020/' + $Label)
New-Item -ItemType Directory -Force $out | Out-Null
$godotArgs = @('--path', ('"' + $root + '"'), '--windowed', '--resolution', $Resolution, '--audio-driver', 'Dummy',
    '--script', 'res://tools/hearthblock/HearthblockLightingReview.gd', '--', ('--output=res://tmp/hearthblock_lighting_20261020/' + $Label))
$roaming = $env:APPDATA
$local = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $out 'profile'
    $env:LOCALAPPDATA = Join-Path $out 'local'
    $process = Start-Process -FilePath $Godot -ArgumentList $godotArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $out 'run.out') -RedirectStandardError (Join-Path $out 'run.err')
    $null = $process.Handle  # Windows PowerShell 5.1 loses ExitCode unless the handle is cached now
    $process.WaitForExit()
    Write-Output ("exit " + $process.ExitCode + "; logs: " + $out)
} finally {
    $env:APPDATA = $roaming
    $env:LOCALAPPDATA = $local
}
