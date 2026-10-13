extends Node3D

## Isolated small-world graphics lab. Nothing here is loaded by the main scene.
## Uses production voxel meshing, material identities, assets and roof lighting.
const OUT := "res://tmp/visual_study_20261012/art_pass_3/"
const TerrainScript = preload("StudyTerrain.gd")
const LightRules = preload("res://scripts/components/TerrainLighting.gd")
var ready_for_review := false
var terrain
var field
var environment: Environment
var sun: DirectionalLight3D
var camera: Camera3D
var study_shader: Shader
var materials: Array[Dictionary] = []
var bindings: Array[Dictionary] = []
var props: Array[Dictionary] = []
var terrain_pair: Dictionary
var floor_pair: Dictionary
var water_pair: Dictionary
var study := true
var detailed_ground := true
var ground_button: Button
var phase := "Day"
var sample_open := false
var capture_mode := false
var animation_time := 0.0
var target := Vector3(48,20,47)
var azimuth := 0.52
var elevation := 0.79
var distance := 66.0
var orbiting := false
var summary: Label
var metrics: Label
var mode_button: Button
var edit_button: Button
var slice_label: Label
var _metrics_elapsed := 0.0
var last_remesh_ms := 0.0
var environment_art: Node3D
var original_trees: Array[Node3D] = []
var bounce_lights: Array[OmniLight3D] = []


func _ready() -> void:
	get_window().title = "Deepdraft - Visual study (32 x 32)"
	# This dedicated process never reads or overwrites a settlement save.
	SaveManager.configure_storage_for_testing("user://visual_study")
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager","WorldEventDirector"]:
		var owner := get_node_or_null("/root/"+id)
		if owner != null: owner.set_process(false)
	WorldClock.set_paused(true)
	WorldClock.restore_state({"year":1,"season":"summer","day":1,"hour":12.0,"speed":1,"paused":true})
	WorldGenerator.world_seed = 1234
	WeatherManager._seed_rng()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_environment()
	terrain = TerrainScript.new()
	add_child(terrain)
	terrain.create_world()
	field = preload("res://scripts/components/UndergroundLighting.gd").new()
	add_child(field)
	_build_study_shader()
	terrain.excavate_rooms()
	var source := StandardMaterial3D.new()
	source.vertex_color_use_as_albedo = true
	terrain_pair = _material_pair(field.make_material(source),true)
	floor_pair = _material_pair(field.make_material(source))
	_build_props()
	environment_art = preload("StudyEnvironmentArt.gd").new()
	add_child(environment_art)
	var art_source := StandardMaterial3D.new()
	art_source.vertex_color_use_as_albedo = true
	environment_art.build(terrain,field.make_material(art_source))
	_build_water()
	_build_ui()
	# Let deferred autoload startup finish before binding once. An earlier bind
	# created a second moon on direct launches, giving walls a purple cast.
	await get_tree().process_frame
	for light in get_children():
		if light is DirectionalLight3D and light != sun:
			remove_child(light)
			light.queue_free()
	SkyController.rebind_to_current_scene()
	SkyController.set_process(false)
	WeatherManager.set_weather("base:weather:clear")
	SkyController._darken = 1.0
	SkyController._vision = 1.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	await settle()
	_rebuild()
	apply_look(true,"Day")
	var lights := []
	for light in get_children():
		if light is DirectionalLight3D:
			lights.append({"name":light.name,"visible":light.visible,"color":light.light_color.to_html(),"energy":light.light_energy})
	print("VISUAL_STUDY_LIGHTS ",JSON.stringify(lights))
	ready_for_review = true
	print("VISUAL_STUDY_READY: 32×32 world; C compares; G compares ground; 1/2/3 time; [/] slice; RMB orbit; wheel zoom")


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	world_env.environment = environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55,-25,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	LightRules.configure_sun(sun)
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 39
	camera.far = 160
	add_child(camera)
	camera.current = true
	_update_camera()


func _build_study_shader() -> void:
	# In-memory experiment: all roof-light sampling and local-light behavior
	# remain the shipped shader. Its source file is never edited by the study.
	var original: Shader = load("res://scripts/shaders/underground_lighting.gdshader")
	var detail := FileAccess.get_file_as_string("res://tools/visual_study/terrain_detail.gdshaderinc")
	study_shader = Shader.new()
	study_shader.code = original.code.replace("uniform vec4 tint", "uniform bool study_terrain = false;\nuniform vec4 tint")
	# Terrain chamfer vertices lie just inside the logical solid. Sample the exposed
	# face's air cell, rather than the deliberately bright slice-plate fallback.
	study_shader.code = study_shader.code.replace("    sky_access = actor_sky_access", """
    if (study_terrain && UV2.x > 2.5) {
        vec3 n = abs(world_normal);
        vec3 axis = n.y >= max(n.x,n.z) ? vec3(0.0,sign(world_normal.y),0.0) : (n.x >= n.z ? vec3(sign(world_normal.x),0.0,0.0) : vec3(0.0,0.0,sign(world_normal.z)));
        vec3 air_cell = floor(world_position+axis*0.15);
        sample_position = clamp(world_position+axis*0.15,air_cell+vec3(0.12),air_cell+vec3(0.88));
    }
    sky_access = actor_sky_access""")
	study_shader.code = study_shader.code.replace("    ROUGHNESS = 1.0;", detail + "\n    ROUGHNESS = 1.0;")


func _material_pair(current: ShaderMaterial, is_terrain := false) -> Dictionary:
	for pair in materials:
		if pair.current == current and pair.terrain == is_terrain: return pair
	var proposed := current.duplicate() as ShaderMaterial
	proposed.shader = study_shader
	proposed.set_shader_parameter("study_terrain",is_terrain)
	var pair := {"current":current,"study":proposed,"terrain":is_terrain}
	materials.append(pair)
	# Keep live sky-page/fog updates wired to both treatments; no duplicate
	# light solver, actor field, or terrain identity is introduced.
	field._material_cache["study:%d" % proposed.get_instance_id()] = proposed
	return pair


func _bind_model(node: Node3D) -> void:
	field.bind_tree(node)
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override is ShaderMaterial:
			bindings.append({"mesh":mesh,"surface":-1,"pair":_material_pair(mesh.material_override)})
		else:
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as ShaderMaterial
				if material != null: bindings.append({"mesh":mesh,"surface":surface,"pair":_material_pair(material)})


func _model(path: String, at: Vector3, yaw := 0.0) -> Node3D:
	var node: Node3D = (load(path) as PackedScene).instantiate()
	# Static GLBs store their palette in vertex colors. Match the production
	# furniture/flora owners rather than relying on the GLB import material.
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.roughness = 1.0
	solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		mesh.material_override = solid
	add_child(node)
	node.position = Vector3(TerrainScript.ORIGIN)+at
	node.rotation.y = yaw
	props.append({"node":node,"floor":floori(node.position.y)})
	return node


func _build_props() -> void:
	var loader = load("res://scripts/systems/FurniturePlacementController.gd").new()
	loader._load_defs()
	var defs: Dictionary = loader.get_defs()
	var placements := [
		["wooden_table",Vector3(6,21,8),0.0],
		["wooden_chair",Vector3(6,21,10),PI],
		["wooden_chair",Vector3(6,21,6),0.0],
		["barrel",Vector3(4.5,21,5.5),0.0],
		["barrel",Vector3(5.7,21,5.5),0.0],
		["log_bed",Vector3(14,21,5),0.0],
		["crude_workbench",Vector3(19,21,9),0.0],
		["bench",Vector3(14,21,11),0.0],
		["wooden_torch",Vector3(5,22.15,4),0.0],
		["wooden_torch",Vector3(9,22.15,4),0.0],
		["wooden_torch",Vector3(15,22.15,4),0.0],
		["wooden_torch",Vector3(20,22.15,4),0.0],
		["wooden_torch",Vector3(6.5,22.15,16),0.0],
		["wooden_torch",Vector3(19.5,22.15,16),0.0]]
	for placement in placements:
		var def: Dictionary = defs["base:furniture:"+placement[0]]
		var node := _model(def.model,placement[1],placement[2])
		preload("res://scripts/components/FurnitureLighting.gd").attach(node,def)
		for animation in node.find_children("FlameAnimation","Node",true,false): animation.set_process(false)
		_bind_model(node)
	loader.free()
	# Keep the shipped trees for the comparison treatment.
	for spec in [[Vector2i(2,24),"pine/pine_mature"], [Vector2i(8,28),"oak/oak_sapling"],
		[Vector2i(17,28),"pine/pine_sapling"], [Vector2i(21,24),"oak/oak_sapling"],
		[Vector2i(30,25),"pine/pine_mature"], [Vector2i(30,17),"pine/pine_sapling"],
		[Vector2i(3,29),"pine/pine_sapling"]]:
		var cell: Vector2i = spec[0]
		var node := _model("res://assets/models/flora/trees/"+spec[1]+".glb",Vector3(cell.x+.5,terrain.surface_height(cell.x,cell.y)+1,cell.y+.5),cell.x*.61)
		original_trees.append(node)
		_bind_model(node)
	for cell in [Vector2i(3,21),Vector2i(11,27),Vector2i(20,26),Vector2i(29,22),Vector2i(1,29),Vector2i(23,22)]:
		var node := _model("res://assets/models/flora/bushes/wild_strawberry/wild_strawberry_summer.glb",Vector3(cell.x+.5,terrain.surface_height(cell.x,cell.y)+1,cell.y+.5))
		_bind_model(node)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for spec in [[Vector3(8,21,10),301], [Vector3(17,21,10),302], [Vector3(13,18,25),303]]:
		var actor = factory.spawn(factory.generate(spec[1],{}),spec[1])
		add_child(actor)
		actor.position = Vector3(TerrainScript.ORIGIN)+spec[0]
		actor.rotation.y = -.5
		actor.set_process(false)
		props.append({"node":actor,"floor":floori(actor.position.y)})
		_bind_model(actor)
	# Modest local fill stands in for torch bounce in this art study. It is
	# short-ranged and authored for these rooms, not simulated indirect light.
	for at in [Vector3(7,23,10),Vector3(17,23,10)]:
		var light := OmniLight3D.new()
		light.position = Vector3(TerrainScript.ORIGIN)+at
		light.light_color = Color("d6ad74")
		light.light_energy = .8
		light.omni_range = 5.5
		light.light_size = 1.5
		light.shadow_enabled = false
		add_child(light)
		bounce_lights.append(light)


func _build_water() -> void:
	var source := StandardMaterial3D.new()
	source.albedo_color = Color("3a91ac")
	source.roughness = .65
	source.metallic_specular = .12
	var current: ShaderMaterial = field.make_material(source,true)
	current.set_shader_parameter("water_surface",true)
	var motion := Image.create(256,1,false,Image.FORMAT_RGF)
	motion.fill(Color(0,.3,0))
	current.set_shader_parameter("water_motion",ImageTexture.create_from_image(motion))
	water_pair = _material_pair(current)
	water_pair.study.set_shader_parameter("tint",Color("286f84"))
	var water_specs: Array = []
	for z in range(32):
		var edges: Vector2i = terrain.river_bounds(z)
		water_specs.append([Vector3((edges.x+edges.y+1)*.5,21.8 if z<13 else 16.8,z+.5),Vector2(edges.y-edges.x+1,1),0])
	water_specs.append([Vector3(26.5,19.3,13),Vector2(3,5),1])
	water_specs.append([Vector3(26.5,16.82,13.8),Vector2(3,1.6),2])
	# Batch the contour-following strips by slice level, retaining per-vertex
	# fall/foam tags and shore UVs. More river bends should not mean more draws.
	var batches: Dictionary = {}
	for spec in water_specs:
		var floor_y := floori(spec[0].y)
		if not batches.has(floor_y): batches[floor_y] = preload("StudyMesh.gd").new()
		var plane := PlaneMesh.new()
		plane.size = spec[1]
		var basis := Basis(Vector3.RIGHT,PI*.5) if spec[2] == 1 else Basis.IDENTITY
		batches[floor_y].append_arrays(plane.get_mesh_arrays(),Transform3D(basis,Vector3(TerrainScript.ORIGIN)+spec[0]),Vector2(0,spec[2]))
	for floor_y: int in batches:
		var mesh := MeshInstance3D.new()
		mesh.mesh = batches[floor_y].to_mesh()
		mesh.material_override = current
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		bindings.append({"mesh":mesh,"surface":-1,"pair":water_pair})
		props.append({"node":mesh,"floor":floor_y})


func _rebuild() -> void:
	var start := Time.get_ticks_usec()
	terrain.rebuild(terrain_pair.study if study else terrain_pair.current,floor_pair.study if study else floor_pair.current,study,study and detailed_ground)
	last_remesh_ms = (Time.get_ticks_usec()-start)/1000.0
	for entry in props:
		entry.node.visible = entry.floor <= terrain.slice_y+1
	for tree in original_trees: tree.visible = not study and tree.position.y <= terrain.slice_y+1
	if environment_art != null:
		environment_art.visible = study
		environment_art.set_slice(terrain.slice_y)
	_update_labels()


func apply_look(proposed: bool, time_of_day: String) -> void:
	var geometry_changed := study != proposed
	study = proposed
	phase = time_of_day
	var hour: float = {"Day":12.0,"Dusk":SkyController.current_event_hours().get("sunset",20.0),"Night":23.0}[phase]
	WorldClock.hour = hour
	SkyController._apply_static_base()
	SkyController._update(hour)
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES if study else Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if study else Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("9eafb7") if phase=="Day" else Color("849ba9")
	environment.ambient_light_sky_contribution = 0.0 if study else 1.0
	environment.ambient_light_energy = (.32 if phase == "Night" else .55) if study else .4
	environment.background_mode = Environment.BG_COLOR if study else Environment.BG_SKY
	environment.background_color = Color("29383e") if phase=="Day" else Color("18252e")
	environment.ssao_enabled = study
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 2.0
	environment.ssao_power = 1.5
	environment.ssao_light_affect = .3
	environment.ssao_ao_channel_affect = 1.0
	environment.glow_enabled = study
	environment.glow_intensity = .42
	environment.glow_bloom = .03
	# Keep distant haze, but the small study's foreground should remain clear.
	if study:
		get_viewport().msaa_3d = Viewport.MSAA_4X
		environment.fog_density *= .35
		sun.shadow_caster_mask |= LightRules.TERRAIN_LAYER
		sun.light_angular_distance = 1.4
		if phase == "Day":
			sun.light_color = Color("ffeccf")
			sun.light_energy = 1.1
	else:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		LightRules.configure_sun(sun)
		sun.light_angular_distance = 0.0
	for light in bounce_lights: light.visible = study
	for binding in bindings:
		var material: ShaderMaterial = binding.pair.study if study else binding.pair.current
		if binding.surface < 0: binding.mesh.material_override = material
		else: binding.mesh.set_surface_override_material(binding.surface,material)
	if geometry_changed: _rebuild()
	_update_labels()


func set_slice(height: int) -> void:
	terrain.slice_y = clampi(height,17,31)
	_rebuild()

func toggle_ground() -> void:
	if not study: return
	detailed_ground = not detailed_ground
	_rebuild()


func toggle_sample() -> void:
	sample_open = not sample_open
	terrain.set_sample_open(sample_open)
	_rebuild()
	_update_labels()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var panel := PanelContainer.new()
	UITheme.apply_surface(panel)
	panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	panel.position = Vector2(18,18)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Deepdraft · Environment study"
	UITheme.apply_title(heading,23)
	column.add_child(heading)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size",14)
	column.add_child(summary)
	var row := HBoxContainer.new()
	column.add_child(row)
	mode_button = _button("",func(): apply_look(not study,phase),row)
	for time_of_day in ["Day","Dusk","Night"]:
		_button(time_of_day,func(): apply_look(study,time_of_day),row)
	var slices := HBoxContainer.new()
	column.add_child(slices)
	_button("−4",func(): set_slice(terrain.slice_y-4),slices)
	_button("−1",func(): set_slice(terrain.slice_y-1),slices)
	slice_label = Label.new()
	slice_label.custom_minimum_size.x = 68
	slice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slices.add_child(slice_label)
	_button("+1",func(): set_slice(terrain.slice_y+1),slices)
	_button("+4",func(): set_slice(terrain.slice_y+4),slices)
	_button("Full",func(): set_slice(31),slices)
	edit_button = _button("Mine test opening",toggle_sample,column)
	var views := HBoxContainer.new()
	column.add_child(views)
	_button("Whole scene",func(): set_view("Scene"),views)
	_button("Rooms",func(): set_view("Rooms"),views)
	_button("Stream",func(): set_view("Stream"),views)
	_button("Trees",func(): set_view("Trees"),views)
	var ground_row := HBoxContainer.new()
	column.add_child(ground_row)
	ground_button = _button("",toggle_ground,ground_row)
	_button("Ground close-up",func(): set_view("Ground"),ground_row)
	var help := Label.new()
	help.text = "RMB orbit · Wheel zoom · C compare\nG compare ground · 1 / 2 / 3 time · [ / ] slice · Esc close"
	help.add_theme_font_size_override("font_size",12)
	help.add_theme_color_override("font_color",UITheme.HEARTH_MUTED)
	column.add_child(help)
	metrics = Label.new()
	metrics.text = "Measuring GPU…\nLast terrain rebuild —"
	metrics.add_theme_font_size_override("font_size",12)
	column.add_child(metrics)
	var note := Label.new()
	layer.add_child(note)
	note.text = "32 × 32 art study · Prototype geometry · Scripted water · No settlement saves"
	note.add_theme_font_size_override("font_size",13)
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	note.position = Vector2(18,get_viewport().get_visible_rect().size.y-30)


func _button(text: String, action: Callable, parent: Node) -> Button:
	var button := UITheme.make_button(text,"",Vector2(48,30))
	UITheme.apply_hearth_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _update_labels() -> void:
	if summary == null: return
	summary.text = (("Environment art · Pass 3" if detailed_ground else "Environment art · Pass 2") if study else "Current assets")+" · "+phase
	ground_button.text = "Ground: Pass 3" if detailed_ground else "Ground: Pass 2"
	ground_button.disabled = not study
	mode_button.text = "Compare: Current" if study else "Compare: Study"
	slice_label.text = "Level %d" % terrain.slice_y
	edit_button.text = "Restore test wall" if sample_open else "Mine test opening"


func _process(delta: float) -> void:
	if not ready_for_review: return
	animation_time = 12.0 if capture_mode else animation_time+delta
	for key in ["current","study"]: water_pair[key].set_shader_parameter("water_time",animation_time)
	_metrics_elapsed += delta
	if _metrics_elapsed >= .5 and not capture_mode:
		_metrics_elapsed = 0
		var data := render_metrics()
		metrics.text = "GPU %.2f ms · %d draws\nLast terrain rebuild %.1f ms" % [data.gpu_ms,data.draw_calls,last_remesh_ms]


func render_metrics() -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	return {"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(rid),
		"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)}


func _update_camera() -> void:
	camera.position = target+Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))*distance
	camera.look_at(target)


func set_view(preset: String) -> void:
	azimuth = .52
	elevation = .79
	match preset:
		"Scene": target = Vector3(48,20,47); camera.size = 39
		"Rooms": target = Vector3(45,21,40); camera.size = 25
		"Stream": target = Vector3(58.5,20,44); camera.size = 21; azimuth = .85
		"Trees": target = Vector3(37,23,59); camera.size = 18
		"Ground": target = Vector3(46,18,59); camera.size = 20; elevation = .58
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: orbiting = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size+(-2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2),12,65)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C: apply_look(not study,phase)
			KEY_G: toggle_ground()
			KEY_1: apply_look(study,"Day")
			KEY_2: apply_look(study,"Dusk")
			KEY_3: apply_look(study,"Night")
			KEY_BRACKETLEFT: set_slice(terrain.slice_y-1)
			KEY_BRACKETRIGHT: set_slice(terrain.slice_y+1)
			KEY_ESCAPE: get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed: orbiting = false
	if event is InputEventMouseMotion and orbiting:
		azimuth -= event.relative.x*.006
		elevation = clampf(elevation+event.relative.y*.004,.4,1.2)
		_update_camera()


func settle() -> void:
	for i in range(5): await get_tree().process_frame
	while field.is_updating(): await get_tree().process_frame
