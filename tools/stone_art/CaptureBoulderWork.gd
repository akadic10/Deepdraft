extends "res://scripts/tests/BoulderPilotTest.gd"

func _run() -> void:
	if not "/ground_stones_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Stone worker capture requires its isolated profile")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute("res://tmp/ground_stones_20261013/worker")
	await super._run()

func _capture_boulders(_output := "") -> void:
	await super._capture_boulders("res://tmp/ground_stones_20261013/worker/boulder_breaking.png")
