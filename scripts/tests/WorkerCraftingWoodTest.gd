extends "res://scripts/tests/WorkerCraftingTest.gd"

const OAK := "base:resources:wood:oak_log"
const APPLE := "base:resources:wood:apple_wood"
const JUNIPER := "base:resources:wood:juniper_log"
const WOOD_OUT := "res://tmp/worker_crafting_review/wood_filters"

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Wood selection test timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(WOOD_OUT)
	for key: String in [OAK,APPLE,JUNIPER]: drops.spawn_drop(key,1,Vector3i(40,21,40))
	var id: int = crafting.queue_order(BENCH_RECIPE,1)
	for i in range(10): await _tick()
	var order = crafting.get_order(id)
	_expect(order.allowed_ingredients==[PINE] and order.lease_id<0,"new orders default to Pine and wait despite other loose timber")
	_expect(crafting.ingredient_available(order.recipe,crafting.stock_snapshot(),order.allowed_ingredients)==0,"available count excludes disallowed species")
	drops.spawn_drop(PINE,1,Vector3i(43,21,41))
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"allowed Pine wakes waiting order")
	worker._process(.4)
	_expect(drops.item_key_of(worker._fetch_item)==PINE,"nearby Oak and Apple never substitute for Pine")
	var progress: float = order.progress
	crafting.set_allowed_ingredients(id,[JUNIPER])
	_expect(worker._carried_entries.is_empty() and _count(PINE)==1,"removing carried species returns its intact log")
	_expect(order.progress==progress,"changing wood preserves partial work")
	_expect(await _completed(id),"newly allowed Juniper completes the interrupted order")
	_expect(_count(OAK)==1 and _count(APPLE)==1 and _count(JUNIPER)==0,"only explicitly allowed wood is consumed")
	_clear_loose_wood()
	# Stored wood uses distance within the allowed set, not alphabetic species.
	for pair in [[OAK,40],[PINE,41],[APPLE,43]]:
		var cell := Vector3i(pair[1],20,44)
		zone.cell_stacks[cell] = {"item":pair[0],"count":1}
		drops.restore_stored_item(pair[0],cell,1)
	stockpiles.rebuild_totals()
	worker.position = Vector3(40.5,21,42.5)
	id = crafting.queue_order(BENCH_RECIPE,1,false,[APPLE,PINE])
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"allowed stored timber can be collected")
	_expect(drops.item_key_of(worker._fetch_item)==PINE,"stored Pine nearer than Apple wins despite alphabetical order")
	_expect(await _completed(id),"stored Pine batch completes")
	id = crafting.queue_order(BENCH_RECIPE,1)
	for i in range(10): await _tick()
	_expect(crafting.get_order(id).lease_id<0 and _count(OAK)==1 and _count(APPLE)==1,"exhausted Pine waits without withdrawing stored Oak or Apple")
	crafting.remove_order(id)
	# Containers participate in the same allowed-key and proximity lookup.
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(40,20,43)]
	container.setup_container({"storage":{"capacity":2}},cells)
	container.source_id = tasks.allocate_source_id()
	stockpiles.register_container(container)
	container.restore_inventory({PINE:1},drops)
	stockpiles.rebuild_totals()
	id = crafting.queue_order(BENCH_RECIPE,1,false,[APPLE,PINE])
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"allowed container timber can be collected")
	_expect(drops.item_key_of(worker._fetch_item)==PINE and container.stored_count()==0,"nearby allowed container beats farther stored Apple")
	crafting.remove_order(id)
	_expect(_count(PINE)==1 and _count(APPLE)==1,"cancel returns container timber without touching other species")
	_clear_loose_wood()
	container.restore_inventory({PINE:1},drops)
	container.suspended = true
	var fallback_cell := Vector3i(42,20,44)
	zone.cell_stacks[fallback_cell] = {"item":PINE,"count":1}
	drops.restore_stored_item(PINE,fallback_cell,1)
	stockpiles.rebuild_totals()
	id = crafting.queue_order(BENCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"suspended nearby container does not block other allowed storage")
	_expect(container.stored_count()==1,"suspended container retains its timber")
	_expect(await _completed(id),"farther allowed stored Pine completes while container is suspended")
	stockpiles.deregister_container(container)
	stockpiles.rebuild_totals()
	_clear_loose_wood()
	# Explicit Oak and Apple selection remains available to the player.
	id = crafting.queue_order(BENCH_RECIPE,1,false,[OAK])
	_expect(await _completed(id) and _count(OAK)==0,"explicitly selected Oak is a valid ingredient")
	id = crafting.queue_order(BENCH_RECIPE,1,false,[APPLE])
	_expect(await _completed(id) and _count(APPLE)==0,"explicitly selected Apple is a valid ingredient")
	var maintain_id: int = crafting.queue_order(TORCH_RECIPE,4,true,[PINE,JUNIPER])
	var same_id: int = crafting.queue_order(TORCH_RECIPE,8,true,[APPLE])
	_expect(same_id==maintain_id and crafting.orders.size()==1 and crafting.orders[0].allowed_ingredients==[APPLE],"updating maintain order also updates its material choice without duplicates")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(crafting.serialize_state()))
	crafting.restore_state(saved)
	_expect(crafting.orders[0].allowed_ingredients==[APPLE],"nondefault wood selection survives JSON round trip")
	crafting.restore_state({"orders":[{"recipe":BENCH_RECIPE,"quantity":1},
		{"recipe":TORCH_RECIPE,"quantity":1,"allowed_ingredients":[]},
		{"recipe":BENCH_RECIPE,"quantity":1,"allowed_ingredients":["base:resources:wood:oak_stave","missing:key"]}]})
	await _frames(2)
	_expect(crafting.orders[0].allowed_ingredients==[PINE],"pre-filter saves migrate conservatively to Pine")
	_expect(crafting.orders[1].allowed_ingredients.is_empty() and crafting.orders[2].allowed_ingredients.is_empty(),"empty or invalid saved choices never widen to other wood")
	for entry in crafting.orders.duplicate(): crafting.remove_order(entry.id)
	await _test_wood_menu()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("WORKER_WOOD_OK: Pine default, loose/stored/container filtering and proximity, opt-in species, active changes conserve timber/progress, maintain updates, save/migration and menu")
	quit(0 if failures.is_empty() else 1)

func _clear_loose_wood() -> void:
	for node in drops._loose.keys():
		if drops.item_key_of(node) in [PINE,OAK,APPLE,JUNIPER]: drops.take(node); node.free()

func _test_wood_menu() -> void:
	dock.open_crafting(BENCH_RECIPE)
	await _frames(6)
	_expect(panel._draft_ingredients[BENCH_RECIPE]==[PINE],"recipe draft starts with only Pine checked")
	_click(panel._wood.get_global_rect().get_center())
	await _frames(3)
	var popup: PopupMenu = panel._wood.get_popup()
	_expect(popup.visible and popup.item_count==4,"Allowed wood opens four species checkboxes")
	popup.id_pressed.emit(_wood_index(popup,JUNIPER))
	popup.id_pressed.emit(_wood_index(popup,PINE))
	_expect(panel._draft_ingredients[BENCH_RECIPE]==[JUNIPER],"checkboxes change recipe draft independently")
	popup.hide()
	panel.select_recipe(TORCH_RECIPE)
	_expect(panel._draft_ingredients[TORCH_RECIPE]==[PINE],"other recipe retains its own Pine default")
	panel.select_recipe(BENCH_RECIPE)
	await _frames(2)
	_click(panel._make.get_global_rect().get_center())
	await _frames(3)
	_expect(crafting.orders.size()==1 and crafting.orders[0].allowed_ingredients==[JUNIPER],"queue button copies selected wood onto the order")
	var order = crafting.orders[0]
	var row: Dictionary = panel._rows[order.id]
	_click(row.wood.get_global_rect().get_center())
	await _frames(2)
	var row_popup: PopupMenu = row.wood.get_popup()
	row_popup.id_pressed.emit(_wood_index(row_popup,JUNIPER))
	_expect(order.allowed_ingredients.is_empty() and crafting.status(order,crafting.stock_snapshot())=="Choose allowed wood","clearing an existing order waits without substitutions")
	row_popup.id_pressed.emit(_wood_index(row_popup,PINE))
	_expect(order.allowed_ingredients==[PINE],"queued order can be edited through its own wood menu")
	row_popup.hide()
	# Clearing the draft must disable submission, not mean 'any timber'.
	panel._open_wood_menu(panel._wood,-1)
	popup.id_pressed.emit(_wood_index(popup,JUNIPER))
	_expect(panel._make.disabled,"empty draft cannot submit a crafting order")
	popup.id_pressed.emit(_wood_index(popup,PINE))
	crafting.queue_order(TORCH_RECIPE,8,true,[PINE,JUNIPER])
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		await _frames(8)
		_expect(panel._detail_scroll.get_global_rect().encloses(panel._place.get_global_rect()),"material chooser keeps both crafting actions visible at %s" % viewport)
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(WOOD_OUT+"/crafting_%dx%d.png" % [viewport.x,viewport.y])
	_click(panel._wood.get_global_rect().get_center())
	await _frames(3)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(WOOD_OUT+"/allowed_wood_menu.png")
	popup.hide()

func _wood_index(popup: PopupMenu, key: String) -> int:
	for index in range(popup.item_count):
		if popup.get_item_metadata(index)==key: return index
	return -1
