extends VBoxContainer

## Colony Dwarves' Details card (doc 261), after Stonehearth's Citizens: who the selected
## dwarf is, and the ways into more.
## - The portrait on the people tile, the name, the profession with its level and the way
##   to the next, and the traits as tags.
## - Character sheet (the main action), Change profession, Crafting while the profession
##   crafts today, and Follow.
## Everything live (what the dwarf is doing, rest, mood) is on the roster's rows. While the
## window is open, ObjectExplorerController hosts the selected dwarf here instead of the
## compact panel: show_data(), clear_subject() and action_requested. Read-only: the
## portrait clones the dwarf's visual parts into its own viewport.
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const HAY := Color("e2c06a")
const MUTED := Color("aeb5ad")
const ACTIONS := [
	["character_sheet", "Character sheet", "Everything about this dwarf: work, mood, traits, equipment and profession."],
	["profession", "Change profession", "Explore career paths and choose this dwarf's profession."],
	["crafting", "Crafting", "Open this profession's crafting."],
	["follow", "Follow", "Follow this dwarf. Moving the camera manually stops following."],
]
# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
signal action_requested(action: String)

var _agent: DwarfAgent
var _portrait: SubViewport
var _portrait_model: Node3D
var _heading: Label
var _top: BoxContainer
var _portrait_frame: PanelContainer
var _identity: VBoxContainer
var _name_label: Label
var _role: HBoxContainer
var _role_frame: PanelContainer
var _role_icon: TextureRect
var _profession: Label
var _experience_bar: ProgressBar
var _experience: Label
var _tags: HFlowContainer
var _gap: Control
var _shown_traits := []
var _tag_size := 13
var _buttons := {}   # action id -> Button
var _follow: Button
var _textures := {}


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_heading = _text(self, "DETAILS", MEDIUM.small, HAY)
	_top = BoxContainer.new()
	add_child(_top)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame = UITheme.framed_picture(picture)   # on the people tile
	_top.add_child(_portrait_frame)
	_portrait = Portrait.create_viewport(picture)
	_identity = VBoxContainer.new()
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_identity.add_theme_constant_override("separation", 4)
	_top.add_child(_identity)
	_name_label = _text(_identity, "", MEDIUM.title, UITheme.CARD_TITLE, true)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_PASS   # the whole name on hover
	_role = HBoxContainer.new()
	_role.add_theme_constant_override("separation", 8)
	_identity.add_child(_role)
	_role_icon = TextureRect.new()
	_role_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_role_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_role_frame = UITheme.framed_picture(_role_icon)
	_role.add_child(_role_frame)
	_profession = _text(_role, "", MEDIUM.lead, UITheme.CARD_TITLE, true)
	_profession.autowrap_mode = TextServer.AUTOWRAP_OFF
	_profession.size_flags_horizontal = Control.SIZE_FILL
	_profession.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_experience_bar = ProgressBar.new()
	UITheme.hearth_progress(_experience_bar)
	_experience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(_experience_bar)
	_experience = _text(_identity, "", MEDIUM.small, MUTED)
	_tags = HFlowContainer.new()
	_tags.add_theme_constant_override("h_separation", 8)
	_tags.add_theme_constant_override("v_separation", 6)
	add_child(_tags)
	_gap = Control.new()   # the buttons follow the traits, near the portrait
	add_child(_gap)
	for entry: Array in ACTIONS:
		var action := String(entry[0])
		var button := Button.new()
		button.text = entry[1]
		button.tooltip_text = entry[2]
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func(): action_requested.emit(action))
		add_child(button)
		_buttons[action] = button
	_follow = _buttons.follow
	UITheme.apply_hearth_button(_buttons.character_sheet, true)   # the card's main action


## The roster's sizes. `vertical` stacks the portrait over the name, centred, as
## Stonehearth's card; short screens set them side by side to save height.
func apply_size(s: Dictionary) -> void:
	var vertical := bool(s.vertical)
	add_theme_constant_override("separation", int(s.gap))
	_heading.add_theme_font_size_override("font_size", s.card_heading)
	_top.vertical = vertical
	_top.add_theme_constant_override("separation", int(s.gap) if vertical else int(s.gap) + 4)
	_portrait_frame.custom_minimum_size = Vector2.ONE * float(s.card_portrait)
	_portrait_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if vertical else Control.SIZE_FILL
	var align := HORIZONTAL_ALIGNMENT_CENTER if vertical else HORIZONTAL_ALIGNMENT_LEFT
	UITheme.format_label(_name_label, true, int(s.card_name), UITheme.CARD_TITLE, 5)
	_name_label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_name_label.horizontal_alignment = align
	_experience.horizontal_alignment = align
	_experience.add_theme_font_size_override("font_size", s.card_line)
	_role.alignment = BoxContainer.ALIGNMENT_CENTER if vertical else BoxContainer.ALIGNMENT_BEGIN
	_role_frame.custom_minimum_size = Vector2.ONE * float(s.card_role_tile)
	_profession.add_theme_font_size_override("font_size", s.card_role)
	_experience_bar.custom_minimum_size = s.card_bar
	_experience_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if vertical else Control.SIZE_EXPAND_FILL
	_tags.alignment = FlowContainer.ALIGNMENT_CENTER if vertical else FlowContainer.ALIGNMENT_BEGIN
	_tag_size = int(s.card_tag)
	_shown_traits = [null]   # rebuild the tags at the new size on the next show
	_gap.custom_minimum_size.y = float(s.gap) * 2.0
	for action: String in _buttons:
		var button: Button = _buttons[action]
		button.custom_minimum_size.y = float(s.card_main if action == "character_sheet" else s.card_button)
		button.add_theme_font_size_override("font_size", s.card_button_font)


func show_data(data: Dictionary, following: bool) -> void:
	var agent: DwarfAgent = data.agent
	if agent != _agent:
		_agent = agent
		_refresh_portrait()
	_name_label.text = String(data.title)
	_name_label.tooltip_text = String(data.title)
	var experience: Dictionary = data.get("experience", {})
	_role_icon.texture = _texture(String(data.get("profession_icon", "")))
	_profession.text = "%s · Level %d" % [data.get("profession_name", "Worker"), int(experience.get("level", 1))]
	_experience_bar.value = float(experience.get("progress", 0.0)) * 100.0
	_experience.text = String(experience.get("line", ""))
	_show_traits(data.get("trait_details", []))
	# Crafting shows while the profession has recipes today (a Worker's Rudimentary).
	_buttons.crafting.visible = not String(data.get("crafting_section", "")).is_empty()
	# Follow says whether it is on.
	var follow_text := "Stop following" if following else "Follow"
	if _follow.text != follow_text:
		_follow.text = follow_text


func _show_traits(entries: Array) -> void:
	# Trait definitions are static: keep the tags during live refreshes.
	if entries == _shown_traits: return
	_shown_traits = entries.duplicate(true)
	for child in _tags.get_children():
		_tags.remove_child(child)
		child.queue_free()
	_tags.visible = not entries.is_empty()
	for entry: Dictionary in entries:
		var tone := "fine" if bool(entry.get("positive", true)) else "blocked"
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 3))
		tag.tooltip_text = String(entry.description)
		var label := Label.new()
		label.text = String(entry.name)
		UITheme.format_label(label, false, _tag_size, UITheme.tag_ink(tone))
		tag.add_child(label)
		_tags.add_child(tag)


func clear_subject() -> void:
	_agent = null
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = null
	_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _refresh_portrait() -> void:
	if is_instance_valid(_portrait_model):
		_portrait_model.free()
	_portrait_model = Portrait.create_model(_portrait, _agent)


func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]


func _text(parent: Control, value: String, font_size: int, color := UITheme.CARD_TEXT, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.format_label(label, display, font_size, color)
	parent.add_child(label)
	return label
