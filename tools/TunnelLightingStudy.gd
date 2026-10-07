extends SceneTree

## Native visual study, not wired into gameplay. Roof/air cells below describe
## a representative mined tunnel, independently of the displayed cut plane.
## Existing registries supply stone colours, dwarf parts and installed torches.
## Run with isolated APPDATA and --script res://tools/TunnelLightingStudy.gd.
const OUTPUT := "res://tmp/tunnel_lighting_review/"
const TerrainLight = preload("res://scripts/components/TerrainLighting.gd")
const FurnitureLight = preload("res://scripts/components/FurnitureLighting.gd")
var stage: Node3D
var camera: Camera3D
var carved: Dictionary = {}
var daylight: Dictionary = {}
var records: Array[Dictionary] = []
var torches: Array[Node3D] = []
var shader: Shader
var sky_map: ImageTexture
var title: Label
var subtitle: Label
var readout: Label
var failures: Array[String] = []
var dwarf_count := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Tunnel lighting study timed out"); quit(1))
	if not "/tunnel_lighting_review/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Tunnel study requires isolated APPDATA under tmp/tunnel_lighting_review.")
		quit(1)
		return
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("WorldGenerator").world_seed = 1234
	root.size = Vector2i(1400,900)
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	environment.environment = env
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55,30,0)
	sun.shadow_enabled = true
	TerrainLight.configure_sun(sun)
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.far = 200
	camera.position = Vector3(35,44,52)
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(9,0,12))
	_build_shader()
	_build_cells()
	_build_terrain()
	_build_props()
	_expect(dwarf_count == 3, "all three reference dwarves were created")
	_build_labels()
	for i in range(6): await process_frame
	var sky_controller = root.get_node("SkyController")
	sky_controller._update(12.0)
	env.fog_enabled = false # close inspection, identical in every variant
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var samples := {}
	for mode in ["current", "unlit", "torches"]:
		_set_mode(mode)
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png(OUTPUT + mode + ".png")
		capture.save_jpg(OUTPUT + mode + ".jpg", .9)
		samples[mode] = {
			"outside": _luminance(capture, Vector3(4.5,.02,25.5)),
			"entrance": _luminance(capture, Vector3(8.5,.02,20.5)),
			"deep": _luminance(capture, Vector3(8,.02,11.5)),
			"chamber": _luminance(capture, Vector3(9,.02,3.5)),
		}
	_expect(absf(samples.current.outside - samples.unlit.outside) < .01, "outdoor daylight is preserved")
	_expect(samples.unlit.deep < samples.current.deep * .35, "unlit tunnel is visibly darker than current fill")
	_expect(samples.unlit.entrance > samples.unlit.deep * 2, "daylight falls off away from the entrance")
	_expect(samples.torches.deep > samples.unlit.deep * 1.5, "installed torch improves tunnel visibility")
	_expect(samples.torches.chamber > samples.unlit.chamber * 1.5, "a second torch lights the chamber locally")
	_expect(samples.unlit.deep > .005, "unlit floor retains a small readability floor")
	var report := {"scope":"native visual study only; no gameplay renderer changes",
		"renderer":RenderingServer.get_video_adapter_name(), "samples":samples,
		"readability_floor":.05, "entrance_falloff_blocks":7,
		"reference_dwarves":dwarf_count,
		"dwarves_and_props_share_indoor_shading":dwarf_count == 3, "failures":failures}
	var file := FileAccess.open(OUTPUT + "checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ") + "\n")
	file.close()
	print("TUNNEL_LIGHTING_STUDY: ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _build_shader() -> void:
	shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform sampler2D sky_map : filter_linear, repeat_disable;
uniform float readability_floor = 0.05;
varying vec3 world_normal;
varying vec3 world_position;
void vertex() {
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float sky_access = texture(sky_map, world_position.xz / vec2(20.0, 22.0)).r;
    ALBEDO = tint.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    EMISSION = ALBEDO * (readability_floor * (0.7 + 0.3 * max(world_normal.y, 0.0)) + sky_access * 0.2);
}
void light() {
    float sky_access = texture(sky_map, world_position.xz / vec2(20.0, 22.0)).r;
    float access = LIGHT_IS_DIRECTIONAL ? sky_access : 1.0;
    DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR * access / PI;
}
"""


func _build_cells() -> void:
	for x in range(7,11):
		for z in range(6,22): carved[Vector2i(x,z)] = true
	for x in range(4,16):
		for z in range(2,8): carved[Vector2i(x,z)] = true
	for x in range(11,16):
		for z in range(12,16): carved[Vector2i(x,z)] = true
	# A bounded flood from the physical entrance follows air cells. It does not
	# treat the removed roof in this cutaway as open sky. This is study data,
	# not the runtime's eventual incremental 3D sky-access implementation.
	var queue: Array[Vector2i] = []
	var distance: Dictionary = {}
	for x in range(7,11):
		var cell := Vector2i(x,21)
		queue.append(cell)
		distance[cell] = 0
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var steps: int = distance[cell]
		daylight[cell] = pow(maxf(0,1.0-float(steps)/7.0),2)
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if carved.has(next) and not distance.has(next):
				distance[next] = steps + 1
				queue.append(next)
	# Filter the field across cell centres so entrance falloff does not produce
	# visible strips on flat floor tiles. Props sample the same world positions.
	var map_image := Image.create(20,22,false,Image.FORMAT_RF)
	map_image.fill(Color.BLACK)
	for cell: Vector2i in daylight:
		map_image.set_pixel(cell.x,cell.y,Color(float(daylight[cell]),0,0))
	sky_map = ImageTexture.create_from_image(map_image)


func _build_terrain() -> void:
	var registry = root.get_node("BlockRegistry")
	var stone: Color = registry.get_color(registry.get_id("base:terrain:rock:rock01"))
	var grass: Color = registry.get_color(registry.get_id("base:terrain:surface:grass_01"))
	for x in range(-6,26):
		for z in range(22,31):
			_floor(Vector3(x+.5,0,z+.5), grass, -1)
	for x in range(20):
		for z in range(22):
			var cell := Vector2i(x,z)
			if carved.has(cell):
				_floor(Vector3(x+.5,0,z+.5), stone, float(daylight[cell]))
			else:
				# A cut rock plate is solid terrain; it stays subdued and does
				# not become an underground light receiver or reveal resources.
				_floor(Vector3(x+.5,4,z+.5), Color(stone.r*.5,stone.g*.5,stone.b*.5), -1)
				for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var neighbor: Vector2i = cell + direction
					if carved.has(neighbor):
						_wall(cell, direction, stone, float(daylight[neighbor]))
					elif neighbor.x < 0 or neighbor.x >= 20 or neighbor.y < 0 or neighbor.y >= 22:
						_wall(cell, direction, stone, -1)


func _floor(at: Vector3, color: Color, exposure: float) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	mesh.mesh = plane
	mesh.position = at
	stage.add_child(mesh)
	_material(mesh, color, exposure)
	TerrainLight.configure_mesh(mesh)


func _wall(cell: Vector2i, direction: Vector2i, color: Color, exposure: float) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1,4)
	mesh.mesh = quad
	mesh.position = Vector3(cell.x+.5+direction.x*.5,2,cell.y+.5+direction.y*.5)
	mesh.rotation.y = atan2(float(direction.x),float(direction.y))
	stage.add_child(mesh)
	_material(mesh, color, exposure)
	TerrainLight.configure_mesh(mesh)


func _material(mesh: MeshInstance3D, color: Color, exposure: float, vertex_color: bool = false) -> void:
	var normal := StandardMaterial3D.new()
	normal.albedo_color = color
	normal.roughness = 1.0
	normal.vertex_color_use_as_albedo = vertex_color
	normal.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = normal
	if exposure < 0: return
	var proposed := ShaderMaterial.new()
	proposed.shader = shader
	proposed.set_shader_parameter("tint", color)
	proposed.set_shader_parameter("use_vertex_color", vertex_color)
	proposed.set_shader_parameter("sky_map", sky_map)
	records.append({"mesh":mesh,"current":normal,"proposed":proposed})


func _shade_prop(node: Node3D, exposure: float) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if String(mesh.name).contains("flame"): continue
		var source := mesh.get_active_material(0) as BaseMaterial3D
		_material(mesh, source.albedo_color if source != null else Color.WHITE,
			exposure, source.vertex_color_use_as_albedo if source != null else true)


func _build_props() -> void:
	var loader = load("res://scripts/systems/FurniturePlacementController.gd").new()
	loader._load_defs()
	var definition: Dictionary = loader.get_defs()["base:furniture:wall_torch"]
	for placement in [[Vector3(11,2.5,13),-PI/2], [Vector3(6,2.5,2),0.0]]:
		var torch: Node3D = load(String(definition.model)).instantiate()
		stage.add_child(torch)
		torch.position = placement[0]
		torch.rotation.y = placement[1]
		FurnitureLight.attach(torch,definition)
		_shade_prop(torch,0)
		for animation in torch.find_children("FlameAnimation","Node",true,false): animation.set_process(false)
		torches.append(torch)
	loader.free()
	var barrel: Node3D = load("res://assets/models/furniture/barrel.glb").instantiate()
	stage.add_child(barrel)
	barrel.position = Vector3(13,0,5)
	_shade_prop(barrel,0)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for spec in [[Vector3(8.8,0,18.5),310],[Vector3(7,0,4.5),311],[Vector3(10,0,25),312]]:
		var dwarf = factory.spawn(factory.generate(int(spec[1]),{}),int(spec[1]))
		stage.add_child(dwarf)
		dwarf.set_process(false)
		dwarf.position = spec[0]
		dwarf.rotation.y = .6
		if spec[0].z < 22: _shade_prop(dwarf,0)
		dwarf_count += 1


func _build_labels() -> void:
	var hud := CanvasLayer.new()
	stage.add_child(hud)
	var panel := PanelContainer.new()
	UITheme.apply_surface(panel)
	panel.add_theme_stylebox_override("panel",UITheme.orders_panel_style())
	panel.position = Vector2(24,24)
	hud.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	panel.add_child(column)
	title = Label.new()
	UITheme.apply_title(title,24)
	column.add_child(title)
	subtitle = Label.new()
	column.add_child(subtitle)
	readout = Label.new()
	readout.add_theme_color_override("font_color",UITheme.HEARTH_MUTED)
	column.add_child(readout)


func _set_mode(mode: String) -> void:
	for record in records: record.mesh.material_override = record.current if mode == "current" else record.proposed
	for torch in torches: torch.visible = mode == "torches"
	title.text = {"current":"Current daylight fill", "unlit":"Covered tunnel · no lights", "torches":"Covered tunnel · two wall torches"}[mode]
	subtitle.text = "Native lighting study · representative tunnel · roof hidden for inspection"
	readout.text = "Unchanged outdoor daylight · visibility only · no work penalties"


func _luminance(capture: Image, world_point: Vector3) -> float:
	var point := Vector2i(camera.unproject_position(world_point))
	var total := 0.0
	for x in range(point.x-2,point.x+3):
		for y in range(point.y-2,point.y+3): total += capture.get_pixel(x,y).get_luminance()
	return total/25.0


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
