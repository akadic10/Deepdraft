param([string]$Scene = 'res://tools/furniture_art/review.tscn', [string]$Script = '', [string]$Label = 'review', [string]$Profile = '', [string]$Output = 'tmp/furniture_faceted_20261013', [string[]]$UserArguments = @())
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputRoot = Join-Path $projectRoot $Output
New-Item -ItemType Directory -Force $outputRoot | Out-Null
$runArgs = @('--path',('"'+$projectRoot+'"'),'--resolution','1600x1000','--audio-driver','Dummy')
if ($Script) { $runArgs += @('--script',$Script) } else { $runArgs += @($Scene,'--','--capture') }
if ($UserArguments.Count -gt 0) { if ($Script) { $runArgs += '--' }; $runArgs += $UserArguments }
$originalAppData = $env:APPDATA
try {
    if ($Profile) { $env:APPDATA = Join-Path $outputRoot $Profile }
    $runProcess = Start-Process -FilePath 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -ArgumentList $runArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputRoot ($Label+'.out')) -RedirectStandardError (Join-Path $outputRoot ($Label+'.err'))
    $null = $runProcess.Handle
} finally { $env:APPDATA = $originalAppData }
$timer = [Diagnostics.Stopwatch]::StartNew()
while (-not $runProcess.WaitForExit(1000)) {
    if ($timer.Elapsed.TotalSeconds -gt 180) { Stop-Process -Id $runProcess.Id; throw 'Native review timed out' }
}
Get-Content (Join-Path $outputRoot ($Label+'.out')) -Tail 3
Get-Content (Join-Path $outputRoot ($Label+'.err')) -Tail 16
if ($runProcess.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $outputRoot ($Label+'.err')) -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)) { exit 1 }
exit 0
