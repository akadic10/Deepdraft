extends MarginContainer

## The storage window (doc 261, phase 4), after Stonehearth's stockpile filter and contents.
## - One line on what to do. The filter: the groups (Materials, Food & farming, Goods), each
##   with its All, Some or None state, and their categories as pictures marked ✓ or −. A
##   click on a picture stores the whole category or stops it; a click on its name opens
##   its exact goods under the group, where a click allows or refuses one good: the
##   exceptions both ways.
## - All and None, how full it is, and Remove zone.
## - Filter and Contents hang under the window, as Stonehearth's do. Contents is the same
##   grouped picture grid with counts; goods awaiting relocation carry a "!".
## Changes go straight to the storage owner; nothing waits for Apply. The groups and the
## categories' pictures are UIRegistry's (storage_filters.json).
signal action_requested(action_id: String)

const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Grid = preload("res://scripts/ui/PictureGrid.gd")
const HAY := Color("e2c06a")
const MUTED := Color("aeb5ad")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height: large from 1300 px tall (the concept's sizes on the
## 7680×2160 screen), small below 650 px. `body` is the filter's height: the window keeps it
## from tab to tab, as far as the room above the dock allows, and longer pages scroll.
const SIZES := {
	"large": {"width": 860, "side": 20, "top": 12, "bottom": 8, "hint": LARGE.body, "tile": 80, "exact": 64, "caption": 14,
		"heading": LARGE.heading, "heading_width": 200, "state": 15, "label": LARGE.small, "used": LARGE.lead, "bar": 14, "button": Vector2(120, 46),
		"button_font": LARGE.body, "action": 44, "tab": Vector2(170, 46), "tab_font": LARGE.body, "body": 640, "gap": 12, "tile_gap": 24, "type": LARGE},
	"medium": {"width": 640, "side": 14, "top": 8, "bottom": 6, "hint": MEDIUM.body, "tile": 60, "exact": 48, "caption": 12,
		"heading": MEDIUM.heading, "heading_width": 150, "state": 13, "label": MEDIUM.small, "used": MEDIUM.lead, "bar": 10, "button": Vector2(96, 36),
		"button_font": MEDIUM.body, "action": 34, "tab": Vector2(130, 36), "tab_font": MEDIUM.body, "body": 420, "gap": 8, "tile_gap": 16, "type": MEDIUM},
	"small": {"width": 470, "side": 10, "top": 6, "bottom": 4, "hint": SMALL.body, "tile": 44, "exact": 40, "caption": 11,
		"heading": SMALL.heading, "heading_width": 112, "state": 12, "label": SMALL.small, "used": SMALL.lead, "bar": 8, "button": Vector2(80, 30),
		"button_font": SMALL.body, "action": 30, "tab": Vector2(110, 32), "tab_font": SMALL.body, "body": 260, "gap": 6, "tile_gap": 10, "type": SMALL},
}
const HINTS := ["Click the pictures to choose what to store here; a name opens its exact goods.",
	"What this storage holds. Click a picture to find it in the filter."]

var window: UIWindow
var dock: Node   # DockUI, when there is one: the window fits above it
var storage: StorageComponent
var category := ""   # the category whose exact goods are open, or ""
var info_label: Label   # how full it is
var _size: Dictionary = {}
var _column: VBoxContainer
var _hint: Label
var _body: PanelContainer
var _scroll: ScrollContainer
var _filter: VBoxContainer   # a row per group; the open category's goods under its group
var _rows := {}   # group id -> its picture grid
var _exact: MarginContainer
var _exact_heading: Label
var _exact_grid
var _exact_empty: Label
var _contents_page: VBoxContainer
var _contents
var _contents_empty: Label
var _footer: HBoxContainer
var _all: Button
var _none: Button
var _capacity: ProgressBar
var _waiting: Label
var _actions: VBoxContainer
var _action_data: Array = []
var _hanger: Control
var _tab_row: HBoxContainer
var _tabs: Array[Button] = []
var _shown_tab := 0
var _category_keys := {}   # category tag -> its item keys, by name
var _content_entries: Array[Dictionary] = []   # what Contents shows: id, item, name, count, group, waiting
var _textures := {}
var _refresh_queued := false


func _ready() -> void:
	UITheme.apply_surface(self)
	_column = VBoxContainer.new()
	add_child(_column)
	_hint = _text(_column, HINTS[0], MEDIUM.body, MUTED)
	_body = PanelContainer.new()
	_body.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_column.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_body.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_filter = VBoxContainer.new()
	pages.add_child(_filter)
	for group: Dictionary in UIRegistry.get_storage_groups():
		var row = _grid()
		row.item_pressed.connect(_toggle_category)
		row.caption_pressed.connect(_open_category)
		row.group_pressed.connect(_toggle_group)
		_filter.add_child(row)
		_rows[String(group.id)] = row
	# The open category's exact goods, indented under its group's pictures.
	_exact = MarginContainer.new()
	_filter.add_child(_exact)
	var exact_panel := PanelContainer.new()
	exact_panel.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_exact.add_child(exact_panel)
	var exact_box := VBoxContainer.new()
	exact_box.add_theme_constant_override("separation", 8)
	exact_panel.add_child(exact_box)
	_exact_heading = _text(exact_box, "", MEDIUM.small, HAY)
	_exact_grid = _grid()
	_exact_grid.item_pressed.connect(_toggle_item)
	exact_box.add_child(_exact_grid)
	_exact_empty = _text(exact_box, "No goods of this kind are known yet.", MEDIUM.small, MUTED)
	_contents_page = VBoxContainer.new()
	pages.add_child(_contents_page)
	_contents = _grid()
	_contents.item_pressed.connect(_find_in_filter)
	_contents_page.add_child(_contents)
	_contents_empty = _text(_contents_page, "This storage is empty.\nDwarves will bring the goods its filter allows.", MEDIUM.body, MUTED)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	_column.add_child(_footer)
	_all = _button(_footer, "All", "Store every kind of goods here.")
	_all.pressed.connect(func(): if storage != null: storage.set_all_accepted(true))
	_none = _button(_footer, "None", "Store nothing here. Goods already here wait for room elsewhere.")
	_none.pressed.connect(func(): if storage != null: storage.set_all_accepted(false))
	var fullness := VBoxContainer.new()
	fullness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullness.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fullness.add_theme_constant_override("separation", 4)
	_footer.add_child(fullness)
	info_label = _text(fullness, "", MEDIUM.heading, HAY, true)
	info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_capacity = ProgressBar.new()
	UITheme.hearth_progress(_capacity)
	_capacity.tooltip_text = "Produce crates hold several goods in one cell."
	fullness.add_child(_capacity)
	_waiting = _text(_column, "", MEDIUM.body, HAY)
	_actions = VBoxContainer.new()
	_column.add_child(_actions)
	# Filter and Contents hang under the window, as Stonehearth's tabs do: a row placed
	# below the window's bottom edge, outside its frame.
	_hanger = Control.new()
	_hanger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_hanger)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	_hanger.add_child(_tab_row)
	for caption: String in ["Filter", "Contents"]:
		var tab := Button.new()
		tab.text = caption
		tab.focus_mode = Control.FOCUS_ALL
		tab.pressed.connect(_show_tab.bind(_tabs.size()))
		_tab_row.add_child(tab)
		_tabs.append(tab)
	_hanger.item_rect_changed.connect(_place_tabs)
	get_viewport().size_changed.connect(func(): _fit.call_deferred())
	visibility_changed.connect(func(): if is_visible_in_tree(): _queue_refresh())
	_apply_size(SIZES.medium)
	_show_tab(0)


func show_storage(value: StorageComponent, actions: Array = [], title: String = "Storage") -> void:
	if window != null: window.set_window_title(title, "")   # the band names the zone
	if storage == value and actions == _action_data: return
	if storage != value:
		clear_subject()
		storage = value
		storage.changed.connect(_queue_refresh)
		_index_goods()
		category = ""
		_show_tab(0)
	if actions != _action_data:
		_action_data = actions.duplicate(true)
		_clear_children(_actions)
		for action: Dictionary in actions:
			var button := _button(_actions, String(action.text), "")
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UITheme.apply_button_variant(button, String(action.get("variant", "")))
			button.pressed.connect(func(): action_requested.emit(String(action.id)))
		_apply_size(_size)
	refresh()


func clear_subject() -> void:
	if storage != null and storage.changed.is_connected(_queue_refresh):
		storage.changed.disconnect(_queue_refresh)
	storage = null


func _exit_tree() -> void:
	clear_subject()


## Every known good under its category, by name; identity comes from the item registry.
func _index_goods() -> void:
	_category_keys.clear()
	if not is_instance_valid(storage.drop_manager): return
	var keys: Array[String] = []
	keys.assign(storage.drop_manager.get_item_defs().keys())
	keys.sort_custom(func(a: String, b: String): return _item_name(a).naturalnocasecmp_to(_item_name(b)) < 0)
	for entry: Dictionary in UIRegistry.get_storage_categories():
		var tag := String(entry.tag)
		_category_keys[tag] = keys.filter(func(key: String): return tag in storage.drop_manager.get_item_def(key).get("material_tags", []))


## A category's state for this storage: "on" when it takes all of it, "some", or "off".
func category_state(tag: String) -> String:
	var keys: Array = _category_keys.get(tag, [])
	if keys.is_empty(): return "on" if tag in storage.filter_tags else "off"
	var allowed := keys.filter(func(key: String): return storage.accepts_key(key)).size()
	return "on" if allowed == keys.size() else ("off" if allowed == 0 else "some")


## The picture of a category in the filter, for tests and the tour.
func get_category_tile(tag: String) -> Button:
	for row in _rows.values():
		if row.get_tile(tag) != null: return row.get_tile(tag)
	return null


## Open a category's exact goods under its group. The rebuild waits for the next idle
## moment: the click that asked for it must finish on its button, or it reaches the world.
func set_category(tag: String) -> void:
	category = tag
	_queue_refresh()


func _open_category(tag: String) -> void:
	set_category("" if tag == category else tag)


func _toggle_category(tag: String) -> void:
	if storage != null: storage.set_category_accepted(tag, category_state(tag) != "on")


func _toggle_group(group_id: String) -> void:
	if storage == null: return
	var categories := _categories_of(group_id)
	var allow := not categories.all(func(entry: Dictionary): return category_state(String(entry.tag)) == "on")
	for entry: Dictionary in categories: storage.set_category_accepted(String(entry.tag), allow)


func _toggle_item(key: String) -> void:
	if storage != null: storage.set_item_accepted(key, not storage.accepts_key(key))


## A stored good's picture in Contents opens its category in the filter.
func _find_in_filter(id: String) -> void:
	var tag := _category_of(id.get_slice("|", 0))
	if tag.is_empty(): return
	category = tag
	_show_tab(0)
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if storage == null or not is_instance_valid(storage.drop_manager): return
	var held := storage.contents()
	var goods := 0
	var rejected := 0
	for key: String in held:
		goods += int(held[key])
		if not storage.accepts_key(key): rejected += int(held[key])
	var used := storage.stored_entries().size()
	info_label.text = "Used %d / %d cells · %d goods" % [used, storage.storage_capacity(), goods]
	_capacity.max_value = maxi(1, storage.storage_capacity())
	_capacity.value = used
	_show_filter()
	_show_contents()
	var accepts_any := UIRegistry.get_storage_categories().any(func(entry: Dictionary): return category_state(String(entry.tag)) != "off")
	_waiting.visible = rejected > 0 or not accepts_any
	_waiting.text = "Goods awaiting relocation: %d · kept here until storage that takes them has room." % rejected if rejected > 0 \
		else "Nothing is allowed yet: choose goods to start deliveries."
	_fit.call_deferred()


func _show_filter() -> void:
	for group: Dictionary in UIRegistry.get_storage_groups():
		var items := []
		var states := []
		for entry: Dictionary in _categories_of(String(group.id)):
			var tag := String(entry.tag)
			var state := category_state(tag)
			states.append(state)
			var open := tag == category
			items.append({"id": tag, "picture": _texture(String(entry.picture)), "mark": {"on": "on", "some": "some"}.get(state, ""),
				"dim": state == "off", "selected": open, "caption": "%s %s" % [entry.label, "▴" if open else "▾"], "caption_button": true,
				"tooltip": "%s · %s\nClick the picture to %s. Click its name for its exact goods." % [entry.label,
					{"on": "all stored here", "some": "some stored here", "off": "not stored here"}[state],
					"stop storing it" if state == "on" else "store all of it"]})
		var group_state := "All" if states.all(func(state: String): return state == "on") else ("None" if states.all(func(state: String): return state == "off") else "Some")
		_rows[String(group.id)].show_groups([{"id": group.id, "title": group.label, "state": group_state, "items": items}])
	# The open category's exact goods sit under its group's row.
	var open_entry := _category_entry(category)
	_exact.visible = not open_entry.is_empty()
	if open_entry.is_empty(): return
	var row_index: int = _rows[String(open_entry.group)].get_index()
	_filter.move_child(_exact, row_index if _exact.get_index() < row_index else row_index + 1)   # just under the row
	_exact_heading.text = "%s · exact goods" % String(open_entry.label).to_upper()
	var items := []
	for key: String in _category_keys.get(category, []):
		var allowed := storage.accepts_key(key)
		items.append({"id": key, "picture": _item_texture(key), "mark": "on" if allowed else "", "dim": not allowed,
			"tooltip": "%s\n%s" % [_item_name(key), "Stored here. Click to refuse it." if allowed else "Not stored here. Click to allow it."]})
	_exact_grid.show_groups([{"id": category, "items": items}])
	_exact_empty.visible = items.is_empty()


func _show_contents() -> void:
	# Derive a presentation view only; physical slots still own the inventory. Each good
	# keeps its material apart (a pine and an oak stool are two pictures).
	var grouped := {}
	_content_entries.clear()
	for stack: Dictionary in storage.stored_entries().values():
		var key := String(stack.item)
		var material_id := String(stack.get("material_id", ""))
		var id := "%s|%s" % [key, material_id]
		if not grouped.has(id):
			var tag := _category_of(key)
			var entry := {"id": id, "item": key, "count": 0, "waiting": not storage.accepts_key(key),
				"name": CraftMaterials.product_name(_item_name(key), material_id),
				"group": String(_category_entry(tag).get("group", "goods"))}
			grouped[id] = entry
			_content_entries.append(entry)
		grouped[id].count += int(stack.count)
	_content_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order := String(a.name).naturalnocasecmp_to(String(b.name))
		return order < 0 if order != 0 else String(a.id) < String(b.id))
	var groups := []
	for group: Dictionary in UIRegistry.get_storage_groups():
		var items := []
		for entry: Dictionary in _content_entries:
			if entry.group != group.id: continue
			items.append({"id": entry.id, "picture": _item_texture(String(entry.item)), "count": entry.count,
				"mark": "missing" if entry.waiting else "",
				"tooltip": "%s × %d%s" % [entry.name, entry.count, "\nAwaiting relocation: kept here until storage that takes it has room." if entry.waiting else ""]})
		if not items.is_empty(): groups.append({"id": group.id, "title": group.label, "items": items})
	_contents.show_groups(groups)
	_contents_empty.visible = groups.is_empty()


func _show_tab(index: int) -> void:
	_shown_tab = index
	for i in range(_tabs.size()):
		UITheme.show_tab(_tabs[i], i == index)
	_filter.visible = index == 0
	_contents_page.visible = index == 1
	_all.visible = index == 0
	_none.visible = index == 0
	_hint.text = HINTS[index]
	_scroll.scroll_vertical = 0
	_fit.call_deferred()


# ── Size and fit ──────────────────────────────────────────────────────────────

## Take the size for the screen and the room above the dock. The body keeps one height
## from tab to tab, so opening a category or switching to Contents never moves the
## buttons; the tabs that hang under the window keep their room too.
func _fit() -> void:
	if window == null or not is_visible_in_tree(): return
	var viewport := get_viewport_rect().size
	var chosen: Dictionary = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	if chosen != _size: _apply_size(chosen)
	custom_minimum_size.x = minf(float(_size.width) - 8.0, viewport.x - 32.0)   # the frame's sides
	var top := UIWindow.VIEWPORT_MARGIN if viewport.y < 650.0 else 32.0
	var bottom: float = (dock.dock_top() if is_instance_valid(dock) else viewport.y) - 8.0 - float(_size.tab.y)
	_scroll.custom_minimum_size.y = 0.0
	window.reset_size()
	UITheme.lay_out_now(window)
	var chrome := window.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(bottom - top - chrome, 96.0, float(_size.body))
	window.reset_size()
	window.position.y = minf(window.position.y, maxf(top, bottom - window.size.y))
	window.clamp_to_viewport()
	_place_tabs.call_deferred()


## The tabs sit under the window's bottom edge, overlapping it a little.
func _place_tabs() -> void:
	if window == null or not is_inside_tree(): return
	var frame := window.get_global_rect()
	var origin := _hanger.get_global_rect().position
	_tab_row.position = Vector2(frame.position.x + float(_size.get("side", 14)) + 4.0 - origin.x, frame.end.y - 6.0 - origin.y)


func _apply_size(s: Dictionary) -> void:
	_size = s
	var gap := int(s.gap)
	for side: String in ["left", "right"]: add_theme_constant_override("margin_" + side, int(s.side))
	add_theme_constant_override("margin_top", int(s.top))
	add_theme_constant_override("margin_bottom", int(s.bottom))
	_column.add_theme_constant_override("separation", gap)
	_hint.add_theme_font_size_override("font_size", s.hint)
	_filter.add_theme_constant_override("separation", gap + 4)
	for row in _rows.values() + [_contents]:
		row.heading_beside = true
		row.heading_width = float(s.heading_width)
		row.heading_size = int(s.heading)
		row.state_size = int(s.state)
		row.caption_size = int(s.caption)
		row.gap = float(s.tile_gap)
		row.set_tile_size(float(s.tile))
	_exact_grid.gap = float(s.tile_gap) * 0.5
	_exact_grid.set_tile_size(float(s.exact))
	_exact.add_theme_constant_override("margin_left", int(s.heading_width) + 16)   # under the pictures
	_exact_heading.add_theme_font_size_override("font_size", s.label)
	for label: Label in [_exact_empty, _contents_empty, _waiting]: label.add_theme_font_size_override("font_size", int(s.hint))
	info_label.add_theme_font_size_override("font_size", s.used)
	_capacity.custom_minimum_size.y = float(s.bar)
	for button: Button in [_all, _none]:
		button.custom_minimum_size = s.button
		button.add_theme_font_size_override("font_size", s.button_font)
	for button: Node in _actions.get_children():
		(button as Button).custom_minimum_size.y = float(s.action)
		(button as Button).add_theme_font_size_override("font_size", s.button_font)
	for tab: Button in _tabs:
		tab.custom_minimum_size = s.tab
		tab.add_theme_font_size_override("font_size", s.tab_font)
	if storage != null: refresh()


# ── Pieces ────────────────────────────────────────────────────────────────────

func _grid():
	var grid = Grid.new()
	grid.family = UIRegistry.get_icon_family_color("work")
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _categories_of(group_id: String) -> Array[Dictionary]:
	return UIRegistry.get_storage_categories().filter(func(entry: Dictionary): return String(entry.group) == group_id)


func _category_entry(tag: String) -> Dictionary:
	for entry: Dictionary in UIRegistry.get_storage_categories():
		if String(entry.tag) == tag: return entry
	return {}


## The filter category a good belongs to, by its stockpile tag.
func _category_of(key: String) -> String:
	var tags: Array = storage.drop_manager.get_item_def(key).get("material_tags", [])
	for entry: Dictionary in UIRegistry.get_storage_categories():
		if String(entry.tag) in tags: return String(entry.tag)
	return ""


func _item_name(key: String) -> String:
	return String(storage.drop_manager.get_item_def(key).get("display_name", key))


func _item_texture(key: String) -> Texture2D:
	var path := Inventory.thumbnail_path(key)
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)   # packed furniture
	return _texture(path if ResourceLoader.exists(path) else "res://assets/ui/icons/stocks.png")


func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]


func _button(parent: Node, caption: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	parent.add_child(button)
	return button


func _text(parent: Node, value: String, font_size: int, color := UITheme.CARD_TEXT, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.format_label(label, display, font_size, color)
	parent.add_child(label)
	return label


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
