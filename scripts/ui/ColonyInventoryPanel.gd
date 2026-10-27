extends MarginContainer

## The Colony Inventory window (doc 262), in the Place window's shape:
## - every category open at once as a group of the picture grid: each good on the
##   settlement tile with how many the colony holds (dimmed when none are left), its name
##   on hover;
## - the chosen good on the pine board: its picture and total, its description, what it is
##   made of, where it is (stored, loose, carried, equipped) and what it is free for
##   (available, reserved, disallowed);
## - Locate and Inspect storage under the board.
## Storage owners and ItemDropManager stay authoritative; this only reads the
## ColonyInventory snapshot. Sizes follow the screen's height, and the window fits above
## the dock.
signal locate_requested(item_key: String, storage_only: bool)

const Grid = preload("res://scripts/ui/PictureGrid.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const INK := UITheme.CATALOG_INK
const INK_SOFT := UITheme.CATALOG_MUTED
const FALLBACK := "res://assets/ui/icons/stocks.png"
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as Place's: large from 1300 px tall, small below 650 px.
## `columns` is the columns' least height; they grow until every good's board shows whole,
## as far as the room above the dock allows.
const SIZES := {
	"large": {"tile": 110, "gap": 14, "per_row": 6, "card": 680, "picture": 260, "spacing": 10, "title": LARGE.name, "body": LARGE.body, "label": LARGE.small,
		"heading": LARGE.heading, "material": 64, "material_gap": 16, "value": LARGE.title, "word": LARGE.body, "action": 72, "verb": LARGE.heading, "columns": 960, "type": LARGE},
	"medium": {"tile": 72, "gap": 10, "per_row": 5, "card": 440, "picture": 110, "spacing": 7, "title": MEDIUM.name, "body": MEDIUM.body, "label": MEDIUM.small,
		"heading": MEDIUM.heading, "material": 46, "material_gap": 20, "value": MEDIUM.title, "word": MEDIUM.body, "action": 52, "verb": MEDIUM.heading, "columns": 560, "type": MEDIUM},
	"small": {"tile": 52, "gap": 8, "per_row": 5, "card": 330, "picture": 70, "spacing": 5, "title": SMALL.name, "body": SMALL.body, "label": SMALL.small,
		"heading": SMALL.heading, "material": 36, "material_gap": 8, "value": SMALL.title, "word": SMALL.body, "action": 40, "verb": SMALL.heading, "columns": 300, "type": SMALL},
}
## Where the goods are, then what they are free for: each number with its word.
const WHERE := ["Stored", "Loose", "Carried", "Equipped"]
const STATUS := ["Available", "Reserved", "Disallowed"]
const TIPS := {
	"Stored": "In stockpiles and on construction sites waiting to be used.",
	"Loose": "On the ground outside storage.",
	"Carried": "In a dwarf's hands on the way somewhere.",
	"Equipped": "Tools a dwarf is using.",
	"Available": "Unassigned goods available for new orders.",
	"Reserved": "Already assigned to a dwarf or an order, including equipped tools. Included in the total, not extra goods.",
	"Disallowed": "Goods the dwarves leave where they are.",
}

var window: UIWindow
var controller: FurniturePlacementController
var items: ItemDropManager
var selected_key := ""
var _stock := {}
var _entries := {}
var _categories: Array = []
## The browsing list holds still until the window reopens: goods that run out keep their
## tile, and goods that arrive wait in a New group at the end, so nothing moves under the
## pointer.
var _browse_keys: Array[String] = []
var _arrivals: Array[String] = []
var _browsing := false   # the window's first refresh has listed what the colony held
var _shown: Array[String] = []
var _textures := {}
var _size: Dictionary = SIZES.medium
var _dock_top := 600.0
var _layout_pending := false
var _refresh_queued := false
var _columns: HBoxContainer
var _intro: Label
var _left: PanelContainer
var _scroll: ScrollContainer
var _grid
var _empty: VBoxContainer
var _empty_title: Label
var _empty_text: Label
var _side: VBoxContainer
var _none: PanelContainer
var _none_text: Label
var _card_scroll: ScrollContainer
var _card: PanelContainer
var _content: VBoxContainer
var _name: Label
var _picture: TextureRect
var _chips: VBoxContainer
var _total: Label
var _kind: Label
var _description: Label
var _made_heading: Label
var _materials
var _where_heading: Label
var _values := {}
var _words := {}
var _actions: HBoxContainer
var _locate: Button
var _inspect: Button
var _hint: Label


func _ready() -> void:
	UITheme.apply_surface(self)
	for side: String in ["left", "right", "top"]: add_theme_constant_override("margin_" + side, 12)
	add_theme_constant_override("margin_bottom", 10)
	_categories = UIRegistry.get_inventory_catalog().get("categories", [])
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	add_child(_columns)
	_columns.add_child(_build_goods())
	_columns.add_child(_build_side())
	StockpileManager.stockpile_changed.connect(func(_key: String, _delta: int): _queue_refresh())
	_bind_items()


func _build_goods() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_intro = _text("Click a picture to see where it is kept · hover for its name", MEDIUM.body, UITheme.HEARTH_MUTED)
	_intro.autowrap_mode = TextServer.AUTOWRAP_OFF
	_intro.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_intro)
	_left = PanelContainer.new()
	_left.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_left)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Reserve the scrollbar's gutter before the list overflows: new goods must not move the
	# tiles sideways.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.mouse_force_pass_scroll_events = false
	_left.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	_scroll.add_child(list)
	_grid = Grid.new()
	_grid.family = UIRegistry.get_icon_family_color("settlement")
	_grid.heading_display = true
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.item_pressed.connect(_select)
	list.add_child(_grid)
	_empty = VBoxContainer.new()
	_empty.add_theme_constant_override("separation", 8)
	list.add_child(_empty)
	_empty_title = Label.new()
	_empty_title.text = "Your stockroom is quiet"
	UITheme.format_label(_empty_title, true, MEDIUM.heading, UITheme.TAG_TONES.waiting[0])
	_empty.add_child(_empty_title)
	_empty_text = _text("Gather resources or bring finished furniture into the colony.", MEDIUM.body, UITheme.HEARTH_MUTED)
	_empty.add_child(_empty_text)
	return column


func _build_side() -> Control:
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	_none = PanelContainer.new()
	_none.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_none.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_none)
	_none_text = _text("Choose a picture to see where it is kept.", MEDIUM.body, INK_SOFT)
	_none_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_none_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_none.add_child(_none_text)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.mouse_force_pass_scroll_events = false
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_card_scroll)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card)
	var content := VBoxContainer.new()
	_content = content
	_card.add_child(content)
	_name = _text("", MEDIUM.title, INK)
	_name.add_theme_font_override("font", UITheme.display_font())
	content.add_child(_name)
	var showcase := HBoxContainer.new()
	showcase.add_theme_constant_override("separation", 12)
	content.add_child(showcase)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.add_child(_picture)
	_chips = VBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	showcase.add_child(_chips)
	_total = _chip("Stored + Loose + Carried + Equipped. Installed furniture is in use and not counted.")
	_kind = _chip("The group it is listed under")
	_description = _text("", MEDIUM.lead, INK)
	content.add_child(_description)
	# Any room the board has to spare goes here, so what it is made of and where it is sit
	# at its foot.
	var spare := Control.new()
	spare.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spare)
	_made_heading = _text("MADE OF", MEDIUM.small, INK_SOFT)
	content.add_child(_made_heading)
	_materials = Grid.new()
	_materials.family = UIRegistry.get_icon_family_color("settlement")
	_materials.board = true
	_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_materials)
	_where_heading = _text("WHERE IT IS", MEDIUM.small, INK_SOFT)
	content.add_child(_where_heading)
	for states: Array in [WHERE, STATUS]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
		for state: String in states:
			var stat := HBoxContainer.new()
			stat.add_theme_constant_override("separation", 6)
			stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stat.tooltip_text = TIPS[state]
			row.add_child(stat)
			var value := Label.new()
			value.text = "—"
			UITheme.format_label(value, true, MEDIUM.title, INK)
			stat.add_child(value)
			var word := Label.new()
			word.text = state.to_lower()
			UITheme.format_label(word, false, MEDIUM.body, INK_SOFT)
			word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			stat.add_child(word)
			_values[state] = value
			_words[state] = word
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_side.add_child(_actions)
	_locate = Button.new()
	_locate.text = "Locate"
	_locate.tooltip_text = "Find a stored, loose or carried one"
	UITheme.apply_catalog_primary(_locate)
	_locate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locate.pressed.connect(func(): locate_requested.emit(selected_key, false))
	_actions.add_child(_locate)
	_inspect = UITheme.make_button("Inspect storage", "Open a stockpile holding it", Vector2(0, 32))
	_inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect.pressed.connect(func(): locate_requested.emit(selected_key, true))
	_actions.add_child(_inspect)
	_hint = Label.new()
	_hint.text = "Locate looks on this slice · Inspect storage opens its stockpile"
	_hint.tooltip_text = _hint.text
	UITheme.format_label(_hint, false, MEDIUM.body, UITheme.HEARTH_MUTED)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_side.add_child(_hint)
	return _side


func bind_controller(value: FurniturePlacementController) -> void:
	controller = value
	controller.catalog_changed.connect(_queue_refresh)
	_entries.clear()
	_queue_refresh()


func _bind_items() -> void:
	if is_instance_valid(items): return
	items = ItemDropManager.find(get_tree())
	if items != null: items.loose_items_changed.connect(_queue_refresh)


## A shown good's picture tile, or null.
func tile(key: String) -> Button:
	return _grid.get_tile(key)


## The goods shown now, in their order on screen.
func shown_goods() -> Array[String]:
	return _shown.duplicate()


## The group a good is listed under (data/ui/inventory_catalog.json).
func category_of(key: String) -> String:
	return String(_entry(key).category)


func begin_browsing() -> void:
	_bind_items()
	_browse_keys.clear()
	_arrivals.clear()
	_browsing = false
	_scroll.scroll_vertical = 0
	refresh()
	_fit.call_deferred()


func _select(key: String) -> void:
	selected_key = key
	_card_scroll.scroll_vertical = 0
	refresh()


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
	for key: String in newcomers:
		_browse_keys.append(key)
		if _browsing: _arrivals.append(key)
	_browsing = true
	var groups := _groups()
	_shown.clear()
	for group: Dictionary in groups:
		for item: Dictionary in group.items: _shown.append(String(item.id))
	if not selected_key in _shown: selected_key = _shown[0] if not _shown.is_empty() else ""
	for group: Dictionary in groups:
		for item: Dictionary in group.items: item.selected = item.id == selected_key
	_grid.show_groups(groups)
	_grid.visible = not _shown.is_empty()
	_empty.visible = _shown.is_empty()
	var chosen := not selected_key.is_empty()
	_card_scroll.visible = chosen
	_none.visible = not chosen
	var row: Dictionary = _stock.get(selected_key, {})
	_locate.disabled = int(row.get("total", 0)) <= 0
	_inspect.disabled = int(row.get("stored", 0)) <= 0
	if chosen: _show_card(selected_key)
	else:
		for value: Label in _values.values(): value.text = "—"
	# No refit, sorting of existing goods, scroll reset or window movement here.


## Every category with its goods, in the order the window first listed them. Goods that
## arrived after the window opened wait in a New group at the end.
func _groups() -> Array:
	var by_category := {}
	var arrived: Array = []
	for key: String in _browse_keys:
		if key in _arrivals:
			arrived.append(_good(key))
			continue
		var category := String(_entry(key).category)
		if not by_category.has(category): by_category[category] = []
		by_category[category].append(_good(key))
	var groups: Array = []
	for category: Dictionary in _categories:
		if by_category.has(category.id):
			groups.append({"id": String(category.id), "title": String(category.label), "items": by_category[category.id]})
	if not arrived.is_empty(): groups.append({"id": "new", "title": "New", "items": arrived})
	return groups


func _good(key: String) -> Dictionary:
	var entry := _entry(key)
	var total := int(_stock.get(key, {}).get("total", 0))
	return {"id": key, "picture": _picture_at(String(entry.texture)), "count": total if total > 0 else -1, "dim": total <= 0,
		"tooltip": "%s · %d in the colony" % [entry.label, total]}


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


## The chosen good on the board. Also measures each good's board for the window's height,
## so it only shows.
func _show_card(key: String) -> void:
	var entry := _entry(key)
	var row: Dictionary = _stock.get(key, {})
	_name.text = String(entry.label)
	_picture.texture = _picture_at(String(entry.texture))
	_total.text = "%d in the colony" % int(row.get("total", 0))
	_kind.text = String(entry.category).capitalize()
	for category: Dictionary in _categories:
		if category.id == entry.category: _kind.text = String(category.label)
	_description.text = String(entry.description)
	# Small screens keep the board for where the goods are.
	_description.visible = not _description.text.is_empty() and _size != SIZES.small
	_show_materials(key, row)
	for state: String in WHERE + STATUS: _values[state].text = str(int(row.get(state.to_lower(), 0)))


## What a good is made of, as pictures with counts, when it comes in more than one
## material (furniture of different woods); never the good itself.
func _show_materials(key: String, row: Dictionary) -> void:
	var made: Array = []
	var variants: Dictionary = row.get("materials", {})
	for id: String in variants:
		var material: Dictionary = CraftMaterials.definitions.get(id, {})
		var ingredients: Array = material.get("ingredients", [])
		if id.is_empty() or (not ingredients.is_empty() and String(ingredients[0]) == key): continue
		var name := CraftMaterials.material_name(id)
		var picture: Texture2D = _picture_at(Inventory.thumbnail_path(String(ingredients[0]))) if not ingredients.is_empty() else null
		made.append({"id": id, "picture": picture, "text": "" if picture != null else name, "count": int(variants[id]),
			"caption": name if _size != SIZES.small else "", "tooltip": "%s · %d" % [name, int(variants[id])]})
	_made_heading.visible = not made.is_empty()
	_materials.visible = not made.is_empty()
	if not made.is_empty(): _materials.show_groups([{"id": "materials", "items": made}])


func _picture_at(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path) if ResourceLoader.exists(path) else load(FALLBACK)
	return _textures[path]


# ── Size and fit ──────────────────────────────────────────────────────────────

func fit_above_dock(top: float) -> void:
	_dock_top = top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	_size = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	_apply_size()
	refresh()
	# The columns are as tall as the tallest board of the goods listed needs, as far as the
	# room the window's frame leaves above the dock allows; the goods scroll, and so does a
	# board that cannot show whole.
	_columns.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	var room := maxf(200.0, _dock_top - 12.0 - chrome)
	_columns.custom_minimum_size.y = minf(room, maxf(float(_size.columns), _tallest_side()))
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock.call_deferred()
	_settle_layout()


## The side's height when every listed good's board shows whole at this size, with the
## actions and the hint under it. Measured on the live board, so wrapped text counts as it
## will show.
func _tallest_side() -> float:
	if not is_visible_in_tree() or _shown.is_empty(): return 0.0
	_card_scroll.visible = true
	_none.visible = false
	window.reset_size()
	UITheme.lay_out_now(window)   # every column takes its width for this size
	_card.size.x = _card_scroll.size.x   # a board that fits has no scrollbar beside it
	var tallest := 0.0
	for key: String in _shown:
		_show_card(key)
		UITheme.lay_out_now(_card)
		tallest = maxf(tallest, _card.get_combined_minimum_size().y)
	refresh()
	var separation := float(_side.get_theme_constant("separation"))
	return ceilf(tallest + _actions.get_combined_minimum_size().y + _hint.get_combined_minimum_size().y + separation * 2.0)


func _apply_size() -> void:
	var s := _size
	_grid.gap = float(s.gap)
	_grid.heading_size = int(s.heading)
	_grid.set_tile_size(float(s.tile))
	_left.custom_minimum_size.x = float(s.per_row) * (float(s.tile) + float(s.gap)) + 40.0   # the inset and its scrollbar
	_side.custom_minimum_size.x = float(s.card)
	_intro.visible = s != SIZES.small   # small screens: the hover card says it
	_intro.add_theme_font_size_override("font_size", int(s.body))
	_empty_title.add_theme_font_size_override("font_size", s.heading)
	_empty_text.add_theme_font_size_override("font_size", s.body)
	_none_text.add_theme_font_size_override("font_size", s.body)
	_picture.custom_minimum_size = Vector2(float(s.picture), float(s.picture) * 0.82)
	_content.add_theme_constant_override("separation", s.spacing)   # the board holds more than Place's
	_name.add_theme_font_size_override("font_size", s.title)
	_description.add_theme_font_size_override("font_size", s.body)
	for chip: Label in [_total, _kind]: chip.add_theme_font_size_override("font_size", int(s.body))
	for heading: Label in [_made_heading, _where_heading]: heading.add_theme_font_size_override("font_size", s.label)
	_materials.caption_size = int(s.label)
	_materials.gap = float(s.material_gap)   # room for each material's name under its tile
	_materials.set_tile_size(float(s.material))
	for value: Label in _values.values(): value.add_theme_font_size_override("font_size", s.value)
	for word: Label in _words.values(): word.add_theme_font_size_override("font_size", s.word)
	_locate.custom_minimum_size.y = float(s.action)
	_locate.add_theme_font_size_override("font_size", s.verb)
	_inspect.custom_minimum_size.y = float(s.action)
	_inspect.add_theme_font_size_override("font_size", int(s.type.lead))
	_hint.add_theme_font_size_override("font_size", int(s.label))


func _settle_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	# Wrapped text needs its final width before measuring.
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_pending = false
	if not is_instance_valid(window): return
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock()


func _clamp_above_dock() -> void:
	if window == null: return
	window.position.y = minf(window.position.y, maxf(4, _dock_top - 8 - window.size.y))


# ── Pieces ────────────────────────────────────────────────────────────────────

## A stone chip beside the picture, holding one line; returns its label.
func _chip(tip: String) -> Label:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.cell_style("chip", 3))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.tooltip_text = tip
	_chips.add_child(chip)
	var label := Label.new()
	UITheme.format_label(label, false, MEDIUM.lead, UITheme.KEYCAP_INK)
	chip.add_child(label)
	return label


func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UITheme.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
