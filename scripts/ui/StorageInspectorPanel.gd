extends VBoxContainer

## Shared presentation for ground storage, chests, barrels and shelves.
## Changes go directly to the selected storage owner; nothing waits for Apply.
signal action_requested(action_id: String)

const Inventory = preload("res://scripts/components/ColonyInventory.gd")
var window: UIWindow
var storage: StorageComponent
var category := "stockpile_stone"
var info_label: Label
var _kind: Label
var _capacity: ProgressBar
var _tabs: Array[Button] = []
var _filters: VBoxContainer
var _bulk: HBoxContainer
var _all: Button
var _none: Button
var _category: OptionButton
var _group: Button
var _scroll: ScrollContainer
var _grid: GridContainer
var _contents: VBoxContainer
var _summary: Label
var _waiting: Label
var _actions: HBoxContainer
var _action_data: Array = []
var _tiles: Dictionary = {}
var _groups: Array[Dictionary] = []
var _keys: Array[String] = []
var _refresh_queued := false
var _shown_tab := 0


func _ready() -> void:
	UITheme.apply_surface(self)
	custom_minimum_size.x = 390
	add_theme_constant_override("separation", 8)
	_kind = _label(self, "GROUND STORAGE", 11, UITheme.HEARTH_COPPER)
	info_label = _label(self, "", 14)
	_capacity = ProgressBar.new()
	_capacity.show_percentage = false
	_capacity.custom_minimum_size.y = 5
	add_child(_capacity)
	var tabs := HBoxContainer.new()
	add_child(tabs)
	for caption in ["Filters", "Contents"]:
		var tab := _button(tabs, caption)
		tab.toggle_mode = true
		tab.pressed.connect(_show_tab.bind(_tabs.size()))
		_tabs.append(tab)
	_filters = VBoxContainer.new()
	_filters.add_theme_constant_override("separation", 8)
	add_child(_filters)
	_bulk = HBoxContainer.new()
	_filters.add_child(_bulk)
	_all = _button(_bulk, "Accept all goods")
	_all.pressed.connect(func(): if storage != null: storage.set_all_accepted(true))
	_none = _button(_bulk, "Clear all filters")
	_none.pressed.connect(func(): if storage != null: storage.set_all_accepted(false))
	_category = OptionButton.new()
	_category.focus_mode = Control.FOCUS_ALL
	_category.custom_minimum_size.y = 30
	_category.item_selected.connect(func(index: int): set_category(String(_groups[index].tag)))
	_filters.add_child(_category)
	_group = _button(_filters, "")
	_group.toggle_mode = true
	_group.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_group.pressed.connect(_toggle_category)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.custom_minimum_size.y = 220
	add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	pages.add_child(_grid)
	_contents = VBoxContainer.new()
	_contents.add_theme_constant_override("separation", 8)
	pages.add_child(_contents)
	_summary = _label(self, "", 13)
	_summary.max_lines_visible = 2
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_waiting = _label(self, "", 12, UITheme.HEARTH_COPPER)
	_actions = HBoxContainer.new()
	add_child(_actions)
	_groups = UIRegistry.get_storage_categories()
	for entry in _groups: _category.add_item(entry.label)
	get_viewport().size_changed.connect(_fit)
	visibility_changed.connect(func(): if is_visible_in_tree(): _queue_refresh())
	_show_tab(0)


func show_storage(value: StorageComponent, actions: Array = []) -> void:
	if storage == value and actions == _action_data: return
	if storage != value:
		clear_subject()
		storage = value
		storage.changed.connect(_queue_refresh)
		_build_tiles()
		_show_tab(0)
	if actions != _action_data:
		_action_data = actions.duplicate(true)
		_clear_children(_actions)
		for action: Dictionary in actions:
			var button := _button(_actions, String(action.text))
			UITheme.apply_button_variant(button, String(action.get("variant", "")))
			button.pressed.connect(func(): action_requested.emit(String(action.id)))
	refresh()


func clear_subject() -> void:
	if storage != null and storage.changed.is_connected(_queue_refresh):
		storage.changed.disconnect(_queue_refresh)
	storage = null


func _exit_tree() -> void:
	clear_subject()


func _build_tiles() -> void:
	_clear_children(_grid)
	_tiles.clear()
	_keys.clear()
	if not is_instance_valid(storage.drop_manager): return
	var definitions: Dictionary = storage.drop_manager.get_item_defs()
	_keys.assign(definitions.keys())
	_keys.sort_custom(func(a: String, b: String): return _item_name(a).naturalnocasecmp_to(_item_name(b)) < 0)
	for key in _keys:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(100, 96)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s\nAllow this exact item type. Changes take effect immediately." % _item_name(key)
		button.pressed.connect(func(): if storage != null: storage.set_item_accepted(key, not storage.accepts_key(key)))
		_grid.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 6)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		button.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		margin.add_child(box)
		var top := HBoxContainer.new()
		box.add_child(top)
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.y = 47
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path := Inventory.thumbnail_path(key)
		if not ResourceLoader.exists(path):
			path = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)
		image.texture = load(path) if ResourceLoader.exists(path) else load("res://assets/ui/icons/stocks.svg")
		top.add_child(image)
		var check := _label(top, "", 16, UITheme.HEARTH_COPPER)
		check.custom_minimum_size.x = 16
		check.autowrap_mode = TextServer.AUTOWRAP_OFF
		var caption := _label(box, _item_name(key), 12)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.max_lines_visible = 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_ignore_mouse(margin)
		_tiles[key] = {"button": button, "check": check}


func set_category(tag: String) -> void:
	category = tag
	_scroll.scroll_vertical = 0
	refresh()


func _category_keys(tag: String) -> Array[String]:
	var result: Array[String] = []
	for key in _keys:
		if tag in storage.drop_manager.get_item_def(key).get("material_tags", []): result.append(key)
	return result


func _toggle_category() -> void:
	if storage == null: return
	var keys := _category_keys(category)
	var all_selected := not keys.is_empty()
	for key in keys:
		if not storage.accepts_key(key): all_selected = false
	storage.set_category_accepted(category, not all_selected)


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if storage == null or not is_instance_valid(storage.drop_manager): return
	var is_ground := storage is StockpileZoneComponent
	_kind.text = "GROUND STORAGE" if is_ground else "CONTAINER STORAGE"
	if not is_ground and storage.suspended: _kind.text = "UNINSTALL PENDING · DELIVERIES PAUSED"
	var held := storage.contents()
	var goods := 0
	var rejected := 0
	for key: String in held:
		goods += int(held[key])
		if not storage.accepts_key(key): rejected += int(held[key])
	info_label.text = "%d / %d %s used   ·   Goods stored: %d" % [storage.stored_entries().size(), storage.storage_capacity(), "cells" if is_ground else "slots", goods]
	_capacity.max_value = maxi(1, storage.storage_capacity())
	_capacity.value = storage.stored_entries().size()
	_capacity.tooltip_text = "Produce crates hold several goods in one cell or slot."
	var selected_count := 0
	for key in _keys:
		var selected := storage.accepts_key(key)
		if selected: selected_count += 1
		var tile: Dictionary = _tiles[key]
		tile.button.visible = category in storage.drop_manager.get_item_def(key).get("material_tags", [])
		tile.button.set_pressed_no_signal(selected)
		tile.button.add_theme_stylebox_override("normal", UITheme.storage_item_style(selected))
		tile.button.add_theme_stylebox_override("pressed", UITheme.storage_item_style(true))
		tile.button.add_theme_stylebox_override("hover_pressed", UITheme.storage_item_style(true))
		tile.check.text = "✓" if selected else "□"
	var summary: Array[String] = []
	for index in range(_groups.size()):
		var group: Dictionary = _groups[index]
		var keys := _category_keys(group.tag)
		var count := 0
		for key in keys:
			if storage.accepts_key(key): count += 1
		_category.set_item_text(index, "%s  ·  %d / %d" % [group.label, count, keys.size()])
		if group.tag == category:
			_category.select(index)
			_group.set_pressed_no_signal(count > 0 and count == keys.size())
			_group.text = "%s  All %s%s" % ["✓" if count > 0 and count == keys.size() else ("−" if count > 0 else "□"), String(group.label).to_lower(), " (some selected)" if count > 0 and count < keys.size() else ""]
			_group.disabled = keys.is_empty()
			_group.tooltip_text = "Select the whole category, including future items of this type. A dash means some items are allowed."
		if count > 0 and count == keys.size() and group.tag in storage.filter_tags:
			summary.append("All " + String(group.label).to_lower())
		else:
			for key in keys:
				if storage.accepts_key(key): summary.append(_item_name(key))
	_summary.text = "Accepting: " + ("All goods" if selected_count == _keys.size() else ("Nothing" if selected_count == 0 else " + ".join(summary)))
	_summary.tooltip_text = _summary.text
	_waiting.visible = rejected > 0 or selected_count == 0
	_waiting.text = "Goods awaiting relocation: %d\nKept here until accepting storage has room." % rejected if rejected > 0 else "Choose items or a category to enable deliveries."
	_refresh_contents(held)
	_fit.call_deferred()


func _refresh_contents(held: Dictionary) -> void:
	_clear_children(_contents)
	if held.is_empty():
		_label(_contents, "This storage is empty.\nDwarves will bring the goods allowed by its filters.", 14, UITheme.TEXT_DIM)
		return
	for slot in storage.stored_entries():
		var stack: Dictionary = storage.stored_entries()[slot]
		var key := String(stack.item)
		var row := HBoxContainer.new()
		_contents.add_child(row)
		var name_label := _label(row, _item_name(key), 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var quantity := _label(row, "× %d" % int(stack.count), 14)
		quantity.autowrap_mode = TextServer.AUTOWRAP_OFF
		var toggle := _button(row, "Disallow" if storage.slot_allowed(slot) else "Allow")
		toggle.icon = preload("res://assets/ui/icons/disallow.svg")
		toggle.add_theme_constant_override("icon_max_width",18)
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		toggle.pressed.connect(func(): if storage != null: storage.set_disallowed(slot, storage.slot_allowed(slot)))
		if not storage.slot_allowed(slot): _label(_contents, "Disallowed — kept here, unavailable for colony work", 12, UITheme.HEARTH_COPPER)
		if not storage.accepts_key(key):
			_label(_contents, "Awaiting relocation", 12, UITheme.HEARTH_COPPER)
		_contents.add_child(HSeparator.new())


func _show_tab(index: int) -> void:
	_shown_tab = index
	for i in range(_tabs.size()): _tabs[i].set_pressed_no_signal(i == index)
	_filters.visible = index == 0
	_grid.visible = index == 0
	_contents.visible = index == 1
	_scroll.scroll_vertical = 0
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_visible_in_tree(): return
	var viewport := get_viewport_rect().size
	var compact := viewport.y < 620
	_kind.visible = not compact
	add_theme_constant_override("separation", 6 if compact else 8)
	_filters.add_theme_constant_override("separation", 6 if compact else 8)
	custom_minimum_size.x = clampf(viewport.x - 48, 280, 390)
	_grid.columns = 2 if custom_minimum_size.x < 360 else 3
	window.custom_minimum_size.x = custom_minimum_size.x + 30
	var fixed := window.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var max_scroll: float = 250.0 + (_filters.get_combined_minimum_size().y + 8 if _shown_tab == 1 else 0)
	_scroll.custom_minimum_size.y = clampf(viewport.y - 100 - fixed, 100, max_scroll)
	window.reset_size()
	window.clamp_to_viewport()


func _item_name(key: String) -> String:
	return String(storage.drop_manager.get_item_def(key).get("display_name", key))


func _button(parent: Node, caption: String) -> Button:
	var button := UITheme.make_button(caption, "", Vector2(0, 30))
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int, color: Color = UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control: _ignore_mouse(child)
