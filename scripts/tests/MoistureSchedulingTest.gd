extends SceneTree

class Terrain:
	extends Node3D
	signal visible_volume_changed
	var slice_y := 127
	var underground_lighting: Node
	var revealed := true
	func is_revealed_air(_cell: Vector3i) -> bool: return revealed

var failures: Array[String] = []
var checks := 0
var view: Node3D
var terrain: Terrain
var water: Node
var gen: Node
var world: Node
var grass := 0

func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Moisture scheduling timeout"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	water = root.get_node("WaterManager")
	water.set_process(false)
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_col: Vector2i) -> Array: return [Vector2i(11,128)]
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water.initialized = true
	gen = root.get_node("WorldGenerator")
	gen.heightmap.resize(1024*1024)
	gen.heightmap.fill(10)
	gen._maps_ready = true
	gen.water_profile = {"rendering":{"moisture_budget_ms":0.02}}
	world = root.get_node("WorldData")
	grass = root.get_node("BlockRegistry").get_id("base:terrain:surface:grass_01")
	for x in range(64,128):
		for z in range(64,128):
			var cell := Vector3i(x,10,z)
			_ground(cell,grass)
			water.moisture.soils[cell] = {"value":600000,"target":600000,"since":0}
	terrain = Terrain.new()
	root.add_child(terrain)
	terrain.underground_lighting = load("res://scripts/components/UndergroundLighting.gd").new()
	terrain.add_child(terrain.underground_lighting)
	terrain.underground_lighting.set_process(false)
	view = load("res://scripts/components/MoistureRenderer.gd").new()
	view.terrain = terrain
	terrain.add_child(view)
	view.set_process(false)
	var saved: Array = water.moisture.serialize()
	view._process(0)
	check(view.is_updating(),"large initial work yields across frames")
	_drain()
	check(_faces().size()==4096,"all 16 tiles eventually render, including distant tiles")
	check(water.moisture.serialize()==saved,"budgeted drawing does not mutate moisture")
	var built: int = view.get_mesh_stats().built
	view._process(0)
	check(view.get_mesh_stats().built==built,"unchanged input keeps existing meshes")
	# A slice invalidates finished AND partially constructed tiles immediately.
	terrain.visible_volume_changed.emit()
	for i in 10000:
		view._process(0)
		if view._building.x>=0 and view._build_head>0: break
	check(view._building.x>=0,"tiny budget produces a partial tile")
	terrain.slice_y = 9
	terrain.visible_volume_changed.emit()
	check(_faces().is_empty(),"slice conceals all old meshes synchronously")
	_drain()
	check(_faces().is_empty(),"partial old tile cannot return above the slice")
	terrain.slice_y = 127
	terrain.visible_volume_changed.emit()
	_drain()
	check(_faces().size()==4096,"reveal restores all current tiles")
	# Exact soil notifications discover candidates added after initial indexing.
	var added := Vector3i(130,10,70)
	_ground(added,grass)
	water.moisture.set_source(Vector3i(131,11,70),{added:1000000},water.elapsed_usec)
	water.elapsed_usec += 120000000
	_drain()
	check(_faces().has(added),"new irrigated soil is discovered without a full scan")
	water.moisture.set_source(Vector3i(131,11,70),{},water.elapsed_usec)
	water.elapsed_usec += 1440000000
	_drain()
	check(not _faces().has(added),"drying removes its overlay")
	water.show_moisture = true
	_drain()
	check(_faces().has(added),"debug coverage retains tracked dry soil")
	water.show_moisture = false
	# Films exist independently of the irrigation dictionary.
	var film := Vector3i(140,10,70)
	_ground(film,grass)
	water.flow.mass[film+Vector3i.UP] = 30000
	water.surface_changed.emit([film+Vector3i.UP])
	_drain()
	check(_faces().has(film),"new surface film renders damp ground")
	water.flow.mass[film+Vector3i.UP] = 500000
	water.surface_changed.emit([film+Vector3i.UP])
	_drain()
	check(not _faces().has(film),"standing water replaces the film overlay")
	water.flow.mass[film+Vector3i.UP] = 30000
	water.surface_changed.emit([film+Vector3i.UP])
	_drain()
	water.flow.mass[film+Vector3i.UP] = 0
	water.surface_changed.emit([film+Vector3i.UP])
	water.show_moisture = true
	_drain()
	check(not _faces().has(film),"removed film leaves no stale debug ground")
	# Terrain invalidation removes a formerly soil-only face while paused.
	var changed := Vector3i(70,10,70)
	var rock: int = root.get_node("BlockRegistry").get_id("base:terrain:rock:rock07")
	_ground(changed,rock)
	view._on_block_changed(changed,grass,rock)
	_drain()
	check(not _faces().has(changed),"terrain edit invalidates its cached overlay")
	# A replacement owner cannot inherit meshes or callbacks from a prior world.
	var old_moisture: RefCounted = water.moisture
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water.flow.mass.clear()
	view._process(0)
	check(_faces().is_empty(),"owner replacement conceals the previous world immediately")
	_drain()
	old_moisture.set_source(Vector3i.ZERO,{added:1000000},water.elapsed_usec)
	check(view._soil_changes.is_empty(),"old owner callbacks are disconnected")
	terrain.free()
	gen._maps_ready = false
	water.reset()
	print("MOISTURE_SCHEDULING_PASS " if failures.is_empty() else "MOISTURE_SCHEDULING_FAIL ",checks)
	quit(0 if failures.is_empty() else 1)

func _ground(cell: Vector3i, id: int) -> void:
	var chunk: Chunk = world.get_chunk(cell.x>>4,cell.y>>4,cell.z>>4)
	chunk.blocks[Chunk.local_index(cell.x&15,cell.y&15,cell.z&15)] = id

func _drain() -> void:
	for i in 100000:
		view._process(0)
		if not view.is_updating(): return
	check(false,"work eventually drains")

func _faces() -> Dictionary:
	var result: Dictionary = {}
	for node: MeshInstance3D in view._nodes.values():
		if not node.visible or node.mesh==null: continue
		var data: Array = node.mesh.surface_get_arrays(0)
		for i in range(0,data[Mesh.ARRAY_VERTEX].size(),4):
			var point: Vector3 = data[Mesh.ARRAY_VERTEX][i]
			result[Vector3i(roundi(point.x),floori(point.y)-1,roundi(point.z))] = data[Mesh.ARRAY_COLOR][i]
	return result
