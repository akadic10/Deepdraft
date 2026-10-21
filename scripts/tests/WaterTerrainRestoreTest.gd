extends SceneTree

## Final terrain installation must preserve saved water and its deterministic
## continuation without simulating the intermediate per-voxel construction.
var failures: Array[String] = []
var notifications := 0
var surface_notifications := 0

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var generator = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	var world = root.get_node("WorldData")
	root.get_node("WorldClock").set_paused(true)
	root.get_node("SaveManager").set_process(false)
	root.get_node("TaskManager").set_process(false)
	water.set_process(false)
	generator.generate(1234)
	while not generator._maps_ready or generator.is_generating(): await process_frame
	water.initialize()
	var initial: Dictionary = water.serialize_state()
	water.levels_changed.connect(func(_cells): notifications += 1)
	water.surface_changed.connect(func(_cells): surface_notifications += 1)
	var dam: Vector3i = water.dev_toggle_dam()
	_expect(dam != Vector3i.ZERO, "live dam fixture exists")
	var lake: Vector2i = generator.lake_center
	var floor_y: int = generator.get_surface_y(lake.x,lake.y)
	var volume: float = water.flow.total_volume()
	for y in range(floor_y-3,floor_y+1): world.set_block(lake.x,y,lake.y,0)
	_expect(water.depth_at(Vector3i(lake.x,floor_y-3,lake.y))>0, "ordinary mining immediately floods a lake breach")
	_expect(absf(water.flow.total_volume()-volume)<0.000001, "live terrain edits conserve water")
	_expect(notifications>0 and surface_notifications>0, "live edits still notify water consumers")
	for _i in 5: water.step(0.1)
	# Include explicit displaced water as well as wet cells and active queues.
	water.flow.pending.append({"point":Vector3i(lake.x,128,lake.y),"units":137})
	var saved: Dictionary = water.serialize_state()
	var terrain := {"edits":world.serialize_edits()}
	for _i in 8: water.step(0.1)
	var future: Dictionary = water.serialize_state()
	for entry: Dictionary in terrain.edits:
		var p: Array = entry.cell
		world.set_block(p[0],p[1],p[2],generator.get_generated_block_id(p[0],p[1],p[2]))
	water.edited_columns.clear()
	water.restore_state(initial)
	var before_bulk: Dictionary = water.flow.serialize()
	notifications = 0
	surface_notifications = 0
	water.begin_terrain_restore()
	world.restore_terrain(terrain)
	_expect(water.flow.serialize()==before_bulk, "bulk terrain does not displace, wake or simulate provisional water")
	_expect(notifications==0 and surface_notifications==0, "bulk terrain emits no intermediate water notifications")
	for entry: Dictionary in terrain.edits:
		_expect(water.edited_columns.has(Vector2i(entry.cell[0],entry.cell[2])), "restored columns use final terrain topology")
	water.restore_state(saved)
	_expect(not water.restoring and notifications==1, "authoritative water completes restore and notifies once")
	_expect(water.serialize_state()==saved, "saved mass, active/displaced queues, moisture and clocks restore exactly")
	_expect(water.depth_at(Vector3i(lake.x,floor_y-3,lake.y))>0, "restored breach has the correct water topology")
	for _i in 8: water.step(0.1)
	_expect(water.serialize_state()==future, "water and moisture continuation matches the original world")
	water.begin_terrain_restore()
	water.reset()
	_expect(not water.restoring, "world reset clears the restore context")
	generator.prepare_for_world_reload()
	for failure in failures: push_error(failure)
	print("WATER_TERRAIN_RESTORE_OK" if failures.is_empty() else "WATER_TERRAIN_RESTORE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
