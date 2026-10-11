extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var generator = root.get_node("WorldGenerator")
	var manager = root.get_node("WaterManager")
	root.get_node("WorldClock").paused = true
	generator.generate(1630876908)
	while not generator._maps_ready: await process_frame
	manager.initialize()
	var initial: float = manager.flow.total_volume()
	var report: Array = []
	for i in 900:
		manager.step(0.1)
		if i not in [99,299,599,669,839,899]: continue
		var flooded: Array = []
		for cell: Vector3i in manager.flow.mass:
			if generator.get_waterline(cell.x,cell.z)>=0 or manager.flow.volume(cell)<0.001: continue
			flooded.append({"cell":[cell.x,cell.y,cell.z],"depth":manager.flow.volume(cell)})
		flooded.sort_custom(func(a,b): return a.depth>b.depth)
		var flooded_volume := 0.0
		for entry: Dictionary in flooded: flooded_volume += float(entry.depth)
		var item := {"time":(i+1)*0.1,"count":flooded.size(),"flood_volume":flooded_volume,"added":manager.flow.added,"drained":manager.flow.drained,"balance":manager.flow.total_volume()-initial-manager.flow.added+manager.flow.drained,"cells":flooded}
		report.append(item)
		print("FLOOD_DIAG ",JSON.stringify({"time":item.time,"count":item.count,"flood_volume":flooded_volume,"added":item.added,"drained":item.drained,"balance":item.balance,"deepest":flooded.slice(0,5)}))
	var river: Array = []
	for p: Vector2i in generator.river_layout.route:
		var floor_y: int = generator.get_surface_y(p.x,p.y)
		var cell := Vector3i(p.x,floor_y+1,p.y)
		river.append({"cell":[p.x,floor_y+1,p.y],"depth":manager.flow.volume(cell)})
	var file := FileAccess.open("res://tmp/water_review/flood_diagnosis.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":1630876908,"samples":report,"route":river},"\t"))
	file.close()
	generator.prepare_for_world_reload()
	quit()
