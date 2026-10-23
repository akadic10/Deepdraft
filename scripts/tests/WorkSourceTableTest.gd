extends "res://scripts/tests/LadderTest.gd"

## Doc 258 step 6: one WorkSourceTable owns work-source bookkeeping for ladders,
## bridges, flora, surface details and furniture. Checks the shared contract on
## a stub family and through two real owners (ladders and trees):
## - a release keeps the one pending lease and never posts another (Hard Rule 12);
## - a lease that is gone (cancelled) is re-posted once by its source;
## - retiring cancels the source's tasks without re-posting and unregisters it;
## - save/restore rebuilds exactly one freshly registered source per record;
## - the work-journal key names the task type instead of its enum number.

# Loaded at run time: the test script compiles before the autoloads exist.
var Table: GDScript
var Adapter: GDScript
const OAK := Vector2i(30, 30)


class StubSource extends RefCounted:
	var source_id := -1
	var origin := Vector3i(10, 20, 10)
	var task_type: int = Task.Type.CLEAR_BOULDER
	var events: Array[String] = []

	func work_task_gone(_task: Task, dwarf_id: int) -> void:
		events.append("gone:%d" % dwarf_id)

	func work_task_released(_task: Task, dwarf_id: int) -> void:
		events.append("released:%d" % dwarf_id)

	func work_source_retired() -> void:
		events.append("retired")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Work source table test timed out"); quit(1))
	await _setup_crafting_fixture()
	Table = load("res://scripts/components/WorkSourceTable.gd")
	Adapter = load("res://scripts/components/WorkSourceAdapter.gd")
	_check_stub_family()
	await _check_ladders()
	await _check_trees()
	for failure: String in failures: push_error(failure)
	print("WORK_SOURCE_TABLE_OK" if failures.is_empty() else "WORK_SOURCE_TABLE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _leases(source_id: int) -> int:
	return tasks._tasks.values().filter(func(task: Task): return task.source_id == source_id).size()


func _check_stub_family() -> void:
	var table = Table.new()
	var stub := StubSource.new()
	var id: int = table.add("stub", stub)
	_expect(stub.source_id == id and tasks.get_work_source(id) == stub and table.key_for(id) == "stub", "add registers the source under its key")
	_expect(Adapter.locator(stub, id).contains("task_type=CLEAR_BOULDER"), "journal key names the task type")
	var lease: int = tasks.add_task(Task.Type.CLEAR_BOULDER, stub.origin, {}, id)
	tasks.task_released.emit(tasks.get_task(lease), 7, Task.ReleaseReason.NO_PROGRESS)
	_expect(stub.events == ["released:7"], "a release reaches only work_task_released (got %s)" % str(stub.events))
	tasks.cancel_task(lease)
	_expect(stub.events.back() == "gone:-1", "a cancelled lease reaches work_task_gone")
	tasks.add_task(Task.Type.CLEAR_BOULDER, stub.origin, {}, id)
	var before := stub.events.size()
	_expect(table.retire("stub", true) == stub, "retire returns the source")
	_expect(stub.events.slice(before) == ["retired"], "retiring cancels without routing gone events (got %s)" % str(stub.events.slice(before)))
	_expect(_leases(id) == 0 and tasks.get_work_source(id) == null and table.size() == 0 and table.key_for(id) == null, "retire cancels, unregisters and forgets")


func _check_ladders() -> void:
	ladders = furniture._ladders
	ladders.set_process(false)
	nav = root.get_node("NavGrid")
	_build_cliff()
	await process_frame
	var cell := Vector3i(40,20,44)
	zone.cell_stacks[cell] = {"item":SECTION,"count":1,"material_id":"base:material:pine"}
	drops.restore_stored_item(SECTION,cell,1,"",false,"base:material:pine")
	stockpiles.rebuild_totals()
	var pine := ["base:material:pine","base:material:pine","base:material:pine"]
	ladders.restore_state({"next_id":3,"routes":[
		{"id":1,"key":LADDER,"base":[48,20,48],"yaw":0,"height":12,"built":4,"mode":"build",
			"progress":0.0,"materials":pine.slice(0,1),"required_material_id":""},
		{"id":2,"key":LADDER,"base":[52,20,48],"yaw":0,"height":12,"built":12,"mode":"remove",
			"progress":0.0,"materials":pine,"required_material_id":""}]})
	var old_ids := {}
	for id: int in [1, 2]:
		var source = ladders.work.get_source(id)
		_expect(source != null and _leases(source.source_id) == 1, "ladder %d posts one lease" % id)
		if source == null: return
		old_ids[id] = source.source_id
		tasks.task_released.emit(tasks._tasks[source._lease_id], worker.dwarf_id, Task.ReleaseReason.PLAYER)
		if source.has_method("update_lease"): source.update_lease()
		_expect(_leases(source.source_id) == 1, "ladder %d keeps one lease after a release" % id)
	ladders.restore_state(ladders.serialize_state())
	for id: int in [1, 2]:
		var source = ladders.work.get_source(id)
		_expect(source != null and source.source_id != old_ids[id], "ladder %d restores a fresh source" % id)
		_expect(tasks.get_work_source(old_ids[id]) == null and _leases(old_ids[id]) == 0, "ladder %d's old source is retired with its lease" % id)
		if source != null: _expect(_leases(source.source_id) == 1, "ladder %d restores exactly one lease" % id)
	var removal: int = ladders.work.get_source(2).source_id
	ladders.perform_explorer_action(2, "pause")
	_expect(not ladders.work.has(2) and _leases(removal) == 0 and tasks.get_work_source(removal) == null, "cancelling dismantling retires the removal lease")


func _check_trees() -> void:
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "Flora"
	scene.add_child(flora)
	flora.set_process(false)
	_spawn_tree("oak", "mature", OAK)
	await process_frame
	_expect(flora.designate_felling(OAK), "oak accepts a felling order")
	var source = flora.work.get_source(OAK)
	if source == null:
		_expect(false, "felling order creates a source")
		return
	var lease: int = source.lease_id
	_expect(lease >= 0 and _leases(source.source_id) == 1, "felling posts one lease")
	_expect(Adapter.locator(source, source.source_id).contains("task_type=FELL_TREE"), "felling journal key names the task type")
	tasks.task_released.emit(tasks.get_task(lease), worker.dwarf_id, Task.ReleaseReason.PLAYER)
	_expect(source.lease_id == lease and _leases(source.source_id) == 1, "a released felling lease is kept, not duplicated")
	tasks.cancel_task(lease)
	_expect(source.lease_id >= 0 and source.lease_id != lease and _leases(source.source_id) == 1, "a lost felling lease is re-posted once")
	var old_id: int = source.source_id
	flora.restore_state(flora.serialize_state())
	var restored = flora.work.get_source(OAK)
	_expect(restored != null and restored != source and restored.source_id != old_id, "restore rebuilds the felling source")
	_expect(tasks.get_work_source(old_id) == null and _leases(old_id) == 0, "restore retires the old felling source and lease")
	if restored == null: return
	_expect(flora.work.size() == 1 and _leases(restored.source_id) == 1, "restore posts exactly one felling lease")
	var restored_id: int = restored.source_id
	flora.cancel_felling(OAK)
	_expect(not flora.work.has(OAK) and _leases(restored_id) == 0 and tasks.get_work_source(restored_id) == null, "cancelling felling retires its source without re-posting")


func _spawn_tree(species_name: String, stage_name: String, id: Vector2i) -> Node3D:
	var species: Dictionary = flora._species_for_key("base:flora:%s_tree" % species_name)
	var stage: Dictionary = species.stages[stage_name]
	var cell := Vector3i(id.x,20,id.y)
	var path: String = flora.resolve_tree_model_for_season(stage, flora._season, cell)
	var node: Node3D = flora._instance_tree(species_name, path, stage_name, stage,
		id.x, id.y, 20, flora._footprint_for(species.placement, stage_name))
	if node != null:
		var column := Vector2i(id.x >> 4, id.y >> 4)
		if not flora._loaded_columns.has(column):
			flora._loaded_columns[column] = []
		flora._loaded_columns[column].append(node)
	return node
