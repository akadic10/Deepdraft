extends SceneTree

## The ambience scan looks for water around the camera every 0.75 s. It must
## only ask the solver about columns that have held water: a first spans()
## lookup per dry column made panning onto new ground stall up to 79 ms.
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	var generator = root.get_node("WorldGenerator")
	generator.heightmap.resize(1024*1024)
	generator.heightmap.fill(100)
	generator._maps_ready = true
	var water = root.get_node("WaterManager")
	var asked: Dictionary = {}
	var pool := Vector2i(500,500)
	var flow = preload("res://scripts/components/WaterFlow.gd").new()
	flow.spans_at = func(col: Vector2i) -> Array:
		asked[col] = true
		return [Vector2i(101,128)] if col == pool else []
	flow.seed_column(Vector3i(pool.x,101,pool.y),1.0)
	water.flow = flow
	water.initialized = true
	water.water_columns = {pool: true}
	var sources = load("res://scripts/components/EnvironmentSoundSources.gd").new()
	sources.scan(Vector3(500.5,101.5,500.5),127,18,null,null)
	check(asked.keys() == [pool],"the scan should ask only about the wet column, asked %d columns" % asked.size())
	water.initialized = false
	water.water_columns = {}
	generator._maps_ready = false
	for failure: String in failures: push_error(failure)
	print("AMBIENT_WATER_SCAN_OK" if failures.is_empty() else "AMBIENT_WATER_SCAN_FAIL")
	quit(0 if failures.is_empty() else 1)
