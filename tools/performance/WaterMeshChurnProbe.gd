extends SceneTree

## Diagnostic: how much visible water actually moves between water-tile mesh
## rebuilds in a loaded save. Runs the live game for --seconds, then, after every
## water tick, compares each tile's visible surface with what each candidate
## policy last "rendered", and counts the rebuilds each policy would make.
## Run with an isolated APPDATA holding a copy of the save as quicksave.json.
const THRESHOLDS := [0.0, 1.0/256.0, 1.0/128.0, 1.0/64.0, 1.0/32.0, 1.0/16.0]
var output := ""
var seconds := 30.0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
	_run.call_deferred()

func _run() -> void:
	var clock = root.get_node("WorldClock")
	var saves = root.get_node("SaveManager")
	var water = root.get_node("WaterManager")
	clock.set_paused(true)
	saves.set_process(false)
	var placeholder := Node3D.new()
	placeholder.scene_file_path = "res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene = placeholder
	saves.set_process(true)
	if not saves.request_load(): quit(2); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	var renderer = current_scene.get_node("Renderer")
	var view = renderer.get_node("Water")
	var settle := Time.get_ticks_msec()
	while not view.is_loading_complete() and Time.get_ticks_msec()-settle < 120000: await process_frame
	clock.set_paused(false)
	clock.set_speed(1)
	var baselines: Array = [] # per threshold: tile -> {key: level}
	for t in THRESHOLDS: baselines.append({})
	var rebuilds: Array = []
	var wet_rebuilds: Array = []
	for t in THRESHOLDS:
		rebuilds.append(0)
		wet_rebuilds.append(0)
	var delta_hist := {} # bucket label -> count of (tile, tick) changes
	var ticks := 0
	var tiles_with_water := 0
	var stats_start: Dictionary = view.get_mesh_stats()
	var last_elapsed: float = water.elapsed
	var started := Time.get_ticks_msec()
	var first := true
	while Time.get_ticks_msec()-started < seconds*1000.0:
		await process_frame
		if water.elapsed == last_elapsed: continue
		last_elapsed = water.elapsed
		var tiles := _visible_by_tile(water)
		tiles_with_water = maxi(tiles_with_water, tiles.size())
		if first:
			for b: Dictionary in baselines:
				for tile: Vector2i in tiles: b[tile] = tiles[tile]
			first = false
			continue
		ticks += 1
		var all_tiles := tiles.keys()
		for tile: Vector2i in baselines[0]: if not tiles.has(tile): all_tiles.append(tile)
		for tile: Vector2i in all_tiles:
			var now: Dictionary = tiles.get(tile, {})
			for i in THRESHOLDS.size():
				var before: Dictionary = baselines[i].get(tile, {})
				var change := _change(before, now)
				if i == 0 and (change.wet or change.max > 0.0): _bucket(delta_hist, change)
				if change.wet or (change.max > 0.0 and change.max >= THRESHOLDS[i]):
					rebuilds[i] += 1
					if change.wet: wet_rebuilds[i] += 1
					baselines[i][tile] = now
	var stats_end: Dictionary = view.get_mesh_stats()
	var sim_seconds := ticks*0.1
	var report := {"ticks":ticks,"sim_seconds":sim_seconds,"tiles_with_visible_water":tiles_with_water,
		"actual_built":int(stats_end.built)-int(stats_start.built),
		"actual_unchanged":int(stats_end.unchanged)-int(stats_start.unchanged),
		"actual_oldest_ms_end":stats_end.oldest_ms,"change_histogram":delta_hist,"policies":[]}
	for i in THRESHOLDS.size():
		report.policies.append({"threshold_blocks":THRESHOLDS[i],"rebuilds":rebuilds[i],
			"per_second":rebuilds[i]/maxf(sim_seconds,0.1),"forced_by_wet_dry":wet_rebuilds[i]})
	print(JSON.stringify(report, "  "))
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0)

## Visible surface water per 32×32 tile, as the renderer would draw it from the
## surface view: cells at or above standing depth, level = bottom + volume.
func _visible_by_tile(water: Node) -> Dictionary:
	var tiles := {}
	var flow = water.flow
	for key: Vector3i in flow.mass:
		var units: int = flow.mass[key]
		var amount := float(units)/1000000.0
		if amount < water.standing_depth: continue
		var tile := Vector2i(int(key.x/32.0), int(key.z/32.0))
		if not tiles.has(tile): tiles[tile] = {}
		tiles[tile][key] = key.y+amount
	return tiles

func _change(before: Dictionary, now: Dictionary) -> Dictionary:
	var wet := before.size() != now.size()
	var most := 0.0
	for key: Vector3i in now:
		if not before.has(key): wet = true; continue
		most = maxf(most, absf(float(now[key])-float(before[key])))
	return {"wet":wet, "max":most}

func _bucket(hist: Dictionary, change: Dictionary) -> void:
	var label := "wet_dry_change"
	if not change.wet:
		var m: float = change.max
		if m < 1.0/1024.0: label = "a_under_1_1024"
		elif m < 1.0/256.0: label = "b_1_1024_to_1_256"
		elif m < 1.0/64.0: label = "c_1_256_to_1_64"
		elif m < 1.0/32.0: label = "d_1_64_to_1_32"
		elif m < 1.0/16.0: label = "e_1_32_to_1_16"
		else: label = "f_over_1_16"
	hist[label] = int(hist.get(label, 0))+1
