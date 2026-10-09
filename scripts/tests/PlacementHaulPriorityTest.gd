extends "res://scripts/tests/WorkerCraftingTest.gd"

## Real HAUL reservations and executors, including fist-contact ownership.
var case_number := 0

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Placement haul priority timed out"); quit(1))
	await _setup_crafting_fixture()
	for phase in [worker.TaskPhase.HAUL_TO_ITEM, worker.TaskPhase.HAUL_PICKUP,
			worker.TaskPhase.HAUL_TO_ZONE, worker.TaskPhase.HAUL_DEPOSIT]:
		await _bench_case(phase, false)
	await _bench_case(worker.TaskPhase.HAUL_PICKUP, true)
	await _interrupted_handoff(false)
	await _interrupted_handoff(true)
	await _sleep_handoff()
	await _protected_claim()
	await _relocation_case()
	await _crate_case()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("PLACEMENT_HAUL_PRIORITY_OK: paused catalog, read-only browsing, pickup/carry/deposit handoff, same carrier, cancellation, blocked site, relocation, split crate and conservation")
	quit(0 if failures.is_empty() else 1)

func _clean_case() -> void:
	clock_node.set_paused(false)
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in tasks._tasks.keys(): tasks.cancel_task(id)
	for node in drops._loose.keys(): drops.take(node); node.queue_free()
	worker.position = Vector3(32.5,21,40.5)
	case_number += 1
	await process_frame

func _start_bench(phase: int, after_contact := false) -> Node3D:
	await _clean_case()
	drops.restore_loose_item(BENCH_ITEM, Vector3(40.5,21,40.5), 0, 1)
	var item: Node3D = drops._loose.keys()[0]
	_expect(await _until(phase), "haul reaches phase %s" % phase)
	if after_contact: worker._process(.35)
	_expect(tasks.get_task(worker.current_task_id).type == Task.Type.HAUL, "real haul owns item")
	return item

func _place_bench(cell: Vector3i) -> RefCounted:
	furniture.activate_for(BENCH, true)
	furniture._hover_cell = cell
	furniture._confirm_ghost()
	return furniture._ghosts.values()[-1] if not furniture._ghosts.is_empty() else null

func _bench_case(phase: int, after_contact: bool) -> void:
	var item := await _start_bench(phase, after_contact)
	var old_task: int = worker.current_task_id
	var was_carried: bool = not worker._carried_entries.is_empty()
	clock_node.set_paused(true)
	_expect(int(furniture.get_catalog_stock()[BENCH].available) == 1, "haul stock stays available while paused")
	dock._open_place_catalog()
	dock._place_catalog._select(BENCH)
	await _frames(3)
	_expect(dock._place_catalog._values.Available.text == "1" and not dock._place_catalog._place.disabled, "open Place UI enables reserved stock")
	_expect(worker.current_task_id == old_task and tasks.get_task(old_task) != null, "browsing does not interrupt haul")
	if DisplayServer.get_name() != "headless" and case_number == 1:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/placement_haul_review/available_while_hauling.png")
	var cell := Vector3i(48 + case_number*3,20,40)
	var ghost := _place_bench(cell)
	_expect(ghost != null and tasks.get_task(old_task) == null, "confirmation supersedes haul immediately while paused")
	_expect(zone._pulls.is_empty(), "old haul releases deposit and item claims")
	_expect(int(furniture.get_catalog_stock()[BENCH].available) == 0, "one owned item cannot be promised twice")
	if was_carried:
		_expect(worker._fetch_item == item and worker._fetch_picked_up, "same carrier retains exact item without another pickup")
		_expect(worker._task_phase in [worker.TaskPhase.FETCH_TO_GHOST,worker.TaskPhase.FETCH_WORKING], "carrier goes directly to placement")
		var cargo: Array = worker.serialize_state().carried_items
		_expect(cargo.size() == 1 and int(cargo[0].count) == 1, "redirected item remains physical save cargo")
	else:
		_expect(drops.reserved_by(item, ghost.claim_owner_id()), "waiting item transfers to placement claim")
	_expect(_count(BENCH_ITEM) == 1, "handoff conserves physical item")
	var before: int = furniture._ghosts.size()
	furniture._confirm_ghost()
	_expect(furniture._ghosts.size() == before, "rapid second click cannot overbook")
	clock_node.set_paused(false)
	for i in range(700):
		if furniture._ghosts.is_empty(): break
		await _tick()
	_expect(furniture._ghosts.is_empty() and furniture._cell_to_installed.has(cell), "redirected item installs")
	_expect(_count(BENCH_ITEM) == 0 and worker._carried_entries.is_empty(), "installation consumes exactly one item")

func _interrupted_handoff(blocked: bool) -> void:
	await _start_bench(worker.TaskPhase.HAUL_TO_ZONE)
	var ghost := _place_bench(Vector3i(80,20,40))
	if blocked:
		ghost.build_valid_callback = func(_plan): return false
		worker._fetch_complete() # Support changed before final commit.
		_expect(_count(BENCH_ITEM) == 1 and worker._carried_entries.is_empty(), "failed site drops intact cargo")
		_expect(not ghost._carried_by.has(worker.dwarf_id), "failed site frees carrier bookkeeping")
	else:
		furniture.cancel_ghost(ghost.ghost_id)
		_expect(_count(BENCH_ITEM) == 1 and worker._carried_entries.is_empty(), "cancelled redirected placement returns loose cargo")
		_expect(int(furniture.get_catalog_stock()[BENCH].available) == 1, "cancel restores placement availability")

func _relocation_case() -> void:
	await _clean_case()
	var origin = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(40,20,36)]
	origin.setup(99,cells)
	stockpiles.register_zone(origin)
	origin.cell_stacks[cells[0]] = {"item": BENCH_ITEM, "count": 1}
	drops.restore_stored_item(BENCH_ITEM,cells[0])
	stockpiles._totals[BENCH_ITEM] = 1
	origin.set_all_accepted(false)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ITEM), "storage relocation starts")
	_expect(not origin._outgoing.is_empty(), "stored item owns outgoing reservation")
	_expect(int(furniture.get_catalog_stock()[BENCH].available) == 1, "stored relocation is counted once")
	var ghost := _place_bench(Vector3i(80,20,44))
	_expect(origin._outgoing.is_empty() and zone._pulls.is_empty(), "placement frees both relocation tokens")
	for i in range(700):
		if not furniture._ghosts.has(ghost.ghost_id): break
		await _tick()
	_expect(not furniture._ghosts.has(ghost.ghost_id) and _count(BENCH_ITEM) == 0, "relocated stock installs without a storage detour or duplicate")
	stockpiles.deregister_zone(origin)

func _sleep_handoff() -> void:
	await _start_bench(worker.TaskPhase.HAUL_TO_ZONE)
	var ghost := _place_bench(Vector3i(80,20,40))
	worker.dev_make_tired()
	worker._process(.01)
	_expect(worker.is_sleeping() and _count(BENCH_ITEM) == 1 and worker._carried_entries.is_empty(), "sleep safely interrupts redirected cargo")
	furniture._process(.3) # Existing drop wake refreshes generic furniture claims.
	_expect(ghost._claim_valid(), "drop wake returns item to existing placement claim")
	furniture.cancel_ghost(ghost.ghost_id)
	worker._wake_up()

func _protected_claim() -> void:
	var item := await _start_bench(worker.TaskPhase.HAUL_TO_ITEM)
	item.set_meta("instance_id", "test:bench:protected")
	drops.promise_instance("test:bench:protected", 123456)
	_expect(tasks.placement_haul_offers().is_empty() and int(furniture.get_catalog_stock()[BENCH].available) == 0, "exact instance promised to another plan cannot be reclaimed")
	drops.release_instance_promise("test:bench:protected",123456)
	_expect(int(furniture.get_catalog_stock()[BENCH].available) == 1, "releasing exact promise restores haul availability")

func _crate_case() -> void:
	await _clean_case()
	var key := "base:resources:flora:blueberry_cutting"
	# Derive the item key from the actual placement definitions.
	var definition := {}
	for def: Dictionary in furniture.get_defs().values():
		if String(def.get("item_key", "")).contains("blueberry_cutting"): definition = def; key = String(def.item_key); break
	_expect(not definition.is_empty(), "cutting placement definition exists")
	if definition.is_empty(): return
	drops.restore_loose_item(key,Vector3(40.5,21,40.5),0,3)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "cutting crate enters haul cargo")
	var ghost = load("res://scripts/components/ShrubPlantingComponent.gd").new()
	ghost.setup(900,"test:plant",definition,Vector3i(85,20,40),0)
	ghost.source_id = tasks.allocate_source_id()
	ghost.drop_manager = drops
	tasks.register_work_source(ghost.source_id,ghost)
	ghost.update_lease()
	_expect(worker._carried_entries.is_empty() and _count(key) == 3, "multi-unit crate safely returns loose for splitting")
	var pull: Dictionary = ghost.reserve_fetch(worker.dwarf_id,worker.current_cell())
	var unit: Node3D = ghost.take_planting_item(pull.item,worker.dwarf_id)
	_expect(unit != null and drops.quantity_of(unit) == 1 and _loose_units() == 2, "placement takes one cutting and preserves remaining crate")
	if unit != null: drops.drop_loose(unit,worker.current_cell())
	ghost.cancel_fetch(worker.dwarf_id)
	tasks.cancel_task(ghost._lease_id)
	ghost.release_claim()
	tasks.unregister_work_source(ghost.source_id)
