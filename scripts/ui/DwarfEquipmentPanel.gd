extends VBoxContainer

## The character sheet's Equipment tab (doc 261): the tool the dwarf has, on the people
## tile, with its tier, materials and benefit, then the upgrade path. Read-only: planned
## upgrades are deliberately not item IDs or active equip actions until those physical
## goods and recipes exist.
const HAY := Color("e2c06a")
const MUTED := Color("aeb5ad")
# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM
var _tool_name: Label
var _tool_details: Label
var _benefit: Label
var _icon: TextureRect
var _upgrade_name: Label
var _upgrade_status: Label
var _upgrade_description: Label
var _upgrade_method: Label
var _pending: Label
var _headings: Array[Label] = []
var _shown := {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_headings.append(_label(self, "EQUIPPED TOOL", MEDIUM.small, HAY))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.cell_style("raised", 3))
	add_child(card)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	card.add_child(contents)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	contents.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(64, 64)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(UITheme.framed_picture(_icon))
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(identity)
	_tool_name = _label(identity, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	_tool_details = _label(identity, "", MEDIUM.small, MUTED)
	_benefit = _label(contents, "", MEDIUM.body)
	_pending = _label(self, "", MEDIUM.body, HAY)
	_headings.append(_label(self, "UPGRADE PATH", MEDIUM.small, HAY))
	_upgrade_name = _label(self, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	_upgrade_status = _label(self, "", MEDIUM.body, HAY)
	_upgrade_description = _label(self, "", MEDIUM.body)
	_upgrade_method = _label(self, "", MEDIUM.body, MUTED)

## The sheet's sizes: body text, the small capitals over each part, names and the picture.
func apply_size(text: int, heading: int, title: int, picture: float) -> void:
	for label: Label in _headings: label.add_theme_font_size_override("font_size", heading)
	for label: Label in [_tool_name, _upgrade_name]: label.add_theme_font_size_override("font_size", title)
	for label: Label in [_benefit, _upgrade_description]: label.add_theme_font_size_override("font_size", text)
	for label: Label in [_tool_details, _pending, _upgrade_status, _upgrade_method]: label.add_theme_font_size_override("font_size", text)
	_icon.custom_minimum_size = Vector2.ONE * picture

func show_equipment(details: Dictionary) -> void:
	if details == _shown: return
	_shown = details.duplicate(true)
	_tool_name.text = String(details.get("name", "Basic work tools"))
	_tool_details.text = "%s\n%s" % [details.get("tier", "Standard"), details.get("materials", "")]
	_benefit.text = String(details.get("benefit", ""))
	var path := String(details.get("icon", ""))
	_icon.texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	_upgrade_name.text = String(details.get("upgrade_name", "Future tool upgrades"))
	_upgrade_status.text = String(details.get("upgrade_status", "Planned"))
	_upgrade_description.text = String(details.get("upgrade_description", ""))
	_upgrade_method.text = String(details.get("upgrade_method", ""))
	_pending.text = String(details.get("pending", ""))
	_pending.visible = not _pending.text.is_empty()

func _label(parent: Control, text: String, font_size: int, color := UITheme.CARD_TEXT, display := false) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.format_label(label, display, font_size, color)
	parent.add_child(label)
	return label
