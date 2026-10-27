extends MarginContainer

## The DEV item stamper's window (doc 23, "The item stamper"), laid out as Place is:
## - every item as a picture, in the groups of data/ui/item_stamper.json, with the recent
##   ones first. The search box keeps the items whose name or id holds what is typed, and
##   Enter picks the first;
## - the chosen item on the pine board: its name, id, picture and description, its wood as
##   pictures for furniture, and the amount;
## - Stamp starts stamping (ItemStamperController). The tool bar then has the keys, what
##   each stamp put down, and Done; Esc ends it too (doc 23, "The tool bar").
## Items that cannot be stamped show dimmed, with the reason. Recent items are kept between
## sessions in user://. Sizes follow the screen's height, and the window fits above the dock.
signal stamp_requested

const Grid = preload("res://scripts/ui/PictureGrid.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Stamper = preload("res://scripts/systems/ItemStamperController.gd")
const RECENT_PATH := "user://item_stamper.cfg"
const INK := UITheme.CATALOG_INK
const INK_SOFT := UITheme.CATALOG_MUTED
const RECENT := "recent:"   # a recent tile's id: the same item as its group's tile
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Place's sizes by the screen's height: large from 1300 px tall, small below 650 px. `columns`
## is the columns' height, room for the tallest board, as far as the room above the dock
## allows. Small screens name the woods on hover only.
const SIZES := {
	"large": {"tile": 110, "gap": 14, "per_row": 6, "card": 600, "picture": 220, "title": LARGE.name, "body": LARGE.body,
		"label": LARGE.small, "heading": LARGE.heading, "wood": 80, "value": LARGE.name, "word": LARGE.body, "action": 72, "verb": LARGE.heading, "columns": 1000, "type": LARGE},
	"medium": {"tile": 72, "gap": 10, "per_row": 6, "card": 420, "picture": 130, "title": MEDIUM.name, "body": MEDIUM.body,
		"label": MEDIUM.small, "heading": MEDIUM.heading, "wood": 64, "value": MEDIUM.name, "word": MEDIUM.body, "action": 52, "verb": MEDIUM.heading, "columns": 620, "type": MEDIUM},
	"small": {"tile": 52, "gap": 8, "per_row": 5, "card": 330, "picture": 80, "title": SMALL.name, "body": SMALL.body,
		"label": SMALL.small, "heading": SMALL.heading, "wood": 48, "value": SMALL.name, "word": SMALL.body, "action": 40, "verb": SMALL.heading, "columns": 400, "type": SMALL},
}

var controller: Node
var window: UIWindow
## The chosen item's key, "" before one is chosen.
var selected_key := ""
## The items stamped lately, newest first.
var recent: Array[String] = []
var search: LineEdit
var grid: Grid
var woods: Grid
var stamp_button: Button
var _wood := ""
var _amount := 1
var _items := {}   # key -> {key, name, picture, group, refusal}
var _groups: Array = []
var _size: Dictionary = SIZES.medium
var _dock_top := 600.0
var _columns: HBoxContainer
var _intro: Label
var _left: PanelContainer
var _nothing: Label
var _card_scroll: ScrollContainer
var _card: PanelContainer
var _title: Label
var _id: Label
var _picture: TextureRect
var _about: Label
var _wood_heading: Label
var _amount_heading: Label
var _value: Label
var _amount_row: HBoxContainer
var _refusal: Label
var _hint: Label


func _init() -> void:
	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 10)
	add_theme_constant_override("margin_top", 8)
	add_theme_constant_override("margin_bottom", 10)
	_read_items()
	_load_recent()
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	add_child(_columns)
	_columns.add_child(_build_items())
	_columns.add_child(_build_side())
	_show_grid()
	_show_card()


func _ready() -> void:
	get_viewport().size_changed.connect(func(): if is_visible_in_tree(): _fit())
	visibility_changed.connect(func(): if is_visible_in_tree(): _fit.call_deferred())
	if controller != null: bind_controller(controller)


## The tool this window drives: its state shows on Stamp, and each stamp keeps Recent.
func bind_controller(tool: Node) -> void:
	controller = tool
	if not controller.tool_active_changed.is_connected(_on_active_changed):
		controller.tool_active_changed.connect(_on_active_changed)
		controller.stamped.connect(_on_stamped)
	_push()
	_on_active_changed(controller.is_active())


func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()


# ── Building ──────────────────────────────────────────────────────────────────

func _build_items() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	_intro = _text("Pick an item, Stamp, then click floors", MEDIUM.body, UITheme.HEARTH_MUTED)
	_intro.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_intro)
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search by name or id"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): _show_grid())
	search.text_submitted.connect(func(_text: String): _pick_first())
	top.add_child(search)
	_left = PanelContainer.new()
	_left.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	grid = Grid.new()
	grid.family = UIRegistry.get_icon_family_color("dev")
	grid.heading_display = true
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.item_pressed.connect(_select)
	list.add_child(grid)
	_nothing = _text("", MEDIUM.lead, UITheme.TAG_TONES.waiting[0], true)
	_nothing.visible = false
	list.add_child(_nothing)
	return column


func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_card_scroll)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_card.add_child(column)
	_title = _text("", MEDIUM.name, INK, true)
	column.add_child(_title)
	_id = _text("", MEDIUM.body, INK_SOFT)
	column.add_child(_id)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_picture)
	_about = _text("", MEDIUM.lead, INK)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_about)
	_wood_heading = _text("WOOD · the stamped piece is made of it", MEDIUM.body, INK_SOFT)
	column.add_child(_wood_heading)
	woods = Grid.new()
	woods.family = UIRegistry.get_icon_family_color("dev")
	woods.board = true
	woods.item_pressed.connect(func(id: String):
		_wood = id
		_show_card()
		_push())
	column.add_child(woods)
	_amount_heading = _text("AMOUNT", MEDIUM.body, INK_SOFT)
	column.add_child(_amount_heading)
	_amount_row = HBoxContainer.new()
	_amount_row.add_theme_constant_override("separation", 6)
	column.add_child(_amount_row)
	_amount_row.add_child(_amount_button("−", func(): _set_amount(_amount - 1)))
	_value = _text("1", MEDIUM.name, INK, true)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_row.add_child(_value)
	_amount_row.add_child(_amount_button("+", func(): _set_amount(_amount + 1)))
	for jump: Variant in UIRegistry.get_item_stamper().get("amounts", []):
		_amount_row.add_child(_amount_button(str(int(jump)), _set_amount.bind(int(jump))))
	_refusal = _text("", MEDIUM.body, UITheme.TAG_TONES.blocked[2])
	_refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_refusal)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	side.add_child(actions)
	stamp_button = Button.new()
	stamp_button.name = "Stamp"
	stamp_button.text = "Stamp"
	stamp_button.tooltip_text = "Then click a floor; each click puts the amount down"
	stamp_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_hearth_button(stamp_button, true)
	stamp_button.pressed.connect(func(): stamp_requested.emit())
	actions.add_child(stamp_button)
	_hint = _text("", MEDIUM.body, UITheme.HEARTH_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_hint)
	return side


func _amount_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	UITheme.apply_hearth_button(button)
	button.pressed.connect(action)
	return button


func _text(text: String, font_size: int, color: Color, display := false) -> Label:
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, display, font_size, color)
	return label


# ── Items ─────────────────────────────────────────────────────────────────────

## Every item with its name, picture, group and whether it can be stamped. An item whose
## category no group names falls in the last group.
func _read_items() -> void:
	_groups = UIRegistry.get_item_stamper().get("groups", [])
	for key: String in ContentRegistry.items:
		var definition: Dictionary = ContentRegistry.item_def(key)
		var category := key.get_slice(":", 2) if key.get_slice_count(":") > 2 else ""
		var group := String(_groups.back().id) if not _groups.is_empty() else ""
		for entry: Dictionary in _groups:
			if category in entry.get("categories", []):
				group = String(entry.id)
				break
		_items[key] = {"key": key, "name": String(definition.get("display_name", key)), "picture": _picture_of(key),
			"group": group, "refusal": Stamper.refusal(key)}


static func _picture_of(key: String) -> Texture2D:
	for path: String in [Inventory.thumbnail_path(key), "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)]:
		if ResourceLoader.exists(path): return load(path)
	return null


func _matches(item: Dictionary, query: String) -> bool:
	return query.is_empty() or String(item.name).to_lower().contains(query) or String(item.key).contains(query)


func _tile(item: Dictionary, prefix := "") -> Dictionary:
	var refused := not String(item.refusal).is_empty()
	return {"id": prefix + String(item.key), "picture": item.picture, "text": "" if item.picture != null else String(item.name),
		"selected": item.key == selected_key, "dim": refused,
		"tooltip": String(item.name) + ("\n" + String(item.refusal) if refused else "")}


## The groups as tiles, with Recent first while nothing is searched for. A search hides what
## does not match, and says so when nothing does.
func _show_grid() -> void:
	var query := search.text.strip_edges().to_lower()
	var shown: Array = []
	if query.is_empty() and not recent.is_empty():
		shown.append({"id": "recent", "title": "Recent", "items": recent.filter(func(key: String) -> bool: return _items.has(key))
			.map(func(key: String) -> Dictionary: return _tile(_items[key], RECENT))})
	var found := 0
	for entry: Dictionary in _groups:
		var tiles: Array = []
		for item: Dictionary in _in_group(String(entry.id)):
			var tile := _tile(item)
			tile.hidden = not _matches(item, query)
			if not tile.hidden: found += 1
			tiles.append(tile)
		shown.append({"id": String(entry.id), "title": String(entry.title), "items": tiles})
	grid.show_groups(shown)
	_nothing.visible = found == 0
	_nothing.text = "Nothing is called \"%s\"." % search.text.strip_edges()


func _in_group(group: String) -> Array:
	var members: Array = _items.values().filter(func(item: Dictionary) -> bool: return item.group == group)
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return members


## Enter in the search box: the first item that matches.
func _pick_first() -> void:
	var query := search.text.strip_edges().to_lower()
	for entry: Dictionary in _groups:
		for item: Dictionary in _in_group(String(entry.id)):
			if _matches(item, query):
				_select(String(item.key))
				return


func _select(id: String) -> void:
	selected_key = id.trim_prefix(RECENT)
	_wood = ""
	var woods_of := _woods_for(selected_key)
	if not woods_of.is_empty(): _wood = String(woods_of[0])
	_show_grid()
	_show_card()
	_push()


## The woods an item can be made of, in the materials' order; empty when it takes none.
func _woods_for(key: String) -> Array:
	var group := String(ContentRegistry.item_def(key).get("material_group", ""))
	if group.is_empty(): return []
	return CraftMaterials.definitions.keys().filter(func(id: String) -> bool: return String(CraftMaterials.definitions[id].group) == group)


func _set_amount(value: int) -> void:
	_amount = clampi(value, 1, 999)
	_value.text = str(_amount)
	_push()


func _push() -> void:
	if controller != null: controller.choose(selected_key, _amount, _wood)
	_show_actions()


# ── The board ─────────────────────────────────────────────────────────────────

func _show_card() -> void:
	var item: Dictionary = _items.get(selected_key, {})
	_card.visible = not item.is_empty()
	_value.text = str(_amount)
	if item.is_empty():
		_show_actions()
		return
	var definition: Dictionary = ContentRegistry.item_def(selected_key)
	_title.text = String(item.name)
	_id.text = selected_key
	_picture.texture = item.picture
	_about.text = String(definition.get("description", ""))
	var choices := _woods_for(selected_key)
	_wood_heading.visible = not choices.is_empty()
	woods.visible = not choices.is_empty()
	woods.show_groups([{"id": "woods", "items": choices.map(func(id: String) -> Dictionary:
		var ingredients: Array = CraftMaterials.definitions[id].get("ingredients", [])
		var picture := _picture_of(String(ingredients[0])) if not ingredients.is_empty() else null
		var name := CraftMaterials.material_name(id)
		return {"id": id, "picture": picture, "text": "" if picture != null else name, "caption": name if _size != SIZES.small else "",
			"selected": id == _wood, "tooltip": "Stamp %s made of %s" % [String(item.name).to_lower(), name.to_lower()]})}])
	_refusal.text = String(item.refusal)
	_refusal.visible = not _refusal.text.is_empty()
	_show_actions()


func _show_actions() -> void:
	var active: bool = controller != null and controller.is_active()
	stamp_button.disabled = active or selected_key.is_empty() or not String(_items.get(selected_key, {}).get("refusal", "x")).is_empty()
	# While stamping, the tool bar has the keys, what each stamp did, and Done.
	if active: _hint.text = ""
	elif selected_key.is_empty(): _hint.text = "Choose an item, then Stamp, then click a floor."


func _on_active_changed(_active: bool) -> void:
	_show_actions()


func _on_stamped(key: String, _count: int, _floor: Vector3i) -> void:
	recent.erase(key)
	recent.push_front(key)
	recent.resize(mini(recent.size(), int(UIRegistry.get_item_stamper().get("recent", 8))))
	_save_recent()
	_show_grid()


# ── Recent ────────────────────────────────────────────────────────────────────

func _load_recent() -> void:
	var file := ConfigFile.new()
	if file.load(RECENT_PATH) != OK: return
	for key: Variant in file.get_value("stamper", "recent", []):
		if _items.has(String(key)): recent.append(String(key))


func _save_recent() -> void:
	var file := ConfigFile.new()
	file.set_value("stamper", "recent", recent)
	var error := file.save(RECENT_PATH)
	if error != OK: push_warning("ItemStamperPanel: could not keep the recent items: " + error_string(error))


# ── Sizes ─────────────────────────────────────────────────────────────────────

func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	_size = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	var s := _size
	grid.tile_size = float(s.tile)
	grid.gap = float(s.gap)
	grid.heading_size = int(s.heading)
	grid.caption_size = int(s.label)
	woods.tile_size = float(s.wood)
	woods.caption_size = int(s.label)
	_left.custom_minimum_size.x = int(s.per_row) * (float(s.tile) + float(s.gap)) + float(s.gap) + 30.0
	search.custom_minimum_size.x = float(s.tile) * 2.6
	search.add_theme_font_size_override("font_size", int(s.word))
	_intro.add_theme_font_size_override("font_size", int(s.label))
	_card_scroll.custom_minimum_size.x = float(s.card)
	_title.add_theme_font_size_override("font_size", int(s.title))
	_id.add_theme_font_size_override("font_size", int(s.label))
	_picture.custom_minimum_size = Vector2.ONE * float(s.picture)
	_about.add_theme_font_size_override("font_size", int(s.body))
	_about.custom_minimum_size.x = float(s.card) - 40.0
	for label: Label in [_wood_heading, _amount_heading, _hint]: label.add_theme_font_size_override("font_size", int(s.label))
	_refusal.add_theme_font_size_override("font_size", int(s.body))
	_value.add_theme_font_size_override("font_size", int(s.value))
	_value.custom_minimum_size.x = float(s.value) * 1.6
	for child: Node in _amount_row.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2.ONE * float(s.action) * 0.7
			(child as Button).add_theme_font_size_override("font_size", int(s.word))
	stamp_button.custom_minimum_size.y = float(s.action)
	stamp_button.add_theme_font_size_override("font_size", int(s.verb))
	_show_grid()
	_show_card()
	# The columns are as tall as the size asks, as far as the room above the dock allows.
	_columns.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	_columns.custom_minimum_size.y = minf(maxf(200.0, _dock_top - 12.0 - chrome), float(s.columns))
	window.reset_size()
	window.clamp_to_viewport()
