extends VBoxContainer

## A Ranger's catch log on the character sheet's Profession tab (doc 292, concept C), in place
## of the list of rewards: each water's fish with the catches, dimmed until one is caught; the
## big fish, the best day and the fish dried; and the next reward with the catches to go.
## Shows CatchLog.describe(); rebuilt only when it changes.
const HAY := Color("e2c06a")
const MUTED := Color("aeb5ad")

var _shown := {}
var _size := {}


## `size` is the sheet's size entry: its type scale, `label` and `carry` (the tile's side).
func show_log(log: Dictionary, size: Dictionary) -> void:
	if log == _shown and size == _size: return
	_shown = log.duplicate(true)
	_size = size
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var type: Dictionary = size.type
	add_theme_constant_override("separation", int(size.gap))
	_text(self, "CATCH LOG", int(size.label), HAY)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", int(size.gap) + 2)
	add_child(kinds)
	for fish: Dictionary in log.fish:
		var caught := int(fish.count) > 0
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		kinds.add_child(column)
		var picture := TextureRect.new()
		picture.texture = load(String(fish.picture)) if ResourceLoader.exists(String(fish.picture)) else null
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var frame := UITheme.framed_picture(picture)
		frame.custom_minimum_size = Vector2.ONE * float(size.carry)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		frame.modulate = Color.WHITE if caught else Color(1, 1, 1, 0.45)
		column.add_child(frame)
		var label := _text(column, "%s · %d" % [fish.name, int(fish.count)], int(type.small), UITheme.CARD_TEXT if caught else MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.tooltip_text = "%s · %d caught" % [fish.name, int(fish.count)]
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", int(size.gap) * 2 + 2)
	facts.add_theme_constant_override("v_separation", 4)
	add_child(facts)
	for fact: Array in log.facts:
		_text(facts, String(fact[0]), int(type.body), MUTED)
		_text(facts, String(fact[1]), int(type.body), UITheme.CARD_TEXT)
	var next: Dictionary = log.next
	if next.is_empty(): return
	_text(self, "NEXT REWARD", int(size.label), HAY)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UITheme.cell_style("raised_off", 3))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)
	var level := Label.new()
	level.text = "Lv %d" % int(next.level)
	UITheme.format_label(level, true, int(size.tag), MUTED)
	tag.add_child(level)
	var words := _text(row, String(next.text), int(type.body), UITheme.CARD_TEXT)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _text(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.format_label(label, false, font_size, color)
	parent.add_child(label)
	return label
