extends "res://scripts/tests/HaulingAnimationTest.gd"

## Storage priority (doc 294, step 2). Every store ranks from 1 (filled first) to 5 (last), and
## ground zones start at 5:
## - loose goods go to the best store with room, nearer or not;
## - stored goods move up to a better store, never between equal ones;
## - a full better store, or one its haulers can't reach or whose hauls wait for attention,
##   leaves the goods to worse ones;
## - taking goods out still takes the nearest;
## - a project's materials crate always takes its own goods;
## - saves keep the priority, and a zone saved without one is a 5;
## - the storage window sets it;
## - a trip moving goods up that skips one gives its claim back, and the trip still ends cleanly;
## - stored food never moves up onto a crate far from it in freshness.
const APPLE := "base:resources:flora:apple"
var _next_source := 60
var storage


## A project's order as its materials crate reads it in setup.
class OrderStub extends RefCounted:
	var ghost_id := 1
	var drop_manager
	func item_keys() -> Array: return ["base:resources:stone:rough_stone"]


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Storage priority test timed out"); quit(1))
	await _setup_fixture()
	await _new_trip(STONE, 1)
	var near_zone = zone
	var far_zone = _other_zone(Vector3i(52, 20, 48), 3)
	_expect(near_zone.priority == 5 and far_zone.priority == 5, "ground storage starts at priority 5, last")
	# Equal priorities: the nearest store, as before.
	_expect(await _until_true(func(): return near_zone.stored_count() == 1), "at equal priority the stone goes to the nearer zone")
	# A better store takes new goods, nearer or not, and draws stored ones up out of worse stores.
	far_zone.set_priority(2)
	drops.restore_loose_item(STONE, Vector3(41.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return far_zone.stored_count() == 2 and near_zone.stored_count() == 0),
		"at priority 2 the far zone takes the new stone and draws the stored one up out of the nearer zone")
	# Equal again: nothing moves back, and new goods go to the nearest.
	near_zone.set_priority(2)
	for i in range(150): await _step()
	_expect(far_zone.stored_count() == 2 and near_zone.stored_count() == 0, "goods never move between stores of equal priority")
	drops.restore_loose_item(STONE, Vector3(41.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return near_zone.stored_count() == 1), "between equal stores the nearest takes new goods, though the far one has room")
	# Ranked last again, the near zone's stone moves up into the far zone's last cell; with the
	# far zone full, new goods go to the near one.
	near_zone.set_priority(5)
	_expect(await _until_true(func(): return far_zone.stored_count() == 3 and near_zone.stored_count() == 0), "the stone moves up into the far zone's last cell")
	drops.restore_loose_item(STONE, Vector3(42.5, 21, 40.5), 0, 1)
	_expect(await _until_true(func(): return near_zone.stored_count() == 1), "with the better zone full, the worse zone takes the stone")
	_expect(far_zone.stored_count() == 3, "and the full zone keeps its own")
	# A better store whose haulers can't reach anything leaves the goods to worse ones.
	var walled = _other_zone(Vector3i(56, 20, 52))
	walled.set_priority(1)
	drops.restore_loose_item(STONE, Vector3(42.5, 21, 40.5), 0, 1)
	stockpiles._process(.3)
	_expect(not walled._lease_ids.is_empty() and stockpiles.better_store_takes(STONE, near_zone), "a better zone with room posts its haul and claims the stone first")
	for task_id: int in walled._lease_ids: tasks.get_task(task_id).retry_at = Time.get_ticks_msec() + 600000
	stockpiles.storage_rules_changed()
	_expect(walled.hauling_blocked() and not stockpiles.better_store_takes(STONE, near_zone), "while its hauls are blocked, it no longer claims the stone")
	# A haul paused for attention (repeated failures, until the player retries it) blocks the store
	# too, though its retry time has long passed (the project review, 2026-11-09: zones refused
	# loose food that rotted outside).
	for task_id: int in walled._lease_ids:
		var lease = tasks.get_task(task_id)
		lease.retry_at = 0
		lease.recovery_paused = true
	stockpiles.storage_rules_changed()
	_expect(walled.hauling_blocked() and not stockpiles.better_store_takes(STONE, near_zone), "a haul paused for attention leaves the stone to the worse zone too")
	_expect(await _until_true(func(): return near_zone.stored_count() == 2), "so the worse zone takes it")
	stockpiles.deregister_zone(walled)
	# Taking goods out still takes the nearest, whatever the store's rank.
	var keys: Array[String] = [STONE]
	var taken: Node3D = stockpiles.withdraw_matching_item(keys, Vector3i(41, 20, 43), 777)
	_expect(taken != null and drops.item_floor_cell(taken) in near_zone.tile_cells, "a withdrawal takes the nearest stone, from the worse zone")
	drops.unreserve(taken, 777)
	# A project's materials crate always takes its own goods.
	var crate = load("res://scripts/components/ConstructionMaterials.gd").new()
	var order := OrderStub.new()
	order.drop_manager = drops
	crate.setup(order)
	_expect(crate.priority == 0 and not stockpiles.better_store_takes(STONE, crate), "a project's crate ranks 0: no store takes its goods ahead of it")
	# Saves keep the priority; a zone saved without one is a 5.
	await _saves_and_window()
	await _skipped_relocation()
	_fresh_relocation()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STORAGE_PRIORITY_OK: ground starts at 5, the best store with room first, moving up and never sideways, full and unreachable stores, nearest withdrawal, the project crate, saves, the window, a skipped good and fresh food kept apart")
	quit(0 if failures.is_empty() else 1)


## A trip moving stored goods up takes one hidden handoff marker for each good. When it skips one
## (its walk failed, or the store refused it), that good's claim goes back to its store at once.
## A permission change mid-trip and the delivery must meet no freed marker (a SCRIPT ERROR fails
## the run), and the trip's end releases every claim and frees every marker (project review
## 2026-11-09: the skip freed the marker, and the delivery's release then stopped half way).
func _skipped_relocation() -> void:
	await _new_trip(STONE, 1)
	for x in [1, 2]: drops.restore_loose_item(STONE, Vector3(40.5 + x, 21, 40.65), 0, 1)
	var fill: Dictionary = zone.reserve_haul(900, Vector3i(40, 20, 40), {})
	var carried: Array = []
	for i in range(fill.get("items", []).size()):
		var node: Node3D = zone.take_item(900, i)
		if node != null: carried.append([node, drops.item_key_of(node)])
	_expect(zone.commit_haul(900, carried) and zone.stored_count() == 3, "three stones are stored in the zone, at priority 5")
	var best = _other_zone(Vector3i(44, 20, 48), 3)
	best.set_priority(1)
	var trip: Dictionary = best.reserve_haul(901, Vector3i(41, 20, 44), {})
	var markers: Array = trip.get("items", [])
	_expect(markers.size() == 3 and int(stockpiles.get_outgoing_totals().get(STONE, 0)) == 3, "a zone at priority 1 gathers all three in one trip: %d" % markers.size())
	if markers.size() != 3: return
	best.skip_item(901, 0)
	_expect(int(stockpiles.get_outgoing_totals().get(STONE, 0)) == 2, "the skipped stone's claim goes back to the zone at once")
	for i in range(3): await process_frame
	stockpiles.permissions_changed()
	carried.clear()
	for i in [1, 2]:
		var node: Node3D = best.take_item(901, i)
		if node != null: carried.append([node, drops.item_key_of(node)])
	_expect(carried.size() == 2 and best.commit_haul(901, carried), "the other two are picked up and delivered")
	await process_frame
	var left: Array = drops.get_children().filter(func(node): return node.has_meta("relocation_id") and not node.is_queued_for_deletion())
	_expect(best.stored_count() == 2 and zone.stored_count() == 1 and stockpiles.get_outgoing_totals().is_empty() and best.reserved_cells.is_empty()
		and best._pulls.is_empty() and left.is_empty(), "the trip's end releases every claim and frees every marker: %d stored, %s out, %d markers" % [best.stored_count(), stockpiles.get_outgoing_totals(), left.size()])


## Goods moving up never top up a crate far from them in freshness: that fallback is for food
## left outside (doc 42 "Spoilage"). Fresh apples stay in a worse zone while the better zone's only
## room is a crate close to rotting (the project review, 2026-11-09).
func _fresh_relocation() -> void:
	var worse = _other_zone(Vector3i(56, 20, 52), 1)
	var better = _other_zone(Vector3i(58, 20, 52), 1)
	better.set_priority(1)
	_store_apples(worse, Vector3i(56, 20, 52), 6, 0.0)
	_store_apples(better, Vector3i(58, 20, 52), 7, 0.9)
	var trip: Dictionary = better.reserve_haul(902, Vector3i(57, 20, 51), {})
	_expect(trip.get("items", []).is_empty() and int(stockpiles.get_outgoing_totals().get(APPLE, 0)) == 0,
		"fresh apples never move up onto a crate close to rotting: %s out" % [stockpiles.get_outgoing_totals()])


## Puts apples straight into a zone's cell, `spoil` of the way to rotting.
func _store_apples(store, cell: Vector3i, count: int, spoil: float) -> void:
	store.cell_stacks[cell] = {"item": APPLE, "count": count}
	if spoil > 0.0: store.cell_stacks[cell]["spoil"] = spoil
	drops.restore_stored_item(APPLE, cell, count, "", false, "", spoil)
	stockpiles.rebuild_totals()


func _saves_and_window() -> void:
	root.size = Vector2i(1280, 720)
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout.clear()
	storage = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage.window_manager_path = NodePath("../Windows")
	scene.add_child(storage)
	storage.set_process(false)
	var cells: Array[Vector3i] = [Vector3i(56, 20, 44), Vector3i(57, 20, 44)]
	var saved_zone = storage._create_zone(cells, 501)
	saved_zone.set_priority(3)
	var state: Dictionary = JSON.parse_string(JSON.stringify(storage.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(int(state.zones[0].priority) == 3 and validator._validate(state, validator.SCENE.stockpiles, "save.scene.stockpiles", {}).is_empty(),
		"a zone's priority saves, within the save's rules")
	storage.remove_zone(501)
	storage.restore_state(state)
	_expect(storage._zones[501].priority == 3, "and comes back from the save")
	state.zones[0].erase("priority")
	_expect(validator._validate(state, validator.SCENE.stockpiles, "save.scene.stockpiles", {}).is_empty(), "a save without it is still valid")
	storage.remove_zone(501)
	storage.restore_state(state)
	_expect(storage._zones[501].priority == 5, "and its zone is a 5")
	# The window: five steps, the store's own pressed, and a click sets it.
	storage._open_zone_window(501)
	for i in range(8): await process_frame
	var panel = storage._storage_panel
	var subject = storage._zones[501]
	_expect(panel._priority_buttons.size() == 5 and panel._priority_buttons[4].button_pressed and not panel._priority_buttons[0].button_pressed,
		"the window shows five steps, with the zone's 5 pressed")
	_click(panel._priority_buttons[1].get_global_rect().get_center())
	for i in range(4): await process_frame
	_expect(subject.priority == 2 and panel._priority_buttons[1].button_pressed and not panel._priority_buttons[4].button_pressed, "a click on 2 sets the zone to 2")


func _other_zone(at: Vector3i, count := 2):
	_next_source += 1
	var result = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = []
	for x in range(count): cells.append(at + Vector3i(x, 0, 0))
	result.setup(_next_source, cells)
	stockpiles.register_zone(result)
	return result


func _step() -> void:
	stockpiles._process(.25)
	tasks._run_scheduler()
	worker._process(.04)
	await process_frame


func _until_true(condition: Callable, limit := 1500) -> bool:
	for i in range(limit):
		if condition.call(): return true
		await _step()
	return false
