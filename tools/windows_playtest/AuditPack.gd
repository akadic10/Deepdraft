extends SceneTree

## Run with the editor executable --main-pack <export.pck> --script <this file>.
## This checks the actual packed imports, not the workspace's cached models.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var checked := {}
	var failed: Array[String] = []
	for file in DirAccess.get_files_at("res://assets/models/furniture"):
		var asset: String = file.trim_suffix(".import").trim_suffix(".remap")
		if not asset.ends_with(".glb") or checked.has(asset): continue
		var path := "res://assets/models/furniture/" + asset
		var packed := load(path) as PackedScene
		if packed == null:
			failed.append(path)
			continue
		var model := packed.instantiate()
		if model == null: failed.append(path)
		else: model.free()
		checked[asset] = true
	for door in ["door.glb", "log_door_3.glb", "log_door_4.glb"]:
		if not checked.has(door): failed.append("Missing door: " + door)
	if checked.size() < 41: failed.append("Expected at least 41 furniture models")
	if not failed.is_empty(): push_error(str(failed))
	print("PACKED_FURNITURE_AUDIT: ", checked.size(), " models, ", "PASS" if failed.is_empty() else failed)
	quit(0 if failed.is_empty() else 1)
