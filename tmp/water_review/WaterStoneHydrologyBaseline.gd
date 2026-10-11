extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	gen.generate(2795346874)
	while not gen._maps_ready: await process_frame
	water.initialize()
	var report := {"initial":_hydrology_hash(water)}
	for i in 100: water.step(0.1)
	report.future = _hydrology_hash(water)
	var target := "res://tmp/water_review/loose_stones_hydrology_before.json"
	if "--compare" in OS.get_cmdline_user_args():
		var before = JSON.parse_string(FileAccess.get_file_as_string(target))
		if report != before:
			push_error("Hydrology changed: "+str(report)+" vs "+str(before))
			gen.prepare_for_world_reload()
			quit(1)
			return
		print("WaterStoneHydrologyBaseline: PASS identical initial water and 100-step future")
	else:
		FileAccess.open(target,FileAccess.WRITE).store_string(JSON.stringify(report))
		print("WaterStoneHydrologyBaseline: captured ",report)
	gen.prepare_for_world_reload()
	quit()

func _hydrology_hash(water: Node) -> String:
	var state: Dictionary = water.serialize_state()
	state.erase("stones")
	state.erase("next_stone_id")
	return JSON.stringify(state,"",false,true).sha256_text()
