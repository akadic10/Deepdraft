extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var source: String="FireCapture" if "--fire" in OS.get_cmdline_user_args() else "FurnitureCapture"
	var scene=load("res://tools/voxel_assets/"+source+".gd").new()
	root.add_child(scene)
	current_scene=scene
