class_name DwarfDirector
extends Node3D

## Owns the colony's dwarf roster (doc 16 Phase 1). Scene node in
## debug_world.tscn — agents are its children, so positions are world
## coordinates (the SurfaceFloraSpawner pattern).
##
## Phase 1 scope: deterministic roster generation (birth-index ordered),
## DEV spawn window (dock 'dwarves' entry routes here, the SliceController
## push-registration pattern), slice culling for agents, and stats for the
## debug overlay. The Settlement Flag flow (Phase 2b of the build order)
## replaces the DEV spawn as the player-facing entry point; the DEV window
## stays as a testing tool.

@export var camera_path: NodePath
@export var slice_controller_path: NodePath
@export var dock_ui_path: NodePath

## Dwarves per DEV spawn press.
@export_range(1, 20, 1) var squad_size: int = 5

const SLICE_OFF_Y: int = 127

var _camera_rig: Node3D = null
var _dock_ui: Node = null
var _factory := DwarfFactory.new()
var _agents: Array[DwarfAgent] = []
var _birth_index: int = 0
var _used_names: Dictionary = {}
var _slice_y: int = SLICE_OFF_Y

var _window_layer: CanvasLayer
var _count_label: Label
var _walk_button: Button

## DEV walk test (step 3b): while ON, left-click terrain orders the whole
## squad to path there — the visual verification for NavGrid (around trees,
## up/down terraces, refusing water).
var _walk_test: bool = false
var _name_tags: bool = false


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_dock_ui = get_node_or_null(dock_ui_path)
	_build_window()

	if _dock_ui != null and _dock_ui.has_method("register_dwarf_director"):
		_dock_ui.call("register_dwarf_director", self)

	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _walk_test:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_set_walk_test(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_order_walk_to_mouse()
			get_viewport().set_input_as_handled()


## Sends every dwarf to a distinct walkable cell around the clicked point.
func _order_walk_to_mouse() -> void:
	var hit := _mouse_surface_cell()
	if hit.is_empty():
		return
	var center := Vector3i(hit["x"], hit["y"], hit["z"])
	var goals: Array[Vector3i] = []
	var ring := 0
	while goals.size() < _agents.size() and ring <= 6:
		for cell in _ring_cells(center.x, center.z, ring):
			if goals.size() >= _agents.size():
				break
			var goal := NavGrid.walkable_floor_at(cell.x, cell.y, center.y)
			if goal.y >= 0 and not goals.has(goal):
				goals.append(goal)
		ring += 1
	var ordered := 0
	for i in range(mini(goals.size(), _agents.size())):
		if is_instance_valid(_agents[i]) and _agents[i].walk_to(goals[i]):
			ordered += 1
	print("DwarfDirector: walk test — %d/%d dwarves pathed to %s." % [
		ordered, _agents.size(), str(center)])


## Height-field surface pick (the FlagPlacementController approach).
func _mouse_surface_cell() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var t := 0.0
	while t < 700.0:
		var p := origin + dir * t
		var wx := floori(p.x)
		var wz := floori(p.z)
		if wx >= 0 and wx < WorldGenerator.WORLD_SIZE_X \
				and wz >= 0 and wz < WorldGenerator.WORLD_SIZE_Z:
			var sy := int(WorldGenerator.get_visible_surface_y(wx, wz))
			if sy >= 0 and p.y <= float(sy + 1):
				return { "x": wx, "y": sy, "z": wz }
		elif p.y < 0.0:
			return {}
		t += 0.5
	return {}


func _set_walk_test(active: bool) -> void:
	_walk_test = active
	if _walk_button != null:
		_walk_button.text = "Walk test: %s" % ("ON — click ground" if _walk_test else "OFF")


# ── Settlement anchor (doc 16 Phase 1 — set by the Flag flow) ────────────────

## World cell of the placed Settlement Flag; (-1,-1,-1) = not placed yet.
## INTERIM HOME: doc 16 leans toward a field on TaskManager — migrate this
## there when TaskManager ships (step 4) if it becomes the second consumer.
var settlement_anchor: Vector3i = Vector3i(-1, -1, -1)


func set_settlement_anchor(cell: Vector3i) -> void:
	settlement_anchor = cell


func has_settlement() -> bool:
	return settlement_anchor.y >= 0


# ── Spawning ──────────────────────────────────────────────────────────────────

## DEV spawn: a squad on walkable ground around the camera's look point.
## Returns the number actually spawned (0 while worldgen maps aren't ready).
func spawn_squad_at_camera() -> int:
	if _camera_rig == null:
		push_warning("DwarfDirector: camera_path not wired.")
		return 0
	return spawn_squad_at(
		floori(_camera_rig.global_position.x),
		floori(_camera_rig.global_position.z))


## Spawns a squad on standable ground in an expanding ring around (wx, wz).
## Used by the DEV button (camera point) and the Settlement Flag flow (2b).
func spawn_squad_at(wx: int, wz: int) -> int:
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("DwarfDirector: maps not ready — cannot spawn yet.")
		return 0

	var cx := clampi(wx, 0, WorldGenerator.WORLD_SIZE_X - 1)
	var cz := clampi(wz, 0, WorldGenerator.WORLD_SIZE_Z - 1)

	var spawned := 0
	var ring := 0
	while spawned < squad_size and ring <= 12:
		for cell in _ring_cells(cx, cz, ring):
			if spawned >= squad_size:
				break
			if _spawn_one(cell.x, cell.y):
				spawned += 1
		ring += 1
	if spawned > 0:
		print("DwarfDirector: spawned %d dwarves near (%d, %d) — roster %d." % [
			spawned, cx, cz, _agents.size()])
	_refresh_window()
	return spawned


func _spawn_one(wx: int, wz: int) -> bool:
	var ground_y := _standable_ground_y(wx, wz)
	if ground_y < 0:
		return false

	var data := _factory.generate(_birth_index, _used_names)
	var agent := _factory.spawn(data, _birth_index)
	_birth_index += 1
	# Stand on the TOP face of the surface block, centred on the cell.
	agent.position = Vector3(float(wx) + 0.5, float(ground_y + 1), float(wz) + 0.5)
	add_child(agent)
	agent.apply_slice(_slice_y)
	agent.set_name_label_visible(_name_tags)
	_agents.append(agent)
	TaskManager.register_dwarf(agent)
	return true


## A column is standable if it has a valid dry surface and no other dwarf
## already occupies the cell. (Real walkability arrives with NavGrid — this is
## the Phase-1 stand-in; doc 16 build order step 3b.)
func _standable_ground_y(wx: int, wz: int) -> int:
	if wx < 0 or wx >= WorldGenerator.WORLD_SIZE_X \
			or wz < 0 or wz >= WorldGenerator.WORLD_SIZE_Z:
		return -1
	var col := Vector2i(wx, wz)
	if WorldGenerator.lake_columns.has(col) or WorldGenerator.tarn_columns.has(col):
		return -1
	var surface_y := int(WorldGenerator.get_surface_y(wx, wz))
	if surface_y < 0:
		return -1
	# Placed entities (tree trunks, the flag) block the stand cell (doc 32).
	if PlacedEntityRegistry.occupies(Vector3i(wx, surface_y + 1, wz)):
		return -1
	for agent in _agents:
		if is_instance_valid(agent) \
				and floori(agent.position.x) == wx and floori(agent.position.z) == wz:
			return -1
	return surface_y


func _ring_cells(cx: int, cz: int, ring: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if ring == 0:
		cells.append(Vector2i(cx, cz))
		return cells
	for dx in range(-ring, ring + 1):
		for dz in range(-ring, ring + 1):
			if maxi(absi(dx), absi(dz)) != ring:
				continue
			cells.append(Vector2i(cx + dx, cz + dz))
	return cells


# ── Slice culling (doc 11 Phase 5 — same hook as flora) ──────────────────────

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for agent in _agents:
		if is_instance_valid(agent):
			agent.apply_slice(_slice_y)


# ── DEV synthetic tasks (doc 16 step 4 verification) ─────────────────────────

## Queues `count` synthetic MINE-type tasks. radius > 0: walkable-snapped cells
## around the camera (drainable work). radius == 0: random cells across the
## whole map, water and all (exercises probes, backoff, task_unreachable —
## the stress path). Plain randomness is fine here: DEV-only, not gameplay.
func _dev_add_tasks(count: int, radius: int, snap_walkable: bool) -> void:
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready", false)):
		push_warning("DwarfDirector: maps not ready.")
		return
	var cx := 512
	var cz := 512
	if _camera_rig != null:
		cx = clampi(floori(_camera_rig.global_position.x), 0, WorldGenerator.WORLD_SIZE_X - 1)
		cz = clampi(floori(_camera_rig.global_position.z), 0, WorldGenerator.WORLD_SIZE_Z - 1)
	var added := 0
	var attempts := 0
	while added < count and attempts < count * 10:
		attempts += 1
		var wx: int
		var wz: int
		if radius > 0:
			wx = clampi(cx + randi_range(-radius, radius), 0, WorldGenerator.WORLD_SIZE_X - 1)
			wz = clampi(cz + randi_range(-radius, radius), 0, WorldGenerator.WORLD_SIZE_Z - 1)
		else:
			wx = randi_range(0, WorldGenerator.WORLD_SIZE_X - 1)
			wz = randi_range(0, WorldGenerator.WORLD_SIZE_Z - 1)
		var sy := int(WorldGenerator.get_surface_y(wx, wz))
		if sy < 0:
			continue
		var target := Vector3i(wx, sy, wz)
		if snap_walkable:
			target = NavGrid.walkable_floor_at(wx, wz, sy)
			if target.y < 0:
				continue
		TaskManager.add_task(Task.Type.MINE, target, { "synthetic": true })
		added += 1
	print("DwarfDirector: queued %d synthetic tasks (radius %s)." % [
		added, str(radius) if radius > 0 else "whole map"])


# ── Stats (debug overlay, doc 16 Phase 0) ────────────────────────────────────

func get_agent_stats() -> Dictionary:
	var idle := 0
	var sleeping := 0
	for agent in _agents:
		if not is_instance_valid(agent):
			continue
		if agent.is_sleeping():
			sleeping += 1
		elif agent.current_task_id < 0:
			idle += 1
	return { "count": _agents.size(), "idle": idle, "sleeping": sleeping }


# ── DEV interruption (doc 16 Phase 5 — the release-protocol test hooks) ───────

## Force-releases the first working dwarf (reason PLAYER). Instant,
## deterministic; repeated presses cycle through workers.
func _dev_interrupt_worker() -> void:
	for agent in _agents:
		if is_instance_valid(agent) and agent.dev_force_interrupt():
			print("DwarfDirector: DEV interrupt — released %s's task (PLAYER)." % agent.dwarf_name)
			return
	print("DwarfDirector: DEV interrupt — no dwarf holds a task.")


## Drops one dwarf's sleep stat to the threshold — the ORGANIC interrupt path
## (release → sleep in place → wake → resume) fires next frame. Prefers a
## working dwarf so the release protocol is actually exercised.
func _dev_tire_worker() -> void:
	var fallback: DwarfAgent = null
	for agent in _agents:
		if not is_instance_valid(agent) or agent.is_sleeping():
			continue
		if agent.current_task_id >= 0:
			if agent.dev_make_tired():
				print("DwarfDirector: DEV tire — %s will drop their task and sleep." % agent.dwarf_name)
				return
		elif fallback == null:
			fallback = agent
	if fallback != null and fallback.dev_make_tired():
		print("DwarfDirector: DEV tire — %s (idle) will sleep." % fallback.dwarf_name)
		return
	print("DwarfDirector: DEV tire — no awake dwarf available.")


# ── DEV window (dock 'dwarves' entry; SliceController window language) ────────

func toggle_window() -> void:
	_window_layer.visible = not _window_layer.visible
	_refresh_window()


func is_window_visible() -> bool:
	return _window_layer.visible


func _build_window() -> void:
	_window_layer = CanvasLayer.new()
	_window_layer.name = "DwarvesWindow"
	_window_layer.layer = 22
	_window_layer.visible = false
	add_child(_window_layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 420.0)
	panel.custom_minimum_size = Vector2(190.0, 0.0)
	panel.add_theme_stylebox_override("panel", _style(Color(0.065, 0.070, 0.075, 0.94), Color(1, 1, 1, 0.12), 1, 8))
	_window_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "Dwarves"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(30.0, 26.0)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_window)
	header.add_child(close)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_count_label)

	var tags := Button.new()
	tags.text = "Name tags: OFF"
	tags.tooltip_text = "DEV: show floating name labels above dwarves."
	tags.focus_mode = Control.FOCUS_NONE
	tags.custom_minimum_size = Vector2(166.0, 30.0)
	tags.add_theme_font_size_override("font_size", 13)
	tags.pressed.connect(func() -> void:
		_name_tags = not _name_tags
		tags.text = "Name tags: %s" % ("ON" if _name_tags else "OFF")
		for agent in _agents:
			if is_instance_valid(agent):
				agent.set_name_label_visible(_name_tags)
	)
	column.add_child(tags)

	_walk_button = Button.new()
	_walk_button.text = "Walk test: OFF"
	_walk_button.tooltip_text = "While ON, left-click terrain to send the squad there (ESC exits). NavGrid verification."
	_walk_button.focus_mode = Control.FOCUS_NONE
	_walk_button.custom_minimum_size = Vector2(166.0, 30.0)
	_walk_button.add_theme_font_size_override("font_size", 13)
	_walk_button.pressed.connect(func() -> void:
		_set_walk_test(not _walk_test)
	)
	column.add_child(_walk_button)

	var tasks_near := Button.new()
	tasks_near.text = "DEV: +50 tasks here"
	tasks_near.tooltip_text = "Queues 50 synthetic tasks on walkable cells within 30 blocks of the camera. Dwarves walk to each and 'work' 1 s — scheduler loop verification."
	tasks_near.focus_mode = Control.FOCUS_NONE
	tasks_near.custom_minimum_size = Vector2(166.0, 30.0)
	tasks_near.add_theme_font_size_override("font_size", 13)
	tasks_near.pressed.connect(func() -> void:
		_dev_add_tasks(50, 30, true)
	)
	column.add_child(tasks_near)

	var stress := Button.new()
	stress.text = "DEV: stress +500 random"
	stress.tooltip_text = "Queues 500 synthetic tasks at random map cells (many unreachable). Frame time must stay flat — the doc 16 §2.5 no-hang test."
	stress.focus_mode = Control.FOCUS_NONE
	stress.custom_minimum_size = Vector2(166.0, 30.0)
	stress.add_theme_font_size_override("font_size", 13)
	stress.pressed.connect(func() -> void:
		_dev_add_tasks(500, 0, false)
	)
	column.add_child(stress)

	var interrupt := Button.new()
	interrupt.text = "DEV: interrupt worker"
	interrupt.tooltip_text = "Force-releases a working dwarf's task (reason PLAYER). The task returns to PENDING; another idle dwarf should pick it up within one heartbeat — doc 16 §2.8 release-protocol test."
	interrupt.focus_mode = Control.FOCUS_NONE
	interrupt.custom_minimum_size = Vector2(166.0, 30.0)
	interrupt.add_theme_font_size_override("font_size", 13)
	interrupt.pressed.connect(_dev_interrupt_worker)
	column.add_child(interrupt)

	var tire := Button.new()
	tire.text = "DEV: tire a worker"
	tire.tooltip_text = "Drops one dwarf's sleep stat to the threshold — they release their task, sleep in place for 6 in-game hours, then resume work. The organic interrupt path (sleep-lite)."
	tire.focus_mode = Control.FOCUS_NONE
	tire.custom_minimum_size = Vector2(166.0, 30.0)
	tire.add_theme_font_size_override("font_size", 13)
	tire.pressed.connect(_dev_tire_worker)
	column.add_child(tire)

	var spawn := Button.new()
	spawn.text = "DEV: Spawn %d at camera" % squad_size
	spawn.tooltip_text = "Generates the next %d roster dwarves on walkable ground around the camera. Deterministic per world seed." % squad_size
	spawn.focus_mode = Control.FOCUS_NONE
	spawn.custom_minimum_size = Vector2(166.0, 30.0)
	spawn.add_theme_font_size_override("font_size", 13)
	spawn.pressed.connect(func() -> void:
		spawn_squad_at_camera()
	)
	column.add_child(spawn)
	_refresh_window()


func _refresh_window() -> void:
	if _count_label == null:
		return
	_count_label.text = "Roster: %d" % _agents.size()


func _style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style
