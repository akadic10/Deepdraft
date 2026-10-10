extends "res://scripts/tests/DwarfIdleBehaviorTest.gd"

const FIRE := "base:furniture:campfire"
const STOOL := "base:furniture:log_chair"
const OUT := "res://tmp/campfire_stool_review/"
const POSITIONS := [Vector3i(49,20,43),Vector3i(47,20,45),Vector3i(49,20,47),Vector3i(51,20,45)]
const FACINGS := [0,1,2,3]

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Campfire stool test timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(OUT)
	var def: Dictionary = furniture.get_defs()[STOOL]
	var fire_def: Dictionary = furniture.get_defs()[FIRE]
	var fire_origin := Vector3i(48,20,44)
	furniture._install(FIRE,fire_def,fire_origin,0)
	var fire_id: int = furniture._installed.keys()[0]
	# The reported spots are immediately outside the fire's 3x3 area. Test every
	# rotation with all other stools present, including queued neighbors.
	for i in range(4):
		for yaw in range(4):
			var reason: String = furniture._floor_placement_reason(def,POSITIONS[i],yaw)
			_expect(reason.is_empty(),"adjacent stool %d rotation %d is placeable: %s" % [i,yaw,reason])
		furniture.activate_for(STOOL)
		furniture._hover_cell = POSITIONS[i]
		furniture._yaw = 0 # Deliberately identical: the occupant must face the fire.
		furniture._confirm_ghost()
		furniture.deactivate()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	furniture.dev_remove_installed(fire_id)
	_clear_items()
	furniture.restore_state(saved)
	for id in furniture._ghosts.keys():
		_expect(furniture._can_build_ghost(furniture._ghosts[id]),"worker may finish the adjacent stool plan")
		furniture.dev_instant_build(id)
	_expect(furniture._installed.size()==5,"all four adjacent stool plans install around fire")
	# The same layout is valid in reverse construction order, but real body/head
	# obstacles and excessively close stools must still be rejected.
	var fire = _fire()
	furniture.dev_remove_installed(fire.installed_id)
	_expect(furniture._floor_placement_reason(fire_def,fire_origin,0).is_empty(),"fire can be installed after its surrounding stools")
	furniture._install(FIRE,fire_def,fire_origin,0)
	_clear_items()
	_expect(furniture._floor_placement_reason(def,Vector3i(50,20,43),0)=="seat_clearance","adjacent seated heads still cannot overlap")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	world.set_block(49,23,43,stone)
	_expect(furniture._seating.placement_reason(def,POSITIONS[0],0,_stool(POSITIONS[0]))=="seat_clearance","solid terrain at head height still blocks seating")
	world.set_block(49,23,43,blocks.AIR_ID)
	var chest: Dictionary = furniture.get_defs()["base:furniture:storage_chest"]
	_expect(furniture._seating.placement_reason(chest,Vector3i(48,20,42),0)=="seat_clearance","real furniture intruding into a seated body is rejected")
	# Use actual idle movement and claims: placement alone is insufficient if
	# coarse navigation occupancy prevents the dwarf from remaining seated.
	var diners: Array = [worker]
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	for i in range(1,4):
		var data: Dictionary = factory.generate(300+i,{})
		if i==1:
			data.gender = "female"
			data.appearance.gender = "female"
			data.appearance.hair_style = "braid_side"
			data.appearance.beard_style = ""
		else:
			data.gender = "male"
			data.appearance.gender = "male"
			data.appearance.hair_style = "short_back"
			data.appearance.beard_style = "full_long" if i==2 else "braided_long"
		var dwarf = factory.spawn(data,300+i)
		scene.add_child(dwarf)
		dwarf.set_process(false)
		dwarf.sleep = 1.0
		tasks.register_dwarf(dwarf)
		diners.append(dwarf)
	for i in range(4):
		var dwarf = diners[i]
		_configure(dwarf)
		dwarf._idle_behavior.config.seat_chance = 1.0
		var outward: Vector3i = POSITIONS[i]-Vector3i(49,20,45)
		_reset_at(dwarf,POSITIONS[i]+outward)
		_expect(await _seat_phase(dwarf,"sitting"),"dwarf reaches and sits beside the fire on side "+str(i))
		dwarf._process(1)
		_expect(dwarf._idle_behavior.seat==_stool(POSITIONS[i]),"dwarf uses its nearest stool")
		_expect(is_equal_approx(dwarf.rotation.y,float(FACINGS[i])*PI*.5),"occupant turns toward fire independently of stool rotation")
		_expect(_stool(POSITIONS[i]).yaw_steps==0,"sitting does not rotate the installed stool")
	var picking = load("res://scripts/components/ObjectPicking.gd")
	for dwarf in diners:
		for tick in range(15): dwarf._process(.1)
		_expect(dwarf._idle_behavior.state=="sitting","dwarf stays seated beside campfire occupancy")
		if dwarf._idle_behavior.seat==null: continue
		for part in [dwarf._head,dwarf._body,dwarf._hand_l,dwarf._hand_r,dwarf._foot_l,dwarf._foot_r]:
			var bounds: AABB = picking.world_bounds(part)
			for obstruction in furniture._seating._obstacles(fire_def,fire_origin,0):
				_expect(not bounds.grow(-.001).intersects(obstruction.bounds),"seated body parts clear stones and flame")
	if "--capture" in OS.get_cmdline_user_args():
		# A short shadow range keeps the small voxel silhouettes readable in this
		# isolated fixture (the game uses its own sun/environment controller).
		camera.far = 80
		for child in scene.get_children():
			if child is DirectionalLight3D:
				child.directional_shadow_max_distance = 35
				child.shadow_normal_bias = 1.0
			if child is WorldEnvironment:
				child.environment.ambient_light_color = Color.WHITE
		camera.size = 11
		camera.position = Vector3(57,32,55)
		camera.look_at(Vector3(49.5,22,45.5))
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"four_seated.png")
		for i in range(1,4): diners[i].hide()
		camera.size = 7
		camera.position = Vector3(54,26,50)
		camera.look_at(Vector3(49.5,22.4,43.5))
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"relaxed_stool.png")
		diners[0].hide()
		diners[2].show()
		camera.position = Vector3(45,26,40)
		camera.look_at(Vector3(49.5,22.4,47.5))
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"bearded_stool.png")
	for dwarf in diners:
		var used_seat = dwarf._idle_behavior.seat
		dwarf._idle_behavior.cancel()
		_expect(used_seat!=null and used_seat.idle_seat_yaw_steps==-1,"leaving releases the temporary facing")
		_expect(dwarf._body.position.is_zero_approx(),"leaving stool restores ordinary work pose")
	await _focus_fallbacks(def,fire_def,stone)
	for failure in failures: push_error(failure)
	print("CAMPFIRE_STOOL_OK: adjacent positions, independent fire facing, pose clearance, blocked/distant fire fallback and claim cleanup" if failures.is_empty() else "CAMPFIRE_STOOL_FAIL")
	quit(0 if failures.is_empty() else 1)

func _focus_fallbacks(def: Dictionary, fire_def: Dictionary, stone: int) -> void:
	for piece in furniture._installed.values().duplicate(): furniture.dev_remove_installed(piece.installed_id)
	_clear_items()
	var origin := Vector3i(42,20,44)
	furniture._install(STOOL,def,origin,1)
	var stool = _stool(origin)
	var idle = worker._idle_behavior
	_expect(idle._seat_facing(stool).yaw==1,"without a fire the placed facing is retained")
	furniture._install(FIRE,fire_def,Vector3i(41,20,47),0)
	var fire = _fire()
	_expect(idle._seat_facing(stool).get("fire_id",-1)==fire.installed_id,"nearby installed fire is preferred")
	# A thin wall between seat and fire is outside the seated envelope.
	world.set_block(42,22,46,stone)
	_expect(idle._seat_facing(stool)=={"yaw":1},"a fire hidden by terrain is not a focus")
	world.set_block(42,22,46,blocks.AIR_ID)
	# Low terrain beneath the hands/body makes this seat unusable in either
	# direction; a fire must never override the physical clearance check.
	world.set_block(42,21,45,stone)
	_expect(idle._seat_facing(stool).is_empty(),"blocked seated poses are rejected even beside a fire")
	world.set_block(42,21,45,blocks.AIR_ID)
	fire.flagged_uninstall = true
	_expect(idle._seat_facing(stool)=={"yaw":1},"a fire awaiting removal is ignored")
	fire.flagged_uninstall = false
	idle.config.seat_focus_radius = 3
	_expect(idle._seat_facing(stool)=={"yaw":1},"distant fires do not steer resting dwarves")
	idle.config.seat_focus_radius = 6
	# An off-axis fire uses a modest head turn, without rotating the whole seated
	# pose continuously. Removing that focus must not strand or spin the sitter.
	furniture.dev_remove_installed(fire.installed_id)
	furniture._install(FIRE,fire_def,Vector3i(43,20,47),0)
	fire = _fire()
	_reset_at(worker,Vector3i(39,20,44))
	_expect(await _seat_phase(worker,"sitting"),"off-axis fire stool is reached normally")
	worker._process(1)
	var toward: Vector3 = fire.node.global_position-stool.node.global_position
	var head_facing: Vector3 = worker._head.global_basis.z
	_expect(head_facing.normalized().dot(toward.normalized())>.99,"head looks toward an off-axis fire")
	var resting_yaw: float = worker.rotation.y
	furniture.dev_remove_installed(fire.installed_id)
	worker._process(.1)
	_expect(idle.state=="sitting" and is_equal_approx(worker.rotation.y,resting_yaw),"removing the fire keeps a stable valid sitting pose")
	_expect(absf(worker._head.rotation.y)<.03,"removed fire no longer holds the head turned")
	idle.cancel()
	furniture._install(FIRE,fire_def,Vector3i(41,20,47),0)
	# Backed chairs keep their authored facing even with a fire in another direction.
	furniture.dev_remove_installed(stool.installed_id)
	furniture._install(CHAIR,furniture.get_defs()[CHAIR],origin,1)
	var chair = furniture._installed.values().filter(func(p): return p.furniture_key==CHAIR)[0]
	_expect(idle._seat_facing(chair)=={"yaw":1},"wooden chair occupants stay aligned with their backrest")
	await process_frame

func _fire():
	for piece in furniture._installed.values():
		if piece.furniture_key==FIRE: return piece
	return null

func _stool(cell: Vector3i):
	for piece in furniture._installed.values():
		if piece.furniture_key==STOOL and piece.origin_cell==cell: return piece
	return null

func _clear_items() -> void:
	for node in drops._loose.keys(): drops.take(node); node.free()
