extends "res://scripts/tests/ShrubPlantingAnimationTest.gd"

## Run the real worker handoff/planting fixture with the new packed plant art.
func _run() -> void:
	if not "/vegetation_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Planting capture requires its isolated profile")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute("res://tmp/vegetation_art_20261013/worker")
	await super._run()

func _capture_pose(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/vegetation_art_20261013/worker/"+label+".png")
