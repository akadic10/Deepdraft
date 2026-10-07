extends Node

## Scene-owned, derived presentation data. No slice, task or save-state input.
## Recompute only air within daylight reach of edited blocks. A second reach of
## air supplies boundary conditions, including around corners and between floors.
## Sparse GPU pages cover the full 1024 x 128 x 1024 world without a dense volume.
const SHADER = preload("res://scripts/shaders/underground_lighting.gdshader")
const DIRECTIONS := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
const TILE := 32
const PAGE_LAYERS := 1024
const FRAME_BUDGET_USEC := 2500
var reach := 7
var readability := 0.008
var _fog_parameters: Dictionary = {}
var _fog_elapsed := 0.0
var _sky_lights: Array[WeakRef] = []
var _pending: Dictionary = {}
var _roof: Dictionary = {}
var _samples: Dictionary = {}
var _slots: Dictionary = {}
var _images: Array = [[], [], [], []]
var _pages: Array[Texture2DArray] = []
var _table: Image
var _table_texture: ImageTexture
var _dirty_layers: Dictionary = {}
var _table_dirty := false
var _material_cache: Dictionary = {}
var _phase := "idle"
var _edits: Array = []
var _columns: Dictionary = {}
var _column_keys: Array = []
var _air: Dictionary = {}
var _doors: Dictionary = {}
var _visited: Dictionary = {}
var _queue: Array[Vector3i] = []
var _light: Dictionary = {}
var _light_queue: Array[Vector3i] = []
var _affected: Array[Vector3i] = []
var _cursor := 0
var completed_updates := 0
var max_step_usec := 0


func _ready() -> void:
	add_to_group("underground_lighting")
	var tuning: Dictionary = SkyController.underground_settings()
	reach = clampi(int(tuning.get("entrance_reach_blocks", 7)), 1, 16)
	readability = clampf(float(tuning.get("readability_floor", 0.008)), 0, 0.2)
	_table = Image.create(32,128,false,Image.FORMAT_RF)
	_table.fill(Color.BLACK)
	_table_texture = ImageTexture.create_from_image(_table)
	for i in range(4):
		var page := Texture2DArray.new()
		page.create_from_images([_blank_layer()])
		_pages.append(page)
	WorldData.block_changed.connect(_on_block_changed)
	RoomManager.door_boundaries_changed.connect(_on_doors_changed)
	_on_doors_changed(RoomManager.get_door_boundaries().keys())
	get_tree().node_added.connect(_on_node_added)
	for light in get_viewport().find_children("*", "DirectionalLight3D", true, false):
		if light.get_viewport() == get_viewport(): _sky_lights.append(weakref(light))


func _on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if BlockRegistry.is_transparent(old_id) == BlockRegistry.is_transparent(new_id): return
	# Preserve the first old value when multiple writes are coalesced.
	if not _pending.has(pos): _pending[pos] = old_id


func _on_doors_changed(cells: Array) -> void:
	# Queue both sides even on removal. Snapshot boundaries at the next job so
	# install/uninstall during a time-sliced update settles to the latest state.
	for pos: Vector3i in cells:
		if not _pending.has(pos): _pending[pos] = BlockRegistry.AIR_ID


func is_updating() -> bool:
	return _phase != "idle" or not _pending.is_empty()


func sky_at(cell: Vector3i) -> float:
	return float(_samples.get(cell, 1.0))


func _process(delta: float) -> void:
	_fog_elapsed += delta
	if _fog_elapsed >= 0.05:
		_fog_elapsed = 0.0
		_sync_fog()
	var start := Time.get_ticks_usec()
	while is_updating() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
		_step()
	_upload()
	max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - start)


func _sync_fog() -> void:
	# Godot's automatic fog adds outdoor sky colour after lighting, even inside
	# sealed rooms. Supply the scene's fog to the shared material so its opacity
	# can follow the same physical sky access as daylight. No second render pass.
	var environment: Environment = get_viewport().find_world_3d().environment
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.environment != null: environment = camera.environment
	var values := {"scene_fog_enabled": false}
	if environment != null and environment.fog_enabled:
		values = {
			"scene_fog_enabled": true,
			"fog_density": environment.fog_density,
			"fog_depth_mode": environment.fog_mode == Environment.FOG_MODE_DEPTH,
			"fog_depth": Vector3(environment.fog_depth_begin, environment.fog_depth_end, environment.fog_depth_curve),
			"fog_height": Vector2(environment.fog_height, environment.fog_height_density),
			"fog_color": environment.fog_light_color * environment.fog_light_energy,
			"fog_aerial": 0.0,
		}
		var directions := PackedVector3Array()
		var colors := PackedVector3Array()
		for reference in _sky_lights:
			var light := reference.get_ref() as DirectionalLight3D
			if light == null or not light.is_inside_tree() or not light.is_visible_in_tree(): continue
			if directions.size() == 4: break
			directions.append(light.global_basis.z.normalized())
			var color := light.light_color.srgb_to_linear() * light.light_energy * environment.fog_sun_scatter
			colors.append(Vector3(color.r, color.g, color.b))
		values["fog_sun_count"] = directions.size()
		directions.resize(4); colors.resize(4)
		values["fog_sun_directions"] = directions
		values["fog_sun_colors"] = colors
		# The live world uses ProceduralSkyMaterial. Evaluate its gradient in the
		# fragment's view direction, rather than replacing aerial fog with grey.
		if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
			var sky := environment.sky.sky_material as ProceduralSkyMaterial
			var energy := sky.energy_multiplier * environment.background_energy_multiplier
			values.merge({
				"fog_aerial": environment.fog_aerial_perspective,
				"fog_sky_top": sky.sky_top_color * sky.sky_energy_multiplier * energy,
				"fog_sky_horizon": sky.sky_horizon_color * sky.sky_energy_multiplier * energy,
				"fog_ground_bottom": sky.ground_bottom_color * sky.ground_energy_multiplier * energy,
				"fog_ground_horizon": sky.ground_horizon_color * sky.ground_energy_multiplier * energy,
				"fog_sky_curves": Vector2(0.6 / maxf(sky.sky_curve, .001), 0.6 / maxf(sky.ground_curve, .001)),
				"fog_sky_rotation": Basis.from_euler(environment.sky_rotation).inverse(),
			}, true)
	for key: String in values:
		if _fog_parameters.get(key) == values[key]: continue
		for material: ShaderMaterial in _material_cache.values(): material.set_shader_parameter(key, values[key])
		_fog_parameters[key] = values[key]


func _step() -> void:
	match _phase:
		"idle":
			_doors = RoomManager.get_door_boundaries()
			_edits = _pending.keys()
			_columns.clear()
			for pos: Vector3i in _edits:
				var col := Vector2i(pos.x,pos.z)
				var old_top: int = _roof.get(col, WorldGenerator.get_surface_y(pos.x,pos.z))
				if not BlockRegistry.is_transparent(int(_pending[pos])): old_top = maxi(old_top,pos.y)
				_columns[col] = maxi(int(_columns.get(col,-1)),old_top)
			_pending.clear()
			_column_keys = _columns.keys()
			_air.clear()
			_visited.clear()
			_queue.clear()
			_light.clear()
			_light_queue.clear()
			_affected.clear()
			_cursor = 0
			_phase = "roof"
		"roof":
			if _cursor == _column_keys.size():
				_cursor = 0
				_phase = "seed"
				return
			var col: Vector2i = _column_keys[_cursor]
			_cursor += 1
			_roof.erase(col)
			var top := _roof_height(col)
			# Removing/adding a roof changes every air cell below that roof, not
			# just cells next to the edited voxel. This also handles skylights.
			for y in range(mini(top,int(_columns[col]))+1, maxi(top,int(_columns[col]))+1):
				_seed(Vector3i(col.x,y,col.y),0)
		"seed":
			if _cursor == _edits.size():
				_cursor = 0
				_phase = "expand"
				return
			var pos: Vector3i = _edits[_cursor]
			_cursor += 1
			if _doors.has(pos) and _is_air(pos):
				_samples[pos] = 0.0
				_write_cell(pos,0.0,true)
			elif _is_air(pos): _seed(pos,0)
			else:
				_samples.erase(pos)
				_write_cell(pos,1.0,false)
			for direction: Vector3i in DIRECTIONS: _seed(pos+direction,1)
		"expand":
			if _cursor == _queue.size():
				_cursor = 0
				_phase = "light"
				return
			var pos: Vector3i = _queue[_cursor]
			_cursor += 1
			var distance: int = _visited[pos]
			if distance <= reach: _affected.append(pos)
			if pos.y > _roof_height(Vector2i(pos.x,pos.z)):
				_light[pos] = 0
				_light_queue.append(pos)
			if distance < reach*2:
				for direction: Vector3i in DIRECTIONS: _seed(pos+direction,distance+1)
		"light":
			if _cursor == _light_queue.size():
				_cursor = 0
				_phase = "write"
				return
			var pos: Vector3i = _light_queue[_cursor]
			_cursor += 1
			var distance: int = _light[pos]
			if distance >= reach: return
			for direction: Vector3i in DIRECTIONS:
				var next := pos+direction
				if _visited.has(next) and not _light.has(next):
					_light[next] = distance+1
					_light_queue.append(next)
		"write":
			if _cursor == _affected.size():
				completed_updates += 1
				_phase = "idle"
				return
			var pos: Vector3i = _affected[_cursor]
			_cursor += 1
			var amount := pow(maxf(0,1.0-float(_light.get(pos,reach))/reach),2)
			_samples[pos] = amount
			_write_cell(pos,amount,true)


func _seed(pos: Vector3i, distance: int) -> void:
	if (_visited.has(pos) and int(_visited[pos]) <= distance) or not _inside(pos) or _doors.has(pos) or not _is_air(pos): return
	_visited[pos] = distance
	_queue.append(pos)


func _inside(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < 1024 and pos.y >= 0 and pos.y < 128 and pos.z >= 0 and pos.z < 1024


func _is_air(pos: Vector3i) -> bool:
	if _air.has(pos): return bool(_air[pos])
	var id: int
	if WorldData.chunk_exists(pos.x>>4,pos.y>>4,pos.z>>4):
		id = WorldData.get_block(pos.x,pos.y,pos.z)
	else:
		id = WorldGenerator.get_generated_block_id(pos.x,pos.y,pos.z)
	var air := BlockRegistry.is_transparent(id)
	_air[pos] = air
	return air


func _roof_height(col: Vector2i) -> int:
	if _roof.has(col): return int(_roof[col])
	for y in range(127,-1,-1):
		if not _is_air(Vector3i(col.x,y,col.y)):
			_roof[col] = y
			return y
	_roof[col] = -1
	return -1


func _blank_layer() -> Image:
	var image := Image.create(TILE,TILE*TILE,false,Image.FORMAT_RG8)
	image.fill(Color(1,0,0)) # untracked/solid; keep cut plates and outdoors unchanged
	return image


func _write_cell(pos: Vector3i, exposure: float, air: bool) -> void:
	if not _inside(pos): return
	var key := Vector3i(pos.x>>5,pos.y>>5,pos.z>>5)
	if not _slots.has(key):
		var index := _slots.size()
		_slots[key] = index
		_images[index/PAGE_LAYERS].append(_blank_layer())
		_table.set_pixel(key.x,key.z*4+key.y,Color(index+1,0,0))
		_table_dirty = true
	var slot: int = _slots[key]
	var page := slot/PAGE_LAYERS
	var layer := slot%PAGE_LAYERS
	var image: Image = _images[page][layer]
	image.set_pixel(pos.x%TILE,(pos.y%TILE)*TILE+pos.z%TILE,Color(exposure,1.0 if air else 0.0,0))
	_dirty_layers[slot] = true


func _upload() -> void:
	if _dirty_layers.is_empty(): return
	var rebuilt: Dictionary = {}
	for slot: int in _dirty_layers:
		var page := slot/PAGE_LAYERS
		if rebuilt.has(page): continue
		if _pages[page].get_layers() != _images[page].size():
			var images: Array[Image] = []
			images.assign(_images[page])
			_pages[page].create_from_images(images)
			rebuilt[page] = true
		else:
			_pages[page].update_layer(_images[page][slot%PAGE_LAYERS],slot%PAGE_LAYERS)
	_dirty_layers.clear()
	if _table_dirty:
		_table_texture.update(_table)
		_table_dirty = false


func make_material(source: BaseMaterial3D) -> ShaderMaterial:
	var id := source.get_instance_id()
	if _material_cache.has(id): return _material_cache[id]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint",source.albedo_color)
	material.set_shader_parameter("vertex_color",source.vertex_color_use_as_albedo)
	material.set_shader_parameter("readability_floor",readability)
	material.set_shader_parameter("sky_table",_table_texture)
	for i in range(4): material.set_shader_parameter("sky_page_"+str(i),_pages[i])
	for key: String in _fog_parameters: material.set_shader_parameter(key, _fog_parameters[key])
	# Hold the source as metadata too: its instance id cannot be recycled while
	# this cache entry exists. Materials are released with their scene owner.
	material.set_meta("underground_source_material",source)
	_material_cache[id] = material
	return material


static func bind_world_tree(node: Node) -> void:
	if not node.is_inside_tree(): return
	var owner := node.get_tree().get_first_node_in_group("underground_lighting")
	if owner != null: owner.bind_tree(node)


func bind_tree(node: Node) -> void:
	node.set_meta("underground_lit",true)
	if node is MeshInstance3D: _bind_mesh(node)
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false): _bind_mesh(mesh)


func _bind_mesh(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null: return
	for surface in range(mesh.mesh.get_surface_count()):
		var source := mesh.get_active_material(surface) as BaseMaterial3D
		if source == null or source.emission_enabled or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		if mesh.material_override != null:
			mesh.material_override = make_material(source)
			break
		mesh.set_surface_override_material(surface,make_material(source))


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D and node.get_viewport() == get_viewport(): _sky_lights.append(weakref(node))
	if node is MeshInstance3D: _bind_added.call_deferred(weakref(node))


func _bind_added(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if node == null or not node.is_inside_tree(): return
	var parent: Node = node
	while parent != null:
		if parent.has_meta("underground_lit"):
			_bind_mesh(node)
			return
		parent = parent.get_parent()
