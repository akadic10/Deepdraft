param(
    [string]$GodotPath = 'S:/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path
$buildRoot = Join-Path $projectRoot 'build'
# A running Godot game reads its PCK lazily. Replacing that file corrupts the
# running session's resource offsets even when the EXE itself is unchanged.
# Never reuse a playable directory, including when two exports start together.
$buildId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$packageRoot = Join-Path $buildRoot ('windows/releases/' + $buildId + '/Deepdraft')
$archivePath = Join-Path $buildRoot 'windows/Deepdraft-Windows-Playtest.zip'
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $buildRoot '.gdignore') | Out-Null
$exportOut = Join-Path (Split-Path $packageRoot) 'export.out.log'
$exportErr = Join-Path (Split-Path $packageRoot) 'export.err.log'
$exePath = Join-Path $packageRoot 'Deepdraft.exe'
$exportArgs = @('--headless', '--path', ('"' + $projectRoot + '"'),
    '--export-release', '"Windows Desktop"', ('"' + $exePath + '"'))
$engine = Start-Process -FilePath $enginePath -ArgumentList $exportArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $exportOut -RedirectStandardError $exportErr
$timer = [Diagnostics.Stopwatch]::StartNew()
while (-not $engine.WaitForExit(1000)) {
    if ($timer.Elapsed.TotalSeconds -gt 240) {
        $engine.Kill()
        throw "Export timed out. See $exportErr"
    }
}
if ($engine.ExitCode -ne 0) { throw "Export failed ($($engine.ExitCode)). See $exportErr" }
$diagnostics = Get-Content -LiteralPath $exportErr -Raw
if ($diagnostics -match '(?m)^(ERROR|SCRIPT ERROR):') { throw "Export reported errors. See $exportErr" }

# Check every runtime JSON definition, including nested directories. Godot does
# not include raw JSON through resource dependencies alone.
$exportLog = Get-Content -LiteralPath $exportOut -Raw
foreach ($definition in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data') -Filter '*.json' -Recurse -File) {
    $resourcePath = 'res://' + $definition.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    if (-not $exportLog.Contains('Storing File: ' + $resourcePath)) { throw "Missing packed definition: $resourcePath" }
}
if ($exportLog -match 'Storing File: res://(docs|tools|tmp|_to_delete|scripts/tests|scenes/studies)/') {
    throw 'Development files leaked into the export; inspect export_presets.cfg.'
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') -Destination $packageRoot -Force
# Package only the game files, never stale test saves, diagnostics or screenshots.
$packageFiles = @('Deepdraft.exe', 'Deepdraft.console.exe', 'Deepdraft.pck', 'README.txt') |
    ForEach-Object { Join-Path $packageRoot $_ }
foreach ($file in $packageFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing release file: $file" }
}
$dependencies = @(Get-ChildItem -LiteralPath $packageRoot -Filter '*.dll' -File)
if ($dependencies.Count -gt 0) { $packageFiles += $dependencies.FullName }
Compress-Archive -LiteralPath $packageFiles -DestinationPath $archivePath -Force
Write-Output ('Play this build: ' + $exePath)
Write-Output ('Created {0} ({1:N1} MiB)' -f $archivePath, ((Get-Item -LiteralPath $archivePath).Length / 1MB))
Write-Output ('SHA256 ' + (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash)
