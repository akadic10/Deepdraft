extends "res://scripts/tests/WorkerCraftingTest.gd"

const KIT := "base:resources:tools:carpentry_kit"
const CARPENTER := "base:profession:carpenter"
const WORKER := "base:profession:worker"
const MINER := "base:profession:miner"
var director
var promotion

func _run() -> void:
	create_timer(110).timeout.connect(func(): push_error("Tool promotion timed out"); quit(1))
	await _setup_crafting_fixture()
	_expect(not worker.change_profession(CARPENTER) and worker.profession == WORKER, "API rejects Carpenter without a real available kit")
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45,20,42), 0)
	drops.spawn_drop(PINE, 1, Vector3i(42,21,42))
	drops.spawn_drop(STONE, 1, Vector3i(44,21,44))
	var order: int = crafting.queue_order("base:recipe:worker:carpentry_kit", 1)
	_expect(await _completed(order), "Worker crafts the promotion kit from real timber and stone")
	worker.position = Vector3(40.5,21,39.5)
	worker.sleep = 1.0
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	extra_worker = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(extra_worker)
	extra_worker.position = Vector3(41.5,21,39.5)
	extra_worker.set_process(false)
	tasks.register_dwarf(extra_worker)
	_expect(worker.change_profession(CARPENTER), "Carpenter request accepted with spare kit")
	_expect(extra_worker.change_profession(CARPENTER), "competing request may begin before either reserves")
	_expect(worker.profession == WORKER and worker.promotion_pending(), "promotion waits for physical pickup")
	_expect(await _equipment_stage("walking"), "appointment finds and reserves a reachable kit")
	var kit: Node3D = worker._equipment.item
	_expect(drops.reserved_by(kit, worker.dwarf_id), "one exact physical kit is reserved")
	_expect(not worker.dwarf_id in tasks._idle_dwarves and tasks._types_for(worker).is_empty(), "pending appointment cannot receive general work")
	tasks.notify_dwarf_idle(worker.dwarf_id)
	_expect(not worker.dwarf_id in tasks._idle_dwarves, "stray idle wake cannot steal appointment")
	_expect(await _equipment_stage("pickup"), "dwarf walks to kit before pickup")
	var time: float = worker._equipment._elapsed
	clock_node.set_paused(true)
	worker._process(3)
	_expect(worker._equipment._elapsed == time and worker.profession == WORKER, "pause freezes appointment pickup")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	worker._process(.1)
	_expect(is_equal_approx(worker._equipment._elapsed, time + .2), "pickup follows simulation speed")
	clock_node.set_speed(1)
	_expect(await _appointed(), "promotion completes only after pickup")
	_expect(not extra_worker.promotion_pending() and extra_worker.profession == WORKER, "competing dwarf cannot acquire the same kit")
	_expect(worker._equipment.equipped == kit and kit.get_parent() == worker, "actual crafted item is retained as owned equipment")
	var stock: Dictionary = crafting.stock_snapshot()[KIT]
	_expect(stock.total == 1 and stock.equipped == 1 and stock.available == 0 and stock.carried == 0, "equipped kit counts once, unavailable to new orders")
	_expect(worker._carried_entries.is_empty(), "equipped tool does not masquerade as carried cargo")
	_expect(worker.serialize_state().equipment.tool == KIT and drops.serialize_state().loose.is_empty(), "equipment has exactly one save owner")
	_expect(not worker.change_profession("base:profession:farmer"), "other specialist roles remain planned")
	_expect(worker.change_profession(WORKER) and drops._loose.has(kit), "changing back physically returns the same kit")
	_expect(_count(KIT) == 1 and crafting.stock_snapshot()[KIT].available == 1, "role change does not create or lose a kit")
	# Both sides of pickup contact must release safely.
	for after_contact in [false, true]:
		_expect(worker.change_profession(CARPENTER), "new request after returned tool")
		_expect(await _equipment_stage("pickup"), "request reaches pickup")
		if after_contact: worker._process(.35)
		var state: Dictionary = worker.serialize_state()
		_expect(state.equipment.pending_role == CARPENTER and state.equipment.tool == "", "in-flight save remains current profession with appointment intent")
		_expect(state.carried_items.size() == (1 if after_contact else 0), "contact transfers save ownership from loose goods to dwarf")
		worker._equipment.cancel()
		_expect(not worker.promotion_pending() and worker.profession == WORKER and _count(KIT) == 1, "cancellation preserves role and kit before/after contact")
		_expect(crafting.stock_snapshot()[KIT].available == 1 and worker._carried_entries.is_empty(), "cancelled appointment releases cargo/reservation")
	# Sleep cancellation and stale source invalidation.
	worker.change_profession(CARPENTER)
	await _equipment_stage("pickup")
	worker._begin_sleep()
	_expect(not worker.promotion_pending() and crafting.stock_snapshot()[KIT].available == 1 and not worker.dwarf_id in tasks._idle_dwarves, "sleep safely releases appointment without waking worker")
	_expect(not worker.change_profession(CARPENTER), "sleeping dwarf cannot be sent for a tool")
	worker._wake_up()
	worker.change_profession(CARPENTER)
	await _equipment_stage("walking")
	drops.unreserve(worker._equipment.item, worker.dwarf_id)
	worker._process(.05)
	_expect(not worker.promotion_pending() and _count(KIT) == 1, "lost reservation stops appointment without stealing tool")
	worker.change_profession(CARPENTER)
	await _equipment_stage("walking")
	worker.walk_to(Vector3i(40,20,40))
	_expect(not worker.promotion_pending() and crafting.stock_snapshot()[KIT].available == 1, "explicit movement cancels promotion and releases its reservation")
	worker.stop_walking()
	# A sealed nearest kit must not hide a farther reachable one.
	kit = drops.nearest_loose_of_key(KIT, worker.current_cell())
	kit.position = Vector3(48.5,21,47.5)
	for x in range(47,51):
		for z in range(46,50):
			for y in range(21,25): world.set_block(x,y,z,blocks.get_id("base:terrain:rock:rock01"))
	worker.position = Vector3(46.5,21,43.5)
	_expect(worker.change_profession(CARPENTER), "sealed tool is owned but needs a route check")
	_expect(not await _appointed() and not worker.promotion_pending(), "all unreachable tools fail cleanly without locking dwarf")
	_expect(crafting.stock_snapshot()[KIT].available == 1 and worker.dwarf_id in tasks._idle_dwarves, "unreachable promotion leaves kit and worker available")
	drops.restore_loose_item(KIT, Vector3(39.5,21,39.5), 0, 1)
	_expect(worker.change_profession(CARPENTER) and await _appointed(), "blocked nearest tool yields to reachable alternative")
	worker.change_profession(WORKER)
	drops.take(kit)
	kit.free()
	# Ground storage and container storage both use real withdrawal ownership.
	for container_mode in [false, true]:
		kit = drops.nearest_loose_of_key(KIT, worker.current_cell())
		drops.take(kit)
		kit.free()
		var container
		if container_mode:
			container = load("res://scripts/components/ContainerStorageComponent.gd").new()
			var cells: Array[Vector3i] = [Vector3i(43,20,40)]
			container.setup_container({"storage":{"capacity":2}}, cells)
			container.source_id = tasks.allocate_source_id()
			stockpiles.register_container(container)
			container.restore_inventory({KIT:1}, drops)
		else:
			zone.cell_stacks[Vector3i(40,20,44)] = {"item":KIT,"count":1}
			drops.restore_stored_item(KIT, Vector3i(40,20,44), 1)
		stockpiles.rebuild_totals()
		_expect(worker.change_profession(CARPENTER) and await _appointed(), "promotion collects tool from " + ("container" if container_mode else "stockpile"))
		_expect(crafting.stock_snapshot()[KIT].equipped == 1 and crafting.stock_snapshot()[KIT].stored == 0, "withdrawal transfers single ownership")
		worker.change_profession(WORKER)
		if container_mode: stockpiles.deregister_container(container)
	# Save/load equipped and pending at both contact phases, using real owners.
	worker.change_profession(CARPENTER)
	await _appointed()
	await _reload_worker(factory)
	_expect(worker.profession == CARPENTER and crafting.stock_snapshot()[KIT].equipped == 1 and _count(KIT) == 1, "equipped tool survives JSON save restoration once")
	worker.change_profession(WORKER)
	for contact in [false, true]:
		worker.change_profession(CARPENTER)
		await _equipment_stage("pickup")
		if contact: worker._process(.35)
		await _reload_worker(factory)
		_expect(worker.profession == WORKER and worker.promotion_pending() and _count(KIT) == 1, "pending snapshot restores one tool and retains old role")
		_expect(await _appointed(), "restored appointment reacquires physical kit")
		worker.change_profession(WORKER)
	# Per-object permission applies before and after hand contact.
	for contact in [false,true]:
		kit = drops.nearest_loose_of_key(KIT,worker.current_cell())
		drops.set_disallowed(kit,true)
		_expect(not worker.change_profession(CARPENTER), "disallowed kit cannot authorize promotion")
		drops.set_disallowed(kit,false)
		worker.change_profession(CARPENTER)
		await _equipment_stage("pickup")
		if contact: worker._process(.35)
		drops.set_disallowed(kit,true)
		worker._process(.05)
		_expect(not worker.promotion_pending() and worker.profession==WORKER and _count(KIT)==1, "forbid interrupts pickup without promotion or lost kit")
		_expect(drops._loose.has(kit) and not drops.Permission.allowed(kit), "interrupted kit stays disallowed")
		drops.set_disallowed(kit,false)
	worker.change_profession(MINER)
	_expect(worker.profession == MINER and worker._equipment.tool_key().is_empty(), "Miner still promotes freely using default pickaxe")
	await _review_equipment()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TOOL_PROMOTION_OK: crafted kit, competing claims, pickup, cancellation, sleep, routes, storage, equipped and pending saves, Miner and UI")
	quit(0 if failures.is_empty() else 1)

func _equipment_stage(value: String) -> bool:
	for i in range(900):
		if worker._equipment.stage == value: return true
		if not worker.promotion_pending(): return false
		await _tick()
	return false

func _appointed() -> bool:
	for i in range(900):
		if not worker.promotion_pending(): return worker.profession == CARPENTER
		await _tick()
	return false

func _reload_worker(factory) -> void:
	var state: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	var goods: Dictionary = JSON.parse_string(JSON.stringify(drops.serialize_state()))
	tasks.deregister_dwarf(worker.dwarf_id)
	worker.free()
	for node in drops._loose.keys(): drops.take(node); node.free()
	drops.restore_state(goods)
	var data: Dictionary = factory.generate(141, {})
	data.profession = state.profession
	worker = factory.spawn(data, 141)
	scene.add_child(worker)
	worker.position = Vector3(state.position[0],state.position[1],state.position[2])
	worker.set_process(false)
	worker.restore_saved_runtime(state)
	for cargo: Dictionary in state.carried_items:
		drops.restore_loose_item(cargo.item_key, worker.position, 0, cargo.count)
	tasks.register_dwarf(worker)
	await _frames(2)

func _review_equipment() -> void:
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	director._agents.append(worker)
	var explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dwarf_director_path = NodePath("../Dwarves")
	scene.add_child(explorer)
	director.open_professions(worker)
	promotion = director._profession_panel
	worker.change_profession(WORKER)
	promotion.select_profession(CARPENTER)
	await _frames(4)
	_expect(not promotion._promote.disabled, "available kit enables appointment button")
	promotion._promote.pressed.emit()
	await _equipment_stage("walking")
	promotion.refresh()
	_expect(promotion._status.text == "COLLECTING TOOL" and promotion._promote.text == "Cancel promotion", "UI offers cancellation while dwarf collects kit")
	_expect(not promotion._feedback.text.contains("now a Carpenter"), "UI never claims promotion early")
	await _capture_equipment("collecting")
	promotion._promote.pressed.emit()
	_expect(not worker.promotion_pending() and worker.profession == WORKER, "Cancel promotion button releases appointment")
	promotion._promote.pressed.emit()
	await _appointed()
	for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = viewport
		await _frames(8)
		promotion.refresh()
		_expect(promotion._requirements.text.contains("Equipped") and promotion._promote.disabled, "profession screen displays equipped kit")
		_expect(promotion.window.get_global_rect().encloses(promotion._promote.get_global_rect()), "promotion action fits compact window")
		await _capture_equipment("equipped_%d" % viewport.x)
	manager.close("professions")
	director.inspect_dwarf(worker)
	await _frames(6)
	var inspector = explorer._dwarf_panel
	_expect(inspector._equipment.text.contains("carpentry") or inspector._equipment.text.contains("Carpentry"), "inspector identifies real equipped tool")
	await _capture_equipment("inspector_960")
	dock._open_inventory()
	dock._inventory_panel._set_category("tools")
	await _frames(5)
	_expect(crafting.stock_snapshot()[KIT].equipped == 1, "inventory tracks equipped kit separately")

func _capture_equipment(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/tool_promotion_review/%s.png" % label)
