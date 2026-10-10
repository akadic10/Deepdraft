extends "res://scripts/tests/DwarfRosterTest.gd"


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Profession UI test timed out"); quit(1))
	await _setup_fixture()
	root.size = Vector2i(1280, 720)
	var generator := root.get_node("WorldGenerator")
	generator._maps_ready = true
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	manager._layout.clear()
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	rig = load("res://scripts/systems/Camera.gd").new()
	rig.name = "Camera"
	scene.add_child(rig)
	rig.set_process(false)
	director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.name = "Dwarves"
	director.camera_path = NodePath("../Camera")
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	roster = director._roster_panel
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.dwarf_director_path = NodePath("../Dwarves")
	scene.add_child(explorer)
	_adopt_worker()
	for i in range(7): _add_dwarf(510 + i)
	_expect(await _until(worker.TaskPhase.HAUL_TO_ZONE), "real worker is carrying cargo before promotion")
	var carried = worker._carried_entries[0][0]
	manager.open("dwarves")
	director.inspect_dwarf(worker)
	await _settle()
	_click(roster._detail_panel._change_profession.get_global_rect().get_center())
	await _settle()
	var panel = director._profession_panel
	_expect(manager.is_open("professions") and panel._agent == worker, "inspector action opens the selected dwarf's promotion screen")
	_click(panel._nodes["base:profession:farmer"].button.get_global_rect().get_center())
	_expect(panel._promote.disabled and panel._status.text == "PLANNED PROFESSION", "planned career is inspectable and cannot promote")
	_expect("farming" in panel._requirements.text, "placeholder explains the missing gameplay")
	_click(panel._nodes["base:profession:miner"].button.get_global_rect().get_center())
	root.get_node("WorldClock").set_paused(true)
	_click(panel._promote.get_global_rect().get_center())
	_expect(worker.profession == "base:profession:miner", "player can promote while paused")
	_expect(worker.current_task_id < 0 and worker._carried_entries.is_empty() and is_instance_valid(carried), "promotion releases hauling and preserves the physical cargo")
	_expect(panel._promote.disabled and "now a Miner" in panel._feedback.text, "promotion updates the appointment card immediately")
	worker.profession_experience[worker.profession] = 100
	panel.refresh()
	_expect("level 3" in panel._experience.text, "appointment shows retained career experience")
	panel.select_profession("base:profession:stonemason")
	_expect(panel._promote.disabled and panel._role_name.text == "Stonemason", "Stonemason is an honest named placeholder")
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		panel.select_profession("base:profession:miner")
		panel._fit()
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		_expect(bounds.encloses(panel.window.get_global_rect()), "promotion window fits " + str(resolution))
		_expect(panel.window.get_global_rect().encloses(panel._promote.get_global_rect()), "promotion action remains visible " + str(resolution))
		_expect(panel._left_scroll.get_global_rect().encloses(panel._nodes["base:profession:miner"].button.get_global_rect()), "selected career stays visible " + str(resolution))
		_expect(panel.window.get_global_rect().end.y <= dock._dock_panel.position.y - 8, "promotion clears the dock " + str(resolution))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/profession_review/promotion_%d.png" % resolution.x)
	root.size = Vector2i(1280,720)
	panel.select_profession("base:profession:hunter")
	await _settle()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/profession_review/hunter.png")
	_click(dock._button_by_target.colony.get_global_rect().get_center())
	await _settle()
	_key(KEY_ESCAPE)
	_expect(manager.is_open("professions") and not dock.is_action_menu_open(), "Escape closes the menu above the profession window first")
	_key(KEY_ESCAPE)
	_expect(not manager.is_open("professions") and manager.is_open("dwarves"), "Escape returns to the existing roster")
	await _settle()
	_click(dock._button_by_target.colony.get_global_rect().get_center())
	await _settle()
	_click(_button_named(dock._panel_body, "Labor").get_global_rect().get_center())
	await _settle()
	_expect(roster._work_view and not manager.has_window("labor"), "Colony Labor opens real work controls, not a placeholder window")
	var check = roster._rows[worker].checks.mine
	_click(check.get_global_rect().get_center())
	_expect(worker.work_permissions.get("mine") == false, "Work checkbox changes the selected dwarf's actual permission")
	_expect(roster._rows[worker].checks.craft.disabled, "Miner crafting permission explains the Worker capability gate")
	_expect(not roster._rows[worker].button.get_global_rect().intersects(roster._detail_frame.get_global_rect()), "work controls remain in the roster")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/profession_review/work.png")
	director.open_professions(worker)
	panel.select_profession("base:profession:worker")
	panel._apply_promotion()
	panel.select_profession("base:profession:miner")
	_expect("Resume Miner" in panel._promote.text and "level 3" in panel._experience.text, "return path offers the retained level")
	_expect("switched off" in panel._requirements.text, "disabled mining is explained before promotion")
	director._agents.erase(worker)
	panel._process(1)
	_expect(not manager.is_open("professions"), "removed dwarf closes stale promotion window")
	if failures.is_empty(): print("DWARF_PROFESSION_UI_OK: entry, placeholders, paused promotion, safe cargo, retained levels, work controls, three resolutions, Escape and stale subject")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
