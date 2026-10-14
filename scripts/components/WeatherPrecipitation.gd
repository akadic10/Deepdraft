extends Node3D

## One bounded rain mesh. Physical roofs and slice concealment both clip it;
## removing a roof visually never rains into the room underneath.
var mesh := ImmediateMesh.new()
var visual := MeshInstance3D.new()
var drops: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _scan_left := 0.0
var _draw_left := 0.0
var _centre := Vector3.INF
var _weather := ""
var _lighting: Node
var _view: Node3D
var _slice: Node
var visible_streaks := 0

func _ready() -> void:
	process_priority = 57
	_rng.seed = 0x5241494E
	_view = get_tree().get_first_node_in_group("work_audio_view")
	_slice = get_tree().get_first_node_in_group("work_feedback_slice")
	_lighting = get_tree().get_first_node_in_group("underground_lighting")
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = material
	add_child(visual)

func _process(delta: float) -> void:
	var profile: Dictionary = WeatherManager.current_definition().get("precipitation", {})
	if profile.is_empty() or SaveManager.is_loading() or not is_instance_valid(_view) or not _view.is_inside_tree() or not WorldGenerator._maps_ready:
		visual.visible = false
		visible_streaks = 0
		return
	var context: Dictionary = _view.get_work_audio_context()
	if context.is_empty(): return
	visual.visible = true
	if not WorldClock.paused and WorldClock.speed > 0: _time += delta
	_scan_left -= delta
	_draw_left -= delta
	if _scan_left <= 0 or _centre.distance_squared_to(context.focus) > 16 or _weather != WeatherManager.current_weather_id():
		_scan(context.focus, profile)
		_scan_left = .75
		_weather = WeatherManager.current_weather_id()
	if _draw_left <= 0:
		_draw_rain(profile)
		_draw_left = 1.0 / 30.0

func _scan(focus: Vector3, profile: Dictionary) -> void:
	_centre = focus
	drops.clear()
	for i in int(profile.streaks):
		var x := clampf(focus.x + _rng.randf_range(-profile.radius, profile.radius), 0, 1023.99)
		var z := clampf(focus.z + _rng.randf_range(-profile.radius, profile.radius), 0, 1023.99)
		var roof := WorldGenerator.get_surface_y(floori(x), floori(z))
		if is_instance_valid(_lighting): roof = _lighting._roof_height(Vector2i(floori(x), floori(z)))
		drops.append({"point": Vector3(x, roof + 1.05, z), "phase": _rng.randf(), "strength": _rng.randf_range(.16, .32)})

func _draw_rain(profile: Dictionary) -> void:
	mesh.clear_surfaces()
	visible_streaks = 0
	var slice_y := int(_slice.get_slice_y()) if is_instance_valid(_slice) else 127
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var right := camera.global_basis.x * float(profile.width)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for i in mini(drops.size(), roundi(float(profile.streaks) * float(profile.intensity))):
		var drop: Dictionary = drops[i]
		var base: Vector3 = drop.point
		if base.y > slice_y + 1: continue
		var height := minf(float(profile.height), slice_y + 1.0 - base.y)
		if height < .15: continue
		var y := fposmod(float(drop.phase) * height - _time * float(profile.speed), height)
		var bottom := base + Vector3(0, y, 0)
		var top := bottom + Vector3(-float(profile.slant) * .12, minf(float(profile.length), height - y), 0)
		var color := Color(profile.color, float(drop.strength))
		vertices.append_array([bottom-right, bottom+right, top+right, bottom-right, top+right, top-right])
		for j in 6: colors.append(color)
		visible_streaks += 1
	if vertices.is_empty(): return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vertices.size():
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(vertices[i])
	mesh.surface_end()
