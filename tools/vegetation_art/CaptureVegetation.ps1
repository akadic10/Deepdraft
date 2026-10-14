param([string]$Label = 'final', [switch]$Baseline, [switch]$GalleryOnly)
$ErrorActionPreference = 'Stop'
if ($Baseline) { throw 'Legacy model comparisons were retired; use the dated art reports for historical captures.' }
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid capture label' }
$plantRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$plantOutput = Join-Path $plantRoot ('tmp/vegetation_art_20261013/'+$Label)
New-Item -ItemType Directory -Force $plantOutput | Out-Null
$plantAppData = $env:APPDATA
$plantArgs = @('--path',('"'+$plantRoot+'"'),'--script','res://tools/vegetation_art/CaptureVegetation.gd','--',('--output=res://tmp/vegetation_art_20261013/'+$Label))
if ($GalleryOnly) { $plantArgs += '--gallery-only' }
try {
    $env:APPDATA = Join-Path $plantOutput 'profile'
    $plantProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $plantArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $plantOutput 'run.out') -RedirectStandardError (Join-Path $plantOutput 'run.err') -PassThru
    $null = $plantProcess.Handle
} finally { $env:APPDATA = $plantAppData }
$plantProcess.WaitForExit()
Get-Content (Join-Path $plantOutput 'run.err')
Get-Content (Join-Path $plantOutput 'run.out') -Tail 5
if ($plantProcess.ExitCode -ne 0) { exit $plantProcess.ExitCode }
if (-not (Select-String -LiteralPath (Join-Path $plantOutput 'run.out') -Pattern '^VEGETATION_CAPTURE_PASS' -Quiet)) { exit 1 }
