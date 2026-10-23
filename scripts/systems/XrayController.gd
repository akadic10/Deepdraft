extends Node3D

## Scene-owned underground inspection and non-interactive lower-level guide.
## Normal terrain continues to supply shadows and all simulation data.
const XRAY_LAYER := 1 << 18
const TERRAIN_LAYER := 1 << 19
const CACHED_LEVELS_PER_CHUNK := 3
const Geometry = preload("res://scripts/components/XrayGeometry.gd")
@export var renderer_path: NodePath
@export var slice_path: NodePath
@export var dock_path: NodePath
@export var tool_paths: Array[NodePath] = []
signal changed
var renderer: Node
var slice: Node
var dock: Node
var mode := "off"
var last_mode := "full"
var reference_y := -1
var show_reference := true
var working := false
var _tools: Array[Node] = []
var _geometry := Geometry.new()
var _chunks: Dictionary = {}
var _chunk_cache: Dictionary = {} # Chunk -> ordered recent slice variants.
var _dirty: Dictionary = {}
var _job := {}
var _revision := -1
var _level := -1
var _reference_dirty := true
var _reference_job := {}
var _reference: MeshInstance3D
var _reference_mesh_level := -1
var _camera: Camera3D
var _camera_mask := 0
var _camera_environment: Environment
var _view_environment: Environment
var _inspection := false
var _visuals: Array[WeakRef] = []
var _moving: Array[WeakRef] = []
var _scan: Array[Node] = []
var _visual_cursor := 0
var _tracked: Dictionary = {}
var _reference_center := Vector2i(-9999,-9999)
var _config: Dictionary = {}
var _shell_material: Material

func _ready() -> void:
	add_to_group("underground_view")
	if renderer==null: renderer = get_node_or_null(renderer_path)
	if slice==null: slice = get_node_or_null(slice_path)
	if dock==null: dock = get_node_or_null(dock_path)
	_config = UIRegistry.get_time_slice().get("xray",{})
	_reference = MeshInstance3D.new()
	_reference.name = "LowerLevelReference"
	_reference.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reference.layers = 1 | XRAY_LAYER
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(String(_config.get("reference_color","#75d5e699")))
	_reference.material_override = material
	add_child(_reference)
	if renderer!=null:
		renderer.underground_view = self
		_shell_material = renderer.terrain_material().duplicate() if renderer.terrain_material()!=null else null
		if _shell_material is ShaderMaterial:
			_shell_material.set_shader_parameter("readability_floor",float(_config.get("readability_floor",.12)))
			# The inspection shell keeps its own neutral look under Hearthblock lighting.
			_shell_material.set_shader_parameter("readability_tint",Color.WHITE)
			_shell_material.set_shader_parameter("view_fill",0.0)
			_shell_material.set_shader_parameter("slice_cap_tint",Color.WHITE)
	_view_environment = Environment.new()
	_view_environment.background_mode = Environment.BG_COLOR
	_view_environment.background_color = Color(String(_config.get("background_color","#19252b")))
	_view_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_view_environment.ambient_light_color = Color.WHITE
	_view_environment.ambient_light_energy = .2
	if slice!=null: slice.slice_changed.connect(_slice_changed)
	WorldClock.season_changed.connect(func(_season: String): _invalidate_all())
	WaterManager.surface_changed.connect(_water_changed)
	get_tree().node_added.connect(_node_added)
	# Siblings may not have entered the tree yet.
	_bind_tools.call_deferred()
	if dock!=null: dock.register_xray_controller(self)

func _bind_tools() -> void:
	for path in tool_paths:
		var tool := get_node_or_null(path)
		if tool==null: continue
		_tools.append(tool)
		if tool.has_signal("tool_active_changed"): tool.tool_active_changed.connect(_tool_changed)
	_sync_working()

func toggle() -> void:
	set_mode(last_mode if mode=="off" else "off")

func set_mode(value: String) -> void:
	if value not in ["off","full","flat"] or value==mode: return
	var was_off := mode=="off"
	mode = value
	if mode!="off":
		last_mode = mode
		if slice!=null and not slice.is_active(): slice.activate()
		if reference_y<0: pin_reference()
		# Refresh changed world data, retaining geometry for unchanged chunks.
		if was_off:
			_refresh_interiors()
			_select_level(int(renderer.slice_y))
			if _scan.is_empty(): _scan.append(get_tree().current_scene)
	if renderer!=null: renderer.mark_visible_volume_dirty()
	_sync_working()
	_sync_camera()
	_sync_visibility()
	changed.emit()

func pin_reference() -> void:
	reference_y = int(renderer.slice_y) if renderer!=null else SliceController.MAX_SLICE_Y
	_reference_dirty = true
	_reference_job.clear()
	changed.emit()

func set_reference_enabled(enabled: bool) -> void:
	show_reference = enabled
	_reference_dirty = true
	_sync_visibility()
	changed.emit()

func is_inspecting() -> bool:
	return mode!="off" and not working

func _tool_changed(_active: bool) -> void:
	_sync_working()

func _sync_working() -> void:
	var next := false
	for tool in _tools:
		if is_instance_valid(tool) and tool.has_method("is_active") and tool.is_active(): next = true
	if next==working: return
	working = next
	if renderer!=null: renderer.mark_visible_volume_dirty()
	_sync_camera()
	_sync_visibility()
	changed.emit()

func _slice_changed(height: int) -> void:
	_refresh_interiors()
	_select_level(height)
	changed.emit()

func _variant_level(key: Vector3i, level: int) -> int:
	# Fully hidden/full chunks share one variant across distant slice heights.
	# One level beyond the chunk also distinguishes water cut at its top edge
	# from a live surface above it (which belongs to the next chunk).
	return clampi(level,key.y*16-1,key.y*16+16)

func _select_level(level: int) -> void:
	if level==_level: return
	_level = level
	_job.clear()
	_dirty.clear()
	for entry in _chunks.values(): _hide_entry(entry)
	_chunks.clear()
	for key: Vector3i in InteriorTracker.get_interior_chunks():
		var variant := _variant_level(key,level)
		var cache: Dictionary = _chunk_cache.get(key,{})
		if cache.has(variant):
			var entry: Dictionary = cache[variant]
			cache.erase(variant)
			cache[variant] = entry # Most recently used; active variant stays last.
			_chunks[key] = entry
			if entry.water_dirty: _dirty[key] = "water"
		else: _dirty[key] = true
	_reference_dirty = true
	_reference_job.clear()
	# Keep the previous outline aligned while refreshing its columns.
	if _reference.mesh!=null: _reference.position.y = level-_reference_mesh_level
	if renderer!=null: renderer.mark_visible_volume_dirty()
	_sync_visibility()

func _hide_entry(entry: Dictionary) -> void:
	entry.full.hide()
	entry.flat.hide()
	entry.water.hide()

func _free_entry(entry: Dictionary) -> void:
	_hide_entry(entry)
	entry.full.queue_free()
	entry.flat.queue_free()
	entry.water.queue_free()

func _invalidate_chunk(key: Vector3i) -> void:
	for entry in _chunk_cache.get(key,{}).values(): _free_entry(entry)
	_chunk_cache.erase(key)
	_chunks.erase(key)
	_dirty[key] = true

func _invalidate_all() -> void:
	_job.clear()
	for key in _chunk_cache.keys(): _invalidate_chunk(key)
	for key in InteriorTracker.get_interior_chunks(): _dirty[key] = true
	_reference.mesh = null
	_reference_dirty = true
	_reference_job.clear()
	if renderer!=null: renderer.mark_visible_volume_dirty()

func _process(_delta: float) -> void:
	if mode=="off": return
	_sync_camera()
	if renderer==null: return
	_refresh_interiors()
	var level := int(renderer.slice_y)
	_select_level(level)
	var deadline := Time.get_ticks_usec()+int(_config.get("mesh_budget_usec",2500))
	while Time.get_ticks_usec()<deadline and (not _job.is_empty() or not _dirty.is_empty()):
		if _job.is_empty():
			var key: Vector3i = _dirty.keys()[0]
			var water_only: bool = _dirty[key] is String
			_dirty.erase(key)
			_job = {"key":key,"level":_variant_level(key,level),"cells":InteriorTracker.get_interior_cells(key),"cursor":0,"water_only":water_only,
				"full":_geometry.arrays(),"flat":_geometry.arrays(),"water":_geometry.arrays(),"floors":{},"full_cells":{},"flat_cells":{}}
		if _job.cursor<_job.cells.size():
			if not _job.water_only:
				_geometry.append_air(_job.cells[_job.cursor],_job.level,renderer,_job.full,_job.flat,_job.floors,_job.full_cells,_job.flat_cells)
			_geometry.append_water(_job.cells[_job.cursor],_job.level,_job.water)
			_job.cursor += 1
		else:
			_commit_chunk()
	if _job.is_empty() and _dirty.is_empty() and _reference_dirty:
		_advance_reference(deadline)
	_sync_visibility()
	if is_inspecting(): _update_visuals()

func _refresh_interiors() -> void:
	if _revision==InteriorTracker.revision: return
	_revision = InteriorTracker.revision
	for key in InteriorTracker.take_dirty_chunks(): _invalidate_chunk(key)
	# Clearing/restoring a world also retires dormant variants.
	for key in _chunk_cache.keys():
		if InteriorTracker.get_interior_cells(key).is_empty(): _invalidate_chunk(key)
	if not _job.is_empty() and _dirty.has(_job.key) and _dirty[_job.key] is bool:
		_job.clear()
	_reference.mesh = null
	_reference_dirty = true
	_reference_job.clear()
	_visual_cursor = 0
	if renderer!=null: renderer.mark_visible_volume_dirty()

func _commit_chunk() -> void:
	var key: Vector3i = _job.key
	if _job.water_only and _chunks.has(key):
		# Keep terrain, selection sets and the lower-level guide unchanged.
		# Flowing water does not invalidate any of those, or the normal renderer.
		_chunks[key].water.mesh = _geometry.mesh(_job.water)
		_chunks[key].water_dirty = _dirty.has(key)
		_job.clear()
		return
	if _job.cells.is_empty():
		_job.clear()
		return
	var full := _shell_node(_geometry.mesh(_job.full))
	var flat := _shell_node(_geometry.mesh(_job.flat))
	var water := _shell_node(_geometry.mesh(_job.water))
	var entry := {"full":full,"flat":flat,"water":water,"floors":_job.floors,
		"water_dirty":_dirty.has(key),
		"full_cells":_job.full_cells,"flat_cells":_job.flat_cells}
	var cache: Dictionary = _chunk_cache.get(key,{})
	if cache.has(_job.level):
		_free_entry(cache[_job.level])
		cache.erase(_job.level)
	cache[_job.level] = entry
	while cache.size()>CACHED_LEVELS_PER_CHUNK:
		var oldest: int = cache.keys()[0]
		_free_entry(cache[oldest])
		cache.erase(oldest)
	_chunk_cache[key] = cache
	_chunks[key] = entry
	_reference_dirty = _reference_dirty or not _job.water_only
	if not _job.water_only: _reference_job.clear()
	_job.clear()
	renderer.mark_visible_volume_dirty()

func _shell_node(mesh: ArrayMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _shell_material
	node.layers = XRAY_LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _sync_visibility() -> void:
	for key in _chunks:
		var entry: Dictionary = _chunks[key]
		var valid := _chunk_ready(key)
		entry.full.visible = valid and is_inspecting() and mode=="full"
		entry.flat.visible = valid and is_inspecting() and mode=="flat"
		entry.water.visible = valid and is_inspecting()
	_reference.visible = mode!="off" and show_reference and renderer!=null and reference_y<int(renderer.slice_y)

func _chunk_ready(key: Vector3i) -> bool:
	return (not _dirty.has(key) or _dirty[key] is String) and (_job.is_empty() or _job.key!=key or _job.water_only)

func _advance_reference(deadline: int) -> void:
	if _reference_job.is_empty():
		_reference_center = _view_center()
		_reference_job = {"keys":_chunks.keys(),"index":0,"floors":[],"floor_index":0,
			"columns":{},"outline":[],"outline_index":0,"collecting":true,"data":_geometry.arrays()}
	var job := _reference_job
	var radius := int(_config.get("reference_radius",160))
	while Time.get_ticks_usec()<deadline:
		if job.collecting:
			if job.floor_index<job.floors.size():
				var cell: Vector3i = job.floors[job.floor_index]
				job.floor_index += 1
				if cell.y<=reference_y:
					var column := Vector2i(cell.x,cell.z)
					job.columns[column] = maxi(int(job.columns.get(column,-1)),cell.y)
			elif job.index<job.keys.size():
				var key: Vector3i = job.keys[job.index]
				job.index += 1
				if absi(key.x*16-_reference_center.x)>radius+16 or absi(key.z*16-_reference_center.y)>radius+16: continue
				job.floors = _chunks[key].floors.keys()
				job.floor_index = 0
			else:
				job.collecting = false
				job.outline = job.columns.keys()
		elif job.outline_index<job.outline.size():
			_geometry.append_reference(job.outline[job.outline_index],job.columns,int(renderer.slice_y),float(_config.get("reference_width",.065)),job.data)
			job.outline_index += 1
		else:
			_reference.mesh = _geometry.mesh(job.data)
			_reference.position.y = 0
			_reference_mesh_level = int(renderer.slice_y)
			_reference_job.clear()
			_reference_dirty = false
			return

func is_terrain_visible(cell: Vector3i) -> bool:
	if renderer==null or cell.y>int(renderer.slice_y): return false
	if not is_inspecting(): return true
	# A face's supporting solid can belong to the air chunk next door.
	var chunk := Vector3i(cell.x>>4,cell.y>>4,cell.z>>4)
	var field := "full_cells" if mode=="full" else "flat_cells"
	for dx in range(-1,2):
		for dy in range(-1,2):
			for dz in range(-1,2):
				var key := chunk+Vector3i(dx,dy,dz)
				if not _chunk_ready(key): continue
				if _chunks.get(key,{}).get(field,{}).has(cell): return true
	return false

func is_terrain_face_visible(cell: Vector3i, normal: Vector3i) -> bool:
	if not is_terrain_visible(cell): return false
	if not is_inspecting(): return true
	# A floor's underside or a wall's hidden top is not part of the shell.
	var air := cell+normal
	if normal==Vector3i.DOWN or air.y>int(renderer.slice_y) or not InteriorTracker.contains_air(air): return false
	if mode=="full": return true
	return _geometry.has_floor_headroom(air)

func _water_changed(cells: Array) -> void:
	if _chunk_cache.is_empty() and _job.is_empty(): return
	var affected := {}
	for cell: Vector3i in cells:
		for y in range(8):
			var key := Vector3i(cell.x>>4,y,cell.z>>4)
			if _chunk_cache.has(key) or (not _job.is_empty() and _job.key==key): affected[key] = true
	for key in affected:
		# Inactive variants (including while X-ray is off) cannot retain stale
		# pool heights. Refresh their water lazily when selected again.
		for entry in _chunk_cache.get(key,{}).values(): entry.water_dirty = true
		if _chunks.has(key) or (not _job.is_empty() and _job.key==key):
			_dirty[key] = _dirty.get(key,"water")
	# Do not cancel an in-flight mesh for flowing water. Its dirty key causes
	# one subsequent refresh, so continuous flow cannot starve the initial build.

func _sync_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera!=_camera:
		_restore_camera()
		_camera = camera
	if not is_instance_valid(_camera): return
	if is_inspecting() and not _inspection:
		_camera_mask = _camera.cull_mask
		_camera_environment = _camera.environment
		_camera.cull_mask = XRAY_LAYER
		_camera.environment = _view_environment
		_inspection = true
	elif not is_inspecting(): _restore_camera()
	var center := _view_center()
	if center.distance_squared_to(_reference_center)>32*32:
		_reference_dirty = true
		_reference_job.clear()

func _view_center() -> Vector2i:
	if not is_instance_valid(_camera): return Vector2i.ZERO
	var screen := get_viewport().get_visible_rect().get_center()
	var point = Plane(Vector3.UP,float(renderer.slice_y+1)).intersects_ray(_camera.project_ray_origin(screen),_camera.project_ray_normal(screen))
	if point==null: point = _camera.global_position
	return Vector2i(int(point.x),int(point.z))

func _restore_camera() -> void:
	if _inspection and is_instance_valid(_camera):
		_camera.cull_mask = _camera_mask
		_camera.environment = _camera_environment
	_inspection = false

func _node_added(node: Node) -> void:
	if mode!="off" and node is VisualInstance3D: _scan.append(node)

func _update_visuals() -> void:
	var deadline := Time.get_ticks_usec()+int(_config.get("visual_budget_usec",1200))
	while not _scan.is_empty() and Time.get_ticks_usec()<deadline:
		var node = _scan.pop_back()
		if not is_instance_valid(node) or node==self or is_ancestor_of(node) or not node.is_inside_tree(): continue
		if node.get_viewport()!=get_viewport(): continue # portraits and preview worlds
		for child in node.get_children(): _scan.append(child)
		# Terrain, outdoor water and moisture use broad shared batches. The
		# discovered shell includes its own clipped water surfaces instead.
		if not (node is GeometryInstance3D or node is Light3D) or node.layers&TERRAIN_LAYER!=0 or _is_terrain_batch(node) or _tracked.has(node.get_instance_id()): continue
		_tracked[node.get_instance_id()] = true
		_visuals.append(weakref(node))
		var parent: Node = node
		while parent!=null and parent!=get_tree().current_scene:
			if parent is DwarfAgent or parent.has_method("current_cell"):
				_moving.append(weakref(node))
				break
			parent = parent.get_parent()
		_filter_visual(node)
	var remaining := _visuals.size()
	while remaining>0 and Time.get_ticks_usec()<deadline:
		_visual_cursor %= _visuals.size()
		var node = _visuals[_visual_cursor].get_ref()
		remaining -= 1
		if not is_instance_valid(node):
			_visuals.remove_at(_visual_cursor)
			if _visuals.is_empty(): break
			continue
		_visual_cursor += 1
		if node.is_inside_tree(): _filter_visual(node)
	for i in range(_moving.size()-1,-1,-1):
		var node = _moving[i].get_ref()
		if not is_instance_valid(node): _moving.remove_at(i)
		elif node.is_inside_tree(): _filter_visual(node)

func _is_terrain_batch(node: Node) -> bool:
	var ancestor := node.get_parent()
	while ancestor!=null and ancestor!=get_tree().current_scene:
		# The water renderer also owns individually placed, selectable stones.
		if ancestor.is_in_group("water_stones"): return false
		if ancestor==renderer: return true
		ancestor = ancestor.get_parent()
	return false

func _filter_visual(node: VisualInstance3D) -> void:
	if is_ancestor_of(node): return
	if node is Light3D:
		# Camera masks also cull light instances. Preserve actual illumination;
		# world terrain still supplies their shadows and exposure tests.
		node.layers |= XRAY_LAYER
		return
	var bounds: AABB = node.global_transform*node.get_aabb()
	# Sample the visual envelope, retaining a whole furnishing/actor when any
	# of its low/central points belongs to a known interior. Visibility flags
	# remain owned by slicing, animation and the entity; only a camera layer changes.
	for height in [.15,.5]:
		for x in [.1,.5,.9]:
			for z in [.1,.5,.9]:
				var point := bounds.position+bounds.size*Vector3(x,height,z)
				if InteriorTracker.contains_air(Vector3i(point.floor())):
					node.layers |= XRAY_LAYER
					return
	node.layers &= ~XRAY_LAYER

func _exit_tree() -> void:
	_restore_camera()
	for ref: WeakRef in _visuals:
		var node = ref.get_ref()
		if is_instance_valid(node): node.layers &= ~XRAY_LAYER
	if is_instance_valid(renderer): renderer.underground_view = null
