extends SceneTree

## Run with the exported PCK and an isolated copy of the player's settlement.
var output := ""
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not "/seasons_20261015/" in OS.get_user_data_dir().replace("\\","/") or output.is_empty():
		push_error("Season check requires isolated seasons_20261015 profile and output"); quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Packed check must not resolve loose workspace files"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(240).timeout.connect(func(): push_error("Season package timeout"); quit(1))
	root.size = Vector2i(1600,1000)
	var clock_node = root.get_node("WorldClock")
	var saves = root.get_node("SaveManager")
	clock_node.set_paused(true)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	check(saves.request_load(),"copied settlement loads")
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	await _settle()
	var flora = current_scene.get_node("SurfaceFloraSpawner")
	var details = current_scene.get_node("SurfaceDetailManager")
	var terrain = current_scene.get_node("Renderer")
	var roots: Dictionary = {}
	var old_models: Dictionary = {}
	var occupancy: Dictionary = {}
	for id: Vector2i in flora._trees:
		var tree: Dictionary = flora._trees[id]
		if not is_instance_valid(tree.node): continue
		roots[id] = tree.node.get_instance_id()
		old_models[id] = tree.model_path
		occupancy[id] = tree.occupancy_id
	var revisions: Dictionary = terrain.tiles._overview_revisions.duplicate()
	var rig = current_scene.get_node("CameraRig")
	rig.stop_following()
	var focus: Dictionary = flora._trees[roots.keys()[roots.size()/4]]
	rig._target_pos = Vector3(focus.cell)+Vector3(0,4,0)
	rig.global_position = rig._target_pos
	rig._target_zoom = 100
	clock_node.day = 28
	clock_node.hour = 23.999
	clock_node.advance_hours(.001)
	await _frames(10)
	for id: Vector2i in roots:
		check(flora._trees[id].node.get_instance_id() == roots[id],"midnight preserves tree body")
		check(flora._trees[id].model_path == old_models[id],"midnight retains existing tree art")
	check(flora._seasonal_refresh.pending_count() > 0,"night refresh is genuinely pending")
	await _capture("midnight")
	var dawn: float = float(clock_node.get_event_times().midday)-clock_node.daylight_hours(clock_node.day_of_year())*.5
	clock_node.hour = dawn*.5
	for i in 1000:
		await process_frame
		if flora._seasonal_refresh.pending_count() <= ceili(roots.size()*.5) and details._seasonal_refresh.pending_count() <= ceili(details._records.size()*.5): break
	var pending: int = flora._seasonal_refresh.pending_count()
	check(pending > 0 and pending < roots.size(),"midnight-to-dawn refresh is partial halfway through")
	await _frames(12)
	check(flora._seasonal_refresh.pending_count() == pending,"paused night stops further seasonal progress")
	await _capture("half_night")
	for id: Vector2i in roots:
		check(flora._trees[id].node.get_instance_id() == roots[id] and flora._trees[id].occupancy_id == occupancy[id],"partial night preserves body and navigation occupancy")
	# Slice changes are still immediate while a seasonal queue is pending.
	flora._on_slice_changed(0)
	details.apply_slice(0)
	for id: Vector2i in roots: check(not flora._trees[id].node.visible,"pending trees respect slice concealment")
	flora._on_slice_changed(127)
	details.apply_slice(127)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(saves._build_snapshot()))
	saves.set_process(true)
	check(saves.request_save(),"midnight transition manual save accepted")
	while saves.is_saving(): await process_frame
	var saved: Dictionary = saves._read_snapshot(saves._save_path)
	check(saved.get("ok",false) and saved.snapshot.scene == expected.scene,"saving during visual transition preserves authoritative state")
	clock_node.hour = dawn
	await _settle()
	for key: Vector2i in revisions:
		check(int(terrain.tiles._overview_revisions.get(key,0)) > int(revisions[key]),"every existing terrain tile refreshed by end of night")
	_check_final_art(flora,details)
	await _capture("dawn")
	# Reload the actual half-night save while paused. Transient queues rebuild
	# target art promptly; neither old callbacks nor a real-time wait survive load.
	check(saves.request_load(),"saved partial night reload accepted")
	while saves.is_loading(): await process_frame
	clock_node.set_paused(true)
	await _settle()
	check(is_equal_approx(clock_node.hour,dawn*.5),"load restores saved night time")
	flora = current_scene.get_node("SurfaceFloraSpawner")
	details = current_scene.get_node("SurfaceDetailManager")
	_check_final_art(flora,details)
	check(current_scene.get_node("DwarfDirector").get_roster().size() == 5,"all copied dwarves survive transition reload")
	check(current_scene.get_node("WildlifeManager").animals.size() == 79,"all copied wildlife survive transition reload")
	clock_node.hour = 14
	await _frames(20)
	await _capture("restored_daylight")
	var result := {"checks":checks,"failures":failures,"trees":roots.size(),"half_night_pending":pending,
		"season":clock_node.season,"dawn_hour":dawn,"driver":RenderingServer.get_current_rendering_driver_name()}
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	if failures.is_empty(): print("SEASON_EXPORT_PASS ",JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _check_final_art(flora: Node, details: Node) -> void:
	var clock_node = root.get_node("WorldClock")
	var shrub = load("res://scripts/components/ShrubSeason.gd")
	var registry = root.get_node("SurfaceDetailRegistry")
	for id: Vector2i in flora._trees:
		var tree: Dictionary = flora._trees[id]
		if not is_instance_valid(tree.node): continue
		var species: Dictionary = flora._species_for_key("base:flora:%s_tree" % tree.name)
		var picked: bool = String(flora._tree_changes.get(id,{}).get("harvested_cycle","")) == flora._fruit_cycle()
		check(tree.model_path == flora.resolve_tree_model_for_season(species.stages[tree.stage],clock_node.season,tree.cell,picked),"final tree model matches season/crop")
	for id: String in details._records:
		var record: Dictionary = details._records[id]
		if not is_instance_valid(record.node): continue
		var definition: Dictionary = registry.get_definition(record.definition)
		if details._is_shrub(id): check(record.model_path == shrub.model(definition,details._changes.get(id,{})),"final shrub follows season and crop state")
		elif details._is_decorative_plant(id): check(record.model_path == String(definition.seasonal_models[clock_node.season][int(record.variant)]),"final flower/reed model matches season")

func _settle() -> void:
	for i in 12000:
		await process_frame
		var terrain = current_scene.get_node("Renderer")
		var flora = current_scene.get_node("SurfaceFloraSpawner")
		var details = current_scene.get_node("SurfaceDetailManager")
		if terrain.tiles.overview_built and terrain.tiles.dirty_overview_tiles.is_empty() and not terrain.tiles.ovt_building and not terrain.cavity_shell.dirty \
			and terrain._seasonal_refresh.pending_count() == 0 and flora._seasonal_refresh.pending_count() == 0 and details._seasonal_refresh.pending_count() == 0 \
			and flora._ready_to_spawn and flora._pending.is_empty() and details._initialized and details._visual_queue.is_empty() \
			and not terrain.underground_lighting.is_updating(): return
	check(false,"packaged world settles")

func _frames(count: int) -> void:
	for i in count: await process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")
