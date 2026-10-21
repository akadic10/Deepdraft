extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewer = load("res://tools/hand_hewn_study/Viewer.gd").new()
	root.add_child(viewer)
	current_scene=viewer
