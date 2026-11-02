extends Node3D

## Rain and snow, drawn by the GPU (doc 24, "Rain and snow"). Drops belong to
## fixed world tiles, so moving the camera never reshuffles them. This node picks
## the tiles in view on two zoom levels, keeps the landing map and fades the
## weather in and out; the shader does the rest. A drop lands on the top solid
## block of its column, or on the water over it, so a roof hidden by the slice
## still keeps rain out of the room below.
const SHADER := preload("res://scripts/shaders/weather_precipitation.gdshader")
## Must match the size of the shader's `tiles` array.
const MAX_TILES := 192
const DROPS_PER_TILE := 256
## The smallest tile edge, in blocks; each zoom level doubles it.
const BASE_TILE := 8.0
## A zoom level starts where the fine tile edge is this share of the camera distance.
const TILE_PER_DISTANCE := 0.5
## Tiles are checked against the view over a band around the ground at screen
## centre: this share of the camera distance, up to these many blocks.
const BAND_SHARE := 0.4
const BAND_BELOW := 32.0
const BAND_ABOVE := 40.0
## Choose tiles again once the camera has moved this share of a fine tile.
const RESELECT_SHARE := 0.125
const FADE_SECONDS := 4.0
## Drops repeat their landing spots only after this many falls.
const LOOP_CYCLES := 4096.0
## Landing-map work per frame while caves, edits and water are read.
const BUILD_BUDGET_USEC := 1500
const UPLOAD_INTERVAL := 0.25
## Drops keep this share of their colour at night; full colour from this horizon brightness.
const NIGHT_LIGHT := 0.4
const DAY_HORIZON_LUMINANCE := 0.42

var visual := MultiMeshInstance3D.new()
var material := ShaderMaterial.new()
## Drops drawn this frame (tools/environment_audio/ReviewDetails.gd reads it).
var visible_streaks := 0
## Tiles drawn: x, y = world tile index; z = 0 on the fine level, 1 on the coarse.
var tiles := PackedVector3Array()
var tile_sizes := Vector2.ZERO
## 0..1; the weather fades in and out over FADE_SECONDS.
var amount := 0.0
var _profile: Dictionary = {}
var _cycle_time := 1.0
var _time := 0.0
var _view: Node3D
var _slice: Node
var _landing: Image
var _landing_texture: ImageTexture
var _roofs: Dictionary = {}    # Vector2i -> top solid y, where it differs from the heightmap
var _pending: Dictionary = {}  # Vector2i -> y to scan down from, or -1 to read water only
var _pending_order: Array[Vector2i] = []
var _cave_columns: Array[int] = []
var _edit_chunks: Array[Vector2i] = []
var _water_keys: Array = []
var _water_revision := -1
var _dirty := false
var _upload_left := 0.0
var _selected: Dictionary = {}  # the view the tiles were chosen for
var _fine_count := 0


func _ready() -> void:
	process_priority = 57
	_view = get_tree().get_first_node_in_group("work_audio_view")
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = QuadMesh.new()
	multimesh.instance_count = MAX_TILES * DROPS_PER_TILE
	# The shader places every drop; the instances only need valid transforms.
	var buffer := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
	while buffer.size() < multimesh.instance_count * 12: buffer.append_array(buffer)
	buffer.resize(multimesh.instance_count * 12)
	multimesh.buffer = buffer
	multimesh.visible_instance_count = 0
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shader = SHADER
	visual.material_override = material
	visual.visible = false
	add_child(visual)
	WorldData.block_changed.connect(_on_block_changed)
	WaterManager.surface_changed.connect(_on_water_changed)


func _process(delta: float) -> void:
	if SaveManager.is_loading() or not is_instance_valid(_view) or not _view.is_inside_tree() or not WorldGenerator.is_maps_ready():
		_hide()
		return
	# A new weather fades the old one out completely, then fades in.
	var target: Dictionary = WeatherManager.current_definition().get("precipitation", {})
	amount = move_toward(amount, 1.0 if not target.is_empty() and target == _profile else 0.0, delta / FADE_SECONDS)
	if amount <= 0.0 and target != _profile:
		_profile = target
		_apply_profile()
	var context: Dictionary = _view.get_work_audio_context()
	var camera := get_viewport().get_camera_3d()
	if amount <= 0.0 or _profile.is_empty() or context.is_empty() or camera == null:
		_hide()
		return
	if _landing == null: _start_landing()
	if WaterManager.initialized and WaterManager.revision != _water_revision:
		_water_revision = WaterManager.revision
		_water_keys = WaterManager.flow.mass.keys()
	_read_landing(BUILD_BUDGET_USEC)
	_upload_left -= delta
	if _dirty and _upload_left <= 0.0:
		_landing_texture.update(_landing)
		_dirty = false
		_upload_left = UPLOAD_INTERVAL
	if not WorldClock.paused and WorldClock.speed > 0:
		_time = fposmod(_time + delta, _cycle_time * LOOP_CYCLES)
	if not is_instance_valid(_slice): _slice = get_tree().get_first_node_in_group("work_feedback_slice")
	var slice_y := int(_slice.get_slice_y()) if is_instance_valid(_slice) else SliceController.MAX_SLICE_Y
	material.set_shader_parameter("time", _time)
	material.set_shader_parameter("slice_top", float(slice_y) + 1.0)
	var colour := Color.html(String(_profile.get("color", "#9fb6c6")))
	material.set_shader_parameter("tint", Color(colour * _daylight(), float(_profile.get("opacity", 0.3))))
	_show_tiles(camera, context.focus, float(context.zoom))
	visual.visible = true


## Where drops land in a column: the top of its highest solid block or the water on it.
func landing_at(col: Vector2i) -> float:
	if _landing == null: return -1.0
	var cell := _landing.get_pixel(col.y, col.x)
	var wet := roundi(cell.g * 255.0)
	return roundi(cell.r * 255.0) + 1.0 + (float(wet - 1) / 254.0 if wet > 0 else 0.0)


func _hide() -> void:
	visual.visible = false
	visual.multimesh.visible_instance_count = 0
	visible_streaks = 0


func _apply_profile() -> void:
	_selected = {}
	if _profile.is_empty(): return
	var snow := String(_profile.get("style", "rain")) == "snow"
	var height := float(_profile.get("height", 14.0))
	var speed := float(_profile.get("speed", 17.0))
	# Snow rests on the ground before it fades; rain splashes, longer on water.
	var linger := float(_profile.get("settle_seconds", 1.0)) if snow else float(_profile.get("splash_seconds", 0.18))
	var ripple := float(_profile.get("ripple_seconds", linger))
	_cycle_time = height / speed + (linger if snow else maxf(linger, ripple))
	_time = 0.0
	for key: String in ["width_px", "length_px", "size_px", "sway", "slant"]:
		if _profile.has(key): material.set_shader_parameter(key, float(_profile[key]))
	material.set_shader_parameter("style", 1 if snow else 0)
	material.set_shader_parameter("column_height", height)
	material.set_shader_parameter("fall_speed", speed)
	material.set_shader_parameter("splash_time", linger)
	material.set_shader_parameter("ripple_time", ripple)
	material.set_shader_parameter("cycle_time", _cycle_time)
	material.set_shader_parameter("cycle_count", LOOP_CYCLES)


## Drops dim with the sky: the horizon colour SkyController gives the fog.
func _daylight() -> float:
	var world := get_viewport().find_world_3d()
	if world == null or world.environment == null: return 1.0
	return lerpf(NIGHT_LIGHT, 1.0, clampf(world.environment.fog_light_color.get_luminance() / DAY_HORIZON_LUMINANCE, 0.0, 1.0))


# ── Tiles ─────────────────────────────────────────────────────────────────────

func _show_tiles(camera: Camera3D, focus: Vector3, zoom: float) -> void:
	var level_f := maxf(0.0, log(maxf(zoom, 1.0) * TILE_PER_DISTANCE / BASE_TILE) / log(2.0))
	var level := floori(level_f)
	var fine := BASE_TILE * pow(2.0, level)
	# Fine drops give way to coarse ones as the camera pulls back. The coarse
	# level has a quarter of the drops per block and one level shows four times
	# the ground, so drops per screen area stay even across the change.
	var coarse_share := (1.0 - pow(4.0, -(level_f - level))) / 0.75
	var shown := DROPS_PER_TILE * float(_profile.get("intensity", 0.6)) * amount
	var drops := Vector2(shown * (1.0 - coarse_share), shown * coarse_share)
	var view := {"tile": fine, "screen": camera.get_viewport().get_visible_rect().size, "fov": camera.fov}
	var moved: bool = _selected.is_empty() or _selected["tile"] != view["tile"] or _selected["screen"] != view["screen"] \
		or _selected["fov"] != view["fov"] or absf(focus.y - float(_selected["ground"])) > 4.0 \
		or camera.global_position.distance_to(_selected["origin"]) > fine * RESELECT_SHARE \
		or camera.global_basis.z.dot(_selected["facing"]) < 0.9998
	if moved:
		view.merge({"origin": camera.global_position, "facing": camera.global_basis.z, "ground": focus.y})
		_selected = view
		_choose_tiles(camera, focus, zoom, fine)
	material.set_shader_parameter("drops_shown", drops)
	visual.multimesh.visible_instance_count = tiles.size() * mini(DROPS_PER_TILE, ceili(maxf(drops.x, drops.y)))
	visible_streaks = roundi(_fine_count * drops.x + (tiles.size() - _fine_count) * drops.y)


## The tiles of both levels that the camera can see, nearest first if there are too many.
func _choose_tiles(camera: Camera3D, focus: Vector3, zoom: float, fine: float) -> void:
	var low := focus.y - minf(zoom * BAND_SHARE, BAND_BELOW)
	var high := focus.y + minf(zoom * BAND_SHARE, BAND_ABOVE) + float(_profile.get("height", 14.0))
	var reach := clampf(zoom * 3.5, 80.0, camera.far)
	var rect := camera.get_viewport().get_visible_rect().size
	# Where rays along the screen's edges, a little outside it, cross the band.
	# Corners alone are not enough: rays end at `reach`, and mid-edge rays reach further.
	var lo := Vector2(camera.global_position.x, camera.global_position.z)
	var hi := lo
	var edge: Array[Vector2] = []
	for share: float in [-.06, .25, .5, .75, 1.06]:
		edge.append_array([Vector2(share, -.06), Vector2(share, 1.06), Vector2(-.06, share), Vector2(1.06, share)])
	for point_on_screen: Vector2 in edge:
		var from := camera.project_ray_origin(point_on_screen * rect)
		var direction := camera.project_ray_normal(point_on_screen * rect)
		for y: float in [low, high]:
			var along := reach if direction.y > -0.001 else clampf((y - from.y) / direction.y, 0.0, reach)
			var point := from + direction * along
			lo = lo.min(Vector2(point.x, point.z))
			hi = hi.max(Vector2(point.x, point.z))
	var planes: Array[Plane] = []
	var inside := camera.project_position(rect * .5, camera.near + 1.0)
	for plane: Plane in camera.get_frustum():
		planes.append(plane if plane.distance_to(inside) < 0.0 else -plane)
	var drift := float(_profile.get("slant", 0.15)) * float(_profile.get("height", 14.0)) + float(_profile.get("sway", 0.0))
	var picked: Array[Array] = [[], []]
	for level in 2:
		var size := fine * (level + 1)
		var margin := size * RESELECT_SHARE * 2.0 + drift
		var last := Vector2i(ceili(WorldData.WORLD_SIZE_X / size) - 1, ceili(WorldData.WORLD_SIZE_Z / size) - 1)
		var first_tile := Vector2i(floori((lo.x - margin) / size), floori((lo.y - margin) / size)).clamp(Vector2i.ZERO, last)
		var last_tile := Vector2i(floori((hi.x + margin) / size), floori((hi.y + margin) / size)).clamp(Vector2i.ZERO, last)
		for tx in range(first_tile.x, last_tile.x + 1):
			for tz in range(first_tile.y, last_tile.y + 1):
				var box := AABB(Vector3(tx * size - margin, low - margin, tz * size - margin), Vector3(size + 2.0 * margin, high - low + 2.0 * margin, size + 2.0 * margin))
				if _box_in_view(box, planes):
					var centre := Vector2((tx + .5) * size, (tz + .5) * size)
					picked[level].append([centre.distance_squared_to(Vector2(focus.x, focus.z)), Vector3(tx, tz, level)])
	var room := MAX_TILES - mini(picked[1].size(), MAX_TILES)
	if picked[0].size() > room:
		picked[0].sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		picked[0].resize(room)
	tiles.clear()
	for entry: Array in picked[0] + picked[1].slice(0, MAX_TILES):
		tiles.append(entry[1])
	_fine_count = picked[0].size()
	tile_sizes = Vector2(fine, fine * 2.0)
	var padded := tiles.duplicate()
	padded.resize(MAX_TILES)
	material.set_shader_parameter("tiles", padded)
	material.set_shader_parameter("tile_count", tiles.size())
	material.set_shader_parameter("tile_sizes", tile_sizes)
	visual.custom_aabb = AABB(Vector3(lo.x - fine * 2.0, 0.0, lo.y - fine * 2.0), Vector3(hi.x - lo.x + fine * 4.0, WorldData.WORLD_SIZE_Y + high - low, hi.y - lo.y + fine * 4.0))


func _box_in_view(box: AABB, planes: Array[Plane]) -> bool:
	for plane: Plane in planes:
		# The box corner furthest inside this plane; outside means the whole box is.
		var corner := Vector3(box.position.x if plane.normal.x > 0.0 else box.end.x,
			box.position.y if plane.normal.y > 0.0 else box.end.y,
			box.position.z if plane.normal.z > 0.0 else box.end.z)
		if plane.distance_to(corner) > 0.0: return false
	return true


# ── Landing map ───────────────────────────────────────────────────────────────

func _start_landing() -> void:
	# The generated heightmap is the top solid block of every untouched column.
	# Its int32 bytes read as RGBA8 put the height in red and zero in green.
	_landing = Image.create_from_data(WorldData.WORLD_SIZE_Z, WorldData.WORLD_SIZE_X, false, Image.FORMAT_RGBA8, WorldGenerator.heightmap.to_byte_array())
	_landing.convert(Image.FORMAT_RG8)
	_landing_texture = ImageTexture.create_from_image(_landing)
	material.set_shader_parameter("landing", _landing_texture)
	# The columns that differ follow over the next frames: caves open to the
	# sky, mined or built columns, and water.
	for cave: Dictionary in WorldGenerator.get_cave_catalog():
		if cave.get("surface_open", false):
			for index: int in cave.columns: _cave_columns.append(index)
	_edit_chunks = WorldData.override_columns()
	_water_revision = -1


func _read_landing(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < budget_usec:
		if not _cave_columns.is_empty():
			var index: int = _cave_columns.pop_back()
			var col := Vector2i(floori(float(index) / WorldData.WORLD_SIZE_Z), index % WorldData.WORLD_SIZE_Z)
			_queue(col, WorldGenerator.get_surface_y(col.x, col.y))
		elif not _edit_chunks.is_empty():
			var chunk: Vector2i = _edit_chunks.pop_back()
			var tops := {}
			for cell: Vector3i in WorldData.column_overrides(chunk.x, chunk.y):
				tops[Vector2i(cell.x, cell.z)] = maxi(int(tops.get(Vector2i(cell.x, cell.z), -1)), cell.y)
			for col: Vector2i in tops:
				# Edits below an untouched surface leave the roof where it was.
				if tops[col] >= WorldGenerator.get_surface_y(col.x, col.y): _queue(col, tops[col])
		elif not _water_keys.is_empty():
			var key: Vector3i = _water_keys.pop_back()
			_queue(Vector2i(key.x, key.z), -1)
		elif not _pending_order.is_empty():
			var col: Vector2i = _pending_order.pop_back()
			_write_column(col, int(_pending[col]))
			_pending.erase(col)
		else:
			return


func _queue(col: Vector2i, scan_from: int) -> void:
	if not _pending.has(col): _pending_order.append(col)
	_pending[col] = maxi(int(_pending.get(col, -1)), scan_from)


func _roof(col: Vector2i) -> int:
	return int(_roofs.get(col, WorldGenerator.get_surface_y(col.x, col.y)))


func _write_column(col: Vector2i, scan_from: int) -> void:
	if col.x < 0 or col.y < 0 or col.x >= WorldData.WORLD_SIZE_X or col.y >= WorldData.WORLD_SIZE_Z: return
	if scan_from >= 0:
		var top := -1
		for y in range(mini(scan_from, WorldData.MAX_Y), -1, -1):
			if BlockRegistry.is_solid(WorldData.get_terrain_block(col.x, y, col.y)):
				top = y
				break
		if top == WorldGenerator.get_surface_y(col.x, col.y): _roofs.erase(col)
		else: _roofs[col] = top
	var roof := _roof(col)
	var water := 0.0
	if WaterManager.initialized:
		water = WaterManager.flow.volume(Vector3i(col.x, roof + 1, col.y))
		if water < WaterManager.standing_depth: water = 0.0
	var whole := clampi(roof + floori(water), 0, 255)
	var wet := 1 + roundi(fposmod(water, 1.0) * 254.0) if water > 0.0 else 0
	var old := _landing.get_pixel(col.y, col.x)
	if roundi(old.r * 255.0) == whole and roundi(old.g * 255.0) == wet: return
	_landing.set_pixel(col.y, col.x, Color8(whole, wet, 0))
	_dirty = true


func _on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if _landing == null or BlockRegistry.is_solid(old_id) == BlockRegistry.is_solid(new_id): return
	var col := Vector2i(pos.x, pos.z)
	# Below the roof nothing changes where drops land.
	if pos.y >= _roof(col): _queue(col, maxi(pos.y, _roof(col)))


func _on_water_changed(cells: Array) -> void:
	if _landing == null: return
	for key: Vector3i in cells:
		# Only water on top of a column changes where drops land.
		if key.y == _roof(Vector2i(key.x, key.z)) + 1: _queue(Vector2i(key.x, key.z), -1)
