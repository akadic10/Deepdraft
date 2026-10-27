extends "res://scripts/tests/WorkerCraftingTest.gd"

const BLUEBERRY := "base:resources:flora:blueberry"
const APPLE := "base:resources:flora:apple"
var second

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Food test timed out"); quit(1))
	await _setup_crafting_fixture()
	for node in drops._loose.keys(): drops.take(node); node.free()
	_expect(drops.edible_keys().size() == 5,"only five existing fruit types are edible")
	_expect(drops.food_definition(ACORN).is_empty() and drops.food_definition("base:resources:flora:plump_helmet").is_empty(),"seed and future food tags do not imply current edibility")
	await _clock_checks()
	_expect(worker.dev_make_hungry() and worker._food.hungry(),"development action triggers the ordinary hunger threshold")
	_store(BLUEBERRY,24)
	drops.spawn_drop(APPLE,3,worker.current_cell()+Vector3i.UP)
	_hungry(worker)
	_expect(await _food_phase("walking"),"hungry worker finds storage")
	_expect(worker._food._quote.key == BLUEBERRY,"stored fruit beats closer loose fruit")
	_expect(zone.contents().get(BLUEBERRY,0)==24 and zone._outgoing.size()==1,"walking reserves one portion but leaves the crate stored")
	var row: Dictionary = inventory_script.snapshot(drops,furniture)[BLUEBERRY]
	_expect(row.total==24 and row.available==23,"one stored portion is reserved in inventory")
	_expect(tasks.worker_availability(worker)=="Self-care" and not tasks._idle_dwarves.has(worker.dwarf_id),"food search is unavailable to job assignment")
	tasks._supervision._reconcile_workers()
	_expect(not tasks._idle_dwarves.has(worker.dwarf_id),"reconciliation preserves eating availability")
	_expect(await _food_phase("eating"),"worker physically reaches and collects fruit")
	_expect(zone.contents().get(BLUEBERRY,0)==23 and worker._carried_entries.size()==1,"pickup splits one fruit from the full crate")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	_expect(saved.carried_items.size()==1 and saved.carried_items[0].count==1 and saved.food.last_meal=="","mid-meal save owns one uneaten portion and grants no nutrition")
	var before: float = worker._food.value
	clock_node.set_paused(true)
	worker._process(20)
	_expect(worker._food.value==before and worker._food._elapsed==0,"pause freezes hunger and eating")
	clock_node.set_paused(false)
	worker._process(2)
	worker.force_interrupt()
	_expect(_food_total(BLUEBERRY)==24 and worker._carried_entries.is_empty() and zone._outgoing.is_empty(),"interrupted meal drops its whole portion and frees claims")
	worker.restore_saved_runtime(saved)
	_expect(is_equal_approx(worker._food.value,float(saved.food.value)),"hunger survives saved runtime restore")
	worker._food.retry_hours=0
	_expect(await _food_phase("eating"),"interrupted dwarf can eat again")
	await _finish_food()
	_expect(_food_total(BLUEBERRY)==23 and worker._food.value>.8 and worker._food.last_meal==BLUEBERRY,"completion consumes exactly one unit and restores nutrition")
	worker._process(.1)
	_expect(_food_total(BLUEBERRY)==23,"completion cannot consume twice")
	await _contention()
	await _removed_source()
	await _unreachable_storage()
	await _no_food()
	await _job_interrupt()
	await _stored_apple_meal()
	await _ui()
	for failure in failures: push_error(failure)
	print("DWARF_FOOD_OK: clock, sleep, stored/loose priority, portions, claims, cancellation, save, contention, routes, jobs, stored Apple and UI" if failures.is_empty() else "DWARF_FOOD_FAIL")
	quit(0 if failures.is_empty() else 1)

func _store(key: String, count: int) -> void:
	var cell := Vector3i(40,20,44)
	zone.cell_stacks[cell]={"item":key,"count":count}
	drops.restore_stored_item(key,cell,count)
	stockpiles._totals[key]=count

func _hungry(dwarf) -> void:
	if dwarf.is_eating(): dwarf._food.cancel()
	if dwarf.is_sleeping(): dwarf._wake_up()
	dwarf._idle_behavior.cancel()
	dwarf.stop_walking()
	dwarf.sleep=1.0
	dwarf._food.value=.3
	dwarf._food.retry_hours=0

func _food_phase(target: String, limit := 600) -> bool:
	for i in limit:
		if worker._food.state==target: return true
		worker._process(.05)
		await process_frame
	return false

func _finish_food() -> void:
	for i in 600:
		worker._process(.05)
		await process_frame
		if not worker.is_eating(): return
	_expect(false,"meal must finish within bounded time")

func _food_total(key: String) -> int:
	return int(inventory_script.snapshot(drops,furniture).get(key,{}).get("total",0))

func _clear_food() -> void:
	if worker.is_eating(): worker._food.cancel()
	if is_instance_valid(second):
		if second.is_eating(): second._food.cancel()
		tasks.deregister_dwarf(second.dwarf_id)
		second.free()
	worker._food.value=1.0
	worker.force_interrupt()
	for cell in zone.cell_stacks.keys():
		var node = drops.stored_node_at(cell)
		if is_instance_valid(node): node.free()
	zone.cell_stacks.clear()
	zone.release_storage_claims()
	stockpiles._totals.clear()
	for node in drops._loose.keys():
		node.set_meta("disallowed",false)
		drops.take(node)
		node.free()
	worker._idle_behavior.cancel()
	worker.stop_walking()
	worker.position=Vector3(40.5,21,39.5)

func _clock_checks() -> void:
	for speed: float in [1.0,2.0,3.0]:
		worker._food.value=1.0
		clock_node.set_speed(speed)
		worker._process(60.0/speed)
		_expect(is_equal_approx(worker._food.value,.925),"same hunger drain per game hour at x%s" % speed)
	clock_node.set_speed(0)
	var value: float=worker._food.value
	worker._process(60)
	_expect(worker._food.value==value,"zero speed freezes hunger")
	clock_node.set_speed(1)
	worker._begin_sleep()
	worker._process(60)
	_expect(is_equal_approx(worker._food.value,value-.075) and worker.is_sleeping(),"hunger advances during sleep without normal hunger waking the dwarf")
	worker._wake_up()
	worker._idle_behavior.cancel()
	worker.stop_walking()
	worker.position=Vector3(40.5,21,39.5)

func _contention() -> void:
	_clear_food()
	_store(BLUEBERRY,3)
	var factory=load("res://scripts/entities/DwarfFactory.gd").new()
	second=factory.spawn(factory.generate(142,{}),142)
	scene.add_child(second)
	second.position=Vector3(42.5,21,39.5)
	second.set_process(false)
	tasks.register_dwarf(second)
	_hungry(worker); _hungry(second)
	for i in 100:
		worker._process(.001); second._process(.001)
		await process_frame
		if worker._food.state=="walking" and second._food.state=="walking": break
	_expect(worker._food.state=="walking" and second._food.state=="walking" and int(zone._outgoing.values()[0].count)==2,"two dwarves reserve separate portions in the same crate")
	for i in 300:
		worker._process(.05); second._process(.05)
		await process_frame
	_expect(_food_total(BLUEBERRY)==1 and worker._food.value>.7 and second._food.value>.7,"shared crate feeds both dwarves and retains its final portion")
	_hungry(worker); _hungry(second)
	for i in 300:
		worker._process(.05); second._process(.05)
		await process_frame
	var meals:=int(worker._food.value>.7)+int(second._food.value>.7)
	_expect(meals==1 and _food_total(BLUEBERRY)==0,"two hungry workers cannot consume the same final portion")
	_expect(zone._outgoing.is_empty(),"contention leaves no stuck claim")

func _removed_source() -> void:
	_clear_food(); _store(BLUEBERRY,3); _hungry(worker)
	_expect(await _food_phase("walking"),"removal fixture begins reserved trip")
	zone.release_storage_claims()
	worker._process(.1)
	_expect(not worker.is_eating() and _food_total(BLUEBERRY)==3,"invalidated storage claim cancels without consuming food")
	_hungry(worker)
	_expect(await _food_phase("eating"),"removal fixture collects a real portion")
	tasks.deregister_dwarf(worker.dwarf_id)
	_expect(not worker.is_eating() and worker._carried_entries.is_empty() and _food_total(BLUEBERRY)==3,"removing an eater preserves its uneaten portion and releases self-care")
	tasks.register_dwarf(worker)

func _unreachable_storage() -> void:
	_clear_food(); _store(BLUEBERRY,3)
	var stone: int=blocks.get_id("base:terrain:rock:rock01")
	for x in range(38,43):
		for z in range(42,47):
			if x==38 or x==42 or z==42 or z==46:
				for y in range(21,25): world.set_block(x,y,z,stone)
	drops.spawn_drop(APPLE,3,Vector3i(40,21,38))
	_hungry(worker)
	_expect(await _food_phase("eating"),"unreachable storage permits harvested loose food")
	_expect(worker._food._quote.key==APPLE,"inaccessible stored crate cannot hide reachable loose fruit")
	await _finish_food()
	_expect(_food_total(APPLE)==2 and _food_total(BLUEBERRY)==3,"loose crate loses one portion only")
	for x in range(38,43):
		for z in range(42,47):
			if x==38 or x==42 or z==42 or z==46:
				for y in range(21,25): world.set_block(x,y,z,blocks.AIR_ID)

func _no_food() -> void:
	_clear_food()
	drops.spawn_drop(APPLE,1,Vector3i(40,21,38))
	var fruit: Node3D=drops._loose.keys()[0]
	fruit.set_meta("disallowed",true)
	_hungry(worker)
	worker._process(.05)
	await _finish_food()
	_expect(worker._food.message.contains("No reachable food") and worker._food.retry_hours>0,"no permitted food reports reason and backs off")
	_expect(tasks._idle_dwarves.has(worker.dwarf_id) and _food_total(APPLE)==1,"unsuccessful search returns to work without eating disallowed fruit")
	worker.sleep=0.0
	worker._process(.05)
	_expect(worker.is_sleeping(),"food shortage does not prevent needed sleep")
	worker._wake_up()

func _job_interrupt() -> void:
	_clear_food()
	drops.spawn_drop(PINE,1,Vector3i(42,21,39))
	var id: int=crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"real crafting job starts before hunger interrupt")
	_store(BLUEBERRY,3)
	_hungry(worker)
	worker._process(.05)
	_expect(worker.current_task_id<0 and worker._carried_entries.is_empty() and _count(PINE)==1,"hunger releases the job and drops its ingredient intact")
	_expect(await _food_phase("eating"),"interrupted worker collects a meal")
	await _finish_food()
	_expect(await _completed(id),"worker returns and completes the interrupted craft")

func _stored_apple_meal() -> void:
	_clear_food()
	_store(APPLE,4)
	_hungry(worker)
	_expect(await _food_phase("eating"),"dwarf eats stored Apple from the stockpile zone")
	await _finish_food()
	_expect(_food_total(APPLE)==3,"stored Apple meal consumes one portion and updates totals")

func _ui() -> void:
	var inspector=load("res://scripts/ui/DwarfInspectorPanel.gd").new()
	var layer:=CanvasLayer.new()
	scene.add_child(layer)
	layer.add_child(inspector)
	inspector.position=Vector2(20,20)
	inspector.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker),false)
	await _frames(3)
	_expect(inspector._food.title.text=="Food" and inspector._food.panel.tooltip_text.contains("Apple"),"the character sheet shows actual Food and the last meal")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/food_20261012/food_inspector.png")
