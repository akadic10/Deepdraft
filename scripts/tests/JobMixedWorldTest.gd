extends "res://scripts/tests/LadderTest.gd"

const CAMP := "base:furniture:campfire"
const CAMP_ITEM := "base:resources:furniture:campfire"
var crew: Array[Node3D] = []
var frozen := {}
var injected := {}
var seen := {}
var surface: RefCounted
var mine: RefCounted
var water: Node
var flooded := Vector3i(-1,-1,-1)
var had_camp := false
var sleep_injected := false
var frame_number := 0
var checked := 0

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Mixed jobs timed out"); quit(1))
	await _setup_crafting_fixture()
	ladders = furniture._ladders
	ladders.set_process(false)
	nav = root.get_node("NavGrid")
	_build_cliff()
	crew.append(worker)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for id in range(142,145):
		var agent = factory.spawn(factory.generate(id,{}),id)
		scene.add_child(agent)
		agent.position = Vector3(37.5+(id-142)*2,21,38.5)
		agent.set_process(false)
		agent.sleep = 1.0
		tasks.register_dwarf(agent)
		crew.append(agent)
	for cell: Vector3i in [Vector3i(40,20,44),Vector3i(41,20,44)]:
		zone.cell_stacks[cell] = {"item":SECTION,"count":1,"material_id":"base:material:pine"}
		drops.restore_stored_item(SECTION,cell,1,"",false,"base:material:pine")
	stockpiles.rebuild_totals()
	ladders.restore_state({"next_id":2,"routes":[{"id":1,"key":LADDER,"base":[48,20,48],"yaw":0,
		"height":12,"built":4,"mode":"build","progress":0.0,"materials":["base:material:pine"],"required_material_id":""}]})
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	var cells: Array[Vector3i] = [Vector3i(50,32,45)]
	mine = tasks.get_work_source(mining._create_zone(cells))
	drops.restore_loose_item(CAMP_ITEM,Vector3(44.5,21,39.5),0,1)
	furniture.activate_for(CAMP,true)
	furniture._hover_cell = Vector3i(39,20,49)
	furniture._confirm_ghost()
	furniture.deactivate()
	root.get_node("WorldGenerator")._maps_ready = false
	drops.spawn_drop(PINE,1,Vector3i(42,21,41))
	var craft_id: int = crafting.queue_order(BENCH_RECIPE,1)
	drops.spawn_drop(ACORN,7,Vector3i(36,21,43))
	surface = load("res://scripts/components/TreeFellingComponent.gd").new()
	surface.origin = Vector3i(35,20,45)
	surface.duration = 3.0
	surface.state = {"designated":true,"work_seconds":0.0}
	surface.source_id = tasks.allocate_source_id()
	surface.complete_callback = func(_worker: int):
		surface.state.felled = true
		drops.spawn_drop(STONE,1,surface.origin+Vector3i.UP)
		return true
	tasks.register_work_source(surface.source_id,surface)
	tasks.task_released.connect(func(task: Task,id: int,_reason: int):
		if task.source_id==surface.source_id: surface.release_worker(id))
	tasks.task_completed.connect(func(task: Task):
		if task.source_id==surface.source_id: surface.on_task_gone(task))
	surface.ensure_lease()
	water = root.get_node("WaterManager")
	water.set_process(false)
	water._config = root.get_node("WorldGenerator").load_water_profile()
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_col: Vector2i): return [Vector2i(21,128)]
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water._water_id = blocks.get_id("base:terrain:water:source")
	water.initialized = true
	tasks._probe_node_cap = 5
	tasks._max_probes_per_wake = 2
	for tick in range(5000):
		frame_number = tick
		await _tick()
		if had_camp and furniture._installed.is_empty() and ladders.routes[1].built==12 and mine.remaining_count()==0 \
				and crafting.get_order(craft_id)==null and bool(surface.state.get("felled",false)) and tasks._active.is_empty(): break
	_expect(had_camp and furniture._installed.is_empty() and _count(CAMP_ITEM)==1,"placement and uninstall both finish, recovering exactly one kit")
	_expect(ladders.routes[1].built==12 and _count(SECTION)==0,"access construction survives interruptions and consumes two paid kits")
	_expect(mine.remaining_count()==0,"mining waiting on access eventually completes")
	_expect(crafting.get_order(craft_id)==null and _count(BENCH_ITEM)==1 and _count(PINE)==0,"craft output and ingredients remain conserved")
	_expect(_count(ACORN)==7 and bool(surface.state.get("felled",false)),"hauling and surface work finish without quantity loss")
	_expect(injected.size()==7,"faults reached haul, craft, mine, surface, furniture, ladder and uninstall executors: %s"%str(injected.keys()))
	_expect(sleep_injected and flooded.x>=0,"mixed scenario exercises sleep and a live water route edit")
	print("MIXED_JOB_METRICS ",{"sim_seconds":tasks.journal.now,"invariant_checks":checked,"faults":injected.keys(),"scheduler":tasks.get_scheduler_stats()})
	for failure: String in failures: push_error(failure)
	print("JOB_MIXED_WORLD_OK" if failures.is_empty() else "JOB_MIXED_WORLD_FAIL")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	var step := .1
	ladders._process(step)
	crafting._refresh()
	furniture._process(step)
	zone.update_leases()
	tasks.advance_supervision(step)
	tasks._run_scheduler()
	for agent in crew:
		var task = tasks.get_task(agent.current_task_id)
		if task != null:
			var family := Task.type_name(task.type)
			var source = tasks.get_work_source(task.source_id)
			if source != null and source.get_script().resource_path.ends_with("LadderBuildComponent.gd"): family = "ladder"
			seen[family] = true
			if not injected.has(family):
				injected[family] = true
				frozen[agent.dwarf_id] = {"task":task.id,"generation":task.attempt.generation,"until":tasks.journal.now+15.0}
		if frozen.has(agent.dwarf_id):
			var freeze: Dictionary = frozen[agent.dwarf_id]
			if task != null and task.id==freeze.task and task.attempt.generation==freeze.generation and tasks.journal.now<freeze.until: continue
			frozen.erase(agent.dwarf_id)
		if not sleep_injected and frame_number>180 and agent.current_task_id<0 and nav.is_walkable(agent.current_cell()):
			agent.dev_make_tired()
			agent._process(step)
			agent._sleep_hours_left = .1
			sleep_injected = true
		agent._process(step)
		if flooded.x<0 and frame_number>200 and not agent._move_path.is_empty():
			var cell: Vector3i = agent._move_path.back()
			if cell.y==20 and crew.all(func(other): return other.current_cell()!=cell):
				flooded = cell+Vector3i.UP
				water.flow.add_at(flooded,1.0,22.0)
				water._flush_changes()
				_expect(not nav.is_walkable(cell),"water invalidates a real pending destination")
	if frame_number==600 and flooded.x>=0:
		water.reset()
		water.levels_changed.emit([flooded])
	for piece in furniture._installed.values():
		if piece.furniture_key==CAMP:
			had_camp = true
			piece.set_uninstall(true)
	var errors: Array = tasks.lifecycle_errors()
	if not errors.is_empty():
		_expect(false,"lifecycle invariant: %s"%str(errors))
		quit(1)
	checked += 1
	await process_frame
