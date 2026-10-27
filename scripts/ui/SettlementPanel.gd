extends MarginContainer

## Colony's page (doc 23): the settlement at a glance, as Colony's window in the people
## family, opening where windows open, with the rows at a glance beside the journal.
## - The header: the flag on its tile, the settlement's name with Rename, when it was
##   founded and how many dwarves it has, a badge for each profession, and at the right the
##   colony's mood: the face for its average step, the word in its tone, the step's line
##   and its happiness of 100.
## - Colony's entries (dock.json's "colony"): Dwarves, Labor, Settlement flag and the
##   planned Trade. Each closes the page and opens its own window or view.
## - At a glance: dwarves at work, food in days, own bedrooms, storage and happiness, each
##   with its picture, what it counts and its value in words. The last four fill a meter
##   toward their goal (settlement_page.json) in the tag tones: moss when met, hay below,
##   rust when short.
## - The journal beside the rows (ColonyJournal): what the dwarves said, newest day first,
##   complaints then praises, a line per topic with the speaker's face, name and words and
##   how many share it. It is as tall as the rows, and only it scrolls. Small or narrow
##   screens set it under the rows, and the two scroll together.
## - Before the flag is planted: "No settlement yet" and Found the settlement, which starts
##   the flag tool.
## Rename turns the name into a field with Suggest another and Done; Esc leaves the name as
## it was. The page reads the colony each second while it is open; FlagPlacementController
## keeps the name. Sizes follow the screen's height, and the body scrolls above the dock.
signal entry_requested(target: String)

const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const SettlementName = preload("res://scripts/components/SettlementName.gd")
const MUTED := Color("aeb5ad")
const SOFT := Color("bdb8a9")
const RULE := Color("27312f")
const HAY := Color("e2c06a")
const REFRESH_SECONDS := 1.0
const ROWS := {"dwarves": "Dwarves", "food": "Food", "beds": "Beds", "storage": "Storage", "happiness": "Happiness"}
const GROUPS := [["working", "fine"], ["resting", "waiting"], ["idle", "waiting"]]
const BEFORE := "Plant the settlement flag to found it. Your dwarves arrive with it."
const JOURNAL_INTRO := "What your dwarves said, newest first."
const JOURNAL_EMPTY := "Nothing yet. When something begins to please or trouble a dwarf, their words land here, a line for each thought a day."
const PARTS := [["complaint", "Complaints", "blocked"], ["praise", "Praises", "fine"]]
## A speaker who has left, or one the page never saw.
const NO_FACE := "res://assets/ui/icons/dwarves.png"
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as Colony Dwarves': large from 1300 px tall (the concept's,
## on the 7680×2160 screen), medium from 900, short from 650 (all five rows above the dock at
## 1280×720, clear of the Sky Dial), small below. `width` has the journal beside the rows
## (the rows at least `glance` across); `narrow` sets it under them, on small screens and
## wherever `width` does not fit across. Small screens show the badges' counts alone.
const SIZES := {
	"large": {"width": 1560, "narrow": 1240, "glance": 720, "margin": 22, "gap": 14, "flag": 136, "name": LARGE.display, "line": LARGE.body,
		"badge": 52, "face": 112, "mood": 300, "word": LARGE.title, "entry": 60, "icon": 40, "heading": LARGE.heading, "tile": 84, "label": LARGE.body,
		"value": LARGE.heading, "sub": LARGE.body, "tag": LARGE.small, "meter": Vector2(330, 24), "button": 42, "portrait": 68, "who": LARGE.body, "quote": LARGE.body, "day": LARGE.lead, "type": LARGE},
	"medium": {"width": 1200, "narrow": 920, "glance": 540, "margin": 16, "gap": 10, "flag": 96, "name": MEDIUM.display, "line": MEDIUM.body,
		"badge": 38, "face": 80, "mood": 230, "word": MEDIUM.title, "entry": 46, "icon": 30, "heading": MEDIUM.heading, "tile": 60, "label": MEDIUM.body,
		"value": MEDIUM.heading, "sub": MEDIUM.body, "tag": MEDIUM.small, "meter": Vector2(240, 18), "button": 34, "portrait": 50, "who": MEDIUM.body, "quote": MEDIUM.body, "day": MEDIUM.lead, "type": MEDIUM},
	"short": {"width": 1020, "narrow": 860, "glance": 470, "margin": 12, "gap": 6, "flag": 64, "name": SMALL.display, "line": SMALL.body,
		"badge": 28, "face": 58, "mood": 210, "word": SMALL.title, "entry": 34, "icon": 22, "heading": SMALL.heading, "tile": 44, "label": SMALL.body,
		"value": SMALL.heading, "sub": SMALL.body, "tag": SMALL.small, "meter": Vector2(200, 14), "button": 30, "portrait": 40, "who": SMALL.body, "quote": SMALL.body, "day": SMALL.lead, "type": SMALL},
	"small": {"width": 680, "narrow": 680, "glance": 0, "margin": 10, "gap": 6, "flag": 56, "name": SMALL.display, "line": SMALL.body,
		"badge": 26, "face": 50, "mood": 160, "word": SMALL.title, "entry": 32, "icon": 22, "heading": SMALL.heading, "tile": 40, "label": SMALL.body,
		"value": SMALL.heading, "sub": SMALL.body, "tag": SMALL.small, "meter": Vector2(160, 12), "button": 28, "portrait": 36, "who": SMALL.body, "quote": SMALL.body, "day": SMALL.lead, "type": SMALL},
}

var window: UIWindow
## FlagPlacementController, which keeps the name; DockUI hands it over.
var settlement: Node
var _size: Dictionary = SIZES.medium
var _wide := true                # the journal beside the rows, not under them
var _dock_top := 600.0
var _refresh_left := 0.0
var _layout_pending := false
var _editing := false
var _suggestion := 0
var _shown: Array = []          # what the page shows, so a refresh that changes nothing keeps it
var _badges_shown: Array = []   # the badges and group tags shown, kept while they stay the same,
var _groups_shown: Array = []   # so a tooltip being read stays open
var _journal_shown: Array = []
var _founded_text := ""
var _textures := {}
var _faces := {}                 # dwarf id -> their head and shoulders, rendered once
var _studio: Node                # the portraits' viewports
var _column: VBoxContainer
var _header: HBoxContainer
var _name_row: HBoxContainer
var _name: Label
var _rename: Button
var _edit_row: HBoxContainer
var _field: LineEdit
var _done: Button
var _founded: Label
var _badges: HFlowContainer
var _found: Button
var _mood: HBoxContainer
var _face: TextureRect
var _mood_word: Label
var _mood_line: Label
var _mood_points: Label
var _entries: HFlowContainer
var _after_entries: ColorRect
var _heading: Label
var _scroll: ScrollContainer
var _body: BoxContainer
var _glance: VBoxContainer
var _list: VBoxContainer
var _rows := {}
var _journal: VBoxContainer
var _journal_scroll: ScrollContainer
var _journal_list: VBoxContainer
var _before: Label


func _ready() -> void:
	UITheme.apply_surface(self)
	_studio = Node.new()
	_studio.name = "Portraits"
	add_child(_studio)
	_column = VBoxContainer.new()
	add_child(_column)
	_build_header()
	_column.add_child(_rule())
	_entries = HFlowContainer.new()
	_entries.name = "Entries"
	_column.add_child(_entries)
	for entry: Dictionary in UIRegistry.get_menu("colony").get("items", []):
		_entries.add_child(_entry_button(entry))
	_after_entries = _rule()
	_column.add_child(_after_entries)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_column.add_child(_scroll)
	_body = BoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_glance = VBoxContainer.new()
	_glance.name = "Glance"
	_body.add_child(_glance)
	_heading = _label("At a glance", true, HAY, "heading")
	_glance.add_child(_heading)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_glance.add_child(_list)
	for id: String in ROWS: _rows[id] = _build_row(id)
	_build_journal()
	_before = _label("The rows at a glance and the journal begin once the settlement is founded.", false, MUTED, "line")
	_column.add_child(_before)
	_apply_size()


func _process(delta: float) -> void:
	if window == null or not window.visible: return
	_refresh_left -= delta
	if _refresh_left > 0.0: return
	_refresh_left = REFRESH_SECONDS
	refresh()


## The window has opened: the page reads the colony now, with the name as it is.
func begin_viewing() -> void:
	_editing = false
	_shown = []
	_scroll.scroll_vertical = 0
	_journal_scroll.scroll_vertical = 0
	_fit()


## Reads the colony and the journal and shows them, unless nothing changed since the last
## look.
func refresh() -> void:
	if not is_inside_tree() or (window != null and not window.visible): return
	var founded: bool = settlement != null and settlement.is_founded()
	var colony := read_colony(get_tree()) if founded else {}
	var state := [founded, _editing, String(settlement.settlement_name) if founded else "", colony, _size, _wide]
	var changed := state != _shown
	if changed:
		_shown = state
		_show_mode(founded)
		if founded: show_colony(colony)
	if founded and _show_journal(): changed = true
	if changed: _fit_height()


## The colony as the page reads it now: how many dwarves and which are working, resting
## or idle, its professions, its average happiness and main complaint, days of food, own
## bedrooms, and the storage cells used of all storage.
static func read_colony(tree: SceneTree) -> Dictionary:
	var colony := {"dwarves": 0, "groups": {"working": [], "resting": [], "idle": []}, "professions": {}, "points": 0,
		"complaint": {}, "food_days": 0.0, "beds": 0, "used": 0, "capacity": 0, "items": 0}
	var points := 0
	var complaints := {}
	var agents: Array[DwarfAgent] = []
	for agent: DwarfAgent in TaskManager.get_agents():
		if not is_instance_valid(agent): continue
		agents.append(agent)
		(colony.groups[String(Inspection.roster_state(agent).group)] as Array).append(agent.dwarf_name)
		colony.professions[agent.profession] = int(colony.professions.get(agent.profession, 0)) + 1
		points += int(agent.get_mood().points())
		var worst: Dictionary = agent.get_mood().strongest_negative_thought()
		if worst.is_empty(): continue
		var help := String(worst.help).get_slice(".", 0)
		var complaint: Dictionary = complaints.get(worst.reason, {"text": String(worst.reason), "count": 0,
			"help": "" if help.is_empty() else help + "."})
		complaint.count = int(complaint.count) + 1
		complaints[worst.reason] = complaint
	colony.dwarves = agents.size()
	colony.points = roundi(float(points) / maxi(1, agents.size()))
	for complaint: Dictionary in complaints.values():
		if colony.complaint.is_empty() or int(complaint.count) > int(colony.complaint.count): colony.complaint = complaint
	# Food: the edible goods' nutrition against what the dwarves eat in a day.
	var items := ItemDropManager.find(tree)
	if items != null and not agents.is_empty():
		var nutrition := 0.0
		var stock := Inventory.snapshot(items, tree.get_first_node_in_group("furniture_controller"))
		for key: String in stock:
			var food := items.food_definition(key)
			if not food.is_empty(): nutrition += int(stock[key].total) * float(food.nutrition)
		var daily := float(TaskManager.get_config_section("food").drain_per_hour) * WorldClock.hours_per_day() * agents.size()
		colony.food_days = nutrition / daily
	var owners := {}
	for room: Dictionary in RoomManager.get_rooms().values():
		if int(room.get("owner_id", -1)) >= 0: owners[int(room.owner_id)] = true
	for agent: DwarfAgent in agents:
		if owners.has(agent.dwarf_id): colony.beds = int(colony.beds) + 1
	for zone: StorageComponent in StockpileManager.get_zones():
		colony.used = int(colony.used) + zone.stored_entries().size()
		colony.capacity = int(colony.capacity) + zone.storage_capacity()
		var held := zone.contents()
		for key: String in held: colony.items = int(colony.items) + int(held[key])
	return colony


## Shows `colony` (read_colony's shape) in the header's counts and the rows.
func show_colony(colony: Dictionary) -> void:
	var count := int(colony.dwarves)
	_founded_text = "Founded %s · %s" % [_date(int(settlement.founded_day)), _count(count, "dwarf", "dwarves")]
	_check_name()
	_show_badges(colony.professions)
	var step := _step(int(colony.points))
	_mood.visible = count > 0
	_face.texture = _texture(String(step.icon))
	_mood_word.text = String(step.word)
	_mood_word.add_theme_color_override("font_color", UITheme.TAG_TONES[_tone(int(step.index))][1])
	_mood_line.text = String(step.line)
	_mood_points.text = "Happiness %d of 100" % int(colony.points)
	_show_rows(colony, count, step)


# ── The header ─────────────────────────────────────────────────────────────────

func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.name = "Header"
	_column.add_child(_header)
	_header.add_child(_picture(_texture(FlagPlacementController.PICTURE), "flag"))
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 6)
	_header.add_child(identity)
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 16)
	identity.add_child(_name_row)
	_name = _label("", true, UITheme.CARD_TITLE, "name")
	_name.name = "SettlementName"
	_name.add_theme_constant_override("outline_size", 6)
	_name.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_name_row.add_child(_name)
	_rename = _button("Rename", false, "Give the settlement a new name. Events keep the name they were written with.")
	_rename.pressed.connect(_begin_rename)
	_name_row.add_child(_rename)
	_edit_row = HBoxContainer.new()
	_edit_row.add_theme_constant_override("separation", 12)
	_edit_row.hide()
	identity.add_child(_edit_row)
	_field = LineEdit.new()
	_field.name = "NameField"
	_field.max_length = SettlementName.MAX_LENGTH
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.add_theme_font_override("font", UITheme.display_font())
	_field.add_theme_color_override("font_color", UITheme.CARD_TITLE)
	_field.add_theme_color_override("caret_color", HAY)
	for state: String in ["normal", "focus"]: _field.add_theme_stylebox_override(state, UITheme.cell_style("inset", 3))
	_field.set_meta("font_role", "value")
	_field.text_changed.connect(func(_text: String): _check_name())
	_field.text_submitted.connect(func(_text: String): _finish_rename())
	_field.gui_input.connect(_on_field_input)
	_edit_row.add_child(_field)
	var suggest := _button("Suggest another", false, "Draw the next name the world's seed suggests")
	suggest.pressed.connect(_suggest_name)
	_edit_row.add_child(suggest)
	_done = _button("Done", true, "Keep this name")
	_done.pressed.connect(_finish_rename)
	_edit_row.add_child(_done)
	_founded = _label("", false, MUTED, "line")
	identity.add_child(_founded)
	_badges = HFlowContainer.new()
	_badges.name = "Badges"
	identity.add_child(_badges)
	_found = _button("Found the settlement", true, "Choose where to plant the flag, then name the settlement")
	_found.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_found.pressed.connect(func(): entry_requested.emit("flag"))
	identity.add_child(_found)
	_mood = HBoxContainer.new()
	_mood.name = "Mood"
	_mood.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_header.add_child(_mood)
	var face := _picture(null, "face")
	_face = face.get_child(0)
	_mood.add_child(face)
	var words := VBoxContainer.new()
	words.name = "MoodWords"
	words.add_theme_constant_override("separation", 2)
	_mood.add_child(words)
	_mood_word = _label("", true, UITheme.CARD_TITLE, "word")
	words.add_child(_mood_word)
	_mood_line = _label("", false, SOFT, "line")
	_mood_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_mood_line)
	_mood_points = _label("", false, MUTED, "sub")
	words.add_child(_mood_points)


## The page before and after founding, and the name or its field.
func _show_mode(founded: bool) -> void:
	_name.text = String(settlement.settlement_name) if founded else "No settlement yet"
	_name.add_theme_color_override("font_color", UITheme.CARD_TITLE if founded else MUTED)
	_name_row.visible = not (founded and _editing)
	_rename.visible = founded
	_edit_row.visible = founded and _editing
	_badges.visible = founded
	_found.visible = not founded
	_entries.visible = founded
	_after_entries.visible = founded
	_heading.visible = founded
	_scroll.visible = founded
	_before.visible = not founded
	if not founded:
		_mood.visible = false
		_founded_text = BEFORE
		_check_name()


## A badge for each profession the colony has, in professions.json's order: its picture and
## how many ("3 Workers"; the count alone on small screens, the words on hover).
func _show_badges(professions: Dictionary) -> void:
	if [professions, _size] == _badges_shown: return
	_badges_shown = [professions, _size]
	for child: Node in _badges.get_children():
		_badges.remove_child(child)
		child.queue_free()
	for key: String in DwarfAssets.profession_ids():
		var count := int(professions.get(key, 0))
		if count <= 0: continue
		var definition: Dictionary = DwarfAssets.profession_definition(key)
		var words := "%d %s%s" % [count, String(definition.get("display_name", key)), "" if count == 1 else "s"]
		var badge := HBoxContainer.new()
		badge.name = "Badge"
		badge.tooltip_text = words
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.add_theme_constant_override("separation", 6)
		badge.add_child(_picture(_texture(String(definition.get("icon", ""))), "badge"))
		var label := _label(str(count) if _size == SIZES.small else words, false, UITheme.CARD_TEXT, "line")
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.add_child(label)
		_badges.add_child(badge)


# ── Rename ─────────────────────────────────────────────────────────────────────

func _begin_rename() -> void:
	_editing = true
	_field.text = String(settlement.settlement_name)
	refresh()
	_field.grab_focus()
	_field.select_all()


func _suggest_name() -> void:
	_suggestion += 1
	var suggestion := String(settlement.suggestion(_suggestion))
	if suggestion == SettlementName.clean(_field.text):
		_suggestion += 1
		suggestion = String(settlement.suggestion(_suggestion))
	_field.text = suggestion
	_field.caret_column = suggestion.length()
	_check_name()


func _finish_rename() -> void:
	if not _editing or not settlement.rename(_field.text): return
	_editing = false
	refresh()


func _on_field_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_field.accept_event()
		_editing = false
		refresh()


## While renaming, Done waits for a name in the rules, and the line under it says why.
func _check_name() -> void:
	var valid := not _editing or SettlementName.is_valid(_field.text)
	_done.disabled = not valid
	_founded.text = _founded_text if valid else SettlementName.RULE
	_founded.add_theme_color_override("font_color", MUTED if valid else UITheme.TAG_TONES.blocked[1])


# ── The rows ───────────────────────────────────────────────────────────────────

## A row: its picture, what it counts, the value in words, then a meter with its goal and
## tag (the Dwarves row: a tag for each group), and for Happiness the main complaint.
func _build_row(id: String) -> Dictionary:
	var row := {}
	var box := HBoxContainer.new()
	box.name = id.to_pascal_case()
	_list.add_child(box)
	row.box = box
	var picture := _picture(_texture(String(UIRegistry.get_settlement_page().get("rows", {}).get(id, {}).get("picture", ""))), "tile")
	row.art = picture.get_child(0)
	box.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	box.add_child(words)
	row.label = _label(ROWS[id], false, MUTED, "label")
	words.add_child(row.label)
	row.value = _label("", true, UITheme.CARD_TITLE, "value")
	row.value.name = "Value"
	words.add_child(row.value)
	row.line = HBoxContainer.new()
	words.add_child(row.line)
	if id != "dwarves":
		row.meter = Meter.new()
		row.meter.name = "Meter"
		row.meter.set_meta("meter_role", "meter")
		row.meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.line.add_child(row.meter)
		row.goal = _label("", false, MUTED, "sub")
		row.goal.name = "Goal"
		row.goal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.line.add_child(row.goal)
		row.tag = _tag("", "fine")
		row.line.add_child(row.tag)
	if id == "happiness":
		row.note = _label("", false, SOFT, "sub")
		row.note.name = "Note"
		row.note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(row.note)
	return row


func _show_rows(colony: Dictionary, count: int, step: Dictionary) -> void:
	var page: Dictionary = UIRegistry.get_settlement_page().get("rows", {})
	_rows.dwarves.value.text = _count(count, "dwarf", "dwarves")
	if [colony.groups, _size] != _groups_shown:
		_groups_shown = [colony.groups, _size]
		for child: Node in _rows.dwarves.line.get_children():
			_rows.dwarves.line.remove_child(child)
			child.queue_free()
		for group: Array in GROUPS:
			var names: Array = colony.groups[group[0]]
			if names.is_empty(): continue
			var tag := _tag("%d %s" % [names.size(), group[0]], group[1])
			tag.tooltip_text = ", ".join(names)
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			_rows.dwarves.line.add_child(tag)
	var food: Dictionary = page.get("food", {})
	var goal := float(food.get("goal_days", 10))
	var days := float(colony.food_days)
	var food_tone := "blocked" if days < float(food.get("short_days", 3)) else ("waiting" if days < goal else "fine")
	_show_meter(_rows.food, _food_words(days) if count > 0 else "No dwarves to feed", days / goal, food_tone,
		"Goal %d days" % goal, {"blocked": "Short", "waiting": "Low", "fine": "Plenty"}[food_tone])
	var beds := int(colony.beds)
	_show_meter(_rows.beds, "%d of %d sleep in their own bedroom" % [beds, count], float(beds) / maxi(1, count),
		"fine" if beds >= count else "waiting", "Goal: one each", "Everyone" if beds >= count else "%d without" % (count - beds))
	var capacity := int(colony.capacity)
	if capacity <= 0:
		_show_meter(_rows.storage, "No storage yet", 0.0, "waiting", "Make a storage zone in Zones", "")
	else:
		var fill := float(colony.used) / capacity
		var storage_tone := "fine" if fill < float(page.get("storage", {}).get("filling", 0.8)) else ("waiting" if fill < 1.0 else "blocked")
		_show_meter(_rows.storage, "%d of %d cells used" % [int(colony.used), capacity], fill, storage_tone,
			_count(int(colony.items), "item", "items") + " stored", {"fine": "Room to spare", "waiting": "Filling up", "blocked": "Full"}[storage_tone])
	var happiness: Dictionary = _rows.happiness
	happiness.art.texture = _texture(String(step.icon))
	_show_meter(happiness, "%s · %d" % [step.word, int(colony.points)], float(colony.points) / 100.0, _tone(int(step.index)), "of 100", "")
	var ticks: Array = []
	var steps: Array = TaskManager.get_config_section("mood").steps
	for index in range(steps.size() - 1): ticks.append(float(steps[index].most) / 100.0)
	happiness.meter.show_value(float(colony.points) / 100.0, _tone(int(step.index)), ticks)
	var complaint: Dictionary = colony.complaint
	happiness.note.text = "No complaints: nothing is wearing on them." if complaint.is_empty() else "Main complaint: %s, %s. %s" % [
		String(complaint.text).to_lower(), _count(int(complaint.count), "dwarf", "dwarves"), String(complaint.help)]


func _show_meter(row: Dictionary, value: String, fraction: float, tone: String, goal: String, tag: String) -> void:
	row.value.text = value
	row.meter.show_value(fraction, tone)
	row.goal.text = goal
	row.tag.visible = not tag.is_empty()
	_set_tag(row.tag, tag, tone)


## "Food for 6 days", in whole days, and under a day as such.
static func _food_words(days: float) -> String:
	if days < 1.0: return "Food for less than a day"
	if days < 2.0: return "Food for 1 day"
	return "Food for %d days" % floori(days)


# ── The journal ────────────────────────────────────────────────────────────────

## The journal's column: its heading and what it is, then the days in an inset that fills
## the rows' height and scrolls.
func _build_journal() -> void:
	_journal = VBoxContainer.new()
	_journal.name = "Journal"
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_journal)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_journal.add_child(head)
	head.add_child(_label("Journal", true, HAY, "heading"))
	var intro := _label(JOURNAL_INTRO, false, MUTED, "sub")
	intro.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(intro)
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.add_child(inset)
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.name = "JournalScroll"
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal_scroll.mouse_force_pass_scroll_events = false
	inset.add_child(_journal_scroll)
	_journal_list = VBoxContainer.new()
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_list)


## The days, newest first ("Today · Autumn, day 8"), each with its complaints, then its
## praises, the most shared first. Says whether it drew anything new.
func _show_journal() -> bool:
	var today := floori(WorldClock.elapsed_days())
	var lines: Array = ColonyJournal.lines()
	var state := [lines, today, _size]
	if state == _journal_shown: return false
	_journal_shown = state
	var scroll := _journal_scroll.scroll_vertical
	for child: Node in _journal_list.get_children():
		_journal_list.remove_child(child)
		child.queue_free()
	if lines.is_empty():
		var empty := _label(JOURNAL_EMPTY, false, MUTED, "quote")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_journal_list.add_child(empty)
	var days: Array = []
	for line: Dictionary in lines:
		if not int(line.day) in days: days.append(int(line.day))
	for day: int in days:
		if _journal_list.get_child_count() > 0: _journal_list.add_child(_rule())
		var section := VBoxContainer.new()
		section.name = "Day"
		section.add_theme_constant_override("separation", _size.gap)
		_journal_list.add_child(section)
		section.add_child(_label(_day_title(day, today), true, HAY, "day"))
		for part: Array in PARTS:
			var topics: Array = lines.filter(func(line: Dictionary) -> bool: return int(line.day) == day and line.tone == part[0])
			if topics.is_empty(): continue
			# The most shared first; among equals, the newest (the order lines() gives).
			var order := {}
			for index in range(topics.size()): order[topics[index]] = index
			topics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.dwarves.size() > b.dwarves.size() or (a.dwarves.size() == b.dwarves.size() and order[a] < order[b]))
			var heading := _label(part[1], true, UITheme.TAG_TONES[part[2]][1], "who")
			heading.name = part[1]
			section.add_child(heading)
			for line: Dictionary in topics: section.add_child(_journal_line(line, part[2]))
	_journal_scroll.set_deferred("scroll_vertical", scroll)
	return true


## One line: the speaker's head and shoulders, their name with the thought and how many
## share it (their names on hover), then their words.
func _journal_line(line: Dictionary, tone: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Line"
	row.add_theme_constant_override("separation", _size.gap + 4)
	var face := _face_of(int(line.speaker))
	row.add_child(_picture(face if face != null else _texture(NO_FACE), "portrait"))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", _size.gap)
	words.add_child(head)
	head.add_child(_label(String(line.name), false, UITheme.CARD_TITLE, "who"))
	head.add_child(_label("· " + String(line.text), false, UITheme.TAG_TONES[tone][1], "who"))
	var shared: Array = line.dwarves
	if shared.size() > 1:
		var tag := _tag(_count(shared.size(), "dwarf", "dwarves"), tone)
		var names: Array = []
		for id: Variant in shared:
			var agent := TaskManager.get_agent(int(id))
			if agent != null: names.append(agent.dwarf_name)
		tag.tooltip_text = ", ".join(names)
		tag.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(tag)
	if not String(line.words).is_empty():
		var quote := _label("“%s”" % line.words, false, UITheme.CARD_TEXT, "quote")
		quote.name = "Words"
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(quote)
	return row


## The dwarf's head and shoulders, rendered once and kept, so a dwarf who has left keeps
## their face here; null for one the page never saw.
func _face_of(dwarf_id: int) -> Texture2D:
	if not _faces.has(dwarf_id):
		var agent := TaskManager.get_agent(dwarf_id)
		if agent == null: return null
		# The portrait's viewport sits in the tree, so its camera can aim; only its picture shows.
		var holder := TextureRect.new()
		holder.visible = false
		_studio.add_child(holder)
		var viewport := Portrait.create_viewport(holder, Vector2i(96, 112))
		Portrait.create_model(viewport, agent)
		var face := AtlasTexture.new()
		face.atlas = viewport.get_texture()
		var crop := func() -> void:   # the same square at whatever size the UI scale renders it
			var k := float(viewport.size.x) / 96.0
			face.region = Rect2(Vector2(8, 6) * k, Vector2(80, 80) * k)
		crop.call()
		viewport.size_changed.connect(crop)
		_faces[dwarf_id] = face
	return _faces[dwarf_id]


## "Today · Autumn, day 8", "Yesterday · Autumn, day 7", then "Autumn, day 6".
static func _day_title(day: int, today: int) -> String:
	var date := WorldClock.date_at(float(day))
	var words := "%s, day %d" % [String(date.season).capitalize(), int(date.day)]
	if day == today: return "Today · " + words
	if day == today - 1: return "Yesterday · " + words
	return words


# ── Words ──────────────────────────────────────────────────────────────────────

## The mood step for `points`, as DwarfMood.step() reads a dwarf's: index, word, line, icon.
static func _step(points: int) -> Dictionary:
	var steps: Array = TaskManager.get_config_section("mood").steps
	for index in range(steps.size()):
		var entry: Dictionary = steps[index]
		if index == steps.size() - 1 or points <= int(entry.most):
			return {"index": index, "word": String(entry.word), "line": String(entry.line), "icon": String(entry.icon)}
	return {}


## Rust for the two lowest steps, where the face shows over a dwarf's head; hay for the
## middle; moss above.
static func _tone(step_index: int) -> String:
	return "blocked" if step_index < 2 else ("waiting" if step_index == 2 else "fine")


static func _count(count: int, one: String, many: String) -> String:
	return "%d %s" % [count, one if count == 1 else many]


static func _date(day: int) -> String:
	var date := WorldClock.date_at(float(day))
	return "%s, day %d, year %d" % [String(date.season).capitalize(), int(date.day), int(date.year)]


# ── Size and fit ──────────────────────────────────────────────────────────────

func fit_above_dock(top: float) -> void:
	_dock_top = top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	var size_now: Dictionary = SIZES.large if viewport.y >= 1300.0 else (SIZES.medium if viewport.y >= 900.0 else (SIZES.short if viewport.y >= 650.0 else SIZES.small))
	var wide := size_now != SIZES.small and viewport.x - 50.0 >= float(size_now.width)
	if size_now != _size or wide != _wide:
		_size = size_now
		_wide = wide
		_apply_size()
	refresh()
	_fit_height()


func _apply_size() -> void:
	var s := _size
	custom_minimum_size.x = float(s.width if _wide else s.narrow) - 8.0   # the window's frame brings 4 px a side
	for side: String in ["left", "right", "top", "bottom"]: add_theme_constant_override("margin_" + side, s.margin)
	# Beside the rows the journal fills their height and scrolls alone; under them, it shows
	# whole and the two scroll together.
	_body.vertical = not _wide
	_body.add_theme_constant_override("separation", s.gap * (3 if _wide else 2))
	_glance.custom_minimum_size.x = float(s.glance) if _wide else 0.0
	_journal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _wide else ScrollContainer.SCROLL_MODE_DISABLED
	_journal.add_theme_constant_override("separation", s.gap)
	_journal_list.add_theme_constant_override("separation", s.gap + 4)
	_glance.add_theme_constant_override("separation", s.gap)
	_column.add_theme_constant_override("separation", s.gap)
	_header.add_theme_constant_override("separation", s.gap * 2)
	_mood.add_theme_constant_override("separation", s.gap)
	_list.add_theme_constant_override("separation", s.gap)
	for row: Dictionary in _rows.values():
		row.box.add_theme_constant_override("separation", s.gap + 4)
		row.line.add_theme_constant_override("separation", s.gap)
		# On the short and small sizes the picture and the value say what a row counts.
		row.label.visible = s == SIZES.large or s == SIZES.medium
	_entries.add_theme_constant_override("h_separation", s.gap)
	_entries.add_theme_constant_override("v_separation", s.gap)
	_badges.add_theme_constant_override("h_separation", s.gap * 2)
	_badges.add_theme_constant_override("v_separation", 6)
	(_mood.get_node("MoodWords") as Control).custom_minimum_size.x = s.mood
	_field.custom_minimum_size = Vector2(s.mood * 0.6, s.button)
	for node: Node in find_children("*", "Control", true, false): _size_piece(node)


## Sizes a piece by its role: a font size, a picture's tile, a meter or a button's height.
func _size_piece(node: Node) -> void:
	var s := _size
	if node.has_meta("font_role"): node.add_theme_font_size_override("font_size", s[node.get_meta("font_role")])
	if node.has_meta("picture_role"):
		var side := float(s[node.get_meta("picture_role")])
		node.custom_minimum_size = Vector2.ONE * side
		# A face fills its tile; other pictures keep a margin inside it.
		node.get_child(0).custom_minimum_size = Vector2.ONE * roundf(side * (0.92 if node.get_meta("picture_role") == "portrait" else 0.8))
	if node.has_meta("meter_role"): node.custom_minimum_size = s.meter
	if node.has_meta("button_role"): node.custom_minimum_size.y = s.button
	if node.has_meta("entry"): _size_entry(node)


## The body as tall as the rows need (with the journal under them, as both need), as far as
## the room above the dock allows; then it scrolls.
func _fit_height() -> void:
	if window == null or not window.visible: return
	window.reset_size()
	UITheme.lay_out_now(window)
	_measure()
	_settle_layout()


func _measure() -> void:
	var chrome := window.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := maxf(120.0, _dock_top - 12.0 - chrome)
	_scroll.custom_minimum_size.y = minf(room, ceilf(_body.get_combined_minimum_size().y)) if _scroll.visible else 0.0
	window.reset_size()
	window.clamp_to_viewport()
	window.position.y = minf(window.position.y, maxf(4, _dock_top - 8 - window.size.y))


func _settle_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	# Wrapped words need their final width before measuring.
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_pending = false
	if is_instance_valid(window) and window.visible: _measure()


# ── Pieces ────────────────────────────────────────────────────────────────────

## One of Colony's entries: a raised button with its picture and word; a planned one is
## dimmed, with its hay tag inside at the right.
func _entry_button(entry: Dictionary) -> Button:
	var planned := bool(entry.get("planned", false))
	var button := Button.new()
	button.name = "Entry" + String(entry.id).to_pascal_case()
	button.text = String(entry.label)
	button.icon = UIRegistry.get_dock_icon(entry)
	button.tooltip_text = String(entry.get("tooltip", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UITheme.body_font())
	button.add_theme_constant_override("h_separation", 10)
	button.set_meta("font_role", "line")
	button.set_meta("entry", planned)
	if planned:
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, MUTED)
		for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, Color(1, 1, 1, 0.5))
		button.add_child(_tag("Planned", "waiting"))
		button.resized.connect(_place_tag.bind(button))
	button.pressed.connect(func(): entry_requested.emit(String(entry.target)))
	return button


## The Planned tag at the entry's right, as small as its word: a size change leaves a
## control no smaller by itself.
func _place_tag(button: Button) -> void:
	var tag: Control = button.get_child(0)
	tag.reset_size()
	tag.position = Vector2(button.size.x - tag.size.x - 12.0, roundf((button.size.y - tag.size.y) / 2.0) - 1.0)


## An entry's height and picture by the size; a planned one keeps room at its right for its
## tag, measured from the tag's words.
func _size_entry(button: Button) -> void:
	button.add_theme_constant_override("icon_max_width", _size.icon)
	button.custom_minimum_size.y = float(_size.entry)
	if not bool(button.get_meta("entry")): return
	var room := UITheme.body_font().get_string_size("Planned", HORIZONTAL_ALIGNMENT_LEFT, -1, _size.tag).x + 16.0 + 12.0
	for state: Array in [["normal", "raised_off"], ["hover", "raised_hover"], ["pressed", "raised_on"], ["hover_pressed", "raised_on"]]:
		var style: StyleBox = UITheme.cell_style(state[1], 3).duplicate()
		style.content_margin_right += room
		button.add_theme_stylebox_override(state[0], style)
	_place_tag.call_deferred(button)


## A picture on the people tile, sized by `role` (flag, badge, face or tile).
func _picture(texture: Texture2D, role: String) -> PanelContainer:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame := UITheme.framed_picture(art)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.set_meta("picture_role", role)
	_size_piece(frame)
	return frame


func _button(text: String, main: bool, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	UITheme.apply_hearth_button(button, main)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_meta("font_role", "line")
	button.set_meta("button_role", true)
	_size_piece(button)
	return button


## A tag in one of the tones: moss, hay or rust.
func _tag(text: String, tone: String) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.name = "Tag"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(_label(text, false, Color.WHITE, "tag"))
	_set_tag(tag, text, tone)
	return tag


func _set_tag(tag: PanelContainer, text: String, tone: String) -> void:
	tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 2))
	var label: Label = tag.get_child(0)
	label.text = text
	label.add_theme_color_override("font_color", UITheme.tag_ink(tone))


func _label(value: String, display: bool, color: Color, role: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", UITheme.display_font() if display else UITheme.body_font())
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("font_role", role)
	_size_piece(label)
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 3
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]


## A meter (doc 23): the cell groove, filled toward its goal in the row's tone; ticks mark
## the mood steps on Happiness's.
class Meter extends Control:
	var fraction := 0.0
	var tone := "fine"
	var ticks: Array = []
	var _fill: Texture2D
	var _fill_key := ""

	func show_value(value: float, value_tone: String, marks: Array = []) -> void:
		fraction = clampf(value, 0.0, 1.0)
		tone = value_tone
		ticks = marks
		queue_redraw()

	func _draw() -> void:
		var cell := 3 if size.y >= 21.0 else 2
		draw_style_box(UITheme.cell_style("groove", cell), Rect2(Vector2.ZERO, size))
		var inner := Rect2(Vector2.ONE * cell, size - Vector2.ONE * cell * 2.0)
		var cells := Vector2i(floori(inner.size.x * fraction / cell), floori(inner.size.y / cell))
		if cells.x >= 3 and cells.y >= 3:
			var key := "%s %s %d" % [tone, cells, cell]
			if key != _fill_key:
				var tones: Array = UITheme.TAG_TONES[tone]
				var art := UITheme.cell_slab(cells.x, cells.y, tones[0], tones[1], tones[2], tones[3], 1, 1)
				art.resize(cells.x * cell, cells.y * cell, Image.INTERPOLATE_NEAREST)
				_fill = UITheme.cell_texture(art)
				_fill_key = key
			draw_texture(_fill, inner.position)
		for tick: Variant in ticks:
			draw_rect(Rect2(inner.position.x + inner.size.x * float(tick) - 1.0, inner.position.y, 3.0, inner.size.y), UITheme.CARD_OUTLINE)
