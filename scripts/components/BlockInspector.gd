extends RefCounted

## DEV Block Inspector for WorldRenderer: a draggable CanvasLayer panel that
## reports the clicked block's identity, generation data and room, plus a
## yellow outline on the block. WorldRenderer builds it only when
## UIRegistry.dev_tools_enabled and forwards unhandled input to it.

const WORLD_SIZE_X: int = WorldData.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldData.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldData.WORLD_SIZE_Z
const RENDER_MODE: String = preload("res://scripts/components/TerrainTileMesher.gd").RENDER_MODE

var renderer: Node3D

var _inspector_layer: CanvasLayer = null
var _inspector_panel: PanelContainer = null
var _inspector_label: Label = null
var _inspector_outline: MeshInstance3D = null
var _inspector_dragging: bool = false


func _init(owner: Node3D) -> void:
	renderer = owner
	_build_block_inspector_ui()


func is_active() -> bool:
	return _inspector_layer != null and _inspector_layer.visible


func handle_input(event: InputEvent) -> void:
	if _inspector_layer == null or not _inspector_layer.visible:
		return
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
			_inspect_block_at_screen_position(mbe.position)


func _build_block_inspector_ui() -> void:
	_inspector_layer = CanvasLayer.new()
	_inspector_layer.name = "BlockInspector"
	renderer.add_child(_inspector_layer)
	_inspector_layer.visible = false
	_inspector_layer.visibility_changed.connect(_on_inspector_visibility_changed)

	_inspector_panel = PanelContainer.new()
	UITheme.apply_surface(_inspector_panel)
	_inspector_panel.name = "Panel"
	_inspector_panel.position = Vector2(48.0, 128.0)
	_inspector_panel.custom_minimum_size = Vector2(420.0, 270.0)
	_inspector_panel.add_theme_stylebox_override("panel", UITheme.window_style())
	_inspector_layer.add_child(_inspector_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 1)
	margin.add_theme_constant_override("margin_right", 1)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	_inspector_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	var title_bar := PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0.0, 34.0)
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.add_theme_stylebox_override("panel", UITheme.titlebar_style())
	title_bar.gui_input.connect(_on_inspector_title_bar_gui_input)
	column.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_bar.add_child(title_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	title_margin.add_child(header)

	var title := Label.new()
	title.text = "Block Inspector"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_title(title)
	header.add_child(title)

	var close := Button.new()
	close.name = "CloseButton"
	UITheme.apply_close_button(close)
	close.pressed.connect(func() -> void:
		_inspector_layer.visible = false
		if _inspector_outline != null:
			_inspector_outline.visible = false
	)
	header.add_child(close)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 10)
	body_margin.add_theme_constant_override("margin_right", 10)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	column.add_child(body_margin)

	_inspector_label = Label.new()
	_inspector_label.name = "Details"
	_inspector_label.add_theme_font_size_override("font_size", 13)
	_inspector_label.text = "Block inspector\nclick a block"
	body_margin.add_child(_inspector_label)
	_build_block_inspector_outline()

func _on_inspector_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_inspector_dragging = mouse.pressed
	elif event is InputEventMouseMotion and _inspector_dragging:
		var motion := event as InputEventMouseMotion
		_inspector_panel.position += motion.relative

func _on_inspector_visibility_changed() -> void:
	if _inspector_layer != null and not _inspector_layer.visible and _inspector_outline != null:
		_inspector_outline.visible = false


func _build_block_inspector_outline() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color.YELLOW)

	var corners := [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1, 1, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 1),
		Vector3(1, 1, 1),
		Vector3(0, 1, 1),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge: Array in edges:
		mesh.surface_add_vertex(corners[edge[0] as int])
		mesh.surface_add_vertex(corners[edge[1] as int])
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true

	_inspector_outline = MeshInstance3D.new()
	_inspector_outline.name = "BlockInspectorOutline"
	_inspector_outline.mesh = mesh
	_inspector_outline.material_override = material
	_inspector_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inspector_outline.visible = false
	renderer.add_child(_inspector_outline)


func _inspect_block_at_screen_position(screen_pos: Vector2) -> void:
	var camera_rig: Camera = renderer.camera_rig()
	if camera_rig == null or camera_rig.camera_node == null:
		_set_inspector_text("Block inspector\nno camera")
		return

	var camera := camera_rig.camera_node
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var hit := _find_block_on_ray(origin, direction, camera.far)
	if hit.is_empty():
		_set_inspector_text("Block inspector\nno block hit")
		return

	var pos: Vector3i = hit["pos"]
	var block_id: int = hit["block_id"]
	var generated_block_id: int = hit.get("generated_block_id", block_id)
	var source: String = hit.get("source", "unknown")
	var face: String = hit.get("face", "unknown")
	var key_name := BlockRegistry.get_key(block_id)
	var key := String(key_name)
	var def := BlockRegistry.get_def(key_name)
	var kind: String = def.get("kind", "unknown")
	var generated_key := String(BlockRegistry.get_key(generated_block_id))
	var season: String = WorldClock.season
	var color := BlockRegistry.get_color(block_id, season)
	var column_info: Dictionary = WorldGenerator.get_column_debug_info(pos.x, pos.z) if WorldGenerator.has_method("get_column_debug_info") else {}
	var visible_key: String = column_info.get("visible_block_key", "")
	var agreement: String = "yes" if generated_block_id == block_id else "NO"
	_move_block_inspector_outline(pos)
	var lines: Array[String] = [
		"Block inspector",
		"render: %s" % RENDER_MODE,
		"source: %s  face: %s" % [source, face],
		"hit: %s" % key,
		"generated: %s  agree: %s" % [generated_key, agreement],
		"visible top: y %d  %s" % [
			column_info.get("visible_surface_y", -1),
			visible_key,
		],
		"domain: %s %.3f  surface y: %d" % [
			column_info.get("domain", "unknown"),
			column_info.get("domain_n", 0.0),
			column_info.get("surface_y", -1),
		],
		"height band: %s" % column_info.get("height_band", "unknown"),
		"water: lake %s  tarn %s  bank %s" % [
			str(column_info.get("is_lake", false)),
			str(column_info.get("is_tarn", false)),
			str(column_info.get("is_water_bank", false)),
		],
		"kind: %s  color: %s" % [kind, color.to_html(false)],
		"x: %d  y: %d  z: %d" % [pos.x, pos.y, pos.z],
	]
	lines.append_array(_room_inspect_lines(hit.get("air_pos", Vector3i(-999999, -999999, -999999))))
	_set_inspector_text("\n".join(lines))


func _find_block_on_ray(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var step := 0.25
	var distance := 0.0
	var last_pos := Vector3i(-999999, -999999, -999999)
	var last_empty_pos := last_pos
	while distance <= max_distance:
		var sample := origin + direction * distance
		var pos := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		if pos != last_pos:
			var prev_pos := last_pos
			last_pos = pos
			var hit_info := _inspect_block_id(pos)
			var block_id: int = hit_info.get("block_id", BlockRegistry.AIR_ID)
			if BlockRegistry.is_transparent(block_id):
				last_empty_pos = pos
			else:
				return {
					"pos": pos,
					"block_id": block_id,
					"generated_block_id": hit_info.get("generated_block_id", block_id),
					"source": hit_info.get("source", "unknown"),
					"face": _hit_face_label(pos - last_empty_pos if last_empty_pos != Vector3i(-999999, -999999, -999999) else pos - prev_pos),
					# The last AIR cell the ray crossed before this solid hit —
					# the open cell adjacent to the hit face. The room inspect
					# block queries RoomManager with it (a sealed room's
					# interior is air; the hit block itself is solid and can
					# never be inside a room). Sentinel (-999999,…) if the ray
					# started inside solid.
					"air_pos": last_empty_pos,
				}
		distance += step
	return {}


func _inspect_block_id(pos: Vector3i) -> Dictionary:
	if pos.x < 0 or pos.x >= WORLD_SIZE_X or pos.y < 0 or pos.y >= WORLD_SIZE_Y or pos.z < 0 or pos.z >= WORLD_SIZE_Z:
		return {"block_id": BlockRegistry.AIR_ID, "generated_block_id": BlockRegistry.AIR_ID, "source": "out_of_bounds"}
	if pos.y > renderer.slice_y:
		return {"block_id": BlockRegistry.AIR_ID, "generated_block_id": BlockRegistry.AIR_ID, "source": "above_slice"}

	var generated_block_id := BlockRegistry.AIR_ID
	if WorldGenerator.has_method("get_generated_block_id"):
		generated_block_id = WorldGenerator.get_generated_block_id(pos.x, pos.y, pos.z)
	# A materialized chunk's AIR is authoritative too: do not resurrect mined rock.
	var block_id := WorldData.get_live_block(pos.x, pos.y, pos.z)
	if WorldData.chunk_exists(pos.x >> 4,pos.y >> 4,pos.z >> 4):
		return {"block_id": block_id, "generated_block_id": generated_block_id, "source": "streamed_chunk"}
	return {"block_id": generated_block_id, "generated_block_id": generated_block_id, "source": "overview_generated"}


## Room inspect block (doc 34 "UI — Room Temperature Display"; built in the
## doc 22 close-out pass). The Block Inspector IS the doc 34 inspect panel:
## if the air cell the ray crossed just before the solid hit belongs to a
## sealed room, RoomManager.get_room_at() already returns everything the
## panel needs. Null-safe: degrades to a single "room: —" line if RoomManager
## is somehow absent, and to "room: none" when the cell is open air.
## EXPLICIT TYPES at every Dictionary read — the RoomManager/WorldClock
## Variant-inference trap (see RoomManager._recompute_temp header note).
func _room_inspect_lines(air_pos: Vector3i) -> Array[String]:
	if air_pos.x == -999999:
		return []
	var room_manager := renderer.get_node_or_null("/root/RoomManager")
	if room_manager == null:
		return ["room: — (RoomManager absent)"]
	var room: Dictionary = room_manager.get_room_at(air_pos)
	if room.is_empty():
		return ["room: none (open air)"]
	var temp_c: float = float(room.get("temp_c", 0.0))
	var volume: int = int(room.get("volume", 0))
	var heat_units: int = int(room.get("heat_units", 0))
	var mean_floor_y: float = float(room.get("mean_floor_y", 0.0))
	var seasonal: float = float(room.get("seasonal_influence", 0.0))
	var is_frozen: bool = bool(room.get("is_frozen_vault", false))
	var doors: int = room.get("door_cells", {}).size()
	var heat_bonus: float = float(room.get("heat_bonus_c",0))
	var label := "room: FROZEN VAULT" if is_frozen else "room: Sealed (%s)" % RoomManager.comfort_label(temp_c)
	if room.get("room_type", "room") == "bedroom": label = "room: Bedroom (%s)" % RoomManager.comfort_label(temp_c)
	return [
		label,
		"room temp: %.1f°C  volume: %d blocks" % [temp_c, volume],
		"room heat: %d units (+%.1f°C)  doors: %d" % [heat_units, heat_bonus, doors],
		"room seasonal influence: %d%%  mean floor y: %.1f" % [roundi(seasonal * 100.0), mean_floor_y],
	]


func _hit_face_label(delta: Vector3i) -> String:
	if delta.x > 0:
		return "west"
	if delta.x < 0:
		return "east"
	if delta.y > 0:
		return "bottom"
	if delta.y < 0:
		return "top"
	if delta.z > 0:
		return "north"
	if delta.z < 0:
		return "south"
	return "unknown"


func _set_inspector_text(text: String) -> void:
	if _inspector_label != null:
		_inspector_label.text = text


func _move_block_inspector_outline(pos: Vector3i) -> void:
	if _inspector_outline == null:
		return
	_inspector_outline.global_position = Vector3(float(pos.x), float(pos.y), float(pos.z))
	_inspector_outline.visible = true
