from pathlib import Path
s=Path('tmp/ladder_extension_20261011/PlayerLadderProbe.gd').read_text(encoding='utf-8')
s=s.replace('DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tmp/ladder_extension_20261011/player_quicksave.json"), ProjectSettings.globalize_path("user://ladder_probe/quicksave.json"))','''# Test-only normalization of the archived fixture's diagnostic schema.
	# The original player's file is opened read-only and never rewritten.
	var fixture := "res://tmp/ladder_extension_20261011/player_quicksave.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save="): fixture = argument.trim_prefix("--save=")
	if not FileAccess.file_exists(fixture): push_error("Supply the archived ladder save with --save=..."); quit(1); return
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not snapshot.scene.has("jobs"):
		snapshot.scene["jobs"] = {"next_order":1,"next_attempt":1,"time":0.0,"records":{},"history":[]}
	var number := 1
	for order: Dictionary in snapshot.scene.worker_crafting.orders:
		if not order.has("id"): order["id"] = number
		number += 1
	var copy := FileAccess.open("user://ladder_probe/quicksave.json",FileAccess.WRITE)
	copy.store_string(JSON.stringify(snapshot))
	copy.close()''')
s=s.replace('print("PLAYER_LADDER_COMPLETE stock="','print("SAVED_LADDER_JOB_OK stock="')
s=s.replace('"worker and assignment disagree"','"worker and assignment disagree"')
# Keep integration output compact while retaining actual runtime checks.
a=s.index('\tfor route: Dictionary in ladders.routes.values():')
b=s.index('\tclock.set_paused(false)',a)
s=s[:a]+s[b:]
a=s.index('\t\tif Time.get_ticks_msec() >= next_debug:')
b=s.index('\t\tvar route:',a)
s=s[:a]+s[b:]
s=s.replace('\tvar next_debug := started\n','')
s=s.replace('\t\t\tprint("SAVED_LADDER_JOB_OK stock="','\t\t\tif not tasks.lifecycle_errors().is_empty(): push_error(str(tasks.lifecycle_errors())); quit(1); return\n\t\t\tprint("SAVED_LADDER_JOB_OK stock="')
Path('scripts/tests/SavedLadderJobTest.gd').write_text(s,encoding='utf-8')
