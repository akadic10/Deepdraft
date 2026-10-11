extends SceneTree

func _init() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	gen.generate(1675083273)
	while not gen._maps_ready: await process_frame
	water.initialize()
	var mouth: Vector3i = gen.spring_cave.mouth
	var back: Vector2i = gen.river_layout.spring_back
	var side := Vector2i(-back.y,back.x)
	print("MOUTH ",mouth," BACK ",back," ROUTE ",gen.river_layout.route.slice(0,22))
	for d in range(-6,4):
		var row: Array = []
		for u in range(-4,5):
			var p := Vector2i(mouth.x,mouth.z)+back*d+side*u
			var span: Vector2i = water.flow.spans(p)[0]
			var key := Vector3i(p.x,span.x,p.y)
			row.append("%d:%d/%.2f" % [u,span.x,water.flow.volume(key)])
		print("ROW ",d,": ",row)
	gen.prepare_for_world_reload()
	print("SpringGapProbe: DONE")
	quit()
