extends "res://scripts/tests/WorkerCraftingTest.gd"

## Windows in Deepdraft's Hearthblock style (doc 261, phase 1): the pieces in UITheme, the
## frame every window wears (its family's band, the display-face title, the keycap close,
## a flush body where the content brings its own margins), and the grouped picture grid.
## godot --headless --path . --script res://scripts/tests/WindowStyleTest.gd
const Grid = preload("res://scripts/ui/PictureGrid.gd")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Window style test timed out"); quit(1))
	await _setup_crafting_fixture()
	_check_pieces()
	await _check_windows()
	await _check_grid()
	for failure in failures: push_error(failure)
	print("WINDOW_STYLE_OK: pieces, frames and families, picture grid" if failures.is_empty() else "WINDOW_STYLE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_pieces() -> void:
	var registry := root.get_node("UIRegistry")
	var people: Color = registry.get_icon_family_color("people")
	var cell := UITheme.CARD_CELL
	var frame := _art(UITheme.window_frame(people))
	_expect(frame.get_pixel(0, 0).a == 0.0 and _near(frame.get_pixel(frame.get_width() >> 1, 4 * cell + 1), people)
		and _near(frame.get_pixel(frame.get_width() >> 1, (UITheme.WINDOW_BAND_ROWS - 1) * cell + 1), people.darkened(0.55))
		and _near(frame.get_pixel(frame.get_width() >> 1, (UITheme.WINDOW_BAND_ROWS + 1) * cell + 1), UITheme.CARD_FACE),
		"window frame: a notched slab with the family's band, its seam and the hearth face below")
	_expect(UITheme.window_frame(people) == UITheme.window_frame(people), "frames are built once per family")
	var frame_texture: Texture2D = UITheme.window_frame(people).texture
	_expect(frame_texture is CanvasTexture and (frame_texture as CanvasTexture).texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"cell art draws nearest, so its cells stay crisp at any UI scale")
	var theme := UITheme.shared_theme()
	_expect(theme.get_stylebox("normal", "Button") == UITheme.cell_style("raised", 3)
		and theme.get_stylebox("pressed", "Button") == UITheme.cell_style("raised_on", 3)
		and theme.get_stylebox("disabled", "Button") == UITheme.cell_style("raised_off", 3), "buttons: raised blocks")
	var on := _art(UITheme.cell_style("raised_on", 3))
	_expect(_near(on.get_pixel(12, 1), UITheme.TAG_TONES.waiting[0]) and _near(on.get_pixel(12, 13), UITheme.RAISED_HOVER),
		"a pressed or selected button has a hay edge")
	_expect(theme.get_stylebox("background", "ProgressBar") == UITheme.cell_style("groove", 2)
		and theme.get_stylebox("fill", "ProgressBar") == UITheme.cell_style("fill", 2)
		and theme.get_stylebox("normal", "LineEdit") == UITheme.cell_style("groove", 2)
		and theme.get_stylebox("grabber", "VScrollBar") == UITheme.cell_style("grabber", 2), "bars, fields and scrollbars: cell grooves")
	_expect(_near(_art(UITheme.hearth_panel(true)).get_pixel(12, 12), UITheme.INSET_FACE)
		and _near(_art(UITheme.catalog_paper_style()).get_pixel(15, 15), UITheme.BOARD_FACE),
		"cards: recessed insets; parchment: the pine board")
	var bar := ProgressBar.new()
	UITheme.hearth_progress(bar)
	_expect(bar.custom_minimum_size.y >= UITheme.cell_style("groove", 2).get_minimum_size().y, "bars are tall enough for their cells")
	bar.free()
	# A window's theme wears its family: the shown tab and the main action are the family
	# block, pictures sit on the family tile with a hay rim when selected. Outside the
	# windows the main action stays a hay block.
	var family := UITheme.family_theme(people)
	_expect(family == UITheme.family_theme(people) and UITheme.family_theme(Color.TRANSPARENT) == theme, "family themes are built once; no family is the shared theme")
	_expect(family.get_stylebox("pressed", "Button") == UITheme.family_block_style(people)
		and family.get_stylebox("normal", "FamilyBlock") == UITheme.family_block_style(people)
		and family.get_font("font", "FamilyBlock") == UITheme.display_font()
		and theme.get_stylebox("normal", "FamilyBlock") == UITheme.cell_style("hay", 3), "the family block for tabs and main actions; hay outside windows")
	var block := _art(UITheme.family_block_style(people))
	_expect(_near(block.get_pixel(12, 13), people), "the family block is the family's colour")
	_expect(family.get_stylebox("normal", "PictureTile") == UITheme.icon_tile_style(people)
		and family.get_stylebox("pressed", "PictureTile") == UITheme.icon_tile_style(people, "selected")
		and family.get_stylebox("panel", "PictureFrame") == UITheme.icon_tile_style(people), "pictures on the family tile")
	var selected := _art(UITheme.icon_tile_style(people, "selected"))
	_expect(_near(selected.get_pixel(16, 0), UITheme.TAG_TONES.waiting[0]) and _near(selected.get_pixel(16, 16), people),
		"a selected picture has a hay rim round the family tile")


func _check_windows() -> void:
	var registry := root.get_node("UIRegistry")
	var windows: Array = manager.get_children().filter(func(node): return node is UIWindow)
	_expect(windows.size() >= 5, "the dock's windows are registered")
	for window: UIWindow in windows:
		var colour: Color = registry.get_icon_family_color(window.family)
		_expect(not window.family.is_empty() and window.get_theme_stylebox("panel") == UITheme.window_frame(colour)
			and window.theme == UITheme.family_theme(colour), "%s wears its family's band and theme" % window.window_id)
		# Nothing inside a window hides the family theme or uses the HUD's title face.
		for node: Node in window.find_children("*", "Control", true, false):
			var control := node as Control
			_expect(control.theme == null or control.theme != UITheme.shared_theme(), "%s: %s inherits the family theme" % [window.window_id, control.name])
			if control is Label:
				_expect(control.get_theme_font("font") != UITheme.hearth_title_font(), "%s: %s is not in the HUD's title face" % [window.window_id, control.name])
		_expect(window.get_title_label().get_theme_font("font") == UITheme.display_font()
			and window.get_title_label().get_theme_color("font_color") == UITheme.CARD_TITLE, "%s: the title in the display face" % window.window_id)
		var close: Button = window._close_button
		_expect(close.text == "✕" and (close.get_theme_stylebox("normal") as StyleBoxTexture).texture == UITheme.cell_style("keycap", 3).texture,
			"%s closes on a keycap" % window.window_id)
		# Everything in the title bar fits the band, so the bar is exactly the band.
		_expect(window.get_title_bar().get_combined_minimum_size().y == UITheme.WINDOW_BAND_ROWS * UITheme.CARD_CELL,
			"%s: the title bar is the band (%.0f px)" % [window.window_id, window.get_title_bar().get_combined_minimum_size().y])
	var craft: UIWindow = manager.get_ui_window("craft")
	var plain: UIWindow = manager.get_ui_window("trade")
	_expect(craft.family == "settlement" and craft.flush and craft.get_body_slot().get_theme_constant("margin_left") == 0,
		"crafting is settlement, with a flush body")
	_expect(plain.family == "people" and not plain.flush and plain.get_body_slot().get_theme_constant("margin_left") == 14,
		"a plain window (Trade) keeps the usual margins")
	# A window opens and lays out in its frame: the title on the band, the body under it.
	manager.open("craft")
	await _frames(4)
	var top := craft.get_global_rect().position.y
	var band := UITheme.WINDOW_BAND_ROWS * UITheme.CARD_CELL
	var close_rect: Rect2 = craft._close_button.get_global_rect()
	_expect(craft.visible and craft.get_title_bar().get_global_rect().end.y == top + band and craft.get_body_slot().get_global_rect().position.y == top + band
		and close_rect.position.y > top + UITheme.CARD_CELL and close_rect.end.y <= top + band - UITheme.CARD_CELL,
		"an open window's title and keycap sit on its band (bar %s, close %s)" % [craft.get_title_bar().get_global_rect(), close_rect])
	# Today's crafting contents inherit the settlement theme without being rebuilt.
	var settlement: Color = registry.get_icon_family_color("settlement")
	var recipe: Button = panel._recipes.get_tile(panel.selected)
	_expect(panel._queue_button.get_theme_stylebox("normal") == UITheme.family_block_style(settlement)
		and panel._recipes_tab.get_theme_stylebox("normal") == UITheme.family_block_style(settlement)
		and panel._orders_tab.get_theme_stylebox("normal") == UITheme.button_normal_style()
		and recipe != null and recipe.get_theme_stylebox("normal") in [UITheme.icon_tile_style(settlement), UITheme.icon_tile_style(settlement, "planned")],
		"crafting's Queue and shown tab are terracotta blocks; its recipes sit on terracotta tiles")
	manager.close("craft")
	# Wrapped text measures against no width while a window is hidden; once open and laid
	# out, the window shrinks to its contents (the Trade preview opened 2,600 px tall).
	manager.open("trade")
	await _frames(3)
	var trade: UIWindow = manager.get_ui_window("trade")
	_expect(trade.size.y < 400 and trade.size.y == trade.get_combined_minimum_size().y,
		"an opened window fits its wrapped text (%.0f px)" % trade.size.y)
	manager.close("trade")


func _check_grid() -> void:
	var grid = Grid.new()
	grid.family = root.get_node("UIRegistry").get_icon_family_color("settlement")
	scene.add_child(grid)
	var bench: Texture2D = load("res://assets/ui/furniture/bench.png")
	var torch: Texture2D = load("res://assets/ui/furniture/wooden_torch.png")
	var groups := [
		{"id": "dining", "title": "Dining", "items": [
			{"id": "bench", "picture": bench, "count": 3, "mark": "on", "selected": true, "tooltip": "Log bench"},
			{"id": "table", "picture": bench, "mark": "missing", "dim": true, "tooltip": "Log table: needs 2 logs"}]},
		{"id": "lighting", "title": "Lighting", "state": "Some", "items": [{"id": "torch", "picture": torch}]},
	]
	grid.show_groups(groups)
	await _frames(2)
	var tile: Button = grid.get_tile("bench")
	_expect(tile != null and tile.icon == bench and tile.get_node("Count").text == "3" and tile.get_node("Mark") != null
		and (tile.get_node("Selected") as Panel).get_theme_stylebox("panel") == UITheme.selection_ring() and tile.tooltip_text == "Log bench",
		"a tile carries its picture, count, mark, hay selection ring and name")
	var dim: Button = grid.get_tile("table")
	_expect(dim.get_theme_stylebox("normal") == UITheme.icon_tile_style(grid.family, "planned")
		and not dim.has_node("Count") and dim.get_theme_color("icon_normal_color").v < 0.6, "a missing recipe is dimmed")
	_expect(grid.get_tile("torch").get_theme_stylebox("normal") == UITheme.icon_tile_style(grid.family, "normal"), "tiles sit on the window's family tile")
	var pressed := []
	grid.item_pressed.connect(func(id): pressed.append(id))
	grid.group_pressed.connect(func(id): pressed.append("group:" + id))
	tile.pressed.emit()
	_expect(pressed.is_empty(), "a press is reported once the click is over, so a rebuild cannot free its button mid-click")
	await _frames(1)
	_expect(pressed == ["bench"], "pressing a tile names its item")
	grid.show_groups(groups)
	_expect(grid.get_tile("bench") == tile, "an unchanged refresh keeps the tiles")
	groups[0].items[0].count = 4
	groups[0].items[1].dim = false
	grid.show_groups(groups)
	_expect(grid.get_tile("bench") == tile and tile.get_node("Count").text == "4"
		and grid.get_tile("table").get_theme_stylebox("normal") == UITheme.icon_tile_style(grid.family, "normal"),
		"a refresh that changes only looks restyles the same tiles, so focus and hover stay with them")
	groups[1].items[0].hidden = true
	grid.show_groups(groups)
	await _frames(1)
	_expect(not grid.get_tile("torch").visible and not _heading_visible(grid, "LIGHTING"), "a group whose tiles are all hidden hides with them")
	tile.grab_focus()
	groups[0].items.append({"id": "any", "text": "Any"})
	grid.show_groups(groups)
	_expect(grid.get_tile("bench") != tile and grid.get_tile("bench").has_focus() and grid.get_tile("any").text == "Any",
		"a rebuild gives focus back to the tile with the same id; a tile can show a word for its picture")
	# Storage's rows: the heading beside its tiles, its state a tag that toggles the group.
	grid.heading_beside = true
	grid.show_groups([{"id": "materials", "title": "Materials", "state": "Some", "items": [{"id": "stone", "picture": bench, "mark": "on"}]}])
	await _frames(2)
	_expect(grid.get_tile("stone").get_node("Mark").get_global_rect().position.y >= grid.get_global_rect().position.y - 0.5,
		"a mark on the first row stays inside the grid, so a scroll edge cannot cut it")
	var state: Button = null
	for node: Node in grid.find_children("*", "Button", true, false):
		if (node as Button).text == "Some": state = node
	_expect(state != null and state.get_theme_stylebox("normal") == UITheme.cell_style("tag_waiting", 3), "a group's state is a tag in its tone")
	state.pressed.emit()
	await _frames(1)
	_expect(pressed.has("group:materials"), "the state toggles its group")
	grid.free()


static func _heading_visible(grid: Control, title: String) -> bool:
	return grid.find_children("*", "Label", true, false).any(func(label: Label): return label.text == title and label.is_visible_in_tree())


## Cell art stores 8 bits a channel, so colours compare within one step.
static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006 and absf(a.a - b.a) < 0.006


## A cell style's art: the style's texture draws nearest and holds the art (doc 23).
func _art(style: StyleBox) -> Image:
	return ((style as StyleBoxTexture).texture as CanvasTexture).diffuse_texture.get_image()
