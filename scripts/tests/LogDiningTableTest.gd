extends "res://scripts/tests/DwarfDiningTest.gd"

const LOG_TABLE := "base:furniture:log_table"
const LOG_TABLE_ITEM := "base:resources:furniture:log_table"
const LOG_TABLE_RECIPE := "base:recipe:worker:log_table"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Log dining table test timed out"); quit(1))
	await _setup_crafting_fixture()
	await _craft_place_move()
	await _layouts_and_meals()
	await _four_diners()
	_profile_lifecycle()
	for failure in failures: push_error(failure)
	print("LOG_DINING_TABLE_OK: two-log crafting, exact-item Move, four rotated layouts, four wood saves, sixteen compact stool guides, four simultaneous diners, conservation and Place card" if failures.is_empty() else "LOG_DINING_TABLE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _craft_place_move() -> void:
	_piece(BENCH,Vector3i(45,20,42))
	drops.spawn_drop(PINE,2,Vector3i(42,21,40))
	var order: int=crafting.queue_order(LOG_TABLE_RECIPE,1)
	_expect(order>=0 and await _completed(order),"Worker crafts a log table from two actual logs")
	_expect(_count(PINE)==0 and _count(LOG_TABLE_ITEM)==1,"two logs become one packed table")
	furniture.activate_for(LOG_TABLE,true)
	furniture._hover_cell=Vector3i(46,20,38)
	_expect(furniture._placement_valid(furniture._hover_cell),"crafted log table has a valid 3x3 site")
	furniture._confirm_ghost();furniture.deactivate()
	_expect(await _installed(LOG_TABLE),"Worker carries and installs the new table")
	_expect(_count(LOG_TABLE_ITEM)==0,"installation consumes the real packed table")
	var tables: Array=furniture._installed.values().filter(func(p): return p.furniture_key==LOG_TABLE)
	if tables.is_empty(): return
	var piece=tables[0]
	_expect(piece.material_id=="base:material:pine","crafted wood identity reaches the installed table")
	furniture.begin_furniture_move(piece.installed_id)
	furniture._yaw=1;furniture._hover_cell=Vector3i(50,20,38)
	_expect(furniture._placement_valid(furniture._hover_cell),"new table can be moved and rotated")
	var plan_id: int=furniture._next_ghost_id
	furniture._confirm_ghost();furniture.deactivate()
	for i in 1200:
		if not furniture._ghosts.has(plan_id): break
		await _tick()
	tables=furniture._installed.values().filter(func(p): return p.furniture_key==LOG_TABLE)
	_expect(tables.size()==1 and tables[0].origin_cell==Vector3i(50,20,38) and tables[0].yaw_steps==1,"worker moves the same table to the requested rotated layout")
	_expect(_count(LOG_TABLE_ITEM)==0 and furniture._moves.records.is_empty(),"Move leaves no duplicate packed table or pending record")
	_clear_layout()

func _layouts_and_meals() -> void:
	var definition: Dictionary=furniture.get_defs()[LOG_TABLE]
	var woods: Array[String]=["pine","oak","juniper","applewood"]
	for yaw in 4:
		_clear_layout()
		worker.position=Vector3(42.5,21,42.5)
		var origin:=Vector3i(46,20,42)
		var id: int=furniture._next_installed_id
		furniture._install(LOG_TABLE,definition,origin,yaw,"base:material:"+woods[yaw])
		var table=furniture._installed[id]
		_expect(table.cells.size()==9,"table reserves its requested 3x3 space")
		for cell in table.cells:_expect(not root.get_node("NavGrid").is_walkable(cell),"dwarves do not walk through the table area")
		var bounds: AABB=furniture.visual_bounds(definition,origin,yaw)
		_expect(bounds.size.is_equal_approx(Vector3(2.875,1.5,2.875)),"eight-cell slab and sixteen-cell pedestal retain native dimensions")
		_expect(bounds.get_center().is_equal_approx(Vector3(origin)+Vector3(1.5,1.75,1.5)),"top and base are centered on the 3x3 footprint")
		var slots: Array=furniture._seating.slots_for(table)
		_expect(slots.size()==4,"four separate stool guides")
		var layout_box := AABB(Vector3(origin),Vector3(3,1,3))
		for slot in slots:
			layout_box = layout_box.merge(AABB(Vector3(slot.origin),Vector3.ONE))
			var reason: String=furniture._seating.placement_reason(furniture.get_defs()[STOOL],slot.origin,slot.yaw)
			_expect(reason.is_empty(),"stool %s clears table and other diners at yaw %d: %s"%[slot.id,yaw,reason])
			furniture._active_key=STOOL
			furniture._seating.resolve(slot.origin)
			_expect(furniture._seating.snap.get("origin") == slot.origin and furniture._seating.snap.get("yaw") == slot.yaw,"automatic guide snaps to the close inward-facing seat")
			_piece(STOOL,slot.origin,slot.yaw)
		furniture._seating.reset()
		_expect(layout_box.size==Vector3(5,1,5),"table and four chairs occupy exactly 5x5 tiles")
		_expect(furniture.get_dining_seats(id).size()==4,"all four stools associate with the new table")
		var saved: Dictionary=JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		_clear_layout();furniture.restore_state(saved)
		table=furniture._installed[id]
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"all wood IDs, anchors, rotations and stool associations survive restore")
		# Leave the north-local stool free; rotating the table exercises all four world sides.
		for i in range(1,slots.size()):
			furniture._installed[furniture._cell_to_installed[slots[i].origin]].idle_seat_owner=900+i
		var seat=furniture._installed[furniture._cell_to_installed[slots[0].origin]]
		_expect(await _meal_start(),"dwarf reaches food and the log dining table")
		_expect(worker._food._dining.outcome()=="proper" and worker._food._dining.choice.get("seat")==seat,"dwarf dines properly at the free guide in every rotation")
		worker._process(.75)
		if yaw==0 and "--capture" in OS.get_cmdline_user_args():await _capture_log_table(table)
		await _finish_food()
		_expect(worker._food.last_dining=="proper" and _food_total(BLUEBERRY)==3,"completed meal consumes exactly one serving with proper dining")
		_expect(table.dining_claims.is_empty(),"meal releases its table claim")
		worker._idle_behavior.cancel()
		for i in range(1,slots.size()):
			furniture._installed[furniture._cell_to_installed[slots[i].origin]].idle_seat_owner=-1
	_clear_layout()

func _four_diners() -> void:
	_clear_layout()
	var table = _piece(LOG_TABLE,Vector3i(46,20,42))
	var slots: Array = furniture._seating.slots_for(table)
	for slot in slots: _piece(STOOL,slot.origin,slot.yaw)
	_store(BLUEBERRY,20)
	var diners := [worker]
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for i in 3:
		var data: Dictionary = factory.generate(901+i,{})
		data.gender="male"
		data.appearance.beard_style=["full_long","braided_long","forked"][i]
		var diner = factory.spawn(data,901+i)
		scene.add_child(diner);diner.set_process(false);tasks.register_dwarf(diner)
		diners.append(diner)
	for i in diners.size():
		var diner = diners[i]
		diner.position=Vector3(42.5,21,40.5+i)
		# Reserve other empty seats while this diner travels; previous diners keep
		# their real claims and servings. All four then remain seated together.
		for j in slots.size():
			var seat = furniture._installed[furniture._cell_to_installed[slots[j].origin]]
			if j!=i and seat.idle_seat_owner<0: seat.idle_seat_owner=1900+j
		_hungry(diner)
		for tick in 1000:
			diner._process(.05);await process_frame
			if diner._food.state=="eating": break
		_expect(diner._food.state=="eating" and diner._food._dining.outcome()=="proper","each of four diners reaches a separate proper dining seat")
		diner._process(.75)
		for slot in slots:
			var seat = furniture._installed[furniture._cell_to_installed[slot.origin]]
			if seat.idle_seat_owner>=1900: seat.idle_seat_owner=-1
	var picking = load("res://scripts/components/ObjectPicking.gd")
	_expect(table.dining_claims.size()==4,"four simultaneous table claims")
	for i in diners.size():
		var diner = diners[i]
		for j in range(i+1,diners.size()):
			_expect(not picking.world_bounds(diner._head).grow(-.001).intersects(picking.world_bounds(diners[j]._head).grow(-.001)),"adjacent diners' actual heads do not overlap")
		_check_table_clearance(diner,table,picking)
		# Lowest and highest bite positions must both clear the raised slab.
		for seconds in [1.0/.65,1.5/.65]:
			diner._food._meal_pose(seconds)
			_check_table_clearance(diner,table,picking)
	if "--capture" in OS.get_cmdline_user_args(): await _capture_log_table(table)
	for diner in diners:
		for tick in 400:
			diner._process(.05);await process_frame
			if diner._food.state!="eating": break
		_expect(diner._food.last_dining=="proper","each of four diners finishes a proper meal")
		# Resting hands stay above the top after the eating-to-idle transition.
		diner._process(.75)
		_check_table_clearance(diner,table,picking)
		for elapsed in [PI*1.5/1.8,PI*.5/1.8]:
			diner._idle_behavior.elapsed=elapsed
			diner._idle_behavior._pose()
			_check_table_clearance(diner,table,picking)
		var seat = diner._idle_behavior.seat
		_expect(is_equal_approx(picking.world_bounds(diner._body).position.y,picking.world_bounds(seat.node).end.y),"raised table posture keeps the torso supported by its unchanged stool")
		_expect(absf(diner._head.rotation.y)<=.026,"compact seated heads retain their gentle idle turn")
	_expect(_food_total(BLUEBERRY)==16 and table.dining_claims.is_empty(),"four diners consume exactly four servings and release claims")
	for diner in diners: diner._idle_behavior.cancel()
	for i in range(1,diners.size()):
		tasks.deregister_dwarf(diners[i].dwarf_id);diners[i].queue_free()
	_clear_layout()


func _check_table_clearance(diner,table,_picking) -> void:
	# Posed faces, not the parts' combined boxes: belt-length beards hang in front
	# of the table edge, below the top (doc 256).
	for part in [diner._body,diner._head,diner._hand_l,diner._hand_r,diner._foot_l,diner._foot_r]:
		for obstacle in furniture._seating._obstacles(table.def,table.origin_cell,table.yaw_steps):
			_expect(not preload("res://scripts/tests/VoxelFaceClearance.gd").meets(part,obstacle.bounds.grow(-.001)),"seated %s clears the actual pedestal/tabletop"%part.name)


func _profile_lifecycle() -> void:
	var definition: Dictionary=furniture.get_defs()[LOG_TABLE]
	var origin:=Vector3i(46,20,42)
	var slots: Array=furniture._seating.slots_for_layout(definition,origin,0)
	var seats:=[]
	for slot in slots: seats.append(_piece(STOOL,slot.origin,slot.yaw))
	_expect(furniture._seating.chair_settings(seats[0]).face_nearby_fire,"standalone stools retain the original resting profile")
	_expect(furniture._seating.placement_reason(definition,origin,0).is_empty(),"table can be placed after its four independent stools")
	var table=_piece(LOG_TABLE,origin)
	_expect(not furniture._seating.chair_settings(seats[0]).face_nearby_fire,"installing the table refreshes the cached close seating profile")
	var fire=_piece("base:furniture:campfire",Vector3i(42,20,38))
	worker._idle_behavior._furniture=furniture
	var facing: Dictionary=worker._idle_behavior._seat_facing(seats[0])
	_expect(facing.get("yaw")==slots[0].yaw and not facing.has("fire_id"),"close dining stools keep their safe inward pose beside a fire")
	furniture.dev_remove_installed(fire.installed_id)
	furniture.dev_remove_installed(table.installed_id)
	_expect(furniture._seating.chair_settings(seats[0]).face_nearby_fire,"table removal restores the ordinary stool profile without stale cache")
	_expect(furniture.get_defs()[STOOL].seating_chair.rest_pose.left_hand[1]==0,"table profile never mutates the shared stool definition")
	_clear_layout()


func _capture_log_table(table) -> void:
	var out:="res://tmp/log_table_compact_20261018/"
	dock.hide();manager.hide()
	camera.position=table.node.global_position+Vector3(9,8,10)
	camera.look_at(table.node.global_position+Vector3(0,1,0));camera.size=11
	await _frames(4);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"actual_dining.png")
	manager.show();dock.show();dock._open_place_catalog()
	dock._place_catalog.show_all=true;dock._place_catalog._all_toggle.set_pressed_no_signal(true)
	dock._place_catalog._select(LOG_TABLE)
	await _frames(5)
	_expect(dock._place_catalog.facts_text().contains("3 × 3"),"Place card shows the new table dimensions")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"place_card.png")
	dock._place_window.hide()
