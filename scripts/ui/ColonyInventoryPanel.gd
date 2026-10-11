extends VBoxContainer

## Presentation of physical goods. Storage owners and ItemDropManager remain
## authoritative; the browsing list is stable until the next visit.
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
signal locate_requested(item_key: String, storage_only: bool)

var window: UIWindow
var controller: FurniturePlacementController
var items: ItemDropManager
var selected_key := ""
var category := "all"
var _stock := {}
var _entries := {}
var _browse_keys: Array[String] = []
var _tiles := {}
var _tabs := {}
var _categories: Array = []
var _category_tabs: HFlowContainer
var _category_select: OptionButton
var _count: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _empty: Label
var _body: HBoxContainer
var _paper: PanelContainer
var _detail_scroll: ScrollContainer
var _image: TextureRect
var _name: Label
var _description: Label
var _detail_contents: VBoxContainer
var _values := {}
var _locate: Button
var _inspect: Button
var _dock_top := 600.0
var _refresh_queued := false


func _ready() -> void:
	UITheme.apply_surface(self)
	add_theme_constant_override("separation", 0)
	_categories = UIRegistry.get_inventory_catalog().get("categories", [])
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(_margin(header, 12, 8))
	_category_tabs = HFlowContainer.new()
	_category_tabs.add_theme_constant_override("h_separation", 4)
	header.add_child(_category_tabs)
	_category_select = OptionButton.new()
	_category_select.item_selected.connect(func(index: int):
		_set_category(String(_category_select.get_item_metadata(index))))
	for entry: Dictionary in _categories:
		_category_select.add_item(entry.label)
		_category_select.set_item_metadata(_category_select.item_count - 1, entry.id)
		var tab := UITheme.make_button(entry.label, "", Vector2(0, 28))
		tab.toggle_mode = true
		tab.pressed.connect(_set_category.bind(entry.id))
		_category_tabs.add_child(tab)
		_tabs[entry.id] = tab
	var row := HBoxContainer.new()
	header.add_child(row)
	row.add_child(_category_select)
	_count = _label("Supplies across your colony", 13)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_count)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	list.add_child(_margin(_grid, 10, 8))
	_empty = _label("Your stockroom is quiet.\nGather resources or bring finished furniture into the colony.", 16)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_margin(_empty, 18, 14))
	_paper = PanelContainer.new()
	_paper.custom_minimum_size.x = 270
	_paper.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_body.add_child(_paper)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	_paper.add_child(detail)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.mouse_force_pass_scroll_events = false
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_detail_scroll)
	var contents := VBoxContainer.new()
	_detail_contents = contents
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 4)
	_detail_scroll.add_child(contents)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.custom_minimum_size.y = 96
	contents.add_child(_image)
	_name = _label("Colony supplies", 23, true)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(_name)
	for state: String in ["Total", "Stored", "Loose", "Carried", "Equipped", "Reserved", "Disallowed", "Available"]:
		var line := HBoxContainer.new()
		contents.add_child(line)
		var caption := _label(state, 14, true)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(caption)
		var value := _label("—", 17, true)
		line.add_child(value)
		_values[state] = value
		if state == "Total": line.tooltip_text = "Stored + Loose + Carried + Equipped. Installed furniture is already in use and excluded."
		if state == "Reserved":
			line.tooltip_text = "Already assigned to a dwarf or an order, including equipped tools. Included in Total, not extra goods."
		if state == "Available": line.tooltip_text = "Unassigned goods available for new orders."
	_description = _label("Select an item to see where it is kept.", 13, true)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(_description)
	var actions := HBoxContainer.new()
	detail.add_child(actions)
	_locate = UITheme.make_button("Locate", "Find a stored, loose or carried item", Vector2(0, 32))
	_locate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locate.pressed.connect(func(): locate_requested.emit(selected_key, false))
	actions.add_child(_locate)
	_inspect = UITheme.make_button("Inspect storage", "Open a stockpile or container holding this item", Vector2(0, 32))
	_inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect.pressed.connect(func(): locate_requested.emit(selected_key, true))
	actions.add_child(_inspect)
	StockpileManager.stockpile_changed.connect(func(_key: String, _delta: int): _queue_refresh())
	_bind_items()


func bind_controller(value: FurniturePlacementController) -> void:
	controller = value
	controller.catalog_changed.connect(_queue_refresh)
	_entries.clear()
	_queue_refresh()


func _bind_items() -> void:
	if is_instance_valid(items): return
	items = get_tree().get_first_node_in_group("item_drop_manager") as ItemDropManager
	if items != null: items.loose_items_changed.connect(_queue_refresh)


func begin_browsing() -> void:
	_bind_items()
	_browse_keys.clear()
	_scroll.scroll_vertical = 0
	refresh()
	_fit.call_deferred()


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if window == null or not window.visible or not is_instance_valid(items): return
	_stock = Inventory.snapshot(items, controller)
	var newcomers: Array[String] = []
	for key: String in _stock:
		if not key in _browse_keys: newcomers.append(key)
	newcomers.sort_custom(func(a: String, b: String):
		var ea := _entry(a); var eb := _entry(b)
		if ea.category_order != eb.category_order: return ea.category_order < eb.category_order
		return String(ea.label).naturalnocasecmp_to(eb.label) < 0)
	for key in newcomers:
		_browse_keys.append(key)
		if not _tiles.has(key): _build_tile(key)
	for index in range(_browse_keys.size()):
		var button: Button = _tiles[_browse_keys[index]].button
		if button.get_index() != index: _grid.move_child(button, index)
	var visible_keys: Array[String] = []
	for key: String in _tiles:
		var tile: Dictionary = _tiles[key]
		var entry := _entry(key)
		var count := int(_stock.get(key, {}).get("total", 0))
		tile.button.visible = key in _browse_keys and (category == "all" or entry.category == category)
		if tile.button.visible: visible_keys.append(key)
		tile.count.text = str(count)
		tile.image.modulate.a = 1.0 if count > 0 else .4
		tile.button.tooltip_text = "%s · %d in colony" % [entry.label, count]
	if not selected_key in visible_keys:
		selected_key = visible_keys[0] if not visible_keys.is_empty() else ""
	for key: String in _tiles: _tiles[key].button.set_pressed_no_signal(key == selected_key)
	for key: String in _tabs: _tabs[key].set_pressed_no_signal(key == category)
	for index in range(_category_select.item_count):
		if _category_select.get_item_metadata(index) == category: _category_select.select(index)
	_empty.visible = visible_keys.is_empty()
	_empty.text = "Your stockroom is quiet.\nGather resources or bring finished furniture into the colony." if category == "all" else "No supplies in this category yet."
	_count.text = "%d item types · Counts update as dwarves work" % visible_keys.size()
	_refresh_detail()
	# No refit, sorting of existing items, scroll reset or window movement here.


func _entry(key: String) -> Dictionary:
	if _entries.has(key): return _entries[key]
	var definition := items.get_item_def(key)
	var entry := {"label": String(definition.get("display_name", key)), "category": "other", "description": String(definition.get("description", "")), "texture": Inventory.thumbnail_path(key)}
	for group: Dictionary in _categories:
		for tag: String in group.get("tags", []):
			if tag in definition.get("material_tags", []): entry.category = group.id; break
		if entry.category != "other": break
	if is_instance_valid(controller):
		for design: Dictionary in UIRegistry.get_place_catalog().get("items", []):
			var furniture_def: Dictionary = controller.get_defs().get(design.key, {})
			if furniture_def.get("item_key", "") != key: continue
			entry.label = design.label
			entry.category = UIRegistry.get_inventory_catalog().get("furniture_categories", {}).get(design.category, "furniture")
			entry.texture = "res://assets/ui/furniture/%s.png" % String(design.key).get_slice(":", 2)
			break
	if int(definition.get("crate_capacity", 1)) > 1:
		entry.description += " Counts show contents, not the number of crates."
	entry.category_order = _categories.size()
	for index in range(_categories.size()):
		if _categories[index].id == entry.category: entry.category_order = index; break
	_entries[key] = entry
	return entry


func _build_tile(key: String) -> void:
	var entry := _entry(key)
	var button := Button.new()
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 104 if get_viewport_rect().size.y < 650 else 144)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, UITheme.catalog_item_style(state != "normal"))
	_grid.add_child(button)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6; column.offset_right = -6
	column.offset_top = 7; column.offset_bottom = -6
	button.add_child(column)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.texture = load(entry.texture) if ResourceLoader.exists(entry.texture) else load("res://assets/ui/icons/stocks.svg")
	column.add_child(image)
	var caption := _label(entry.label, 13)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.y = 34
	column.add_child(caption)
	var count := _label("0", 14)
	count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	count.position = Vector2(-48, 6)
	count.size = Vector2(42, 22)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_stylebox_override("normal", UITheme.style(UITheme.TRACK_BG, Color.TRANSPARENT, 0, 1, 4, 0))
	button.add_child(count)
	_ignore_mouse(column)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.pressed.connect(func():
		selected_key = key; _detail_scroll.scroll_vertical = 0; refresh())
	_tiles[key] = {"button": button, "image": image, "count": count}


func _refresh_detail() -> void:
	var row: Dictionary = _stock.get(selected_key, {})
	var entry := _entry(selected_key) if not selected_key.is_empty() else {}
	_name.text = entry.get("label", "Colony supplies")
	_description.text = entry.get("description", "Select an item to see where it is kept.")
	_image.texture = _tiles[selected_key].image.texture if _tiles.has(selected_key) else null
	for state: String in _values: _values[state].text = str(row.get(state.to_lower(), 0))
	_locate.disabled = int(row.get("total", 0)) <= 0
	_inspect.disabled = int(row.get("stored", 0)) <= 0


func _set_category(value: String) -> void:
	category = value
	_scroll.scroll_vertical = 0
	refresh()


func fit_above_dock(top: float) -> void:
	_dock_top = top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	var compact := viewport.y < 650
	_category_tabs.visible = not compact
	_category_select.visible = compact
	_count.visible = not compact
	custom_minimum_size.x = minf(820, viewport.x - 48)
	_image.custom_minimum_size.y = 44 if compact else 96
	_name.add_theme_font_size_override("font_size", 19 if compact else 23)
	for value: Label in _values.values(): value.add_theme_font_size_override("font_size", 14 if compact else 17)
	_detail_contents.add_theme_constant_override("separation", 3 if compact else 4)
	for tile: Dictionary in _tiles.values(): tile.button.custom_minimum_size.y = 104 if compact else 144
	_body.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _body.get_combined_minimum_size().y
	_body.custom_minimum_size.y = maxf(180, minf(620, _dock_top - 84) - chrome)
	window.reset_size()
	window.position.y = minf(window.position.y, _dock_top - 8 - window.size.y)
	window.clamp_to_viewport()


func _label(text: String, font_size: int, paper: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 21: UITheme.apply_title(label, font_size)
	if paper: label.add_theme_color_override("font_color", UITheme.CATALOG_INK)
	return label


func _margin(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, horizontal)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, vertical)
	margin.add_child(child)
	return margin


func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
