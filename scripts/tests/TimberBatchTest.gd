extends "res://scripts/tests/WorkerCraftingTest.gd"

const BED_RECIPE := "base:recipe:worker:log_bed"
const BED_ITEM := "base:resources:furniture:log_bed"
const OAK := "base:resources:wood:oak_log"

func _run() -> void:
	create_timer(140).timeout.connect(func(): push_error("Timber batch timeout"); quit(1))
	await _setup_crafting_fixture()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(45,20,42),0)
	drops.spawn_drop(PINE,3,Vector3i(42,21,42))
	drops.spawn_drop(OAK,2,Vector3i(49,21,42))
	var id: int = crafting.queue_order(BED_RECIPE,1,false,[PINE,OAK])
	for i in 20: await _tick()
	var order = crafting.get_order(id)
	_expect(order.lease_id<0 and order.worker_id<0 and _count(BED_ITEM)==0,"incomplete mixed wood cannot start a four-log bed")
	_expect(crafting.status(order,crafting.stock_snapshot())=="Waiting for 4 matching logs","waiting status explains matching batch cost")
	drops.spawn_drop(OAK,2,Vector3i(49,21,42))
	_expect(await _staged(id,1),"worker starts with complete oak batch instead of nearer incomplete pine")
	_expect(order.timber_key==OAK and drops.item_key_of(order.staged_items[0])==OAK,"first log locks the batch's wood")
	crafting.set_allowed_ingredients(id,[PINE])
	_expect(order.worker_id<0 and order.staged_items.is_empty() and _count(PINE)==3 and _count(OAK)==4,"changing wood between deliveries releases every log")
	drops.spawn_drop(PINE,1,Vector3i(42,21,42))
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"four pine logs reach the bench before work starts")
	_expect(order.staged_items.size()==3 and _count(PINE)==4,"three staged logs and one carried log remain physical")
	worker._process(.4)
	var progress: float = order.progress
	var saved_order: Dictionary = JSON.parse_string(JSON.stringify(crafting.serialize_state()))
	var saved_items: Dictionary = drops.serialize_state()
	var carried: Array = worker.serialize_state().carried_items
	_expect(saved_items.loose.filter(func(entry): return entry.item_key==PINE).size()==3 and carried.size()==1 and carried[0].item_key==PINE,"staged and carried logs serialize once through their owners")
	crafting.set_paused(id,true)
	_expect(_count(PINE)==4 and crafting.stock_snapshot()[PINE].available==4 and crafting.bench_claims.is_empty(),"pause returns all four intact logs")
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	drops.restore_state(saved_items)
	for cargo: Dictionary in carried:
		drops.restore_loose_item(cargo.item_key,worker.global_position,0,int(cargo.count))
	crafting.restore_state(saved_order)
	order = crafting.orders[0]
	_expect(_count(PINE)==4 and is_equal_approx(order.progress,progress),"load rebuilds physical batch and partial work without duplication")
	_expect(await _completed(order.id),"restored four-log bed completes")
	var packed: Node3D = drops.nearest_loose_of_key(BED_ITEM,worker.current_cell())
	_expect(_count(PINE)==0 and _count(OAK)==4 and _count(BED_ITEM)==1,"bed consumes exactly four selected logs")
	_expect(root.get_node("CraftMaterials").of_item(packed)=="base:material:pine","finished bed inherits the matching timber")
	# Logs occupy separate storage cells; each remains one physical heavy item.
	for node in drops._loose.keys():
		if drops.item_key_of(node)==OAK:
			drops.take(node)
			node.free()
	for x in range(40,44):
		var cell := Vector3i(x,20,44)
		zone.cell_stacks[cell]={"item":OAK,"count":1}
		drops.restore_stored_item(OAK,cell,1)
	stockpiles._totals[OAK] = 4
	id = crafting.queue_order(BED_RECIPE,1,false,[OAK])
	_expect(await _staged(id,2),"multiple logs withdraw from storage")
	crafting.remove_order(id)
	_expect(_count(OAK)==4 and worker._carried_entries.is_empty() and crafting.bench_claims.is_empty(),"cancelling between storage trips conserves all timber")
	id = crafting.queue_order(BED_RECIPE,1,true,[OAK])
	for i in 1200:
		await _tick()
		if _count(BED_ITEM)==2 and worker.current_task_id<0: break
	order = crafting.get_order(id)
	_expect(_count(OAK)==0 and _count(BED_ITEM)==2 and order.lease_id<0,"maintain crafts one matching bed using loose and stored logs, then stops")
	crafting.remove_order(id)
	# Two free benches must not commit the same six logs to two four-log beds.
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(51,20,42),0)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(48.5,21,40.5)
	extra_worker.set_process(false)
	extra_worker.sleep = 1.0
	tasks.register_dwarf(extra_worker)
	drops.spawn_drop(PINE,6,Vector3i(46,21,40))
	id = crafting.queue_order(BED_RECIPE,1)
	var second: int = crafting.queue_order(BED_RECIPE,1)
	var max_active := 0
	for i in 1400:
		await _tick()
		max_active = maxi(max_active,crafting.orders.filter(func(entry): return entry.worker_id>=0).size())
		if _count(BED_ITEM)==3 and worker.current_task_id<0 and extra_worker.current_task_id<0: break
	_expect(max_active==1 and _count(BED_ITEM)==3 and _count(PINE)==2,"competing workers complete one bed without splitting or over-consuming insufficient stock")
	crafting.remove_order(id)
	crafting.remove_order(second)
	dock.open_crafting()
	panel.select_recipe(BED_RECIPE)
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		await _frames(8)
		_expect(panel._requirements.text.begins_with("4 timber") and panel._requirements.text.contains("same wood"),"recipe card explains increased cost")
		_expect(panel._detail_scroll.get_global_rect().encloses(panel._make.get_global_rect()),"bed crafting action stays visible at "+str(viewport))
		if "--capture" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/bed_cost_20261011"))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/bed_cost_20261011/crafting_%d.png" % viewport.x)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TimberBatchTest: PASS — matching wood, physical delivery, interruption, save, storage, maintain, competing workers and cost UI")
	quit(0 if failures.is_empty() else 1)

func _staged(id: int, count: int) -> bool:
	for i in 900:
		var order = crafting.get_order(id)
		if order != null and order.staged_items.size()>=count: return true
		await _tick()
	return false
