extends SceneTree

## The one terrain raycast (ObjectPicking.terrain_hit), the removed-terrain record
## and the visible-surface rule (WorldData) agree on a small stone floor.
var Picking
var failures: Array[String] = []


func _init() -> void: _run.call_deferred()


func _run() -> void:
	Picking = load("res://scripts/components/ObjectPicking.gd")
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for cx in range(2, 4):
		for cz in range(2, 4):
			for cy in range(2):
				var chunk = load("res://scripts/systems/Chunk.gd").new()
				for ly in range(16):
					if cy * 16 + ly <= 20:
						for lz in range(16):
							for lx in range(16):
								chunk.blocks[lx + 16 * lz + 256 * ly] = stone
				world.submit_chunk(cx, cy, cz, chunk)
	var origin := Vector3(40.5, 60.0, 40.5)
	var hit: Dictionary = Picking.terrain_hit(origin, Vector3.DOWN, world.MAX_Y)
	_expect(_cell(hit) == Vector3i(40, 20, 40) and hit.normal == Vector3i.UP and is_equal_approx(float(hit.distance), 39.0), "a downward ray stops on the floor's top face")
	hit = Picking.terrain_hit(origin, Vector3.DOWN, 10)
	_expect(_cell(hit) == Vector3i(40, 10, 40), "the slice plane hides cells above it")
	_expect(Picking.terrain_hit(origin, Vector3.DOWN, world.MAX_Y, 20.0).is_empty(), "max distance ends the ray")
	_expect(Picking.terrain_hit(Vector3(-5.5, 60, 40.5), Vector3.DOWN, world.MAX_Y).is_empty(), "outside the world nothing is hit")
	var sampled := func(pos: Vector3i) -> int: return blocks.AIR_ID if pos.y >= 15 else stone
	_expect(_cell(Picking.terrain_hit(origin, Vector3.DOWN, world.MAX_Y, 600.0, sampled)) == Vector3i(40, 14, 40), "sample_block replaces the live grid")
	var visible := func(pos: Vector3i, _normal: Vector3i) -> bool: return pos.y <= 12
	_expect(_cell(Picking.terrain_hit(origin, Vector3.DOWN, world.MAX_Y, 600.0, Callable(), visible)) == Vector3i(40, 12, 40), "visible_face skips hidden cells")
	var slanted: Dictionary = Picking.terrain_hit(Vector3(30.2, 30.5, 40.5), Vector3(1, -1, 0).normalized(), world.MAX_Y)
	_expect(_cell(slanted) == Vector3i(39, 20, 40) and slanted.normal == Vector3i.UP, "a slanted ray reports the entering face")

	# The removed-terrain record lives in WorldData only.
	var cell := Vector3i(40, 20, 40)
	_expect(not world.is_removed_terrain(cell) and world.removed_terrain_count() == 0, "untouched terrain is not removed")
	world.set_block(cell.x, cell.y, cell.z, blocks.AIR_ID)
	_expect(world.is_removed_terrain(cell) and world.removed_terrain_count() == 1, "mining records removed terrain")
	_expect(_cell(Picking.terrain_hit(origin, Vector3.DOWN, world.MAX_Y)) == Vector3i(40, 19, 40), "rays pass through removed terrain")
	_expect(world.visible_top_y(40, 40, 20, world.MAX_Y, {}, true) == 19, "the visible surface steps past removed terrain")
	_expect(world.visible_top_y(40, 40, 20, world.MAX_Y, {}) == 20, "removed terrain is opt-in for the surface rule")
	_expect(world.visible_top_y(40, 40, 20, world.MAX_Y, {Vector3i(40, 19, 40): true}, true) == 18, "caller cut cells also step the surface down")
	_expect(world.visible_top_y(40, 40, 20, 5, {}, true) == 5, "the slice plane clamps the surface")
	_expect(world.visible_top_y(40, 40, -1, world.MAX_Y, {}) == -1, "an empty column has no surface")
	world.set_block(cell.x, cell.y, cell.z, stone)
	_expect(not world.is_removed_terrain(cell) and world.removed_terrain_count() == 0, "rebuilding a cell ends its removal")
	_expect(Picking.surface_hit(origin, Vector3.DOWN, 100.0).is_empty(), "the height-field march never hits before maps exist")
	for failure in failures: push_error(failure)
	print("TERRAIN_PICKING_OK" if failures.is_empty() else "TERRAIN_PICKING_FAIL")
	quit(0 if failures.is_empty() else 1)


func _cell(hit: Dictionary) -> Vector3i:
	return Vector3i(-1, -1, -1) if hit.is_empty() else Vector3i(hit.x, hit.y, hit.z)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
