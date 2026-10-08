extends "res://scripts/tests/HaulingAnimationTest.gd"

const BENCH := "base:furniture:crude_workbench"
const TORCH := "base:furniture:wooden_torch"
const BENCH_ITEM := "base:resources:furniture:crude_workbench"
const TORCH_ITEM := "base:resources:furniture:wooden_torch"
const BENCH_RECIPE := "base:recipe:worker:crude_workbench"
const TORCH_RECIPE := "base:recipe:worker:wooden_torch"
const PINE := "base:resources:wood:pine_log"
var inventory_script
var crafting
var dock
var panel
var extra_worker

func _setup_crafting_fixture() -> void:
	inventory_script = load("res://scripts/components/ColonyInventory.gd")
	await _setup_fixture()
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").heightmap.resize(1024*1024)
	root.get_node("WorldGenerator").heightmap.fill(20)
	root.get_node("WorldGenerator")._cache_block_ids()
	_build_review_world()
	# This fixture advances actual workers/scheduler deterministically; storage
	# hauling stays disabled until explicitly exercised below.
	for node in drops._loose.keys(): drops.take(node); node.free()
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.dock_ui_path = NodePath("../Dock")
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	crafting = load("res://scripts/systems/CraftingManager.gd").new()
	scene.add_child(crafting)
	crafting.set_process(false)
	panel = dock._craft_panel
	root.size = Vector2i(1280,720)
	await _frames(4)

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Worker crafting timed out"); quit(1))
	await _setup_crafting_fixture()
	var id: int = crafting.queue_order(TORCH_RECIPE,1)
	await _frames(2)
	_expect(crafting.get_order(id).lease_id < 0 and crafting.status(crafting.get_order(id),inventory_script.snapshot(drops,furniture)) == "Waiting for Pine", "missing ingredients wait without task churn")
	# Put the timber well away from the idle worker (e.g. at a felled tree,
	# while the worker accepted the order near the settlement flag).
	var timber_cell := Vector3i(50,20,41)
	var assigned_cell: Vector3i = worker.current_cell()
	drops.spawn_drop(PINE,3,timber_cell+Vector3i.UP)
	await _frames(2)
	_expect(crafting.get_order(id).lease_id < 0 and crafting.status(crafting.get_order(id),inventory_script.snapshot(drops,furniture)) == "Waiting for a free workbench", "torches require installed workshop")
	crafting.remove_order(id)
	id = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_PICKUP), "Worker reaches distant timber")
	var pickup_cell: Vector3i = worker.current_cell()
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(Vector3(pickup_cell-assigned_cell).length()>4,"fixture separates pickup from assignment position")
	_expect(inspection.describe(worker).destination.contains(inspection.location(timber_cell)),"pickup inspector shows the timber location")
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "Worker collects timber and starts bootstrap recipe")
	var order = crafting.get_order(id)
	_expect(order.work_cell==pickup_cell and worker.current_cell()==pickup_cell and not worker.is_walking(),"bootstrap crafts beside collected timber without returning to assignment position")
	_expect(inspection.describe(worker).destination=="Crafting spot\n"+inspection.location(pickup_cell),"bootstrap inspector shows live work spot, not placeholder zero coordinates")
	var progress: float = order.progress
	clock_node.set_paused(true)
	worker._process(2)
	_expect(order.progress == progress, "pause freezes crafting")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.25)
	_expect(is_equal_approx(order.progress,progress+.5), "craft work follows simulation speed")
	clock_node.set_speed(1)
	_expect(await _completed(id), "bootstrap crafting completes through normal scheduler")
	_expect(_count(BENCH_ITEM)==1 and _count(PINE)==2, "one timber becomes exactly one packed bench")
	var finished_bench: Node3D = drops.nearest_loose_of_key(BENCH_ITEM,pickup_cell)
	_expect(finished_bench!=null and drops.item_floor_cell(finished_bench)==pickup_cell,"finished workbench stays at the local crafting spot for hauling")
	furniture.activate_for(BENCH,true)
	furniture._hover_cell = Vector3i(45,20,42)
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size()==1,"finished bench can be placed from real stock")
	_expect(await _installed(BENCH), "Worker installs crafted bench through fetch/build")
	_expect(_count(BENCH_ITEM)==0,"install consumes packed bench")
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"placed bench enables torch work")
	order = crafting.get_order(id)
	_expect(inspection.describe(worker).destination=="Crude Workbench\n"+inspection.location(order.work_cell),"workshop recipe inspector shows the claimed stump's actual work position")
	worker._process(.8)
	if "--capture" in OS.get_cmdline_user_args():
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/worker_crafting_review/worker_at_bench.png")
	order = crafting.get_order(id)
	progress = order.progress
	_expect(crafting.bench_claims.size()==1,"working dwarf exclusively claims bench")
	_expect(inspection.roster_state(worker).summary=="Crafting","roster identifies crafting")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(crafting.serialize_state()))
	var carried: Array = worker.serialize_state().carried_items
	_expect(carried.size()==1 and carried[0].item_key==PINE,"save owns unconsumed carried ingredient once")
	crafting.set_paused(id,true)
	_expect(_count(PINE)==2 and crafting.bench_claims.is_empty(),"pause returns timber and releases workshop")
	_expect(order.progress==progress,"pause retains work progress")
	crafting.restore_state(saved)
	await _frames(2)
	order = crafting.orders[0]
	id = order.id
	_expect(is_equal_approx(order.progress,progress),"JSON restore retains partial progress without runtime claims")
	_expect(await _completed(id),"restored order resumes and completes")
	_expect(_count(TORCH_ITEM)==4 and _count(PINE)==1,"one timber produces exactly four packed torches")
	# Stored logs use the existing withdrawal ownership path.
	for node in drops._loose.keys():
		if drops.item_key_of(node)==PINE: drops.take(node); node.free()
	zone.cell_stacks[Vector3i(40,20,44)]={"item":PINE,"count":1}
	drops.restore_stored_item(PINE,Vector3i(40,20,44),1)
	stockpiles._totals[PINE] = 1
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"crafting withdraws timber from storage")
	worker._process(.4)
	crafting.remove_order(id)
	_expect(_count(PINE)==1 and worker._carried_entries.is_empty() and crafting.bench_claims.is_empty(),"cancel during work returns stored timber as loose goods")
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"returned timber can be reused")
	var bench = furniture._installed.values()[0]
	bench.set_uninstall(true)
	crafting._refresh()
	_expect(worker._carried_entries.is_empty() and _count(PINE)==1 and crafting.bench_claims.is_empty(),"uninstall interruption releases intact ingredient")
	bench.set_uninstall(false)
	crafting.remove_order(id)
	# Maintain spare goods; placement reservation reduces availability immediately.
	id = crafting.queue_order(TORCH_RECIPE,4,true)
	await _frames(3)
	_expect(crafting.get_order(id).lease_id<0,"maintain sleeps while spare target is met")
	_build_wall()
	furniture.activate_for(TORCH,true)
	furniture._yaw = 0
	furniture._hover_cell = Vector3i(48,20,46)
	_expect(furniture._placement_valid(furniture._hover_cell),"wooden torch fits a three-block-high tunnel")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.size()==1,"crafted wooden torch accepts valid wall mount")
	await _frames(3)
	_expect(crafting.get_order(id).lease_id>=0,"reserved torch wakes maintain order")
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"maintain begins replenishing")
	for i in range(600):
		await _tick()
		if _count(TORCH_ITEM)>=7 and worker.current_task_id<0: break
	_expect(_count(TORCH_ITEM)>=7 and _count(PINE)==0,"maintain replenishes in full four-torch batch")
	_expect(await _installed(TORCH),"crafted torch installed by Worker")
	var torch_piece = furniture._installed.values().filter(func(piece): return piece.furniture_key==TORCH)[0]
	_expect(torch_piece.node.find_children("*","OmniLight3D",true,false).size()==1,"installed wooden torch emits local light")
	_expect(crafting.get_order(id).lease_id<0,"maintain stops after meeting spare target")
	# Queue/inspector navigation and native responsive presentation.
	furniture.perform_explorer_action("installed:%d" % bench.installed_id,"craft")
	await _frames(5)
	_expect(manager.is_open("craft") and panel.selected==TORCH_RECIPE,"bench inspector opens crafting")
	panel._quantity.get_line_edit().text = "2"
	panel._mode.select(0)
	_click(panel._make.get_global_rect().get_center())
	await _frames(3)
	_expect(crafting.orders.size()==2 and crafting.orders[1].quantity==2,"menu queues real recipe batches")
	await _ui_capture()
	_click(panel._place.get_global_rect().get_center())
	await _frames(3)
	_expect(manager.is_open("place") and not manager.is_open("craft") and furniture.active_furniture_key()==TORCH,"craft menu hands finished items to real placement tool")
	furniture.deactivate()
	await _test_competing_workers()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("WORKER_CRAFTING_OK: bootstrap, bench installation, torch batch, conservation, pause/speed, partial save, cancellation, stored timber, uninstall, maintain stock, placement/light and menu")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	crafting._refresh()
	for ghost in furniture._ghosts.values(): ghost.update_lease()
	tasks._run_scheduler()
	worker._process(.05)
	if is_instance_valid(extra_worker): extra_worker._process(.05)
	await process_frame

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _phase(value: int) -> bool:
	for i in range(800):
		if worker._task_phase==value: return true
		await _tick()
	return false

func _completed(id: int) -> bool:
	for i in range(800):
		if crafting.get_order(id)==null: return true
		await _tick()
	return false

func _installed(key: String) -> bool:
	for i in range(800):
		for piece in furniture._installed.values():
			if piece.furniture_key==key: return true
		await _tick()
	return false

func _count(key: String) -> int:
	return int(inventory_script.snapshot(drops,furniture).get(key,{}).get("total",0))

func _build_wall() -> void:
	for x in range(46,51):
		for y in range(21,27): world.set_block(x,y,45,blocks.get_id("base:terrain:rock:rock01"))
		for z in range(46,49): world.set_block(x,24,z,blocks.get_id("base:terrain:rock:rock01"))
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	wall.mesh.size = Vector3(5,3,1)
	wall.position = Vector3(48.5,22.5,45.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("727b83")
	wall.material_override = material
	scene.add_child(wall)

func _ui_capture() -> void:
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		await _frames(8)
		var rect: Rect2 = dock._craft_window.get_global_rect()
		_expect(rect.end.x <= viewport.x and rect.end.y <= dock._dock_panel.position.y-8,"craft window fits above dock at %s" % viewport)
		_expect(panel._make.get_global_rect().size.x>=150,"craft action remains usable")
		_expect(panel._detail_scroll.get_global_rect().encloses(panel._make.get_global_rect()),"queue action visible without scrolling")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/worker_crafting_review/crafting_%dx%d.png" % [viewport.x,viewport.y])

func _test_competing_workers() -> void:
	for order in crafting.orders.duplicate(): crafting.remove_order(order.id)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(43.5,21,42.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	drops.spawn_drop(PINE,2,Vector3i(43,21,41))
	crafting.queue_order(TORCH_RECIPE,1)
	crafting.queue_order(TORCH_RECIPE,1)
	for i in range(500):
		await _tick()
		if crafting.orders.any(func(order): return order.progress>.3): break
	var active: Array = crafting.orders.filter(func(order): return order.worker_id>=0)
	_expect(active.size()==1 and crafting.bench_claims.size()==1,"two Workers and two orders never share one bench")
	if active.is_empty(): return
	var order = active[0]
	var agent = tasks._agents[order.worker_id]
	var progress: float = order.progress
	agent.dev_make_tired()
	agent._process(.01)
	_expect(_count(PINE)==2 and crafting.bench_claims.is_empty(),"sleep releases crafting timber and bench")
	_expect(order.progress==progress,"sleep retains completed crafting work")
	# Cancel a pending reservation before contact as well as a carried job.
	for entry in crafting.orders.duplicate(): crafting.remove_order(entry.id)
	crafting.queue_order(TORCH_RECIPE,1)
	for i in range(200):
		await _tick()
		if not drops._reserved.is_empty(): break
	for entry in crafting.orders.duplicate(): crafting.remove_order(entry.id)
	_expect(_count(PINE)==2 and drops._reserved.is_empty() and crafting.bench_claims.is_empty(),"cancellation before pickup conserves both logs and frees claims")

func _build_review_world() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(55,1,55)
	mesh.position = Vector3(40,20.5,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("748475")
	mesh.material_override = material
	scene.add_child(mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-25,0)
	light.shadow_enabled = true
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("34403e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	scene.add_child(camera)
	camera.position = Vector3(55,34,57)
	camera.look_at(Vector3(44,22,42))
	camera.current = true
