extends RefCounted

## Furniture windows and object-explorer provider for
## FurniturePlacementController (doc 258 step 8): click-select, the compact
## ghost/installed window (the stockpile zone window pattern, with the DEV
## Instant Build and DEV Remove buttons) and the explorer's picking, bounds,
## inspection rows and actions. Actions go back through the controller's public
## methods.

# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
const WallMount = preload("res://scripts/components/WallFurnitureMount.gd")
const GridFence = preload("res://scripts/components/GridFence.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")

var controller
var rules   # FurniturePlacementRules: the shared piece and wall tables
var ghost_id: int = -1
var installed_id: int = -1
var _picking := Picking.new()
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _title: Label = null
var _info: Label = null
var _build_btn: Button = null
var _remove_btn: Button = null


func _init(owner_controller, placement_rules) -> void:
	controller = owner_controller
	rules = placement_rules


# ── Windows (compact — the stockpile zone window pattern) ─────────────────────

func build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FurnitureWindow"
	_layer.layer = 22
	_layer.visible = false
	controller.add_child(_layer)

	_panel = PanelContainer.new()
	UITheme.apply_surface(_panel)
	_panel.position = Vector2(18.0, 470.0)
	_panel.custom_minimum_size = Vector2(220.0, 0.0)
	_panel.add_theme_stylebox_override("panel", UITheme.window_style())
	_layer.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_heading(_title)
	header.add_child(_title)

	var close_button := Button.new()
	UITheme.apply_close_button(close_button)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", MEDIUM.body)
	column.add_child(_info)

	_build_btn = Button.new()
	_build_btn.text = "DEV: Instant Build"
	UITheme.apply_button_variant(_build_btn, "dev")
	_build_btn.focus_mode = Control.FOCUS_NONE
	_build_btn.custom_minimum_size = Vector2(186.0, 30.0)
	_build_btn.add_theme_font_size_override("font_size", MEDIUM.small)
	_build_btn.pressed.connect(_on_primary_pressed)
	column.add_child(_build_btn)

	_remove_btn = Button.new()
	_remove_btn.focus_mode = Control.FOCUS_NONE
	_remove_btn.custom_minimum_size = Vector2(186.0, 30.0)
	_remove_btn.add_theme_font_size_override("font_size", MEDIUM.small)
	_remove_btn.pressed.connect(_on_remove_pressed)
	column.add_child(_remove_btn)


## Primary button: ghost window = DEV Instant Build; installed window = the
## 📤 uninstall TOGGLE (SH parity — clicking again cancels).
func _on_primary_pressed() -> void:
	if ghost_id >= 0:
		controller.dev_instant_build(ghost_id)
		return
	if installed_id >= 0:
		var component: InstalledFurnitureComponent = controller.get_installed(installed_id)
		if component != null:
			controller.toggle_uninstall(component)
			open_installed(installed_id)   # refresh labels


func _on_remove_pressed() -> void:
	if ghost_id >= 0:
		controller.cancel_ghost(ghost_id)
	elif installed_id >= 0:
		controller.dev_remove_installed(installed_id)


func open_ghost(id: int) -> void:
	var ghost: FurnitureGhostComponent = controller.get_ghost(id)
	if ghost == null:
		return
	ghost_id = id
	installed_id = -1
	_title.text = "Ghost — %s" % ghost.display_name()
	if ghost.has_lease():
		_info.text = "Waiting for a dwarf to fetch:\n%s" % ghost.item_key
	else:
		_info.text = "Needs: %s\n(none in the colony)" % ghost.item_key
	_build_btn.text = "DEV: Instant Build"
	UITheme.apply_button_variant(_build_btn, "dev")
	_build_btn.visible = UIRegistry.dev_tools_enabled and not bool(ghost.def.get("plant", false))
	_remove_btn.text = "Cancel"
	UITheme.apply_button_variant(_remove_btn, "danger")
	_remove_btn.visible = true
	_layer.visible = true


func open_installed(id: int) -> void:
	var component: InstalledFurnitureComponent = controller.get_installed(id)
	if component == null:
		return
	installed_id = id
	ghost_id = -1
	_title.text = component.display_name()
	var status_line := "Marked for uninstall — a dwarf is coming." if component.flagged_uninstall else "Installed."
	_info.text = status_line
	_build_btn.text = "Cancel uninstall" if component.flagged_uninstall else "Uninstall"
	UITheme.apply_button_variant(_build_btn)
	_build_btn.visible = true
	_remove_btn.text = "DEV: Remove (drops item)"
	UITheme.apply_button_variant(_remove_btn, "dev")
	_remove_btn.visible = UIRegistry.dev_tools_enabled
	_layer.visible = true


func close() -> void:
	ghost_id = -1
	installed_id = -1
	_layer.visible = false


# ── Click-select (tool on or off — the A3 lesson) ─────────────────────────────

func try_select_at_screen(screen_pos: Vector2) -> bool:
	var hit: Dictionary = controller.surface_cell_for(screen_pos)
	if _try_select_wall(screen_pos, hit):
		return true
	if hit.is_empty():
		return false
	var cell := Vector3i(int(hit["x"]), int(hit["y"]), int(hit["z"]))
	if rules.cell_to_ghost.has(cell):
		open_ghost(int(rules.cell_to_ghost[cell]))
		return true
	if rules.cell_to_installed.has(cell):
		open_installed(int(rules.cell_to_installed[cell]))
		return true
	return false


func _try_select_wall(screen_pos: Vector2, terrain_hit: Dictionary) -> bool:
	var camera: Camera3D = controller.get_viewport().get_camera_3d()
	if camera == null:
		return false
	var ray_max := FurniturePlacementController.RAY_MAX
	var start := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos).normalized()
	var nearest := float(terrain_hit.get("distance", ray_max)) + .001
	var selected_id := -1
	var selected_ghost := false
	for ghost_pass: bool in [true, false]:
		var pieces: Dictionary = rules.ghosts if ghost_pass else rules.installed
		var ids: Array = rules.wall_to_ghost.values() if ghost_pass else rules.wall_to_installed.values()
		for id: int in pieces:
			if GridFence.applies(pieces[id].def): ids.append(id)
		for id: int in ids:
			var piece = pieces[id]
			if piece.node == null or not piece.node.is_visible_in_tree():
				continue
			var bounds: AABB = controller.visual_bounds(piece.def,piece.origin_cell,piece.yaw_steps) if GridFence.applies(piece.def) else WallMount.bounds_for(piece.def, piece.origin_cell, piece.yaw_steps)
			var intersection: Variant = bounds.intersects_segment(start, start + direction * ray_max)
			if intersection == null:
				continue
			var distance := start.distance_to(intersection as Vector3)
			if GridFence.applies(piece.def): distance = _picking.hit_distance(piece.node,start,start+direction*ray_max)
			if distance < nearest:
				nearest = distance
				selected_id = id
				selected_ghost = ghost_pass
	if selected_id < 0:
		return false
	if selected_ghost:
		open_ghost(selected_id)
	else:
		open_installed(selected_id)
	return true


# ── Object explorer provider ──────────────────────────────────────────────────

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for ghost_pass: bool in [true, false]:
		var pieces: Array = controller.get_ghost_pieces() if ghost_pass else controller.get_installed_pieces()
		for piece in pieces:
			if not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
				continue
			if controller.visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps).intersects_segment(start, end) == null:
				continue
			var distance := _picking.hit_distance(piece.node, start, end)
			if distance < nearest:
				nearest = distance
				var id: int = piece.ghost_id if ghost_pass else piece.installed_id
				result = {"id": "%s:%d" % ["ghost" if ghost_pass else "installed", id], "distance": distance}
	return result


func explorer_piece(object_id: Variant) -> Variant:
	var id := String(object_id)
	if id.begins_with("ghost:"):
		return controller.get_ghost(int(id.get_slice(":", 1)))
	if id.begins_with("installed:"):
		return controller.get_installed(int(id.get_slice(":", 1)))
	return null


func get_explorer_bounds(object_id: Variant) -> AABB:
	var piece = explorer_piece(object_id)
	if piece == null or not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
		return AABB()
	return controller.visual_bounds(piece.def, piece.origin_cell, piece.yaw_steps)


func get_explorer_data(object_id: Variant) -> Dictionary:
	var piece = explorer_piece(object_id)
	if piece == null or not is_instance_valid(piece.node) or not piece.node.is_visible_in_tree():
		return {}
	var moves = controller.get_moves()
	var rows: Array = []
	var actions: Array = []
	var details := String(piece.def.get("description", ""))
	var in_use := {}   # the compact panel's line for an installed piece in use (doc 260)
	if piece is FurnitureGhostComponent:
		rows.append(["Status", "Awaiting delivery" if piece.has_lease() else "Awaiting packed item"])
		if WallMount.is_wall(piece.def) and WallMount.work_stands(piece.def,piece.origin_cell,piece.yaw_steps).is_empty():
			rows[0][1] = "Waiting for reachable work position"
		rows.append(["Required item", _explorer_item_name(piece.item_key)])
		actions = [
			{"id": "cancel", "text": "Cancel placement", "variant": "danger"},
			{"id": "build", "text": "DEV: Instant Build", "variant": "dev"},
		]
	else:
		rows.append(["Status", "Marked for uninstall" if piece.flagged_uninstall else "Installed"])
		if bool(piece.def.get("room_heater", false)):
			var heating := RoomManager.heat_source_status(piece.origin_cell + Vector3i.UP, int(piece.def.heat_source.heat_units))
			if heating.is_empty():
				rows.append(["Heating", "No enclosed room"])
				details += "\n\nNot inside an enclosed room. Walls, a roof and a door let this hearth heat a room."
				in_use = {"text": "No enclosed room to heat", "tone": "blocked"}
			else:
				rows.append(["Heating room", "%s · #%d" % [heating.room_label, heating.room_id]])
				rows.append(["Temperature", "%.1f°C · %s" % [heating.temperature_c, heating.comfort]])
				rows.append(["This hearth", "+%.1f°C" % heating.contribution_c])
				in_use = {"text": "Heating the %s · %.1f°C" % [String(heating.room_label).to_lower(), heating.temperature_c], "tone": "fine"}
		if piece.def.get("recreation","") == "board_game":
			var seat_count: int = controller.get_dining_seats(piece.installed_id).filter(func(slot): return not controller.get_installed(slot.chair_id).flagged_uninstall).size()
			var game = controller.get_board_games().games.get(piece.installed_id)
			rows.append(["Log stools", "%d / 2 installed" % seat_count])
			rows.append(["Game", "Playing together" if game != null and game.together else "Playing alone · partner welcome" if game != null and game.playing else "Going to play" if game != null else "Needs a log stool" if seat_count==0 else "Ready for solo or shared play"])
			in_use = {"text": rows[-1][1], "tone": "waiting" if seat_count == 0 else "fine"}
			var effect: Dictionary = TaskManager.get_config_section("mood").recreation
			rows.append(["Happiness", "Solo +%d · Together +%d for %.0f game hours after a completed game" % [roundi(float(effect.solo_bonus)*100),roundi(float(effect.bonus)*100),float(effect.duration_hours)]])
		if piece.def.has("sleep_surface"):
			var assigned: DwarfAgent = TaskManager.get_agent(piece.assigned_dwarf_id)
			rows.append(["Assigned to", assigned.dwarf_name if is_instance_valid(assigned) else "Unassigned"])
			in_use = {"text": "%s's bed" % assigned.dwarf_name if is_instance_valid(assigned) else "Anyone may sleep here", "tone": "fine"}
			var sleeper: DwarfAgent = TaskManager.get_agent(piece.sleep_owner)
			rows.append(["Sleeper", sleeper.dwarf_name if is_instance_valid(sleeper) else "Available"])
		rows.append_array(CraftMaterials.inspection_rows(piece.def, piece.material_id))
		actions = [
			{"id": "uninstall", "text": "Cancel uninstall", "icon": "res://assets/ui/icons/cancel.png"} if piece.flagged_uninstall else {"id": "uninstall", "text": "Uninstall"},
			{"id": "remove", "text": "DEV: Remove (drops item)", "variant": "dev"},
		]
		if piece.def.has("sleep_surface"):
			actions.push_front(preload("res://scripts/components/BedAssignment.gd").action(controller,piece))
		if not moves.for_source(piece.installed_id).is_empty():
			rows[0][1] = "Waiting to move"
			actions[actions.size()-2] = {"id":"cancel_move","text":"Cancel move"}
		elif not piece.flagged_uninstall:
			actions.push_front({"id":"move","text":"Move"})
	if piece.def.has("placement_label"):
		rows.append(["Footprint", String(piece.def.placement_label)])
	if piece is FurnitureGhostComponent and moves.records.has(piece.required_instance_id):
		rows[0][1] = "Awaiting uninstall" if int(moves.records[piece.required_instance_id].installed_id)>=0 else "Worker delivery / placement" if piece.has_lease() else "Awaiting packed furniture"
		return _compact({"title":CraftMaterials.product_name(piece.display_name(),piece.required_material_id),"rows":rows,
			"details":"A dwarf will pack this exact piece and install it here. Cancelling before packing leaves it installed; cancelling afterward keeps the packed item.",
			"actions":[{"id":"cancel","text":"Cancel move"}]}, piece, in_use)
	if WallMount.is_wall(piece.def):
		rows.append(["Mount level",str(WallMount.mount_cell(piece.def,piece.origin_cell).y)])
		if piece is InstalledFurnitureComponent and piece.flagged_uninstall and piece.wall_work_stands().is_empty(): rows[0][1] = "Waiting for reachable work position"
	if piece is InstalledFurnitureComponent and piece.furniture_key == "base:furniture:crude_workbench" and not piece.flagged_uninstall:
		actions.push_front({"id":"craft", "text":"Craft items"})
		rows.append(["Crafter", "Any Worker"])
		in_use = {"text": "Any Worker crafts here", "tone": "fine"}
	if piece.def.has("water_stone"):
		return _compact({"title":piece.display_name(),"rows":rows,"details":"A dwarf will pack, carry and place this stone. Water resumes at its destination after placement.","actions":[{"id":"cancel","text":"Cancel placement"}]}, piece, in_use)
	if bool(piece.def.get("plant", false)):
		var cutting := bool(piece.def.get("from_cutting", false))
		var status := "Awaiting cutting" if cutting else "Awaiting whole plant"
		var plants: Node = controller.get_tree().get_first_node_in_group("surface_details")
		if not piece.required_instance_id.is_empty() and plants != null and not bool(plants.get_change(piece.required_instance_id).get("packed", false)):
			status = "Awaiting uprooting"
		elif piece.has_lease(): status = "Worker delivery / planting"
		rows[0] = ["Status", status]
		rows.append(["Planting", "%d%%" % floori(piece.progress / float(piece.def.planting_seconds) * 100)])
		return _compact({"title":piece.display_name(), "rows":rows,
			"details":"Uses one cutting to grow a young shrub. Cancelling before completion keeps the cutting intact." if cutting else "The existing plant keeps its seasonal state. Cancelling after uprooting leaves the whole plant available for storage or another placement.",
			"actions":[{"id":"cancel","text":"Cancel planting"}]}, piece, in_use)
	return _compact({"title": piece.display_name(), "rows": rows, "details": details, "actions": actions}, piece, in_use)


## The compact panel's fields (doc 260): the piece's picture, its appeal on the badge and
## one status line. A waiting or blocked Status row wins over the in-use line.
func _compact(data: Dictionary, piece, in_use: Dictionary) -> Dictionary:
	data.family = "settlement"
	data.picture = "res://assets/ui/furniture/%s.png" % String(piece.furniture_key).get_slice(":", 2)
	if piece.def.has("appeal"):
		var material: String = piece.material_id
		if piece is FurnitureGhostComponent and not piece.required_material_id.is_empty(): material = piece.required_material_id
		data.badge = CraftMaterials.appeal_badge(piece.def, material)
	var state := String(data.rows[0][1])
	if state.begins_with("Waiting for reachable"): data.status = {"text": state, "tone": "blocked"}
	elif piece is FurnitureGhostComponent or state != "Installed": data.status = {"text": state, "tone": "waiting"}
	elif not in_use.is_empty(): data.status = in_use
	return data


func perform_explorer_action(object_id: Variant, action_id: String) -> void:
	var piece = explorer_piece(object_id)
	if piece == null:
		return
	if piece is FurnitureGhostComponent:
		if action_id == "cancel":
			controller.cancel_ghost(piece.ghost_id)
		elif action_id == "build":
			controller.dev_instant_build(piece.ghost_id)
	elif action_id == "craft" and piece.furniture_key == "base:furniture:crude_workbench" and not piece.flagged_uninstall:
		var dock_ui: Node = controller.get_dock_ui()
		if dock_ui != null: dock_ui.open_crafting("base:recipe:worker:wooden_torch")
	elif action_id.begins_with("assign_bed:"):
		controller.assign_bed(piece.installed_id,int(action_id.get_slice(":",1)))
	elif action_id == "move":
		controller.begin_furniture_move(piece.installed_id)
	elif action_id in ["uninstall","cancel_move"]:
		controller.toggle_uninstall(piece)
	elif action_id == "remove":
		controller.dev_remove_installed(piece.installed_id)


func _explorer_item_name(item_key: String) -> String:
	var drop_manager = controller.get_drop_manager()
	if is_instance_valid(drop_manager):
		var definition: Dictionary = drop_manager.get_item_def(item_key)
		if definition.has("display_name"):
			return String(definition["display_name"])
	return item_key.get_slice(":", item_key.get_slice_count(":") - 1).capitalize()
