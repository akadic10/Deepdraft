extends "res://scripts/tests/WorkerCraftingTest.gd"

## A craft trip carries as many ingredients as hauling would (owner report, 2026-10-30:
## Tekak brought a Log bed's logs to the bench one at a time). After the planned pickup the
## Worker takes the next ingredients the batch needs that lie near, up to the carrying
## limit, sets them down together and keeps the batch's last log in hand to work.
const BED_RECIPE := "base:recipe:worker:log_bed"
const BED_ITEM := "base:resources:furniture:log_bed"
const HEARTH_RECIPE := "base:recipe:worker:hearth"
var deliveries := 0
var most_carried := 0
var _last_phase := -1

func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Craft trip timed out"); quit(1))
	await _setup_crafting_fixture()
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(46,20,40),0)
	# Two loose piles four blocks apart: all four logs in one trip.
	drops.spawn_drop(PINE,2,Vector3i(38,21,39))
	drops.spawn_drop(PINE,2,Vector3i(38,21,43))
	await _craft(BED_RECIPE)
	_expect(deliveries==1 and most_carried==4 and _count(BED_ITEM)==1 and _count(PINE)==0,
		"a log bed's four loose logs come in one trip: %d trips, %d carried at most" % [deliveries,most_carried])
	# Stored logs side by side in the stockpile.
	for x in range(40,44):
		var cell := Vector3i(x,20,44)
		zone.cell_stacks[cell] = {"item":PINE,"count":1}
		drops.restore_stored_item(PINE,cell,1)
	stockpiles._totals[PINE] = 4
	await _craft(BED_RECIPE)
	_expect(deliveries==1 and most_carried==4 and _count(BED_ITEM)==2 and _count(PINE)==0,
		"four stored logs come in one trip: %d trips, %d carried at most" % [deliveries,most_carried])
	# A hearth: four stones fill the first trip, the two logs make the second.
	drops.spawn_drop(STONE,4,Vector3i(38,21,39))
	drops.spawn_drop(PINE,2,Vector3i(38,21,41))
	await _craft(HEARTH_RECIPE)
	_expect(deliveries==2 and most_carried==4 and _count(STONE)==0 and _count(PINE)==0,
		"a hearth's six goods come in two trips: %d trips, %d carried at most" % [deliveries,most_carried])
	# An extra that is gone when the Worker reaches it is skipped; the trip goes on.
	drops.spawn_drop(PINE,2,Vector3i(38,21,39))
	drops.spawn_drop(PINE,3,Vector3i(38,21,43))
	var id: int = crafting.queue_order(BED_RECIPE,1)
	var order = crafting.get_order(id)
	var vanished := false
	_reset_counts()
	for i in range(1600):
		if crafting.get_order(id)==null: break
		if not vanished and worker._task_phase==worker.TaskPhase.FETCH_TO_ITEM and order.carried.size()==2:
			var target: Node3D = order.item
			drops.take(target)
			target.free()
			vanished = true
		await _tick()
	_expect(vanished and crafting.get_order(id)==null and deliveries==2 and _count(BED_ITEM)==3 and _count(PINE)==0,
		"a vanished extra is skipped and the bed still finishes: %d trips" % deliveries)
	for failure in failures: push_error(failure)
	print("CRAFT_TRIP_OK" if failures.is_empty() else "CRAFT_TRIP_FAIL")
	quit(0 if failures.is_empty() else 1)

func _tick() -> void:
	await super._tick()
	var phase: int = worker._task_phase
	if phase==worker.TaskPhase.FETCH_TO_GHOST and _last_phase!=phase: deliveries += 1
	_last_phase = phase
	most_carried = maxi(most_carried,worker._carried_entries.size())

func _craft(recipe: String) -> void:
	var id: int = crafting.queue_order(recipe,1)
	_reset_counts()
	for i in range(1600):
		if crafting.get_order(id)==null: return
		await _tick()
	_expect(false,"%s finishes" % recipe)

func _reset_counts() -> void:
	deliveries = 0
	most_carried = 0
	_last_phase = -1
