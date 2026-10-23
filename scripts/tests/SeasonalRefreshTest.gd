extends "res://scripts/tests/TreeFellingTest.gd"

const Refresh = preload("res://scripts/components/SeasonalRefreshQueue.gd")
var details: Node3D
var checks := 0

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Seasonal refresh timeout"); quit(1))
	_setup_fixture()
	clock_node.set_process(false)
	clock_node.day = 28
	clock_node.hour = 23.99
	clock_node.season = "summer"
	flora._season = "summer"
	flora._ready_to_spawn = true
	flora._pending.clear()
	flora._pending_set.clear()
	var roots: Dictionary = {}
	var occupancy: Dictionary = {}
	for species: String in ["pine", "oak", "apple", "juniper"]:
		for stage: String in ["sapling", "mature", "ancient"]:
			var id := Vector2i(24 + roots.size() % 4 * 22, 24 + roots.size() / 4 * 24)
			var node := _spawn_tree(species, stage, id)
			roots[id] = node
			occupancy[id] = flora._trees[id].occupancy_id
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	for i in 12:
		var id := "flowers:1234:fixture:%d" % i
		details.register_record({"id":id,"definition":"base:detail:flowers","origin":Vector3i(30+i*4,20,110),"variant":i%3,"yaw":i%4,"habitat":"fixture"})
		details._spawn_visual(id)
	details._visual_queue.clear()
	var chop_id: Vector2i = roots.keys()[4]
	flora.designate_felling(chop_id)
	var source = flora.work.sources[chop_id]
	source.state.work_seconds = 0.25
	var saved_flora: Dictionary = flora.serialize_state()
	for next: String in ["autumn", "winter", "spring", "summer"]:
		clock_node.day = 28
		clock_node.hour = 23.999
		var old_paths: Dictionary = {}
		for id: Vector2i in roots: old_paths[id] = flora._trees[id].model_path
		clock_node.advance_hours(0.001)
		_expect(clock_node.season == next and clock_node.day == 1, "calendar rolls normally to "+next)
		await _drain_frames(8)
		for id: Vector2i in roots:
			_expect(flora._trees[id].node == roots[id], "midnight retains tree body")
			_expect(flora._trees[id].model_path == old_paths[id], "no full forest swap at midnight")
		var pending: int = flora._seasonal_refresh.pending_count()
		clock_node.set_paused(true)
		clock_node._process(100)
		await _drain_frames(8)
		_expect(flora._seasonal_refresh.pending_count() == pending, "pause holds scheduled night progress")
		var dawn: float = float(clock_node.get_event_times().midday) - clock_node.daylight_hours(clock_node.day_of_year())*.5
		clock_node.hour = dawn*.5
		await _drain_frames(16)
		_expect(flora._seasonal_refresh.pending_count() == roots.size()/2, "half night refreshes half the tree IDs")
		_expect(details._seasonal_refresh.pending_count() == 6, "half night refreshes half the plants")
		clock_node.hour = dawn
		await _drain_frames(16)
		_expect(flora._seasonal_refresh.pending_count() == 0 and details._seasonal_refresh.pending_count() == 0, "night finishes by dawn")
		for id: Vector2i in roots:
			var tree: Dictionary = flora._trees[id]
			var species: Dictionary = flora._species_for_key("base:flora:%s_tree" % tree.name)
			var expected: String = flora.resolve_tree_model_for_season(species.stages[tree.stage],next,tree.cell)
			_expect(tree.model_path == expected, "final art matches authored season for every species/stage")
			_expect(tree.node == roots[id] and tree.occupancy_id == occupancy[id], "art swap preserves body and occupancy")
		_expect(flora.work.sources[chop_id] == source and source.state.work_seconds == .25, "chopping source and progress survive night")
		_expect(flora.serialize_state() == saved_flora, "visual refresh does not alter forestry save")
	# Save/load notification during a paused night catches up without waiting for dawn.
	clock_node.hour = 1
	var clock_save: Dictionary = clock_node.serialize_state()
	clock_node.restore_state(clock_save)
	await _drain_frames(16)
	_expect(flora._seasonal_refresh.pending_count() == 0, "paused restored night rebuilds derived art")
	_expect(clock_node.serialize_state() == clock_save and not clock_node.restoring_state, "restore context is transient and clock save is unchanged")
	# Terrain work is paced in worker-sized batches, preserving the visible nodes.
	var terrain = load("res://scripts/systems/WorldRenderer.gd").new()
	terrain.overview_tiles_per_frame = 8
	for i in 32: terrain.tiles.overview_tile_nodes[Vector2i(i,0)] = MeshInstance3D.new()
	clock_node.hour = 0
	terrain._on_season_changed(clock_node.season)
	_expect(terrain._seasonal_refresh.pending_count() == 4 and terrain.tiles.dirty_overview_tiles.is_empty(), "terrain queues batches without an immediate full-map rebuild")
	clock_node.hour = 3
	for i in 8:
		await process_frame
		terrain._seasonal_refresh.drain(terrain._enqueue_seasonal_batch)
	_expect(terrain.tiles.dirty_overview_tiles.size() == 16, "half summer night admits two complete terrain batches")
	_expect(terrain.tiles.overview_tile_nodes.size() == 32, "queued recolour retains every terrain node")
	terrain.finish_pending_overview()
	_expect(terrain._seasonal_refresh.pending_count() == 0, "world teardown discards seasonal terrain queue")
	for node: Node in terrain.tiles.overview_tile_nodes.values(): node.free()
	terrain.tiles.overview_tile_nodes.clear()
	terrain.free()
	# Superseded nights, removals and slices are checked against current live state.
	clock_node.advance_season()
	var removed: Vector2i = roots.keys().back()
	flora._tree_changes[removed] = {"felled":true}
	flora._remove_tree_visual(removed)
	details._remove("flowers:1234:fixture:11", "cleared")
	flora._on_slice_changed(10)
	details.apply_slice(10)
	clock_node.advance_hours(24*29)
	await _drain_frames(24)
	_expect(flora._trees[removed].node == null, "queued refresh cannot resurrect felled tree")
	_expect(details._records["flowers:1234:fixture:11"].node == null, "queued refresh cannot resurrect removed plant")
	for id: Vector2i in roots:
		if id != removed: _expect(not flora._trees[id].node.visible, "replacement obeys active slice")
	_expect(flora._seasonal_refresh.pending_count() == 0, "large time jump drains in bounded frames")
	# A slow atomic operation exhausts the shared budget: another owner waits.
	var first = Refresh.new()
	var second = Refresh.new()
	first.begin([1,2,3], clock_node)
	second.begin([4,5], clock_node)
	var calls: Array = []
	await process_frame
	first.drain(func(key): calls.append(key); OS.delay_usec(2500))
	second.drain(func(key): calls.append(key))
	_expect(calls == [1], "owners share a soft budget; no catch-up burst")
	await process_frame
	second.drain(func(key): calls.append(key))
	_expect(calls == [1,4,5], "budget resets on next frame")
	clock_node.set_paused(false)
	clock_node.set_speed(3)
	var before: float = clock_node.hour
	clock_node._process(20)
	_expect(is_equal_approx(clock_node.hour-before,1), "calendar and transition follow chosen game speed")
	clock_node.set_paused(true)
	if failures.is_empty(): print("SEASONAL_REFRESH_PASS ",checks," checks")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _drain_frames(count: int) -> void:
	for i in count:
		await process_frame
		flora._seasonal_refresh.drain(flora._refresh_tree_crop_visual)
		details._seasonal_refresh.drain(details._spawn_visual)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	super._expect(ok,label)
