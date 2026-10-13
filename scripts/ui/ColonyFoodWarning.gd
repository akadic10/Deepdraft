extends PanelContainer

## Persistent, quiet warning driven by actual failed food searches, not by
## total inventory (which can include forbidden, reserved or unreachable food).
var label: Label
var remaining := 0.0

func _ready() -> void:
	name = "ColonyFoodWarning"
	UITheme.apply_surface(self)
	add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -326
	offset_right = -20
	offset_top = 20
	offset_bottom = 20
	custom_minimum_size = Vector2(306,0)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 278
	label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",UITheme.HEARTH_COPPER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	hide()

func _process(delta: float) -> void:
	remaining -= delta
	if remaining > 0: return
	remaining = 1.0
	refresh()

func refresh() -> void:
	var names: PackedStringArray = []
	for agent: DwarfAgent in TaskManager._agents.values():
		if is_instance_valid(agent) and agent._food != null and agent._food.shortage and agent._food.hungry():
			names.append(agent.dwarf_name)
	visible = not names.is_empty()
	label.text = "%d %s cannot find reachable food.\nHarvest berries or make stored food accessible." % [names.size(),"dwarf" if names.size()==1 else "dwarves"]
	tooltip_text = ", ".join(names)
