extends CanvasLayer

## The game menu (doc 23), an autoload. The dock's Menu button opens it, and so does Esc
## once nothing in the scene used the key: as an autoload it hears Esc after every scene
## node, and a front window still open closes first. It outlives the scene reload that Load
## and New game cause.
## - The world dims and the game pauses while it is open, with a clock hold as loading uses,
##   so the player's own pause and speed are never touched.
## - The menu page, titled with the settlement's name once it is founded: the colony's date,
##   when it was last saved, then Resume, Save game and Save as… side by side, Load game…, New
##   game…, Settings…, Quit to main menu… and Exit game….
## - The Save as… page: a name for the save, chosen so typing replaces it, then the player's
##   named saves, each with Replace.
## - The Load page: the quick save and the autosave, each with its settlement's name, its date
##   in the colony and when it was saved, then the player's named saves, in a list that
##   scrolls. Every save has Load and Delete; Open folder shows the named saves' folder.
## - The Settings page (SettingsPanel): Audio, Video and Controls as tabs across the top.
##   AmbientAudio and VideoSettings keep the preferences; Controls is the key list.
## - Load, Replace, Delete, New game, Quit to main menu and Exit ask first, in a question in
##   front of the menu; Load, New game, Quit and Exit say how long ago the colony was last
##   saved. Closing the game's window asks as Exit does.
## - Esc steps back: a question, then a page, then the menu itself.
## - The title screen opens the Load and Settings pages on their own (open_page): Back, ✕ or
##   Esc close them, and a slot loads without asking, as no colony runs yet.
signal opened
signal closed

# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as the windows': large from 1300 px tall, small below 650 px.
const SIZES := {
	"large": {"menu": 640, "page": 960, "ask": 920, "button": 78, "verb": LARGE.heading, "plain": LARGE.heading, "date": LARGE.title, "body": LARGE.lead,
		"note": LARGE.body, "slot": LARGE.title, "slot_date": LARGE.lead, "gap": 14, "type": LARGE},
	"medium": {"menu": 440, "page": 660, "ask": 640, "button": 54, "verb": MEDIUM.heading, "plain": MEDIUM.heading, "date": MEDIUM.title, "body": MEDIUM.lead,
		"note": MEDIUM.body, "slot": MEDIUM.title, "slot_date": MEDIUM.lead, "gap": 10, "type": MEDIUM},
	"small": {"menu": 360, "page": 540, "ask": 520, "button": 38, "verb": SMALL.heading, "plain": SMALL.heading, "date": SMALL.title, "body": SMALL.lead,
		"note": SMALL.body, "slot": SMALL.title, "slot_date": SMALL.lead, "gap": 7, "type": SMALL},
}
## The room the frame's band and margins take, with a little screen around the frame.
const FRAME_ROOM := 120.0
const Settings = preload("res://scripts/ui/SettingsPanel.gd")
const SaveName = preload("res://scripts/components/SaveName.gd")
const NOTES := {"quick": "Written by Save game.", "auto": "Written every five minutes while you play."}
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Keys the name field takes beside text and the menu's own navigation.
const EDIT_KEYS := [KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END]

## SaveManager, or a stand-in with the same calls in tests.
var saves: Node
## Quits the game; tests give their own.
var quit_game: Callable
var _open := false
var _page := "menu"
var _question := ""
## What a save the player asked for leads to: "exit" or "title" once it is written.
var _after_save := ""
## The page the title screen opened on its own, or "" for the game menu itself.
var _title_page := ""
var _size: Dictionary = SIZES.medium
var _root: Control
var _frame: PanelContainer
var _title: Label
var _menu: VBoxContainer
var _load: VBoxContainer
var _date: Label
var _time: Label
var _saved: PanelContainer
var _saved_label: Label
var _buttons := {}
var _menu_hint: Label
var _load_intro: Label
var _slots: VBoxContainer
var _back_button: Button
var _folder_button: Button
var _load_hint: Label
var _save_as: VBoxContainer
var _save_intro: Label
var _name_field: LineEdit
var _save_button: Button
var _name_note: Label
var _save_heading: Label
var _save_scroll: ScrollContainer
var _save_list: VBoxContainer
var _save_back: Button
var _save_hint: Label
var _settings: Settings
var _veil: ColorRect
var _ask_frame: PanelContainer
var _ask_title: Label
var _ask_body: Label
var _ask_buttons: HBoxContainer


func _ready() -> void:
	layer = 100   # above the dock, windows, toasts and hover cards; below the loading screen
	visible = false
	if saves == null: saves = get_node("/root/SaveManager")
	if not quit_game.is_valid(): quit_game = func(): get_tree().quit()
	get_tree().set_auto_accept_quit(false)   # closing the window asks first
	saves.save_finished.connect(_on_save_finished)
	get_viewport().size_changed.connect(func(): if _open: _apply_size())
	_build()


func is_open() -> bool:
	return _open


## Opens the menu on its first page, unless the world is still loading.
func open() -> void:
	if _open or saves.is_loading() or WorldClock.is_loading_held(): return
	_open = true
	visible = true
	WorldClock.hold_for_loading(self, true)
	_question = ""
	_after_save = ""
	_apply_size()
	_show_page("menu")
	opened.emit()


## The title screen's Load game… and Settings… (doc 23): the menu opens on that page alone,
## and Back, ✕ or Esc close it again.
func open_page(page: String) -> void:
	if _open or saves.is_loading(): return
	_open = true
	visible = true
	_title_page = page
	_question = ""
	_after_save = ""
	_apply_size()
	_show_page(page)
	opened.emit()


## Closes the menu and lets the clock run as it did before.
func close() -> void:
	if not _open: return
	_open = false
	visible = false
	_question = ""
	_title_page = ""
	_veil.visible = false
	_ask_frame.get_parent().visible = false
	WorldClock.hold_for_loading(self, false)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey or not event.pressed: return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		if not event.echo: _back()
		get_viewport().set_input_as_handled()
	elif not _navigates(event) and not _types(event as InputEventKey):
		get_viewport().set_input_as_handled()   # the world behind waits


## Esc that no scene node used: the front window closes first, then the menu opens.
func _unhandled_input(event: InputEvent) -> void:
	if _open or not event is InputEventKey or not event.pressed or event.echo: return
	if (event as InputEventKey).keycode != KEY_ESCAPE: return
	var windows := get_tree().get_first_node_in_group("ui_window_manager")
	if windows != null and windows.close_front():
		get_viewport().set_input_as_handled()
		return
	if saves.is_loading() or WorldClock.is_loading_held(): return
	get_viewport().set_input_as_handled()
	open()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST: return
	# Nothing to keep while the world is still being made or loaded.
	if saves.is_loading() or not _colony_ready():
		quit_game.call()
		return
	open()
	if _open: _ask("exit")


func _navigates(event: InputEvent) -> bool:
	for action: String in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_select", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action(action): return true
	return false


## A key the name field takes while it has focus: text, and the keys that edit it.
func _types(event: InputEventKey) -> bool:
	return _name_field.has_focus() and (event.unicode >= 32 or event.keycode in EDIT_KEYS or event.is_command_or_control_pressed())


func _back() -> void:
	if not _question.is_empty(): _close_question()
	elif _page != "menu" and _title_page.is_empty(): _show_page("menu")
	else: close()


# ── Building ──────────────────────────────────────────────────────────────────

func _build() -> void:
	var band: Color = UIRegistry.get_icon_family_color("system")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.family_theme(band)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(_dim(0.55))
	var parts := _framed(band, close)
	_frame = parts.frame
	_title = parts.title
	_root.add_child(_centered(_frame))
	var body: MarginContainer = parts.body
	var pages := VBoxContainer.new()
	body.add_child(pages)
	_menu = VBoxContainer.new()
	pages.add_child(_menu)
	_date = _label(true, UITheme.CARD_TITLE, 5)
	_menu.add_child(_date)
	_time = _label(false, UITheme.HEARTH_MUTED)
	_menu.add_child(_time)
	_saved = PanelContainer.new()
	_saved.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_menu.add_child(_saved)
	_saved_label = _label(false, UITheme.CARD_TEXT)
	_saved.add_child(_saved_label)
	# Save game and Save as… share a row, so the menu still fits a 1280 × 720 screen.
	var saving := HBoxContainer.new()
	for entry: Array in [["resume", "Resume"], ["save", "Save game"], ["save_as", "Save as…"], ["load", "Load game…"],
			["new_game", "New game…"], ["settings", "Settings…"], ["quit_to_title", "Quit to main menu…"], ["exit", "Exit game…"]]:
		var button := Button.new()
		button.text = entry[1]
		UITheme.apply_hearth_button(button, entry[0] == "resume")
		button.pressed.connect(_choose.bind(String(entry[0])))
		_buttons[entry[0]] = button
		if entry[0] in ["save", "save_as"]:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			saving.add_child(button)
			if saving.get_parent() == null: _menu.add_child(saving)
		else:
			_menu.add_child(button)
	_menu_hint = _label(false, UITheme.HEARTH_MUTED)
	_menu_hint.text = "Esc returns to the game"
	_menu.add_child(_menu_hint)
	_load = VBoxContainer.new()
	pages.add_child(_load)
	_load_intro = _label(false, UITheme.HEARTH_MUTED)
	_load_intro.text = "Choose a save. Your colony goes back to that moment."
	_load.add_child(_load_intro)
	_slots = VBoxContainer.new()
	_load.add_child(_slots)
	var foot := _foot()
	_load.add_child(foot)
	_back_button = foot.get_child(0)
	_load_hint = foot.get_child(1)
	_folder_button = Button.new()
	_folder_button.text = "Open folder"
	_folder_button.tooltip_text = "Show the folder your named saves are kept in"
	UITheme.apply_hearth_button(_folder_button)
	_folder_button.pressed.connect(func(): saves.open_saves_folder())
	foot.add_child(_folder_button)
	foot.move_child(_folder_button, 1)
	_build_save_as(pages)
	_settings = Settings.new()
	_settings.back_requested.connect(_back)
	pages.add_child(_settings)
	# The question stands in front of the menu, with a veil over it.
	_veil = _dim(0.45)
	_veil.visible = false
	_root.add_child(_veil)
	var ask := _framed(band, _close_question)
	_ask_frame = ask.frame
	_ask_title = ask.title
	var ask_center := _centered(_ask_frame)
	ask_center.visible = false
	_root.add_child(ask_center)
	var ask_body := VBoxContainer.new()
	ask_body.add_theme_constant_override("separation", 24)
	ask.body.add_child(ask_body)
	_ask_body = _label(false, UITheme.CARD_TEXT)
	_ask_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask_body.add_child(_ask_body)
	_ask_buttons = HBoxContainer.new()
	_ask_buttons.add_theme_constant_override("separation", 16)
	ask_body.add_child(_ask_buttons)


## The Save as… page: its line, the name field (the founding card's, doc 23) with Save, the
## line under the field, Your saves in a list that scrolls, and Back.
func _build_save_as(pages: VBoxContainer) -> void:
	_save_as = VBoxContainer.new()
	pages.add_child(_save_as)
	_save_intro = _label(false, UITheme.HEARTH_MUTED)
	_save_as.add_child(_save_intro)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	_save_as.add_child(line)
	_name_field = LineEdit.new()
	_name_field.name = "Name"
	_name_field.max_length = SaveName.MAX_LENGTH
	_name_field.select_all_on_focus = true
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.add_theme_font_override("font", UITheme.display_font())
	_name_field.add_theme_color_override("font_color", UITheme.CARD_TITLE)
	_name_field.add_theme_color_override("caret_color", UITheme.TAG_TONES.waiting[0])
	for state: String in ["normal", "focus"]: _name_field.add_theme_stylebox_override(state, UITheme.cell_style("inset", 3))
	_name_field.text_changed.connect(func(_text: String): _check_name())
	_name_field.text_submitted.connect(func(_text: String): _submit_name())
	line.add_child(_name_field)
	_save_button = Button.new()
	_save_button.name = "Save"
	_save_button.text = "Save"
	UITheme.apply_hearth_button(_save_button, true)
	_save_button.pressed.connect(_submit_name)
	line.add_child(_save_button)
	_name_note = _label(false, UITheme.HEARTH_MUTED)
	_save_as.add_child(_name_note)
	_save_heading = _label(true, UITheme.CARD_TITLE)
	_save_as.add_child(_save_heading)
	_save_scroll = _scroll()
	_save_as.add_child(_save_scroll)
	_save_list = _save_scroll.get_child(0)
	var foot := _foot()
	_save_as.add_child(foot)
	_save_back = foot.get_child(0)
	_save_hint = foot.get_child(1)


## Back and the line beside it, at the foot of a page.
func _foot() -> HBoxContainer:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	var back := Button.new()
	back.text = "Back"
	UITheme.apply_hearth_button(back)
	back.pressed.connect(_back)
	foot.add_child(back)
	var hint := _label(false, UITheme.HEARTH_MUTED)
	hint.text = "Esc goes back to the menu"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	return foot


## A list of saves that scrolls up and down, its rows in a column.
func _scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return scroll


## A window's frame without its dragging (UIWindow's pieces): the slab with the family band,
## the title on it and a keycap that closes.
func _framed(band: Color, on_close: Callable) -> Dictionary:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.window_frame(band))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	frame.add_child(column)
	var bar := MarginContainer.new()
	bar.custom_minimum_size.y = float(UITheme.WINDOW_BAND_ROWS * UITheme.CARD_CELL)
	bar.add_theme_constant_override("margin_left", 10)
	bar.add_theme_constant_override("margin_right", 8)
	bar.add_theme_constant_override("margin_top", 4)
	bar.add_theme_constant_override("margin_bottom", 4)
	column.add_child(bar)
	var header := HBoxContainer.new()
	bar.add_child(header)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.format_label(title, true, MEDIUM.name, UITheme.CARD_TITLE, 6)
	title.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	header.add_child(title)
	var shut := Button.new()
	UITheme.apply_close_button(shut)
	shut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shut.pressed.connect(on_close)
	header.add_child(shut)
	var body := MarginContainer.new()
	for side: String in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 18)
	body.add_theme_constant_override("margin_top", 14)
	body.add_theme_constant_override("margin_bottom", 16)
	column.add_child(body)
	return {"frame": frame, "title": title, "body": body}


func _dim(alpha: float) -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.06, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind takes a click
	return dim


func _centered(child: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(child)
	return center


func _label(display: bool, color: Color, outline := 0) -> Label:
	var label := Label.new()
	UITheme.format_label(label, display, MEDIUM.heading, color, outline)
	if outline > 0: label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	return label


# ── Pages ─────────────────────────────────────────────────────────────────────

func _show_page(page: String) -> void:
	_page = page
	_menu.visible = page == "menu"
	_load.visible = page == "load"
	_save_as.visible = page == "save_as"
	_settings.visible = page == "settings"
	_title.text = {"menu": _menu_title(), "load": "Load a colony", "save_as": "Save as…", "settings": "Settings"}[page]
	if page == "load":
		_load_intro.text = "Choose a save to play." if not _title_page.is_empty() else "Choose a save. Your colony goes back to that moment."
		_show_slots()
	if page == "save_as": _show_save_as()
	if page == "settings": _settings.show_section(_settings.section)
	_refresh()
	_frame.reset_size()
	_page_focus().grab_focus.call_deferred()


## The menu page's title: the settlement's name once it is founded (doc 23), else the game's.
func _menu_title() -> String:
	var title := _colony_name()
	return "Deepdraft" if title.is_empty() else title


## The settlement's name, or "" before it is founded.
func _colony_name() -> String:
	var settlement := get_tree().get_first_node_in_group("settlement")
	return String(settlement.settlement_name) if settlement != null else ""


func _refresh() -> void:
	var busy: bool = saves.is_saving() or saves.is_loading()
	_date.text = "%s, day %d · Year %d" % [String(WorldClock.season).capitalize(), WorldClock.day, WorldClock.year]
	_time.text = "%s · paused while this menu is open" % WorldClock.time_string()
	var saved_unix: int = saves.colony_saved_unix()
	var fresh := saved_unix > 0 and int(Time.get_unix_time_from_system()) - saved_unix < 60
	_saved_label.text = "Saving…" if saves.is_saving() else ("Last saved %s" % ago(saved_unix) if saved_unix > 0 else "Not saved yet")
	_saved.add_theme_stylebox_override("panel", UITheme.cell_style("tag_fine" if fresh else "tag_waiting", 3))
	_saved_label.add_theme_color_override("font_color", UITheme.tag_ink("fine" if fresh else "waiting"))
	_buttons.save.disabled = busy or not _colony_ready()
	_buttons.save_as.disabled = busy or not _colony_ready()
	_buttons.load.disabled = busy
	_buttons.new_game.disabled = busy
	_buttons.quit_to_title.disabled = busy
	if _page == "save_as": _check_name()


## The Load page: the quick save and the autosave on the pine board, each with its date in
## the colony, when it was saved, Load, and Delete while it holds a save; a missing slot says
## so and cannot be chosen. Then the player's named saves, newest first, with Load and
## Delete, in a list that scrolls.
func _show_slots() -> void:
	for child: Node in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var s := _size
	var named: Array = []
	for slot: Dictionary in saves.save_slots():
		if slot.get("named", false):
			named.append(slot)
			continue
		var board := PanelContainer.new()
		board.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
		_slots.add_child(board)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		board.add_child(row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 4)
		row.add_child(words)
		var exists := bool(slot.exists)
		words.add_child(_ink(String(slot.name), true, int(s.slot), UITheme.CATALOG_INK if exists else UITheme.CATALOG_MUTED))
		words.add_child(_ink(String(NOTES.get(slot.id, "")), false, int(s.note), UITheme.CATALOG_MUTED))
		if exists:
			var date := slot_date(slot)
			if not String(slot.get("colony", "")).is_empty(): date = String(slot.colony) + " · " + date
			words.add_child(_ink(date, true, int(s.slot_date), UITheme.CATALOG_INK))
			words.add_child(_ink("Saved %s · %s" % [ago(int(slot.saved_unix)), _local(int(slot.saved_unix))], false, int(s.body), UITheme.CATALOG_MUTED))
		else:
			words.add_child(_ink("No %s yet." % String(slot.name).to_lower(), true, int(s.slot_date), UITheme.CATALOG_MUTED))
		# Load, and under it Delete while the slot holds a save.
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", s.gap)
		stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stack)
		var pick := Button.new()
		pick.name = "Load_" + String(slot.id)
		pick.text = "Load"
		UITheme.apply_hearth_button(pick, exists)
		pick.disabled = not exists or saves.is_saving() or saves.is_loading()
		pick.custom_minimum_size = Vector2(float(s.button) * 2.7, float(s.button))
		pick.add_theme_font_size_override("font_size", s.verb)
		pick.pressed.connect(_pick_load.bind(slot))
		stack.add_child(pick)
		if exists:
			var drop := Button.new()
			drop.name = "Delete_" + String(slot.id)
			drop.text = "Delete"
			UITheme.apply_hearth_button(drop)
			drop.disabled = saves.is_saving() or saves.is_loading()
			drop.custom_minimum_size = Vector2(float(s.button) * 2.7, float(s.button) * 0.8)
			drop.add_theme_font_size_override("font_size", s.plain)
			drop.pressed.connect(_ask.bind("delete_" + String(slot.id), slot))
			stack.add_child(drop)
	_slots.add_child(_ink(saves_heading(named), true, int(s.slot_date), UITheme.CARD_TITLE))
	if named.is_empty():
		_slots.add_child(_ink("Save as… in the game menu keeps your colony under a name.", false, int(s.note), UITheme.HEARTH_MUTED))
		return
	var scroll := _scroll()
	_slots.add_child(scroll)
	var list: VBoxContainer = scroll.get_child(0)
	list.add_theme_constant_override("separation", s.gap)
	for slot: Dictionary in named:
		list.add_child(_save_row(slot, [["Load", true, _pick_load.bind(slot), "Load_"],
			["Delete", false, _ask.bind("delete_" + String(slot.id), slot), "Delete_"]]))
	_fit_list(_load, scroll, list)


## A Load button: from the title no colony runs yet, so nothing is lost and nothing asks.
func _pick_load(slot: Dictionary) -> void:
	if _title_page.is_empty(): _ask("load_" + String(slot.id), slot)
	else: _confirm_load(String(slot.id))


## The Save as… page: the name Save as… suggests, chosen so typing replaces it, then the
## player's named saves, newest first, each with Replace.
func _show_save_as() -> void:
	var named := _named_slots()
	var colony := _colony_name()
	_save_intro.text = "Name this save. It keeps %s as it is now, beside the quick save and the autosave." % (
		colony if not colony.is_empty() else "your colony")
	_name_field.text = SaveName.suggestion(colony, String(WorldClock.season), WorldClock.day,
		named.map(func(slot: Dictionary) -> String: return String(slot.name)))
	_name_field.caret_column = _name_field.text.length()
	_save_heading.text = saves_heading(named)
	for child: Node in _save_list.get_children():
		_save_list.remove_child(child)
		child.queue_free()
	for slot: Dictionary in named:
		_save_list.add_child(_save_row(slot, [["Replace", false, _ask.bind("replace_" + String(slot.id), slot, String(slot.name)), "Replace_"]]))
	_check_name()
	_fit_list(_save_as, _save_scroll, _save_list)


func _named_slots() -> Array:
	return saves.save_slots().filter(func(slot: Dictionary) -> bool: return slot.get("named", false))


## The named save with this name, capitals aside, or {}.
func _named_slot(name: String) -> Dictionary:
	for slot: Dictionary in _named_slots():
		if SaveName.key(String(slot.name)) == SaveName.key(name): return slot
	return {}


## One of the player's named saves on a compact board: its name with how long ago it was saved
## at its right, its colony and date under it, and the page's buttons, each [text, main,
## action, node name before the save's id].
func _save_row(slot: Dictionary, choices: Array) -> PanelContainer:
	var s := _size
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UITheme.catalog_paper_style(true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", s.gap)
	board.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", s.gap)
	words.add_child(top)
	var title := _ink(String(slot.name), true, int(s.slot_date), UITheme.CATALOG_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	top.add_child(_ink(ago(int(slot.saved_unix)), false, int(s.note), UITheme.CATALOG_MUTED))
	var colony := String(slot.get("colony", ""))
	var line := _ink((colony + " · " if not colony.is_empty() else "") + slot_date(slot), false, int(s.note), UITheme.CATALOG_MUTED)
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(line)
	for choice: Array in choices:
		var button := Button.new()
		button.name = String(choice[3]) + String(slot.id)
		button.text = choice[0]
		UITheme.apply_hearth_button(button, choice[1])
		button.custom_minimum_size = Vector2(float(s.button) * 1.9, float(s.button) * 0.8)
		button.add_theme_font_size_override("font_size", s.verb if choice[1] else s.plain)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = saves.is_saving() or saves.is_loading()
		button.pressed.connect(choice[2])
		row.add_child(button)
	return board


## A page's list of saves scrolls in the room the screen leaves the page, and is never taller
## than its rows.
func _fit_list(page: Control, scroll: ScrollContainer, list: Control) -> void:
	scroll.custom_minimum_size.y = 0.0
	var room := get_viewport().get_visible_rect().size.y - FRAME_ROOM - page.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = clampf(list.get_combined_minimum_size().y, 0.0, maxf(room, 0.0))
	_frame.reset_size()


## Save stays off while the name breaks the rules. The line under the field gives the rules,
## or says that saving replaces the save of that name.
func _check_name() -> void:
	var name := SaveName.clean(_name_field.text)
	var valid := SaveName.is_valid(name)
	var clash := _named_slot(name) if valid else {}
	_save_button.disabled = not valid or saves.is_saving() or saves.is_loading() or not _colony_ready()
	_name_note.text = SaveName.RULE if clash.is_empty() else "\"%s\" is a save already: Save asks before replacing it." % String(clash.name)
	var tone: Color = UITheme.HEARTH_MUTED if valid and clash.is_empty() else (UITheme.TAG_TONES.waiting[0] if valid else UITheme.TAG_TONES.blocked[1])
	_name_note.add_theme_color_override("font_color", tone)


## Save, or Enter in the field: a new name saves at once, a name in use asks first.
func _submit_name() -> void:
	if _save_button.disabled: return
	var name := SaveName.clean(_name_field.text)
	var clash := _named_slot(name)
	if clash.is_empty(): _save_as_now(name)
	else: _ask("replace_" + String(clash.id), clash, name)


## The save starts, and the menu page's tag says so, as Save game's does.
func _save_as_now(name: String) -> void:
	if saves.request_save_as(name): _show_page("menu")


func _ink(text: String, display: bool, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, display, size, color)
	return label


func _choose(id: String) -> void:
	match id:
		"resume": close()
		"save":
			saves.request_save()
			_refresh()
		"save_as": _show_page("save_as")
		"load": _show_page("load")
		"new_game": _ask("new_game")
		"settings": _show_page("settings")
		"quit_to_title": _ask("quit_to_title")
		"exit": _ask("exit")


# ── Questions ─────────────────────────────────────────────────────────────────

## A question in front of the menu: what happens, how long since the colony was last saved,
## and the choices, the main one first. Cancel, ✕ or Esc closes it. Load, Replace and Delete
## name the save they are about; Replace also takes the name the save is kept under.
func _ask(kind: String, slot: Dictionary = {}, save_name := "") -> void:
	_question = kind
	var since := _since()
	var choices: Array = [["Cancel", "", _close_question]]
	var colony := _colony_name()
	var here := colony if not colony.is_empty() else "your colony"
	var subject := colony if not colony.is_empty() else "Your colony"
	if kind.begins_with("load_"):
		if slot.is_empty():
			for entry: Dictionary in saves.save_slots():
				if "load_" + String(entry.id) == kind: slot = entry
		var named := bool(slot.get("named", false))
		_ask_title.text = "Load \"%s\"?" % String(slot.get("name", "")) if named else "Load the %s?" % String(slot.get("name", "save")).to_lower()
		_ask_body.text = "Your colony goes back to %s. %s" % [_when(slot), since]
		choices.push_front(["Load", "main", _confirm_load.bind(String(slot.get("id", kind.trim_prefix("load_"))))])
	elif kind.begins_with("replace_"):
		# Replacing another colony's save loses that colony, so it says so and Cancel leads.
		var held := String(slot.get("colony", ""))
		_ask_title.text = "Replace \"%s\"?" % String(slot.name)
		if _other_colony(slot):
			var lost := held if not held.is_empty() else "a colony not yet named"
			_ask_body.text = "\"%s\" holds another colony, %s, on %s, saved %s. %s takes its place, and %s is lost." % [
				String(slot.name), lost, _when(slot), ago(int(slot.saved_unix)), subject, lost]
			choices = [["Replace " + held if not held.is_empty() else "Replace it", "danger", _confirm_replace.bind(save_name)],
				["Cancel", "main", _close_question]]
		else:
			_ask_body.text = "It holds %s on %s, saved %s. %s as it is now takes its place." % [
				held if not held.is_empty() else "your colony", _when(slot), ago(int(slot.saved_unix)), subject]
			choices.push_front(["Replace", "main", _confirm_replace.bind(save_name)])
	elif kind.begins_with("delete_"):
		# Any save may go, the quick save and the autosave too; they are written again later.
		var held := String(slot.get("colony", ""))
		var named := bool(slot.get("named", false))
		_ask_title.text = "Delete \"%s\"?" % String(slot.name) if named else "Delete the %s?" % String(slot.name).to_lower()
		var after: String = "and it leaves this list." if named else {"quick": "and Save game writes the next one.",
			"auto": "and the next comes after five minutes of play."}.get(String(slot.id), "")
		_ask_body.text = "%s on %s, saved %s. Its files go to the Recycle Bin, %s" % [
			held if not held.is_empty() else "A colony not yet named", _when(slot), ago(int(slot.saved_unix)), after]
		choices = [["Delete", "danger", _confirm_delete.bind(String(slot.id))], ["Cancel", "main", _close_question]]
	match kind:
		"new_game":
			_ask_title.text = "Start a new colony?"
			_ask_body.text = ("A new world grows from a fresh seed. Your saves stay as they are, but once the new colony saves, "
				+ "its quick save and autosave replace the ones you have. Save as… first keeps %s under a name. %s") % [here, since]
			if _colony_ready(): choices.push_front(["Save as… first", "", _save_as_first])
			choices.push_front(["Start a new colony", "main", _confirm_new_game])
		"exit", "quit_to_title":
			var leaving := kind == "exit"
			_ask_title.text = "Exit Deepdraft?" if leaving else "Quit to the main menu?"
			var saved_unix: int = saves.colony_saved_unix()
			_ask_body.text = "Your colony was last saved %s." % ago(saved_unix) if saved_unix > 0 else "Your colony has not been saved."
			choices = [["Exit without saving" if leaving else "Quit without saving", "danger",
				_exit_now if leaving else _quit_to_title_now], choices[0]]
			if _colony_ready():
				choices.push_front(["Save and exit" if leaving else "Save and quit", "main", _save_then.bind(kind)])
	for child: Node in _ask_buttons.get_children():
		_ask_buttons.remove_child(child)
		child.queue_free()
	var focus: Button = null
	for choice: Array in choices:
		var button := Button.new()
		button.name = String(choice[0]).replace(" ", "").replace("…", "")
		button.text = choice[0]
		UITheme.apply_hearth_button(button, choice[1] == "main")
		if choice[1] == "danger": UITheme.apply_button_variant(button, "danger")
		button.custom_minimum_size.y = float(_size.button)
		button.add_theme_font_size_override("font_size", _size.verb if choice[1] == "main" else _size.plain)
		button.pressed.connect(choice[2])
		_ask_buttons.add_child(button)
		# Cancel is the safe default, except leaving, where saving first is.
		if choice[0] == {"exit": "Save and exit", "quit_to_title": "Save and quit"}.get(kind, "Cancel"): focus = button
	if focus == null: focus = _ask_buttons.get_child(_ask_buttons.get_child_count() - 1)
	_veil.visible = true
	_ask_frame.get_parent().visible = true
	_ask_frame.reset_size()
	focus.grab_focus.call_deferred()


## A save's date in the colony and its year, as a question says it: "autumn, day 7, year 1".
static func _when(slot: Dictionary) -> String:
	return "%s, day %d, year %d" % [String(slot.get("season", "")).to_lower(), int(slot.get("day", 0)), int(slot.get("year", 0))]


## Whether a named save holds another colony than this one: another world's seed.
func _other_colony(slot: Dictionary) -> bool:
	return int(slot.get("seed", 0)) != 0 and int(slot.get("seed", 0)) != int(WorldGenerator.world_seed)


## What a question loses: everything since this colony's last save.
func _since() -> String:
	var saved_unix: int = saves.colony_saved_unix()
	if saved_unix <= 0: return "This colony has not been saved, so all of it is lost."
	return "Anything since your last save, %s, is lost." % ago(saved_unix)


func _close_question() -> void:
	_question = ""
	_after_save = ""
	_veil.visible = false
	_ask_frame.get_parent().visible = false
	_page_focus().grab_focus.call_deferred()


## The menu closes first, so the load sees the player's own pause, not the menu's hold.
func _confirm_load(id: String) -> void:
	close()
	saves.request_load_save(id)


func _confirm_replace(save_name: String) -> void:
	_close_question()
	_save_as_now(save_name)


## The save goes, and the page lists what is left.
func _confirm_delete(id: String) -> void:
	_close_question()
	saves.request_delete_save(id)
	_show_page(_page)


func _confirm_new_game() -> void:
	close()
	saves.request_new_game()


## New game's Save as… first: the Save as… page, so the colony keeps a name before a new one
## starts.
func _save_as_first() -> void:
	_close_question()
	_show_page("save_as")


func _exit_now() -> void:
	quit_game.call()


## The menu closes first; SaveManager clears the colony and shows the title screen.
func _quit_to_title_now() -> void:
	close()
	saves.request_quit_to_title()


## Save and exit, or Save and quit to the title: the save, then the leaving once it is written.
func _save_then(kind: String) -> void:
	_after_save = "exit" if kind == "exit" else "title"
	if not saves.request_save():
		_after_save = ""
		_ask_body.text = "The colony could not be saved just now, so the game is still open."
		return
	_ask_body.text = "Saving…"
	for button: Button in _ask_buttons.get_children(): button.disabled = true


func _on_save_finished(success: bool) -> void:
	if not _after_save.is_empty():
		var leaving := _after_save
		_after_save = ""
		if success:
			if leaving == "exit": quit_game.call()
			else: _quit_to_title_now()
			return
		_ask_body.text = "The save failed, so the game is still open. %s without saving, or try again later." % (
			"Exit" if leaving == "exit" else "Quit")
		for button: Button in _ask_buttons.get_children(): button.disabled = false
	if _open: _refresh()


# ── Words and sizes ───────────────────────────────────────────────────────────

func _colony_ready() -> bool:
	return bool(WorldGenerator.get_streaming_stats().get("maps_ready", false))


## How long ago a Unix time was, as the menu and the title screen say it: "3 days ago".
static func ago(stamp: int) -> String:
	var seconds := int(Time.get_unix_time_from_system()) - stamp
	if seconds < 60: return "just now"
	if seconds < 3600: return "%d minute%s ago" % [seconds / 60, "" if seconds < 120 else "s"]
	if seconds < 86400: return "%d hour%s ago" % [seconds / 3600, "" if seconds < 7200 else "s"]
	return "%d day%s ago" % [seconds / 86400, "" if seconds < 172800 else "s"]


static func _local(stamp: int) -> String:
	var when := Time.get_datetime_dict_from_unix_time(stamp + int(Time.get_time_zone_from_system().bias) * 60)
	return "%d %s, %02d:%02d" % [int(when.day), MONTHS[int(when.month) - 1], int(when.hour), int(when.minute)]


static func _hour(hour: float) -> String:
	return "%02d:%02d" % [int(hour) % 24, int((hour - floorf(hour)) * 60.0)]


## A save slot's date in the colony, as the Load page and the title screen show it:
## "Autumn, day 8 · Year 1 · 02:14".
static func slot_date(slot: Dictionary) -> String:
	return "%s, day %d · Year %d · %s" % [String(slot.get("season", "")).capitalize(), int(slot.get("day", 0)),
		int(slot.get("year", 0)), _hour(float(slot.get("hour", 0.0)))]


## Your saves' heading: how many there are and the room their files take ("Your saves ·
## 4 saves · 98 MB").
static func saves_heading(named: Array) -> String:
	if named.is_empty(): return "Your saves · none yet"
	var bytes := 0
	for slot: Dictionary in named: bytes += int(slot.get("bytes", 0))
	return "Your saves · %d save%s · %d MB" % [named.size(), "" if named.size() == 1 else "s", maxi(1, roundi(bytes / 1000000.0))]


func _apply_size() -> void:
	var height := get_viewport().get_visible_rect().size.y
	var key := "large" if height >= 1300.0 else ("small" if height < 650.0 else "medium")
	_size = SIZES[key]
	var s := _size
	_title.add_theme_font_size_override("font_size", LARGE.heading if s == SIZES.large else MEDIUM.heading)
	_ask_title.add_theme_font_size_override("font_size", LARGE.heading if s == SIZES.large else MEDIUM.heading)
	_menu.custom_minimum_size.x = float(s.menu)
	_menu.add_theme_constant_override("separation", s.gap)
	_buttons.save.get_parent().add_theme_constant_override("separation", s.gap)
	_date.add_theme_font_size_override("font_size", s.date)
	_time.add_theme_font_size_override("font_size", s.body)
	_saved_label.add_theme_font_size_override("font_size", s.note)
	for id: String in _buttons:
		var button: Button = _buttons[id]
		button.custom_minimum_size.y = float(s.button)
		button.add_theme_font_size_override("font_size", s.verb if id == "resume" else s.plain)
	_menu_hint.add_theme_font_size_override("font_size", s.note)
	for page: VBoxContainer in [_load, _save_as]:
		page.custom_minimum_size.x = float(s.page)
		page.add_theme_constant_override("separation", s.gap * 2)
	_slots.add_theme_constant_override("separation", s.gap * 2)
	_save_list.add_theme_constant_override("separation", s.gap)
	_load_intro.add_theme_font_size_override("font_size", s.body)
	_save_intro.add_theme_font_size_override("font_size", s.body)
	_name_field.add_theme_font_size_override("font_size", s.slot)
	_save_button.custom_minimum_size = Vector2(float(s.button) * 2.7, float(s.button))
	_save_button.add_theme_font_size_override("font_size", s.verb)
	_name_note.add_theme_font_size_override("font_size", s.note)
	_save_heading.add_theme_font_size_override("font_size", s.slot_date)
	for button: Button in [_back_button, _save_back, _folder_button]:
		button.custom_minimum_size = Vector2(float(s.button) * 2.8, float(s.button) * 0.9)
		button.add_theme_font_size_override("font_size", s.plain)
	for hint: Label in [_load_hint, _save_hint]: hint.add_theme_font_size_override("font_size", s.note)
	_ask_body.custom_minimum_size.x = float(s.ask) - 36.0
	_ask_body.add_theme_font_size_override("font_size", s.type.heading)
	_settings.apply_size(key, height - FRAME_ROOM)
	if _open and _page == "load": _show_slots()
	if _open and _page == "save_as": _fit_list(_save_as, _save_scroll, _save_list)


## Where keyboard focus goes on each page: Resume, Back on Load, the name on Save as…, the
## open section's first control in Settings.
func _page_focus() -> Control:
	match _page:
		"load": return _back_button
		"save_as": return _name_field
		"settings": return _settings.first_focus()
	return _buttons.resume
