extends SceneTree

const OUTPUT := "res://tmp/water_review/appearance"
func _init() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Appearance preview timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2795346874))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var gen = root.get_node("WorldGenerator")
	var water = root.get_node("WaterManager")
	var terrain = current_scene.get_node("Renderer")
	while not terrain._overview_built or terrain._overview_tile_nodes.size()!=1024: await process_frame
	while not water.dirty_tiles.is_empty(): await process_frame
	root.get_node("SkyController").rebind_to_current_scene()
	root.get_node("WorldClock").hour = 10.0
	root.get_node("SkyController")._update(10.0)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	current_scene.add_child(camera)
	camera.make_current()
	root.size = Vector2i(1200,800)
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	# Give the measured current field time to settle without any fixture flow.
	for i in 900:
		water.step(0.1)
		if i%2==0: await process_frame
	var water_view = terrain.get_node("Water")
	await process_frame
	await process_frame
	var paused_time = water_view.material.get_shader_parameter("water_time")
	for i in 12: await process_frame
	if paused_time != water_view.material.get_shader_parameter("water_time"):
		push_error("Paused water animation advanced")
		quit(1)
		return
	var started := Time.get_ticks_usec()
	water_view.motion.update(water.flow,0.1)
	print("Appearance current update usec=",Time.get_ticks_usec()-started," slots=",water_view.motion.slots.size())
	var route: Array = gen.river_layout.route
	var bend := Vector2i.ZERO
	var drop := Vector3.ZERO
	var fall_direction := Vector3.ZERO
	for i in range(8,route.size()-8):
		var a: Vector2i = route[i-1]
		var b: Vector2i = route[i]
		var c: Vector2i = route[i+1]
		var high: int = gen.get_surface_y(a.x,a.y)+2
		var low: int = gen.get_surface_y(b.x,b.y)+2
		if bend==Vector2i.ZERO and a-b!=b-c and high==low and i>route.size()/3: bend = b
		if drop==Vector3.ZERO and high-low>=6:
			drop = Vector3(b.x+0.5,(high+low)*0.5,b.y+0.5)
			fall_direction = Vector3(b.x-a.x,0,b.y-a.y)
	var sites := {
		"bend": [Vector3(bend.x,gen.get_surface_y(bend.x,bend.y)+2,bend.y),Vector3(-14,38,16),28.0],
		"falls": [drop,fall_direction*24+Vector3(-fall_direction.z,0,fall_direction.x)*15+Vector3(0,18,0),23.0],
		"lake": [Vector3(gen.river_layout.outlet),Vector3(25,32,20),35.0],
		"distant": [Vector3(bend.x,gen.get_surface_y(bend.x,bend.y)+2,bend.y),Vector3(45,70,45),85.0]}
	for label in sites:
		camera.size = sites[label][2]
		camera.position = sites[label][0]+sites[label][1]
		camera.look_at(sites[label][0])
		await _clip(label,water)
		print("Appearance ",label," elapsed=",water.elapsed," active currents=",water_view.motion.velocities.size()," last solver step usec=",water.last_step_usec)
	# Actual terrain dam and backed-up water, using the game's reversible dev dam.
	var dam: Vector3i = water.dev_toggle_dam()
	for i in 1200:
		water.step(0.1)
		if i%4==0: await process_frame
	camera.size = 26
	camera.position = Vector3(dam)+Vector3(22,32,25)
	camera.look_at(Vector3(dam))
	await _clip("dam",water)
	print("WaterAppearancePreview: PASS whole-world tiles=",terrain._overview_tile_nodes.size())
	quit()

func _clip(label: String,water: Node) -> void:
	for i in 48:
		water.step(0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT+"/%s_%03d.png" % [label,i])
