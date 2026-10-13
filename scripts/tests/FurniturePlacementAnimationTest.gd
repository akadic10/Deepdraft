extends "res://scripts/tests/WorkerCraftingTest.gd"

const SITE := Vector3i(52,20,46)
const LOG_BENCH := "base:furniture:bench"
const WALL := "base:furniture:wall_torch"
const OUT := "res://tmp/furniture_placement_animation_20261011/"
var checked := 0
var support_cells: Array[Vector3i] = []

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Furniture placement animation timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for key: String in furniture.get_defs():
		var definition: Dictionary = furniture.get_defs()[key]
		if bool(definition.get("plant",false)) or definition.has("bridge") or definition.has("ladder") or definition.has("water_stone"):
			continue # Their real work-source suites exercise the separate contracts.
		await _place_case(key,0)
	for key: String in [LOG_BENCH,"base:furniture:log_bed","base:furniture:log_door_4",WALL]:
		for yaw in range(1,4): await _place_case(key,yaw)
	await _interruptions()
	await _floor_excavation()
	await _cleanup()
	for failure: String in failures: push_error(failure)
	var report := {"placements":checked,"set_down_seconds":tasks.get_config_section("hauling").deposit_time_s,
		"failures":failures,"player_saves_touched":false}
	var file := FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print("FURNITURE_PLACEMENT_ANIMATION_OK: ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _cleanup() -> void:
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in furniture._installed.keys(): furniture._teardown_installed(id,true)
	for node in drops._loose.keys(): drops.take(node); node.queue_free()
	worker.stop_walking()
	worker._idle_behavior.cancel()
	worker.position = Vector3(49.5,21,44.5)
	worker.sleep = 1
	for cell in support_cells: world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
	support_cells.clear()
	await _frames(2)

func _arrive(key: String,yaw: int) -> RefCounted:
	await _cleanup()
	var definition: Dictionary = furniture.get_defs()[key]
	if String(definition.get("placement","floor"))=="wall":
		var mount = load("res://scripts/components/WallFurnitureMount.gd")
		support_cells = mount.supports(definition,SITE,yaw)
		for cell in support_cells: world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock01"))
		await _frames(2)
	drops.restore_loose_item(String(definition.item_key),Vector3(50.5,21,44.5),0,1)
	furniture.activate_for(key,true)
	furniture._yaw = yaw
	furniture._hover_cell = SITE
	_expect(furniture._placement_valid(SITE),"fixture permits "+key+" yaw "+str(yaw))
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST),"actual pickup carries "+key)
	for i in range(400):
		if worker._task_phase!=worker.TaskPhase.FETCH_TO_GHOST: break
		await _tick()
	_expect(worker._task_phase==worker.TaskPhase.FETCH_DEPOSIT,"arrival immediately starts placement for "+key)
	return ghost

func _place_case(key: String,yaw: int) -> void:
	var ghost = await _arrive(key,yaw)
	if worker._task_phase!=worker.TaskPhase.FETCH_DEPOSIT: return
	var duration: float = tasks.get_config_section("hauling").deposit_time_s
	_expect(is_zero_approx(worker._handling_elapsed),"arrival does not spend hidden placement work")
	_expect(is_equal_approx(worker._handling_duration,duration),"only the shared set-down duration is charged")
	var item: Node3D = worker._fetch_item
	var start: Vector3 = item.global_position
	var stand: Vector3 = worker.global_position
	var contact: Vector3 = worker._handling_target
	var wall := String(ghost.def.get("placement","floor"))=="wall"
	if wall:
		_expect(is_equal_approx(contact.y,float(SITE.y)+float(ghost.def.wall_mount.origin_offset_y)),"wall handoff rises to mount height")
	else:
		_expect(ghost.footprint_cells().has(Vector3i(floori(contact.x),roundi(contact.y)-1,floori(contact.z))),"set-down lands inside designated rotated footprint")
		_expect(not ghost.footprint_cells().has(worker.current_cell()),"installer stays beside finished furniture")
	await _capture_pose(key,yaw,"arrival")
	worker._process(.15)
	_expect(item.global_position.distance_to(start)>.025,"cargo visibly moves within 150 ms: "+key)
	_expect(worker.global_position==stand and worker._foot_l.position.is_zero_approx() and worker._foot_r.position.is_zero_approx(),"both boots stay planted")
	var cargo: Array = worker.serialize_state().carried_items
	_expect(cargo.size()==1 and cargo[0].item_key==ghost.item_key and furniture._installed.is_empty(),"save owns the physical cargo until animation finishes")
	var pose := item.global_transform
	clock_node.set_paused(true)
	worker._process(3)
	_expect(item.global_transform.is_equal_approx(pose) and is_equal_approx(worker._handling_elapsed,.15),"pause freezes pose and placement together")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.05)
	_expect(is_equal_approx(worker._handling_elapsed,.25),"2x advances animation and completion together")
	clock_node.set_speed(1)
	worker._process(duration*.85-.25)
	var bounds: AABB = item.global_transform * worker._carry_pose.item_bounds(item)
	_expect(Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z).distance_to(contact)<.005,"physical crate reaches placement contact")
	await _capture_pose(key,yaw,"release")
	worker._process(duration-worker._handling_elapsed-.001)
	_expect(furniture._ghosts.has(ghost.ghost_id) and worker._carried_entries.size()==1,"no premature item consumption")
	worker._process(.002)
	_expect(not furniture._ghosts.has(ghost.ghost_id) and furniture._installed.size()==1,"installed at animation end without another wait: "+key)
	_expect(worker.current_task_id<0 and worker._carried_entries.is_empty() and drops._loose.is_empty(),"worker and cargo released once")
	_expect(root.get_node("NavGrid").is_walkable(worker.current_cell()),"installation does not trap its builder")
	await _capture_pose(key,yaw,"installed")
	checked += 1

func _interruptions() -> void:
	for action in ["cancel","blocked","interrupt"]:
		var ghost = await _arrive(LOG_BENCH,0)
		worker._process(.2)
		var item: Node3D = worker._fetch_item
		if action=="cancel": furniture.cancel_ghost(ghost.ghost_id)
		elif action=="blocked":
			ghost.build_valid_callback = func(_plan): return false
			worker._process(1)
		else: worker.dev_force_interrupt()
		_expect(worker._carried_entries.is_empty() and drops._loose.has(item) and drops._loose.size()==1
			and furniture._installed.is_empty(),action+" conserves the exact packed item")
		if action=="interrupt":
			for task in tasks._tasks.values(): task.retry_at = 0
			_expect(await _phase(worker.TaskPhase.FETCH_DEPOSIT),"interrupted placement resumes with visible set-down")
			worker._process(1)
			_expect(furniture._installed.size()==1 and drops._loose.is_empty(),"resumed placement consumes one item")
	# Direct arrival from an existing carried-item handoff uses the same path.
	var handoff_plan = await _arrive(LOG_BENCH,2)
	worker._clear_item_handling()
	worker._fetch_travel_to_ghost()
	_expect(worker._task_phase==worker.TaskPhase.FETCH_DEPOSIT and is_zero_approx(worker._handling_elapsed),"already at stand begins one immediate set-down")
	worker._process(1)
	_expect(not furniture._ghosts.has(handoff_plan.ghost_id),"same-stand handoff finishes")

func _floor_excavation() -> void:
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	var mount = load("res://scripts/components/WallFurnitureMount.gd")
	var nav = root.get_node("NavGrid")
	var rooms = root.get_node("RoomManager")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for key in [TORCH,WALL]:
		for yaw in range(4):
			await _cleanup()
			var definition: Dictionary = furniture.get_defs()[key]
			support_cells = mount.supports(definition,SITE,yaw)
			for cell in support_cells: world.set_block(cell.x,cell.y,cell.z,stone)
			furniture._install(key,definition,SITE,yaw)
			var piece = furniture._installed.values()[0]
			var position: Vector3 = piece.node.position
			var heat: Dictionary = rooms._heat_cells.duplicate(true)
			var tiles: Array[Vector3i] = [SITE]
			mining._mine_blocks_world(tiles)
			await _frames(2)
			furniture._process(0)
			_expect(furniture._installed.has(piece.installed_id),"floor excavation preserves wall-mounted "+key+" yaw "+str(yaw))
			if furniture._installed.has(piece.installed_id):
				_expect(piece.node.position==position and rooms._heat_cells==heat,"mounted height and heat survive floor excavation")
				for item in drops._loose:
					_expect(drops._loose[item]!=definition.item_key,"excavating the floor refunds no torch")
				var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
				furniture._teardown_installed(piece.installed_id,false)
				for item in drops._loose.keys(): drops.take(item); item.free()
				furniture.restore_state(saved)
				furniture._revalidate_wall_mounts()
				_expect(furniture._installed.size()==1,"save restores a wall torch above the excavated floor")
			var support: Vector3i = support_cells[0]
			world.set_block(support.x,support.y,support.z,blocks.AIR_ID)
			await _frames(2)
			furniture._process(0)
			_expect(furniture._installed.is_empty() and rooms._heat_cells.is_empty(),"mining the actual bracket support still detaches the torch")
			var packed := 0
			for item in drops._loose:
				if drops._loose[item]==definition.item_key: packed += drops.quantity_of(item)
			_expect(packed==1,"only one packed torch is refunded")
			world.set_block(SITE.x,SITE.y,SITE.z,stone)
			nav.refresh_mined_block(SITE)
	# A floor edit may change work access, but never the mount's fixed position.
	await _cleanup()
	var definition: Dictionary = furniture.get_defs()[TORCH]
	support_cells = mount.supports(definition,SITE,0)
	for cell in support_cells: world.set_block(cell.x,cell.y,cell.z,stone)
	drops.restore_loose_item(String(definition.item_key),Vector3(50.5,21,44.5),0,1)
	furniture.activate_for(TORCH,true)
	furniture._hover_cell = SITE
	furniture._yaw = 0
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size()==1,"wall placement fixture starts with a floor and bracket")
	if not furniture._ghosts.is_empty():
		var ghost = furniture._ghosts.values()[0]
		world.set_block(SITE.x,SITE.y,SITE.z,blocks.AIR_ID)
		nav.refresh_mined_block(SITE)
		_expect(furniture._can_build_ghost(ghost),"pending installation can use another floor within reach")
		furniture._revalidate_wall_mounts()
		_expect(furniture._ghosts.size()==1,"floor excavation preserves a structurally valid pending wall mount")
	world.set_block(SITE.x,SITE.y,SITE.z,stone)
	mining.free()

func _capture_pose(key: String,yaw: int,label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or yaw!=0 or key not in [LOG_BENCH,WALL]: return
	root.size = Vector2i(960,720)
	camera.size = 8
	camera.position = Vector3(SITE)+Vector3(6,7,9)
	camera.look_at(Vector3(SITE)+Vector3(.5,2,.5))
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+key.get_slice(":",2)+"_"+label+".png")
