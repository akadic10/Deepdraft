param([ValidatePattern('^[a-z0-9_]+$')][string]$Label = 'fixed', [switch]$Before)
$ErrorActionPreference = 'Stop'
$shoreRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$shoreOutput = Join-Path $shoreRoot ('tmp/shoreline_art_20261013/'+$Label)
New-Item -ItemType Directory -Force $shoreOutput | Out-Null
$shoreAppData = $env:APPDATA
$shoreArgs = @('--path',('"'+$shoreRoot+'"'),'--script','res://tools/terrain_art/CaptureShoreline.gd','--',('--output=res://tmp/shoreline_art_20261013/'+$Label))
if ($Before) { $shoreArgs += '--before' }
try {
    $env:APPDATA = Join-Path $shoreOutput 'profile'
    $shoreProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $shoreArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $shoreOutput 'run.out') -RedirectStandardError (Join-Path $shoreOutput 'run.err') -PassThru
    $null = $shoreProcess.Handle
} finally { $env:APPDATA = $shoreAppData }
$shoreProcess.WaitForExit()
Get-Content (Join-Path $shoreOutput 'run.err')
Get-Content (Join-Path $shoreOutput 'run.out') -Tail 3
if ($shoreProcess.ExitCode -ne 0) { exit $shoreProcess.ExitCode }
if (-not (Select-String -LiteralPath (Join-Path $shoreOutput 'run.out') -Pattern '^SHORELINE_CAPTURE_PASS' -Quiet)) { exit 1 }
