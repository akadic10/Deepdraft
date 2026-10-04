extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("Apple spawn audit timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var world := root.get_node("WorldGenerator")
	world.generate(1388941899)
	while not bool(world.get_streaming_stats().get("maps_ready",false)) or world.is_generating():
		await process_frame
	var flora: Node3D = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	root.add_child(flora)
	flora.set_process(false)
	var counts: Dictionary = {}
	var apples: Array = []
	var nearby: Dictionary = {}
	var candidate_gates: Dictionary = {"low_enough":0,"wet_enough":0,"in_grove":0}
	var apple: Dictionary = {}
	for sp in flora._species:
		if sp.name == "apple":
			apple = sp
	for cx in range(74):
		for cz in range(74):
			var h: int = flora._hash(cx,cz,101)
			var wx: int = cx*14+h%14
			var wz: int = cz*14+floori(float(h)/14.0)%14
			if wx >= 1024 or wz >= 1024:
				continue
			var height: int = world.get_surface_y(wx,wz)
			if height >= 12 and height <= 30:
				candidate_gates.low_enough += 1
				if flora._moisture_weight(apple.placement,world.get_moisture(wx,wz)) > 0:
					candidate_gates.wet_enough += 1
					if flora._grove_weight(apple.placement,wx,wz) > 0:
						candidate_gates.in_grove += 1
			var tree: Node3D = flora._try_spawn_cell(cx,cz,14)
			if tree == null:
				continue
			var parts := String(tree.name).split("_")
			var key: String = parts[0]+"_"+parts[1]
			counts[key] = counts.get(key,0)+1
			if abs(tree.position.x-512) < 150 and abs(tree.position.z-512) < 150:
				nearby[key] = nearby.get(key,0)+1
			if parts[0] == "apple":
				var mesh: MeshInstance3D = tree.find_children("*","MeshInstance3D",true,false)[0]
				var bounds: AABB = mesh.get_aabb()
				apples.append({"name":String(tree.name),"stage":parts[1],"position":[tree.position.x,tree.position.y,tree.position.z],"model":tree.get_child(0).scene_file_path,"bounds":[bounds.size.x,bounds.size.y,bounds.size.z],"distance_to_start":Vector2(tree.position.x-512,tree.position.z-512).length()})
	apples.sort_custom(func(a,b): return a.distance_to_start < b.distance_to_start)
	var report := {"seed":world.world_seed,"season":flora._season,"counts":counts,"near_start_300_square":nearby,"apple_candidate_gates":candidate_gates,"apples":apples}
	var file := FileAccess.open("res://tmp/apple_redesign_preview/spawn_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("APPLE_SPAWN_COUNTS ",counts)
	print("APPLE_NEAR_START ",nearby)
	print("APPLE_NEAREST ",apples.slice(0,5))
	print("APPLE_SPAWN_AUDIT_OK")
	quit(0)
