extends SceneTree
## Directly exercise the coordinator's teardown join with an owned transaction.
func _init() -> void: _run.call_deferred()
func _run() -> void:
	if not "/autosave_20261015/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Shutdown fixture requires isolated profile"); quit(2); return
	var saves=root.get_node("SaveManager")
	if not saves.configure_storage_for_testing("user://shutdown_save"):
		quit(2); return
	var state=JSON.parse_string(FileAccess.get_file_as_string("res://tmp/autosave_20261015/input_quicksave.json"))
	if not state is Dictionary: quit(2); return
	saves._save_job=saves._file_store()
	saves._save_job.paths=saves._absolute_paths(saves._quick_save_paths())
	saves._save_job.snapshot=state
	saves._save_task=WorkerThreadPool.add_task(saves._save_job.run,false,"Shutdown save fixture")
	print("SAVE_SHUTDOWN_JOIN_REQUESTED")
	quit()
