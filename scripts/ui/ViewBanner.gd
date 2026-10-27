extends PanelContainer

## The view banner (doc 23, "Views"): while a view changes how the world looks, a slab at
## the top centre names it, with one line on what it shows and how to leave. Tools name
## themselves at the bottom (the tool bar), views at the top. X-ray steps aside while a tool
## works, and its line with it; Appeal stays on. With both views on, each has its line.
## The words come from the views' entries in data/ui/time_slice.json. Toasts sit below
## it, and the mouse passes through. DockUI hosts it on the toast layer (24).
const KeyText = preload("res://scripts/ui/DockIconButton.gd")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## By screen height, as the toasts: large from 1300 px, small below 650. `top` matches theirs.
const SIZES := {
	"large": {"picture": 52.0, "name": LARGE.heading, "line": LARGE.body, "top": 28.0, "gap": 14, "type": LARGE},
	"medium": {"picture": 40.0, "name": MEDIUM.heading, "line": MEDIUM.body, "top": 22.0, "gap": 12, "type": MEDIUM},
	"small": {"picture": 30.0, "name": SMALL.heading, "line": SMALL.body, "top": 12.0, "gap": 8, "type": SMALL},
}
const VIEWS := ["appeal", "xray"]

var toasts: Control   # the toast stack, kept below the banner
var size_key := "medium"
var _controllers := {}   # view id → its controller
var _rows := {}   # view id → {row, picture, name, line}
var _list: VBoxContainer


func _ready() -> void:
	name = "ViewBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.toast_frame(UIRegistry.get_icon_family_color("system")))
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	var entries: Dictionary = UIRegistry.get_time_slice().get("buttons", {})
	for id: String in VIEWS:
		var entry: Dictionary = entries.get(id, {})
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(row)
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path := String(entry.get("icon", ""))
		if ResourceLoader.exists(path): picture.texture = load(path)
		var frame := UITheme.framed_picture(picture)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(frame)
		var words := VBoxContainer.new()
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_theme_constant_override("separation", 0)
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(words)
		var title := _label(String(entry.get("view_name", entry.get("label", id))))
		words.add_child(title)
		var key := KeyText.key_text(String(entry.get("key_action", "")))
		var line := _label("%s · %s" % [String(entry.get("view_line", "")), key + " or its button to leave" if not key.is_empty() else "Its button to leave"])
		words.add_child(line)
		_rows[id] = {"row": row, "picture": picture, "name": title, "line": line}
	get_viewport().size_changed.connect(_fit)
	_fit()


## Follows a view's controller: AppealViewController ("appeal") or XrayController ("xray").
func bind(id: String, controller: Node) -> void:
	if _controllers.get(id) == controller: return
	_controllers[id] = controller
	controller.changed.connect(refresh)
	refresh()


## Whether the view changes how the world looks now.
func is_showing(id: String) -> bool:
	var controller: Node = _controllers.get(id)
	if not is_instance_valid(controller): return false
	if id == "xray": return String(controller.mode) != "off" and not bool(controller.working)
	return bool(controller.active)


func refresh() -> void:
	if _list == null: return
	var any := false
	for id: String in VIEWS:
		var shown := is_showing(id)
		_rows[id].row.visible = shown
		any = any or shown
	visible = any
	_place.call_deferred()


func _fit() -> void:
	var height := get_viewport().get_visible_rect().size.y
	size_key = "large" if height >= 1300.0 else ("small" if height < 650.0 else "medium")
	var s: Dictionary = SIZES[size_key]
	_list.add_theme_constant_override("separation", s.gap)
	for row: Dictionary in _rows.values():
		row.row.add_theme_constant_override("separation", s.gap)
		row.picture.custom_minimum_size = Vector2.ONE * float(s.picture)
		UITheme.format_label(row.name, true, int(s.name), UITheme.CARD_TITLE, 5 if size_key == "large" else 4)
		row.name.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
		UITheme.format_label(row.line, false, int(s.line), UITheme.CARD_TEXT)
	_place.call_deferred()


## At the top centre, with the toasts below it.
func _place() -> void:
	if not is_inside_tree(): return
	var s: Dictionary = SIZES[size_key]
	reset_size()
	position = Vector2(roundf((get_viewport().get_visible_rect().size.x - size.x) * 0.5), float(s.top))
	if toasts != null and toasts.has_method("reserve_top"):
		toasts.reserve_top(size.y + float(s.gap) if visible else 0.0)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
