class_name DwarfDirector
extends Node3D

## Owns the colony's dwarf roster (doc 16 Phase 1). Scene node in
## debug_world.tscn — agents are its children, so positions are world
## coordinates (the SurfaceFloraSpawner pattern).
##
## Phase 1 scope: deterministic roster generation (birth-index ordered),
## The Colony roster presents real agents through the shared inspector.
## Developer spawning/walk controls live separately under Development.
## The Settlement Flag remains the player-facing arrival flow.

@export var camera_path: NodePath
@export var slice_controller_path: NodePath
@export var window_manager_path: NodePath
## Dock whose tools are dropped when a dwarf is inspected.
@export var dock_ui_path: NodePath

## Dwarves per DEV spawn press.
@export_range(1, 20, 1) var squad_size: int = 5

const SLICE_OFF_Y: int = SliceController.MAX_SLICE_Y
const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var _picking := Picking.new()

var _camera_rig: Node3D = null
var _factory := DwarfFactory.new()
var _agents: Array[DwarfAgent] = []
var _birth_index: int = 0
var _used_names: Dictionary = {}
var _slice_y: int = SLICE_OFF_Y

var _window_manager: UIWindowManager = null
var _dock_ui: Node = null
var _count_label: Label
var _walk_button: Button
var _roster_panel: Control
var _roster_window: UIWindow
var _profession_panel: Control

## DEV walk test (step 3b): while ON, left-click terrain orders the whole
## squad to path there — the visual verification for NavGrid (around trees,
## up/down terraces, refusing water).
var _walk_test: bool = false
var _name_tags: bool = false


func _ready() -> void:
	add_to_group(SaveManager.OWNER_GROUP)
	add_to_group("object_explorer_provider")
	add_to_group("dwarf_director")
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_window_manager = get_node_or_null(window_manager_path) as UIWindowManager
	_dock_ui = get_node_or_null(dock_ui_path) if not dock_ui_path.is_empty() else null
	_register_window()

	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)


func is_walk_test_active() -> bool:
	return _walk_test


## Stable birth order and live node identity, excluding removed actors.
func get_roster() -> Array[DwarfAgent]:
	var result: Array[DwarfAgent] = []
	for agent in _agents:
		if is_instance_valid(agent) and not agent.is_queued_for_deletion(): result.append(agent)
	return result


func can_inspect_dwarf(agent: Variant) -> bool:
	return _inspectable(agent)


func inspect_dwarf(agent: Variant) -> bool:
	if not _inspectable(agent): return false
	var explorer := get_tree().get_first_node_in_group("object_explorer")
	if explorer == null: return false
	if _dock_ui != null: _dock_ui.tool_requested.emit("")
	_set_walk_test(false)
	return explorer.select_object(self, agent)


# Node identity prevents a selected dwarf being silently replaced by a newly
# loaded roster member with the same numeric ID.
func _inspectable(id: Variant) -> bool:
	return is_instance_valid(id) and id is DwarfAgent and not id.is_queued_for_deletion() \
		and id in _agents and id.is_visible_in_tree() and floori(id.global_position.y) <= _slice_y


func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var nearest := INF
	var selected: DwarfAgent
	for agent: DwarfAgent in _agents:
		if not _inspectable(agent):
			continue
		if Picking.visible_world_bounds(agent).intersects_segment(start, end) == null:
			continue
		var distance := _picking.hit_distance(agent, start, end)
		if distance < nearest:
			nearest = distance
			selected = agent
	return {"id": selected, "distance": nearest} if selected != null else {}


func get_explorer_data(id: Variant) -> Dictionary:
	if not _inspectable(id): return {}
	var data := Inspection.describe(id)
	# The compact panel's actions (doc 260): Follow stays lit while the camera follows.
	var following := is_following(id)
	data.actions = [{"id": "follow", "text": "Stop following" if following else "Follow", "active": following},
		{"id": "locate", "text": "Locate"}]
	return data


func get_explorer_bounds(id: Variant) -> AABB:
	return Picking.visible_world_bounds(id) if _inspectable(id) else AABB()


func perform_explorer_action(id: Variant, action: String) -> void:
	if action == "profession":
		if _inspectable(id): open_professions(id)
		return
	if action == "crafting":   # Colony Dwarves' Details card: this profession's crafting
		var section := Inspection.crafting_section(id) if _inspectable(id) else ""
		if not section.is_empty() and _dock_ui != null: _dock_ui.open_crafting("", section)
		return
	if not _inspectable(id) or not is_instance_valid(_camera_rig):
		return
	if action == "locate" and _camera_rig.has_method("locate_subject"):
		_camera_rig.call("locate_subject", id)
	elif action == "follow" and _camera_rig.has_method("follow_subject"):
		_camera_rig.call("follow_subject", id)
	elif action == "stop_follow" and _camera_rig.has_method("stop_following"):
		_camera_rig.call("stop_following")


func is_following(id: Variant) -> bool:
	return _inspectable(id) and is_instance_valid(_camera_rig) \
		and _camera_rig.has_method("is_following") and bool(_camera_rig.call("is_following", id))


func clear_explorer_selection(id: Variant) -> void:
	if is_instance_valid(_camera_rig) and _camera_rig.has_method("is_following") \
			and bool(_camera_rig.call("is_following", id)):
		_camera_rig.call("stop_following")


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
	return Picking.surface_hit(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse), 700.0, 0.5)


func _set_walk_test(active: bool) -> void:
	_walk_test = active
	if _walk_button != null:
		_walk_button.text = "Walk test: %s" % ("ON — click ground" if _walk_test else "OFF")


# ── Settlement anchor (doc 16 Phase 1 — set by the Flag flow) ────────────────

## Last installed Settlement Flag cell; retained while packed. (-1,-1,-1) = unfounded.
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

	var cx := clampi(wx, 0, WorldData.WORLD_SIZE_X - 1)
	var cz := clampi(wz, 0, WorldData.WORLD_SIZE_Z - 1)

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
	refresh_window()
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
	preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(agent)
	agent.apply_slice(_slice_y)
	agent.set_name_label_visible(_name_tags)
	_agents.append(agent)
	TaskManager.register_dwarf(agent)
	return true


## A column is standable if it has a valid dry surface and no other dwarf
## already occupies the cell. (Real walkability arrives with NavGrid — this is
## the Phase-1 stand-in; doc 16 build order step 3b.)
func _standable_ground_y(wx: int, wz: int) -> int:
	if wx < 0 or wx >= WorldData.WORLD_SIZE_X \
			or wz < 0 or wz >= WorldData.WORLD_SIZE_Z:
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


# ── Stats (debug overlay, doc 16 Phase 0) ────────────────────────────────────

func get_agent_stats() -> Dictionary:
	var idle := 0
	var sleeping := 0
	for agent in _agents:
		if not is_instance_valid(agent):
			continue
		if agent.is_sleeping():
			sleeping += 1
		elif agent.current_task_id < 0 and not agent.is_eating() and not agent.promotion_pending():
			idle += 1
	return { "count": _agents.size(), "idle": idle, "sleeping": sleeping }


func save_section_key() -> String:
	return "dwarves"


func save_restore_priority() -> int:
	return 60


func serialize_state() -> Dictionary:
	var roster: Array = []
	for agent in _agents:
		if is_instance_valid(agent):
			roster.append(agent.serialize_state())
	return {
		"birth_index": _birth_index,
		"settlement_anchor": SaveManager.pack_v3i(settlement_anchor),
		"roster": roster,
	}


func restore_state(state: Dictionary) -> void:
	_birth_index = maxi(int(state.get("birth_index", 0)), 0)
	settlement_anchor = SaveManager.unpack_v3i(state.get("settlement_anchor", [-1, -1, -1]))
	_used_names.clear()
	var item_manager := ItemDropManager.find(get_tree())
	for raw in state.get("roster", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var dwarf_id := int(entry.get("id", _birth_index))
		var dwarf_name := String(entry.get("name", "Urist"))
		var data := {
			"name": dwarf_name,
			"gender": String(entry.get("gender", "male")),
			"appearance": _appearance_from_save(entry.get("appearance", {}) as Dictionary),
			"traits": entry.get("traits", []),
			"tastes": entry.get("tastes", {}),
			"found_tastes": entry.get("found_tastes", []),
			"profession": String(entry.get("profession", "base:profession:worker")),
			"profession_experience": entry.get("profession_experience", {}),
			"work_permissions": entry.get("work_permissions", {}),
		}
		var agent := _factory.spawn(data, dwarf_id)
		agent.position = SaveManager.unpack_v3(entry.get("position", []))
		agent.rotation.y = float(entry.get("rotation_y", 0.0))
		add_child(agent)
		preload("res://scripts/components/UndergroundLighting.gd").bind_world_tree(agent)
		agent.restore_saved_runtime(entry)
		agent.apply_slice(_slice_y)
		agent.set_name_label_visible(_name_tags)
		_agents.append(agent)
		_used_names[dwarf_name] = true
		TaskManager.register_dwarf(agent)
		if agent.is_sleeping():
			TaskManager.notify_dwarf_unavailable(dwarf_id)
		var carried_index := 0
		for saved_cargo: Dictionary in entry.get("carried_items", []):
			if item_manager == null:
				break
			var angle := float(carried_index) * 2.399963
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.22
			var item_key := String(saved_cargo.item_key)
			var count := int(saved_cargo.count)
			var instance_id := String(saved_cargo.get("instance_id", ""))
			item_manager.restore_loose_item(item_key, agent.position + offset, 0.0, count, instance_id, bool(saved_cargo.get("disallowed", false)), String(saved_cargo.get("material_id", "")))
			carried_index += 1
		_birth_index = maxi(_birth_index, dwarf_id + 1)
	refresh_window()


func _appearance_from_save(state: Dictionary) -> DwarfAppearanceData:
	var result := DwarfAppearanceData.new()
	result.gender = String(state.get("gender", "male"))
	result.age_tier = String(state.get("age_tier", "adult"))
	result.skin_tone = String(state.get("skin_tone", "medium"))
	result.eye_color = String(state.get("eye_color", "grey"))
	result.hair_color = String(state.get("hair_color", "brown"))
	result.hair_style = String(state.get("hair_style", "short_back"))
	result.eyebrow_style = String(state.get("eyebrow_style", "thick_flat"))
	result.beard_style = String(state.get("beard_style", ""))
	result.scar = String(state.get("scar", "none"))
	result.clothing = String(state.get("clothing", ""))
	return result


# ── DEV interruption (doc 16 Phase 5 — the release-protocol test hooks) ───────

## Force-releases the first working dwarf (reason PLAYER). Instant,
## deterministic; repeated presses cycle through workers.
func _dev_interrupt_worker() -> void:
	for agent in _agents:
		if is_instance_valid(agent) and agent.force_interrupt():
			print("DwarfDirector: DEV interrupt — released %s's task (PLAYER)." % agent.dwarf_name)
			return
	print("DwarfDirector: DEV interrupt — no dwarf holds a task.")


## Trigger real food seeking without spawning supplies or granting nutrition.
func _dev_make_worker_hungry() -> void:
	for agent in _agents:
		if is_instance_valid(agent) and agent.dev_make_hungry():
			print("DwarfDirector: %s will look for a food portion." % agent.dwarf_name)
			return


## Drop rest to its threshold, preferring a working dwarf to exercise release.
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


# ── Roster and development windows ──────────────────────────────────────────

func toggle_window() -> void:
	if _window_manager == null:
		return
	_window_manager.toggle("dwarves")
	refresh_window()


func is_window_visible() -> bool:
	return _window_manager != null and _window_manager.is_open("dwarves")


func open_professions(agent: DwarfAgent) -> void:
	if _window_manager == null or not agent in get_roster(): return
	_window_manager.open("professions")
	_profession_panel.begin_browsing(agent)


func open_work_view() -> void:
	if _window_manager == null: return
	_window_manager.open("dwarves")
	_roster_panel.set_work_view(true)


func _register_window() -> void:
	if _window_manager == null:
		push_warning("DwarfDirector: UIWindowManager not found at '%s' — roster disabled." % window_manager_path)
		return
	_roster_panel = preload("res://scripts/ui/DwarfRosterPanel.gd").new()
	_roster_panel.director = self
	_roster_panel.dock = _dock_ui
	_roster_window = _window_manager.register_window("dwarves", "Colony Dwarves", "", _roster_panel,
		{"persistent": false, "default_pos": Vector2(24, 76), "family": "people", "flush": true})
	_roster_window.keep_body_on_screen = true
	_roster_panel.window = _roster_window
	_roster_panel.refit.call_deferred()
	_profession_panel = preload("res://scripts/ui/DwarfProfessionPanel.gd").new()
	_profession_panel.director = self
	_profession_panel.manager = _window_manager
	_profession_panel.dock = _dock_ui
	var promotion_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: promotion_margin.add_theme_constant_override("margin_" + side, 12)
	promotion_margin.add_child(_profession_panel)
	var promotion_window := _window_manager.register_window("professions", "Professions", "", promotion_margin,
		{"persistent": false, "default_pos": Vector2(70, 50), "family": "people", "flush": true})
	promotion_window.keep_body_on_screen = true
	_profession_panel.window = promotion_window
	if UIRegistry.dev_tools_enabled: _register_dev_window()
	_window_manager.window_state_changed.connect(_on_window_state_changed)


func _register_dev_window() -> void:
	if _window_manager == null:
		push_warning("DwarfDirector: UIWindowManager not found at '%s' — DEV window disabled." % window_manager_path)
		return

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", UITheme.TYPE_MEDIUM.body)
	column.add_child(_count_label)

	var button_size := Vector2(166.0, 30.0)

	var tags := UITheme.make_button("Name tags: OFF",
		"DEV: show floating name labels above dwarves.", button_size, "dev")
	tags.pressed.connect(func() -> void:
		_name_tags = not _name_tags
		tags.text = "Name tags: %s" % ("ON" if _name_tags else "OFF")
		for agent in _agents:
			if is_instance_valid(agent):
				agent.set_name_label_visible(_name_tags)
	)
	column.add_child(tags)

	_walk_button = UITheme.make_button("Walk test: OFF",
		"While ON, left-click terrain to send the squad there (ESC exits). NavGrid verification.",
		button_size, "dev")
	_walk_button.pressed.connect(func() -> void:
		_set_walk_test(not _walk_test)
	)
	column.add_child(_walk_button)

	var interrupt := UITheme.make_button("DEV: interrupt worker",
		"Force-releases a working dwarf's task (reason PLAYER). The task returns to PENDING; another idle dwarf should pick it up within one heartbeat — doc 16 §2.8 release-protocol test.",
		button_size, "dev")
	interrupt.pressed.connect(_dev_interrupt_worker)
	column.add_child(interrupt)
	var jobs := UITheme.make_button("DEV: Job inspector","Inspect order progress, waiting reasons and recovery history.",button_size,"dev")
	jobs.pressed.connect(func(): _window_manager.toggle("jobs_dev"))
	column.add_child(jobs)
	var job_panel := preload("res://scripts/ui/JobInspectorPanel.gd").new()
	_window_manager.register_window("jobs_dev","Job inspector","",job_panel,
		{"persistent":false,"default_pos":Vector2(220,130),"family":"dev"})

	var tire := UITheme.make_button("DEV: tire a worker",
		"Drops one dwarf's sleep stat to the threshold — they release their task, sleep in place for 6 in-game hours, then resume work. The organic interrupt path (sleep-lite).",
		button_size, "dev")
	tire.pressed.connect(_dev_tire_worker)
	column.add_child(tire)
	var hunger := UITheme.make_button("DEV: make a dwarf hungry",
		"Lowers one awake dwarf's Food to the hungry threshold. They must find and eat real food through normal behavior.",button_size,"dev")
	hunger.pressed.connect(_dev_make_worker_hungry)
	column.add_child(hunger)

	var spawn := UITheme.make_button("DEV: Spawn %d at camera" % squad_size,
		"Generates the next %d roster dwarves on walkable ground around the camera. Deterministic per world seed." % squad_size,
		button_size, "dev")
	spawn.pressed.connect(func() -> void:
		spawn_squad_at_camera()
	)
	column.add_child(spawn)

	_window_manager.register_window("dwarves_dev", "Dwarf development", "", column,
		{"persistent": false, "default_pos": Vector2(24, 130), "family": "dev"})
	refresh_window()


## Roster label can go stale while the window is closed (spawns, loads) —
## refresh on every open. The manager's one signal replaces the old
## toggle_window-side refresh.
func _on_window_state_changed(id: String, open: bool) -> void:
	if id == "professions" and not open: _profession_panel.clear_subject()
	if id == "dwarves":
		if open:
			_set_walk_test(false)
			_roster_panel.begin_browsing()
		else:
			_roster_panel.end_browsing()
			_window_manager.close("professions")
	elif id == "dwarves_dev" and open: refresh_window()


func refresh_window() -> void:
	if _roster_panel != null: _roster_panel.refresh()
	if _count_label == null:
		return
	_count_label.text = "Roster: %d" % _agents.size()
