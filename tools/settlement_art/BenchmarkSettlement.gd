extends "res://tools/terrain_art/CaptureTerrain.gd"

## Offline comparison in the full production scene. No shipping model paths change.
var pilot := false
var quick := false
var restore_only := false
var scene: Node3D
var furniture: Node
var director: Node
var wildlife: Node
var clock_node: Node
var camp := Vector3i.ZERO
var slots: Array[Vector3i] = []
var work_zone: RefCounted
var completed_tasks := 0
var frame_probe: Node
var observations := {"moving_dwarf_frames":0,"carrying_dwarf_frames":0,"sleeping_dwarf_frames":0,
	"seated_dwarf_frames":0,"moving_animal_frames":0,"open_door_frames":0}

func _init() -> void:
	output = "res://tmp/settlement_art_20261013/current_1/"
	resolution = Vector2i(2560,1440)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg == "--pilot": pilot = true
		if arg == "--quick": quick = true
		if arg == "--restore-only": restore_only = true
		if arg == "--small": resolution = Vector2i(1600,1000)
	_run.call_deferred()

func _run() -> void:
	if not "/settlement_art_20261013/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Settlement benchmark requires its isolated profile")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = resolution
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var save = root.get_node("SaveManager")
	save.configure_storage_for_testing("user://settlement_benchmark")
	save.set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_paused(true)
	clock_node.set_speed(1)
	clock_node.hour = 12.0
	seed(153)
	if pilot: load("res://tools/dwarf_pilot/DwarfPilotAssets.gd").install(root.get_node("DwarfAssets"))
	scene = load("res://scenes/main/debug_world.tscn").instantiate()
	scene.get_node("Renderer").world_seed = 1234
	if pilot:
		var owner = scene.get_node("WildlifeManager")
		owner.set_script(load("res://tools/animal_pilot/AnimalPilotWildlife.gd"))
		owner.slice_controller_path=NodePath("../SliceController")
		owner.camera_path=NodePath("../CameraRig")
	var publish = func(node: Node):
		if node == scene: current_scene = scene
	node_added.connect(publish)
	root.add_child(scene)
	node_added.disconnect(publish)
	generator = root.get_node("WorldGenerator")
	renderer = scene.get_node("Renderer")
	furniture = scene.get_node("FurniturePlacementController")
	director = scene.get_node("DwarfDirector")
	wildlife = scene.get_node("WildlifeManager")
	if pilot: load("res://tools/furniture_pilot/FurniturePilotAssets.gd").install(furniture)
	while not generator._maps_ready or generator.is_generating(): await process_frame
	while not scene.get_node("SurfaceFloraSpawner")._pending.is_empty(): await process_frame
	var details = scene.get_node("SurfaceDetailManager")
	while not details._initialized or not details._visual_queue.is_empty(): await process_frame
	while not wildlife.duck_initialized: await process_frame
	await _settle()
	report = {"seed":1234,"pilot":pilot,"quick":quick,"resolution":[resolution.x,resolution.y],
		"fixed_simulation_fps":60,"adapter":RenderingServer.get_video_adapter_name(),
		"engine":Engine.get_version_info(),"cpu":OS.get_processor_name(),"captures":{},"failures":[],
		"shader_uniform_buffer_slots":ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size")}
	if restore_only:
		var saved: Dictionary = save._read_snapshot(save._save_path)
		if not saved.get("ok",false):
			report.failures.append("Missing restore fixture")
		else:
			await _reload_check(save,saved.snapshot)
		_finish()
		return
	report["world_fingerprints"] = _fingerprints()
	var identities: Array[String] = []
	for record: Dictionary in details._records.values():
		identities.append("%s:%s:%s:%s"%[record.definition,record.origin,record.variant,record.yaw])
	identities.sort()
	report["detail_identity_sha256"] = "|".join(identities).sha256_text()
	report["tree_count"] = scene.get_node("SurfaceFloraSpawner")._trees.size()
	_find_camp()
	if slots.size() < 48:
		report.failures.append("No suitable camp with 48 separated furniture sites")
		_finish()
		return
	_build_camp()
	await _settle()
	root.get_node("TaskManager").task_completed.connect(func(_task): completed_tasks += 1)
	var rig = scene.get_node("CameraRig")
	rig.set_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(camera)
	camera.make_current()
	for layer in scene.find_children("*","CanvasLayer",true,false): layer.visible = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	frame_probe=load("res://tools/settlement_art/FrameProbe.gd").new()
	scene.add_child(frame_probe)
	_set_light(12)
	report["fixture"] = _fixture_state()
	report["fixture_sha256"] = JSON.stringify(report.fixture).sha256_text()
	var snapshots: Dictionary = save._build_snapshot()
	report["initial_save_validation"] = save._validate_snapshot(snapshots)
	if not report.initial_save_validation.is_empty(): report.failures.append(report.initial_save_validation)
	# Paused views isolate rendering; active views retain the real scheduler/AI.
	_view(Vector3(camp)+Vector3(0,3,0),48,Vector3(-.7,1,1))
	await _sample("paused_close",false)
	_view(Vector3(camp)+Vector3(0,3,0),100,Vector3(-.7,1,1))
	await _sample("paused_neighborhood",false)
	_view(Vector3(camp)+Vector3(0,3,0),220,Vector3(-.7,1,1))
	await _sample("paused_overview",false)
	_set_light(23)
	_view(Vector3(camp)+Vector3(0,3,0),85,Vector3(-.7,1,1))
	await _sample("paused_night",false)
	_set_light(12)
	await _sample("active_neighborhood",true)
	_view(Vector3(camp)+Vector3(0,3,0),48,Vector3(-.7,1,1))
	await _sample("active_close",true)
	_view(Vector3(camp)+Vector3(0,3,0),220,Vector3(-.7,1,1))
	await _sample("active_overview",true)
	_set_light(23)
	_view(Vector3(camp)+Vector3(0,3,0),85,Vector3(-.7,1,1))
	await _sample("active_night",true)
	_set_light(12)
	await _sample("active_pan",true,true)
	await _edit_and_slice()
	clock_node.set_paused(true)
	report["behavior_observations"] = observations
	report["completed_tasks"] = completed_tasks
	report["stored_stacks"] = work_zone.cell_stacks.size()
	report["final_counts"] = _counts()
	if completed_tasks < 1: report.failures.append("No real worker task completed")
	if observations.carrying_dwarf_frames == 0: report.failures.append("No real hauling animation observed")
	if observations.moving_animal_frames == 0: report.failures.append("No wildlife travel observed")
	if observations.open_door_frames == 0: report.failures.append("No live door opening observed")
	report["save_written"] = save.request_save()
	while save.is_saving(): await process_frame
	report["save_written"] = report.save_written and bool(save.last_save_profile.get("success",false))
	if not report.save_written: report.failures.append("Fixture save failed")
	if report.save_written: await _reload_check(save)
	_finish()

func _reload_check(save: Node, expected: Dictionary = {}) -> void:
	if expected.is_empty(): expected=save._build_snapshot()
	# SaveManager validates JSON-normalized snapshots, not live StringName/Vector data.
	expected=JSON.parse_string(JSON.stringify(expected))
	# Reapply study-only model substitutions before the normal restore assembles actors.
	var prepare = func(node: Node):
		if node.name == "DebugWorld":
			node.ready.connect(func():
				if pilot:
					load("res://tools/furniture_pilot/FurniturePilotAssets.gd").install(node.get_node("FurniturePlacementController"))
					node.get_node("WildlifeManager")._deer_models=load("res://tools/animal_pilot/AnimalPilotAssets.gd").models()
			,CONNECT_ONE_SHOT)
	node_added.connect(prepare)
	save.set_process(true)
	var started := Time.get_ticks_usec()
	if not save.request_load():
		report.failures.append("Saved benchmark could not load")
		node_added.disconnect(prepare)
		return
	while save.is_loading(): await process_frame
	node_added.disconnect(prepare)
	save.set_process(false)
	scene=current_scene
	renderer=scene.get_node("Renderer")
	director=scene.get_node("DwarfDirector")
	furniture=scene.get_node("FurniturePlacementController")
	wildlife=scene.get_node("WildlifeManager")
	await _settle()
	var actual: Dictionary = JSON.parse_string(JSON.stringify(save._build_snapshot()))
	FileAccess.open(output+"restore_expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected))
	FileAccess.open(output+"restore_actual.json",FileAccess.WRITE).store_string(JSON.stringify(actual))
	var validation: String = save._validate_snapshot(actual)
	var checks := {"dwarf_count":actual.scene.dwarves.roster.size()==expected.scene.dwarves.roster.size(),
		"furniture":_same_save_value(actual.scene.furniture,expected.scene.furniture),
		"wildlife":_same_save_value(actual.scene.wildlife,expected.scene.wildlife),
		"clock":_same_save_value(actual.clock,expected.clock),
		"terrain_edits":_same_save_value(actual.scene.water.terrain,expected.scene.water.terrain),
		"valid_snapshot":validation.is_empty()}
	checks["dwarf_identity_and_appearance"]=checks.dwarf_count
	if checks.dwarf_count:
		for i in range(actual.scene.dwarves.roster.size()):
			for field in ["id","name","gender","appearance","traits","profession","profession_experience","work_permissions"]:
				if not _same_save_value(actual.scene.dwarves.roster[i][field],expected.scene.dwarves.roster[i][field]):
					checks.dwarf_identity_and_appearance=false
	# Carried goods intentionally return to loose storage on restore. Compare totals.
	checks["stone_conservation"]=_stone_units(actual)==_stone_units(expected)
	for key in checks:
		if not checks[key]: report.failures.append("Restore contract: "+key)
	report["save_reload"]={"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"checks":checks,
		"stone_units":_stone_units(actual),"counts":_counts(),"validation_error":validation}

func _same_save_value(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<=.00001
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same_save_value(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not _same_save_value(a[i],b[i]): return false
		return true
	return a==b

func _stone_units(snapshot: Dictionary) -> int:
	var count := 0
	# Inspect owner-produced save data, preserving the real save/restore pipeline.
	count=_sum_stone(snapshot.scene)
	return count

func _sum_stone(value: Variant) -> int:
	var total := 0
	if value is Dictionary:
		if value.get("item_key",value.get("item",""))=="base:resources:stone:rough_stone":
			return int(value.get("count",1))
		for child in value.values(): total+=_sum_stone(child)
	elif value is Array:
		for child in value: total+=_sum_stone(child)
	return total

func _find_camp() -> void:
	# Choose from unchanged terrain/occupancy, never from the model's visual bounds.
	var blocks = root.get_node("BlockRegistry")
	var nav = root.get_node("NavGrid")
	var best: Array[Vector3i] = []
	for z in range(128,896,24):
		for x in range(128,896,24):
			var cy: int = generator.get_surface_y(x,z)
			if cy < 5 or cy > 44: continue
			var candidates: Array[Vector3i] = []
			for dz in range(-24,25,7):
				for dx in range(-24,25,7):
					var y: int = generator.get_surface_y(x+dx,z+dz)
					if absi(y-cy)>2: continue
					var valid := true
					for ox in range(4):
						for oz in range(4):
							var p := Vector3i(x+dx+ox,y,z+dz+oz)
							if generator.get_surface_y(p.x,p.z)!=y or not nav.is_walkable(p): valid=false; break
							var id: int = generator.get_generated_block_id(p.x,p.y,p.z)
							if blocks.get_def(blocks.get_key(id)).get("kind","") != "grass": valid=false; break
						if not valid: break
					if valid: candidates.append(Vector3i(x+dx,y,z+dz))
			if candidates.size()>best.size(): best=candidates; camp=Vector3i(x,cy,z)
			if best.size()>=48: slots=best; return
	slots=best

func _build_camp() -> void:
	var defs: Dictionary = furniture.get_defs()
	for i in range(48):
		var short_key := "log_bed" if i<16 else "log_chair" if i<32 else "door" if i<40 else "campfire"
		var key := "base:furniture:"+short_key
		var reason: String = furniture._floor_placement_reason(defs[key],slots[i],0)
		if not reason.is_empty(): report.failures.append("Invalid "+key+": "+reason); continue
		furniture._install(key,defs[key],slots[i],0,"base:material:"+["oak","pine","juniper","applewood"][i%4])
	var free_cells: Array[Vector3i] = []
	var nav = root.get_node("NavGrid")
	for z in range(camp.z-25,camp.z+29,2):
		for x in range(camp.x-25,camp.x+29,2):
			var floor_cell := Vector3i(x,generator.get_surface_y(x,z),z)
			if nav.is_walkable(floor_cell) and not furniture.blocks_zone_cell(floor_cell): free_cells.append(floor_cell)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for i in range(24):
		var data: Dictionary = factory.generate(141+i,director._used_names)
		data.gender="male"
		data.appearance.gender="male"; data.appearance.age_tier="adult"
		data.appearance.hair_style="short_back"; data.appearance.beard_style="forked"
		data.appearance.eyebrow_style="thick_flat"; data.appearance.scar="none"
		var actor = factory.spawn(data,i)
		# Distribute across the camp; avoid a line of overlapping heads at one edge.
		actor.position=Vector3(free_cells[(i*19)%free_cells.size()])+Vector3(.5,1,.5)
		director.add_child(actor)
		load("res://scripts/components/UndergroundLighting.gd").bind_world_tree(actor)
		director._agents.append(actor)
		root.get_node("TaskManager").register_dwarf(actor)
		if i<6: actor.sleep=.1
	director._birth_index=24
	director.set_settlement_anchor(camp)
	# Existing seeded populations stay present. A nearby herd makes deer art visible.
	var animal_nav = load("res://scripts/components/AnimalNavigation.gd")
	var herd_count := 0
	for cell in free_cells:
		if cell.z<camp.z+18 or cell.x<camp.x+8 or not animal_nav.standable(cell+Vector3i.UP,4,2): continue
		var animal = wildlife.add_deer("deer:benchmark:%d"%herd_count,cell+Vector3i.UP,153+herd_count,"herd:benchmark")
		animal.home=cell+Vector3i.UP
		herd_count+=1
		if herd_count==12: break
	if herd_count!=12: report.failures.append("Could not place nearby twelve-deer herd")
	# A real stockpile and loose goods exercise the live hauling scheduler.
	var stock = scene.get_node("StockpileDesignationController")
	var groups := {}
	for cell in free_cells:
		if cell.z<camp.z+12 or not stock._is_valid_cell(cell,cell.y): continue
		if not groups.has(cell.y): groups[cell.y]=[]
		groups[cell.y].append(cell)
	var storage_cells: Array[Vector3i] = []
	for cells: Array in groups.values():
		if cells.size()>storage_cells.size(): storage_cells.assign(cells)
	storage_cells.resize(mini(storage_cells.size(),48))
	work_zone=stock._create_zone(storage_cells)
	var drops = scene.get_node("ItemDropManager")
	for i in range(96):
		var cell := free_cells[i%free_cells.size()]
		drops.restore_loose_item("base:resources:stone:rough_stone",Vector3(cell)+Vector3(.5,1,.5),0,1,"benchmark:stone:%d"%i)

func _set_light(hour: float) -> void:
	root.get_node("WeatherManager").set_weather("base:weather:clear")
	var sky = root.get_node("SkyController")
	sky.rebind_to_current_scene()
	sky.set_process(false)
	sky._update(hour)

func _counts() -> Dictionary:
	var counts := {"dwarves":director._agents.size(),"furniture":furniture._installed.size(),"trees":scene.get_node("SurfaceFloraSpawner")._trees.size(),"lights":scene.find_children("*","OmniLight3D",true,false).size(),"mesh_instances":scene.find_children("*","MeshInstance3D",true,false).size()}
	for species in ["rabbit","deer","wolf","duck"]: counts[species]=wildlife.animals_of_species(species).size()
	return counts

func _fixture_state() -> Dictionary:
	return {"camp":str(camp),"counts":_counts(),"dwarves":director.serialize_state(),
		"wildlife":wildlife.serialize_state(),"furniture":furniture.serialize_state(),
		"stockpiles":scene.get_node("StockpileDesignationController").serialize_state(),
		"items":scene.get_node("ItemDropManager").serialize_state()}

func _observe() -> void:
	for actor in director._agents:
		if not actor._move_path.is_empty(): observations.moving_dwarf_frames+=1
		if not actor._carried_entries.is_empty(): observations.carrying_dwarf_frames+=1
		if actor.is_sleeping(): observations.sleeping_dwarf_frames+=1
		if actor._idle_behavior.seat!=null: observations.seated_dwarf_frames+=1
	for animal in wildlife.animals:
		if animal.hop_progress<1: observations.moving_animal_frames+=1
	for piece in furniture._installed.values():
		var door = piece.node.get_node_or_null("DoorAnimation")
		if door!=null and absf(door._angle)>.1: observations.open_door_frames+=1

func _sample(label: String, active: bool, pan := false) -> void:
	clock_node.set_paused(not active)
	var warm := 30 if quick else 120
	var count := 120 if quick else 600
	for i in range(warm): await process_frame
	var samples := {"frame_ms":[],"gpu_ms":[],"render_cpu_ms":[],"scene_process_ms":[]}
	var rid := root.get_viewport_rid()
	for i in range(count):
		var tick := Time.get_ticks_usec()
		if pan:
			var t := float(i)/count*TAU
			_view(Vector3(camp)+Vector3(sin(t)*24,3,cos(t)*24),100,Vector3(-.7,1,1))
		await process_frame
		samples.frame_ms.append((Time.get_ticks_usec()-tick)/1000.0)
		samples.gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		samples.render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		samples.scene_process_ms.append(frame_probe.last_ms)
		if active: _observe()
	clock_node.set_paused(true)
	var result := {"active":active,"warmup_frames":warm,"sample_frames":count,"slice_y":renderer.slice_y,
		"camera_position":str(camera.position),"camera_rotation":str(camera.rotation),"camera_size":camera.size,
		"draws":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"static_memory_bytes":OS.get_static_memory_usage(),
		"completed_tasks":completed_tasks,"stored_stacks":work_zone.cell_stacks.size()}
	for key in samples:
		var values: Array[float] = []
		values.assign(samples[key])
		result[key]=_percentiles(values)
	report.captures[label]=result
	FileAccess.open(output+label+"_samples.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output+label+".png")!=OK: report.failures.append("Capture "+label)
	print("SETTLEMENT_SAMPLE ",label," ",JSON.stringify(result))

func _edit_and_slice() -> void:
	var slice = scene.get_node("SliceController")
	report["slice_transitions"] = []
	_view(Vector3(camp)+Vector3(0,2,0),100,Vector3(-.7,1,1))
	for level in [camp.y+4,camp.y+1,camp.y+4]:
		var tick := Time.get_ticks_usec()
		slice.activate()
		slice._set_slice_y(level)
		var dispatch := (Time.get_ticks_usec()-tick)/1000.0
		var settling := await _settle()
		report.slice_transitions.append({"level":level,"dispatch_ms":dispatch,"settle":settling})
	await _sample("active_slice",true)
	slice.deactivate()
	await _settle()
	if renderer.slice_y!=127: report.failures.append("Full world not restored after slice")
	var cliff := _find_cliff()
	var edits: Array[Vector3i] = []
	for x in range(cliff.x+1,cliff.x+9):
		for y in range(cliff.y+1,cliff.y+4): edits.append(Vector3i(x,y,cliff.z))
	var construction = scene.get_node("ConstructionController")
	var mining = scene.get_node("MiningDesignationController")
	report["terrain_edits"] = []
	for pass_index in range(3):
		var tick := Time.get_ticks_usec()
		mining._mine_blocks_world(edits)
		var dispatch := (Time.get_ticks_usec()-tick)/1000.0
		var settling := await _settle()
		report.terrain_edits.append({"action":"mine","blocks":edits.size(),"dispatch_ms":dispatch,"settle":settling})
		tick=Time.get_ticks_usec()
		for cell in edits: construction._place_block(cell,"base:terrain:rock:rock01")
		dispatch=(Time.get_ticks_usec()-tick)/1000.0
		settling=await _settle()
		report.terrain_edits.append({"action":"restore","blocks":edits.size(),"dispatch_ms":dispatch,"settle":settling})
	report["final_renderer"] = renderer.get_render_stats()

func _finish() -> void:
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SETTLEMENT_BENCHMARK_PASS " if report.failures.is_empty() else "SETTLEMENT_BENCHMARK_FAIL ",output)
	if is_instance_valid(generator): generator.prepare_for_world_reload()
	quit(0 if report.failures.is_empty() else 1)
