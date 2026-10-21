extends "res://tools/voxel_assets/WorldBenchmark.gd"

## Recovery GLBs imported by the same native pipeline, used only in this
## isolated benchmark process. Strong references keep cache overrides alive.
var _baseline_scenes: Array[PackedScene] = []

func _run() -> void:
	var index: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/studies/voxel_migration_baseline/paths.json"))
	for path: String in index:
		var packed := load("res://assets/models/studies/voxel_migration_baseline/"+path) as PackedScene
		assert(packed!=null,path)
		packed.take_over_path("res://"+path)
		_baseline_scenes.append(packed)
	await super._run()
