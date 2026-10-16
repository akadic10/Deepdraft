extends SceneTree
## Native packed-save check. Run from the package directory with editor Godot
## --path <package> --main-pack <pck> --script <absolute helper path>.
var failures: Array[String] = []
var output := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not "/events_20261015/" in OS.get_user_data_dir().replace("\\","/") or output.is_empty():
		push_error("Lighting check requires isolated events_20261015 profile and output")
		quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Packed check must not resolve loose workspace files")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): push_error("Lighting packed check timeout"); quit(1))
	root.size=Vector2i(1600,1000)
	var clock_node=root.get_node("WorldClock")
	var saves=root.get_node("SaveManager")
	clock_node.set_paused(true)
	var placeholder:=Node3D.new()
	placeholder.scene_file_path="res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene=placeholder
	if not saves.request_load(): quit(1); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	var terrain=current_scene.get_node("Renderer")
	await _settle(terrain)
	var feedback=root.get_node("WorkFeedback")
	check(is_instance_valid(feedback._dust_warmup) and not feedback._dust_warmup.visible,"packed world prepares hidden work effect")
	var warmup=feedback._dust_warmup
	feedback._spawn_burst(current_scene.get_node("DwarfDirector").get_roster()[0].position,127,feedback.config.poof,1.0,"packed_check")
	var burst=feedback._bursts.back()
	check(burst._mesh.multimesh.mesh==warmup.multimesh.mesh,"packed effect uses prepared mesh")
	check(burst._mesh.material_override==warmup.material_override,"packed effect uses prepared material")
	# Re-run a real derived lighting update without changing the copied world.
	var field=terrain.underground_lighting
	var published: Dictionary=field._samples.duplicate()
	var textures: Array=[]
	for page in field._images:
		for layer in page: textures.append(layer.get_data())
	var completed: int=field.completed_updates
	field._on_doors_changed(field._edits.duplicate())
	check(field.is_updating(),"packed lighting queues a refresh")
	await _settle(terrain)
	while field._cleanup_task>=0: await process_frame
	check(field.completed_updates>completed,"packed lighting refresh finishes")
	check(field._samples==published,"packed light samples survive buffer disposal")
	var image_index:=0
	for page in field._images:
		for layer in page:
			check(image_index<textures.size() and layer.get_data()==textures[image_index],"packed texture bytes unchanged")
			image_index+=1
	check(image_index==textures.size(),"packed texture layer count unchanged")
	var wildlife=current_scene.get_node("WildlifeManager")
	var rig=current_scene.get_node("CameraRig")
	var camera: Camera3D=rig.camera_node
	var before: Dictionary={}
	var offscreen:=0
	for animal in wildlife.animals:
		before[animal.animal_id]=animal.serialize_state()
		if not camera.is_position_in_frustum(animal.global_position): offscreen+=1
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(8).timeout
	clock_node.set_paused(true)
	var moved:=0
	for animal in wildlife.animals:
		if not before.has(animal.animal_id): continue
		check(animal.pose_time>float(before[animal.animal_id].pose_time),"offscreen/onscreen animal time advances: "+animal.animal_id)
		if animal.position!=saves.unpack_v3(before[animal.animal_id].position): moved+=1
	check(offscreen>0 and moved>0,"copied world contains moving offscreen wildlife")
	var paused: Dictionary=wildlife.serialize_state()
	await create_timer(.2).timeout
	check(paused==wildlife.serialize_state(),"pause freezes all wildlife state")
	for species in ["wolf","duck"]:
		var animals: Array=wildlife.animals_of_species(species)
		check(not animals.is_empty(),"copied save restores "+species)
		if animals.is_empty(): continue
		var animal: Node3D=animals[0]
		rig.stop_following()
		rig._target_pos=animal.position+Vector3.UP
		rig.global_position=rig._target_pos
		rig._target_zoom=16.0
		await create_timer(1.5).timeout
		await _settle(terrain)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+species+".png")
	var first: Node3D=wildlife.animals[0]
	wildlife.apply_slice(floori(first.position.y)-1)
	check(not first.visible,"slice immediately conceals wildlife")
	wildlife.apply_slice(127)
	check(first.visible,"surface wildlife reappears on full slice")
	var queries: Dictionary=wildlife.duck_navigation.get_query_stats()
	check(queries.hits>0 and queries.batches>0,"packed wildlife reuses live navigation queries")
	check(not queries.active and queries.entries==0,"no cached query survives the update")
	check(queries.peak<=4096,"combined query storage is bounded")
	var controller=current_scene.get_node("ConstructionController")
	var roster: Array=current_scene.get_node("DwarfDirector").get_roster()
	var obstacle_comparisons:=0
	var obstacles: Dictionary=controller.obstacle_snapshot()
	for dwarf in roster:
		for x in range(-3,4):
			for z in range(-3,4):
				var cell: Vector3i=dwarf.current_cell()+Vector3i(x,1,z)
				check(controller.build_reason(cell,false)==controller.build_reason(cell,false,true,"stone",obstacles),"packed obstacle query matches live rejection")
				obstacle_comparisons+=1
	var navigation=load("res://scripts/components/AnimalNavigation.gd")
	# Exercise the packaged hauling query against actual saved loose goods.
	# This unregistered source never posts work or reserves inventory.
	var drops=current_scene.get_node("ItemDropManager")
	var quote_source=load("res://scripts/components/StockpileZoneComponent.gd").new()
	var quote_cells: Array[Vector3i]=[roster[0].current_cell()]
	quote_source.setup(-900,quote_cells)
	quote_source.drop_manager=drops
	var snapshot: Dictionary={}
	var quote_comparisons:=0
	for dwarf in roster:
		var from: Vector3i=dwarf.current_cell()
		var query: Dictionary={}
		check(drops.advance_nearest_haul_query(from,quote_source._can_haul_key,query,snapshot,Time.get_ticks_usec()+1000000),"packed shared quote completes")
		var best: Node3D=null
		var distance:=0x7FFFFFFF
		for item: Node3D in drops._loose:
			if bool(item.get_meta("disallowed",false)) or drops._reserved.has(item) or not quote_source._can_haul_key(String(drops._loose[item])): continue
			var delta: Vector3i=drops.item_floor_cell(item)-from
			var next:=absi(delta.x)+absi(delta.y)+absi(delta.z)
			if next<distance:
				best=item
				distance=next
		check(query.get("best")==best,"packed shared quote matches direct live selection")
		quote_comparisons+=1
	var result: Dictionary={"failures":failures,"offscreen_at_start":offscreen,"moved":moved,
		"work_effect_prepared":true,"lighting_refreshes":field.completed_updates-completed,"lighting_texture_layers":image_index,"lighting_cleanup_idle":field._cleanup_task<0,
		"duck_queries":queries,"animals_after":wildlife.animals.size(),"cache":navigation.get_cache_stats(),
		"dwarves":current_scene.get_node("DwarfDirector").get_roster().size(),
		"obstacle_comparisons":obstacle_comparisons,"quote_comparisons":quote_comparisons,"driver":RenderingServer.get_current_rendering_driver_name()}
	FileAccess.open(output+"packed_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("EVENTS_EXPORT_PASS " if failures.is_empty() else "EVENTS_EXPORT_FAIL ",JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)

func _settle(terrain: Node) -> void:
	await process_frame
	await process_frame
	while not terrain._overview_built or not terrain._dirty_overview_tiles.is_empty() or terrain._cavity_shell_dirty or terrain.underground_lighting.is_updating():
		await process_frame
