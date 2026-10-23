extends "res://scripts/tests/HaulingAnimationTest.gd"

## Reproduces Bogorn's bridge-corner fall: the shortcut is legal from the cell
## centre but crosses water from the actor's fractional position near its edge.
var nav
var excavated: Array[Vector3i] = []
const CENTRE := Vector3i(64,20,64)

func _run() -> void:
	create_timer(75).timeout.connect(func(): push_error("Bridge corner test timed out"); quit(1))
	await _setup_fixture()
	nav = root.get_node("NavGrid")
	worker.abort_task()
	tasks.reset_runtime_state()
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for yaw in range(4):
		for cell in excavated: world.set_block(cell.x,cell.y,cell.z,rock)
		excavated.clear()
		nav.remove_bridge(991)
		for x in range(4,124):
			for z in range(51,56):
				for y in range(19,21):
					var cell := _cell(Vector3i(x,y,z),yaw)
					world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
					excavated.append(cell)
		var deck: Array[Vector3i] = []
		var exits: Array[Vector3i] = []
		for x in [59,60]:
			for z in range(51,56): deck.append(_cell(Vector3i(x,20,z),yaw))
			for z in [50,56]: exits.append(_cell(Vector3i(x,20,z),yaw))
		nav.set_bridge(991,deck,exits)
		await process_frame
		var offset_start := _point(Vector3(60.8574,21,51.9883),yaw)
		var goal := _cell(Vector3i(62,20,42),yaw)
		worker.position = offset_start
		_expect(nav.line_walkable_flat(worker.current_cell(),goal), "cell-centre shortcut appears legal: %d" % yaw)
		_expect(not nav.line_walkable_flat_from(offset_start,goal), "actual-position shortcut rejects river corner: %d" % yaw)
		# A newly assigned task may interrupt a walk between centres. It must
		# first reach a safe waypoint instead of cutting the bank's corner.
		_walk(offset_start,goal,.04)
		for delta in [.016,.04,.07,.15]:
			for destination in [Vector3i(62,20,42),Vector3i(64,20,35)]:
				var start := _point(Vector3(62.5,21,64.5),yaw)
				var end := _cell(destination,yaw)
				_walk(start,end,delta)
				_walk(Vector3(end)+Vector3(.5,1,.5),_cell(Vector3i(62,20,64),yaw),delta)
		# Leisure walks use the same physical-origin guard.
		worker.position = offset_start
		worker.walk_nearby(goal)
		_expect(not worker.is_walking(), "leisure rejects unsafe direct crossing: %d" % yaw)
	nav.remove_bridge(991)
	for failure in failures: push_error(failure)
	print("BridgeCornerWalkingTest: ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

func _cell(cell: Vector3i, yaw: int) -> Vector3i:
	return CENTRE + Vector3i((Basis(Vector3.UP,yaw*PI*.5)*Vector3(cell-CENTRE)).round())

func _point(point: Vector3, yaw: int) -> Vector3:
	var pivot := Vector3(CENTRE)+Vector3(.5,1,.5)
	return pivot+Basis(Vector3.UP,yaw*PI*.5)*(point-pivot)

func _walk(start: Vector3, goal: Vector3i, delta: float) -> void:
	worker.stop_walking()
	worker.position = start
	_expect(worker.walk_to(goal), "bridge route begins: %s to %s" % [start,goal])
	var supported := true
	for i in range(4000):
		if not worker.is_walking(): break
		worker._follow_path(delta)
		if not worker._movement.has_floor_support(worker.current_cell()):
			supported = false
			break
	_expect(supported, "every movement step stays supported: %s / %.3f" % [worker.position,delta])
	_expect(not worker.is_walking() and worker.position.is_equal_approx(Vector3(goal)+Vector3(.5,1,.5)), "crossing finishes without getting stuck: %s / %.3f" % [goal,delta])
