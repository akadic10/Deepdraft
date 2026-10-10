extends "res://scripts/tests/WorkerCraftingTest.gd"

const HOE := "base:recipe:worker:stone_hoe"

class SlowQuote extends RefCounted:
	var source: RefCounted
	func scheduling_signature() -> Array: return source.scheduling_signature()
	func advance_worker_quote(from: Vector3i, query: Dictionary, deadline: int, excluded: Dictionary) -> bool:
		var done: bool = source.advance_worker_quote(from,query,deadline,excluded)
		if done: OS.delay_usec(2000)
		return done

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Crafting selection timed out"); quit(1))
	await _setup_crafting_fixture()
	_fresh_workers()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(41,20,42),0)
	drops.spawn_drop(PINE,1,Vector3i(42,21,40))
	drops.spawn_drop(STONE,1,Vector3i(55,21,40))
	var id: int = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==extra_worker.dwarf_id and worker.current_task_id<0,
		"Hilka beside the stone wins over Keltin, first in the idle queue and closer to the bench")
	_expect(await _completed(id),"nearby winner completes both ingredient trips and the real tool batch")
	_expect(_count("base:resources:tools:stone_hoe")==1 and _count(STONE)==0 and _count(PINE)==0,
		"assignment and exact pickup conserve all inputs and output")
	await _recipes_and_storage()
	await _eligibility()
	await _blocked_routes()
	await _yield_and_invalidation()
	for failure in failures: push_error(failure)
	print("CRAFTING_SELECTION_OK" if failures.is_empty() else "CRAFTING_SELECTION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _dispatch_order(id: int) -> void:
	for i in range(500):
		crafting._refresh()
		var before: int = tasks._probes_total
		tasks._run_scheduler()
		_expect(tasks._probes_total-before <= tasks._max_probes_per_wake,"craft comparison respects the per-wake probe cap")
		if crafting.get_order(id).worker_id>=0: return
		await process_frame

func _fresh_workers() -> void:
	for order in crafting.orders.duplicate(): crafting.remove_order(order.id)
	for agent in [worker,extra_worker]:
		if not is_instance_valid(agent): continue
		tasks.deregister_dwarf(agent.dwarf_id)
		agent.free()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(141,{}),141)
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	for agent in [worker,extra_worker]:
		scene.add_child(agent)
		agent.set_process(false)
		agent.sleep = 1.0
		tasks.register_dwarf(agent)
	worker.position = Vector3(40.5,21,39.5)
	extra_worker.position = Vector3(54.5,21,40.5)
	for node in drops._loose.keys(): drops.take(node); node.free()
	tasks._max_probes_per_wake = 1
	tasks._budget_usec = 1000

func _supply() -> void:
	drops.spawn_drop(PINE,1,Vector3i(42,21,40))
	drops.spawn_drop(STONE,1,Vector3i(55,21,40))

func _recipes_and_storage() -> void:
	for recipe in crafting.recipes.values():
		_fresh_workers()
		drops.spawn_drop(PINE,1,Vector3i(55,21,40))
		drops.spawn_drop(STONE,1,Vector3i(55,21,41))
		var id: int = crafting.queue_order(String(recipe.id),1)
		await _dispatch_order(id)
		_expect(crafting.get_order(id).worker_id==extra_worker.dwarf_id,
			String(recipe.id)+": all Worker recipes compare ingredient proximity")
	_fresh_workers()
	# Closer stored material must beat distant loose material as well.
	worker.position = Vector3(55.5,21,37.5)
	extra_worker.position = Vector3(40.5,21,43.5)
	_supply()
	var slot := Vector3i(40,20,44)
	zone.cell_stacks[slot] = {"item":STONE,"count":1}
	drops.restore_stored_item(STONE,slot,1)
	stockpiles.rebuild_totals()
	var id: int = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==extra_worker.dwarf_id and not zone.cell_stacks.has(slot),
		"stored stone beside later idle worker beats farther loose stone")
	_fresh_workers()
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(55,20,40)]
	container.setup_container({"storage":{"capacity":2}},cells)
	container.source_id = tasks.allocate_source_id()
	stockpiles.register_container(container)
	container.restore_inventory({STONE:1},drops)
	stockpiles.rebuild_totals()
	drops.spawn_drop(PINE,1,Vector3i(42,21,40))
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==extra_worker.dwarf_id and container.stored_count()==0,
		"container quote matches its real withdrawal location and chooses the nearby worker")
	_expect(await _completed(id),"container material follows the proven pickup and delivery routes")
	stockpiles.deregister_container(container)
	stockpiles.rebuild_totals()

func _eligibility() -> void:
	_fresh_workers()
	_supply()
	extra_worker.set_work_permission("craft",false)
	var id: int = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==worker.dwarf_id,"near worker with Craft disabled is excluded")
	extra_worker.set_work_permission("craft",true)
	tasks._run_scheduler()
	_expect(crafting.get_order(id).worker_id==worker.dwarf_id,"newly eligible closer dwarf does not steal an active batch")
	_fresh_workers()
	_supply()
	extra_worker.dev_make_tired()
	extra_worker._process(.1)
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(extra_worker.is_sleeping() and crafting.get_order(id).worker_id==worker.dwarf_id,"sleeping nearby worker is excluded")
	_fresh_workers()
	_supply()
	worker.position = Vector3(56.5,21,40.5)
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==worker.dwarf_id,"equal pickup distance keeps stable idle-order ties")
	_fresh_workers()
	_supply()
	# Register the near worker first so the higher-priority bucket claims her.
	tasks.deregister_dwarf(worker.dwarf_id)
	tasks.register_dwarf(worker)
	var priority: int = tasks._static_priorities.BUILD
	tasks._static_priorities.BUILD = 90
	var urgent: int = tasks.add_task(Task.Type.BUILD,Vector3i(54,20,41))
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(extra_worker.current_task_id==urgent and crafting.get_order(id).worker_id==worker.dwarf_id,
		"higher-priority work runs before crafting proximity")
	tasks._static_priorities.BUILD = priority
	tasks.cancel_task(urgent)

func _walls(columns: Array[Vector2i], build: bool) -> void:
	var block: int = blocks.get_id("base:terrain:rock:rock01") if build else blocks.AIR_ID
	for column in columns:
		for y in range(21,25): world.set_block(column.x,y,column.y,block)
	await process_frame
	await process_frame

func _blocked_routes() -> void:
	_fresh_workers()
	_supply()
	extra_worker.position = Vector3(54.5,21,38.5)
	var walls: Array[Vector2i] = [Vector2i(53,38),Vector2i(55,38),Vector2i(54,37),Vector2i(54,39)]
	await _walls(walls,true)
	var id: int = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	_expect(crafting.get_order(id).worker_id==worker.dwarf_id,"unreachable near worker cannot hide a reachable distant worker")
	await _walls(walls,false)
	_fresh_workers()
	_supply()
	extra_worker.set_work_permission("craft",false)
	drops.spawn_drop(STONE,1,Vector3i(42,21,43))
	walls = [Vector2i(41,43),Vector2i(43,43),Vector2i(42,42),Vector2i(42,44)]
	await _walls(walls,true)
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	var order = crafting.get_order(id)
	_expect(order.worker_id==worker.dwarf_id and drops.item_floor_cell(order.item)==Vector3i(55,20,40),
		"blocked closest pile is skipped and executor reserves exactly the reachable quoted pile")
	await _walls(walls,false)
	_fresh_workers()
	_supply()
	# The original bench has no open edge. A farther bench remains usable.
	walls = [Vector2i(40,42),Vector2i(42,42),Vector2i(41,41),Vector2i(41,43)]
	await _walls(walls,true)
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(60,20,42),0)
	id = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	order = crafting.get_order(id)
	_expect(order.worker_id==extra_worker.dwarf_id and order.work_cell.x>=59,
		"reachable alternative workbench is proved from the pickup")
	_expect(await _completed(id),"proven alternate bench completes a real batch")
	await _walls(walls,false)

func _yield_and_invalidation() -> void:
	_fresh_workers()
	_supply()
	var id: int = crafting.queue_order(HOE,1)
	crafting._refresh()
	var order = crafting.get_order(id)
	var slow := SlowQuote.new()
	slow.source = order
	tasks.register_work_source(order.source_id,slow)
	for i in range(30):
		tasks._run_scheduler()
		if int(tasks._craft_match.get("index",0))>=1: break
		await process_frame
	_expect(order.worker_id<0 and drops._reserved.is_empty() and crafting.bench_claims.is_empty(),
		"yielding worker comparison creates no early item or bench reservations")
	tasks.register_work_source(order.source_id,order)
	# The first candidate's quote already exists. Changing stock must discard it.
	var stone: Node3D = drops.nearest_loose_of_key(STONE,Vector3i(55,20,40))
	drops.take(stone)
	stone.free()
	drops.spawn_drop(STONE,1,Vector3i(40,21,40))
	await _dispatch_order(id)
	_expect(order.worker_id==worker.dwarf_id,"material movement invalidates a partially ranked comparison")
	_fresh_workers()
	_supply()
	tasks.notify_dwarf_unavailable(extra_worker.dwarf_id)
	id = crafting.queue_order(HOE,1)
	crafting._refresh()
	order = crafting.get_order(id)
	slow.source = order
	tasks.register_work_source(order.source_id,slow)
	tasks._run_scheduler()
	tasks.register_work_source(order.source_id,order)
	tasks.notify_dwarf_idle(extra_worker.dwarf_id)
	await _dispatch_order(id)
	_expect(order.worker_id==extra_worker.dwarf_id,"newly idle nearby worker joins a yielded comparison")
	_fresh_workers()
	_supply()
	id = crafting.queue_order(HOE,1)
	crafting._refresh()
	order = crafting.get_order(id)
	slow.source = order
	tasks.register_work_source(order.source_id,slow)
	tasks._run_scheduler()
	tasks.register_work_source(order.source_id,order)
	crafting.remove_order(id)
	tasks._run_scheduler()
	_expect(worker.current_task_id<0 and extra_worker.current_task_id<0 and drops._reserved.is_empty(),
		"cancel during comparison cannot claim stale work")
	tasks.reset_runtime_state()
	_expect(tasks._craft_match.is_empty(),"scene reset clears partial crafting comparisons")
