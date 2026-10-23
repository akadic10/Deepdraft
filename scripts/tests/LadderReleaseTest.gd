extends "res://scripts/tests/LadderTest.gd"

## Hard Rule 12: releasing a ladder build or removal lease returns it to
## PENDING. The ladder must keep that one lease and never post a second job.

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ladder release test timed out"); quit(1))
	await _setup_crafting_fixture()
	ladders = furniture._ladders
	ladders.set_process(false)
	nav = root.get_node("NavGrid")
	_build_cliff()
	await process_frame
	# A build only posts its lease while a section is in storage.
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
	for id: int in [1, 2]: _check_release(id)
	for failure: String in failures: push_error(failure)
	print("LADDER_RELEASE_OK" if failures.is_empty() else "LADDER_RELEASE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_release(id: int) -> void:
	var source = ladders.work.get_source(id)
	var lease: int = source._lease_id if source != null else -1
	_expect(lease >= 0, "route %d posts its lease" % id)
	if lease < 0: return
	# release_dwarf_task leaves the same task PENDING and then emits this.
	tasks.task_released.emit(tasks._tasks[lease], worker.dwarf_id, Task.ReleaseReason.NO_PROGRESS)
	if source.has_method("update_lease"): source.update_lease()
	var leases: Array = tasks._tasks.values().filter(func(task: Task): return task.source_id == source.source_id)
	_expect(leases.size() == 1 and source._lease_id == lease, "route %d keeps exactly one lease after a release (has %d)" % [id, leases.size()])
