extends SceneTree

## Input changes replace immutable overview snapshots only between batches.
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	var world = root.get_node("WorldData")
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var cell := Vector3i(40,20,40)
	var cells: Array[Vector3i] = [cell]
	renderer.add_visual_cut_blocks(cells)
	renderer.tiles._refresh_overview_snapshots()
	var cut: Dictionary = renderer.tiles._ovt_cut
	var mined: Dictionary = renderer.tiles._ovt_mined
	renderer.tiles._refresh_overview_snapshots()
	_expect(is_same(cut,renderer.tiles._ovt_cut) and is_same(mined,renderer.tiles._ovt_mined), "unchanged batches reuse both dictionary instances")
	renderer.tiles.ovt_building = true
	world.get_chunk(2,1,2)
	world.set_block(cell.x,cell.y,cell.z,root.get_node("BlockRegistry").AIR_ID) # WorldData records the removal
	renderer.add_mined_blocks(cells)
	_expect(is_same(mined,renderer.tiles._ovt_mined) and not mined.has(cell), "in-flight readers retain the old snapshot after mining")
	renderer.tiles.ovt_building = false
	renderer.tiles._refresh_overview_snapshots()
	_expect(renderer.tiles._ovt_mined.has(cell) and not is_same(mined,renderer.tiles._ovt_mined), "next batch sees designation becoming mined air")
	var cave := Vector3i(41,20,40)
	cells = [cave]
	renderer.set_debug_cave_blocks(cells)
	renderer.tiles._refresh_overview_snapshots()
	_expect(renderer.tiles._ovt_mined.has(cave), "debug cave preview is included")
	renderer.add_discovered_cave_blocks(cells)
	renderer.clear_debug_cave_blocks()
	renderer.tiles._refresh_overview_snapshots()
	_expect(renderer.tiles._ovt_mined.has(cave), "discovery survives preview removal")
	var planned := Vector3i(42,20,40)
	cells = [planned]
	renderer.add_visual_cut_blocks(cells)
	renderer.tiles._refresh_overview_snapshots()
	renderer.remove_visual_cut_blocks(cells)
	renderer.tiles._refresh_overview_snapshots()
	_expect(not renderer.tiles._ovt_cut.has(planned), "cancelled designation leaves the snapshot")
	world.get_chunk(2,1,2)
	world.block_changed.connect(renderer._terrain_block_changed)
	world.set_block(planned.x,planned.y,planned.z,root.get_node("BlockRegistry").get_id("base:construction:floor:stone"))
	renderer._flush_terrain_changes()
	renderer.tiles._refresh_overview_snapshots()
	_expect(renderer.tiles._ovt_mined.has(planned) and renderer.tiles._ovt_cut.has(planned), "solid terrain overrides invalidate snapshots")
	cut = renderer.tiles._ovt_cut
	renderer.tiles.invalidate_global()
	renderer.tiles._refresh_overview_snapshots()
	_expect(not is_same(cut,renderer.tiles._ovt_cut), "global resets rebuild the snapshot")
	renderer.free()
	for failure in failures: push_error(failure)
	print("OVERVIEW_SNAPSHOT_OK" if failures.is_empty() else "OVERVIEW_SNAPSHOT_FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
