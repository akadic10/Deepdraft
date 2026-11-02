extends "res://scripts/tests/WorkerCraftingTest.gd"

## The crafting queue at one busy workbench (owner report, 2026-10-30). Orders behind the
## bench wait their turn ("Next in line", "2nd in line"), not "for a free workbench", and
## their recipes stay ready to queue. The freed bench goes to the top-most order that can
## start, even after the craft scan began below the top or an earlier order got its wood late.
const LADDER_RECIPE := "base:recipe:worker:crude_ladder"
const OAK := "base:resources:wood:oak_log"

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Crafting queue timed out"); quit(1))
	await _setup_crafting_fixture()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(41,20,42),0)
	drops.spawn_drop(PINE,5,Vector3i(42,21,40))
	await _busy_bench_keeps_turns()
	await _late_wood_keeps_its_place()
	for failure in failures: push_error(failure)
	print("CRAFTING_QUEUE_OK" if failures.is_empty() else "CRAFTING_QUEUE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _busy_bench_keeps_turns() -> void:
	var ids: Array[int] = []
	for recipe: String in [TORCH_RECIPE,LADDER_RECIPE,TORCH_RECIPE,LADDER_RECIPE,TORCH_RECIPE]: ids.append(crafting.queue_order(recipe,1))
	crafting._refresh()
	# The top two wait out a short backoff, as when their logs are briefly out of reach, so
	# the third goes first. Where the queue starts must not move with it.
	for id: int in ids.slice(0,2): tasks.apply_backoff(tasks.get_task(crafting.get_order(id).lease_id),Time.get_ticks_msec())
	_expect(await _next_started()==ids[2],"with the top two held back, the third order takes the bench")
	crafting._refresh()
	var totals: Dictionary = crafting.stock_snapshot()
	var labels: Array = ids.map(func(id: int): return crafting.status(crafting.get_order(id),totals))
	_expect(labels[0]=="Next in line" and labels[1]=="2nd in line" and labels[3]=="3rd in line" and labels[4]=="4th in line",
		"orders behind the busy bench wait their turn, not for a free workbench: %s" % [labels])
	var pine: Array[String] = [PINE]
	_expect(crafting.recipe_waiting_reason(crafting.recipes[TORCH_RECIPE],pine,totals).is_empty(),"a busy bench leaves its recipes ready to queue")
	dock.open_crafting(TORCH_RECIPE)
	await _frames(4)
	_expect(not panel._recipes.get_tile(TORCH_RECIPE).has_node("Mark") and _tag_texts().has("✓ A crude workbench"),
		"the window shows the recipe ready and the bench there: %s" % [_tag_texts()])
	var row: Dictionary = panel._rows[ids[0]]
	_expect(row.status.text=="Next in line" and row.tag.get_theme_stylebox("panel")==UITheme.cell_style("tag_fine",2),"the top queued order says Next in line on a fine tag")
	_expect(await _completed(ids[2]),"the third order finishes")
	_expect(await _next_started()==ids[0],"the freed bench goes to the top of the queue")
	_expect(await _completed(ids[0]),"the top order finishes")
	_expect(await _next_started()==ids[1],"then the next order down")
	for id: int in ids: crafting.remove_order(id)

func _late_wood_keeps_its_place() -> void:
	var oak: Array[String] = [OAK]
	var early: int = crafting.queue_order(TORCH_RECIPE,1,false,oak)
	var late: int = crafting.queue_order(LADDER_RECIPE,1)
	crafting._refresh()
	_expect(crafting.get_order(early).lease_id<0 and crafting.get_order(late).lease_id>=0,"only the order with wood posts work")
	drops.spawn_drop(OAK,1,Vector3i(39,21,41))
	crafting._refresh()
	_expect(crafting.get_order(early).lease_id>=0 and crafting.get_order(early).lease_id<crafting.get_order(late).lease_id,
		"once its wood arrives, the earlier order's work is posted ahead of the later one")
	_expect(await _next_started()==early,"and the earlier order takes the free bench")
	for id: int in [early,late]: crafting.remove_order(id)

func _next_started() -> int:
	for i in range(800):
		for order in crafting.orders:
			if order.worker_id>=0: return order.id
		await _tick()
	return -1

func _tag_texts() -> Array[String]:
	var texts: Array[String] = []
	for tag: Node in panel._tags.get_children(): texts.append((tag.get_child(0) as Label).text)
	return texts
