extends "res://scripts/tests/WorkerCraftingTest.gd"

## The compact object panel beside the dock (doc 260, phases 1 and 2), in the family band
## style (doc 259, option A). The style's pieces in UITheme; furniture and goods in the
## panel with their family band, name, badge, status tag, flavour and actions, reaching
## the providers through real clicks; a long name shown whole; the owner list; Esc,
## empty-ground clicks and replacement; reused nodes; and the place beside the dock at
## 7680x2160, 1280x720 and 960x540, clear of the dock, its menus and the view controls.
## godot --headless --path . --script res://scripts/tests/CompactPanelTest.gd [-- --capture]
const OUT := "res://tmp/compact_panel_20261023/"
var compact: Control


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Compact panel test timed out"); quit(1))
	await _setup_crafting_fixture()
	_check_format()
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dock_ui_path = NodePath("../Dock")
	scene.add_child(explorer)
	compact = explorer.get_compact_panel()
	var bench = _put(BENCH, Vector3i(44,20,40))
	var bed = _put("base:furniture:log_bed", Vector3i(36,20,46))
	await _frames(4)
	await _check_furniture(bench)
	await _check_owner_list(bed, bench)
	await _check_closing(bench)
	await _check_goods()
	await _check_placement(bench)
	for failure in failures: push_error(failure)
	print("COMPACT_PANEL_OK: format, furniture, owners, closing, goods, reuse, placement" if failures.is_empty() else "COMPACT_PANEL_FAIL")
	quit(0 if failures.is_empty() else 1)


## Phase 1: every piece of the format builds with the approved colours and sizes.
func _check_format() -> void:
	var names := UITheme.display_font() as FontVariation
	var rows := UITheme.body_font() as FontVariation
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_expect(names.base_font.resource_path.ends_with("fredoka_variable.ttf") and int(names.variation_opentype[wght]) == 600
		and rows.base_font.resource_path.ends_with("nunito_variable.ttf") and int(rows.variation_opentype[wght]) == 700,
		"display face is Fredoka SemiBold (600), body face Nunito Bold (700) (doc 23, Type)")
	# The compact panel in the same style (doc 259, option A): the badge on a stone chip,
	# the status on a tag in its tone.
	var chip := UITheme.cell_style("chip", 3)
	_expect(_near(_art(chip).get_pixel(12, 12), UITheme.KEYCAP_FACE) and chip.texture_margin_bottom == chip.texture_margin_top,
		"badge chip: pale stone with a shallow skirt")
	for tone: String in ["fine", "waiting", "blocked"]:
		var tag := UITheme.cell_style("tag_" + tone, 3)
		_expect(_near(_art(tag).get_pixel(12, 12), UITheme.TAG_TONES[tone][0]) and UITheme.tag_ink(tone) == UITheme.TAG_TONES[tone][4],
			"%s tag: its tone's face and ink" % tone)
	# Hover cards in the Hearthblock style (doc 259, option C): voxel cells, never round.
	var family := Color("4f4a5c")
	var slab := UITheme.cell_slab(12, 12, UITheme.CARD_FACE, UITheme.CARD_TOP, UITheme.CARD_SKIRT, UITheme.CARD_OUTLINE, 2, 2, family, 6)
	_expect(slab.get_pixel(0, 0).a == 0.0 and _near(slab.get_pixel(1, 1), UITheme.CARD_OUTLINE)
		and _near(slab.get_pixel(6, 1), family.lightened(0.12)) and _near(slab.get_pixel(6, 3), family)
		and _near(slab.get_pixel(6, 5), family.darkened(0.55)) and _near(slab.get_pixel(6, 7), UITheme.CARD_FACE)
		and _near(slab.get_pixel(6, 9), UITheme.CARD_SKIRT) and _near(slab.get_pixel(6, 11), UITheme.CARD_OUTLINE),
		"card slab: notched corner, outline, family top with a lit edge and a seam, hearth face, dark skirt")
	var keycap := UITheme.cell_style("keycap", 3)
	_expect(keycap.texture.get_width() == 24 and keycap.texture_margin_bottom > keycap.texture_margin_top
		and UITheme.cell_style("keycap", 3) == keycap, "keycap: 3 px cells, a deep skirt, built once")
	_expect(UITheme.tan_button_style("hover").bg_color != UITheme.TAN_FILL and UITheme.tan_button_style().bg_color == UITheme.TAN_FILL
		and UITheme.tan_button_style("disabled").bg_color.get_luminance() < UITheme.TAN_FILL.get_luminance(), "tan button states")
	_expect(UITheme.title_band_style().bg_color == UITheme.BAND_FILL, "olive title band")
	var tab := UITheme.tab_style(true)
	_expect(tab.bg_color == UITheme.TAB_ACTIVE and UITheme.tab_style().bg_color == UITheme.TAB_FILL
		and tab.corner_radius_top_left == 6 and tab.corner_radius_bottom_left == 0, "tabs: blue, brighter when selected, round on top")


func _check_furniture(bench) -> void:
	var id := "installed:%d" % bench.installed_id
	var data: Dictionary = furniture.get_explorer_data(id)
	_expect(explorer.select_object(furniture, id), "workbench selects")
	await _frames(3)
	_expect(compact.visible and not manager.is_open("character_sheet"), "furniture opens the compact panel, not the window")
	_expect(compact.get_title() == String(data.title), "the band names the piece")
	var settlement: Color = root.get_node("UIRegistry").get_icon_family_color("settlement")
	_expect(_near(compact._frame_art.get_image().get_pixel(compact._frame_art.get_width() >> 1, compact._metrics.cell * 3 + 1), settlement)
		and compact._picture_tile.get_theme_stylebox("panel").texture == UITheme.icon_tile_style(settlement).texture,
		"furniture wears the settlement family: its band and its picture tile")
	_expect(compact._badge.visible and compact._badge_value.text == String(data.badge.value) and compact._badge_icon.texture != null,
		"badge shows the piece's appeal with its picture")
	_expect(compact._picture.texture != null, "panel shows the workbench picture")
	_expect(compact._status.text == "Any Worker crafts here" and compact._tone == "fine"
		and compact._status_tag.get_theme_stylebox("panel") == UITheme.cell_style("tag_fine", 3), "the status says who crafts here, on a moss tag")
	var status_width: float = UITheme.body_font().get_string_size(compact._status.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		compact._status.get_theme_font_size("font_size")).x
	_expect(compact._status.size.x >= status_width - 1.0, "the status tag is wide enough for its whole text")
	_expect(compact._flavour.text == "A broad bark-covered stump with a worn cut top, axe scars and chipped edges.", "flavour is the first sentence")
	for action_id: String in ["move", "uninstall", "craft"]:
		var tile: Button = compact.get_action_button(action_id)
		_expect(tile != null and tile.icon != null, "%s is a picture tile" % action_id)
	_expect(compact.get_action_button("details") == null, "no Details button: the panel itself carries the facts (owner, 2026-10-23)")
	# The tile's hover card (doc 259, option C): its name on the work family's colour.
	var move_tile: Button = compact.get_action_button("move")
	move_tile.grab_focus()
	await create_timer(.35).timeout
	await _frames(2)
	var card: Control = move_tile._info
	_expect(card != null and card.visible and card._title.text == "Move" and card._body.text.begins_with("Choose a new spot")
		and card.get_global_rect().end.y <= move_tile.get_global_rect().position.y, "a panel tile's hover card names it above the tile")
	var work: Color = root.get_node("UIRegistry").get_icon_family_color("work")
	_expect(card._side == "above" and _near(card._art.get_image().get_pixel(card._art.get_width() >> 1, card._cell * 3 + 1), work)
		and card._title.get_theme_color("font_color") == UITheme.CARD_TITLE, "the tile's card wears the work family's colour on top")
	move_tile.release_focus()
	_expect(compact.theme.get_stylebox("panel", "TooltipPanel") == UITheme.cell_style("card", UITheme.CARD_CELL),
		"the panel's plain tooltips are the hearth slab")
	_expect(compact._flavour.tooltip_text == String(data.details), "the full description shows on hovering the flavour line")
	# DEV actions follow the switch and sit apart from the rest.
	var registry := root.get_node("UIRegistry")
	var dev_was: bool = registry.dev_tools_enabled
	registry.dev_tools_enabled = false
	explorer._refresh_selected()
	_expect(compact.get_action_button("remove") == null and not compact._dev_actions.visible, "DEV switch off hides DEV actions")
	registry.dev_tools_enabled = true
	explorer._refresh_selected()
	_expect(compact.get_action_button("remove") != null and compact.get_action_button("remove").get_parent() == compact._dev_actions,
		"DEV switch on shows DEV actions apart")
	registry.dev_tools_enabled = dev_was
	explorer._refresh_selected()
	await _frames(2)
	# Real clicks reach the provider.
	_click(compact.get_action_button("uninstall").get_global_rect().get_center())
	await _frames(2)
	_expect(bench.flagged_uninstall and compact._status.text == "Marked for uninstall" and compact._tone == "waiting"
		and compact._status_tag.get_theme_stylebox("panel") == UITheme.cell_style("tag_waiting", 3), "Pack up marks the piece; the status waits on a hay tag")
	_expect(compact.get_action_button("uninstall").icon == load("res://assets/ui/icons/cancel.png"), "the marked piece offers Cancel uninstall")
	_click(compact.get_action_button("uninstall").get_global_rect().get_center())
	await _frames(2)
	_expect(not bench.flagged_uninstall, "a second click cancels the uninstall")
	await _shoot("workbench")
	# Refreshes update in place.
	var before := [compact.get_action_button("move"), compact.get_action_button("craft"), compact._name, compact._status]
	for i in range(4):
		explorer._refresh_selected()
		await _frames(1)
	var after := [compact.get_action_button("move"), compact.get_action_button("craft"), compact._name, compact._status]
	_expect(before.size() == after.size() and range(before.size()).all(func(i): return is_same(before[i], after[i])), "refreshes reuse the panel's nodes")


func _check_owner_list(bed, bench) -> void:
	_expect(explorer.select_object(furniture, "installed:%d" % bed.installed_id), "bed selects")
	await _frames(3)
	_expect(compact._status.text == "Anyone may sleep here", "an unassigned bed says anyone may sleep there")
	_click(compact.get_action_button("assign_bed").get_global_rect().get_center())
	await _frames(3)
	var rows: Array = compact._owner_rows.get_children()
	_expect(compact._owners.visible and rows.size() == 1 + tasks.get_agents().size(), "Assign owner lists anyone and every dwarf")
	_expect(rows.slice(1).all(func(row): return row.get_meta("portrait").texture is ViewportTexture), "each dwarf shows a live portrait")
	await _shoot("bed_owners")
	for row: Button in rows:
		if row.get_meta("action_id") == "assign_bed:%d" % worker.dwarf_id:
			_click(row.get_global_rect().get_center())
	await _frames(3)
	_expect(bed.assigned_dwarf_id == worker.dwarf_id and not compact._owners.visible, "a portrait click assigns the bed")
	_expect(compact._status.text == "%s's bed" % worker.dwarf_name, "the panel names the owner")
	_click(compact.get_action_button("assign_bed").get_global_rect().get_center())
	await _frames(2)
	explorer.select_object(furniture, "installed:%d" % bench.installed_id)
	await _frames(2)
	_expect(not compact._owners.visible and compact.get_title() == String(furniture.get_explorer_data("installed:%d" % bench.installed_id).title),
		"selecting another object replaces the panel and drops the bed's list")


func _check_closing(bench) -> void:
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await _frames(2)
	_expect(not compact.visible and explorer._provider == null, "Esc closes the panel")
	explorer.select_object(furniture, "installed:%d" % bench.installed_id)
	await _frames(3)
	var frame: Rect2 = compact._frame.get_global_rect()
	_click(Vector2(frame.position.x + 12, frame.end.y - 12))
	await _frames(2)
	_expect(compact.visible and explorer.is_object_selected(furniture, "installed:%d" % bench.installed_id), "a click on the panel never reaches the world")
	_click(Vector2(root.size.x * 0.5, 24))
	await _frames(2)
	_expect(not compact.visible, "a click on empty ground closes the panel")


func _check_goods() -> void:
	drops.spawn_drop("base:resources:stone:rough_stone", 1, Vector3i(40,21,36))
	var stone: Node3D = drops._loose.keys()[-1]
	_expect(explorer.select_object(drops, stone), "loose stone selects")
	await _frames(3)
	_expect(compact.get_title() == "Rough Stone" and not compact._badge.visible and compact._picture.texture != null,
		"single goods show their picture and no badge")
	_expect(compact._status.text == "Awaiting collection" and compact._tone == "waiting", "loose goods wait for collection")
	_click(compact.get_action_button("permission").get_global_rect().get_center())
	await _frames(2)
	_expect(not drops.get_explorer_data(stone).is_empty() and bool(stone.get_meta("disallowed", false))
		and compact._tone == "blocked" and compact._status_tag.get_theme_stylebox("panel") == UITheme.cell_style("tag_blocked", 3),
		"Disallow reaches the goods and the status turns to a rust tag")
	_click(compact.get_action_button("permission").get_global_rect().get_center())
	await _frames(2)
	_expect(not bool(stone.get_meta("disallowed", false)), "Allow restores the goods")
	drops.restore_stored_item(ACORN, Vector3i(42,20,36), 17)
	var crate: Node3D = drops.stored_node_at(Vector3i(42,20,36))
	_expect(explorer.select_object(drops, crate), "stored crate selects")
	await _frames(3)
	_expect(compact._badge.visible and compact._badge_value.text == "17 / 24" and compact._status.text == "In storage"
		and compact.get_action_button("permission") == null, "a crate shows its fill and stays colony stock")
	drops.spawn_drop(BENCH_ITEM, 1, Vector3i(38,21,36))
	var packed: Node3D = drops._loose.keys()[-1]
	_expect(explorer.select_object(drops, packed), "packed furniture selects")
	await _frames(3)
	var materials := root.get_node("CraftMaterials")
	var appeal: Dictionary = materials.appeal_badge(furniture.def_for_item(BENCH_ITEM), materials.of_item(packed), true)
	_expect(compact._badge_value.text == String(appeal.value) and compact._picture.texture != null,
		"packed furniture shows its installed appeal and the furniture picture")
	await _shoot("packed_goods")
	# The owner's example (2026-10-23): today's plate cut "Rudimentary hearth (packed)"
	# short. The band shows a long name whole.
	drops.restore_stored_item("base:resources:furniture:hearth", Vector3i(44,20,36), 1)
	var hearth: Node3D = drops.stored_node_at(Vector3i(44,20,36))
	_expect(explorer.select_object(drops, hearth), "a packed hearth in storage selects")
	await _frames(4)
	var title: String = compact.get_title()
	var needed: float = UITheme.display_font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, compact._name.get_theme_font_size("font_size")).x
	_expect(title.begins_with("Rudimentary hearth") and compact._name.size.x >= needed and compact._name.tooltip_text.is_empty()
		and compact.get_action_button("permission") == null, "the band shows a long name whole, with no actions beside it")
	await _shoot("packed_hearth")
	explorer.clear_selection()


func _check_placement(bench) -> void:
	for size: Vector2i in [Vector2i(7680,2160), Vector2i(1280,720), Vector2i(960,540)]:
		root.size = size
		await _frames(4)
		explorer.clear_selection()
		explorer.select_object(furniture, "installed:%d" % bench.installed_id)
		var first: Rect2 = compact.get_global_rect()
		await _frames(4)
		var rect: Rect2 = compact.get_global_rect()
		_expect(first == rect, "panel opens at its final size and place, without a jump %s" % size)
		var dock_rect: Rect2 = dock._dock_panel.get_global_rect()
		_expect(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect) and not rect.intersects(dock_rect), "panel on screen and off the dock %s" % size)
		if size.x >= 7680:
			_expect(rect.end.x <= dock_rect.position.x and is_equal_approx(rect.end.y, dock_rect.end.y), "wide screens: left of the dock, bottom-aligned")
		else:
			_expect(rect.end.y <= dock_rect.position.y and rect.position.x <= dock_rect.position.x + 1, "narrow screens: above the dock's left end")
		var hud: Control = dock._time_slice_hud
		for reserved: Rect2 in hud.occupied_rects() + [dock._sky_dial.get_global_rect()]:
			_expect(not rect.intersects(reserved), "panel clear of the time controls %s" % size)
		# The slice tower opens above Slice: the panel makes room while it is open.
		hud.tower.show()
		await _frames(2)
		_expect(not compact.get_global_rect().intersects(hud.tower.get_global_rect()), "panel clear of the open slice tower %s" % size)
		hud.tower.hide()
		await _frames(2)
		_expect(compact.get_global_rect() == rect, "panel returns beside the dock when the tower closes %s" % size)
		dock._open_action_panel("craft")
		await _frames(8)
		_expect(not dock._panel_container.get_global_rect().intersects(compact.get_global_rect()), "Craft menu keeps clear of the panel %s" % size)
		await _shoot("craft_%d" % size.x)
		dock._close_action_panel()
		dock._orders.set_open(true, "orders")
		await _frames(4)
		_expect(not dock._orders._shelf.get_global_rect().intersects(compact.get_global_rect()), "Orders shelf keeps clear of the panel %s" % size)
		dock._orders.set_open(false)
		await _shoot("panel_%d" % size.x)
	explorer.clear_selection()


func _put(key: String, cell: Vector3i):
	furniture._install(key, furniture.get_defs()[key], cell, 0, "base:material:pine")
	return furniture._installed[furniture._next_installed_id - 1]


func _shoot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")

## Cell art stores 8 bits a channel, so colours compare within one step.
static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006 and absf(a.a - b.a) < 0.006


## A cell style's art: the style's texture draws nearest and holds the art (doc 23).
func _art(style: StyleBox) -> Image:
	return ((style as StyleBoxTexture).texture as CanvasTexture).diffuse_texture.get_image()
