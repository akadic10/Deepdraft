extends SceneTree

## Exercise real worker completion, concurrent edits, concealment and teardown.
class Terrain extends Node3D:
	var slice_y := 127
	var revealed := true
	func is_revealed_air(_cell: Vector3i) -> bool: return revealed

var failures: Array[String] = []
var view: Node3D
var owner: Node
var generator: Node

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not view._pending.is_empty() or not view._jobs.is_empty() or not owner.dirty_tiles.is_empty():
		view._drain_mesh_work()
		check(view._jobs.size()<=2,"Worker concurrency exceeded the configured limit")
		if Time.get_ticks_msec() > deadline:
			check(false,"Water presentation queue did not drain")
			break
		await process_frame

func top_y(tile: Vector2i) -> float:
	var mesh: ArrayMesh = view._tiles[tile].mesh
	if mesh == null: return -1.0
	var top := -1.0
	for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: top = maxf(top,vertex.y)
	return top

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	generator = root.get_node("WorldGenerator")
	generator.water_profile = generator.load_water_profile()
	generator.heightmap.resize(1024*1024)
	generator.heightmap.fill(100)
	generator._maps_ready = true
	owner = root.get_node("WaterManager")
	owner.dirty_tiles.clear()
	var flow = preload("res://scripts/components/WaterFlow.gd").new()
	flow.spans_at = func(p: Vector2i) -> Array: return [Vector2i(120,128)] if p in [Vector2i(31,8),Vector2i(32,8)] else []
	var left := Vector3i(31,120,8)
	var right := Vector3i(32,120,8)
	flow.seed_column(left,0.75)
	flow.seed_column(right,0.75)
	owner.flow = flow
	view = load("res://scripts/components/WaterRenderer.gd").new()
	view.terrain = Terrain.new()
	view._invalidate_view()
	await settle()
	check(is_equal_approx(top_y(Vector2i.ZERO),120.75),"Initial queued water geometry missing")
	var previous_mesh = view._tiles[Vector2i.ZERO].mesh
	flow.mass[left] = 500000
	for _i in 100: view._queue_tile(Vector2i.ZERO)
	check(view._pending.size()==1,"Repeated invalidations did not coalesce")
	view._drain_mesh_work()
	check(view._tiles[Vector2i.ZERO].mesh==previous_mesh,"Dispatch replaced the mesh before worker completion")
	check(not view._jobs.is_empty(),"No asynchronous geometry job was dispatched")
	# A later simulation tick must neither mutate this snapshot nor disappear.
	flow.mass[left] = 250000
	owner.dirty_tiles[Vector2i.ZERO] = true
	check(view._jobs[0].builder.snapshot.mass[left]==500000,"Worker snapshot shares live mass")
	flow._spans[Vector2i(31,8)].clear()
	check(view._jobs[0].builder.snapshot.spans[Vector2i(31,8)].size()==1,"Worker snapshot shares live topology arrays")
	flow._spans[Vector2i(31,8)] = [Vector2i(120,128)]
	var authoritative: Dictionary = flow.serialize()
	var mass_before: Dictionary = flow.mass.duplicate()
	await settle()
	check(is_equal_approx(top_y(Vector2i.ZERO),120.25),"Change made during a build was lost")
	check(flow.serialize()==authoritative and flow.mass==mass_before,"Presentation changed authoritative water")
	previous_mesh = view._tiles[Vector2i.ZERO].mesh
	view._queue_tile(Vector2i.ZERO)
	await settle()
	check(view._tiles[Vector2i.ZERO].mesh==previous_mesh and view._unchanged>0,"Unchanged inputs caused a redundant GPU mesh replacement")
	# A slice change during a build must hide old water immediately and reject the result.
	flow.mass[left] = 600000
	view._queue_tile(Vector2i.ZERO)
	view._drain_mesh_work()
	view.terrain.slice_y = 119
	view._invalidate_view()
	check(not view._tiles[Vector2i.ZERO].visible,"Old slice remained visible during asynchronous rebuild")
	await settle()
	check(top_y(Vector2i.ZERO)<0 and view._stale>0,"Old-slice worker result was published")
	view.terrain.slice_y = 127
	generator.heightmap.fill(127)
	view.terrain.revealed = false
	view._invalidate_view()
	await settle()
	check(top_y(Vector2i.ZERO)<0 and top_y(Vector2i(1,0))<0,"Undiscovered underground water was exposed")
	var builds_before: int = view._built
	flow.mass[left] = 650000
	view._queue_tile(Vector2i.ZERO)
	await settle()
	check(view._built==builds_before,"Hidden-only water changes rebuilt empty geometry")
	flow.mass[left] = 600000
	view.terrain.revealed = true
	view._invalidate_view()
	await settle()
	check(is_equal_approx(top_y(Vector2i.ZERO),120.6),"Discovered cave water was not restored")
	# World/load revision changes invalidate already-dispatched geometry too.
	flow.mass[left] = 700000
	view._queue_tile(Vector2i.ZERO)
	view._drain_mesh_work()
	owner.revision += 1
	flow.mass[left] = 0
	flow.mass[right] = 0
	view._invalidate_view()
	await settle()
	check(top_y(Vector2i.ZERO)<0 and top_y(Vector2i(1,0))<0,"Reload/drain left obsolete water meshes")
	# Nearby tiles win normally; old remote work still gets a scheduling turn.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(32,150,40)
	camera.look_at(Vector3(32,120,8))
	camera.make_current()
	view._queue_tile(Vector2i(25,25))
	view._queue_tile(Vector2i.ZERO)
	view._dispatch_count = 0
	check(view._next_tile(camera)==Vector2i.ZERO,"Nearby water was not prioritized")
	view._dispatch_count = 7
	check(view._next_tile(camera)==Vector2i(25,25),"Distant dirty water can starve")
	view._pending.clear()
	flow.mass[left] = 1000000
	view._queue_tile(Vector2i.ZERO)
	view._drain_mesh_work()
	view.terrain.free()
	view._exit_tree() # Detached fixture invokes the real teardown hook explicitly.
	check(view._jobs.is_empty(),"Teardown left worker tasks unjoined")
	view.free()
	camera.free()
	generator._maps_ready = false
	print("WaterMeshSchedulingTest: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
