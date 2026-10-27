extends VBoxContainer

## Toasts (doc 23): each event as it lands in EventLog, and the player's own
## messages (saves, loads, the flag, slice hints), at most EventLog.toast_limit() at the
## top centre, newest on top. Each is the toast frame with a band in its tone: the
## people family for an event, rust for a warning or an error, moss for the player's own
## message. The mouse passes through. DockUI hosts it on the toast layer (24).

# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## By screen height, as the windows' sizes (doc 23): large from 1300 px, small below 650.
const SIZES := {
	"large": {"width": 760.0, "picture": 56.0, "text": LARGE.lead, "detail": LARGE.body, "gap": 10, "top": 28.0, "spacing": 16, "type": LARGE},
	"medium": {"width": 520.0, "picture": 40.0, "text": MEDIUM.lead, "detail": MEDIUM.body, "gap": 8, "top": 22.0, "spacing": 12, "type": MEDIUM},
	"small": {"width": 420.0, "picture": 32.0, "text": SMALL.lead, "detail": SMALL.body, "gap": 6, "top": 12.0, "spacing": 10, "type": SMALL},
}
const FADE_SECONDS := 0.3

var size_key := "large"
var reserved_top := 0.0   # room kept above the toasts for the view banner (ViewBanner)
var _pictures := {}


func _ready() -> void:
	name = "Toasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Across the top: each toast centres itself (SIZE_SHRINK_CENTER).
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	theme = UITheme.family_theme(UIRegistry.get_icon_family_color("people"))
	EventLog.entry_added.connect(show_event)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for toast: Control in get_children():
		var left := float(int(toast.get_meta("until")) - now) / 1000.0
		if left <= 0.0:
			_drop(toast)
		elif left < FADE_SECONDS:
			toast.modulate.a = left / FADE_SECONDS


## An entry as it lands in the log: its picture, its words and its second line.
func show_event(entry: Dictionary) -> void:
	var band: Color = UITheme.TAG_TONES.blocked[0] if String(entry.kind) == "warning" else UIRegistry.get_icon_family_color("people")
	_add(_toast(String(entry.text), String(entry.get("detail", "")), String(entry.get("picture", "")), band),
		EventLog.toast_seconds(String(entry.kind)))


## The player's own message (DockUI.show_persistence_status): words only, never logged.
## `seconds` overrides how long it stays.
func show_message(text: String, is_error := false, seconds := 0.0) -> void:
	_add(_toast(text, "", "", UITheme.TAG_TONES.blocked[0] if is_error else UITheme.TAG_TONES.fine[0]),
		seconds if seconds > 0.0 else EventLog.message_seconds(is_error))


func _add(toast: PanelContainer, seconds: float) -> void:
	toast.set_meta("until", Time.get_ticks_msec() + int(seconds * 1000.0))
	add_child(toast)
	move_child(toast, 0)
	while get_child_count() > EventLog.toast_limit():
		_drop(get_child(get_child_count() - 1))


func _drop(toast: Node) -> void:
	remove_child(toast)
	toast.queue_free()


func _toast(text: String, detail: String, picture: String, band: Color) -> PanelContainer:
	var s: Dictionary = SIZES[size_key]
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast.custom_minimum_size.x = s.width
	toast.add_theme_stylebox_override("panel", UITheme.toast_frame(band))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", s.spacing)
	toast.add_child(row)
	var texture := _picture(picture)
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2.ONE * float(s.picture)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame := UITheme.framed_picture(art)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(frame)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(_label(text, s.text, UITheme.CARD_TITLE))
	if not detail.is_empty(): words.add_child(_label(detail, s.detail, UITheme.HEARTH_MUTED))
	return toast


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UITheme.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _picture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _pictures.has(path): _pictures[path] = load(path)
	return _pictures[path]


## Keeps `height` free above the toasts, under the view banner; 0 gives it back.
func reserve_top(height: float) -> void:
	if is_equal_approx(height, reserved_top): return
	reserved_top = height
	_fit()


func _fit() -> void:
	var height := get_viewport().get_visible_rect().size.y
	size_key = "large" if height >= 1300.0 else ("small" if height < 650.0 else "medium")
	var s: Dictionary = SIZES[size_key]
	offset_top = s.top + reserved_top
	add_theme_constant_override("separation", s.gap)
