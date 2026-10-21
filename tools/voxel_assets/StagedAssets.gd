extends RefCounted

## Isolated review/tests only. Strong references retain replacement scenes;
## source files and the editor import cache stay unchanged.
static func install(family: String) -> Array[PackedScene]:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tmp/voxel_migration_20261018/staged/"+family+".json"))
	var scenes: Array[PackedScene]=[]
	for asset: Dictionary in manifest.assets:
		var doc:=GLTFDocument.new(); var state:=GLTFState.new()
		assert(doc.append_from_file("res://tmp/voxel_migration_20261018/staged/"+asset.path,state)==OK)
		var model:=doc.generate_scene(state); var packed:=PackedScene.new()
		assert(packed.pack(model)==OK)
		packed.take_over_path("res://"+asset.path)
		scenes.append(packed); model.free()
	return scenes
