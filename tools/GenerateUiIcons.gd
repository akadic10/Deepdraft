extends SceneTree

## Renders the Hearthblock UI icons (doc 259) to transparent PNGs in form B: the
## staged model from the 3/4 camera with flat warm light and a blocky dark outline.
## The tile is not baked in: UITheme draws it in the icon's family colour.
## It also renders the Sky Dial's layers (doc 23): each staged sky piece from the front,
## tilted down, in the framing data/ui/sky_dial.json gives, with the same light.
##   python3 tools/voxel_assets/build.py icons
##   python3 tools/voxel_assets/build.py sky
##   godot --path . --script res://tools/GenerateUiIcons.gd [-- --only=orders,colony | --sky]
## Reads the staged `icons` and `sky` manifests and writes res://assets/ui/icons/<name>.png
## and res://assets/ui/sky_dial/<piece>.png only. --only renders those icons and no sky;
## --sky renders the sky alone. --app renders the project icon alone (res://icon.png): the
## colony dwarf on a deep-earth tile with stepped strata and a warm lantern glow.
const STAGED := "res://tmp/voxel_migration_20261018/staged/"
const OUT := "res://assets/ui/icons/"
const SKY_OUT := "res://assets/ui/sky_dial/"
const SKY_DATA := "res://data/ui/sky_dial.json"
const PIXELS := 144                       # 72 px buttons at a 2x UI scale
const RENDER := PIXELS * 2                # rendered larger, then downsampled
const OUTLINE := Color("1e1712")
const OUTLINE_SHARE := 0.023              # outline width as a share of the icon
const SKY_OUTLINE_SHARE := 0.008          # the dial's edge, about as thick on screen as an icon's
const APP_OUT := "res://icon.png"
const APP_PIXELS := 256
const APP_MODEL := "assets/ui/icon_models/colony.glb"
const APP_YAW := 32.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600).timeout.connect(func(): push_error("GenerateUiIcons timed out"); quit(1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(640, 400))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var only := PackedStringArray()
	if "--app" in OS.get_cmdline_user_args():
		var ok := await _render_app_icon()
		quit(0 if ok else 1)
		return
	var sky_only := "--sky" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=").split(",")
	if not sky_only:
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGED + "icons.json"))
		if not manifest is Dictionary:
			push_error("No staged icons manifest; run python3 tools/voxel_assets/build.py icons first")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		var count := 0
		for asset: Dictionary in manifest.assets:
			var name := String(asset.path).get_file().get_basename()
			if not only.is_empty() and not name in only: continue
			var image := _outlined(await _render(STAGED + String(asset.path), float(asset.authoring.get("yaw", 0.0))))
			image.resize(PIXELS, PIXELS, Image.INTERPOLATE_LANCZOS)
			if image.save_png(ProjectSettings.globalize_path(OUT + name + ".png")) != OK:
				push_error("Could not save icon " + name)
				quit(1)
				return
			count += 1
		print("UI_ICONS_OK: %d icons" % count)
	if only.is_empty():
		var layers := await _render_sky()
		if layers < 0:
			quit(1)
			return
		print("SKY_DIAL_LAYERS_OK: %d layers" % layers)
	quit()


func _render(path: String, yaw: float) -> Image:
	var viewport := _studio(Vector2i(RENDER, RENDER))
	var scene: Node3D = viewport.get_child(0)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Cannot read staged icon " + path)
		quit(1)
	var model: Node3D = doc.generate_scene(state)
	scene.add_child(model)
	model.rotation_degrees.y = yaw
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	# Fit the turned model's own box corners, not a wider axis-aligned box.
	var corners: Array[Vector3] = []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for corner in range(8):
			corners.append(mesh.global_transform * mesh.get_aabb().get_endpoint(corner))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 200.0
	scene.add_child(camera)
	camera.position = Vector3(10, 8, 12)
	camera.look_at(Vector3.ZERO)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in corners:
		var local: Vector3 = camera.basis.inverse() * point
		low = Vector2(minf(low.x, local.x), minf(low.y, local.y))
		high = Vector2(maxf(high.x, local.x), maxf(high.y, local.y))
	var middle := (low + high) / 2.0
	model.position -= camera.basis * Vector3(middle.x, middle.y, 0)
	# Leave room for the outline inside the picture.
	camera.size = maxf(high.x - low.x, high.y - low.y) / (1.0 - 4.0 * OUTLINE_SHARE)
	return await _capture(viewport)


## The Sky Dial's layers: every staged sky piece seen from the front, tilted down by the
## framing's pitch, with the icons' light. A `picture` piece is rendered in the framing the
## whole dial shares, so the layers stack; a `sprite` (the sun, the moon, a cloud) round its
## own origin at the same scale, for the dial to place. `unshaded` pieces give light, and an
## `outline` piece (the frame, the dial's edge) wears the icons' outline. Returns the layers
## written, or -1.
func _render_sky() -> int:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGED + "sky.json"))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKY_DATA))
	if not manifest is Dictionary or not data is Dictionary:
		push_error("No staged sky manifest; run python3 tools/voxel_assets/build.py sky first")
		return -1
	var framing: Dictionary = data.picture
	var area := Rect2(float(framing.rect[0]), float(framing.rect[1]), float(framing.rect[2]), float(framing.rect[3]))
	var scale := float(framing.width) / area.size.x   # pixels a cell in the saved layer
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SKY_OUT))
	var count := 0
	for asset: Dictionary in manifest.assets:
		var name := String(asset.path).get_file().get_basename()
		var authoring: Dictionary = asset.authoring
		var image := await _render_sky_piece(STAGED + String(asset.path), area, scale, float(framing.pitch), authoring)
		if image == null: return -1
		if bool(authoring.get("outline", false)): image = _outlined(image, SKY_OUTLINE_SHARE)
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		if image.save_png(ProjectSettings.globalize_path(SKY_OUT + name + ".png")) != OK:
			push_error("Could not save sky layer " + name)
			return -1
		count += 1
	return count


func _render_sky_piece(path: String, area: Rect2, scale: float, pitch: float, authoring: Dictionary) -> Image:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Cannot read staged sky piece " + path)
		return null
	var model: Node3D = doc.generate_scene(state)
	model.scale = Vector3.ONE * 16.0   # one cell a unit, as the framing counts them
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	if bool(authoring.get("unshaded", false)): material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tilt := deg_to_rad(pitch)
	var up := Vector3(0, cos(tilt), -sin(tilt))
	var back := Vector3(0, sin(tilt), cos(tilt))
	var reach := 0.0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for corner in range(8):
			var point: Vector3 = (mesh.transform * mesh.get_aabb().get_endpoint(corner)) * 16.0
			reach = maxf(reach, maxf(absf(point.x), absf(point.dot(up))))
	if String(authoring.get("framing", "picture")) == "sprite":
		# Round the piece's own origin, as far as its farthest cell and one more.
		reach = ceilf(reach) + 1.0
		area = Rect2(-reach, -reach, reach * 2.0, reach * 2.0)
	var viewport := _studio(Vector2i(roundi(area.size.x * scale) * 2, roundi(area.size.y * scale) * 2))
	var scene: Node3D = viewport.get_child(0)
	scene.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 1.0
	camera.far = 600.0
	scene.add_child(camera)
	camera.basis = Basis(Vector3.RIGHT, up, back)
	var middle := area.get_center()
	camera.position = Vector3(middle.x, 0, 0) + up * middle.y + back * 300.0
	camera.size = area.size.x
	return await _capture(viewport)


## The project icon: the colony dwarf, outlined like the UI icons, on a rounded tile of
## dark earth. Rendered at twice the size and downsampled, as the icons are.
func _render_app_icon() -> bool:
	var size := APP_PIXELS * 2
	var model := _outlined(await _render(STAGED + APP_MODEL, APP_YAW))
	var inner := roundi(size * 0.74)
	model.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
	var tile := _app_tile(size)
	tile.blend_rect(model, Rect2i(0, 0, inner, inner), Vector2i((size - inner) / 2, roundi(size * 0.13)))
	tile.resize(APP_PIXELS, APP_PIXELS, Image.INTERPOLATE_LANCZOS)
	if tile.save_png(ProjectSettings.globalize_path(APP_OUT)) != OK:
		push_error("Could not save the project icon")
		return false
	print("APP_ICON_OK")
	return true


## A rounded tile: stepped earth strata darkening with depth, a warm glow behind the
## dwarf and the icons' dark outline round the edge. Steps are whole cells so it reads
## as blocks.
func _app_tile(size: int) -> Image:
	var tile := Image.create(size, size, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0, 0, 0, 0))
	var strata: Array[Color] = [Color("7a5639"), Color("5e4130"), Color("6a5a4c"), Color("4a3a30"), Color("3a3532"), Color("221c18")]
	var cell := size / 32
	var radius := size * 0.17
	var border := maxi(2, roundi(size * 0.03))
	var glow := Vector2(size * 0.5, size * 0.52)
	for y in range(size):
		for x in range(size):
			var corner := Vector2(clampf(x + 0.5, radius, size - radius), clampf(y + 0.5, radius, size - radius))
			var reach := Vector2(x + 0.5, y + 0.5).distance_to(corner)
			if reach > radius: continue
			var cx := x / cell
			# Each stratum's lower edge wanders by whole cells, from the column's hash.
			var row := float(y / cell) + float(((cx * 7349 + 13) % 5) - 2) * 0.35
			var band := clampi(int(row / 32.0 * strata.size()), 0, strata.size() - 1)
			var colour: Color = strata[band]
			var light := 1.0 - clampf(Vector2(x, y).distance_to(glow) / (size * 0.55), 0.0, 1.0)
			# A few ore cells in the deeper strata, as in the mine icon.
			var fleck := (cx * 92821 + (y / cell) * 68917) % 37
			if band >= 3 and fleck == 0: colour = Color("d9893b")
			elif band >= 3 and fleck == 1: colour = Color("e9c247")
			colour = colour.lerp(Color("e8a24a"), light * light * 0.5)
			if reach > radius - border: colour = OUTLINE
			tile.set_pixel(x, y, colour)
	return tile


## A transparent viewport holding a scene with the icons' studio: an ambient fill and a
## warm key light from the upper left.
func _studio(pixels: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d9e4da")
	environment.environment.ambient_light_energy = 0.9
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.light_color = Color("ffe4bb")
	light.light_energy = 0.85
	light.rotation_degrees = Vector3(-52, -32, 0)
	scene.add_child(light)
	return viewport


func _capture(viewport: SubViewport) -> Image:
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	image.convert(Image.FORMAT_RGBA8)
	return image


## A square (Chebyshev) dilation of the silhouette gives a blocky outline that matches
## the cells. Running window counts keep it linear in the picture size. `share` is the
## outline's width as a share of the picture's.
func _outlined(image: Image, share := OUTLINE_SHARE) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var radius := maxi(1, roundi(w * share))
	var data := image.get_data()
	var mask := PackedInt32Array()
	mask.resize(w * h)
	for i in range(w * h):
		mask[i] = 1 if data[i * 4 + 3] > 96 else 0
	var rows := _dilate(mask, w, h, radius, 1, w)
	var both := _dilate(rows, h, w, radius, w, 1)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for i in range(w * h):
		if both[i] > 0: out.set_pixel(i % w, i / w, OUTLINE)
	out.blend_rect(image, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return out


## Marks every cell within `radius` of a set cell along one axis. `length` cells per
## line, `lines` lines; `step` moves along a line and `stride` to the next line.
func _dilate(source: PackedInt32Array, length: int, lines: int, radius: int, step: int, stride: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(source.size())
	for line in range(lines):
		var base := line * stride
		var inside := 0
		for i in range(mini(radius, length)):
			inside += source[base + i * step]
		for i in range(length):
			if i + radius < length: inside += source[base + (i + radius) * step]
			if i - radius - 1 >= 0: inside -= source[base + (i - radius - 1) * step]
			result[base + i * step] = 1 if inside > 0 else 0
	return result
