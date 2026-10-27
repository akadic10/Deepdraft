extends Control

## The compact object panel (doc 260) beside the dock, in Deepdraft's own Hearthblock style
## (doc 259, option A): the hover card's hearth slab in voxel cells, with a band in the
## selected kind's family colour across its top. The band holds the name and the badge on
## a stone chip; below sit the picture on a family tile, a flavour line, the status on a
## tag in its tone and icon actions. A longer description shows in full on hovering the
## flavour line. A dwarf shows a live portrait on its tile, its profession and what it is
## doing instead (doc 260 phase 3). ObjectExplorerController owns selection, refresh and
## actions; this panel only presents a provider's data. Nodes are built once and updated
## in place; action tiles are rebuilt only when the object's actions change.
signal action_requested(action_id: String)

const ActionTile = preload("res://scripts/ui/DockIconButton.gd")
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const ObjectPortrait = preload("res://scripts/ui/ObjectPortrait.gd")
const DOCK_GAP := 12.0
const MARGIN := 24.0
const WIDE_SCREEN := 1200.0   # the dock's own breakpoint between its two icon sizes
const POPUP_LAYER := 30       # the owner list sits with the hover cards
const BAND_BELOW := 10.0      # the band reaches this far below the name row
# Sizes on wide and on compact screens. `cell` is the slab's voxel cell, `chip_cell` the
# badge chip's and the tags'.
const METRICS := {
	true: {"cell": 4, "chip_cell": 3, "inset": 20.0, "top": 16.0, "bottom": 24.0, "name_font": 30, "name_outline": 6,
		"name_max": 900.0, "badge_font": 24, "badge_icon": 30.0, "picture": 84.0, "portrait": 112.0, "tile_pad": 8.0,
		"tile": 72.0, "dev_tile": 44.0, "text": 340.0, "flavour": 18, "status": 17,
		"profession_tile": 38.0, "profession_font": 21},
	false: {"cell": 3, "chip_cell": 2, "inset": 14.0, "top": 12.0, "bottom": 18.0, "name_font": 24, "name_outline": 5,
		"name_max": 600.0, "badge_font": 19, "badge_icon": 24.0, "picture": 60.0, "portrait": 84.0, "tile_pad": 6.0,
		"tile": 56.0, "dev_tile": 36.0, "text": 260.0, "flavour": 15, "status": 15,
		"profession_tile": 30.0, "profession_font": 17},
}
const FLAVOUR_LINES := 3
const LINE_SPACING := 2
const PRIMARY_SCALE := 1.15     # the primary action's tile, such as Character sheet

# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
var _frame: PanelContainer
var _frame_art: Texture2D   # kept here: the canvas holds only the texture's RID
var _frame_art_key := ""
var _heading: HBoxContainer
var _name: Label
var _badge: PanelContainer
var _badge_icon: TextureRect
var _badge_value: Label
var _picture_tile: PanelContainer
var _picture: TextureRect
var _object_viewport: SubViewport
var _object_model: Node3D
var _portrait_subject: Node3D
var _badge_art := ""
var _text: VBoxContainer
var _flavour: Label
var _status_line: HBoxContainer
var _status_tag: PanelContainer
var _status: Label
var _actions: HBoxContainer
var _dev_actions: VBoxContainer
var _dwarf := false
var _agent: DwarfAgent
var _portrait_rect: TextureRect
var _portrait_viewport: SubViewport
var _portrait_model: Node3D
var _profession_row: HBoxContainer
var _profession_tile: Panel
var _profession_icon: TextureRect
var _profession_label: Label
var _profession_path := ""
var _activity_row: HBoxContainer
var _activity_tag: PanelContainer
var _concern_icon: TextureRect
var _activity_label: Label
var _popups: CanvasLayer
var _owners: PanelContainer
var _owners_title: Label
var _owner_rows: VBoxContainer
var _owners_scroll: ScrollContainer
var _owners_anchor: Control
var _owners_art: Texture2D   # kept here: the canvas holds only the texture's RID
var _owners_art_key := ""
var _action_data: Array = []
var _title := ""
var _tone := "fine"
var _family := ""
var _family_color := Color.TRANSPARENT
var _tile_boxes: Dictionary = {}   # family colour -> the picture tile's style
var _picture_path := ""
var _dock_rect := Rect2()
var _reserved: Array[Rect2] = []
var _wide := true
var _metrics: Dictionary = METRICS[true]


func _init() -> void:
	name = "CompactObjectPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.shared_theme()
	_frame = PanelContainer.new()
	_frame.draw.connect(_draw_frame)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks on the panel never reach the world
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_frame.add_child(column)
	# The band: the name, never cut short, and the badge on its stone chip.
	_heading = HBoxContainer.new()
	_heading.add_theme_constant_override("separation", 16)
	column.add_child(_heading)
	_name = Label.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip, for a name past the widest band
	_heading.add_child(_name)
	_badge = PanelContainer.new()
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip; the wheel still reaches the frame
	_heading.add_child(_badge)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 8)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(chip)
	_badge_icon = TextureRect.new()
	_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_badge_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_badge_icon)
	_badge_value = Label.new()
	_badge_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(_badge_value)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	# The picture, a live portrait or a dwarf's portrait, on a tile in the family colour, as
	# the dock's icons sit on theirs.
	_picture_tile = PanelContainer.new()
	_picture_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_picture_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_picture_tile)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_tile.add_child(_picture)
	_portrait_rect = TextureRect.new()
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_tile.add_child(_portrait_rect)
	_text = VBoxContainer.new()
	_text.add_theme_constant_override("separation", 8)
	_text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_text)
	_flavour = Label.new()
	_flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flavour.max_lines_visible = FLAVOUR_LINES
	_flavour.add_theme_constant_override("line_spacing", LINE_SPACING)
	_flavour.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_flavour.mouse_filter = Control.MOUSE_FILTER_PASS   # for its tooltip; clicks still stop at the frame
	_text.add_child(_flavour)
	# The status on a tag in its tone; the line keeps the tag at its own width.
	_status_line = HBoxContainer.new()
	_text.add_child(_status_line)
	_status_tag = PanelContainer.new()
	_status_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_line.add_child(_status_tag)
	_status = Label.new()
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_tag.add_child(_status)
	_build_dwarf_rows()
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_actions)
	# DEV actions stand apart at the right edge, on their own DEV tiles.
	_dev_actions = VBoxContainer.new()
	_dev_actions.add_theme_constant_override("separation", 4)
	_dev_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dev_actions)
	_popups = CanvasLayer.new()
	_popups.layer = POPUP_LAYER
	add_child(_popups)
	_build_owner_list()
	# Scrolling over the panel never zooms the world: Godot passes wheel events through
	# a control unless it accepts them.
	_frame.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_frame.accept_event())
	_set_dwarf(false)
	_apply_metrics()
	visibility_changed.connect(func():
		if not visible: _close_owner_list())


func _ready() -> void:
	# Deferred, so the dock has refitted and handed over its new place first.
	get_viewport().size_changed.connect(_fit, CONNECT_DEFERRED)


## Show a provider's explorer data (title, rows, details, actions and the optional
## compact fields family, picture or portrait, badge, status and flavour). Safe to call
## on every refresh. `portrait` names a world node to show as a live still, rendered once.
func show_data(data: Dictionary) -> void:
	var layout_changed := false
	var title := String(data.get("title", "Object"))
	if title != _title:
		_title = title
		_name.text = title
		_size_name()
		layout_changed = true
	var dwarf := String(data.get("presentation", "")) == "dwarf"
	if dwarf != _dwarf:
		_set_dwarf(dwarf)
		layout_changed = true
	_set_family(String(data.get("family", "people" if dwarf else "system")))
	if dwarf:
		_show_dwarf_rows(data)
	var portrait: Variant = data.get("portrait")
	if not dwarf and is_instance_valid(portrait) and portrait is Node3D:
		if portrait != _portrait_subject:
			_show_object_portrait(portrait)
			layout_changed = true
	else:
		var picture := String(data.get("picture", ""))
		if picture != _picture_path:
			_clear_object_portrait()
			_picture_path = picture
			_picture.texture = load(picture) if not picture.is_empty() and ResourceLoader.exists(picture) else null
			layout_changed = true
	var tile_shown := dwarf or _picture.texture != null
	if _picture_tile.visible != tile_shown: layout_changed = true
	_picture_tile.visible = tile_shown
	var badge: Dictionary = data.get("badge", {})
	if _badge.visible == badge.is_empty(): layout_changed = true
	_badge.visible = not badge.is_empty()
	if _badge.visible:
		# A badge may carry its own picture, such as the fruit a tree is ready to give.
		var art := String(badge.get("icon", badge.get("kind", "")))
		if art != _badge_art:
			_badge_art = art
			_badge_icon.texture = load(art) if art.begins_with("res://") and ResourceLoader.exists(art) else UIRegistry.get_compact_badge(art)
		_badge_icon.visible = _badge_icon.texture != null
		if _badge_value.text != String(badge.get("value", "")): layout_changed = true
		_badge_value.text = String(badge.get("value", ""))
		_badge.tooltip_text = String(badge.get("tooltip", ""))
	var status: Dictionary = data.get("status", {})
	var status_text := String(status.get("text", _row_value(data.get("rows", []), "Status")))
	if status_text != _status.text:
		_status.text = status_text
		_size_tag_text(_status, 0.0)
	var tone := String(status.get("tone", "fine"))
	if not UITheme.TAG_TONES.has(tone): tone = "fine"
	if tone != _tone:
		_tone = tone
		_style_status()
	var details := String(data.get("details", "")).strip_edges()
	_flavour.text = String(data.get("flavour", _first_sentence(details)))
	# The rest of a longer description, often how to put the object to use, shows on hover.
	_flavour.tooltip_text = details if details != _flavour.text else ""
	var actions: Array = UIRegistry.shown_actions(data.get("actions", []))
	if actions != _action_data:
		_action_data = actions.duplicate(true)
		_rebuild_actions()
		layout_changed = true
	if layout_changed:
		_fit()
		_fit.call_deferred()   # again once the containers have sorted the new content


## The shown name, as the band says it.
func get_title() -> String:
	return _name.text


## Forget the shown object: popups and the portrait belong to it. The next show_data
## starts afresh.
func clear_subject() -> void:
	_close_owner_list()
	_title = ""
	_agent = null
	if is_instance_valid(_portrait_model): _portrait_model.free()
	_portrait_model = null
	_clear_object_portrait()


## Sit beside the dock (doc 260): left of it and bottom-aligned when there is room,
## otherwise above its left end, clear of `reserved` (the slice tower and the X-ray
## options while they are open). Without a dock the panel keeps the bottom-left corner.
func fit_beside_dock(dock_rect: Rect2, reserved: Array[Rect2] = []) -> void:
	_dock_rect = dock_rect
	_reserved = reserved
	_fit()


## The tile for a shown action id, or null.
func get_action_button(id: String) -> Button:
	for box: Container in [_actions, _dev_actions]:
		for button: Button in box.get_children():
			if String(button.get_meta("action_id", "")) == id: return button
	return null


func _fit() -> void:
	if not is_inside_tree(): return
	var wide := get_viewport_rect().size.x >= WIDE_SCREEN
	if wide != _wide:
		_wide = wide
		_metrics = METRICS[wide]
		_apply_metrics()
	_frame.reset_size()
	_frame.position = Vector2.ZERO
	size = _frame.size
	var viewport := get_viewport_rect().size
	var spot := Vector2(MARGIN, viewport.y - MARGIN - size.y)
	if _dock_rect.has_area():
		spot = Vector2(_dock_rect.position.x - DOCK_GAP - size.x, _dock_rect.end.y - size.y)
		if spot.x < MARGIN:
			spot = Vector2(clampf(_dock_rect.position.x, MARGIN, maxf(MARGIN, viewport.x - MARGIN - size.x)),
				_dock_rect.position.y - DOCK_GAP - size.y)
			for rect: Rect2 in _reserved:
				var room := rect.grow(DOCK_GAP)
				if not Rect2(spot, size).intersects(room): continue
				spot.x = maxf(MARGIN, room.position.x - size.x)   # slide left first, then rise above it
				if Rect2(spot, size).intersects(room): spot.y = room.position.y - size.y
	position = spot.round()
	_place_owner_list()


func _apply_metrics() -> void:
	var m := _metrics
	var margins := StyleBoxEmpty.new()
	margins.content_margin_left = m.inset
	margins.content_margin_right = m.inset
	margins.content_margin_top = m.top
	margins.content_margin_bottom = m.bottom
	_frame.add_theme_stylebox_override("panel", margins)
	UITheme.format_label(_name, true, m.name_font, UITheme.CARD_TITLE, m.name_outline)
	_name.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_size_name()
	_badge.add_theme_stylebox_override("panel", UITheme.cell_style("chip", m.chip_cell))
	_badge_icon.custom_minimum_size = Vector2.ONE * m.badge_icon
	UITheme.format_label(_badge_value, true, m.badge_font, UITheme.KEYCAP_INK)
	_picture.custom_minimum_size = Vector2.ONE * m.picture
	_portrait_rect.custom_minimum_size = Vector2.ONE * m.portrait
	_tile_boxes.clear()
	_style_tile()
	UITheme.format_label(_flavour, false, m.flavour, UITheme.CARD_TEXT)
	_flavour.custom_minimum_size.x = m.text
	_style_status()
	_profession_tile.custom_minimum_size = Vector2.ONE * m.profession_tile
	UITheme.format_label(_profession_label, true, m.profession_font, UITheme.CARD_TITLE)
	_activity_tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_fine", m.chip_cell))
	UITheme.format_label(_activity_label, false, m.status, UITheme.tag_ink("fine"))
	_size_activity()
	_concern_icon.custom_minimum_size = Vector2.ONE * m.profession_tile * 0.8
	# Room for every flavour line and the status tag from the start, so the panel never
	# grows a frame later.
	var tag: StyleBox = UITheme.cell_style("tag_fine", m.chip_cell)
	_text.custom_minimum_size = Vector2(m.text, (UITheme.body_font().get_height(m.flavour) + LINE_SPACING) * FLAVOUR_LINES
		+ 8.0 + UITheme.body_font().get_height(m.status) + tag.content_margin_top + tag.content_margin_bottom)
	_size_tiles()
	_frame.queue_redraw()


## The name is never cut short: the band grows with it, up to the widest band.
func _size_name() -> void:
	var width: float = UITheme.display_font().get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _metrics.name_font).x + 2.0 * _metrics.name_outline
	_name.custom_minimum_size.x = minf(width, _metrics.name_max)
	_name.tooltip_text = _name.text if width > _metrics.name_max else ""


func _style_status() -> void:
	_status_tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + _tone, _metrics.chip_cell))
	UITheme.format_label(_status, false, _metrics.status, UITheme.tag_ink(_tone))
	_size_tag_text(_status, 0.0)


## A tag holds its whole text, up to the text column's width; only longer text is trimmed.
## Trimming labels report no minimum width of their own, so the tag needs this to show.
func _size_tag_text(label: Label, beside: float) -> void:
	var tag: StyleBox = UITheme.cell_style("tag_fine", _metrics.chip_cell)
	var room: float = _metrics.text - tag.content_margin_left - tag.content_margin_right - beside
	var width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x
	label.custom_minimum_size.x = minf(ceilf(width), room)


## The family names the band's and the picture tile's colour: settlement, work or people
## (doc 23). Unknown or missing families take the system colour.
func _set_family(family: String) -> void:
	if family == _family: return
	_family = family
	_family_color = UIRegistry.get_icon_family_color(family)
	if _family_color.a == 0.0: _family_color = UIRegistry.get_icon_family_color("system")
	_style_tile()
	_frame.queue_redraw()


func _style_tile() -> void:
	if _family_color.a == 0.0: return
	var key := _family_color.to_html()
	if not _tile_boxes.has(key):
		var box := UITheme.icon_tile_style(_family_color).duplicate() as StyleBoxTexture
		box.set_content_margin_all(_metrics.tile_pad)
		_tile_boxes[key] = box
	_picture_tile.add_theme_stylebox_override("panel", _tile_boxes[key])


## The slab in voxel cells, with the family band behind the name row (doc 259, option A).
func _draw_frame() -> void:
	var cell: int = _metrics.cell
	var w := ceili(_frame.size.x / cell)
	var h := ceili(_frame.size.y / cell)
	if w < 6 or h < 6: return
	var top: float = _frame.get_theme_stylebox("panel").content_margin_top
	var header := ceili((top + _heading.get_combined_minimum_size().y + BAND_BELOW) / cell)
	var key := "%d %d %d %d %s" % [w, h, header, cell, _family_color.to_html()]
	if key != _frame_art_key:
		_frame_art_key = key
		var art := UITheme.cell_slab(w, h, UITheme.CARD_FACE, UITheme.CARD_TOP, UITheme.CARD_SKIRT,
			UITheme.CARD_OUTLINE, 2, 2, _family_color, header)
		art.resize(w * cell, h * cell, Image.INTERPOLATE_NEAREST)
		_frame_art = UITheme.cell_texture(art)
	_frame.draw_texture_rect(_frame_art, Rect2(Vector2.ZERO, _frame_art.get_size()), false)


func _size_tiles() -> void:
	for button: Button in _actions.get_children():
		var side: float = _metrics.tile * (PRIMARY_SCALE if bool(button.get_meta("primary", false)) else 1.0)
		button.custom_minimum_size = Vector2.ONE * side if button.icon != null else Vector2(0, _metrics.tile * 0.6)
	for button: Button in _dev_actions.get_children():
		button.custom_minimum_size = Vector2.ONE * _metrics.dev_tile


# ── Actions ─────────────────────────────────────────────────────────────────────

func _rebuild_actions() -> void:
	_close_owner_list()
	for box: Container in [_actions, _dev_actions]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for action: Dictionary in _action_data:
		var id := String(action.get("id", ""))
		var dev := String(action.get("variant", "")) == "dev"
		var button := _make_tile(action, dev)
		if action.has("options"): button.pressed.connect(_toggle_owner_list.bind(action, button))
		else: button.pressed.connect(func(): action_requested.emit(id))
		(_dev_actions if dev else _actions).add_child(button)
	_dev_actions.visible = _dev_actions.get_child_count() > 0
	_size_tiles()


## A picture tile for an action: its own icon, the registry's picture for its id, or the
## DEV picture. An action without any picture keeps its words on a tan button.
func _make_tile(action: Dictionary, dev: bool) -> Button:
	var id := String(action.get("id", ""))
	var text := String(action.get("text", id))
	var art := UIRegistry.get_compact_action(id)
	var icon: Texture2D = UIRegistry.get_compact_dev_icon() if dev else art.get("icon")
	if action.has("icon") and not dev: icon = load(String(action.icon))
	var button: Button
	if icon == null:
		button = Button.new()
		button.text = text
		button.tooltip_text = String(art.get("tooltip", ""))
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.apply_tan_button(button)
	else:
		button = ActionTile.new()
		var hint := "A development shortcut, shown while the DEV switch is on." if dev else String(art.get("tooltip", ""))
		button.setup({"label": text, "tooltip": hint if not hint.is_empty() else text,
			"family": UIRegistry.get_compact_family(dev)}, icon)
		button.toggle_mode = false
	button.name = "Action_" + id.validate_node_name()
	button.set_meta("action_id", id)
	button.set_meta("primary", bool(action.get("primary", false)))
	button.disabled = bool(action.get("disabled", false))
	if bool(action.get("active", false)):
		# A running action, such as Follow, stays lit.
		button.toggle_mode = true
		button.set_pressed_no_signal(true)
	return button


## A live still of a world object in the picture slot (ObjectPortrait).
func _show_object_portrait(subject: Node3D) -> void:
	_clear_object_portrait()
	if _object_viewport == null: _object_viewport = ObjectPortrait.create_viewport(_picture)
	_object_model = ObjectPortrait.create_model(_object_viewport, subject)
	_portrait_subject = subject
	_picture.texture = _object_viewport.get_texture()
	_picture_path = "portrait"


func _clear_object_portrait() -> void:
	if is_instance_valid(_object_model): _object_model.free()
	_object_model = null
	_portrait_subject = null
	if _picture_path == "portrait":
		_picture_path = ""
		_picture.texture = null


# ── Dwarf ───────────────────────────────────────────────────────────────────────

## The dwarf's rows in the text column: the profession on its tile, then what the dwarf
## is doing on a moss tag, with a concern icon when one needs the player.
func _build_dwarf_rows() -> void:
	_profession_row = HBoxContainer.new()
	_profession_row.add_theme_constant_override("separation", 10)
	_text.add_child(_profession_row)
	_profession_tile = Panel.new()
	_profession_tile.add_theme_stylebox_override("panel", UITheme.icon_tile_style(UIRegistry.get_icon_family_color("people")))
	_profession_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profession_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profession_row.add_child(_profession_tile)
	_profession_icon = TextureRect.new()
	_profession_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profession_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_profession_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_profession_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profession_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profession_icon.offset_left = 3
	_profession_icon.offset_top = 3
	_profession_icon.offset_right = -3
	_profession_icon.offset_bottom = -3
	_profession_tile.add_child(_profession_icon)
	_profession_label = Label.new()
	_profession_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profession_label.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip names the tool
	_profession_row.add_child(_profession_label)
	_activity_row = HBoxContainer.new()
	_activity_row.add_theme_constant_override("separation", 8)
	_text.add_child(_activity_row)
	_concern_icon = TextureRect.new()
	_concern_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_concern_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_concern_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_concern_icon.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip explains the concern
	_activity_row.add_child(_concern_icon)
	_activity_tag = PanelContainer.new()
	_activity_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_activity_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_activity_row.add_child(_activity_tag)
	_activity_label = Label.new()
	_activity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_activity_label.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip explains the activity
	_activity_tag.add_child(_activity_label)


func _set_dwarf(on: bool) -> void:
	_dwarf = on
	for node: Control in [_portrait_rect, _profession_row, _activity_row]: node.visible = on
	for node: Control in [_picture, _flavour, _status_line]: node.visible = not on


func _show_dwarf_rows(data: Dictionary) -> void:
	var agent: DwarfAgent = data.get("agent")
	if agent != _agent:
		_agent = agent
		_refresh_portrait()
	var icon := String(data.get("profession_icon", ""))
	if icon != _profession_path:
		_profession_path = icon
		_profession_icon.texture = load(icon) if not icon.is_empty() and ResourceLoader.exists(icon) else null
	_profession_label.text = String(data.get("profession", ""))
	_profession_label.tooltip_text = "Tool · " + String(data.get("equipment", "")).get_slice("\n", 0)
	_activity_label.text = String(data.get("activity", ""))
	var destination := String(data.get("destination", ""))
	_activity_label.tooltip_text = String(data.get("explanation", "")) + ("" if destination in ["", "No destination"] else "\n" + destination)
	var concern: Dictionary = data.get("concern", {})
	_concern_icon.visible = not concern.is_empty()
	if not concern.is_empty():
		_concern_icon.texture = UIRegistry.get_need_icon(String(concern.kind))
		_concern_icon.tooltip_text = "%s · %s\n%s" % [concern.title, concern.reason, concern.help]
	_size_activity()


func _size_activity() -> void:
	_size_tag_text(_activity_label, _concern_icon.custom_minimum_size.x + 8.0 if _concern_icon.visible else 0.0)


## The portrait renders once per dwarf, from copies of its head and body (DwarfPortrait).
func _refresh_portrait() -> void:
	if is_instance_valid(_portrait_model): _portrait_model.free()
	_portrait_model = null
	if not is_instance_valid(_agent) or not is_inside_tree(): return
	if _portrait_viewport == null: _portrait_viewport = Portrait.create_viewport(_portrait_rect, Vector2i(192, 224))
	_portrait_model = Portrait.create_model(_portrait_viewport, _agent)


# ── Owner list (Assign owner) ───────────────────────────────────────────────────

func _build_owner_list() -> void:
	_owners = PanelContainer.new()
	_owners.visible = false
	_owners.theme = UITheme.shared_theme()
	var margins := StyleBoxEmpty.new()
	margins.content_margin_left = 20
	margins.content_margin_right = 20
	margins.content_margin_top = 16
	margins.content_margin_bottom = 22
	_owners.add_theme_stylebox_override("panel", margins)
	_owners.draw.connect(_draw_owner_list)
	_owners.mouse_filter = Control.MOUSE_FILTER_STOP
	_popups.add_child(_owners)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_owners.add_child(column)
	_owners_title = Label.new()
	UITheme.format_label(_owners_title, true, MEDIUM.title, UITheme.CARD_TITLE, 5)
	_owners_title.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	column.add_child(_owners_title)
	_owners_scroll = ScrollContainer.new()
	_owners_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_owners_scroll.mouse_force_pass_scroll_events = false
	column.add_child(_owners_scroll)
	_owner_rows = VBoxContainer.new()
	_owner_rows.add_theme_constant_override("separation", 4)
	_owner_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owners_scroll.add_child(_owner_rows)


## The list is drawn as a hover card (doc 259, option C): the hearth slab, with the work
## family's colour behind its title, like the tile that opened it.
func _draw_owner_list() -> void:
	var cell := UITheme.CARD_CELL
	var w := ceili(_owners.size.x / cell)
	var h := ceili(_owners.size.y / cell)
	var top: float = _owners.get_theme_stylebox("panel").content_margin_top
	var header := ceili((top + _owners_title.get_combined_minimum_size().y + 12.0) / cell)
	var key := "%d %d %d" % [w, h, header]
	if key != _owners_art_key:
		_owners_art_key = key
		var family: Color = UIRegistry.get_icon_family_color(UIRegistry.get_compact_family())
		var art := UITheme.cell_slab(w, h, UITheme.CARD_FACE, UITheme.CARD_TOP, UITheme.CARD_SKIRT,
			UITheme.CARD_OUTLINE, 2, 2, family, header)
		art.resize(w * cell, h * cell, Image.INTERPOLATE_NEAREST)
		_owners_art = UITheme.cell_texture(art)
	_owners.draw_texture_rect(_owners_art, Rect2(Vector2.ZERO, _owners_art.get_size()), false)


func _toggle_owner_list(action: Dictionary, anchor: Control) -> void:
	if _owners.visible:
		_close_owner_list()
		return
	_owners_anchor = anchor
	_owners_title.text = String(action.get("text", "")).trim_suffix("…")
	for option: Dictionary in action.get("options", []):
		var row := _owner_row(option)
		_owner_rows.add_child(row)
		# A portrait renders only once its viewport is inside the tree.
		var agent: DwarfAgent = TaskManager.get_agent(int(option.get("dwarf_id", -1)))
		if is_instance_valid(agent):
			Portrait.create_model(Portrait.create_viewport(row.get_meta("portrait"), Vector2i(96, 112)), agent)
	_owners.show()
	_place_owner_list()


## One choice in the list: the dwarf's portrait and name, or the colony for "anyone".
func _owner_row(option: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Owner_" + String(option.get("id", "")).validate_node_name()
	button.set_meta("action_id", String(option.get("id", "")))
	button.custom_minimum_size.y = 60
	var selected := bool(option.get("selected", false))
	var hay: Color = UITheme.TAG_TONES.waiting[0]
	button.add_theme_stylebox_override("normal", UITheme.style(UITheme.CARD_TOP if selected else Color.TRANSPARENT,
		hay if selected else Color.TRANSPARENT, 2 if selected else 0, 0, 8, 4))
	button.add_theme_stylebox_override("hover", UITheme.style(UITheme.CARD_TOP, UITheme.CARD_TOP.lightened(0.25), 1, 0, 8, 4))
	button.add_theme_stylebox_override("pressed", button.get_theme_stylebox("hover"))
	button.add_theme_stylebox_override("focus", UITheme.focus_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	button.add_child(line)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(48, 56)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(portrait)
	button.set_meta("portrait", portrait)
	if int(option.get("dwarf_id", -1)) < 0: portrait.texture = load("res://assets/ui/icons/dwarves.png")
	var caption := Label.new()
	caption.text = String(option.get("text", ""))
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.format_label(caption, true, MEDIUM.lead, hay if selected else UITheme.CARD_TITLE)
	line.add_child(caption)
	button.custom_minimum_size.x = 80 + UITheme.display_font().get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var id := String(option.get("id", ""))
	button.pressed.connect(func():
		_close_owner_list()
		action_requested.emit(id))
	return button


func _place_owner_list() -> void:
	if not _owners.visible or not is_instance_valid(_owners_anchor): return
	var room := maxf(120.0, global_position.y - 24.0)
	_owners_scroll.custom_minimum_size.y = minf(_owner_rows.get_combined_minimum_size().y, room - 60.0)
	_owners.reset_size()
	var viewport := get_viewport_rect().size
	var anchor := _owners_anchor.get_global_rect()
	_owners.position = Vector2(clampf(anchor.get_center().x - _owners.size.x * 0.5, 8.0, maxf(8.0, viewport.x - _owners.size.x - 8.0)),
		maxf(8.0, global_position.y - _owners.size.y - 12.0)).round()


func _close_owner_list() -> void:
	if _owners == null: return
	_owners.hide()
	for child in _owner_rows.get_children():
		_owner_rows.remove_child(child)
		child.queue_free()


static func _row_value(rows: Array, row_name: String) -> String:
	for row: Array in rows:
		if String(row[0]) == row_name: return String(row[1])
	return ""


## The first sentence of a description, for the flavour line.
static func _first_sentence(text: String) -> String:
	var line := text.get_slice("\n", 0).strip_edges()
	for i in range(line.length() - 1):
		if line[i] in ".!?" and line[i + 1] == " ": return line.substr(0, i + 1)
	return line
