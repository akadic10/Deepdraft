extends SceneTree

## Live play advances water per frame, spreading each 0.1 s tick's cells over the
## frames until the next tick so the solver no longer hitches one frame at 10 Hz.
## The spread path must leave exactly the state that whole ticks (step) leave.
const TICKS := 200
const FRAMES := [0.013, 0.037, 0.021, 0.029] # one tick, split unevenly
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var generator = root.get_node("WorldGenerator")
	var manager = root.get_node("WaterManager")
	root.get_node("WorldClock").paused = true
	generator.generate(1234)
	while not generator.is_maps_ready(): await process_frame
	manager.reset()
	manager.initialize()
	var busiest_tick := 0
	for i in TICKS:
		manager.step(0.1)
		busiest_tick = maxi(busiest_tick, manager.last_frame_cells)
	var whole := _state(manager)
	manager.reset()
	manager.initialize()
	var busiest_frame := 0
	for i in TICKS:
		for seconds: float in FRAMES:
			manager.advance(seconds)
			busiest_frame = maxi(busiest_frame, manager.last_frame_cells)
	var spread := _state(manager)
	check(whole.elapsed == spread.elapsed, "spread ticks keep the water clock")
	check(whole.flow == spread.flow, "spread ticks leave the same water, queue and totals")
	check(whole.moisture == spread.moisture, "spread ticks leave the same soil moisture")
	check(busiest_tick > 0, "the river keeps the solver busy")
	check(busiest_frame * 2 <= busiest_tick, "no frame runs most of a tick: %d of %d cells" % [busiest_frame, busiest_tick])
	# A save between frames finishes the tick in progress, so the saved queue
	# sits on a tick boundary and no partly-run tick is lost.
	manager.advance(0.05)
	var saved: Dictionary = manager.serialize_state()
	check(int(saved.accumulator_usec) == 0, "a save mid-tick finishes that tick")
	check(int(saved.elapsed_usec) == whole.elapsed + 100000, "the finished tick is counted once")
	print("WaterTickSpread: busiest tick %d cells, busiest frame %d" % [busiest_tick, busiest_frame])
	generator.prepare_for_world_reload()
	for failure: String in failures: push_error(failure)
	print("WATER_TICK_SPREAD_OK" if failures.is_empty() else "WATER_TICK_SPREAD_FAIL")
	quit(0 if failures.is_empty() else 1)

func _state(manager: Node) -> Dictionary:
	return {"flow": manager.flow.serialize(), "moisture": manager.moisture.serialize(), "elapsed": manager.elapsed_usec}
