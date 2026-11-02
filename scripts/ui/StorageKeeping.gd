extends VBoxContainer

## The storage window's Keeping list (doc 23 "The storage window"; doc 282, the owner's pick,
## 2026-10-29): on Contents, above the pictures.
## - A heading says how the store keeps food: "Keeping · 7°C in a sealed room".
## - A row for each food that spoils, the soonest to rot first: its picture, its name and the
##   count of its stalest crate, a bar of that crate's remaining life in its freshness tone,
##   and the days it has left there (FoodSpoilage.freshness).
## - A store holding no such food says how long blueberries would keep there instead (the
##   Temperature view's keeping_food); a store that takes no food shows nothing.
## The window refreshes it after each spoilage pass. Presentation only.
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
## The window's sizes for the screen (StorageInspectorPanel.SIZES): heading, hint, exact,
## heading_width, bar and gap.
var sizes: Dictionary = {}
## What the rows show, the soonest to rot first: {key, count, total, spoil, days, tone, text}.
var rows: Array[Dictionary] = []
var heading := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows the store's keeping; false, and hidden, when the store takes no food.
func show_storage(storage: StorageComponent) -> bool:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rows.clear()
	var drops: ItemDropManager = storage.drop_manager
	var spoilage = StockpileManager.spoilage
	var stalest := {}   # item key -> its row
	for slot in storage.stored_entries():
		var stack: Dictionary = storage.stored_entries()[slot]
		var key := String(stack.item)
		var food := drops.food_definition(key)
		if float(food.get("keeps_days", 0.0)) <= 0.0: continue
		var fresh: Dictionary = spoilage.freshness(food, float(stack.get("spoil", 0.0)), storage.slot_cell(slot) + Vector3i.UP)
		var row: Dictionary = stalest.get(key, {"key": key, "total": 0, "days": INF})
		row.total = int(row.total) + int(stack.count)
		if float(fresh.days) < float(row.days):
			row.merge({"count": int(stack.count), "spoil": float(stack.get("spoil", 0.0)), "days": float(fresh.days),
				"tone": fresh.tone, "text": fresh.text}, true)
		stalest[key] = row
	var keeping_key := String(UIRegistry.get_time_slice().get("temperature", {}).get("keeping_food", ""))
	visible = not stalest.is_empty() or storage.accepts_key(keeping_key)
	if not visible: return false
	rows.assign(stalest.values())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.days) < float(b.days))
	add_theme_constant_override("separation", int(sizes.get("gap", 8)))
	var place := _place(storage)
	heading = "Keeping · %s" % _place_words(place)
	var title := _label(heading, int(sizes.get("heading", 20)), UITheme.CARD_TITLE, true)
	add_child(title)
	for row: Dictionary in rows: add_child(_row(drops, row))
	if rows.is_empty() and not drops.food_definition(keeping_key).is_empty():
		var definition := drops.get_item_def(keeping_key)
		var name := String(definition.get("plural_name", String(definition.get("display_name", keeping_key)).to_lower()))
		add_child(_label("Nothing here spoils yet. %s would keep %s here." % [name.left(1).to_upper() + name.substr(1),
			spoilage.days_text(spoilage.keeps_days_at(drops.food_definition(keeping_key), place))], int(sizes.get("hint", 16)), UITheme.CARD_TEXT))
	return true


## A food's row: picture, name and count, the bar of its stalest crate and its days left.
func _row(drops: ItemDropManager, row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(sizes.get("gap", 8)))
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	var definition := drops.get_item_def(String(row.key))
	var name := String(definition.get("display_name", row.key))
	var plural := String(definition.get("plural_name", name.to_lower()))
	line.tooltip_text = "%d of %d %s: %s here." % [int(row.count), int(row.total), plural, row.text] if int(row.count) < int(row.total) \
		else "%d %s: %s here." % [int(row.count), plural if int(row.count) > 1 else name.to_lower(), row.text]
	var picture := TextureRect.new()
	var path := Inventory.thumbnail_path(String(row.key))
	if ResourceLoader.exists(path): picture.texture = load(path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2.ONE * float(sizes.get("exact", 48)) * 0.7
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)
	var label := _label("%s · %d" % [name, int(row.count)], int(sizes.get("hint", 16)), UITheme.CARD_TEXT)
	label.custom_minimum_size.x = float(sizes.get("heading_width", 150)) * 1.1
	line.add_child(label)
	var bar := ProgressBar.new()
	UITheme.hearth_progress(bar)
	var cell := 3 if float(sizes.get("bar", 10)) >= 14.0 else 2
	bar.add_theme_stylebox_override("background", UITheme.cell_style("groove", cell))
	bar.add_theme_stylebox_override("fill", UITheme.cell_style("tag_" + String(row.tone), cell))
	bar.max_value = 1.0
	bar.value = clampf(1.0 - float(row.spoil), 0.0, 1.0)   # the stalest crate's life left
	bar.custom_minimum_size.y = float(sizes.get("bar", 10))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(bar)
	var left := _label("%s left" % StockpileManager.spoilage.days_text(float(row.days)), int(sizes.get("hint", 16)), UITheme.CARD_TEXT)
	left.custom_minimum_size.x = float(sizes.get("heading_width", 150))
	line.add_child(left)
	return line


## The store's middle cell's air: where its heading reads the temperature.
static func _place(storage: StorageComponent) -> Vector3i:
	var cells: Array = storage.get("tile_cells") if storage.get("tile_cells") != null else []
	if cells.is_empty():
		for slot in storage.stored_entries(): return storage.slot_cell(slot) + Vector3i.UP
		return Vector3i.ZERO
	var middle := Vector3.ZERO
	for cell: Vector3i in cells: middle += Vector3(cell)
	middle /= float(cells.size())
	var best: Vector3i = cells[0]
	for cell: Vector3i in cells:
		if Vector3(cell).distance_squared_to(middle) < Vector3(best).distance_squared_to(middle): best = cell
	return best + Vector3i.UP


## "7°C in a sealed room", "12°C under the open sky, in the rain".
static func _place_words(place: Vector3i) -> String:
	var temperature := float(RoomManager.temperature_at(place))
	var where := "under a roof"
	if not RoomManager.get_room_at(place).is_empty(): where = "in a sealed room"
	elif RoomManager.climate.is_open_sky(place): where = "under the open sky" + (", in the rain" if RoomManager.climate.is_wet() else "")
	return "%d°C %s" % [roundi(temperature), where]


func _label(text: String, font_size: int, colour: Color, display := false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if not display else TextServer.AUTOWRAP_OFF
	UITheme.format_label(label, display, font_size, colour)
	return label
