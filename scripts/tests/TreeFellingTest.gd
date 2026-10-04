extends "res://scripts/tests/ObjectExplorerTest.gd"

## Reuses the isolated flat world/picking helpers, then exercises actual scheduler
## assignment and DwarfAgent execution. No player saves or layout writes.
var tasks
var clock_node
var drops
var worker
var dock
var chop


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Tree felling test timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	clock_node = root.get_node("WorldClock")
	clock_node.set_process(false)
	clock_node.set_paused(false)
	clock_node.set_speed(1)
	tasks = root.get_node("TaskManager")
	tasks.set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/ui/UIWindowManager.gd").new()
	manager.name = "Windows"
	scene.add_child(manager)
	manager._layout_loaded = false
	drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "Flora"
	scene.add_child(flora)
	flora.set_process(false)
	dock = load("res://scripts/ui/DockUI.gd").new()
	dock.name = "Dock"
	dock.window_manager_path = NodePath("../Windows")
	scene.add_child(dock)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.name = "Explorer"
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	chop = load("res://scripts/systems/TreeFellingController.gd").new()
	chop.dock_ui_path = NodePath("../Dock")
	chop.flora_path = NodePath("../Flora")
	chop.explorer_path = NodePath("../Explorer")
	scene.add_child(chop)
	explorer._tools.append(chop)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	root.size = Vector2i(1280, 800)
	root.get_node("WorldGenerator")._maps_ready = true
	var oak_id := Vector2i(40,40)
	var oak := _spawn_tree("oak", "mature", oak_id)
	_aim_above(oak.position)
	await process_frame
	await process_frame
	# The pre-existing axe menu opens and activates the new tool.
	dock._dispatch("open_panel", "chop")
	_expect(dock._button_by_target["chop"].button_pressed, "axe highlights while Chop menu is open")
	var buttons: Array = dock._panel_body.get_children()
	_expect(buttons[0].text == "Chop Trees" and not buttons[0].disabled, "existing Chop Trees menu is enabled")
	_expect(buttons[1].disabled and buttons[2].disabled, "future forestry/stump actions are disabled")
	buttons[0].pressed.emit()
	_expect(chop.is_active() and not dock._panel_container.visible, "existing menu activates chop tool and closes")
	_expect(not dock._button_by_target["chop"].button_pressed, "axe clears its highlight when menu closes")
	dock._dispatch("open_panel", "chop")
	_expect(dock._button_by_target["chop"].button_pressed, "reopened Chop menu highlights axe")
	dock._dispatch("open_panel", "chop")
	_expect(not dock._button_by_target["chop"].button_pressed and chop.is_active(), "closing menu clears highlight without cancelling Chop mode")
	var screen := camera.unproject_position(oak.position + Vector3.UP)
	_click(screen)
	_expect(flora._tree_changes.has(oak_id), "normal viewport click designates tree")
	_expect(flora._felling_markers.has(oak_id), "designation has a visible marker")
	var source = flora._felling_sources.get(oak_id)
	if source == null:
		push_error("Cannot continue: click did not create a felling source")
		quit(1)
		return
	var original_lease: int = source.lease_id
	chop.designate_at_screen(screen)
	_expect(source.lease_id == original_lease and flora._felling_sources.size() == 1, "repeat designation is idempotent")
	await _test_rectangle_designation(oak_id)
	dock.tool_requested.emit("mine_precision")
	_expect(not chop.is_active(), "another tool deactivates chop")
	dock._dispatch_panel_action("chop", "Chop Trees")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_expect(not chop.is_active(), "Escape exits chop tool")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	worker = factory.spawn(factory.generate(101, {}), 101)
	scene.add_child(worker)
	worker.position = Vector3(34.5,21,40.5)
	worker.set_process(false)
	tasks.register_dwarf(worker)
	_expect(await _until_working(), "scheduler dispatches dwarf to tree perimeter")
	_expect(source.is_work_position(worker.current_cell()), "worker stands outside trunk footprint")
	_check_axe_grips()
	worker._process(1.0)
	var partial: float = source.state.work_seconds
	_expect(partial > 0 and partial < source.duration, "chopping accumulates source progress")
	clock_node.set_paused(true)
	var paused_pose: Transform3D = worker._hand_r.transform
	worker._process(4)
	_expect(is_equal_approx(source.state.work_seconds, partial), "paused chopping does not advance")
	_expect(worker._hand_r.transform.is_equal_approx(paused_pose), "pause freezes the axe and hands")
	clock_node.set_paused(false)
	var timer_before: float = worker._swing_timer
	clock_node.set_speed(2)
	worker._process(.05)
	_expect(is_equal_approx(worker._swing_timer,fposmod(timer_before-.1,worker._swing_time)), "axe animation follows simulation speed")
	clock_node.set_speed(1)
	partial = float(source.state.work_seconds)
	worker.dev_force_interrupt()
	_check_stowed_axe("interruption")
	_expect(source.reserved_by == -1 and source.lease_id == original_lease, "interrupt releases reservation and retains lease")
	_expect(is_equal_approx(source.state.work_seconds, partial), "interrupt preserves work")
	_expect(await _until_working(), "interrupted job resumes")
	worker.dev_make_tired()
	worker._process(.1)
	_expect(worker.is_sleeping() and source.reserved_by == -1, "sleep releases tree")
	_check_stowed_axe("sleep")
	_expect(is_equal_approx(source.state.work_seconds, partial), "sleep preserves work")
	worker._wake_up()
	_expect(await _until_working(), "job resumes after waking")
	explorer.select_object(flora, oak_id)
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1680, 1000)
		explorer._window.position = Vector2(24, 150)
		dock._dispatch_panel_action("chop", "Chop Trees")
		dock._open_action_panel("chop")
		await _capture(oak, "res://tmp/tree_felling_review/felling.png")
		dock._dispatch_panel_action("chop", "Cancel")
	explorer._perform_action("cancel_felling")
	_check_stowed_axe("cancel")
	_expect(worker.current_task_id == -1 and not flora._felling_sources.has(oak_id), "explorer cancellation stops assigned dwarf")
	_expect(not flora._tree_changes[oak_id].designated and is_equal_approx(flora._tree_changes[oak_id].work_seconds, partial), "cancel preserves partial work")
	# JSON round trip into a fresh owner: restore before a visual exists.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora._despawn_column(Vector2i(oak_id.x >> 4, oak_id.y >> 4))
	flora.free()
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "RestoredFlora"
	scene.add_child(flora)
	flora.set_process(false)
	flora.restore_state(saved)
	chop._flora = flora
	# JSON numbers parse as floats; normalize both snapshots before comparing.
	_expect(JSON.parse_string(JSON.stringify(flora.serialize_state())) == saved, "cancelled progress round trips before visual spawning")
	_spawn_tree("oak", "mature", oak_id)
	flora.designate_felling(oak_id)
	_expect(await _until_working(), "restored partial tree can be re-designated")
	source = flora._felling_sources[oak_id]
	# Season swap during work: no lost progress, reservation or lease.
	flora._ready_to_spawn = true
	flora._on_season_changed("winter")
	_expect(root.get_node("PlacedEntityRegistry").occupies(Vector3i(40,21,40)), "season rebuild preserves trunk navigation occupancy")
	_expect(source.reserved_by == worker.dwarf_id and is_equal_approx(source.state.work_seconds, partial), "season swap preserves live job")
	_spawn_tree("oak", "mature", oak_id)
	_expect(await _until_felled(oak_id), "dwarf completes felling")
	_check_stowed_axe("completion")
	_expect(flora._trees[oak_id].node == null and flora.get_explorer_data(oak_id).is_empty(), "felled tree disappears and cannot be inspected")
	_expect(not flora._felling_markers.has(oak_id), "felling removes the axe marker")
	_expect(not root.get_node("PlacedEntityRegistry").occupies(Vector3i(40,21,40)), "felling removes trunk occupancy")
	_expect(_item_count("base:resources:wood:oak_log") == 4, "mature oak drops four raw logs")
	_expect(not drops._missing_models.has("res://assets/models/items/wood/oak_log.glb"), "oak drops use the real timber model")
	_expect(_item_count("base:resources:wood:oak_stave") == 0, "felling never creates crafted staves")
	var drop_count: int = drops.get_stats().loose
	_expect(not source.advance_work(worker.dwarf_id, 100), "completion cannot run twice")
	_expect(drops.get_stats().loose == drop_count, "duplicate completion produces no drops")
	_expect(_spawn_tree("oak", "mature", oak_id) == null, "seasonal/streaming instancing rejects a felled tree")
	saved = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora.restore_state(saved)
	_expect(_spawn_tree("oak", "mature", oak_id) == null and drops.get_stats().loose == drop_count, "restoring tombstone does not respawn tree or replay drops")
	# Active designation and partial work reconstruct one unreserved job on load.
	var pine_id := Vector2i(64,40)
	_spawn_tree("pine", "mature", pine_id)
	flora.designate_felling(pine_id)
	_expect(await _until_working(), "second job starts")
	worker._process(.5)
	var pine_work: float = flora._tree_changes[pine_id].work_seconds
	saved = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	flora.restore_state(saved)
	_expect(flora._felling_sources[pine_id].reserved_by == -1 and is_equal_approx(flora._tree_changes[pine_id].work_seconds, pine_work), "load rebuilds lease without stale dwarf reservation")
	_expect(await _until_felled(pine_id), "restored pending work completes")
	# Saplings can be cleared without gaining a timber yield.
	var sapling_id := Vector2i(68,44)
	_spawn_tree("pine", "sapling", sapling_id)
	flora.designate_felling(sapling_id)
	drop_count = drops.get_stats().loose
	_expect(await _until_felled(sapling_id), "sapling clearing completes")
	_expect(drops.get_stats().loose == drop_count, "saplings yield no timber")
	# Tree yields enter the existing haul pipeline and its Wood filter unchanged.
	var storage = root.get_node("StockpileManager")
	storage.set_process(false)
	storage._process(.3)
	var zone = load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i] = []
	for x in range(52,56):
		for z in range(35,39):
			cells.append(Vector3i(x,20,z))
	zone.setup(501, cells)
	zone.filter_tags.assign(["stockpile_wood"])
	storage.register_zone(zone)
	for item in ["oak_log", "pine_log", "apple_wood", "juniper_log"]:
		var definition: Dictionary = drops.get_item_def("base:resources:wood:%s" % item)
		_expect(zone.accepts(definition.get("material_tags", [])), "%s matches the Wood stockpile filter" % item)
	for i in range(2400):
		storage._process(.3)
		tasks._run_scheduler()
		worker._process(.1)
		if storage.get_total("base:resources:wood:oak_log") == 4:
			break
		if i % 30 == 0:
			await process_frame
	_expect(storage.get_total("base:resources:wood:oak_log") == 4 and _item_count("base:resources:wood:oak_log") == 0, "felled oak logs are hauled into the wood stockpile")
	worker.dev_force_interrupt()
	storage.deregister_zone(zone)
	# Fully blocked work backs off and remains designated.
	var blocked_id := Vector2i(80,80)
	_spawn_tree("juniper", "mature", blocked_id)
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		for y in range(21,26):
			world.set_block(80 + offset.x, y, 80 + offset.y, stone)
	await process_frame
	flora.designate_felling(blocked_id)
	tasks._run_scheduler()
	var blocked_task = tasks.get_task(flora._felling_sources[blocked_id].lease_id)
	_expect(blocked_task.retry_at > Time.get_ticks_msec() and flora._tree_changes[blocked_id].designated, "unreachable tree backs off without losing designation")
	flora.cancel_felling(blocked_id)
	# Old saves with no forestry changes remain valid.
	flora.restore_state({})
	_expect(flora.serialize_state().trees.is_empty(), "empty legacy forestry state accepted")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TREE_FELLING_OK: click/rectangle input, axe markers, worker execution, cancel/sleep/resume, pause, season, JSON restore, timber drops/hauling, occupancy, saplings, unreachable retries")
	quit(0 if failures.is_empty() else 1)


func _test_rectangle_designation(oak_id: Vector2i) -> void:
	var sapling_id := Vector2i(48,42)
	var juniper_id := Vector2i(48,49)
	var outside_id := Vector2i(70,70)
	_spawn_tree("pine", "sapling", sapling_id)
	_spawn_tree("juniper", "mature", juniper_id)
	_spawn_tree("pine", "sapling", outside_id)
	explorer.clear_selection()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 65
	_aim_above(Vector3(45,21,45))
	await process_frame
	var a := camera.unproject_position(Vector3(38.2,21,38.2))
	var b := camera.unproject_position(Vector3(53.8,21,53.8))
	_mouse_button(a, true)
	_mouse_motion(b)
	_expect(chop._box_select and chop._preview_trees.size() == 3, "ground rectangle previews its three trees")
	_expect(not flora._tree_changes.has(sapling_id), "drag preview does not designate before release")
	# A camera pan must move the canvas projection on the very next frame,
	# even when the slower candidate-count timer has not fired yet.
	var polygon: PackedVector2Array = chop._selection._polygon.duplicate()
	chop._hover_elapsed = 0.0
	camera.position.x += .1
	chop._process(1.0 / 60.0)
	var corner := Vector3(chop._selection_rect.position.x, chop._anchor.y + 1.02, chop._selection_rect.position.y)
	_expect(chop._selection._polygon != polygon and chop._selection._polygon[0].is_equal_approx(camera.unproject_position(corner)), "marquee follows camera on the next frame before count timer")
	camera.position.x -= .1
	chop._process(1.0 / 60.0)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture_designation("rectangle")
	_mouse_button(b, false)
	_expect(flora._felling_sources.size() == 3 and not flora._tree_changes.has(outside_id), "release marks only trees in rectangle")
	var sapling_lease: int = flora._felling_sources[sapling_id].lease_id
	# Reverse drags select the same region and never duplicate leases.
	_mouse_button(b, true)
	_mouse_motion(a)
	_mouse_button(a, false)
	_expect(flora._felling_sources.size() == 3 and flora._felling_sources[sapling_id].lease_id == sapling_lease, "reverse rectangle is idempotent")
	flora._update_felling_marker_positions()
	var marker: Label = flora._felling_markers[sapling_id]
	_expect(marker.text == "🪓" and marker.visible and marker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "marked tree has a non-interactive axe emoji")
	var before := marker.position
	camera.position.x += 5
	flora._update_felling_marker_positions()
	_expect(marker.position != before, "axe follows camera movement")
	flora._on_slice_changed(19)
	_expect(not marker.visible, "slice-hidden tree hides its axe")
	_expect(flora.trees_in_felling_rect(Rect2i(38,38,16,16)).is_empty(), "rectangle excludes slice-hidden trees")
	flora._on_slice_changed(127)
	chop.deactivate()
	flora._update_felling_marker_positions()
	_expect(marker.visible, "axe remains after leaving Chop mode")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture_designation("axes")
	dock._dispatch_panel_action("chop", "Chop Trees")
	# Escape discards an unfinished rectangle without marking the outside tree.
	_mouse_button(a, true)
	_mouse_motion(camera.unproject_position(Vector3(75,21,75)))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_mouse_button(b, false)
	_expect(not chop._dragging and not flora._tree_changes.has(outside_id), "Escape cancels rectangle")
	# Switching tools / losing window focus cancels a gesture too.
	dock._dispatch_panel_action("chop", "Chop Trees")
	_mouse_button(a, true)
	_mouse_motion(b)
	dock.tool_requested.emit("mine_precision")
	_expect(not chop._dragging, "tool switch discards rectangle")
	dock._dispatch_panel_action("chop", "Chop Trees")
	_mouse_button(a, true)
	chop._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(not chop._dragging, "focus loss discards rectangle")
	flora.cancel_felling(sapling_id)
	flora.cancel_felling(juniper_id)
	_expect(not flora._felling_markers.has(sapling_id), "cancelling removes the axe")
	# A UI press must not begin a world drag; a world drag released over UI
	# must cancel instead of getting stuck or committing through that window.
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 30
	scene.add_child(ui_layer)
	var blocker := Panel.new()
	blocker.position = b - Vector2(20,20)
	blocker.size = Vector2(40,40)
	ui_layer.add_child(blocker)
	await process_frame
	_mouse_motion(b)
	_mouse_button(b, true)
	_expect(not chop._dragging, "pressing UI never starts rectangle")
	_mouse_button(b, false)
	_mouse_motion(a)
	_mouse_button(a, true)
	_mouse_motion(b)
	await process_frame
	_mouse_button(b, false)
	_expect(not chop._dragging and not flora._tree_changes[sapling_id].designated, "release over UI cancels rectangle")
	ui_layer.free()
	for id in [sapling_id, juniper_id, outside_id]:
		flora._remove_tree_visual(id)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_aim_above(flora._trees[oak_id].node.position)
	await process_frame


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	root.push_input(event, true)


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	root.push_input(event, true)


func _capture_designation(label: String) -> void:
	if scene.get_node_or_null("DesignationEnvironment") == null:
		var environment := WorldEnvironment.new()
		environment.name = "DesignationEnvironment"
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(.12,.16,.19)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = .7
		environment.environment = env
		scene.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55,-30,0)
		scene.add_child(sun)
	flora._update_felling_marker_positions()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/tree_felling_review")
	root.get_texture().get_image().save_png("res://tmp/tree_felling_review/%s.png" % label)


func _spawn_tree(species_name: String, stage_name: String, id: Vector2i) -> Node3D:
	var species: Dictionary = flora._species_for_key("base:flora:%s_tree" % species_name)
	var stage: Dictionary = species.stages[stage_name]
	var cell := Vector3i(id.x,20,id.y)
	var path: String = flora.resolve_tree_model_for_season(stage, flora._season, cell)
	var node: Node3D = flora._instance_tree(species_name, path, stage_name, stage,
		id.x, id.y, 20, flora._footprint_for(species.placement, stage_name))
	if node != null:
		var column := Vector2i(id.x >> 4, id.y >> 4)
		if not flora._loaded_columns.has(column):
			flora._loaded_columns[column] = []
		flora._loaded_columns[column].append(node)
	return node


func _until_working() -> bool:
	for i in range(1500):
		tasks._run_scheduler()
		worker._process(.1)
		if worker._task_phase == worker.TaskPhase.FELL_WORKING:
			return true
		if i % 30 == 0:
			await process_frame
	return false


func _check_axe_grips() -> void:
	var pose: RefCounted = worker._felling_pose
	var axe: Node3D = pose.axe
	_expect(is_instance_valid(axe) and axe.visible and axe.get_parent() == worker._hand_r, "felling equips an axe on the right hand")
	var previous := Vector3.ZERO
	for phase in [0.0,.2,.36,.48,.56,.8]:
		pose.apply(phase,worker._fell_contact)
		var right: Vector3 = worker._hand_r.global_transform * pose.PALM
		var left: Vector3 = worker._hand_l.global_transform * pose.PALM
		_expect(right.distance_to(axe.global_position) < .001, "lower grip stays on the axe shaft")
		_expect(left.distance_to(axe.global_transform * pose.SUPPORT_GRIP) < .001, "supporting hand stays on the axe shaft")
		if phase == .56:
			var edge: Vector3 = axe.global_transform * pose.CUTTING_EDGE
			_expect(edge.distance_to(worker.to_global(worker._fell_contact)) < .001, "strike lands on the aimed trunk surface")
		if phase > 0:
			_expect(axe.global_position.distance_to(previous) > .001, "wind-up strike and recovery move the tool")
		previous = axe.global_position
	pose.apply(0.0,worker._fell_contact)
	worker.apply_slice(19)
	_expect(not axe.is_visible_in_tree(), "slice hides axe with the dwarf")
	worker.apply_slice(127)
	_expect(axe.is_visible_in_tree(), "revealing dwarf restores visible axe")
	_expect(worker._hand_r.basis.determinant() < 0, "animation preserves right-hand mirroring")


func _check_stowed_axe(reason: String) -> void:
	_expect(not worker._felling_pose.axe.visible, "%s stows axe" % reason)
	_expect(worker._hand_r.scale.is_equal_approx(Vector3(-1,1,1)) and worker._foot_r.scale.is_equal_approx(Vector3(-1,1,1)), "%s preserves mirrored hands and boots" % reason)
	for part in [worker._body,worker._head,worker._hand_l,worker._hand_r,worker._foot_l,worker._foot_r]:
		_expect(part.position.is_zero_approx() and part.rotation.is_zero_approx(), "%s restores normal part offsets" % reason)


func _until_felled(id: Vector2i) -> bool:
	for i in range(1800):
		tasks._run_scheduler()
		worker._process(.1)
		if bool(flora._tree_changes.get(id, {}).get("felled", false)):
			return true
		if i % 30 == 0:
			await process_frame
	return false


func _item_count(key: String) -> int:
	var count := 0
	for item_key: String in drops._loose.values():
		if item_key == key:
			count += 1
	return count
