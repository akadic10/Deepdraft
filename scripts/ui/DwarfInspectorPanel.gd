extends MarginContainer

## The character sheet (doc 261, phase 3), after Stonehearth's Character Info.
## - The header: the live portrait on the people tile; the name; the profession on its tile
##   with its level, experience bar and the way to the next level; the traits as tags, moss
##   for good ones and rust for bad ones, the description on hover; and the mood banner with
##   the mood's face, word and happiness.
## - Six tabs. Overview: what the dwarf is doing and where they are heading, Rest and Food
##   with the pictures from over their head, what they carry, and the latest two thoughts.
##   Mood: the thoughts as cards, what weighs on them on the left and what lifts their
##   spirits on the right, over the mood's face, word and line and the five-step scale.
##   Traits, Equipment and Profession. Tastes (doc 41 "Tastes"): what they love, like and
##   dislike as tiles, "?" until found, and how their own bedroom feels to them.
## - Locate, and Follow as the main action.
## Its own window, opened from the compact panel or Colony Dwarves' Details card.
## Read-only: the portrait clones the dwarf's visual parts into its own viewport, never
## another live agent or a world camera.
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const EquipmentPanel = preload("res://scripts/ui/DwarfEquipmentPanel.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const Appeal = preload("res://scripts/components/RoomAppeal.gd")
const RoomPanel = preload("res://scripts/ui/RoomInspectorPanel.gd")   # its appeal scale
const TABS := ["Overview", "Mood", "Traits", "Equipment", "Profession", "Tastes"]
const TASTES_TAB := 5
const HAY := Color("e2c06a")
const MOSS := Color("8fbf5a")
const RUST := Color("d3856e")   # the rust tag, lit, for words on the dark slab
const MUTED := Color("aeb5ad")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height, as crafting's: large from 1300 px tall (the concept's sizes
## on the 7680×2160 screen), small below 650 px. `body` is the tab body's height; longer
## pages scroll, and it shrinks to the room above the dock.
const SIZES := {
	"large": {"width": 780, "side": 20, "top": 18, "bottom": 14, "portrait": 176, "name": LARGE.display, "outline": 7,
		"role": LARGE.lead, "role_tile": 44, "bar": 16, "bar_width": 310, "sub": LARGE.small, "label": LARGE.small, "tag": LARGE.small,
		"banner": Vector2i(35, 49), "face": 60, "word": LARGE.lead, "value": LARGE.title, "tab": 42, "tab_font": LARGE.body, "body": 500,
		"title": LARGE.heading, "text": LARGE.body, "need": 52, "carry": 72, "count": LARGE.body, "thought": 46, "thought_font": LARGE.body,
		"mood_tile": 84, "mood_word": LARGE.title, "mood_line": LARGE.body, "step": 48, "step_font": LARGE.body, "marker": Vector2(28, 16),
		"action": 48, "action_width": 240, "action_font": LARGE.body, "gap": 12, "thought_columns": 2, "type": LARGE},
	"medium": {"width": 580, "side": 14, "top": 8, "bottom": 8, "portrait": 100, "name": MEDIUM.display, "outline": 5,
		"role": MEDIUM.lead, "role_tile": 28, "bar": 10, "bar_width": 220, "sub": MEDIUM.small, "label": MEDIUM.small, "tag": MEDIUM.small,
		"banner": Vector2i(25, 31), "face": 40, "word": MEDIUM.lead, "value": MEDIUM.title, "tab": 30, "tab_font": MEDIUM.body, "body": 340,
		"title": MEDIUM.heading, "text": MEDIUM.body, "need": 36, "carry": 48, "count": MEDIUM.body, "thought": 34, "thought_font": MEDIUM.small,
		"mood_tile": 56, "mood_word": MEDIUM.title, "mood_line": MEDIUM.body, "step": 32, "step_font": MEDIUM.body, "marker": Vector2(21, 12),
		"action": 32, "action_width": 160, "action_font": MEDIUM.body, "gap": 8, "thought_columns": 2, "type": MEDIUM},
	"small": {"width": 470, "side": 10, "top": 8, "bottom": 6, "portrait": 80, "name": SMALL.display, "outline": 4,
		"role": SMALL.lead, "role_tile": 26, "bar": 10, "bar_width": 170, "sub": SMALL.small, "label": SMALL.small, "tag": SMALL.small,
		"banner": Vector2i(20, 28), "face": 32, "word": SMALL.lead, "value": SMALL.title, "tab": 28, "tab_font": SMALL.body, "body": 240,
		"title": SMALL.heading, "text": SMALL.body, "need": 30, "carry": 40, "count": SMALL.body, "thought": 30, "thought_font": SMALL.body,
		"mood_tile": 44, "mood_word": SMALL.title, "mood_line": SMALL.body, "step": 28, "step_font": SMALL.body, "marker": Vector2(14, 8),
		"action": 30, "action_width": 120, "action_font": SMALL.body, "gap": 8, "thought_columns": 1, "type": SMALL},
}
signal action_requested(action: String)

var window: UIWindow   # its own window: the body fits the room above the dock
var dock: Node   # DockUI, when there is one
var _size: Dictionary = SIZES.medium
var _agent: DwarfAgent
var _data := {}
var _following := false
var _textures := {}
var _shown := {}   # what each rebuilt list last showed, so live refreshes keep their nodes
var _portrait: SubViewport
var _portrait_model: Node3D
var _portrait_frame: PanelContainer
var _column: VBoxContainer
var _header: HBoxContainer
var _identity: VBoxContainer
var _name_label: Label
var _role_frame: PanelContainer
var _role_icon: TextureRect
var _profession: Label
var _experience_bar: ProgressBar
var _experience: Label
var _traits_row: HBoxContainer
var _traits_heading: Label
var _trait_tags: HFlowContainer
var _banner: Control
var _banner_art: TextureRect
var _banner_face: TextureRect
var _banner_word: Label
var _banner_value: Label
var _tab_grid: GridContainer
var _tabs: Array[Button] = []
var _body: PanelContainer
var _scroll: ScrollContainer
var _pages: Array[VBoxContainer] = []
var _tastes_intro: Label
var _taste_rows := {}   # love, like, dislike -> its row of tiles
var _own_room: Label
var _own_scale: RoomPanel.AppealScale
var _headings: Array[Label] = []
# Overview
var _activity: Label
var _explanation: Label
var _destination: Label
var _concern_box: HBoxContainer
var _concern_icon: TextureRect
var _concern_title: Label
var _concern_help: Label
var _needs: GridContainer
var _rest: Dictionary
var _food: Dictionary
var _food_effects: Label
var _carry_heading: Label
var _carry_row: HBoxContainer
var _carry_tiles: HBoxContainer
var _cargo: Label
var _latest: GridContainer
var _latest_empty: Label
var _see_mood: Button
# Mood
var _mood_columns: GridContainer
var _bad: VBoxContainer
var _good: VBoxContainer
var _bad_empty: Label
var _good_empty: Label
var _mood_frame: PanelContainer
var _mood_face: TextureRect
var _mood_word: Label
var _mood_line: Label
var _steps: Array[PanelContainer] = []
var _step_words: Array[Label] = []
var _markers: Array[TextureRect] = []
var _happiness: Label
# Traits, Equipment, Profession
var _traits_list: VBoxContainer
var _traits_note: Label
var _equipment_page: VBoxContainer
var _profession_frame: PanelContainer
var _profession_icon: TextureRect
var _profession_title: Label
var _profession_line: Label
var _profession_bar: ProgressBar
var _profession_summary: Label
var _rewards_heading: Label
var _rewards: VBoxContainer
var _change_profession: Button
# Footer
var _locate: Button
var _follow: Button
var _hint: Label


func _ready() -> void:
	UITheme.apply_surface(self)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	add_child(_column)
	_build_header()
	_tab_grid = GridContainer.new()
	_column.add_child(_tab_grid)
	for i in range(TABS.size()):
		var tab := Button.new()
		tab.text = TABS[i]
		tab.focus_mode = Control.FOCUS_ALL
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show_tab.bind(i))
		_tab_grid.add_child(tab)
		_tabs.append(tab)
	_tabs[4].tooltip_text = "The profession, its level and rewards · Change profession"
	_tabs[TASTES_TAB].tooltip_text = "What they love, like and dislike, found as they use things"
	_body = PanelContainer.new()
	_body.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_column.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_body.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for builder: Callable in [_build_overview, _build_mood, _build_traits, _build_equipment, _build_profession, _build_tastes]:
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages.append(page)
		builder.call(page)
	_build_footer()
	get_viewport().size_changed.connect(func(): fit.call_deferred())   # after the dock moves
	fit()
	_show_tab(0)


# ── Building ──────────────────────────────────────────────────────────────────

func _build_header() -> void:
	_header = HBoxContainer.new()
	_column.add_child(_header)
	var portrait := _picture_rect()
	_portrait_frame = UITheme.framed_picture(portrait)   # on the people tile
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_header.add_child(_portrait_frame)
	_portrait = Portrait.create_viewport(portrait)
	_identity = VBoxContainer.new()
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity.add_theme_constant_override("separation", 4)
	_header.add_child(_identity)
	_name_label = _text(_identity, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_PASS   # the whole name on hover
	var role := HBoxContainer.new()
	role.add_theme_constant_override("separation", 10)
	_identity.add_child(role)
	_role_icon = _picture_rect()
	_role_frame = UITheme.framed_picture(_role_icon)
	role.add_child(_role_frame)
	_profession = _text(role, "", MEDIUM.lead, UITheme.CARD_TITLE, true)
	_profession.autowrap_mode = TextServer.AUTOWRAP_OFF
	_profession.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_experience_bar = _bar(_identity)
	_experience = _text(_identity, "", MEDIUM.small, MUTED)
	_traits_row = HBoxContainer.new()
	_traits_row.add_theme_constant_override("separation", 8)
	_identity.add_child(_traits_row)
	_traits_heading = _text(_traits_row, "TRAITS", MEDIUM.small, HAY)
	_traits_heading.autowrap_mode = TextServer.AUTOWRAP_OFF   # beside the tags it would get no width
	_traits_heading.size_flags_horizontal = Control.SIZE_FILL
	_traits_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trait_tags = HFlowContainer.new()
	_trait_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trait_tags.add_theme_constant_override("h_separation", 8)
	_trait_tags.add_theme_constant_override("v_separation", 6)
	_traits_row.add_child(_trait_tags)
	# The mood banner, hung at the right like Stonehearth's Town Morale ribbon.
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_header.add_child(_banner)
	_banner_art = TextureRect.new()
	_banner_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_banner_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_art)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	_banner.add_child(stack)
	_banner_face = _picture_rect()
	_banner_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(_banner_face)
	_banner_word = _text(stack, "", MEDIUM.title, UITheme.CARD_TITLE, true)
	_banner_value = _text(stack, "", MEDIUM.name, UITheme.CARD_TITLE, true)
	for label: Label in [_banner_word, _banner_value]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_overview(page: VBoxContainer) -> void:
	var now := VBoxContainer.new()
	now.add_theme_constant_override("separation", 2)
	page.add_child(now)
	_heading(now, "RIGHT NOW")
	_activity = _text(now, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	_activity.mouse_filter = Control.MOUSE_FILTER_PASS
	_explanation = _text(now, "", MEDIUM.body, MUTED)
	_destination = _text(now, "", MEDIUM.body, MUTED)
	_concern_box = HBoxContainer.new()
	_concern_box.add_theme_constant_override("separation", 8)
	page.add_child(_concern_box)
	_concern_icon = _picture_rect()
	_concern_icon.custom_minimum_size = Vector2(32, 36)
	_concern_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_concern_box.add_child(_concern_icon)
	var concern := VBoxContainer.new()
	concern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_concern_box.add_child(concern)
	_concern_title = _text(concern, "", MEDIUM.body, HAY, true)
	_concern_help = _text(concern, "", MEDIUM.small, MUTED)
	_concern_box.hide()
	# Rest and Food, with the same pictures as the badges over heads.
	_needs = GridContainer.new()
	page.add_child(_needs)
	_rest = _need(_needs, "rest", "Rest")
	_rest.panel.tooltip_text = "Current rest level. Dwarves sleep when tired."
	_food = _need(_needs, "food", "Food")
	_food_effects = _text(_food.column, "", MEDIUM.small, HAY)
	_carry_heading = _heading(page, "")
	_carry_row = HBoxContainer.new()
	_carry_row.add_theme_constant_override("separation", 12)
	page.add_child(_carry_row)
	_carry_tiles = HBoxContainer.new()
	_carry_tiles.add_theme_constant_override("separation", 8)
	_carry_row.add_child(_carry_tiles)
	_cargo = _text(_carry_row, "", MEDIUM.body, MUTED)
	_cargo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_carry_row.tooltip_text = "Carry load reflects each object's weight. Crate contents do not count as separate carried objects."
	var latest_heading := HBoxContainer.new()
	latest_heading.add_theme_constant_override("separation", 6)
	page.add_child(latest_heading)
	_headings.append(_text(latest_heading, "LATEST THOUGHTS ·", MEDIUM.small, HAY))
	_headings[-1].autowrap_mode = TextServer.AUTOWRAP_OFF
	_headings[-1].size_flags_horizontal = Control.SIZE_FILL
	_see_mood = Button.new()
	_see_mood.flat = true
	_see_mood.text = "see Mood"
	_see_mood.focus_mode = Control.FOCUS_ALL
	_see_mood.tooltip_text = "Every thought, and the mood they add up to"
	_see_mood.add_theme_font_override("font", UITheme.body_font())
	for look: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_see_mood.add_theme_color_override(look, HAY)
	_see_mood.pressed.connect(_show_tab.bind(1))
	latest_heading.add_child(_see_mood)
	_latest = GridContainer.new()
	page.add_child(_latest)
	_latest_empty = _text(page, "No thoughts on their mind right now.", MEDIUM.body, MUTED)


func _build_mood(page: VBoxContainer) -> void:
	_mood_columns = GridContainer.new()
	page.add_child(_mood_columns)
	_bad = VBoxContainer.new()
	_good = VBoxContainer.new()
	for side: Array in [[_bad, "WEIGHING ON THEM", RUST], [_good, "LIFTING THEIR SPIRITS", MOSS]]:
		var column: VBoxContainer = side[0]
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mood_columns.add_child(column)
		var title := _heading(column, side[1])
		title.add_theme_color_override("font_color", side[2])
	_bad_empty = _text(_bad, "Nothing weighs on them.", MEDIUM.body, MUTED)
	_good_empty = _text(_good, "Nothing lifts their spirits yet.", MEDIUM.body, MUTED)
	# The mood, its word and a line, over the five-step scale with a marker.
	var mood := HBoxContainer.new()
	mood.add_theme_constant_override("separation", 16)
	page.add_child(mood)
	_mood_face = _picture_rect()
	_mood_frame = UITheme.framed_picture(_mood_face)
	mood.add_child(_mood_frame)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mood.add_child(words)
	_mood_word = _text(words, "", MEDIUM.display, UITheme.CARD_TITLE, true)
	_mood_line = _text(words, "", MEDIUM.heading)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	page.add_child(scale_row)
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 6)
	page.add_child(marks)
	for step: Dictionary in TaskManager.get_config_section("mood").steps:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.tooltip_text = String(step.word)
		scale_row.add_child(cell)
		_steps.append(cell)
		var word := _text(cell, String(step.word), MEDIUM.heading)
		word.autowrap_mode = TextServer.AUTOWRAP_OFF
		word.clip_text = true
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_step_words.append(word)
		var marker := TextureRect.new()
		marker.texture = _marker_texture()
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		marker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		marks.add_child(marker)
		_markers.append(marker)
	_happiness = _text(page, "", MEDIUM.body, MUTED)


func _build_traits(page: VBoxContainer) -> void:
	_traits_list = VBoxContainer.new()
	page.add_child(_traits_list)
	# Traits are generated and saved, but the simulation does not apply their effects.
	_traits_note = _text(page, "Trait effects are not active yet.", MEDIUM.body, MUTED)


func _build_equipment(page: VBoxContainer) -> void:
	_equipment_page = EquipmentPanel.new()
	page.add_child(_equipment_page)


func _build_profession(page: VBoxContainer) -> void:
	var role := HBoxContainer.new()
	role.add_theme_constant_override("separation", 14)
	page.add_child(role)
	_profession_icon = _picture_rect()
	_profession_frame = UITheme.framed_picture(_profession_icon)
	role.add_child(_profession_frame)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 4)
	role.add_child(identity)
	_profession_title = _text(identity, "", MEDIUM.title, UITheme.CARD_TITLE, true)
	_profession_bar = _bar(identity)
	_profession_line = _text(identity, "", MEDIUM.body, MUTED)
	# The tab's action, near the top so it never scrolls out of view.
	_change_profession = Button.new()
	_change_profession.text = "Change profession"
	_change_profession.tooltip_text = "Explore career paths and choose this dwarf's profession"
	_change_profession.focus_mode = Control.FOCUS_ALL
	_change_profession.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_change_profession.pressed.connect(func(): action_requested.emit("profession"))
	page.add_child(_change_profession)
	_profession_summary = _text(page, "", MEDIUM.lead)
	_rewards_heading = _heading(page, "LEVEL REWARDS")
	_rewards = VBoxContainer.new()
	_rewards.add_theme_constant_override("separation", 6)
	page.add_child(_rewards)


## The Tastes tab: a line on how tastes are found, a row of tiles for each kind, and their
## own bedroom on the appeal scale.
func _build_tastes(page: VBoxContainer) -> void:
	_tastes_intro = _text(page, "", MEDIUM.body, MUTED)
	for kind: String in ["love", "like", "dislike"]:
		var heading := _heading(page, {"love": "LOVES", "like": "LIKES", "dislike": "DISLIKES"}[kind])
		heading.add_theme_color_override("font_color", RUST if kind == "dislike" else MOSS)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		page.add_child(row)
		_taste_rows[kind] = row
	_heading(page, "OWN BEDROOM")
	_own_room = _text(page, "", MEDIUM.lead)
	_own_scale = RoomPanel.AppealScale.new()
	_own_scale.words = RoomManager.appeal_config.get("words", [])
	_own_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_own_scale)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_column.add_child(footer)
	_locate = Button.new()
	_locate.text = "Locate"
	_locate.tooltip_text = "Center the camera on this dwarf."
	_locate.pressed.connect(func(): action_requested.emit("locate"))
	_follow = Button.new()
	_follow.text = "Follow"
	_follow.tooltip_text = "Follow this dwarf. Moving the camera manually stops following."
	_follow.pressed.connect(func(): action_requested.emit("follow"))
	for button: Button in [_locate, _follow]:
		button.focus_mode = Control.FOCUS_ALL
		footer.add_child(button)
	UITheme.apply_hearth_button(_follow, true)   # the sheet's main action
	_hint = _text(footer, "Esc to close", MEDIUM.body, MUTED)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# ── Showing a dwarf ───────────────────────────────────────────────────────────

func show_data(data: Dictionary, following: bool) -> void:
	var agent: DwarfAgent = data.agent
	_data = data
	_following = following
	if agent != _agent:
		_agent = agent
		_refresh_portrait()
		_show_tab(0)
	_name_label.text = String(data.title)
	_name_label.tooltip_text = String(data.title)
	var experience: Dictionary = data.get("experience", {})
	var role := "%s · Level %d" % [data.get("profession_name", "Worker"), int(experience.get("level", 1))]
	_role_icon.texture = _texture(String(data.get("profession_icon", "")))
	_profession.text = role
	_experience_bar.value = float(experience.get("progress", 0.0)) * 100.0
	_experience.text = String(experience.get("line", ""))
	_show_traits(data.get("trait_details", []))
	_show_mood(data.get("mood", {}))
	_show_overview(data)
	_equipment_page.show_equipment(data.get("equipment_details", {}))
	_profession_icon.texture = _role_icon.texture
	_profession_title.text = role
	_profession_bar.value = _experience_bar.value
	_profession_line.text = _experience.text
	_profession_summary.text = String(experience.get("summary", ""))
	_show_rewards(experience.get("rewards", []))
	if _pages[TASTES_TAB].visible: _show_tastes(Inspection.tastes_sheet(agent))
	# Follow is the sheet's main action either way: its words say whether it is on.
	var follow_text := "Stop following" if following else "Follow"
	if _follow.text != follow_text:
		_follow.text = follow_text


func _show_overview(data: Dictionary) -> void:
	_activity.text = String(data.activity)
	_activity.tooltip_text = String(data.explanation)
	_explanation.text = String(data.explanation)
	var destination := String(data.destination)
	_destination.text = "" if destination == "No destination" else destination.replace("\n", " · ")
	_destination.tooltip_text = "Now at " + String(data.location)
	_destination.visible = not _destination.text.is_empty()
	var concern: Dictionary = data.get("concern", {})
	_concern_box.visible = not concern.is_empty()
	if not concern.is_empty():
		_concern_icon.texture = UIRegistry.get_need_icon(concern.kind)
		_concern_title.text = "%s · %s" % [concern.title, concern.reason]
		_concern_help.text = concern.help
	var rest := roundi(float(data.rest) * 100)
	_rest.status.text = "%d%% · %s" % [rest, "Sleeping" if data.sleeping else ("Tired" if rest <= 25 else "Awake")]
	_rest.bar.value = rest
	var food: Dictionary = data.food
	_food.status.text = "%d%% · %s" % [roundi(float(food.value) * 100), food.label]
	_food.bar.value = float(food.value) * 100.0
	_food.panel.tooltip_text = String(food.detail)
	_food_effects.text = String(food.effects)
	_food_effects.visible = not _food_effects.text.is_empty()
	_carry_heading.text = "CARRYING · %d / %d" % [data.load, data.capacity]
	var lines: Array[String] = []
	for entry: Dictionary in data.cargo:
		var line := "%d × %s" % [entry.count, entry.name]
		if entry.crate:
			line += " (%d %s)" % [entry.objects, "crate" if entry.objects == 1 else "crates"]
		lines.append(line)
	_cargo.text = "\n".join(lines) if not lines.is_empty() else "Empty hands"
	if _changed("cargo", data.cargo):
		_clear(_carry_tiles)
		for entry: Dictionary in data.cargo:
			var key := String(entry.key)
			var path := Inventory.thumbnail_path(key)
			if not ResourceLoader.exists(path): path = "res://assets/ui/furniture/%s.png" % key.get_slice(":", key.get_slice_count(":") - 1)   # packed furniture
			_carry_tiles.add_child(_counted_tile(_texture(path), int(entry.count)))
	_carry_tiles.visible = _carry_tiles.get_child_count() > 0


func _show_mood(mood: Dictionary) -> void:
	if mood.is_empty(): return
	var face := _texture(String(mood.icon))
	var value := "%d%%" % int(mood.points)
	_banner_face.texture = face
	_banner_word.text = String(mood.word)
	_banner_value.text = value
	_banner.tooltip_text = "%s · Happiness %s\n%s" % [mood.word, value, mood.line]
	_mood_face.texture = face
	_mood_word.text = String(mood.word)
	_mood_line.text = String(mood.line)
	_happiness.text = "Happiness %s · thoughts fade as their hours run out." % value
	if _changed("step", int(mood.index)):
		for i in range(_steps.size()):
			var current := i == int(mood.index)
			_steps[i].add_theme_stylebox_override("panel", UITheme.family_block_style(_family()) if current else UITheme.cell_style("raised", 3))
			UITheme.format_label(_step_words[i], current, int(_size.step_font), UITheme.CARD_TITLE if current else UITheme.CARD_TEXT, 4 if current else 0)
			_step_words[i].add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
			_markers[i].modulate.a = 1.0 if current else 0.0
	var thoughts: Array = mood.thoughts
	var bad := thoughts.filter(func(thought: Dictionary): return int(thought.points) < 0)
	var good := thoughts.filter(func(thought: Dictionary): return int(thought.points) > 0)
	bad.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.points) < int(b.points))
	good.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.points) > int(b.points))
	var latest := thoughts.duplicate()
	latest.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.age) < float(b.age))
	_fill_thoughts(_bad, bad, "bad")
	_fill_thoughts(_good, good, "good")
	_fill_thoughts(_latest, latest.slice(0, 2), "latest")
	_bad_empty.visible = bad.is_empty()
	_good_empty.visible = good.is_empty()
	_latest_empty.visible = thoughts.is_empty()


## One raised card per thought: the hours left, the words and the value. The cards stay
## while the same thoughts show; only their hours change.
func _fill_thoughts(box: Container, thoughts: Array, key: String) -> void:
	var names := thoughts.map(func(thought: Dictionary): return [thought.text, thought.points])
	if _changed(key, names):
		for child in box.get_children():
			if child.has_meta("thought"):
				box.remove_child(child)
				child.queue_free()
		for thought: Dictionary in thoughts:
			box.add_child(_thought_card())
	var cards := box.get_children().filter(func(child: Node): return child.has_meta("thought"))
	for i in range(thoughts.size()):
		var thought: Dictionary = thoughts[i]
		var card: PanelContainer = cards[i]
		var points := int(thought.points)
		var hours := float(thought.hours)
		var parts: Dictionary = card.get_meta("thought")
		parts.hours.text = "now" if hours < 0 else "%dh" % maxi(1, ceili(hours))
		parts.text.text = String(thought.text)
		parts.points.text = "%s%d" % ["+" if points > 0 else "−", absi(points)]
		parts.points.add_theme_color_override("font_color", MOSS if points > 0 else RUST)
		var note := String(thought.effect) if hours < 0 else "%.1f game hours left" % hours
		card.tooltip_text = "%s · %s%d happiness\n%s%s" % [thought.text, "+" if points > 0 else "−", absi(points), note,
			"\n" + String(thought.help) if not String(thought.help).is_empty() else ""]


func _show_traits(entries: Array) -> void:
	# Trait definitions are static: keep the tags and rows during live refreshes.
	if not _changed("traits", entries): return
	_clear(_trait_tags)
	_clear(_traits_list)
	_traits_row.visible = not entries.is_empty()
	_traits_note.visible = not entries.is_empty()
	if entries.is_empty():
		_text(_traits_list, "No distinctive traits.", int(_size.text), MUTED)
		return
	for entry: Dictionary in entries:
		var tone := "fine" if bool(entry.get("positive", true)) else "blocked"
		var tag := _tag(String(entry.name), tone, int(_size.tag))
		tag.tooltip_text = String(entry.description)
		_trait_tags.add_child(tag)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_traits_list.add_child(row)
		var name_tag := _tag(String(entry.name), tone, int(_size.tag) + 1)
		name_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(name_tag)
		_text(row, String(entry.description), int(_size.text))


func _show_rewards(rewards: Array) -> void:
	_rewards_heading.visible = not rewards.is_empty()
	if not _changed("rewards", rewards): return
	_clear(_rewards)
	for reward: Dictionary in rewards:
		var earned := bool(reward.earned)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rewards.add_child(row)
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_fine", 3) if earned else UITheme.cell_style("raised_off", 3))
		row.add_child(tag)
		var level := Label.new()
		level.text = "Lv %d" % int(reward.level)
		UITheme.format_label(level, true, int(_size.tag), UITheme.tag_ink("fine") if earned else MUTED)
		tag.add_child(level)
		var words := _text(row, String(reward.text), int(_size.text), UITheme.CARD_TEXT if earned else MUTED)
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.tooltip_text = "Earned" if earned else "Not earned yet"


## The Tastes tab (doc 41 "Tastes"): each taste as a tile, its picture and name once found
## and "?" until then; then how their own bedroom feels to them on the appeal scale.
func _show_tastes(sheet: Dictionary) -> void:
	_tastes_intro.text = "What %s loves, likes and dislikes. A taste shows once they have used the thing: slept in the bed, sat on the seat, eaten at the table, played at the board, or used anything made of the wood." % sheet.name
	var held: Array = sheet.tastes
	if _changed("tastes", held):
		for kind: String in _taste_rows: _clear(_taste_rows[kind])
		for taste: Dictionary in held: (_taste_rows[taste.kind] as HBoxContainer).add_child(_taste_tile(taste))
	var own: Dictionary = sheet.own_room
	_own_scale.visible = not own.is_empty()
	if own.is_empty():
		_own_room.text = "No bedroom of their own yet."
		return
	var moved := not String(own.taste).is_empty()
	_own_room.text = "%s is %s %s." % [own.name, own.word, Appeal.number(float(own.score))]
	if moved: _own_room.text += " %s %s, so to them it is %s %s." % [sheet.name, own.taste, own.felt_word, Appeal.number(float(own.felt_score))]
	_own_scale.score = float(own.score)
	_own_scale.felt = float(own.felt_score) if moved else NAN
	_own_scale.queue_redraw()


## A taste's tile: its picture with its name under it once found; "?" and "Not found yet"
## before, so the sheet never tells a taste the dwarf has not met.
func _taste_tile(taste: Dictionary) -> VBoxContainer:
	var found := bool(taste.found)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var verbs := {"love": "loves it", "like": "likes it", "dislike": "dislikes it"}
	column.tooltip_text = "%s · %s" % [taste.name, verbs[taste.kind]] if found else "Not found yet: they have not used it"
	var picture := _picture_rect()
	picture.texture = _texture(String(taste.picture)) if found else null
	var tile := UITheme.framed_picture(picture)
	tile.custom_minimum_size = Vector2.ONE * float(_size.carry)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not found:
		var mark := Label.new()
		mark.text = "?"
		UITheme.format_label(mark, true, int(_size.title), MUTED, 4)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(mark)
	column.add_child(tile)
	var name := _text(column, String(taste.name) if found else "Not found yet", int(_size.text) - 1, UITheme.CARD_TEXT if found else MUTED)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return column


func clear_subject() -> void:
	_agent = null
	_data = {}
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = null
	_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _refresh_portrait() -> void:
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = Portrait.create_model(_portrait, _agent)


func _show_tab(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index
	for i in range(_tabs.size()):
		UITheme.show_tab(_tabs[i], i == index)
	_scroll.scroll_vertical = 0
	# Tastes are worked out only while their tab shows.
	if index == TASTES_TAB and is_instance_valid(_agent): _show_tastes(Inspection.tastes_sheet(_agent))


# ── Size and fit ──────────────────────────────────────────────────────────────

## Take the size for the screen and, in its own window, the room above the dock: the tab
## body is as tall as the size allows, so the window keeps one height from tab to tab.
func fit() -> void:
	if not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	var chosen: Dictionary = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	if chosen != _size:
		_size = chosen
		_shown.clear()   # rebuild the lists at the new size
	_apply_size()
	if not _data.is_empty() and is_instance_valid(_data.agent): show_data(_data, _following)
	_scroll.custom_minimum_size.y = float(_size.body)
	if window == null: return
	# The window's frame, header, tabs and footer take what they need; the body has the rest
	# of the room between the top of the screen and the dock, up to its size's height.
	var top := UIWindow.VIEWPORT_MARGIN if viewport.y < 650.0 else 32.0
	var bottom: float = (dock.dock_top() if is_instance_valid(dock) else viewport.y) - 8.0
	_scroll.custom_minimum_size.y = 0.0
	window.reset_size()
	UITheme.lay_out_now(window)
	var chrome := window.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(bottom - top - chrome, 96.0, float(_size.body))
	window.reset_size()


## The lowest a window's top may sit so it stays above the dock.
func lowest_top() -> float:
	var viewport := get_viewport_rect().size
	var bottom: float = (dock.dock_top() if is_instance_valid(dock) else viewport.y) - 8.0
	return maxf(UIWindow.VIEWPORT_MARGIN, bottom - (window.size.y if window != null else size.y))


func _apply_size() -> void:
	var s := _size
	var gap := int(s.gap)
	for side: String in ["left", "right"]: add_theme_constant_override("margin_" + side, int(s.side))
	add_theme_constant_override("margin_top", int(s.top))
	add_theme_constant_override("margin_bottom", int(s.bottom))
	custom_minimum_size.x = float(s.width) - 8.0   # the frame's sides
	_column.add_theme_constant_override("separation", gap)
	_header.add_theme_constant_override("separation", gap + 6)
	_identity.add_theme_constant_override("separation", 4 if s == SIZES.large else 2)
	_portrait_frame.custom_minimum_size = Vector2.ONE * float(s.portrait)
	UITheme.format_label(_name_label, true, int(s.name), UITheme.CARD_TITLE, int(s.outline))
	_name_label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_role_frame.custom_minimum_size = Vector2.ONE * float(s.role_tile)
	_profession.add_theme_font_size_override("font_size", s.role)
	_experience_bar.custom_minimum_size = Vector2(float(s.bar_width), float(s.bar))
	_experience_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_experience.add_theme_font_size_override("font_size", s.sub)
	_traits_heading.add_theme_font_size_override("font_size", s.label)
	# The mood banner, hung at the right.
	var cells: Vector2i = s.banner
	_banner.custom_minimum_size = Vector2(cells * UITheme.CARD_CELL)
	_banner_art.texture = UITheme.banner_texture(_family(), cells.x, cells.y)
	_banner_art.size = _banner.custom_minimum_size
	var stack := _banner_face.get_parent() as VBoxContainer
	stack.offset_top = roundf(float(s.face) * 0.23)
	_banner_face.custom_minimum_size = Vector2.ONE * float(s.face)
	_banner_word.add_theme_font_size_override("font_size", s.word)
	_banner_value.add_theme_font_size_override("font_size", s.value)
	for label: Label in [_banner_word, _banner_value]:
		label.add_theme_constant_override("outline_size", int(s.outline) - 2)
		label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_tab_grid.columns = TABS.size() if s != SIZES.small else 3   # two rows of tabs on small screens
	_tab_grid.add_theme_constant_override("h_separation", 6)
	_tab_grid.add_theme_constant_override("v_separation", 6)
	for tab: Button in _tabs:
		tab.custom_minimum_size.y = float(s.tab)
		tab.add_theme_font_size_override("font_size", s.tab_font)
	for page: VBoxContainer in _pages: page.add_theme_constant_override("separation", gap + 4)
	for label: Label in _headings: label.add_theme_font_size_override("font_size", s.label)
	_see_mood.add_theme_font_size_override("font_size", s.label)
	UITheme.format_label(_activity, true, int(s.title), UITheme.CARD_TITLE)
	for label: Label in [_explanation, _destination, _cargo, _latest_empty, _bad_empty, _good_empty, _happiness, _traits_note, _profession_line]:
		label.add_theme_font_size_override("font_size", s.text)
	_concern_title.add_theme_font_size_override("font_size", s.text)
	_concern_help.add_theme_font_size_override("font_size", int(s.text))
	_needs.columns = 2
	_needs.add_theme_constant_override("h_separation", gap * 2)
	_needs.add_theme_constant_override("v_separation", gap)
	for need: Dictionary in [_rest, _food]:
		need.frame.custom_minimum_size = Vector2.ONE * float(s.need)
		need.title.add_theme_font_size_override("font_size", int(s.type.body))
		need.status.add_theme_font_size_override("font_size", s.text)
		need.bar.custom_minimum_size.y = maxf(8.0, float(s.bar) - 2.0)
	_food_effects.add_theme_font_size_override("font_size", int(s.text))
	_cargo.custom_minimum_size.x = 0.0
	for grid: GridContainer in [_latest, _mood_columns]:
		grid.columns = int(s.thought_columns)
		grid.add_theme_constant_override("h_separation", gap + 4)
		grid.add_theme_constant_override("v_separation", gap)
	for column: VBoxContainer in [_bad, _good]: column.add_theme_constant_override("separation", gap - 2)
	_mood_frame.custom_minimum_size = Vector2.ONE * float(s.mood_tile)
	UITheme.format_label(_mood_word, true, int(s.mood_word), UITheme.CARD_TITLE, int(s.outline) - 1)
	_mood_word.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_mood_line.add_theme_font_size_override("font_size", s.mood_line)
	for i in range(_steps.size()):
		_steps[i].custom_minimum_size.y = float(s.step)
		_markers[i].custom_minimum_size = s.marker
	_profession_frame.custom_minimum_size = Vector2.ONE * float(s.mood_tile)
	UITheme.format_label(_profession_title, true, int(s.type.heading), UITheme.CARD_TITLE)
	_profession_bar.custom_minimum_size = Vector2(float(s.bar_width), float(s.bar))
	_profession_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_profession_summary.add_theme_font_size_override("font_size", s.text)
	_equipment_page.apply_size(int(s.text), int(s.label), int(s.role), float(s.mood_tile))
	_tastes_intro.add_theme_font_size_override("font_size", int(s.text))
	_own_room.add_theme_font_size_override("font_size", s.text)
	_own_scale.font_size = int(s.label)
	_own_scale.custom_minimum_size.y = roundf(float(s.need) * 0.5) + float(s.label) + 12.0
	for button: Button in [_locate, _follow, _change_profession]:
		button.custom_minimum_size = Vector2(float(s.action_width), float(s.action))
		button.add_theme_font_size_override("font_size", s.action_font)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hint.add_theme_font_size_override("font_size", int(s.label))


# ── Pieces ────────────────────────────────────────────────────────────────────

## A need beside its picture from over the head: the name, its value and state, and a bar.
func _need(parent: Control, icon: String, title: String) -> Dictionary:
	var panel := HBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	var picture := _picture_rect()
	picture.texture = UIRegistry.get_need_icon(icon)
	var frame := UITheme.framed_picture(picture)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(frame)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	column.add_child(line)
	var heading := _text(line, title, MEDIUM.heading, UITheme.CARD_TITLE, true)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal = Control.SIZE_FILL
	var status := _text(line, "", MEDIUM.body, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := _bar(column)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return {"panel": panel, "frame": frame, "column": column, "title": heading, "status": status, "bar": bar}


func _thought_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.cell_style("raised", 3))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = float(_size.thought)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var font := int(_size.thought_font)
	var hours := _text(row, "", font - 1, MUTED)
	hours.autowrap_mode = TextServer.AUTOWRAP_OFF
	hours.size_flags_horizontal = Control.SIZE_FILL
	hours.custom_minimum_size.x = float(font) * 2.0
	var words := _text(row, "", font)
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	words.clip_text = true
	words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var points := _text(row, "", font + 2, MOSS, true)
	points.autowrap_mode = TextServer.AUTOWRAP_OFF
	points.size_flags_horizontal = Control.SIZE_FILL
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label: Label in [hours, words, points]: label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.set_meta("thought", {"hours": hours, "text": words, "points": points})
	return card


## A carried good: its picture on the family tile, with the count at the corner.
func _counted_tile(texture: Texture2D, count: int) -> PanelContainer:
	var picture := _picture_rect()
	picture.texture = texture
	var tile := UITheme.framed_picture(picture)
	tile.custom_minimum_size = Vector2.ONE * float(_size.carry)
	var label := Label.new()
	label.text = str(count)
	UITheme.format_label(label, true, int(_size.count), UITheme.CARD_TITLE, 5)
	label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tile.add_child(label)
	return tile


func _tag(text: String, tone: String, font_size: int) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 3))
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, false, font_size, UITheme.tag_ink(tone))
	tag.add_child(label)
	return tag


func _heading(parent: Control, text: String) -> Label:
	var label := _text(parent, text, MEDIUM.small, HAY)
	_headings.append(label)
	return label


func _bar(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	UITheme.hearth_progress(bar)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _text(parent: Control, value: String, font_size: int, color := UITheme.CARD_TEXT, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.format_label(label, display, font_size, color)
	parent.add_child(label)
	return label


func _picture_rect() -> TextureRect:
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else load("res://assets/ui/icons/stocks.png")
	return _textures[path]


## The hay marker under the scale's current step.
static func _marker_texture() -> Texture2D:
	var image := Image.create(7, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for row in range(4):   # pointing up at the step, its foot in shade
		for x in range(3 - row, 4 + row): image.set_pixel(x, row, HAY if row < 3 else Color("8a6d2a"))
	return ImageTexture.create_from_image(image)


func _family() -> Color:
	return UIRegistry.get_icon_family_color("people")


## Whether a rebuilt list's contents changed since it last showed.
func _changed(key: String, value: Variant) -> bool:
	if _shown.has(key) and _shown[key] == value: return false
	_shown[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return true


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
