extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var scene=load("res://tools/voxel_assets/OrganicLogCapture.gd").new()
	root.add_child(scene);current_scene=scene
