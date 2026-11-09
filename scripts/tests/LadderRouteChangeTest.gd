extends "res://scripts/tests/RudimentaryRecreationTest.gd"

## A ladder change leaves a walk alone unless its route uses the changed rungs, and a replan keeps
## the meal, game or promotion that owns the walk (doc 32).
const APPLE := "base:resources:flora:apple"
const KIT := "base:resources:tools:carpentry_kit"
const CARPENTER := "base:profession:carpenter"
const FAR := Vector3i(100,20,100)
var nav
var next_ladder := 900

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Ladder route change test timed out"); quit(1))
	await _setup_crafting_fixture()
	nav = root.get_node("NavGrid")
	_route_checks()
	await _meal()
	await _promotion()
	await _game()
	for failure in failures: push_error(failure)
	print("LADDER_ROUTE_CHANGE_OK" if failures.is_empty() else "LADDER_ROUTE_CHANGE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _ladder_at(cell: Vector3i) -> int:
	next_ladder += 1
	nav.set_ladder(next_ladder,cell,1,Vector3i.FORWARD,1.0)
	return next_ladder

func _route_checks() -> void:
	var path: Array = [Vector3i(50,20,50),Vector3i(51,20,50),Vector3i(51,21,50),Vector3i(52,21,50),Vector3i(53,21,50)]
	var id := _ladder_at(FAR)
	var since: int = nav.ladder_revision
	_expect(not nav.ladder_change_touches(path,0,since),"no change, nothing touched")
	nav.set_ladder(id,FAR,2,Vector3i.FORWARD,1.0)
	_expect(not nav.ladder_change_touches(path,0,since),"a section far away touches nothing")
	var used := _ladder_at(Vector3i(51,20,50))
	_expect(nav.ladder_change_touches(path,0,since),"a ladder on the route touches it")
	_expect(not nav.ladder_change_touches(path,4,since),"a ladder on a part already walked does not")
	since = nav.ladder_revision
	nav.set_ladder(used,Vector3i(51,20,50),3,Vector3i.FORWARD,1.0)
	_expect(not nav.ladder_change_touches([Vector3i(51,20,50),Vector3i(51,21,50)],0,since),"a section on top leaves the rungs below alone")
	_expect(nav.ladder_change_touches([Vector3i(51,23,50)],0,since),"a section on top touches its own new rungs")
	since = nav.ladder_revision
	nav.set_ladder(used,Vector3i(51,20,50),3,Vector3i.FORWARD,1.0,true)
	_expect(nav.ladder_change_touches([Vector3i(51,20,50)],0,since),"a ladder closing changes every rung")
	since = nav.ladder_revision
	for i in nav.LADDER_CHANGE_LOG+2: nav.set_ladder(id,FAR,2+i,Vector3i.FORWARD,1.0)
	_expect(nav.ladder_change_touches([FAR+Vector3i(5,0,5)],0,since),"a walk older than the log replans to be safe")
	nav.remove_ladder(id)
	nav.remove_ladder(used)

func _on_route_cell() -> Vector3i:
	return worker._move_path[mini(worker._move_index+1,worker._move_path.size()-1)]

## A far change keeps the very same route; one on the route replaces it. `active` is the activity.
func _ladders_during(active: Callable, name_of: String) -> void:
	var path: Array = worker._move_path
	var far := _ladder_at(FAR)
	worker._process(.01)
	_expect(active.call() and is_same(worker._move_path,path) and worker._ladder_path_revision==nav.ladder_revision,"a far ladder leaves the walk to %s untouched" % name_of)
	var near := _ladder_at(_on_route_cell())
	worker._process(.01)
	_expect(active.call() and worker.is_walking() and not is_same(worker._move_path,path) and worker._ladder_path_revision==nav.ladder_revision,"a ladder on the route replans the walk to %s and keeps it" % name_of)
	nav.remove_ladder(far)
	nav.remove_ladder(near)

func _meal() -> void:
	drops.spawn_drop(APPLE,1,Vector3i(30,21,39))
	worker.sleep = 1.0
	worker._food.value = .3
	worker._food.retry_hours = 0
	for i in 200:
		worker._process(.001)
		await process_frame
		if worker._food.state=="walking": break
	_expect(worker._food.state=="walking" and worker.is_walking(),"worker walks to a meal")
	await _ladders_during(func(): return worker._food.state=="walking","a meal")
	for i in 600:
		worker._process(.05)
		await process_frame
		if worker._food.state=="eating": break
	_expect(worker._food.state=="eating","the meal is reached after the ladder changes")
	worker._food.cancel()
	worker._food.value = 1.0
	worker.stop_walking()
	await _clear_loose()

func _clear_loose() -> void:
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	await process_frame

func _promotion() -> void:
	worker.position = Vector3(40.5,21,39.5)
	drops.restore_loose_item(KIT,Vector3(30.5,21,39.5),0,1)
	_expect(worker.change_profession(CARPENTER),"a promotion starts")
	for i in 200:
		worker._process(.001)
		await process_frame
		if worker._equipment.stage=="walking": break
	_expect(worker._equipment.stage=="walking" and worker.is_walking(),"worker walks to its tool")
	await _ladders_during(func(): return worker.promotion_pending() and worker._equipment.stage=="walking","a tool")
	for i in 600:
		worker._process(.05)
		await process_frame
		if not worker.promotion_pending(): break
	_expect(worker.profession==CARPENTER,"the promotion finishes after the ladder changes")
	await _clear_loose()

func _game() -> void:
	_create_partner()
	_layout(1)
	extra_worker._mood.recreation_retry_hours = 6
	worker.position = Vector3(30.5,21,30.5)
	for i in 400:
		await _game_tick()
		if worker.is_recreating() and worker.is_walking(): break
	_expect(worker.is_recreating() and worker.is_walking(),"worker walks to a game")
	if worker.is_recreating() and worker.is_walking():
		await _ladders_during(func(): return worker.is_recreating(),"a game")
