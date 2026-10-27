extends VBoxContainer

## The game menu's Settings page (doc 23). The sections are tabs across the top, as in the
## dwarf, room and storage windows: Audio, Interface, Video and Controls. The open section's
## settings sit in the inset, with Back, the Esc hint and Restore defaults along the foot.
## - Every setting is a row: its name and a line on what it does on the left, its control
##   on the right: choice blocks (the chosen one is the family block) or a slider with its
##   value.
## - Interface is the UI scale (doc 23): Auto and the steps the window has room for, then,
##   under a rule, the scale in effect with the room it leaves and what Auto follows.
## - Controls is the key list (data/ui/controls.json): groups in two columns, each entry
##   what the player does and its keys on keycaps. It has nothing to restore; choosing keys
##   comes later.
## - AmbientAudio and VideoSettings own the values. The page shows them and follows their
##   preferences_changed, whoever changed them.
## - Every row takes the tallest row's height, and the inset keeps one size on every
##   section. When the screen is too short, the rows drop their lines (which become their
##   tooltips) and, only if still too short, the inset scrolls. On short screens the key
##   list scrolls where Audio and Video still fit.
## GameMenu builds it, sizes it and handles Esc.
signal back_requested

# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the menu's; GameMenu passes the size's name. Small
## screens never show the rows' lines.
const SIZES := {
	"large": {"page": 1056, "gap": 18, "tab": Vector2(200, 64), "tab_font": LARGE.lead, "tab_gap": 12, "intro": LARGE.body, "pad": 16,
		"words": 380, "title": LARGE.heading, "about": LARGE.body, "lines": true, "row_gap": 24, "rule": 3, "rule_gap": 24, "block": 64,
		"block_font": LARGE.body, "block_gap": 12, "track": 30, "knob": Vector2i(14, 16), "knob_cell": 3, "value": LARGE.heading, "value_width": 92,
		"detail": LARGE.small, "mute": Vector2(120, 56), "mute_font": LARGE.body, "note": LARGE.body, "back": Vector2(220, 70), "back_font": LARGE.heading,
		"hint": LARGE.body, "restore": Vector2(290, 62), "restore_font": LARGE.lead,
		"key_text": LARGE.body, "key": LARGE.body, "key_cell": 3, "key_row": 5, "key_group": 22, "key_columns": 56, "type": LARGE},
	"medium": {"page": 720, "gap": 12, "tab": Vector2(136, 44), "tab_font": MEDIUM.lead, "tab_gap": 8, "intro": MEDIUM.body, "pad": 10,
		"words": 260, "title": MEDIUM.heading, "about": MEDIUM.body, "lines": true, "row_gap": 16, "rule": 2, "rule_gap": 16, "block": 44,
		"block_font": MEDIUM.body, "block_gap": 8, "track": 20, "knob": Vector2i(14, 17), "knob_cell": 2, "value": MEDIUM.heading, "value_width": 64,
		"detail": MEDIUM.small, "mute": Vector2(84, 40), "mute_font": MEDIUM.body, "note": MEDIUM.body, "back": Vector2(150, 48), "back_font": MEDIUM.heading,
		"hint": MEDIUM.body, "restore": Vector2(200, 44), "restore_font": MEDIUM.lead,
		"key_text": MEDIUM.body, "key": MEDIUM.body, "key_cell": 2, "key_row": 3, "key_group": 14, "key_columns": 36, "type": MEDIUM},
	"small": {"page": 600, "gap": 8, "tab": Vector2(100, 34), "tab_font": SMALL.lead, "tab_gap": 6, "intro": SMALL.body, "pad": 6,
		"words": 190, "title": SMALL.heading, "about": SMALL.body, "lines": false, "row_gap": 10, "rule": 2, "rule_gap": 8, "block": 32,
		"block_font": SMALL.body, "block_gap": 6, "track": 14, "knob": Vector2i(10, 13), "knob_cell": 2, "value": SMALL.heading, "value_width": 48,
		"detail": SMALL.small, "mute": Vector2(60, 30), "mute_font": SMALL.body, "note": SMALL.body, "back": Vector2(110, 36), "back_font": SMALL.heading,
		"hint": SMALL.body, "restore": Vector2(150, 34), "restore_font": SMALL.lead,
		"key_text": SMALL.body, "key": SMALL.body, "key_cell": 2, "key_row": 2, "key_group": 8, "key_columns": 20, "type": SMALL},
}
const SECTIONS := ["audio", "interface", "video", "controls"]
const INTRO := {"audio": "Your audio preferences apply to every colony.",
	"interface": "The size of the interface. Changes show at once and apply to every colony.",
	"video": "Changes show at once and apply to every colony.",
	"controls": "Every key and mouse control. Choosing your own keys comes later."}
const RESTORE_TIPS := {"audio": "Restore the original audio mix", "interface": "Restore the original interface size",
	"video": "Restore the original video settings"}
const CHANNELS := [["ambience", "Ambience", "Weather, woodland, shoreline and cave sounds"],
	["effects", "Effects", "Work, wildlife, water, fires and notifications"]]
const RULE := Color("27312f")
const DockIcon = preload("res://scripts/ui/DockIconButton.gd")   # names an input action's key
const INSET_SIDES := 24.0   # the inset's own margins, left and right
const INSET_ENDS := 20.0   # and top and bottom
const SCROLLBAR := 14.0

## The open section; it stays open between visits.
var section := "audio"
var tabs := {}
## Each setting's controls by id: a channel's slider, value and mute; render scale's slider,
## value and detail; a choice setting's buttons by choice.
var controls := {}
var back_button: Button
var restore_button: Button
var _intro: Label
var _scroll: ScrollContainer
var _pad: MarginContainer
var _sections := {}
var _rows: Array[Dictionary] = []
var _rules: Array[HSeparator] = []
var _choice_ids: Array[String] = []
var _rates: HBoxContainer
var _shown_rates: Array[int] = []
var _scales: HBoxContainer
var _shown_scales: Array[int] = []
var _note: Label
var _scale_note: Label   # the UI scale in effect, the room it leaves and what Auto follows
var _hint: Label
var _size: Dictionary = SIZES.medium
var _tracks := {}
var _knobs := {}
var _key_columns: HBoxContainer
var _key_headings: Array[Label] = []
## Each entry of the key list: its row, label, words and keys box, the keys (each a chord or
## a list of keys shown side by side) and the word between them.
var _key_rows: Array[Dictionary] = []
var _keys_size: Dictionary = {}   # the size the keycaps were last built at


func _init() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	for id: String in SECTIONS:
		var tab := Button.new()
		tab.name = id.capitalize() + "Tab"
		tab.text = id.capitalize()
		UITheme.apply_hearth_button(tab)
		tab.pressed.connect(show_section.bind(id))
		bar.add_child(tab)
		tabs[id] = tab
	_intro = _label(false, UITheme.HEARTH_MUTED)
	add_child(_intro)
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	add_child(inset)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inset.add_child(_scroll)
	_pad = MarginContainer.new()
	_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_pad)
	var pages := VBoxContainer.new()
	_pad.add_child(pages)
	for id: String in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 0)
		pages.add_child(page)
		_sections[id] = page
	for entry: Array in CHANNELS:
		_channel_row(entry[0], entry[1], entry[2])
	_rule(_sections.audio)
	_note = _label(false, UITheme.HEARTH_MUTED)
	_note.text = "Ambience softens while paused."
	_sections.audio.add_child(_note)
	for setting: Dictionary in VideoSettings.settings():
		_video_row(setting)
	_rule(_sections.interface)
	_scale_note = _label(false, UITheme.HEARTH_MUTED)
	_sections.interface.add_child(_scale_note)
	_build_keys()
	var foot := HBoxContainer.new()
	add_child(foot)
	back_button = Button.new()
	back_button.text = "Back"
	UITheme.apply_hearth_button(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	foot.add_child(back_button)
	_hint = _label(false, UITheme.HEARTH_MUTED)
	_hint.text = "Esc goes back to the menu"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hint)
	restore_button = Button.new()
	restore_button.text = "Restore defaults"
	UITheme.apply_hearth_button(restore_button)
	restore_button.pressed.connect(_restore)
	foot.add_child(restore_button)
	AmbientAudio.preferences_changed.connect(show_values)
	VideoSettings.preferences_changed.connect(show_values)
	show_section(section)


## Opens a section: its tab becomes the family block, and Restore defaults acts on it.
func show_section(id: String) -> void:
	section = id
	for key: String in SECTIONS:
		_sections[key].visible = key == id
		UITheme.show_tab(tabs[key], key == id)
	_intro.text = INTRO[id]
	restore_button.visible = id != "controls"
	restore_button.tooltip_text = RESTORE_TIPS.get(id, "")
	show_values()


## The controls follow AmbientAudio and VideoSettings, whoever changed them.
func show_values() -> void:
	for entry: Array in CHANNELS:
		var parts: Dictionary = controls[entry[0]]
		var volume: float = AmbientAudio.volume(entry[0])
		(parts.slider as HSlider).set_value_no_signal(volume * 100.0)
		(parts.value as Label).text = "%d%%" % roundi(volume * 100.0)
		(parts.mute as Button).set_pressed_no_signal(AmbientAudio.muted(entry[0]))
	_show_rates()
	_show_scales()
	for id: String in _choice_ids:
		var chosen: Variant = VideoSettings.frame_rate() if id == "frame_rate" else VideoSettings.value(id)
		for choice: Variant in controls[id]:   # the UI scale's choices are "auto" and percentages
			UITheme.show_tab(controls[id][choice], typeof(choice) == typeof(chosen) and choice == chosen)
	var scale: float = VideoSettings.value("render_scale")
	var world := VideoSettings.render_size()
	(controls.render_scale.slider as HSlider).set_value_no_signal(scale * 100.0)
	(controls.render_scale.value as Label).text = "%d%%" % roundi(scale * 100.0)
	(controls.render_scale.detail as Label).text = "%d × %d" % [world.x, world.y]
	var width: float = _size.page - INSET_SIDES - 2.0 * _size.pad - SCROLLBAR
	_scale_note.text = _wrap(_scale_text(), UITheme.body_font(), _size.note, width) + "\n" \
		+ _wrap("Auto follows the display scale Windows sets for this screen.", UITheme.body_font(), _size.note, width)


## Where keyboard focus lands: the open section's first control (the chosen UI scale on
## Interface), or the Controls tab.
func first_focus() -> Control:
	if section == "audio": return controls.ambience.slider
	if section == "controls": return tabs.controls
	if section == "interface": return controls.ui_scale.get(VideoSettings.value("ui_scale"), controls.ui_scale.auto)
	return controls.display[VideoSettings.value("display")]


## The keys a row of the key list shows, as the player reads them: "Ctrl + ] / Ctrl + [".
## Empty when no row has that label.
func shown_keys(label: String) -> String:
	for row: Dictionary in _key_rows:
		if row.text != label: continue
		var words := PackedStringArray()
		for part: Node in (row.keys as HBoxContainer).get_children():
			words.append(((part.get_child(0) if part is PanelContainer else part) as Label).text)
		return " ".join(words)
	return ""


## Sizes the page for the screen; `height` is the room the menu's frame leaves it. The inset
## takes the tallest section, so switching never resizes the window. When the settings' rows
## (Audio, Interface and Video) do not fit, they drop their lines first. The inset scrolls
## only for a section that still does not fit, and only that section leaves room for the
## scrollbar.
func apply_size(key: String, height: float) -> void:
	_size = SIZES[key]
	var s := _size
	custom_minimum_size.x = s.page
	add_theme_constant_override("separation", s.gap)
	(tabs.audio.get_parent() as HBoxContainer).add_theme_constant_override("separation", s.tab_gap)
	for tab: Button in tabs.values():
		tab.custom_minimum_size = s.tab
		tab.add_theme_font_size_override("font_size", s.tab_font)
	_intro.add_theme_font_size_override("font_size", s.intro)
	for side: String in ["left", "right", "top", "bottom"]:
		_pad.add_theme_constant_override("margin_" + side, s.pad)
	var line := StyleBoxLine.new()
	line.color = RULE
	line.thickness = s.rule
	for rule: HSeparator in _rules:
		rule.add_theme_stylebox_override("separator", line)
		rule.add_theme_constant_override("separation", s.rule_gap)
	for row: Dictionary in _rows:
		(row.row as HBoxContainer).add_theme_constant_override("separation", s.row_gap)
		(row.box as HBoxContainer).add_theme_constant_override("separation", s.block_gap)
		(row.words as VBoxContainer).custom_minimum_size.x = s.words
		(row.title as Label).add_theme_font_size_override("font_size", s.title)
		var about: Label = row.about
		about.add_theme_font_size_override("font_size", s.about)
		about.text = _wrap(String(row.text), UITheme.body_font(), s.about, s.words)
	for entry: Array in CHANNELS:
		var parts: Dictionary = controls[entry[0]]
		_dress_slider(parts.slider)
		_dress_value(parts.value)
		var mute: Button = parts.mute
		mute.custom_minimum_size = s.mute
		mute.add_theme_font_size_override("font_size", s.mute_font)
	_dress_slider(controls.render_scale.slider)
	_dress_value(controls.render_scale.value)
	(controls.render_scale.detail as Label).add_theme_font_size_override("font_size", s.detail)
	_note.add_theme_font_size_override("font_size", s.note)
	_scale_note.add_theme_font_size_override("font_size", s.note)
	(back_button.get_parent() as HBoxContainer).add_theme_constant_override("separation", s.gap)
	back_button.custom_minimum_size = s.back
	back_button.add_theme_font_size_override("font_size", s.back_font)
	_hint.add_theme_font_size_override("font_size", s.hint)
	restore_button.custom_minimum_size = s.restore
	restore_button.add_theme_font_size_override("font_size", s.restore_font)
	_size_blocks(0.0)
	show_values()   # the window may have room for other UI scale steps now
	_size_keys(0.0)
	_show_lines(s.lines)
	var room: float = height - s.tab.y - _intro.get_combined_minimum_size().y - s.back.y - 3.0 * s.gap - INSET_ENDS
	var heights := _heights()
	if _rows_height(heights) > room and s.lines:
		_show_lines(false)
		heights = _heights()
	var tallest: float = heights.values().max()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if tallest > room else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = minf(tallest, room)
	if _rows_height(heights) > room: _size_blocks(SCROLLBAR)
	if heights.controls > room: _size_keys(SCROLLBAR)


# ── Building ──────────────────────────────────────────────────────────────────

## A setting's row: its name and what it does on the left, then the box for its control.
func _row(page: VBoxContainer, title: String, about: String) -> HBoxContainer:
	if page.get_child_count() > 0: _rule(page)
	var row := HBoxContainer.new()
	page.add_child(row)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(words)
	var heading := _label(true, UITheme.CARD_TITLE)
	heading.text = title
	words.add_child(heading)
	var line := _label(false, UITheme.HEARTH_MUTED)
	line.text = about
	words.add_child(line)
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	_rows.append({"row": row, "words": words, "title": heading, "about": line, "text": about, "box": box})
	return box


func _rule(page: VBoxContainer) -> void:
	var rule := HSeparator.new()
	page.add_child(rule)
	_rules.append(rule)


## An audio channel: its volume, the percentage and Mute.
func _channel_row(channel: String, title: String, about: String) -> void:
	var box := _row(_sections.audio, title, about)
	var slider := _slider(title + "Volume", "%s volume" % title, 0.0, 100.0, 1.0)
	slider.value_changed.connect(func(volume: float): AmbientAudio.set_volume(channel, volume / 100.0))
	box.add_child(slider)
	var amount := _value_label()
	box.add_child(amount)
	# A toggled button is the family block in a family window (doc 23).
	var mute := Button.new()
	mute.name = title + "Mute"
	mute.text = "Mute"
	mute.toggle_mode = true
	mute.tooltip_text = "Mute %s" % channel
	UITheme.apply_hearth_button(mute)
	mute.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mute.toggled.connect(func(on: bool): AmbientAudio.set_muted(channel, on))
	box.add_child(mute)
	controls[channel] = {"slider": slider, "value": amount, "mute": mute}


## A VideoSettings setting, on its section's tab: render scale's slider with its percentage
## and the world's resolution, the frame rates the screen offers, the UI scales the window
## has room for with their line, or the setting's choices.
func _video_row(setting: Dictionary) -> void:
	var id := String(setting.id)
	var about := String(setting.about).format({"refresh": roundi(VideoSettings.refresh_rate())})
	var box := _row(_sections[VideoSettings.section_of(id)], String(setting.title), about)
	match id:
		"render_scale":
			var slider := _slider("RenderScale", "Render scale", float(setting.min) * 100.0, float(setting.max) * 100.0,
				float(setting.step) * 100.0)
			slider.value_changed.connect(func(percent: float): VideoSettings.set_value(id, percent / 100.0))
			box.add_child(slider)
			var readout := VBoxContainer.new()
			readout.add_theme_constant_override("separation", 0)
			readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(readout)
			var amount := _value_label()
			readout.add_child(amount)
			var detail := _label(false, UITheme.HEARTH_MUTED)
			detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			readout.add_child(detail)
			controls[id] = {"slider": slider, "value": amount, "detail": detail}
		"frame_rate":
			_choice_ids.append(id)
			_rates = box
			_show_rates()
		"ui_scale":
			_choice_ids.append(id)
			_scales = box
			_show_scales()
		_:
			_choice_ids.append(id)
			controls[id] = {}
			for choice: Dictionary in setting.choices:
				_choice(box, id, String(choice.id), String(choice.label))


## The frame rates on offer follow the screen's refresh rate.
func _show_rates() -> void:
	var rates := VideoSettings.frame_rates()
	if rates == _shown_rates: return
	_shown_rates = rates
	for child: Node in _rates.get_children():
		_rates.remove_child(child)
		child.queue_free()
	controls.frame_rate = {}
	for fps: int in rates:
		_choice(_rates, "frame_rate", fps, "%d fps" % fps)
	_size_blocks(0.0)


## Auto and the UI scale steps the window has room for.
func _show_scales() -> void:
	var steps := VideoSettings.ui_scales()
	if steps == _shown_scales: return
	_shown_scales = steps
	for child: Node in _scales.get_children():
		_scales.remove_child(child)
		child.queue_free()
	controls.ui_scale = {}
	_choice(_scales, "ui_scale", "auto", "Auto")
	for percent: int in steps:
		_choice(_scales, "ui_scale", percent, "%d%%" % percent)
	_size_blocks(0.0)


## The note under the UI scale: the scale in effect and the room it leaves the interface.
func _scale_text() -> String:
	var room := VideoSettings.layout_size()
	var percent := VideoSettings.ui_percent()
	var chosen: Variant = VideoSettings.value("ui_scale")
	var text := "The interface lays out at %d × %d." % [room.x, room.y]
	if chosen is String:
		var system := VideoSettings.system_scale()
		var auto := "Auto: %d%%, as Windows sets this screen." % percent if percent == system \
			else "Auto: %d%% (Windows uses %d%%)." % [percent, system]
		text = auto + " " + text
	elif int(chosen) != percent:
		text = "%d%% needs a larger window: %d%% for now. %s" % [chosen, percent, text]
	if _shown_scales.size() == 1: text += " This window has no room for a larger size."
	return text


func _choice(box: HBoxContainer, id: String, choice: Variant, label: String) -> void:
	var button := Button.new()
	button.name = "%s_%s" % [id, choice]
	button.text = label
	UITheme.apply_hearth_button(button)
	button.pressed.connect(VideoSettings.set_value.bind(id, choice))
	box.add_child(button)
	controls[id][choice] = button


func _slider(node_name: String, tip: String, lowest: float, highest: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = lowest
	slider.max_value = highest
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = tip
	return slider


func _value_label() -> Label:
	var value := _label(true, UITheme.TAG_TONES.waiting[0])
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return value


func _label(display: bool, color: Color) -> Label:
	var label := Label.new()
	UITheme.format_label(label, display, MEDIUM.heading, color)
	return label


func _restore() -> void:
	if section == "controls": return
	if section in ["interface", "video"]:
		VideoSettings.restore_defaults(section)
		return
	AmbientAudio.set_volume("ambience", float(AmbientAudio.config.default_volume))
	AmbientAudio.set_volume("effects", float(AmbientAudio.config.default_effects_volume))
	AmbientAudio.set_muted("ambience", false)
	AmbientAudio.set_muted("effects", false)


## The key list (doc 23 "Keys"): the groups in columns, each entry what the player does with
## its keys at the right. An input action's keys come from the input map, so the list shows
## the keys the game uses. The keycaps are built when the page is sized.
func _build_keys() -> void:
	_key_columns = HBoxContainer.new()
	_sections.controls.add_child(_key_columns)
	for column: Array in UIRegistry.get_controls().get("columns", []):
		var stack := VBoxContainer.new()
		_key_columns.add_child(stack)
		for group: Dictionary in column:
			var block := VBoxContainer.new()
			stack.add_child(block)
			var heading := _label(true, UITheme.CARD_TITLE)
			heading.text = String(group.title)
			block.add_child(heading)
			_key_headings.append(heading)
			for entry: Dictionary in group.entries:
				var row := HBoxContainer.new()
				block.add_child(row)
				var words := _label(false, UITheme.CARD_TEXT)
				words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(words)
				var keys := HBoxContainer.new()
				keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(keys)
				var chords: Array = []
				for action: String in entry.get("actions", []):
					chords.append(DockIcon.key_text(action))
				chords.append_array(entry.get("keys", []))
				_key_rows.append({"row": row, "text": String(entry.label), "words": words, "keys": keys,
					"chords": chords, "joined": String(entry.get("joined", "or"))})


## Each row's keys on caps of the size's type, with the word between them.
func _show_keys() -> void:
	var s := _size
	for row: Dictionary in _key_rows:
		var keys: HBoxContainer = row.keys
		for child: Node in keys.get_children():
			keys.remove_child(child)
			child.queue_free()
		for i in range(row.chords.size()):
			if i > 0:
				var joined := _label(false, UITheme.HEARTH_MUTED)
				joined.text = row.joined
				joined.add_theme_font_size_override("font_size", s.key_text)
				keys.add_child(joined)
			var chord: Variant = row.chords[i]
			for key: String in (chord if chord is Array else [chord]):
				UITheme.add_keycaps(keys, key, s.key, s.key_cell)
	_keys_size = s


# ── Sizes ─────────────────────────────────────────────────────────────────────

## Choice blocks share the control column evenly. Two choices keep the width of three, so
## the columns line up from row to row.
func _size_blocks(scrollbar: float) -> void:
	var s := _size
	var width: float = s.page - INSET_SIDES - 2.0 * s.pad - s.words - s.row_gap - scrollbar
	for id: String in _choice_ids:
		var buttons: Dictionary = controls[id]
		var count := maxi(buttons.size(), 3)
		var each := floorf((width - s.block_gap * (count - 1)) / count)
		for button: Button in buttons.values():
			button.custom_minimum_size = Vector2(each, s.block)
			button.add_theme_font_size_override("font_size", s.block_font)


## The key list's columns share the inset evenly. Each row's keys sit at its right, and its
## words break into lines in the room left, so its height is known before layout.
func _size_keys(scrollbar: float) -> void:
	var s := _size
	if _keys_size != s: _show_keys()
	var count := maxi(_key_columns.get_child_count(), 1)
	var width: float = s.page - INSET_SIDES - 2.0 * s.pad - scrollbar
	var column := floorf((width - s.key_columns * (count - 1)) / count)
	_key_columns.add_theme_constant_override("separation", s.key_columns)
	for stack: VBoxContainer in _key_columns.get_children():
		stack.custom_minimum_size.x = column
		stack.add_theme_constant_override("separation", s.key_group)
		for block: VBoxContainer in stack.get_children():
			block.add_theme_constant_override("separation", s.key_row)
	for heading: Label in _key_headings:
		heading.add_theme_font_size_override("font_size", s.title)
	for row: Dictionary in _key_rows:
		var keys: HBoxContainer = row.keys
		keys.add_theme_constant_override("separation", roundi(s.block_gap * 0.5))
		(row.row as HBoxContainer).add_theme_constant_override("separation", s.block_gap)
		var words: Label = row.words
		words.add_theme_font_size_override("font_size", s.key_text)
		var room: float = column - keys.get_combined_minimum_size().x - s.block_gap
		words.text = _wrap(String(row.text), UITheme.body_font(), s.key_text, room)


## A row's line under its name, or, when there is no room for it, its tooltip.
func _show_lines(shown: bool) -> void:
	for row: Dictionary in _rows:
		(row.about as Label).visible = shown
		(row.words as Control).tooltip_text = "" if shown else String(row.text)


## Every row takes the tallest row's height, as in the concept; returns each section's height
## in the inset by its id.
func _heights() -> Dictionary:
	var row_height := 0.0
	for row: Dictionary in _rows:
		(row.row as Control).custom_minimum_size.y = 0.0
		row_height = maxf(row_height, (row.row as Control).get_combined_minimum_size().y)
	for row: Dictionary in _rows:
		(row.row as Control).custom_minimum_size.y = row_height
	var heights := {}
	for id: String in SECTIONS:
		heights[id] = (_sections[id] as Control).get_combined_minimum_size().y + 2.0 * _size.pad
	return heights


## The tallest section of settings' rows (Audio, Interface and Video): their rows drop their
## lines before the inset would scroll.
static func _rows_height(heights: Dictionary) -> float:
	return maxf(maxf(heights.audio, heights.video), heights.interface)


func _dress_slider(slider: HSlider) -> void:
	var s := _size
	slider.add_theme_stylebox_override("slider", _track("groove", int(s.track)))
	for area: String in ["grabber_area", "grabber_area_highlight"]:
		slider.add_theme_stylebox_override(area, _track("fill", int(s.track)))
	slider.add_theme_icon_override("grabber", _knob(s.knob, int(s.knob_cell), false))
	slider.add_theme_icon_override("grabber_highlight", _knob(s.knob, int(s.knob_cell), true))


func _dress_value(label: Label) -> void:
	label.add_theme_font_size_override("font_size", _size.value)
	label.custom_minimum_size.x = _size.value_width   # "100%" never shifts the slider


## The words broken into lines that fit `width`, so a row's height is known before layout. A
## number or a slash stays with the word after it: "1 level", "1 / 4 levels", "120 Hz".
static func _wrap(text: String, font: Font, font_size: int, width: float) -> String:
	var units := PackedStringArray()
	var glued := ""
	for word: String in text.split(" "):
		glued = word if glued.is_empty() else glued + " " + word
		if word == "/" or word.is_valid_float(): continue
		units.append(glued)
		glued = ""
	if not glued.is_empty(): units.append(glued)
	var lines := PackedStringArray()
	var line := ""
	for word: String in units:
		var longer := word if line.is_empty() else line + " " + word
		if line.is_empty() or font.get_string_size(longer, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			line = longer
		else:
			lines.append(line)
			line = word
	lines.append(line)
	return "\n".join(lines)


## A slider's groove or hay fill, `height` px thick: the cell styles with their content
## margins opened up, since a slider draws its track at its style's minimum height.
func _track(kind: String, height: int) -> StyleBox:
	var key := "%s%d" % [kind, height]
	if not _tracks.has(key):
		var style: StyleBoxTexture = UITheme.cell_style(kind, 2).duplicate()
		style.content_margin_top = height * 0.5
		style.content_margin_bottom = height * 0.5
		_tracks[key] = style
	return _tracks[key]


## The slider's knob: a stone keycap in cell art, lighter while hovered or dragged.
func _knob(cells: Vector2i, cell: int, lit: bool) -> Texture2D:
	var key := "%s%d%s" % [cells, cell, lit]
	if not _knobs.has(key):
		var face := UITheme.KEYCAP_FACE.lightened(0.12) if lit else UITheme.KEYCAP_FACE
		var art := UITheme.cell_slab(cells.x, cells.y, face, UITheme.KEYCAP_TOP, UITheme.KEYCAP_SKIRT, UITheme.KEYCAP_OUTLINE, 1, 2)
		art.resize(cells.x * cell, cells.y * cell, Image.INTERPOLATE_NEAREST)
		_knobs[key] = UITheme.cell_texture(art)
	return _knobs[key]
