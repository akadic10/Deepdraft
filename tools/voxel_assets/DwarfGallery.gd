extends SceneTree

## Assemble staged modular GLBs through the real registry and actor in an
## isolated process. Production registry files remain untouched by this review.
func _init() -> void: _run.call_deferred()

func _packed(path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(path,state)==OK,"staged import "+path)
	var model := document.generate_scene(state)
	var packed := PackedScene.new()
	assert(packed.pack(model)==OK,"staged packing "+path)
	model.free()
	return packed

func _run() -> void:
	var output := "res://tmp/settlement_art_20261013/dwarves_roster_gallery/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	var registry := root.get_node("DwarfAssets")
	if not "--production" in OS.get_cmdline_user_args():
		for table_name in ["heads","hair_male","hair_female","beards","brows_male","brows_female","scars"]:
			var table: Dictionary=registry.get(table_name).duplicate()
			for key in table:
				if table[key]!=null: table[key]=_packed(String(table[key].resource_path).replace("res://","res://tmp/voxel_migration_20261018/staged/"))
			registry.set(table_name,table)
		for key in ["eyes","body","hand","foot","felling_axe","mining_pickaxe"]:
			registry.set(key,_packed(String(registry.get(key).resource_path).replace("res://","res://tmp/voxel_migration_20261018/staged/")))
		var proportions: Dictionary=registry.get_proportions().duplicate()
		proportions.body_width=1.0; proportions.head_width=1.0
		registry.set("_proportions",proportions)
	var capture=load("res://tools/voxel_assets/VoxelRosterCapture.gd").new()
	capture.output=output
	root.add_child(capture)
	current_scene=capture
