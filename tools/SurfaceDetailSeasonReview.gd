extends SceneTree

## Isolates the detail refresh enqueue cost from tree/material rebuilds.
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var generator := root.get_node("WorldGenerator")
	generator.world_seed = 1234
	generator._cache_block_ids()
	generator._layout_profile = generator.load_macro_layout_profile()
	generator._build_noise_instances()
	generator._build_seeded_maps()
	generator._apply_edge_detail()
	generator._maps_ready = true
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	scene.add_child(environment)
	var flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details.initialize_layout()
	var registry := root.get_node("SurfaceDetailRegistry")
	var expected: Array[String] = []
	for record: Dictionary in details._records.values():
		if String(registry.get_definition(record.definition).get("kind","")) in ["shrub","flower","reed"]: expected.append(record.id)
	var failures: Array = []
	var report := {"records":details._records.size(),"plant_records":expected.size(),"cases":{}}
	for scenario: String in ["empty","half_pending","all_pending"]:
		var samples: Array[float] = []
		var pending := 0 if scenario == "empty" else expected.size()/2 if scenario == "half_pending" else expected.size()
		for repeat in range(15):
			details._visual_queue.clear()
			for index in range(pending): details._visual_queue.append(expected[index])
			var started := Time.get_ticks_usec()
			details._on_season_changed("summer")
			samples.append((Time.get_ticks_usec()-started)/1000.0)
			# Repeated events during a partly drained queue must neither duplicate nor
			# lose a plant. Keep the already queued prefix in its original order.
			var actual: Array = details._visual_queue.duplicate()
			var sorted_expected: Array = expected.duplicate()
			actual.sort(); sorted_expected.sort()
			if actual != sorted_expected: failures.append("queued identities differ: "+scenario)
			if pending > 0 and details._visual_queue.slice(0,pending) != expected.slice(0,pending): failures.append("pending order changed: "+scenario)
		samples.sort()
		report.cases[scenario] = {"median_ms":samples[7],"p95_ms":samples[14]}
	report["failures"] = failures
	var name := "season_queue_after.json" if "--after" in OS.get_cmdline_user_args() else "season_queue_before.json"
	var file := FileAccess.open("res://tmp/surface_review/"+name,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("SURFACE_SEASON_QUEUE_", "PASS" if failures.is_empty() else "FAIL", " ",report)
	quit(0 if failures.is_empty() else 1)
