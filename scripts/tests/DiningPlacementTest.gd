extends "res://scripts/tests/ObjectExplorerTest.gd"

const CHAIR := "base:furniture:wooden_chair"
const TABLE := "base:furniture:communal_table"
const PERSONAL := "base:furniture:wooden_table"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Dining placement timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.get_node("RoomManager").set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	_build_floor()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._process(0)
	root.get_node("WorldGenerator")._maps_ready = true
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	root.size = Vector2i(1280, 800)
	var nav = root.get_node("NavGrid")
	var registry = root.get_node("PlacedEntityRegistry")
	var def: Dictionary = furniture.get_defs()[CHAIR]
	var table_def: Dictionary = furniture.get_defs()[TABLE]
	_expect(table_def.footprint == {"width":8.0,"depth":4.0}, "communal table is 8x4")
	_expect(items.get_item_def(table_def.item_key).carry_cost == 4, "communal crate costs one full carry load")
	var dock = load("res://scripts/ui/DockUI.gd").new()
	_expect(dock.FURNITURE_PANEL_ITEMS["📥 Communal Dining Table"] == TABLE, "new table in Build menu")
	dock.free()
	_check_personal_capacity()

	# Rotated tables must have eight independent, inward-facing and buildable seats.
	for yaw in range(4):
		var origin := Vector3i(24+yaw*22, 20, 24)
		var table_id: int = furniture._next_installed_id
		furniture._install(TABLE, table_def, origin, yaw)
		var table = furniture._installed[table_id]
		var slots: Array[Dictionary] = furniture._seating.slots_for(table)
		_expect(slots.size() == 8, "eight seats at rotation %d" % yaw)
		_expect(furniture._installed.size() == yaw*9+1, "table never auto-spawns chairs")
		var seen := {}
		for slot in slots:
			_expect(not seen.has(slot.origin), "unique seat origin")
			seen[slot.origin] = true
			var toward: Vector3 = table.node.position-furniture._world_pos(def, slot.origin, slot.yaw)
			var forward := Basis(Vector3.UP, slot.yaw*PI*.5)*Vector3.BACK
			_expect(forward.dot(toward.normalized()) > .5, "chair faces table")
			furniture._active_key = CHAIR
			furniture._yaw = slot.yaw
			var valid: bool = furniture._placement_valid(slot.origin)
			_expect(valid, "seat %s yaw %d valid: %s" % [slot.id,yaw,furniture._invalid_reason])
			furniture._seating.resolve(slot.origin)
			_expect(not furniture._seating.snap.is_empty() and furniture._seating.snap.origin == slot.origin, "snaps to correct slot")
			_expect(furniture._seating.snap.get("yaw",-1) == slot.yaw, "snap chooses inward rotation")
			furniture._hover_cell = slot.origin
			var ghost_id: int = furniture._next_ghost_id
			furniture._confirm_ghost()
			_expect(nav.is_walkable(slot.origin), "planned chairs remain non-solid")
			_expect(not furniture._placement_valid(slot.origin), "planned chair reserves slot")
			furniture.dev_instant_build(ghost_id)
			_expect(not nav.is_walkable(slot.origin), "built chair reserves four floor cells")
		_expect(furniture.get_dining_seats(table_id).size() == 8, "all eight installed seats associated")
		_expect(table.cells.size() == 32, "table has correct rotated logical footprint")
		_expect(table.node.scale == Vector3.ONE, "baked model scale stays one")
	# Derived associations survive round trips without extra persistent seat IDs.
	var saved: Dictionary = furniture.serialize_state()
	_clear_furniture()
	furniture.restore_state(saved)
	_expect(furniture.serialize_state() == saved, "rotated furniture state round-trips exactly")
	for id: int in furniture._installed:
		if furniture._installed[id].furniture_key == TABLE:
			_expect(furniture.get_dining_seats(id).size() == 8, "seat associations survive restore")
	# Removing a table leaves all its independent chairs.
	var table_id: int = furniture._installed.keys()[0]
	var chair_ids: Array[int] = []
	for slot in furniture.get_dining_seats(table_id):
		chair_ids.append(slot.chair_id)
	furniture.dev_remove_installed(table_id)
	for id in chair_ids:
		_expect(furniture._installed.has(id), "removing table leaves chair")
	_clear_furniture()

	# Old saves stay 1x1 and keep the original art, including unfinished ghosts.
	var legacy := {"key":CHAIR, "origin":[25,20,60], "yaw":1, "id":200}
	furniture.restore_state({"installed":[legacy]})
	var old = furniture._installed[200]
	_expect(old.cells.size() == 1 and old.def.model.ends_with("wooden_chair_legacy.glb"), "unversioned chair preserves original model and footprint")
	_expect(furniture._visual_bounds(old.def,old.origin_cell,old.yaw_steps).size.is_equal_approx(Vector3(1,2,1)), "legacy art uses its saved layout")
	_expect(not furniture._seating.is_chair(old.def), "legacy chair does not claim a new wide seat")
	var versioned: Dictionary = furniture.serialize_state()
	_expect(versioned.installed[0].layout_version == 1, "legacy version persists on next save")
	_clear_furniture()
	furniture.restore_state(versioned)
	_expect(furniture.serialize_state() == versioned, "legacy layout survives repeated saves")
	_clear_furniture()
	furniture.restore_state({"ghosts":[legacy]})
	_expect(furniture._ghosts[200].footprint_cells().size() == 1, "old ghost stays narrow")
	furniture.dev_instant_build(200)
	_expect(furniture._installed.values()[0].cells.size() == 1, "building old ghost preserves layout")
	_clear_furniture()
	var current_plan := legacy.duplicate(true)
	current_plan["layout_version"] = 2
	furniture.restore_state({"ghosts":[current_plan]})
	_expect(furniture._ghosts[200].footprint_cells().size() == 4, "versioned wide chair plan retains four cells")
	var plan_save: Dictionary = furniture.serialize_state()
	_clear_furniture()
	furniture.restore_state(plan_save)
	_expect(furniture.serialize_state() == plan_save, "wide chair ghost round-trips exactly")
	_clear_furniture()

	# Head-space checks include terrain and external occupancy beyond chair tiles.
	var origin := Vector3i(40,20,60)
	furniture._active_key = CHAIR
	furniture._yaw = 0
	_expect(furniture._placement_valid(origin), "standalone chair allowed")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var obstruction := origin+Vector3i(-1,3,0)
	world.set_block(obstruction.x,obstruction.y,obstruction.z,stone)
	_expect(not furniture._placement_valid(origin) and furniture._invalid_reason == "seat_clearance", "head overhang cannot intersect rock outside footprint")
	world.set_block(obstruction.x,obstruction.y,obstruction.z,blocks.AIR_ID)
	var external_id: int = registry.register_box(obstruction,Vector3i.ONE)
	_expect(not furniture._placement_valid(origin), "head cannot intersect external entity")
	registry.unregister(external_id)
	# Only low obstructions: head clearance remains free, but every access is blocked.
	var access: Array[Vector3i] = furniture._seating.access_cells(def,origin,0)
	for cell in access:
		world.set_block(cell.x,cell.y+1,cell.z,stone)
	_expect(not furniture._placement_valid(origin) and furniture._invalid_reason == "seat_access", "chair needs a reachable side or back tile")
	for cell in access:
		world.set_block(cell.x,cell.y+1,cell.z,blocks.AIR_ID)
	furniture._install(CHAIR,def,origin,0)
	_expect(not furniture._placement_valid(origin+Vector3i(2,0,0)) and furniture._invalid_reason == "seat_clearance", "adjacent seated heads cannot overlap")
	_expect(furniture._placement_valid(origin+Vector3i(3,0,0)), "three-block seat spacing has head room")
	furniture._active_key = PERSONAL
	_expect(not furniture._placement_valid(origin+Vector3i(2,0,0)), "new furniture respects existing chair head space")
	_clear_furniture()

	# Ghost tables advertise slots; blocked positions stay red instead of silently
	# falling back to standalone placement. A missing table leaves its chairs intact.
	furniture._active_key = TABLE
	furniture._hover_cell = Vector3i(40,20,60)
	furniture._yaw = 0
	var ghost_id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	var table_ghost = furniture._ghosts[ghost_id]
	var slot: Dictionary = furniture._seating.slots_for(table_ghost)[0]
	furniture._active_key = CHAIR
	furniture._seating.resolve(slot.origin)
	_expect(furniture._seating.guides.size() == 8, "ghost table shows eight guides")
	var blocked_slot: Dictionary = furniture._seating.slots_for(table_ghost)[1]
	var barrel_id: int = furniture._next_installed_id
	var barrel_key := "base:furniture:barrel"
	furniture._install(barrel_key,furniture._defs[barrel_key],blocked_slot.origin,0)
	furniture._seating.resolve(slot.origin)
	var red_guides := 0
	for guide: Node3D in furniture._seating.guides:
		var meshes: Array = guide.find_children("*","MeshInstance3D",true,false)
		var color: Color = meshes[0].material_override.albedo_color
		if color.r > color.g:
			red_guides += 1
	_expect(furniture._seating.guides.size() == 8 and red_guides == 1, "occupied by other furniture displays a red guide")
	furniture.dev_remove_installed(barrel_id)
	var obstruction2: Vector3i = slot.origin+Vector3i(-1,3,0)
	world.set_block(obstruction2.x,obstruction2.y,obstruction2.z,stone)
	furniture._seating.resolve(slot.origin)
	_expect(furniture._seating.snap.origin == slot.origin, "blocked seat remains snapped")
	furniture._yaw = slot.yaw
	_expect(not furniture._placement_valid(slot.origin), "blocked guide rejects confirmation")
	world.set_block(obstruction2.x,obstruction2.y,obstruction2.z,blocks.AIR_ID)
	furniture._seating.resolve(Vector3i(90,20,90))
	_expect(furniture._seating.snap.is_empty() and furniture._seating.guides.is_empty(), "far from tables is standalone placement")
	furniture.cancel_ghost(ghost_id)
	_expect(furniture._ghosts.is_empty(), "cancel removes planned table")

	# A real input path (ray, hover, rotate, click) places only one independent chair.
	furniture._install(TABLE,table_def,Vector3i(40,20,60),0)
	var live_table_id: int = furniture._installed.keys()[0]
	var live_table = furniture._installed[live_table_id]
	slot = furniture._seating.slots_for(live_table)[0]
	_aim_above(live_table.node.position)
	furniture.activate_for(CHAIR)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(furniture._world_pos(def,slot.origin,slot.yaw))
	root.push_input(motion,true)
	furniture._update_hover(true, motion.position)
	_expect(furniture._hover_cell == slot.origin and furniture._hover_valid, "screen hover snaps to valid chair slot")
	var rotate := InputEventKey.new()
	rotate.pressed = true
	rotate.keycode = KEY_R
	furniture._unhandled_input(rotate)
	furniture._update_hover(true, motion.position) # Headless display has no physical mouse.
	_expect(furniture._yaw == slot.yaw, "R preserves inward-facing snap")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = motion.position
	furniture._unhandled_input(click)
	_expect(furniture._ghosts.size() == 1, "one click queues one chair")
	if furniture._ghosts.size() == 1:
		var built = furniture._ghosts.values()[0]
		_expect(built.origin_cell == slot.origin and built.yaw_steps == slot.yaw, "click uses snapped origin and facing")
		# Obstruction appearing while a builder walks must prevent consuming the item.
		world.set_block(obstruction2.x,obstruction2.y,obstruction2.z,stone)
		_expect(not furniture._can_build_ghost(built), "build rechecks new head obstruction")
		world.set_block(obstruction2.x,obstruction2.y,obstruction2.z,blocks.AIR_ID)
		_expect(furniture._can_build_ghost(built), "build ignores its own ghost reservation")
		furniture.dev_instant_build(built.ghost_id)
		_expect(furniture.get_dining_seats(live_table_id).size() == 1, "clicked chair links to table")
	furniture._on_slice_changed(19)
	_expect(furniture._seating.guides.is_empty(), "slice hides guides of hidden table")
	furniture._on_slice_changed(127)
	furniture.deactivate()
	_expect(furniture._seating.guides.is_empty(), "cancel tool removes guides")
	var personal_id: int = furniture._next_installed_id
	furniture._install(PERSONAL,furniture._defs[PERSONAL],Vector3i(55,20,60),1)
	var personal_slots: Array[Dictionary] = furniture._seating.slots_for(furniture._installed[personal_id])
	_expect(personal_slots.size() == 4, "personal table offers four alternative chair positions")
	# New communal item uses the same real animated fetch/build/refund pipeline.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var dwarf = factory.spawn(factory.generate(100, {}), 100)
	scene.add_child(dwarf)
	dwarf.set_process(false)
	dwarf.position = Vector3(69.5,21,60.5)
	furniture._active_key = TABLE
	furniture._hover_cell = Vector3i(70,20,60)
	furniture._yaw = 1
	var fetch_id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	var fetch = furniture._ghosts[fetch_id]
	items.spawn_drop(table_def.item_key,1,Vector3i(68,21,60))
	fetch._ensure_claim()
	var pull: Dictionary = fetch.reserve_fetch(100,Vector3i(69,20,60))
	_expect(not pull.is_empty() and pull.heavy, "new communal crate has a heavy fetch lease")
	if not pull.is_empty():
		dwarf._fetch_source_id = fetch.source_id
		dwarf._fetch_item = pull.item
		dwarf._fetch_heavy = pull.heavy
		dwarf._fetch_pickup()
		_expect(not dwarf._fetch_picked_up, "communal pickup waits for hand contact")
		dwarf._process_item_handling(dwarf._handling_duration*.5)
		_expect(dwarf._fetch_picked_up, "communal crate transfers at hand contact")
		var build_id: int = furniture._next_installed_id
		dwarf._begin_fetch_deposit()
		dwarf._process_item_handling(dwarf._handling_duration)
		_expect(furniture._installed.has(build_id) and not furniture._ghosts.has(fetch_id), "dwarf completes communal table")
		_expect(dwarf._carried_entries.is_empty(), "build consumes communal crate")
		furniture.dev_remove_installed(build_id)
		_expect(items.nearest_loose_of_key(table_def.item_key,Vector3i(70,20,60)) != null, "uninstall refunds communal crate")
	dwarf.queue_free()
	if "--capture" in OS.get_cmdline_user_args():
		items.visible = false
		var personal_slot: Dictionary = personal_slots[0]
		furniture._install(CHAIR,def,personal_slot.origin,personal_slot.yaw)
		await _capture_dining(live_table)
	print("DINING_PLACEMENT_%s: 4 rotations, 32 communal seats, 4 personal sides/one-chair cap, snap/input, clearance/access, old/new saves, independent removal" % ("OK" if failures.is_empty() else "FAILED"))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_personal_capacity() -> void:
	var def: Dictionary = furniture._defs[PERSONAL]
	var chair_def: Dictionary = furniture._defs[CHAIR]
	_expect(def.seating.max_chairs == 1, "personal chair capacity is authored in JSON")
	for yaw in range(4):
		var origin := Vector3i(24+yaw*20,20,88)
		var table_id: int = furniture._next_installed_id
		furniture._install(PERSONAL,def,origin,yaw)
		var table = furniture._installed[table_id]
		var slots: Array[Dictionary] = furniture._seating.slots_for(table)
		_expect(slots.size() == 4, "personal table has four sides at every rotation")
		for choice in slots:
			furniture._active_key = CHAIR
			for slot in slots:
				furniture._yaw = slot.yaw
				_expect(furniture._placement_valid(slot.origin), "every empty personal side is buildable")
				var direction := Basis(Vector3.UP, slot.yaw*PI*.5)*Vector3.BACK
				var toward: Vector3 = table.node.position-furniture._world_pos(chair_def,slot.origin,slot.yaw)
				_expect(direction.dot(toward.normalized()) > .99, "each personal side faces directly inward")
			furniture._seating.resolve(choice.origin)
			_expect(furniture._seating.snap.get("origin") == choice.origin, "personal snapping chooses hovered side")
			_expect(furniture._seating.guides.size() == 4, "empty personal table advertises four choices")
			furniture._hover_cell = choice.origin
			furniture._yaw = choice.yaw
			var ghost_id: int = furniture._next_ghost_id
			furniture._confirm_ghost()
			_expect(furniture._can_build_ghost(furniture._ghosts[ghost_id]), "chair plan excludes itself from capacity")
			_assert_personal_full(slots,choice)
			# Cancelling the plan makes every side available again.
			furniture.cancel_ghost(ghost_id)
			furniture._seating.resolve(choice.origin)
			_expect(furniture._seating.guides.size() == 4, "cancellation restores all four choices")
			furniture._hover_cell = choice.origin
			furniture._yaw = choice.yaw
			ghost_id = furniture._next_ghost_id
			furniture._confirm_ghost()
			# Persistence keeps the pending chair reservation, without another saved ID.
			var saved: Dictionary = furniture.serialize_state()
			_clear_furniture()
			furniture.restore_state(saved)
			table = furniture._installed[table_id]
			_expect(furniture.serialize_state() == saved, "personal chair plan and table survive restore")
			_assert_personal_full(slots,choice)
			var chair_id: int = furniture._next_installed_id
			furniture.dev_instant_build(ghost_id)
			_expect(furniture._installed.has(chair_id), "selected personal side builds successfully")
			_expect(furniture.get_dining_seats(table_id).size() == 1, "exactly one personal dining chair associated")
			_assert_personal_full(slots,choice)
			# An uninstall request still occupies the seat until the item is removed.
			furniture._installed[chair_id].set_uninstall(true)
			_assert_personal_full(slots,choice)
			saved = furniture.serialize_state()
			_clear_furniture()
			furniture.restore_state(saved)
			table = furniture._installed[table_id]
			_expect(furniture.serialize_state() == saved, "installed personal chair and uninstall flag survive restore")
			_assert_personal_full(slots,choice)
			furniture.dev_remove_installed(chair_id)
			furniture._seating.resolve(choice.origin)
			_expect(furniture._seating.guides.size() == 4, "removal reopens every personal side")
		_clear_furniture()
	# Ghost tables use the same capacity, and one reserved chair must not stop
	# the table from being built before its chair.
	var origin := Vector3i(40,20,108)
	furniture._active_key = PERSONAL
	furniture._hover_cell = origin
	furniture._yaw = 0
	var table_ghost_id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	var slots: Array[Dictionary] = furniture._seating.slots_for(furniture._ghosts[table_ghost_id])
	var choice: Dictionary = slots[2]
	furniture._active_key = CHAIR
	furniture._hover_cell = choice.origin
	furniture._yaw = choice.yaw
	var chair_ghost_id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	_assert_personal_full(slots,choice)
	_expect(furniture._can_build_ghost(furniture._ghosts[table_ghost_id]), "one planned chair permits building its table")
	furniture.dev_instant_build(table_ghost_id)
	furniture.dev_instant_build(chair_ghost_id)
	_expect(furniture._installed.size() == 2 and furniture._ghosts.is_empty(), "planned personal table and chair both build")
	furniture._active_key = CHAIR
	furniture._yaw = 0
	_expect(furniture._placement_valid(Vector3i(70,20,108)), "full personal table does not limit unrelated standalone chairs")
	_clear_furniture()
	# Place chairs first: a new personal table may not attach two opposing chairs.
	slots = furniture._seating.slots_for_layout(def,origin,0)
	for slot in [slots[0],slots[1]]:
		furniture._install(CHAIR,chair_def,slot.origin,slot.yaw)
	furniture._active_key = PERSONAL
	furniture._yaw = 0
	_expect(not furniture._placement_valid(origin) and furniture._invalid_reason == "seat_capacity", "table cannot bypass capacity by being placed after two chairs")
	furniture.dev_remove_installed(furniture._installed.keys()[0])
	_expect(furniture._placement_valid(origin), "table may be placed beside one preexisting chair")
	_clear_furniture()
	# Preserve preexisting pieces on restore. Previously independent plans get a
	# stable order, so an older over-capacity save cannot deadlock both builders.
	furniture._install(PERSONAL,def,origin,0)
	var old_plan_ids: Array[int] = []
	for slot in [slots[0],slots[1]]:
		furniture._active_key = CHAIR
		furniture._hover_cell = slot.origin
		furniture._yaw = slot.yaw
		old_plan_ids.append(furniture._next_ghost_id)
		furniture._confirm_ghost() # Restore, unlike new placement, preserves old plans.
	_expect(furniture._can_build_ghost(furniture._ghosts[old_plan_ids[0]]), "first old chair plan can complete")
	_expect(not furniture._can_build_ghost(furniture._ghosts[old_plan_ids[1]]), "excess old chair plan waits for capacity")
	furniture.dev_instant_build(old_plan_ids[0])
	_expect(not furniture._can_build_ghost(furniture._ghosts[old_plan_ids[1]]), "installed first chair still reserves capacity")
	_clear_furniture()
	furniture._seating.reset()


func _assert_personal_full(slots: Array[Dictionary], chosen: Dictionary) -> void:
	furniture._active_key = CHAIR
	for slot in slots:
		if slot.id == chosen.id:
			continue
		furniture._yaw = slot.yaw
		_expect(not furniture._placement_valid(slot.origin) and furniture._invalid_reason == "seat_capacity", "second personal chair blocked by table capacity")
		furniture._seating.resolve(slot.origin)
		_expect(furniture._seating.snap.get("origin") == slot.origin, "full side stays snapped so it cannot bypass the cap")
		_expect(furniture._seating.guides.is_empty(), "full personal table hides unused guides")
		furniture._update_hint(slot.origin)
		_expect("chair limit" in furniture._hint_label.text, "full personal table explains why another chair is blocked")


func _clear_furniture() -> void:
	furniture.deactivate()
	for id in furniture._ghosts.keys():
		furniture.cancel_ghost(id)
	for id in furniture._installed.keys():
		furniture.dev_remove_installed(id)


func _capture_dining(table) -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100,100)
	floor_mesh.mesh = plane
	floor_mesh.position = table.node.position+Vector3(4,-.015,0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.29,.38,.35)
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.08,.11,.13)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var center: Vector3 = table.node.position+Vector3(2,0,0)
	camera.size = 23
	camera.position = center+Vector3(10,19,17)
	camera.look_at(center)
	furniture._active = true
	furniture._active_key = CHAIR
	furniture._ensure_preview()
	furniture._seating.resolve(table.origin_cell+Vector3i(3,0,-2))
	furniture._hover_cell = furniture._seating.snap.origin
	furniture._yaw = furniture._seating.snap.yaw
	furniture._hover_valid = furniture._placement_valid(furniture._hover_cell)
	furniture._position_preview(furniture._hover_cell)
	furniture._close_window()
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/seating_study/live_dining_guides.png")
