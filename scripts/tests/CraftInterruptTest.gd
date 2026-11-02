extends "res://scripts/tests/WorkerCraftingTest.gd"

## An interrupted craft keeps its goods (owner report, 2026-10-30): a Worker fell asleep
## while making a hearth, a hauler carried its stones and logs back to storage, and the next
## Worker gathered them all again. Now the six goods stay beside the bench, claimed by the
## order, through a save and a load; the bench goes to the order above in turn; then a Worker
## lifts the last log and finishes the hearth with exactly those goods while hauling runs.
const HEARTH_RECIPE := "base:recipe:worker:hearth"
const HEARTH_ITEM := "base:resources:furniture:hearth"
var hauling_live := false
var kept: Array[int] = [] # instance ids of the six goods at the bench when the crafter fell asleep
var hauled := false
var resumed: Array[int] = [] # what the Worker who resumed the hearth carried

func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Craft interrupt timed out"); quit(1))
	await _setup_crafting_fixture()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(46,20,40),0)
	drops.spawn_drop(STONE,4,Vector3i(42,21,39))
	drops.spawn_drop(PINE,3,Vector3i(42,21,41))
	var hearth: int = crafting.queue_order(HEARTH_RECIPE,1)
	_expect(await _working(),"the hearth's four stones and two logs reach the bench")
	var order = crafting.get_order(hearth)
	worker._process(.5)
	var progress: float = order.progress
	var bench_id: int = order.bench_id
	var torch: int = crafting.queue_order(TORCH_RECIPE,1)
	for node: Node3D in order.staged_items: kept.append(node.get_instance_id())
	for cargo: Array in worker._carried_entries: kept.append((cargo[0] as Node3D).get_instance_id())
	_spawn_extra_worker()
	worker.dev_make_tired()
	worker._process(.01)
	hauling_live = true
	_expect(worker.is_sleeping() and order.worker_id<0 and is_equal_approx(order.progress,progress),"the crafter falls asleep and the order keeps its work")
	_expect(kept.size()==6 and _holds_kept(order),"all six goods, the log in hand included, stay beside the bench, claimed by the order")
	_expect(crafting.bench_claims.is_empty(),"the bench is free for the next order in turn")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(crafting.serialize_state()))
	var entry: Dictionary = saved.orders.filter(func(item: Dictionary): return int(item.id)==hearth)[0]
	_expect(entry.get("staged",[]).size()==6 and int(entry.get("bench",-1))==bench_id,"a save names the six goods and their bench")
	crafting.restore_state(saved)
	order = crafting.get_order(hearth)
	_expect(_holds_kept(order) and order.bench_id==bench_id and is_equal_approx(order.progress,progress),"a load claims the same goods beside the same bench")
	crafting.move_order(torch,-1)
	_expect(await _started()==torch,"the torch, now above the hearth, takes the free bench first")
	crafting._refresh()
	var waiting: String = crafting.status(order,crafting.stock_snapshot())
	_expect(waiting=="Next in line" and order.staged_items.size()==6,"the hearth waits its turn with its goods: %s" % waiting)
	_expect(await _completed(torch) and await _completed(hearth),"the torch, then the hearth, are finished")
	_expect(not hauled,"no hauler ever carried the hearth's goods away")
	_expect(resumed.size()==1 and resumed[0] in kept,"the Worker who resumed the hearth only lifted one kept log: %s of %s" % [resumed,kept])
	_expect(_count(HEARTH_ITEM)==1 and _count(TORCH_ITEM)==4 and _count(STONE)==0 and _count(PINE)==0,
		"the hearth is made from exactly the kept goods")
	for failure in failures: push_error(failure)
	print("CRAFT_INTERRUPT_OK" if failures.is_empty() else "CRAFT_INTERRUPT_FAIL")
	quit(0 if failures.is_empty() else 1)

## Once the crafter sleeps, hauling runs: loose goods are offered to the stockpile each tick.
func _tick() -> void:
	if not hauling_live:
		await super._tick()
		return
	zone.update_leases()
	await super._tick()
	var haul_phases := [worker.TaskPhase.HAUL_TO_ITEM, worker.TaskPhase.HAUL_PICKUP, worker.TaskPhase.HAUL_TO_ZONE, worker.TaskPhase.HAUL_DEPOSIT]
	for dwarf in [worker, extra_worker]:
		if not is_instance_valid(dwarf): continue
		var on_hearth: bool = crafting.orders.any(func(entry): return entry.worker_id==dwarf.dwarf_id and String(entry.recipe.id)==HEARTH_RECIPE)
		for cargo: Array in dwarf._carried_entries:
			var id: int = (cargo[0] as Node3D).get_instance_id()
			if id in kept and dwarf._task_phase in haul_phases: hauled = true
			if on_hearth and id not in resumed: resumed.append(id)

## The order holds exactly the six goods it had when the crafter fell asleep, claimed by it.
func _holds_kept(order) -> bool:
	var ids: Array[int] = []
	for node: Node3D in order.staged_items:
		if not drops.reserved_by(node,order.claim_owner_id()): return false
		ids.append(node.get_instance_id())
	ids.sort()
	var expected := kept.duplicate()
	expected.sort()
	return ids==expected

func _working() -> bool:
	for i in range(2000):
		if worker._task_phase==worker.TaskPhase.FETCH_WORKING: return true
		await _tick()
	return false

func _started() -> int:
	for i in range(800):
		for entry in crafting.orders:
			if entry.worker_id>=0: return entry.id
		await _tick()
	return -1

func _completed(id: int) -> bool:
	for i in range(2400):
		if crafting.get_order(id)==null: return true
		await _tick()
	return false

func _spawn_extra_worker() -> void:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(40.5,21,42.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
