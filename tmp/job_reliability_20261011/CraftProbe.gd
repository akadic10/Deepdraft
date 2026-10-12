extends "res://scripts/tests/CraftingSelectionTest.gd"
func _run() -> void:
	await _setup_crafting_fixture()
	_fresh_workers()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(41,20,42),0)
	_supply()
	var id: int = crafting.queue_order(HOE,1)
	await _dispatch_order(id)
	var prior := ""
	for n in range(800):
		await _tick()
		var order = crafting.get_order(id)
		if order==null: print("DONE"); quit(); return
		var info := str([extra_worker._task_phase,order.worker_id,order.staged_items.size(),order.timber_key,order.work_cell,extra_worker._fetch_plan.get("stage",""),extra_worker._fetch_plan.get("material",{}).get("key",""),tasks.get_task(order.lease_id).wait_reason if order.lease_id>=0 else ""])
		if info!=prior:
			print("PROBE ",info," plan=",extra_worker._fetch_plan)
			prior=info
	quit(1)
