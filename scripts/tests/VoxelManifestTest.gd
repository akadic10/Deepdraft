extends SceneTree

## Exhaustive native-import contracts for every currently migrated manifest.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var failures: Array[String] = []
var checks := 0
var count := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): only=arg.trim_prefix("--family=")
	for file in DirAccess.get_files_at("res://data/art/voxel_manifests"):
		if not file.ends_with(".json") or not only.is_empty() and file.get_basename()!=only: continue
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/voxel_manifests/"+file))
		for asset: Dictionary in manifest.assets:
			var path: String = "res://"+asset.path
			_expect(FileAccess.get_sha256(path)==asset.sha256,path+": manifest hash")
			var packed := load(path) as PackedScene
			_expect(packed!=null,path+": imported PackedScene")
			if packed==null: continue
			var model := packed.instantiate() as Node3D
			count+=1
			_expect(model.transform.is_equal_approx(Transform3D.IDENTITY),path+": unit root")
			var expected_pairs := 0
			for part: Dictionary in asset.parts:
				if part.shadow!=null: expected_pairs+=1
			_expect(Shadows.configure(model)==expected_pairs,path+": paired nodes survive native import")
			_expect(Shadows.visual_meshes(model).size()==asset.parts.size(),path+": visual part count")
			for mesh in Shadows.visual_meshes(model):
				_expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),path+": unit part transform")
				_expect(mesh.mesh.get_surface_count()==1,path+": one palette surface")
				var proxy := Shadows.proxy_for_visual(mesh)
				if proxy!=null:
					_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,path+": visual casting off")
					_expect(proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,path+": proxy only casts")
					_expect(mesh.get_aabb().grow(.002).encloses(proxy.get_aabb()),path+": proxy stays within visual bounds")
				else:
					_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,path+": authored noncasting part")
				var arrays := mesh.mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var off_grid := false
				for vertex in vertices:
					for axis in range(3):
						if not is_finite(vertex[axis]) or absf(vertex[axis]*16-roundf(vertex[axis]*16))>.02: off_grid=true
				_expect(not off_grid,path+": 1:16 positions within import quantization tolerance")
			model.free()
	_expect(count>0,"at least one selected family")
	for message in failures: push_error(message)
	print("VOXEL_MANIFEST_PASS " if failures.is_empty() else "VOXEL_MANIFEST_FAIL ",checks," checks; ",count," models")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
