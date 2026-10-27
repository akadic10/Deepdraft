extends MarginContainer

## The Blueprints window (doc 273, Phase 3), laid out as Place:
## - every blueprint as a picture: the starters, then the player's own (BlueprintLibrary);
## - the chosen one on the paper card: its name (a field to rename the player's own), its size,
##   its picture, and each material's blocks against the stock, in rust where it runs short;
## - Place starts placing it (BlueprintController), Rename keeps the name typed, Delete (the
##   player's own, pressed twice) removes its file, and Open folder shows where the files are
##   kept, to share them or drop a friend's in.
## Files the library could not read are named at the bottom, each with why. Opening the window
## reads the folder again. Sizes follow the screen's height; the window fits above the dock.
signal place_requested(id: String)

const Grid = preload("res://scripts/ui/PictureGrid.gd")
const Work = preload("res://scripts/components/ConstructionWork.gd")
const INK := UITheme.CATALOG_INK
const INK_SOFT := UITheme.CATALOG_MUTED
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Place's sizes by the screen's height: large from 1300 px tall, small below 650 px.
const SIZES := {
	"large": {"tile": 110, "gap": 14, "per_row": 5, "card": 560, "picture": 260, "title": LARGE.name, "body": LARGE.body,
		"label": LARGE.small, "heading": LARGE.heading, "action": 72, "verb": LARGE.heading, "columns": 1000},
	"medium": {"tile": 80, "gap": 10, "per_row": 5, "card": 400, "picture": 170, "title": MEDIUM.name, "body": MEDIUM.body,
		"label": MEDIUM.small, "heading": MEDIUM.heading, "action": 52, "verb": MEDIUM.heading, "columns": 620},
	"small": {"tile": 56, "gap": 8, "per_row": 4, "card": 300, "picture": 110, "title": SMALL.name, "body": SMALL.body,
		"label": SMALL.small, "heading": SMALL.heading, "action": 40, "verb": SMALL.heading, "columns": 400},
}

var controller: Node
var window: UIWindow
## The chosen blueprint's id, "" before one is chosen.
var selected := ""
var grid: Grid
var name_field: LineEdit
var place_button: Button
var rename_button: Button
var delete_button: Button
var folder_button: Button
var _size: Dictionary = SIZES.medium
var _dock_top := 600.0
var _deleting := false
var _columns: HBoxContainer
var _intro: Label
var _left: PanelContainer
var _refused: Label
var _card_scroll: ScrollContainer
var _card: PanelContainer
var _measure: Label
var _origin: Label
var _picture: TextureRect
var _materials: Label
var _hint: Label


func _init() -> void:
	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 10)
	add_theme_constant_override("margin_top", 8)
	add_theme_constant_override("margin_bottom", 10)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	add_child(_columns)
	_columns.add_child(_build_grid())
	_columns.add_child(_build_card())


func _ready() -> void:
	BlueprintLibrary.changed.connect(_show)
	get_viewport().size_changed.connect(func(): if is_visible_in_tree(): _fit())
	visibility_changed.connect(func():
		if not is_visible_in_tree(): return
		BlueprintLibrary.rescan()
		_fit.call_deferred())
	_show()


## The tool this window drives: Place is off while it places.
func bind_controller(tool: Node) -> void:
	controller = tool
	if not controller.tool_active_changed.is_connected(_on_active_changed):
		controller.tool_active_changed.connect(_on_active_changed)
	_show_actions()


func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()


## Shows a blueprint; with `naming`, its name field takes the keys, all of it chosen, as after
## Copy.
func select(id: String, naming := false) -> void:
	selected = id
	_deleting = false
	_show()
	if naming and name_field.editable:
		name_field.grab_focus()
		name_field.select_all()


# ── Building ──────────────────────────────────────────────────────────────────

func _build_grid() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_intro = _text("Pick a blueprint, then Place. Copy keeps what you build as one.", MEDIUM.body, UITheme.HEARTH_MUTED)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_intro)
	_left = PanelContainer.new()
	_left.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	grid = Grid.new()
	grid.family = UIRegistry.get_icon_family_color("work")
	grid.heading_display = true
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.item_pressed.connect(func(id: String): select(id))
	list.add_child(grid)
	_refused = _text("", MEDIUM.body, UITheme.TAG_TONES.blocked[0])
	_refused.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_refused)
	return column


func _build_card() -> Control:
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
	name_field = LineEdit.new()
	name_field.name = "Name"
	name_field.max_length = BlueprintLibrary.MAX_NAME
	name_field.placeholder_text = "Name this blueprint"
	name_field.text_submitted.connect(func(_text: String): _rename())
	column.add_child(name_field)
	_measure = _text("", MEDIUM.body, INK_SOFT)
	column.add_child(_measure)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_picture)
	_materials = _text("", MEDIUM.lead, INK)
	_materials.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_materials)
	_origin = _text("", MEDIUM.body, INK_SOFT)
	_origin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_origin)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	side.add_child(actions)
	place_button = _action("Place", true, "Then click where it goes; R turns it")
	place_button.pressed.connect(func(): if not selected.is_empty(): place_requested.emit(selected))
	actions.add_child(place_button)
	rename_button = _action("Rename", false, "Keeps the name typed above")
	rename_button.pressed.connect(_rename)
	actions.add_child(rename_button)
	delete_button = _action("Delete", false, "Removes this blueprint's file; press twice")
	delete_button.pressed.connect(_delete)
	actions.add_child(delete_button)
	folder_button = _action("Open folder", false, "Where your blueprints are kept: copy a file to share one, drop a friend's in")
	folder_button.pressed.connect(BlueprintLibrary.open_folder)
	actions.add_child(folder_button)
	_hint = _text("", MEDIUM.body, UITheme.HEARTH_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_hint)
	return side


func _action(text: String, primary: bool, tooltip: String) -> Button:
	var button := Button.new()
	button.name = text.to_pascal_case()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if primary else Control.SIZE_SHRINK_BEGIN
	UITheme.apply_hearth_button(button, primary)
	return button


func _text(text: String, font_size: int, color: Color, display := false) -> Label:
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, display, font_size, color)
	return label


# ── Showing ───────────────────────────────────────────────────────────────────

func _show() -> void:
	if grid == null: return
	if BlueprintLibrary.get_blueprint(selected).is_empty():
		var all := BlueprintLibrary.blueprints()
		selected = String(all[0].id) if not all.is_empty() else ""
	var starters: Array = []
	var own: Array = []
	for blueprint: Dictionary in BlueprintLibrary.blueprints():
		var picture: Texture2D = BlueprintLibrary.picture(String(blueprint.id))
		var tile := {"id": String(blueprint.id), "picture": picture, "text": "" if picture != null else String(blueprint.name),
			"caption": String(blueprint.name) if _size != SIZES.small else "", "selected": blueprint.id == selected,
			"tooltip": "%s · %s" % [blueprint.name, _measure_text(blueprint.size)]}
		(starters if blueprint.starter else own).append(tile)
	var groups: Array = [{"id": "starters", "title": "Starters", "items": starters}]
	if not own.is_empty(): groups.append({"id": "own", "title": "Yours", "items": own})
	grid.show_groups(groups)
	var refused := BlueprintLibrary.refused()
	_refused.visible = not refused.is_empty()
	_refused.text = "Not read from the folder:\n" + "\n".join(refused)
	_show_card()


func _show_card() -> void:
	var blueprint := BlueprintLibrary.get_blueprint(selected)
	_card.visible = not blueprint.is_empty()
	if blueprint.is_empty():
		_show_actions()
		return
	if not name_field.has_focus(): name_field.text = String(blueprint.name)
	name_field.editable = not blueprint.starter
	_measure.text = _measure_text(blueprint.size)
	_picture.texture = BlueprintLibrary.picture(selected)
	_picture.visible = _picture.texture != null
	var lines: Array[String] = []
	var short := false
	for good: Dictionary in BlueprintLibrary.goods(blueprint.blocks):
		var need: int = int(good.count) * int(BlockRegistry.get_construction_def(good.kind).get("cost", 1))
		var stock := 0
		for item: String in BlockRegistry.construction_goods(good.kind, good.wood): stock += StockpileManager.get_available_total(item)
		lines.append("%s · %d %s · %d in stock" % [Work.type_name(good.kind, good.wood), need, Work.good_words(good.kind, good.wood, need), stock])
		short = short or need > stock
	_materials.text = "\n".join(lines)
	_materials.add_theme_color_override("font_color", UITheme.TAG_TONES.blocked[2] if short else INK)
	_origin.text = "A starter blueprint." if blueprint.starter else "Yours, kept as %s." % String(blueprint.path).get_file()
	_show_actions()


static func _measure_text(size: Vector3i) -> String:
	return "%d × %d · %d tall" % [size.x, size.z, size.y]


func _show_actions() -> void:
	var blueprint := BlueprintLibrary.get_blueprint(selected)
	var placing: bool = controller != null and controller.is_placing()
	place_button.disabled = blueprint.is_empty()
	rename_button.disabled = blueprint.is_empty() or blueprint.starter
	delete_button.disabled = blueprint.is_empty() or blueprint.starter
	delete_button.text = "Delete for good" if _deleting else "Delete"
	UITheme.apply_hearth_button(delete_button, _deleting)
	_hint.text = "Click where it goes; R turns it, Esc or Done ends." if placing else ""


func _on_active_changed(_active: bool) -> void:
	_show_actions()


func _rename() -> void:
	var renamed := BlueprintLibrary.rename(selected, name_field.text)
	if not renamed.is_empty(): selected = renamed
	name_field.release_focus()
	_show()


func _delete() -> void:
	if not _deleting:
		_deleting = true
		_show_actions()
		return
	_deleting = false
	if BlueprintLibrary.delete(selected): selected = ""
	_show()


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
	_left.custom_minimum_size.x = int(s.per_row) * (float(s.tile) + float(s.gap)) + float(s.gap) + 30.0
	_intro.add_theme_font_size_override("font_size", int(s.label))
	_intro.custom_minimum_size.x = _left.custom_minimum_size.x
	_refused.add_theme_font_size_override("font_size", int(s.label))
	_card_scroll.custom_minimum_size.x = float(s.card)
	name_field.add_theme_font_size_override("font_size", int(s.title))
	_measure.add_theme_font_size_override("font_size", int(s.label))
	_picture.custom_minimum_size = Vector2.ONE * float(s.picture)
	_materials.add_theme_font_size_override("font_size", int(s.body))
	_materials.custom_minimum_size.x = float(s.card) - 40.0
	_origin.add_theme_font_size_override("font_size", int(s.label))
	_hint.add_theme_font_size_override("font_size", int(s.label))
	for button: Button in [place_button, rename_button, delete_button, folder_button]:
		button.custom_minimum_size.y = float(s.action)
		button.add_theme_font_size_override("font_size", int(s.verb) if button == place_button else int(s.body))
	_show()
	# The columns are as tall as the size asks, as far as the room above the dock allows.
	_columns.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	_columns.custom_minimum_size.y = minf(maxf(200.0, _dock_top - 12.0 - chrome), float(s.columns))
	window.reset_size()
	window.clamp_to_viewport()
