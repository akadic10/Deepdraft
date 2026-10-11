extends SceneTree
const OUTPUT := "res://tmp/water_review/dry_stone"
func _init() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Dry stone preview timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2795346874))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var terrain = current_scene.get_node("Renderer")
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	while not terrain._overview_built or terrain._overview_tile_nodes.size()!=1024: await process_frame
	while not water.initialized or not water.dirty_tiles.is_empty(): await process_frame
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	root.size = Vector2i(1200,850)
	root.get_node("SkyController").rebind_to_current_scene()
	root.get_node("WorldClock").hour = 11.0
	root.get_node("SkyController")._update(11.0)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14
	current_scene.add_child(camera)
	camera.make_current()
	var stone: Vector3i = gen.river_layout.dry_stone
	var lake: Vector2i = gen.lake_center
	var toward_lake := Vector3(lake.x-stone.x,0,lake.y-stone.z).normalized()
	var point := Vector3(stone)+Vector3(0.5,1.5,0.5)
	camera.position = point+toward_lake*12+Vector3(0,12,0)
	camera.look_at(point)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/submerged.png")
	if not terrain.get_node("Water").find_children("*RockMouth*","",false,false).is_empty():
		push_error("Decorative mouth still present")
		quit(1)
		return
	# A temporary local drawdown shows the real cube, without any material or
	# render overrides. This isolated preview never saves the changed water.
	for dx in range(-5,6):
		for dz in range(-5,6):
			var x := stone.x+dx
			var z := stone.z+dz
			if x<0 or z<0 or x>=1024 or z>=1024: continue
			water.extract(Vector3i(x,gen.get_surface_y(x,z)+1,z),100)
	while not water.dirty_tiles.is_empty(): await process_frame
	camera.size = 9
	point = Vector3(stone)+Vector3(0.5,1.0,0.5)
	camera.position = point+toward_lake*7+Vector3(0,18,0)
	camera.look_at(point)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/exposed.png")
	print("DryStonePreview: PASS stone=",stone," whole-world tiles=",terrain._overview_tile_nodes.size())
	quit()
