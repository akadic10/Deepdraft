extends VBoxContainer

## Read-only equipment view. Planned upgrades are deliberately not item IDs or
## active equip actions until those physical goods and recipes exist.
var _tool_name: Label
var _tool_details: Label
var _benefit: Label
var _icon: TextureRect
var _upgrade_name: Label
var _upgrade_status: Label
var _upgrade_description: Label
var _upgrade_method: Label
var _pending: Label
var _shown := {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_label(self, "EQUIPPED TOOL", 12, UITheme.HEARTH_COPPER)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	add_child(card)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 10)
	card.add_child(contents)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	contents.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(64,64)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(identity)
	_tool_name = _label(identity, "", 17)
	_tool_name.add_theme_font_override("font", UITheme.hearth_title_font())
	_tool_details = _label(identity, "", 12, UITheme.HEARTH_MUTED)
	_benefit = _label(contents, "", 14)
	_pending = _label(self, "", 13, UITheme.HEARTH_COPPER)
	_label(self, "UPGRADE PATH", 12, UITheme.HEARTH_COPPER)
	_upgrade_name = _label(self, "", 18)
	_upgrade_name.add_theme_font_override("font", UITheme.hearth_title_font())
	_upgrade_status = _label(self, "", 13, UITheme.HEARTH_COPPER)
	_upgrade_description = _label(self, "", 14)
	_upgrade_method = _label(self, "", 13, UITheme.HEARTH_MUTED)

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

func _label(parent: Control, text: String, size: int, color := UITheme.HEARTH_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
