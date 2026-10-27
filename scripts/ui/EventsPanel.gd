extends MarginContainer

## The Events window (doc 23): the colony's event log, opening where the
## other windows open, in the people family.
## - Needs attention: each warning still unresolved on a card with the rust band: what is
##   wrong, what to do, since when, and Locate.
## - Then the days, newest first ("Today · Autumn, day 7"): each entry's picture on the
##   family tile, its words, its time, a hay New tag until it has been seen, and Locate
##   where it has a place or dwarves. A resolved warning stays in its day, greyed, with a
##   moss Resolved tag and no Locate.
## EventLog stays authoritative; this only reads it. Opening the window marks the log seen,
## which clears the dock's count, and the window stays open while Locate moves the view.
## Sizes follow the screen's height, and the window fits above the dock.
signal locate_requested(target: Dictionary)

const LOCATE_ICON := "res://assets/ui/icons/locate.png"
const FALLBACK := "res://assets/ui/icons/events.png"
const INTRO := "Newest first. Warnings stay at the top until they are resolved."
const EMPTY := "Nothing yet. Arrivals, discoveries, colony news and warnings will land here."
const MUTED := Color("aeb5ad")
const RULE := Color("27312f")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the other windows': large from 1300 px tall (the
## concept's, on the 7680×2160 screen), small below 650 px, where Locate is its pin alone.
const SIZES := {
	"large": {"width": 900, "tile": 64, "text": LARGE.lead, "sub": LARGE.body, "time": LARGE.body, "tag": LARGE.small, "heading": LARGE.heading, "row": 92,
		"locate": Vector2(150, 52), "pin": 36, "gap": 18, "spacing": 12, "intro": LARGE.body, "margin": 16, "type": LARGE},
	"medium": {"width": 640, "tile": 46, "text": MEDIUM.lead, "sub": MEDIUM.body, "time": MEDIUM.body, "tag": MEDIUM.small, "heading": MEDIUM.heading, "row": 68,
		"locate": Vector2(116, 40), "pin": 28, "gap": 12, "spacing": 8, "intro": MEDIUM.body, "margin": 12, "type": MEDIUM},
	"small": {"width": 480, "tile": 36, "text": SMALL.lead, "sub": SMALL.body, "time": SMALL.body, "tag": SMALL.small, "heading": SMALL.heading, "row": 54,
		"locate": Vector2(40, 34), "pin": 24, "gap": 10, "spacing": 6, "intro": SMALL.body, "margin": 10, "type": SMALL},
}

var window: UIWindow
var _size: Dictionary = SIZES.medium
var _dock_top := 600.0
var _new_after := 0    # entries after this id are New while the window stays open
var _turns := {}       # entry id -> which of its dwarves Locate goes to next
var _shown: Array = [] # what the list shows, so a refresh that changes nothing keeps it
var _textures := {}
var _refresh_queued := false
var _layout_pending := false
var _column: VBoxContainer
var _intro: Label
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	UITheme.apply_surface(self)
	_column = VBoxContainer.new()
	add_child(_column)
	_intro = _label(INTRO, false, MEDIUM.body, MUTED)
	_column.add_child(_intro)
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_column.add_child(inset)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	inset.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	EventLog.changed.connect(_queue_refresh)
	WorldClock.day_changed.connect(func(_day: int): _queue_refresh())
	_apply_size()


## The window has opened: what came since the last look stays New while it is open, and
## the log counts as seen.
func begin_viewing() -> void:
	_new_after = EventLog.last_seen()
	EventLog.mark_seen()
	_scroll.scroll_vertical = 0
	_fit()


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if window == null or not window.visible: return
	# What lands while the window is open is seen as it lands.
	EventLog.mark_seen()
	var today := floori(WorldClock.elapsed_days())
	var state := [EventLog.entries(), _new_after, today, _size]
	if state == _shown: return
	_shown = state
	var scroll := _scroll.scroll_vertical
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var pinned := EventLog.pinned()
	if not pinned.is_empty():
		var attention := _section("Needs attention", UITheme.TAG_TONES.blocked[1])
		for entry: Dictionary in pinned: attention.add_child(_card(entry, today))
	var pinned_ids: Array = pinned.map(func(entry: Dictionary) -> int: return int(entry.id))
	var day := -1
	var rows: VBoxContainer = null
	for entry: Dictionary in EventLog.entries():
		if int(entry.id) in pinned_ids: continue
		if floori(float(entry.time)) != day:
			day = floori(float(entry.time))
			rows = VBoxContainer.new()
			rows.add_theme_constant_override("separation", 0)
			_section(_day_title(day, today), UITheme.TAG_TONES.waiting[0]).add_child(rows)
		rows.add_child(_row(entry, today))
	if _list.get_child_count() == 0: _list.add_child(_text(EMPTY, _size.text, MUTED))
	_scroll.set_deferred("scroll_vertical", scroll)
	_fit_height()


# ── The log ────────────────────────────────────────────────────────────────────

## A section of the list under its heading, after a rule when something is above it.
func _section(title: String, color: Color) -> VBoxContainer:
	if _list.get_child_count() > 0:
		var rule := ColorRect.new()
		rule.color = RULE
		rule.custom_minimum_size.y = 3
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(rule)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", _size.spacing)
	_list.add_child(section)
	var heading := _label(title, true, _size.heading, color)
	heading.name = "Heading"
	section.add_child(heading)
	return section


## A warning still unresolved: what is wrong and what to do, since when, and Locate.
func _card(entry: Dictionary, today: int) -> Control:
	var card := PanelContainer.new()
	card.name = "Warning"
	card.set_meta("event_id", int(entry.id))
	card.add_theme_stylebox_override("panel", UITheme.warning_frame())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", _size.gap)
	card.add_child(line)
	line.add_child(_picture(String(entry.picture)))
	var words := _words()
	line.add_child(words)
	words.add_child(_text(String(entry.text), _size.text, UITheme.CARD_TITLE))
	if not String(entry.detail).is_empty(): words.add_child(_text(String(entry.detail), _size.sub, UITheme.HEARTH_MUTED))
	words.add_child(_label("Since " + _when(float(entry.time), today, today), false, _size.time, MUTED))
	var locate := _locate_button(entry)
	if locate != null: line.add_child(locate)
	return card


## One entry: its picture, its words, its time with New or Resolved, and Locate.
func _row(entry: Dictionary, today: int) -> Control:
	var resolved := entry.has("resolved")
	var row := HBoxContainer.new()
	row.name = "Entry"
	row.set_meta("event_id", int(entry.id))
	row.custom_minimum_size.y = _size.row
	row.add_theme_constant_override("separation", _size.gap)
	row.add_child(_picture(String(entry.picture)))
	var words := _words()
	row.add_child(words)
	words.add_child(_text(String(entry.text), _size.text, MUTED if resolved else UITheme.CARD_TEXT))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	words.add_child(line)
	line.add_child(_label(WorldClock.time_string_at(float(entry.time)), false, _size.time, MUTED))
	if resolved: line.add_child(_tag(_resolved(entry, today), "fine"))
	elif int(entry.id) > _new_after: line.add_child(_tag("New", "waiting"))
	if not resolved:
		var locate := _locate_button(entry)
		if locate != null: row.add_child(locate)
	return row


## Locate where the entry has a place or dwarves still in the colony.
func _locate_button(entry: Dictionary) -> Button:
	var dwarves := _present(entry)
	if dwarves.is_empty() and not entry.has("place"): return null
	var button := Button.new()
	button.name = "Locate"
	button.text = "" if _size == SIZES.small else "Locate"
	button.icon = _texture(LOCATE_ICON)
	button.custom_minimum_size = _size.locate
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_constant_override("icon_max_width", _size.pin)
	button.add_theme_font_override("font", UITheme.body_font())
	button.add_theme_font_size_override("font_size", int(_size.type.body))
	if dwarves.size() > 1: button.tooltip_text = "Move the view to each of these dwarves in turn"
	elif dwarves.size() == 1: button.tooltip_text = "Move the view to " + String(TaskManager.get_agent(int(dwarves[0])).dwarf_name)
	else: button.tooltip_text = "Move the view to where it happened"
	button.pressed.connect(_locate.bind(int(entry.id)))
	return button


## The view goes to the entry's dwarves one by one where it names them, else to its place.
func _locate(id: int) -> void:
	for entry: Dictionary in EventLog.entries():
		if int(entry.id) != id: continue
		var dwarves := _present(entry)
		if not dwarves.is_empty():
			var turn := int(_turns.get(id, 0))
			_turns[id] = turn + 1
			locate_requested.emit({"dwarf": int(dwarves[turn % dwarves.size()])})
		elif entry.has("place"):
			locate_requested.emit({"cell": Vector3i(int(entry.place[0]), int(entry.place[1]), int(entry.place[2]))})
		return


## The entry's dwarves still in the colony.
static func _present(entry: Dictionary) -> Array:
	return (entry.get("dwarves", []) as Array).filter(func(id: Variant) -> bool: return TaskManager.get_agent(int(id)) != null)


# ── Words ──────────────────────────────────────────────────────────────────────

## "Today · Autumn, day 7", "Yesterday · Autumn, day 6", then "Autumn, day 5".
static func _day_title(day: int, today: int) -> String:
	if day == today: return "Today · " + _date(day)
	if day == today - 1: return "Yesterday · " + _date(day)
	return _date(day)


static func _date(day: int) -> String:
	var date := WorldClock.date_at(float(day))
	return "%s, day %d" % [String(date.season).capitalize(), int(date.day)]


## The clock at `time`, with its day when that is not `day`: "today, 01:10",
## "yesterday, 19:23" or "Autumn, day 5, 19:23".
static func _when(time: float, day: int, today: int) -> String:
	var clock := WorldClock.time_string_at(time)
	var on := floori(time)
	if on == day: return clock
	if on == today: return "today, " + clock
	if on == today - 1: return "yesterday, " + clock
	return _date(on) + ", " + clock


## "Resolved at 22:35", with the day when it was resolved on a later one.
static func _resolved(entry: Dictionary, today: int) -> String:
	var day := floori(float(entry.time))
	if floori(float(entry.resolved)) == day: return "Resolved at " + WorldClock.time_string_at(float(entry.resolved))
	return "Resolved " + _when(float(entry.resolved), day, today)


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
	_fit_height()


func _apply_size() -> void:
	custom_minimum_size.x = float(_size.width) - 8.0   # the window's frame brings 4 px a side
	for side: String in ["left", "right", "top", "bottom"]: add_theme_constant_override("margin_" + side, _size.margin)
	_column.add_theme_constant_override("separation", _size.margin)
	_list.add_theme_constant_override("separation", _size.gap)
	_intro.add_theme_font_size_override("font_size", _size.intro)
	_intro.visible = _size != SIZES.small   # small screens keep the room for the log


## The list as tall as its entries need, as far as the room above the dock allows; a
## longer log scrolls.
func _fit_height() -> void:
	if window == null or not window.visible: return
	window.reset_size()
	UITheme.lay_out_now(window)
	_measure()
	_settle_layout()


func _measure() -> void:
	var chrome := window.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := maxf(120.0, _dock_top - 12.0 - chrome)
	_scroll.custom_minimum_size.y = minf(room, ceilf(_list.get_combined_minimum_size().y))
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock()


func _settle_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	# Wrapped words need their final width before measuring.
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_pending = false
	if is_instance_valid(window) and window.visible: _measure()


func _clamp_above_dock() -> void:
	window.position.y = minf(window.position.y, maxf(4, _dock_top - 8 - window.size.y))


# ── Pieces ────────────────────────────────────────────────────────────────────

## A picture on the people tile.
func _picture(path: String) -> Control:
	var art := TextureRect.new()
	art.texture = _texture(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2.ONE * roundf(float(_size.tile) * 0.8)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame := UITheme.framed_picture(art)
	frame.custom_minimum_size = Vector2.ONE * float(_size.tile)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return frame


func _words() -> VBoxContainer:
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return words


## A tag in one of the tones: hay for New, moss for Resolved.
func _tag(text: String, tone: String) -> Control:
	var tag := PanelContainer.new()
	tag.name = "Tag"
	tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 2))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(_label(text, false, _size.tag, UITheme.tag_ink(tone)))
	return tag


## Words that wrap at the width the row leaves them.
func _text(value: String, font_size: int, color: Color) -> Label:
	var label := _label(value, false, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## One line: a heading, a time or a tag's word.
func _label(value: String, display: bool, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_override("font", UITheme.display_font() if display else UITheme.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path) if ResourceLoader.exists(path) else load(FALLBACK)
	return _textures[path]
