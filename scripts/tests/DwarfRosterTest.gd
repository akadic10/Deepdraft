extends "res://scripts/tests/DwarfInspectorTest.gd"

var dock
var roster
var idle_worker
var resting_worker


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Roster test timed out"); quit(1))
	await _setup_fixture()
	root.size = Vector2i(1280, 720)
	var generator := root.get_node("WorldGenerator")
	generator._maps_ready = true
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
	generator._cache_block_ids()
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	rig = load("res://scripts/systems/Camera.gd").new()
	rig.name = "Camera"
	scene.add_child(rig)
	rig.set_process(false)
	camera = rig.camera_node
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	camera.global_position = Vector3(53, 42, 56)
	camera.look_at(Vector3(41, 21, 42))
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.camera_path = NodePath("../Camera")
	director.window_manager_path = NodePath("../Windows")
	director.dock_ui_path = NodePath("../Dock")
	scene.add_child(director)
	roster = director._roster_panel
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dwarf_director_path = NodePath("../Dwarves")
	scene.add_child(explorer)
	await _settle()
	# Colony's page has the real Dwarves entry: the player roster, not the developer controls.
	_click(dock._button_by_target.colony.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("colony"), "Colony opens its page")
	dock._colony_panel._entries.get_node("EntryDwarves").pressed.emit()
	await _settle()
	_expect(manager.is_open("dwarves") and not manager.is_open("dwarves_dev") and not manager.is_open("colony"), "Colony's Dwarves opens the real roster")
	_expect(roster._empty.visible, "empty roster explains settlement arrival")
	dock._counts.refresh()
	_expect(dock._button_by_target.colony.count_text == "", "no dwarves: Colony shows no count")
	_adopt_worker()
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "worker reaches real carried-crate phase")
	worker.sleep = .76
	idle_worker = _add_dwarf(510)
	idle_worker.sleep = .86
	resting_worker = _add_dwarf(511)
	resting_worker.sleep = .18
	resting_worker._begin_sleep()
	_add_dwarf(512).sleep = .44
	_add_dwarf(513).sleep = .68
	roster.refresh()
	await _settle()
	_expect(roster._rows.size() == 5 and roster._filters.working.button.text == "Working  1" and roster._filters.resting.button.text == "Resting  1", "filters show actual workforce counts")
	_expect(roster._rows[worker].activity.text == "Hauling" and "12" in roster._rows[worker].note.text, "row reports real hauling and crate contents")
	_expect(roster._rows[worker].cargo_icon.texture.resource_path.ends_with("base_resources_seed_oak_acorn.png"), "cargo uses existing model thumbnail")
	# The profession's picture on a tile the portrait's size; the bar to the next level only
	# where the profession earns levels, but its room on every row (doc 23).
	var assets: Node = root.get_node("DwarfAssets")
	var first: Dictionary = roster._rows[worker]
	_expect(first.role.texture != null and first.role.texture.resource_path == String(assets.profession_definition(worker.profession).icon)
		and is_equal_approx(first.role.get_parent().size.x, first.portrait.get_parent().size.x),
		"each row shows its profession's picture on a tile the portrait's size")
	var name_offset: float = first.name.get_global_rect().position.y - first.button.get_global_rect().position.y
	var even := true
	for agent in roster._rows:
		var row: Dictionary = roster._rows[agent]
		even = even and is_equal_approx(row.name.get_global_rect().position.y - row.button.get_global_rect().position.y, name_offset) \
			and row.level.self_modulate.a == 0.0 and row.identity.get_global_rect().end.y <= row.button.get_global_rect().end.y
	_expect(even, "Workers earn no levels yet: no bar shows, and every name sits at the same height within its row")
	var rows_before: Dictionary = {}
	for agent in roster._rows: rows_before[agent] = roster._rows[agent].button.get_global_rect()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/colony_overview_review/initial.png")
	var portrait = roster._rows[worker].viewport
	var task_count: int = tasks._agents.size()
	roster.refresh()
	await _settle()
	_expect(is_instance_valid(portrait) and roster._rows[worker].viewport == portrait and portrait.get_child_count() == 4, "portrait is reused and contains only rendering nodes")
	_expect(tasks._agents.size() == task_count, "portrait never registers another actor")
	_click(roster._rows[worker].button.get_global_rect().position + Vector2(100,32))
	await _settle()
	_expect(explorer.is_object_selected(director, worker) and manager.is_open("dwarves"), "roster selects through the shared world selection owner")
	_expect(not manager.is_open("character_sheet") and roster._card._agent == worker and roster._card.visible and not roster._detail_empty.visible,
		"the selected dwarf's Details card shows inside the overview, without a second window")
	_expect(roster._rows[worker].button.button_pressed, "selected row is highlighted")
	# The Details card, after Stonehearth's Citizens: who the dwarf is, and the ways in.
	var mood: Dictionary = worker.get_mood().step()
	_expect(roster._card._name_label.text == worker.dwarf_name and roster._card._profession.text == "Worker · Level 1"
		and roster._card._buttons.crafting.visible, "the card names the dwarf and their profession, with a Worker's crafting")
	_expect(roster._rows[worker].mood_word.text == String(mood.word) and roster._rows[worker].mood_face.texture == load(String(mood.icon))
		and roster._rows[idle_worker].mood.visible, "every row shows the dwarf's mood: the step's face and word")
	var word_label: Label = roster._rows[worker].mood_word
	var word_width: float = word_label.get_theme_font("font").get_string_size(word_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_label.get_theme_font_size("font_size")).x
	_expect(word_label.size.x >= word_width - 1.0, "the mood word has room to show whole (%.0f of %.0f px)" % [word_label.size.x, word_width])
	_click(roster._card._buttons.character_sheet.get_global_rect().get_center())
	await _settle()
	_expect(manager.is_open("character_sheet") and manager.is_open("dwarves") and explorer._dwarf_panel._agent == worker,
		"Character sheet opens the dwarf's sheet beside Colony Dwarves")
	# The sheet opens beside the Sky Dial, over the middle of the rows on a small screen: click
	# a row by its portrait.
	_click(roster._rows[idle_worker].button.get_global_rect().position + Vector2(30,28))
	await _settle()
	_expect(manager.is_open("character_sheet") and explorer._dwarf_panel._agent == idle_worker and roster._card._agent == idle_worker,
		"an open sheet follows the roster's selection")
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("character_sheet") and manager.is_open("dwarves"), "Escape closes the sheet first, then Colony Dwarves")
	_click(roster._rows[worker].button.get_global_rect().position + Vector2(30,28))
	await _settle()
	_click(roster._card._follow.get_global_rect().get_center())
	_expect(rig.is_following(worker) and roster._card._follow.text == "Stop following", "the card's Follow uses the shared camera action")
	_click(roster._card._follow.get_global_rect().get_center())
	_expect(not rig.is_following(worker), "the card's Follow can stop tracking")
	var zoom: float = rig._target_zoom
	var task_id: int = idle_worker.current_task_id
	_click(roster._rows[idle_worker].locate.get_global_rect().get_center())
	_expect(rig._target_pos == idle_worker.global_position + Vector3(0,1.5,0) and rig._target_zoom == zoom, "Locate moves camera while preserving zoom")
	_expect(idle_worker.current_task_id == task_id and not idle_worker.is_walking(), "Locate issues no movement or work orders")
	_expect(explorer.is_object_selected(director, worker), "Locate button does not also select its row")
	_click(roster._filters.resting.button.get_global_rect().get_center())
	await _settle()
	_expect(roster._rows[resting_worker].button.visible and not roster._rows[worker].button.visible, "Resting filter uses sleep state")
	_expect(roster._card._agent == worker, "filtering does not redirect the selected dwarf")
	_click(roster._filters.all.button.get_global_rect().get_center())
	roster._search.text = idle_worker.dwarf_name.to_lower()
	roster.refresh()
	_expect(roster._rows[idle_worker].button.visible and not roster._rows[worker].button.visible, "name search is case insensitive")
	roster._search.text = "Nobody matches this"
	roster.refresh()
	_expect(roster._empty.visible and "match" in roster._empty.text, "search has honest empty result")
	# Camera movement polls physical keys; GUI consumption alone cannot protect typing.
	roster._search.grab_focus()
	var typing := InputEventKey.new()
	typing.physical_keycode = KEY_W; typing.keycode = KEY_W; typing.pressed = true
	Input.parse_input_event(typing)
	Input.flush_buffered_events()
	await process_frame
	var camera_before: Vector3 = rig._target_pos
	rig._handle_pan(.1)
	_expect(rig._target_pos == camera_before, "typing a name does not pan the camera")
	roster._search.release_focus()
	rig._handle_pan(.1)
	_expect(rig._target_pos != camera_before, "movement keys resume after leaving search")
	typing = typing.duplicate(); typing.pressed = false
	Input.parse_input_event(typing)
	Input.flush_buffered_events()
	roster._search.clear()
	roster.refresh()
	await _settle()
	# Real contact/deposit and resting updates cannot shuffle All rows.
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "worker reaches actual stockpile deposit")
	worker._process(worker._work_execution._handling_duration)
	roster.refresh()
	await _settle()
	_expect(roster._rows[worker].cargo_icon.visible == false and zone.stored_count() == 12, "deposit clears carried thumbnail and preserves stock")
	for agent in rows_before:
		_expect(roster._rows[agent].button.get_global_rect() == rows_before[agent], "activity update leaves row position stable")
	worker.dev_make_tired()
	worker._process(.01)
	roster.refresh()
	_expect(roster._rows[worker].activity.text == "Resting", "organic sleep transition updates roster")
	# Hidden actors remain accounted for, with world actions safely disabled.
	director._on_slice_changed(19)
	explorer._on_slice_changed(19)
	roster.refresh()
	_expect(roster._rows.size() == 5 and roster._rows[worker].locate.disabled and roster._rows[worker].button.disabled, "slice-hidden dwarves stay listed without revealing their location")
	_expect(not director.inspect_dwarf(worker), "slice guard also protects direct stale action calls")
	director._on_slice_changed(127)
	explorer._on_slice_changed(127)
	roster.refresh()
	# Pause affects simulation, not the roster's UI refresh.
	clock_node.set_paused(true)
	idle_worker.sleep = .55
	roster._process(roster.REFRESH_SECONDS)
	_expect(roster._rows[idle_worker].rest_label.text == "55%", "UI refresh stays current while game is paused")
	# Scroll/lazy portraits, keyboard focus and arrivals.
	for i in range(14): _add_dwarf(520 + i)
	roster.refresh()
	await _settle()
	var rendered := 0
	for row: Dictionary in roster._rows.values():
		if row.viewport != null: rendered += 1
	_expect(rendered < roster._rows.size(), "offscreen portraits are not rendered eagerly")
	roster._scroll.scroll_vertical = 180
	await _settle()
	var scroll: int = roster._scroll.scroll_vertical
	var next: Button = roster._rows[resting_worker].button
	next.grab_focus()
	var fixed_rect := next.get_global_rect()
	_add_dwarf(550)
	roster.refresh()
	await _settle()
	_expect(next.get_global_rect() == fixed_rect and next.has_focus() and roster._scroll.scroll_vertical == scroll, "new arrivals preserve existing positions, scroll and focus")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = roster._scroll.get_global_rect().get_center()
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel = wheel.duplicate(); wheel.pressed = false
	root.push_input(wheel, true)
	await _settle()
	_expect(roster._scroll.scroll_vertical > scroll and rig._target_zoom == zoom, "scrolling roster never zooms the world")
	# Removal and reused numeric IDs must not redirect the selected dwarf.
	roster._scroll.scroll_vertical = 0
	await _settle()
	director.inspect_dwarf(idle_worker)
	var old_id: int = idle_worker.dwarf_id
	tasks.deregister_dwarf(old_id)
	idle_worker.queue_free()
	await _settle()
	explorer._refresh_selected()
	roster.refresh()
	_expect(not manager.is_open("character_sheet"), "removed actor clears inspector")
	_expect(not roster._card.visible and roster._detail_empty.visible, "removed actor clears the Details card")
	idle_worker = _add_dwarf(old_id)
	roster.refresh()
	_expect(not explorer.is_object_selected(director, idle_worker), "new actor with reused ID is not selected implicitly")
	# Native title drag and small/large layouts with details inside the overview.
	await _settle()
	var start: Vector2 = director._roster_window.position
	_drag_title(start + Vector2(130,18), Vector2(20,-8))
	_expect(director._roster_window.position != start, "roster title bar drags")
	var moved: Vector2 = director._roster_window.position
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("dwarves") and not roster.is_processing(), "Escape closes roster and stops polling")
	dock._toggle_window("dwarves")
	await _settle()
	_expect(director._roster_window.position == moved, "reopening remembers dragged position")
	var original_name: String = worker.dwarf_name
	worker.dwarf_name = "Borin Copperbeard Stonehammer XVIII"
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		director._roster_window.position = Vector2(24,76)
		roster._scroll.scroll_vertical = 0
		roster.refresh()
		explorer._inspector_positioned = false
		director.inspect_dwarf(worker)
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		var roster_rect: Rect2 = director._roster_window.get_global_rect()
		_expect(bounds.encloses(roster_rect), "roster fits " + str(resolution))
		_expect(roster_rect.end.y <= dock._dock_panel.position.y - 8, "roster clears bottom dock " + str(resolution))
		_expect(not manager.is_open("character_sheet") and roster_rect.encloses(roster._card.get_global_rect()), "the Details card stays in the window at " + str(resolution))
		_expect(not roster._detail_frame.get_global_rect().intersects(roster._scroll.get_global_rect()), "details and roster do not overlap " + str(resolution))
		_expect(roster._rows[worker].button.size.y <= float(roster._size.row), "rows keep their size " + str(resolution))
		_expect(roster._card._follow.get_global_rect().end.y <= roster._detail_frame.get_global_rect().end.y, "the card's buttons stay inside it at " + str(resolution))
		_expect(roster._rows[worker].mood.visible and roster_rect.encloses(roster._rows[worker].mood.get_global_rect()), "the Mood column shows at " + str(resolution))
		if resolution.y >= 1300:
			_expect(roster._size == roster.SIZES.large and is_equal_approx(roster_rect.size.x, 1688.0), "tall screens take the large size (%.0f across)" % roster_rect.size.x)
		_expect(roster_rect.encloses(roster._rows[worker].locate.get_global_rect()), "Locate stays reachable with long name " + str(resolution))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/colony_overview_review/roster_%d.png" % resolution.x)
	worker.dwarf_name = original_name
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280,720)
		explorer._refresh_selected()
		roster.refresh()
		await _settle()
		director._roster_window.position = Vector2(24,32)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/colony_overview_review/colony-dwarves.png")
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("dwarves") and not manager.is_open("character_sheet") and explorer.selected_dwarf(director) == null, "Escape closes the complete overview and clears selection")
	director.inspect_dwarf(worker)
	_expect(explorer.get_compact_panel().visible and not manager.is_open("character_sheet") and explorer.get_compact_panel()._agent == worker,
		"world inspection returns to the compact panel after the overview closes")
	explorer._perform_dwarf_action("follow")
	dock._toggle_window("dwarves")
	await _settle()
	_expect(not manager.is_open("character_sheet") and not explorer.get_compact_panel().visible and roster._card._agent == worker,
		"opening overview transfers existing selected dwarf onto its Details card")
	_expect(rig.is_following(worker) and roster._card._follow.text == "Stop following", "presentation handoff preserves camera follow")
	_key(KEY_ESCAPE)
	_expect(not rig.is_following(worker), "closing overview releases camera follow")
	# Reopening with a retained filter chooses a visible matching dwarf.
	roster.category = "resting"
	dock._toggle_window("dwarves")
	await _settle()
	var selected = explorer.selected_dwarf(director)
	_expect(selected != null and roster._rows[selected].button.visible and selected.is_sleeping(), "initial selection respects the retained roster filter")
	_key(KEY_ESCAPE)
	# Developer tools are still reachable through their new menu.
	_click(dock._button_by_target.development.get_global_rect().get_center())
	await _settle()
	_click(_button_named(dock._panel_body, "Dwarf tools").get_global_rect().get_center())
	_expect(manager.is_open("dwarves_dev"), "developer controls remain available under Menu")
	await _check_counts_and_levels()
	if failures.is_empty(): print("DWARF_ROSTER_OK: native menu, compact table with moods, the Details card with the character sheet and Follow, real haul/sleep, live filters/search, stable rows, selection handoff, Locate, slice/removal guards, lazy rendering, drag, scroll, Escape and 960/1280/2560 layouts")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## Colony counts the idle dwarves, as the roster's Idle filter files them, once each has
## waited a few game minutes (doc 23, "Counts"); its hover card says so and the tile never
## moves. Then a row follows a change of profession: the Miner's picture and its bar to the
## next level (doc 23).
func _check_counts_and_levels() -> void:
	_key(KEY_ESCAPE)
	roster.category = "all"
	dock._toggle_window("dwarves")
	await _settle()
	var colony: Control = dock._button_by_target.colony
	var tile: Rect2 = colony.get_global_rect()
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	var idle := 0
	var groups := {}
	var agree := true
	for agent in director.get_roster():
		var group: String = inspection.roster_state(agent).group
		groups[group] = true
		agree = agree and inspection.roster_group(agent) == group
		if group == "idle": idle += 1
	_expect(agree and groups.size() >= 2, "the count's quick check files every dwarf as the roster does (%s)" % [groups.keys()])
	dock._counts.refresh()
	clock_node.advance_hours(0.1)
	dock._counts.refresh()
	var note := "1 dwarf is idle" if idle == 1 else "%d dwarves are idle" % idle
	_expect(idle > 0 and colony.count_text == str(idle) and colony.count_tone == "waiting" and colony.count_note == note
		and colony.get_global_rect() == tile, "Colony counts the %d idle dwarves in hay, and keeps its place (%s)" % [idle, colony.count_text])
	colony.grab_focus()
	colony._show_info()
	_expect(colony._info._status.text == note and colony._info._tag_row.visible, "Colony's hover card says what its count counts")
	colony.release_focus()
	_add_dwarf(560)
	dock._counts.refresh()
	_expect(colony.count_text == str(idle), "a dwarf who has just run out of work waits before it counts")
	clock_node.advance_hours(0.1)
	dock._counts.refresh()
	_expect(colony.count_text == str(idle + 1), "and counts once it has waited")
	var miner_key := "base:profession:miner"
	var assets: Node = root.get_node("DwarfAssets")
	var miner = idle_worker
	roster.refresh()
	await _settle()
	var row: Dictionary = roster._rows[miner]
	var offset: float = row.name.get_global_rect().position.y - row.button.get_global_rect().position.y
	miner._complete_profession_change(miner_key)
	miner.profession_experience[miner_key] = int(assets.experience_threshold(2)) + 40
	roster.refresh()
	await _settle()
	var experience: Dictionary = inspection.experience(miner)
	_expect(row.role.texture != null and row.role.texture.resource_path == String(assets.profession_definition(miner_key).icon),
		"the row's picture follows a change of profession")
	_expect(experience.earns and float(experience.progress) > 0.0 and row.level.self_modulate.a == 1.0
		and absf(row.level.value - float(experience.progress) * 100.0) < 0.5 and String(experience.line) in row.button.tooltip_text,
		"a Miner's row shows the way to the next level, and its hover says it (bar %.2f for %.4f, shown %s, line %s)"
		% [row.level.value, float(experience.progress), row.level.self_modulate.a == 1.0, String(experience.line) in row.button.tooltip_text])
	_expect(is_equal_approx(row.name.get_global_rect().position.y - row.button.get_global_rect().position.y, offset),
		"the bar has its room already: the name stays put")
	_key(KEY_ESCAPE)


func _add_dwarf(id: int):
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	director.add_child(agent)
	agent.position = Vector3(38.5 + id % 6, 21, 38.5 + id % 4)
	agent.set_process(false)
	director._agents.append(agent)
	tasks.register_dwarf(agent)
	return agent


func _settle() -> void:
	for i in range(8): await process_frame


func _button_named(parent: Node, caption: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == caption: return child
		if child.get_script() == preload("res://scripts/ui/DockIconButton.gd") and child.caption == caption: return child
	return null


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	root.push_input(event, true)


func _drag_title(point: Vector2, offset: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = point
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + offset; motion.relative = offset
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	press = press.duplicate(); press.pressed = false; press.position = motion.position
	root.push_input(press, true)
