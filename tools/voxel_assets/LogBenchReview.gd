extends SceneTree

## Optional staged GLB override is process-local; production files are untouched.
var staged_model: PackedScene

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--bench-model="): continue
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(arg.trim_prefix("--bench-model="),state)==OK)
		var model := document.generate_scene(state)
		staged_model = PackedScene.new()
		assert(staged_model.pack(model)==OK)
		staged_model.take_over_path("res://assets/models/furniture/bench.glb")
		model.free()
	var stage = load("res://tools/voxel_assets/LogBenchCapture.gd").new()
	root.add_child(stage)
	current_scene = stage
