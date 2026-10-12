param([ValidateSet('import-review','import-game','preview','thumbnail','verify')][string]$Mode)
$reviewRoot = 'P:\Deepdraft\tmp\rudimentary_hearth_20261011'
$env:APPDATA = "$reviewRoot\profile"
$engineArgs = switch ($Mode) {
  'import-review' { @('--headless','--editor','--path',$reviewRoot,'--import') }
  'import-game' { @('--headless','--editor','--path','P:/Deepdraft','--import') }
  'preview' { @('--path',$reviewRoot,'--resolution','1600x1000','--','--capture') }
  'thumbnail' { @('--path','P:/Deepdraft','--script','res://tools/FurnitureCatalogThumbnails.gd','--','--only=hearth') }
  'verify' { @('--headless','--path','P:/Deepdraft','--script','res://tools/VerifyHearthAnimation.gd') }
}
$reviewProcess = Start-Process -FilePath 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' -ArgumentList $engineArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput "$reviewRoot\$Mode.out" -RedirectStandardError "$reviewRoot\$Mode.err"
if (-not $reviewProcess.WaitForExit(120000)) { Stop-Process -Id $reviewProcess.Id; throw "$Mode timed out" }
Write-Output "$Mode exit=$($reviewProcess.ExitCode)"
Get-Content "$reviewRoot\$Mode.err" -Tail 25
Get-Content "$reviewRoot\$Mode.out" -Tail 10
