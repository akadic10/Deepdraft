$env:APPDATA = 'P:\Deepdraft\tmp\colony_balance_review_20261011\verify_profile'
$reviewProcess = Start-Process -FilePath 'S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' -ArgumentList @('--headless','--path','P:/Deepdraft','--script','res://tmp/colony_balance_review_20261011/ColonyVerification.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput 'P:\Deepdraft\tmp\colony_balance_review_20261011\verification.out' -RedirectStandardError 'P:\Deepdraft\tmp\colony_balance_review_20261011\verification.err'
if (-not $reviewProcess.WaitForExit(180000)) { Stop-Process -Id $reviewProcess.Id; throw 'Colony verification timeout' }
Get-Content 'P:\Deepdraft\tmp\colony_balance_review_20261011\verification.err' -Tail 12
Get-Content 'P:\Deepdraft\tmp\colony_balance_review_20261011\verification.out' -Tail 2
