extends VBoxContainer

## A career map and appointment card for one explicit dwarf. Planned roles
## remain inspectable but only the registry's runtime allowlist can promote.
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const PREFIX := "base:profession:"
var director: Node
var manager: UIWindowManager
var window: UIWindow
var _agent: DwarfAgent
var _selected := PREFIX + "miner"
var _entries := {}
var _nodes := {}
var _tree: Control
var _body: HBoxContainer
var _left_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _identity: Label
var _current: Label
var _portrait: SubViewport
var _model: Node3D
var _role_name: Label
var _description: Label
var _rewards: Label
var _appointment: Label
var _requirements: Label
var _status: Label
var _experience: Label
var _progress: ProgressBar
var _promote: Button
var _feedback: Label
var _elapsed := 0.0
var _compact := false
var _portrait_texture: TextureRect
var _paper: PanelContainer
var _paper_column: VBoxContainer
var _paper_heading: Label


func _ready() -> void:
	UITheme.apply_surface(self)
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	add_child(header)
	var portrait_texture := TextureRect.new()
	_portrait_texture = portrait_texture
	portrait_texture.custom_minimum_size = Vector2(54, 60)
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(portrait_texture)
	_portrait = Portrait.create_viewport(portrait_texture)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	_identity = _label(identity, "", 23)
	UITheme.apply_title(_identity, 23)
	_current = _label(identity, "", 13, UITheme.HEARTH_MUTED)
	var back := UITheme.make_button("Back to colony", "Return to this dwarf in the colony roster", Vector2(132, 34))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		manager.open("dwarves")
		if is_instance_valid(_agent): director.inspect_dwarf(_agent)
		manager.close("professions"))
	header.add_child(back)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	_body.add_child(left)
	_label(left, "CAREER PATHS", 11, UITheme.HEARTH_COPPER)
	_left_scroll = ScrollContainer.new()
	_left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_scroll.mouse_force_pass_scroll_events = false
	left.add_child(_left_scroll)
	_tree = Control.new()
	_tree.custom_minimum_size = Vector2(656, 342)
	_left_scroll.add_child(_tree)
	for entry: Dictionary in DwarfAssets.promotion_entries():
		var key := PREFIX + String(entry.role)
		_entries[key] = entry
		_build_node(key, entry)
	_tree.draw.connect(_draw_connections)
	_label(left, "Current / Available = usable now    ·    Planned = future gameplay", 12, UITheme.HEARTH_MUTED)
	var details := PanelContainer.new()
	details.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	left.add_child(details)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.mouse_force_pass_scroll_events = false
	_detail_scroll.custom_minimum_size.y = 150
	details.add_child(_detail_scroll)
	var detail_column := VBoxContainer.new()
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 8)
	_detail_scroll.add_child(detail_column)
	_role_name = _label(detail_column, "", 22)
	UITheme.apply_title(_role_name, 22)
	_description = _label(detail_column, "", 14)
	_rewards = _label(detail_column, "", 13, UITheme.HEARTH_MUTED)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	right.add_theme_constant_override("separation", 10)
	_body.add_child(right)
	var paper := PanelContainer.new()
	_paper = paper
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	paper.add_theme_stylebox_override("panel", UITheme.style(UITheme.CATALOG_PAPER, UITheme.CATALOG_GOLD, 2, 3, 18, 18))
	right.add_child(paper)
	var paper_scroll := ScrollContainer.new()
	paper_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper_scroll.mouse_force_pass_scroll_events = false
	paper.add_child(paper_scroll)
	var column := VBoxContainer.new()
	_paper_column = column
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	paper_scroll.add_child(column)
	_paper_heading = _label(column, "COLONY APPOINTMENT", 11, UITheme.CATALOG_MUTED)
	_appointment = _label(column, "", 23, UITheme.CATALOG_INK)
	_appointment.add_theme_font_override("font", UITheme.hearth_title_font())
	_status = _label(column, "", 13, UITheme.CATALOG_INK)
	column.add_child(HSeparator.new())
	_label(column, "REQUIREMENTS", 11, UITheme.CATALOG_MUTED)
	_requirements = _label(column, "", 14, UITheme.CATALOG_INK)
	column.add_child(HSeparator.new())
	_label(column, "Experience stays with each profession.", 12, UITheme.CATALOG_MUTED)
	_experience = _label(right, "", 13, UITheme.HEARTH_MUTED)
	_progress = ProgressBar.new()
	UITheme.hearth_progress(_progress)
	right.add_child(_progress)
	_feedback = _label(right, "", 13, UITheme.SUCCESS)
	_feedback.hide()
	_promote = UITheme.make_button("", "", Vector2(0, 42))
	_promote.pressed.connect(_apply_promotion)
	right.add_child(_promote)
	_label(self, "Choose a profession to inspect its work, progression and requirements.", 12, UITheme.HEARTH_MUTED)
	get_viewport().size_changed.connect(func(): _fit.call_deferred())
	set_process(false)


func _build_node(key: String, entry: Dictionary) -> void:
	var button := Button.new()
	button.position = Vector2(entry.position[0], entry.position[1])
	button.size = Vector2(100, 78)
	button.toggle_mode = true
	button.tooltip_text = entry.summary
	_tree.add_child(button)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 7
	box.offset_bottom = -5
	box.add_theme_constant_override("separation", 4)
	button.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/icons/%s.svg" % entry.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(30, 24)
	icon.modulate = UITheme.HEARTH_COPPER
	box.add_child(icon)
	var title := _label(box, String(DwarfAssets.profession_definition(key).display_name), 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var state := _label(box, "", 11, UITheme.HEARTH_MUTED)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignore_mouse(box)
	button.pressed.connect(select_profession.bind(key))
	_nodes[key] = {"button": button, "state": state, "icon": icon}


func _draw_connections() -> void:
	for key: String in _entries:
		var parent: Variant = DwarfAssets.profession_definition(key).get("promotes_from")
		if parent == null: continue
		if not _nodes.has(parent): continue
		var from: Vector2 = _nodes[parent].button.position + Vector2(_nodes[parent].button.size.x * .5, 78)
		var to: Vector2 = _nodes[key].button.position + Vector2(_nodes[key].button.size.x * .5, 0)
		var halfway := (from.y + to.y) * .5
		var color := UITheme.HEARTH_COPPER if key == _selected else UITheme.HEARTH_EDGE
		_tree.draw_polyline(PackedVector2Array([from, Vector2(from.x, halfway), Vector2(to.x, halfway), to]), color, 2, true)


func begin_browsing(agent: DwarfAgent) -> void:
	clear_subject()
	_agent = agent
	_model = Portrait.create_model(_portrait, agent)
	_identity.text = agent.dwarf_name
	window.set_window_title("Professions · " + agent.dwarf_name, "")
	select_profession(agent.profession if agent.profession != PREFIX + "worker" else PREFIX + "miner")
	_left_scroll.scroll_vertical = 0
	_left_scroll.scroll_horizontal = 0
	set_process(true)
	_fit.call_deferred()


func clear_subject() -> void:
	set_process(false)
	_agent = null
	if is_instance_valid(_model): _model.free()
	_model = null
	if _portrait != null: _portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var dock := get_tree().get_first_node_in_group("command_dock")
		if dock != null and dock.is_action_menu_open(): return
		manager.close("professions")
		get_viewport().set_input_as_handled()


func select_profession(key: String) -> void:
	if not _entries.has(key): return
	_selected = key
	_feedback.text = ""
	_feedback.hide()
	refresh()
	_reveal_selection.call_deferred()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .35: return
	_elapsed = 0
	if not is_instance_valid(_agent) or not _agent in director.get_roster():
		manager.close("professions")
		return
	refresh()


func refresh() -> void:
	if not is_instance_valid(_agent): return
	var entry: Dictionary = _entries[_selected]
	var title := String(DwarfAssets.profession_definition(_selected).display_name)
	var enabled := DwarfAssets.profession_enabled(_selected)
	var current := _agent.profession == _selected
	var pending := _agent.promotion_pending()
	var selected_pending: bool = pending and _agent._equipment.pending_role == _selected
	var blocked: String = _agent._equipment.blocked_reason(_selected) if enabled and not current and not selected_pending else ""
	var level := DwarfAssets.profession_level(_selected, _agent.profession_experience)
	var count := maxi(0, int(_agent.profession_experience.get(_selected, 0)))
	_current.text = "Currently %s · One active profession" % DwarfAssets.profession_definition(_agent.profession).get("display_name", "Worker")
	_role_name.text = title
	_description.text = entry.summary
	_appointment.text = title if _compact else "%s\n%s" % [_agent.dwarf_name, title]
	_status.text = "CURRENT PROFESSION" if current else "AVAILABLE" if enabled else "PLANNED PROFESSION"
	if selected_pending: _status.text = "COLLECTING TOOL"
	elif not blocked.is_empty(): _status.text = "TOOL REQUIRED" if not _agent.is_sleeping() else "RESTING"
	_requirements.text = entry.availability
	var starter_tool := String(entry.get("starter_tool", ""))
	if not starter_tool.is_empty():
		var crafting := get_tree().get_first_node_in_group("crafting_manager")
		if crafting != null and is_instance_valid(crafting.items):
			var tool_name := String(crafting.items.get_item_def(starter_tool).get("display_name", "Starter tool"))
			var stock := Inventory.snapshot(crafting.items, crafting.furniture)
			var count_available := int(stock.get(starter_tool, {}).get("available", 0))
			_requirements.text = "%s · %d available\nWorker · crude workbench\n\n%s" % [tool_name, count_available, entry.availability]
			if selected_pending: _requirements.text = "Tool collection in progress.\n\n" + _requirements.text
			elif current: _requirements.text = "Equipped: %s\n\nSpecialist workshop and recipes are planned." % tool_name
	if not blocked.is_empty(): _requirements.text += "\n\n" + blocked
	var equipment_preview: Dictionary = DwarfAssets.profession_definition(_selected).get("equipment_preview", {})
	if equipment_preview.has("upgrade_status"):
		_requirements.text += "\n\nNext tool: %s\n%s\nSee the dwarf's Equipment view for the upgrade path." % [equipment_preview.upgrade_name, equipment_preview.upgrade_status]
	if _selected == PREFIX + "miner" and not bool(_agent.work_permissions.get("mine", true)):
		_requirements.text += "\n\nMining is switched off for this dwarf. Enable Mine in the colony Work view to let them dig."
	_rewards.text = "General colony work and basic crafting. Worker progression will arrive with a later milestone."
	_progress.visible = _selected == PREFIX + "miner"
	if _selected == PREFIX + "miner":
		var rewards: Array[String] = ["Lv 1  Mining focus"]
		for reward_level in range(2, 6):
			var value := DwarfAssets.mining_duration_multiplier(_selected, {_selected: DwarfAssets.experience_threshold(reward_level)})
			rewards.append("Lv %d  %d%% less digging time" % [reward_level, roundi((1.0 - value) * 100)])
		_rewards.text = "  ·  ".join(rewards) + "\nOne experience per completed block. Walking speed stays unchanged."
		var lower := DwarfAssets.experience_threshold(level) if level > 1 else 0
		var upper := DwarfAssets.experience_threshold(level + 1) if level < 5 else count
		_experience.text = "Retained level %d · %d blocks mined\n%s" % [level, count, "%d more blocks to level %d" % [upper - count, level + 1] if level < 5 else "Master Miner · Maximum level"]
		_progress.max_value = maxi(1, upper - lower)
		_progress.value = count - lower if level < 5 else _progress.max_value
	else:
		_experience.text = "No experience required." if enabled else "Level rewards will be defined with this profession's gameplay."
		if not enabled: _rewards.text = "FUTURE CAREER\nThis role can be explored here, but cannot be assigned yet."
	if _selected == PREFIX + "carpenter":
		_rewards.text = "Equips a real carpentry kit. General hauling, gathering, mining and building remain available. Specialist crafting and experience are planned. No tool speed bonus yet."
	_promote.disabled = (current and not pending) or not enabled or not blocked.is_empty() or not _agent in director.get_roster()
	_promote.text = "Current profession" if current else "Not yet available" if not enabled else "Return to Worker" if _selected == PREFIX + "worker" else ("Resume %s · Lv %d" % [title, level] if count > 0 else "Promote to " + title)
	if selected_pending or (current and pending): _promote.text = "Cancel promotion"
	elif not blocked.is_empty(): _promote.text = "Waiting for tool" if not _agent.is_sleeping() else "Dwarf is sleeping"
	_feedback.text = _agent._equipment.message
	_feedback.visible = not _feedback.text.is_empty()
	for key: String in _nodes:
		var node: Dictionary = _nodes[key]
		var usable := DwarfAssets.profession_enabled(key)
		node.state.text = "Current" if key == _agent.profession else "Available" if usable else "Planned"
		if pending and key == _agent._equipment.pending_role: node.state.text = "Collecting tool"
		node.state.add_theme_color_override("font_color", UITheme.SUCCESS if usable else UITheme.HEARTH_MUTED)
		node.icon.modulate = UITheme.HEARTH_COPPER if usable or key == _selected else UITheme.HEARTH_MUTED
		node.button.set_pressed_no_signal(key == _selected)
	_tree.queue_redraw()


func _apply_promotion() -> void:
	if not is_instance_valid(_agent) or not _agent in director.get_roster(): return
	if _agent.promotion_pending() and _agent._equipment.pending_role == _selected:
		_agent._equipment.cancel()
	else:
		_agent.change_profession(_selected)
	refresh()
	director._refresh_window()


func _fit() -> void:
	if window == null: return
	var viewport := get_viewport_rect().size
	_compact = viewport.y < 650
	_portrait_texture.custom_minimum_size.y = 40 if _compact else 60
	_paper_heading.visible = not _compact
	_paper_column.add_theme_constant_override("separation", 6 if _compact else 12)
	_paper.add_theme_stylebox_override("panel", UITheme.style(UITheme.CATALOG_PAPER, UITheme.CATALOG_GOLD, 2, 3, 12 if _compact else 18, 12 if _compact else 18))
	_appointment.add_theme_font_size_override("font_size", 19 if _compact else 23)
	custom_minimum_size.x = minf(1080, viewport.x - 64)
	_body.custom_minimum_size.y = clampf(viewport.y - (280 if _compact else 294), 236, 600)
	_detail_scroll.custom_minimum_size.y = 64 if _compact else 150
	var narrow := viewport.x < 1150
	_tree.custom_minimum_size.x = 580 if narrow else 656
	for key: String in _entries:
		var entry: Dictionary = _entries[key]
		_nodes[key].button.position = Vector2(float(entry.position[0]) * (.884 if narrow else 1.0), entry.position[1])
		_nodes[key].button.size.x = 90 if narrow else 100
	window.reset_size()
	window.position.y = maxf(8, minf(window.position.y, viewport.y - window.size.y - 104))
	window.clamp_to_viewport()
	refresh()
	_reveal_selection.call_deferred()
	_settle_window.call_deferred()


func _settle_window() -> void:
	# Font sizes and scroll minimums settle after container layout. Shrink
	# again then, so an initial compact opening cannot retain its old height.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not is_visible_in_tree() or window == null: return
	window.reset_size()
	var viewport := get_viewport_rect().size
	window.position.y = maxf(8, minf(window.position.y, viewport.y - window.size.y - 104))
	window.clamp_to_viewport()


func _reveal_selection() -> void:
	# Layout and scrollbar limits settle over two frames. Only selection or a
	# viewport change scrolls the map; normal experience refreshes never do.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not is_visible_in_tree() or not _nodes.has(_selected): return
	var button: Button = _nodes[_selected].button
	var top := int(button.position.y)
	var bottom := top + int(button.size.y)
	var visible_height := int(_left_scroll.size.y) - 12
	if top < _left_scroll.scroll_vertical:
		_left_scroll.scroll_vertical = maxi(0, top - 8)
	elif bottom > _left_scroll.scroll_vertical + visible_height:
		_left_scroll.scroll_vertical = maxi(0, bottom - visible_height)


func _label(parent: Control, text: String, size: int, color := UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control: _ignore_mouse(child)
