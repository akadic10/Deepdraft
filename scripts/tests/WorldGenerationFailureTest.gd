extends SceneTree

## A failed world generation must say so on the loading screen and stay
## covered, instead of waiting forever for maps that never arrive.

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("World generation failure test timed out"); quit(1))
	var saves = root.get_node("SaveManager")
	_expect(saves.configure_storage_for_testing("user://generation_failure_test"), "isolated save directory")
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var generator = root.get_node("WorldGenerator")
	var screen = current_scene.get_node("WorldLoadingScreen")
	var reported: Array[String] = []
	generator.generation_failed.connect(func(reason: String): reported.append(reason))
	_expect(generator.generation_error.is_empty(), "a running generation has no error")
	# Stands in for the generator's own failure paths (invalid profile or layout).
	generator._fail("test layout failure")
	await process_frame
	await process_frame
	_expect(reported == ["test layout failure"], "generation_failed reports the reason once")
	_expect(screen._art.failure == "test layout failure", "loading screen shows the failure")
	_expect(not screen._released, "a failed world is never revealed")
	generator.prepare_for_world_reload()
	generator._reset_generation_state()
	_expect(generator.generation_error.is_empty(), "the next generation starts without the old error")
	saves.reset_storage_after_testing()
	for failure: String in failures: push_error(failure)
	print("WORLD_GENERATION_FAILURE_OK" if failures.is_empty() else "WORLD_GENERATION_FAILURE_FAIL")
	quit(0 if failures.is_empty() else 1)
