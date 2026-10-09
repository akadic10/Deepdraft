class_name FurniturePlacePanel
extends VBoxContainer

## Presentation only. Inventory, reservations, validity and delivery stay with
## FurniturePlacementController; movable chrome belongs to UIWindowManager.
signal place_requested(furniture_key: String)

var controller: FurniturePlacementController
var window: UIWindow
var selected_key := ""
var category := "all"
var show_all := false
var _entries: Array = []
var _stock := {}
## Keep browsing targets fixed until the player reopens the catalog. Newly
## available designs append; a temporarily carried/claimed item never removes
## a tile or moves the items after it under the pointer.
var _browse_keys: Array[String] = []
var _tiles := {}
var _tabs := {}
var _category_tabs: HFlowContainer
var _category_select: OptionButton
var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: VBoxContainer
var _all_toggle: CheckBox
var _count: Label
var _name: Label
var _spec: Label
var _note: Label
var _values := {}
var _place: Button
var _done: Button
var _undo: Button
var _hint: Label
var _paper: PanelContainer
var _detail: VBoxContainer
var _undo_ids: Array[int] = []
var _dock_top := 600.0


func _ready() -> void:
	UITheme.apply_surface(self)
	add_theme_constant_override("separation", 0)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	add_child(_margin(top, 12, 8))
	var tabs := HFlowContainer.new()
	_category_tabs = tabs
	tabs.add_theme_constant_override("h_separation", 3)
	tabs.add_theme_constant_override("v_separation", 3)
	top.add_child(tabs)
	var catalog := UIRegistry.get_place_catalog()
	_entries = catalog.get("items", [])
	_category_select = OptionButton.new()
	_category_select.custom_minimum_size = Vector2(118, 28)
	_category_select.add_theme_font_size_override("font_size", 12)
	_category_select.item_selected.connect(func(index: int):
		category = String(_category_select.get_item_metadata(index)); refresh(); _fit.call_deferred())
	for entry: Dictionary in catalog.get("categories", []):
		_category_select.add_item(entry.label)
		_category_select.set_item_metadata(_category_select.item_count - 1, entry.id)
		var tab := UITheme.make_button(entry.label, "", Vector2(0, 26))
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_ALL
		tab.add_theme_font_size_override("font_size", 13)
		tab.pressed.connect(func(): category = entry.id; refresh(); _fit.call_deferred())
		tabs.add_child(tab)
		_tabs[entry.id] = tab
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_child(_category_select)
	_count = _label("", 12)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_count)
	_all_toggle = CheckBox.new()
	_all_toggle.text = "Show all designs"
	_all_toggle.add_theme_font_size_override("font_size", 12)
	_all_toggle.toggled.connect(func(value: bool): show_all = value; refresh(); _fit.call_deferred())
	row.add_child(_all_toggle)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Reserve the scrollbar gutter even before the list overflows; adding a
	# design must not resize every existing tile horizontally.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.mouse_force_pass_scroll_events = false
	add_child(_scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(items)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	items.add_child(_margin(_grid, 10, 8))
	_empty = VBoxContainer.new()
	_empty.add_child(_label("Nothing ready to place", 17, true))
	var explanation := _label("Finished furniture, uprooted plants and cuttings appear here when available.", 13)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(explanation)
	var browse := UITheme.make_button("Browse all designs", "", Vector2(0, 30))
	browse.pressed.connect(func(): _all_toggle.button_pressed = true)
	_empty.add_child(browse)
	items.add_child(_margin(_empty, 14, 8))
	var paper := PanelContainer.new()
	_paper = paper
	paper.hide()
	paper.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	add_child(paper)
	var detail := VBoxContainer.new()
	_detail = detail
	detail.add_theme_constant_override("separation", 5)
	paper.add_child(detail)
	_name = _label("Select an item", 19, true)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_color_override("font_color", UITheme.CATALOG_INK)
	detail.add_child(_name)
	_spec = _label("", 12)
	_spec.add_theme_color_override("font_color", UITheme.CATALOG_MUTED)
	_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_spec)
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 8)
	detail.add_child(counts)
	for state: String in ["Available", "Reserved", "Crafting"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		counts.add_child(column)
		var value := _label("—", 21, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color", UITheme.CATALOG_INK)
		column.add_child(value)
		_values[state] = value
		var caption := _label(state, 12)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color", UITheme.CATALOG_MUTED)
		column.add_child(caption)
		if state == "Crafting": column.tooltip_text = "Items requested in the Worker crafting queue."
	_note = _label("", 12)
	_note.add_theme_color_override("font_color", UITheme.CATALOG_MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_note)
	_place = Button.new()
	UITheme.apply_catalog_primary(_place)
	_place.pressed.connect(func(): if not selected_key.is_empty(): place_requested.emit(selected_key))
	var actions := HBoxContainer.new()
	detail.add_child(actions)
	_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_place)
	_done = UITheme.make_button("Done", "Finish placing (Esc)", Vector2(0, 28))
	_done.pressed.connect(func(): controller.deactivate())
	actions.add_child(_done)
	_undo = UITheme.make_button("Undo last", "Cancel your last unfinished placement", Vector2(0, 28))
	_undo.pressed.connect(_undo_last)
	actions.add_child(_undo)
	_hint = _label("R rotates · Esc finishes", 12)
	_hint.add_theme_color_override("font_color", UITheme.CATALOG_MUTED)
	detail.add_child(_hint)


func bind_controller(value: FurniturePlacementController) -> void:
	controller = value
	for entry: Dictionary in _entries:
		if controller.get_defs().has(entry.key): _build_tile(entry)
	controller.catalog_changed.connect(refresh)
	controller.tool_active_changed.connect(func(_active: bool): refresh())
	controller.ghost_placed.connect(func(id: int):
		if window != null and window.visible and controller.is_active(): _undo_ids.append(id))
	refresh()


func _build_tile(entry: Dictionary) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", UITheme.catalog_item_style())
	button.add_theme_stylebox_override("hover", UITheme.catalog_item_style(true))
	button.add_theme_stylebox_override("pressed", UITheme.catalog_item_style(true))
	button.add_theme_stylebox_override("hover_pressed", UITheme.catalog_item_style(true))
	_grid.add_child(button)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6; column.offset_right = -6
	column.offset_top = 5; column.offset_bottom = -5
	column.add_theme_constant_override("separation", 0)
	button.add_child(column)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var path := "res://assets/ui/furniture/%s.png" % String(entry.key).get_slice(":", 2)
	if ResourceLoader.exists(path): image.texture = load(path)
	column.add_child(image)
	var caption := _label(entry.label, 12)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.y = 32
	column.add_child(caption)
	var count := _label("0", 12)
	count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	count.position = Vector2(-32, 6)
	count.size = Vector2(26, 20)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_stylebox_override("normal", UITheme.style(UITheme.TRACK_BG, Color.TRANSPARENT, 0, 1, 4, 0))
	button.add_child(count)
	var check := _label("✓", 13)
	check.position = Vector2(7, 5)
	check.add_theme_color_override("font_color", UITheme.CATALOG_GOLD)
	button.add_child(check)
	_ignore_mouse(column)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.pressed.connect(_select.bind(entry.key))
	_tiles[entry.key] = {"button": button, "image": image, "count": count, "check": check}


func _select(key: String) -> void:
	selected_key = key
	# A tile is the placement action. Use current stock, since a hauler may
	# reserve the last item before the deferred catalog refresh reaches us.
	var available := int(controller.get_catalog_stock().get(key, {}).get("available", 0))
	if available > 0:
		# Re-clicking the active design should keep the player's rotation.
		if controller.active_furniture_key() != key: place_requested.emit(key)
	else:
		controller.deactivate()
	refresh()
	_fit.call_deferred()


func begin_browsing() -> void:
	_browse_keys.clear()
	_scroll.scroll_vertical = 0
	refresh()
	_fit.call_deferred()


func refresh() -> void:
	if controller == null or _grid == null: return
	if window != null and not window.visible: return
	_stock = controller.get_catalog_stock()
	for entry: Dictionary in _entries:
		if _tiles.has(entry.key) and not entry.key in _browse_keys:
			var counts: Dictionary = _stock[entry.key]
			if counts.available > 0 or counts.reserved > 0: _browse_keys.append(entry.key)
	# Filter/order changes are deliberate; stock updates only append new designs.
	# Hidden controls can stay after the browsing list without affecting the grid.
	var order: Array = [] if show_all else _browse_keys.duplicate()
	for entry: Dictionary in _entries:
		if _tiles.has(entry.key) and not entry.key in order: order.append(entry.key)
	for index in range(order.size()):
		var button: Button = _tiles[order[index]].button
		if button.get_index() != index: _grid.move_child(button, index)
	var visible_keys: Array[String] = []
	for entry: Dictionary in _entries:
		if not _tiles.has(entry.key): continue
		var tile: Dictionary = _tiles[entry.key]
		var counts: Dictionary = _stock[entry.key]
		tile.button.visible = (category == "all" or category == entry.category) \
			and (show_all or entry.key in _browse_keys)
		if tile.button.visible: visible_keys.append(entry.key)
		tile.count.text = str(counts.available)
		tile.image.modulate = Color(1, 1, 1, 1 if counts.available > 0 else .45)
		tile.button.tooltip_text = "%s\n%d available · %d reserved for placement" % [controller.get_defs()[entry.key].display_name, counts.available, counts.reserved]
	var previous_selection := selected_key
	if not selected_key in visible_keys:
		selected_key = ""
		for key: String in visible_keys:
			if selected_key.is_empty() or int(_stock[key].available) > 0:
				selected_key = key
				if int(_stock[key].available) > 0: break
	for key: String in _tiles:
		_tiles[key].button.set_pressed_no_signal(selected_key == key)
		_tiles[key].check.visible = selected_key == key
	var has_selection := not selected_key.is_empty()
	if _paper.visible != has_selection:
		_paper.visible = has_selection
		_fit.call_deferred() # only refit when the detail area appears/disappears
	if previous_selection != selected_key and controller.is_active():
		controller.deactivate() # a filtered-out design must not keep placing
	for key: String in _tabs: _tabs[key].set_pressed_no_signal(key == category)
	for index in range(_category_select.item_count):
		if _category_select.get_item_metadata(index) == category: _category_select.select(index)
	_count.text = "%d designs" % visible_keys.size()
	_empty.visible = visible_keys.is_empty()
	_grid.visible = not visible_keys.is_empty()
	_undo_ids = _undo_ids.filter(func(id: int): return controller.has_pending_placement(id))
	_undo.disabled = _undo_ids.is_empty()
	_done.disabled = not controller.is_active()
	if selected_key.is_empty():
		_place.disabled = true
		return
	var definition: Dictionary = controller.get_defs()[selected_key]
	var stock: Dictionary = _stock[selected_key]
	_name.text = String(definition.display_name)
	var footprint: Dictionary = definition.get("footprint", {})
	_spec.text = "%d × %d" % [int(footprint.get("width", 1)), int(footprint.get("depth", 1))]
	if definition.has("seating"):
		var seating: Dictionary = definition.seating
		_spec.text += " · %d chair%s" % [int(seating.get("max_chairs", seating.get("slots", []).size())), "" if int(seating.get("max_chairs", 0)) == 1 else "s"]
	elif selected_key == "base:furniture:wooden_chair": _spec.text += " · Snaps to tables"
	elif String(definition.placement) == "wall": _spec.text += " · Wall mounted"
	_values.Available.text = str(stock.available)
	_values.Reserved.text = str(stock.reserved)
	var crafting := get_tree().get_first_node_in_group("crafting_manager")
	_values.Crafting.text = str(crafting.crafting_count(String(definition.item_key))) if crafting != null else "0"
	_place.disabled = stock.available <= 0
	var placing := controller.active_furniture_key() == selected_key
	_place.text = "Placing · %d available" % stock.available if placing else "Place item" if stock.available > 0 else "None available"
	_note.text = "Reserved items are awaiting delivery." if stock.reserved > 0 else "Finished furniture, ready for a home." if stock.available > 0 else "No finished items available."
	if bool(definition.get("plant", false)):
		var cutting := bool(definition.get("from_cutting", false))
		_spec.text = "3 × 3 planting area · Open sky"
		if cutting:
			var plant := SurfaceDetailRegistry.get_definition(String(definition.plant_definition))
			_note.text = "Uses 1 cutting. Matures after %.1f growth days; growth pauses in winter." % float(plant.growth_days)
			_place.text = "Plant cutting" if stock.available > 0 else "No cuttings available"
		else:
			_note.text = "Replant this whole plant. Its shape and seasonal state are preserved." if stock.available > 0 else "Uproot a plant of this type to place it here."
			_place.text = "Replant" if stock.available > 0 else "No uprooted plants"
	_hint.text = "Click to place repeatedly · R rotates · Esc finishes" if placing else "Click an available item to start placing."
	if String(definition.placement) == "ladder":
		_spec.text = "%d blocks per section" % int(definition.ladder.section_height)
		_note.text = "Aim at a cliff face. The preview shows the full height and section cost before you place it."
		_place.text = "Place ladder" if stock.available > 0 else "Craft ladder sections first"
		_hint.text = "Aim at a cliff or its edge · R rotates · Esc finishes" if placing else "Craft sections at a crude workbench."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Inventory wakes change counts/availability only. Refitting here resets
	# scroll limits and can clamp a player-positioned window on every pickup.


func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	var compact := viewport.y < 650
	_category_tabs.visible = not compact
	_category_select.visible = compact
	_count.visible = not compact
	_hint.visible = not compact
	_paper.add_theme_stylebox_override("panel", UITheme.catalog_paper_style(compact))
	_detail.add_theme_constant_override("separation", 3 if compact else 5)
	_name.add_theme_font_size_override("font_size", 17 if compact else 19)
	for value: Label in _values.values(): value.add_theme_font_size_override("font_size", 18 if compact else 21)
	custom_minimum_size.x = minf(400, viewport.x - 48)
	for tile: Dictionary in _tiles.values():
		tile.button.custom_minimum_size = Vector2(0, 96 if compact else 130)
	_scroll.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(112, minf(710, _dock_top - 84) - chrome)
	window.reset_size()
	window.clamp_to_viewport()


func _undo_last() -> void:
	while not _undo_ids.is_empty():
		var id: int = _undo_ids.pop_back()
		if controller.has_pending_placement(id):
			controller.cancel_ghost(id)
			break
	refresh()


func _label(text: String, font_size: int, title: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if title: UITheme.apply_title(label, font_size)
	return label


func _margin(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	margin.add_child(child)
	return margin


func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
