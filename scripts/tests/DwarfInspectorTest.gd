extends "res://scripts/tests/HaulingAnimationTest.gd"

## Real actors, task/cargo transitions, native picking and controls. No saves
## or player window preferences are written by this fixture. A selected dwarf shows in
## the compact panel; its big button opens the character sheet (doc 261 phase 3): the
## header, six tabs, the mood as thought cards on a five-step scale, the traits as tags
## and the level for every profession, one height from tab to tab at four screen sizes.
var director
var rig


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Dwarf inspector test timed out"); quit(1))
	await _setup_fixture()
	root.size = Vector2i(1280, 720)
	root.get_node("WorldGenerator")._maps_ready = true
	root.get_node("WorldGenerator").heightmap.resize(1024 * 1024)
	root.get_node("WorldGenerator").heightmap.fill(20)
	root.get_node("WorldGenerator").waterline_map.resize(1024 * 1024)
	root.get_node("WorldGenerator").waterline_map.fill(-1)
	root.get_node("WorldGenerator")._cache_block_ids()
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	rig = load("res://scripts/systems/Camera.gd").new()
	rig.name = "Camera"
	scene.add_child(rig)
	rig.set_process(false)
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.camera_path = NodePath("../Camera")
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	_adopt_worker()
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.name = "Furniture"
	scene.add_child(furniture)
	furniture.set_process(false)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dwarf_director_path = NodePath("../Dwarves")
	explorer.click_tool_paths.append(NodePath("../Furniture"))
	scene.add_child(explorer)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	_aim_above(worker.position)
	await process_frame
	await process_frame
	var screen := camera.unproject_position(worker.position + Vector3(0, 2.5, 0))
	_click(screen)
	await process_frame
	_expect(explorer._provider == director and explorer._object_id == worker, "world click selects the dwarf through shared explorer")
	var compact: Control = explorer.get_compact_panel()
	_expect(compact.visible and not manager.is_open("character_sheet"), "a dwarf opens the compact panel, not a window")
	_expect(compact.get_title() == worker.dwarf_name, "actual generated identity")
	_expect(compact._portrait_model.get_child_count() == (2 if worker.appearance.scar=="none" else 3), "portrait contains static head/body copies and the saved optional scar")
	_expect(tasks._agents.size() == 1, "portrait never registers another worker")
	var mood: Dictionary = worker.get_mood().describe()
	_expect(compact._badge.visible and compact._badge_value.text == "%d%%" % roundi(float(mood.value) * 100)
		and compact._badge.tooltip_text.contains(String(mood.label)), "mood badge shows happiness, with the mood on hover")
	_expect(compact._badge_icon.texture == load(String(worker.get_mood().step().icon)), "mood badge shows the mood step's face")
	_expect(compact._profession_label.text == "Worker" and compact._profession_icon.texture == load("res://assets/ui/icons/worker.png"), "profession row shows the Worker icon")
	_expect(compact._activity_label.text == String(director.get_explorer_data(worker).activity), "activity row shows what the dwarf is doing")
	var activity_width: float = UITheme.body_font().get_string_size(compact._activity_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		compact._activity_label.get_theme_font_size("font_size")).x
	_expect(compact._activity_label.size.x >= activity_width - 1.0, "the activity tag is wide enough for its whole text")
	var frame: Rect2 = compact._frame.get_global_rect()
	_click(Vector2(frame.position.x + frame.size.x * .5, frame.end.y - 10))
	_expect(explorer._object_id == worker, "panel clicks cannot pick through UI")

	# Nearest visible geometry, not the logical 1x1 nav box.
	var behind = load("res://scripts/entities/DwarfFactory.gd").new().spawn(
		load("res://scripts/entities/DwarfFactory.gd").new().generate(142, {}), 142)
	director.add_child(behind)
	director._agents.append(behind)
	behind.position = worker.position - Vector3(0, 6, 0)
	behind.set_process(false)
	_expect(explorer.pick_at_screen(screen).id == worker, "front dwarf wins overlapping silhouettes")
	director._agents.erase(behind)
	behind.free()
	var occlusion_cell := Vector3i(40, 32, 39)
	world.set_block(occlusion_cell.x, occlusion_cell.y, occlusion_cell.z, blocks.get_id("base:terrain:rock:rock01"))
	_expect(explorer.pick_at_screen(screen).is_empty(), "solid rock occludes a dwarf")
	world.set_block(occlusion_cell.x, occlusion_cell.y, occlusion_cell.z, blocks.AIR_ID)
	furniture._active = true
	_expect(not explorer.select_at_screen(screen), "placement tools keep ownership of dwarf clicks")
	furniture._active = false
	director._walk_test = true
	_expect(not explorer.select_at_screen(screen), "walk test keeps click ownership")
	director._walk_test = false

	# Locate/follow leave zoom, pitch, tasks and inventory alone.
	var zoom: float = rig._target_zoom
	var pitch: float = rig._pitch
	_click(compact.get_action_button("locate").get_global_rect().get_center())
	_expect(rig._target_pos == worker.global_position + Vector3(0, 1.5, 0), "Locate centers on the dwarf")
	_expect(rig._target_zoom == zoom and rig._pitch == pitch, "Locate preserves framing")
	_click(compact.get_action_button("follow").get_global_rect().get_center())
	var follow: Button = compact.get_action_button("follow")
	_expect(rig.is_following(worker) and follow.button_pressed and follow.caption == "Stop following", "Follow toggles and stays lit")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = compact._frame.get_global_rect().get_center()
	wheel.pressed = true
	root.push_input(wheel, true)
	_expect(rig.is_following(worker) and rig._target_zoom == zoom, "wheel over the panel retains Follow and world zoom")
	var original_position: Vector3 = worker.position
	worker.position.x += 2
	rig._update_follow()
	explorer._process(.01)
	_expect(rig._target_pos.x == worker.position.x, "Follow tracks moving target")
	_expect(is_equal_approx(explorer._outline.global_position.x - explorer._outline_offset.x, worker.position.x), "outline moves every frame")
	worker.position = original_position
	var pan_event := InputEventKey.new()
	pan_event.physical_keycode = KEY_W
	pan_event.keycode = KEY_W
	pan_event.pressed = true
	Input.parse_input_event(pan_event)
	Input.flush_buffered_events()
	rig._handle_pan(.1)
	pan_event = pan_event.duplicate()
	pan_event.pressed = false
	Input.parse_input_event(pan_event)
	Input.flush_buffered_events()
	_expect(not rig.is_following(worker), "keyboard pan releases Follow")
	explorer._perform_dwarf_action("follow")
	rig._apply_zoom(true)
	_expect(not rig.is_following(worker), "world zoom releases Follow")
	explorer._perform_dwarf_action("follow")
	rig._orbiting = true
	var orbit := InputEventMouseMotion.new()
	orbit.relative = Vector2(20, 0)
	rig._handle_orbit_motion(orbit)
	_expect(not rig.is_following(worker), "orbit releases Follow")
	rig._orbiting = false
	explorer._perform_dwarf_action("follow")
	rig._start_drag()
	_expect(not rig.is_following(worker), "middle drag releases Follow")
	rig._dragging = false
	explorer._perform_dwarf_action("follow")
	director._on_slice_changed(19)
	explorer._on_slice_changed(19)
	_expect(not compact.visible and not rig.is_following(worker), "slice hides the panel and releases Follow")
	_expect(explorer.pick_at_screen(screen).is_empty(), "slice-hidden dwarf cannot be selected")
	director._on_slice_changed(127)
	explorer._on_slice_changed(127)
	explorer.select_object(director, worker)
	# The big button opens the character sheet beside the panel.
	_click(compact.get_action_button("character_sheet").get_global_rect().get_center())
	var panel = explorer._dwarf_panel
	_expect(manager.is_open("character_sheet") and panel.visible and panel._agent == worker and compact.visible,
		"Character sheet opens the window and keeps the panel")
	# The header: the name, the profession with its level and the way to the next, the mood
	# banner, and six tabs.
	var sheet_mood: Dictionary = worker.get_mood().step()
	_expect(panel._name_label.text == worker.dwarf_name and panel._profession.text == "Worker · Level 1"
		and panel._experience.text == "Worker levels are planned" and panel._role_icon.texture == load("res://assets/ui/icons/worker.png"),
		"the header names the dwarf, the profession and its level")
	_expect(panel._banner.visible and panel._banner_word.text == String(sheet_mood.word)
		and panel._banner_value.text == "%d%%" % worker.get_mood().points() and panel._banner_face.texture == load(String(sheet_mood.icon)),
		"the mood banner shows the mood's face, word and happiness")
	_expect(panel._tabs.map(func(tab: Button): return tab.text) == ["Overview", "Mood", "Traits", "Equipment", "Profession", "Tastes"],
		"six tabs: Overview, Mood, Traits, Equipment, Profession and Tastes")

	# Real crate trip: carry amount changes only at contact, then at deposit.
	_expect(await _until(worker.TaskPhase.HAUL_PICKUP), "scheduler reaches pickup")
	explorer._refresh_selected()
	_expect(panel._activity.text == "Picking up supplies" and panel._cargo.text == "Empty hands", "pickup before contact still has empty hands")
	_expect(compact._activity_label.text == "Picking up supplies", "the panel's activity follows live work")
	worker._process(.35)
	explorer._refresh_selected()
	_expect("12 × Oak Acorn (1 crate)" == panel._cargo.text, "crate displays actual contents and physical count")
	_expect(panel._carry_heading.text == "CARRYING · 4 / 4" and panel._carry_tiles.get_child_count() == 1, "one crate uses four carry points and shows as its picture")
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "scheduler reaches delivery")
	explorer._refresh_selected()
	_expect(panel._activity.text == "Delivering supplies" and "Stockpile 1" in panel._destination.text, "live activity and destination")
	var snapshot: Dictionary = worker.serialize_state()
	var reservations: Dictionary = zone.reserved_cells.duplicate(true)
	for i in range(5): explorer._refresh_selected()
	_expect(snapshot == worker.serialize_state() and reservations == zone.reserved_cells, "inspection never mutates goods or reservations")
	_expect(await _until(worker.TaskPhase.HAUL_DEPOSIT), "scheduler reaches set-down")
	worker._process(1)
	explorer._refresh_selected()
	_expect(panel._cargo.text == "Empty hands" and zone.stored_count() == 12, "deposit clears cargo without losing goods")
	worker.dev_make_tired()
	worker._process(.01)
	explorer._refresh_selected()
	_expect(panel._activity.text == "Finding a place to sleep" and "game hours remaining" in panel._explanation.text, "real sleep search state is visible")
	var original_portrait = panel._portrait_model
	var original_compact_portrait = compact._portrait_model
	explorer._refresh_selected()
	_expect(panel._portrait_model == original_portrait and compact._portrait_model == original_compact_portrait, "portraits reused across live refreshes")
	var original_name: String = worker.dwarf_name
	worker.dwarf_name = "Borin Copperbeard Stonehammer XVIII"
	for viewport_size in [Vector2i(2560,1440), Vector2i(1280,720), Vector2i(960,540), Vector2i(1920,1080)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		explorer._refresh_selected()
		await process_frame
		var heights := []
		for tab in range(panel._tabs.size()):
			panel._show_tab(tab)
			explorer._refresh_selected()
			await process_frame
			heights.append(explorer._window.size.y)
		panel._show_tab(0)
		explorer._refresh_selected()
		_expect(heights.min() == heights.max(), "the sheet keeps one height from tab to tab at %s %s" % [viewport_size, heights])
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(explorer._window.get_global_rect()), "the sheet fits %s" % viewport_size)
		_expect(panel._follow.get_global_rect().end.y <= viewport_size.y, "actions remain reachable at %s" % viewport_size)
		_expect(panel._scroll.size.y >= 96, "the tab body stays usable at %s (%.0f px)" % [viewport_size, panel._scroll.size.y])
		_expect(panel._cargo.get_combined_minimum_size().x < explorer._window.size.x, "cargo wraps within the sheet")
		_expect(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(compact.get_global_rect()), "compact panel fits %s" % viewport_size)
		if viewport_size.y >= 1300:
			_expect(panel._size == panel.SIZES.large and is_equal_approx(explorer._window.size.x, 780.0),
				"tall screens take the concept's size: 780 px across (%.0f)" % explorer._window.size.x)
	worker.dwarf_name = original_name

	# Selecting furniture shows it in the same panel, closes the sheet and stops follow.
	var key := "base:furniture:bench"
	furniture._install(key, furniture.get_defs()[key], Vector3i(48,20,42), 0)
	var piece = furniture._installed.values()[0]
	explorer._perform_dwarf_action("follow")
	explorer.select_object(furniture, "installed:%d" % piece.installed_id)
	_expect(not rig.is_following(worker) and not manager.is_open("character_sheet")
		and compact.get_title() == String(furniture.get_explorer_data("installed:%d" % piece.installed_id).title),
		"switching object releases Follow, closes the sheet and shows the piece")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_expect(not rig.is_following(worker) and not compact.visible, "Escape clears the panel and Follow")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	explorer.open_character_sheet()
	manager.close("character_sheet")
	_expect(rig.is_following(worker) and explorer.is_object_selected(director, worker) and compact.visible,
		"closing the character sheet keeps the dwarf selected and followed")
	explorer.clear_selection()
	_expect(not rig.is_following(worker), "clearing the selection releases Follow")
	explorer.select_object(director, worker)
	explorer._perform_dwarf_action("follow")
	tasks.deregister_dwarf(worker.dwarf_id)
	worker.queue_free()
	await process_frame
	explorer._refresh_selected()
	_expect(not compact.visible and not rig.is_following(worker), "removed dwarf clears selection safely")
	await _inspect_furniture_trip()
	await _inspect_mood_and_profession()

	if "--capture" in OS.get_cmdline_user_args():
		await _capture_inspector()
	if failures.is_empty():
		print("DWARF_INSPECTOR_OK: compact panel, character sheet, terrain/slice/tool guards, live cargo/sleep, camera controls, cleanup, responsive UI")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _adopt_worker() -> void:
	director._agents.clear()
	worker.reparent(director)
	director._agents.append(worker)


func _inspect_furniture_trip() -> void:
	var definition: Dictionary = furniture.get_defs()["base:furniture:bench"]
	await _new_trip(String(definition.item_key), 1)
	_adopt_worker()
	explorer.select_object(director, worker)
	explorer.open_character_sheet()
	var ghost = load("res://scripts/components/FurnitureGhostComponent.gd").new()
	ghost.setup(50, "base:furniture:bench", definition, Vector3i(45,20,44), 0)
	ghost.source_id = tasks.allocate_source_id()
	ghost.drop_manager = drops
	tasks.register_work_source(ghost.source_id, ghost)
	var built := [false]
	ghost.install_callback = func(_ghost): built[0] = true
	ghost.update_lease()
	_expect(await _until(worker.TaskPhase.FETCH_PICKUP), "builder starts pickup")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._cargo.text == "Empty hands", "reserved packed furniture is not yet carried")
	_expect(await _until(worker.TaskPhase.FETCH_TO_GHOST), "builder carries to placement")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._activity.text == "Delivering furniture", "fetch activity is distinct from hauling")
	_expect(String(definition.display_name) in explorer._dwarf_panel._destination.text, "destination names the planned furniture")
	_expect(explorer._dwarf_panel._carry_heading.text == "CARRYING · 4 / 4", "packed furniture uses the real carry cost")
	_expect(await _until(worker.TaskPhase.FETCH_DEPOSIT), "builder reaches installation")
	explorer._refresh_selected()
	_expect(explorer._dwarf_panel._activity.text == "Installing furniture", "installation status follows live work")
	worker._process(1)
	explorer._refresh_selected()
	_expect(built[0] and explorer._dwarf_panel._cargo.text == "Empty hands", "installed furniture leaves the cargo readout")
	explorer.clear_selection()
	tasks.unregister_work_source(ghost.source_id)


## The Mood tab and the five steps: thought cards, what weighs on the dwarf on the left and
## what lifts their spirits on the right, strongest first, with the hours left and value;
## the latest two on Overview; the step's word, face and marker; when the face shows over
## the head. Then the traits as tags, and the Miner's level, rewards and Change profession.
func _inspect_mood_and_profession() -> void:
	explorer.select_object(director, worker)
	explorer.open_character_sheet()
	var panel = explorer._dwarf_panel
	var mood = worker.get_mood()
	var concern = load("res://scripts/components/DwarfConcern.gd")
	worker.sleep = 1.0
	worker.get_food().value = 1.0
	_expect(mood.thoughts().is_empty() and mood.points() == 50 and mood.step().word == "Content", "with no thoughts a dwarf is Content at 50")
	mood.bedroom_memory_hours = 18.0
	mood.recreation_memory_hours = 11.0
	_expect(mood.points() == 68 and mood.step().word == "Joyful", "their own bedroom and a game with a friend: Joyful")
	mood.thermal_memory.chilly = 20.0
	mood.record_dining("seat_only")
	mood.dining_memory_hours = 6.0
	_expect(mood.points() == 60 and mood.step().word == "Happy" and not mood.unhappy(), "two small worries leave them Happy at 60")
	explorer._refresh_selected()
	panel._show_tab(1)
	var cards := func(box: Node) -> Array:
		return box.get_children().filter(func(child: Node): return child.has_meta("thought")).map(func(card: Node): return card.get_meta("thought"))
	var bad: Array = cards.call(panel._bad)
	var good: Array = cards.call(panel._good)
	_expect(bad.map(func(card: Dictionary): return card.text.text) == ["Chilly sleep", "Ate without a table"]
		and good.map(func(card: Dictionary): return card.text.text) == ["Slept in my own bedroom", "Played a board game with a friend"],
		"what weighs on them on the left, what lifts their spirits on the right, strongest first")
	_expect(bad[0].points.text == "−5" and bad[0].hours.text == "20h" and good[0].points.text == "+10" and good[0].hours.text == "18h",
		"each thought shows its hours left and its value")
	_expect(cards.call(panel._latest).map(func(card: Dictionary): return card.text.text) == ["Played a board game with a friend", "Ate without a table"],
		"Overview leads with the latest two thoughts")
	# At the medium tier (1280×720) a common thought shows in full: the type scale's body
	# step cut "Slept in my own bedroom" short, so these cards take the small step (doc 23).
	await process_frame
	await process_frame
	var bedroom: Label = good[0].text
	var needed: float = bedroom.get_theme_font("font").get_string_size(bedroom.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		bedroom.get_theme_font_size("font_size")).x
	_expect(needed <= bedroom.size.x + 0.5, "\"Slept in my own bedroom\" shows in full (needs %.0f px, has %.0f)" % [needed, bedroom.size.x])
	var family: Color = root.get_node("UIRegistry").get_icon_family_color("people")
	_expect(panel._mood_word.text == "Happy" and panel._banner_word.text == "Happy" and panel._banner_value.text == "60%"
		and panel._markers[3].modulate.a == 1.0 and panel._markers[2].modulate.a == 0.0
		and panel._steps[3].get_theme_stylebox("panel") == UITheme.family_block_style(family), "the five-step scale marks Happy")
	_expect(panel._mood_face.texture == load("res://assets/ui/icons/mood_happy.png"), "the Mood tab shows the step's face")
	mood.bedroom_memory_hours = 0.0
	mood.recreation_memory_hours = 0.0
	mood.dining_memory_hours = 0.0
	_expect(mood.points() == 45 and mood.step().word == "Content" and concern.describe(worker).is_empty(), "one small worry keeps them Content, with no face over the head")
	mood.thermal_memory.chilly = 0.0
	mood.thermal_memory.cold = 20.0
	_expect(mood.points() == 30 and mood.step().word == "Unhappy" and String(concern.describe(worker).get("kind", "")) == "mood",
		"a night in the cold makes them Unhappy, and the face shows over the head")
	worker.get_food().value = 0.1
	_expect(mood.points() == 15 and mood.step().word == "Miserable", "cold and famished: Miserable")
	explorer._refresh_selected()
	bad = cards.call(panel._bad)
	_expect(bad.size() == 2 and bad[1].text.text == "Famished" and bad[1].hours.text == "now", "hunger lasts until they eat")
	_expect(panel._markers[0].modulate.a == 1.0 and panel._banner_face.texture == load("res://assets/ui/icons/mood_miserable.png"), "the scale marks Miserable")
	mood.thermal_memory.cold = 0.0
	worker.get_food().value = 1.0
	# The traits as tags in the header, moss for good ones and rust for bad ones.
	var kept_traits: Array[String] = worker.traits.duplicate()
	worker.traits.assign(["base:trait:hardworking", "base:trait:light_sleeper"])
	explorer._refresh_selected()
	var tags: Array = panel._trait_tags.get_children()
	_expect(tags.size() == 2 and tags[0].get_theme_stylebox("panel") == UITheme.cell_style("tag_fine", 3)
		and tags[1].get_theme_stylebox("panel") == UITheme.cell_style("tag_blocked", 3) and not String(tags[1].tooltip_text).is_empty(),
		"traits show as tags, moss for good ones and rust for bad ones, the description on hover")
	_expect(panel._traits_list.get_child_count() == 2, "the Traits tab describes each trait")
	panel._show_tab(0)
	await process_frame
	await process_frame
	var one_line := func(label: Label) -> bool: return not label.is_visible_in_tree() or label.size.y <= label.get_line_height() + 4
	_expect(one_line.call(panel._traits_heading) and panel._headings.all(one_line), "the small capitals over each part keep to one line")
	worker.traits.assign(kept_traits)
	# The level and the way to the next show for every profession; the Miner earns them.
	worker.profession = "base:profession:miner"
	worker.profession_experience = {"base:profession:miner": 46}
	explorer._refresh_selected()
	_expect(panel._profession.text == "Miner · Level 2" and panel._experience.text == "40% to level 3 · 46 blocks mined"
		and is_equal_approx(panel._experience_bar.value, 40.0), "the Miner's level and the way to the next")
	panel._show_tab(4)
	await process_frame
	await process_frame
	var rewards: Array = panel._rewards.get_children()
	_expect(rewards.size() == 5 and rewards[1].tooltip_text == "Earned" and rewards[2].tooltip_text == "Not earned yet", "the Profession tab lists the level rewards, the earned ones lit")
	_click(panel._change_profession.get_global_rect().get_center())
	_expect(manager.is_open("professions"), "Change profession opens the career map")
	manager.close("professions")
	worker.profession = "base:profession:worker"
	worker.profession_experience = {}
	explorer.clear_selection()


func _capture_inspector() -> void:
	await _new_trip(STONE, 1)
	_adopt_worker()
	for i in range(2):
		drops.restore_loose_item(STONE, Vector3(41.5 + i, 21, 40.5))
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "capture real three-stone carry")
	worker.sleep = .78
	worker.rotation.y = -.25
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("667877")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .7
	environment.environment = settings
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(90, 1, 90)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(40,20.5,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7c9782")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	root.size = Vector2i(1280,720)
	camera.position = worker.position + Vector3(10, 10, 15)
	camera.look_at(worker.position + Vector3(3, 1.2, 0))
	explorer.select_object(director, worker)
	explorer.open_character_sheet()
	explorer._window.position = Vector2(876,32)
	await _save_capture("dwarf_inspector_1280.png")
	root.size = Vector2i(960,540)
	await process_frame
	explorer._refresh_selected()
	await _save_capture("dwarf_inspector_960.png")
	explorer._dwarf_panel._show_tab(1)
	await _save_capture("dwarf_details_960.png")


func _save_capture(filename: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/dwarf_inspector_review/" + filename)
