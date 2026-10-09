extends SceneTree

## Native renderer contact sheet of the exact registry assets, plus picked crops.
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var packed := "--packed" in OS.get_cmdline_user_args()
	var young := "--young" in OS.get_cmdline_user_args()
	root.size = Vector2i(1540,1090)
	var canvas := Control.new()
	root.add_child(canvas)
	current_scene = canvas
	root.get_node("WorldGenerator").world_seed = 1234
	var back := ColorRect.new()
	back.color = Color("#202d30")
	back.size = Vector2(root.size)
	canvas.add_child(back)
	_label(canvas,"YOUNG SHRUBS / SEASONAL GROWTH" if young else "UPROOTED SHRUBS / WRAPPED ROOTS" if packed else "WILD SHRUBS  /  SEASONAL VOXEL ART",Vector2(30,18),26)
	_label(canvas,"Same camera and world scale. Four young seasons beside the mature plant; young plants have no fruit." if young else "Same camera and world scale in every panel. One block = 8 voxels. Picked plants retain their stems and foliage.",Vector2(30,54),17)
	var species := ["blueberry", "elderberry", "wild_strawberry"]
	var seasons := ["spring", "summer", "autumn", "winter", "picked"]
	for row in range(3):
		var definition: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition("base:flora:%s_bush" % species[row])
		_label(canvas,definition.display_name.to_upper(),Vector2(30,94+row*324),20)
		for col in range(5):
			var season: String = seasons[col]
			var position := Vector2(30+col*300,126+row*324)
			var box := SubViewportContainer.new()
			box.position = position
			box.size = Vector2(280,255)
			canvas.add_child(box)
			var viewport := SubViewport.new()
			viewport.size = Vector2i(280,255)
			viewport.own_world_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			box.add_child(viewport)
			var stage := Node3D.new()
			viewport.add_child(stage)
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color("#425657")
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_energy = .7
			env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			stage.add_child(env)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-55,-35,0)
			sun.shadow_enabled = true
			stage.add_child(sun)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 3.9
			stage.add_child(camera)
			camera.position = Vector3(4,4.2,6)
			camera.look_at(Vector3(0,.95,0))
			var path := String(definition.picked_models["autumn" if row == 1 else "summer"]) if season == "picked" else String(definition.seasonal_models[season])
			if packed: path = String(definition.transplant.models[("autumn_picked" if row == 1 else "summer_picked") if season == "picked" else season])
			if young: path = String(definition.seasonal_models.summer if season == "picked" else definition.young_models[season])
			var plant := load(path).instantiate() as Node3D
			stage.add_child(plant)
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = 1
			for mesh: MeshInstance3D in plant.find_children("*", "MeshInstance3D", true, false): mesh.material_override = material
			var floor_mesh := MeshInstance3D.new()
			var floor_box := BoxMesh.new()
			floor_box.size = Vector3(3,.18,3)
			floor_mesh.mesh = floor_box
			floor_mesh.position.y = -.09
			var floor_mat := StandardMaterial3D.new()
			floor_mat.albedo_color = Color("#58664c") if season != "winter" else Color("#aababa")
			floor_mesh.material_override = floor_mat
			stage.add_child(floor_mesh)
			_label(canvas, "Mature · Summer" if young and season == "picked" else season.capitalize() + (" · Autumn" if row == 1 else " · Summer") if season == "picked" else season.capitalize(),position+Vector2(0,260),17)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/cutting_review/young_art.png" if young else "res://tmp/transplant_review/packed_art.png" if packed else "res://tmp/shrub_review/seasonal_art.png")
	print("SHRUB_ART_CAPTURE_PASS")
	quit()


func _label(parent: Node, text: String, position: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#e0d9c6"))
	parent.add_child(label)
