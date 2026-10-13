extends "res://scripts/tests/WorkerCraftingTest.gd"

func _run() -> void:
	await _setup_crafting_fixture()
	clock_node.set_paused(false)
	var drains: Array[float] = []
	for speed in [1.0, 2.0, 3.0]:
		clock_node.set_speed(speed)
		worker.sleep = 0.9
		worker._process(0.1)
		drains.append(0.9 - worker.sleep)
		print("FATIGUE_SAMPLE speed=", speed, " real_seconds=0.1 drain=", drains.back(), " game_hours=", 0.1 * clock_node.game_hours_per_real_second())
	clock_node.set_paused(true)
	var before: float = worker.sleep
	worker._process(0.1)
	print("PAUSED_DRAIN=", before - worker.sleep)
	var reproduced := drains[0] > 0.0 and is_equal_approx(drains[0], drains[1]) and is_equal_approx(drains[0], drains[2])
	print("FATIGUE_SPEED_REPRODUCED" if reproduced else "FATIGUE_SPEED_NOT_REPRODUCED")
	quit(0 if reproduced else 1)
