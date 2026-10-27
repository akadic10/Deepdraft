extends "res://scripts/tests/WorkerCraftingTest.gd"

const GAME := "base:furniture:board_game_table"
const STOOL := "base:furniture:log_chair"
const FENCE := "base:furniture:log_fence"
const GATE := "base:furniture:log_gate"
var table
var chairs: Array = []
const OUT := "res://tmp/log_game/"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Rudimentary recreation timed out"); quit(1))
	await _setup_crafting_fixture()
	await _craft_and_place()
	_access_and_rotations()
	_saved_layout_roundtrip()
	_create_partner()
	await _play_at_each_rotation()
	await _partners_with_memory()
	await _games_and_interruptions()
	for failure in failures: push_error(failure)
	print("RUDIMENTARY_RECREATION_OK: crafting, real installation, rotations, navigation, two seats, two players, needs, work, timeout, pause, mood and persistence" if failures.is_empty() else "RUDIMENTARY_RECREATION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _piece(key: String, origin: Vector3i, yaw := 0):
	var id: int = furniture._next_installed_id
	furniture._install(key,furniture.get_defs()[key],origin,yaw)
	return furniture._installed[id]

func _clear_layout() -> void:
	for game in furniture._games.games.values(): game.cancel()
	for piece in furniture._installed.values(): furniture.dev_remove_installed(piece.installed_id)
	furniture._games.tables.clear()
	furniture._games.candidates.clear()
	furniture._games.choice = {}
	furniture._games.delay = 0
	chairs.clear()

func _craft_and_place() -> void:
	_piece(BENCH,Vector3i(45,20,42))
	drops.spawn_drop(PINE,4,Vector3i(42,21,40))
	drops.spawn_drop(STONE,1,Vector3i(42,21,41))
	# The enlarged workbench also fills the south boundary beside the old fence site.
	var positions := [Vector3i(44,20,46),Vector3i(49,20,45),Vector3i(46,20,38)]
	var index := 0
	for key: String in [FENCE,GATE,GAME]:
		worker._food.value = 1.0
		var recipe := "base:recipe:worker:"+key.get_slice(":",2)
		var id: int = crafting.queue_order(recipe,1)
		_expect(id >= 0 and await _completed(id),"Worker crafts "+key+" using actual materials")
		var item_key := "base:resources:furniture:"+key.get_slice(":",2)
		_expect(_count(item_key)==1,"one packed output: "+key)
		furniture.activate_for(key,true)
		furniture._hover_cell = positions[index]
		_expect(furniture._placement_valid(positions[index]),"real placement valid: "+key)
		furniture._confirm_ghost()
		furniture.deactivate()
		_expect(await _installed(key),"Worker hauls and installs "+key)
		_expect(_count(item_key)==0,"installation consumes packed output")
		index += 1
	_expect(_count(PINE)==0 and _count(STONE)==0,"recipes consume exactly four logs and one stone")
	var saved: Dictionary = furniture.serialize_state()
	_expect(saved.installed.size()==4,"all three designs serialize with existing workshop")
	_clear_layout()
	furniture.restore_state(saved)
	_expect(furniture._installed.size()==4,"new furniture restores through existing save owner")
	_clear_layout()

func _access_and_rotations() -> void:
	for yaw in range(4):
		var origin := Vector3i(46,20,42)
		var fence = _piece(FENCE,origin,yaw)
		_expect(fence.cells.is_empty(),"grid-corner post does not reserve floor cells")
		furniture.dev_remove_installed(fence.installed_id)
		var gate = _piece(GATE,origin,yaw)
		for cell in gate.cells:
			_expect(root.get_node("NavGrid").is_walkable(cell),"gate is traversable at yaw %d"%yaw)
			_expect(not root.get_node("RoomManager")._door_cells.has(cell),"open rail gate never seals a room")
		var hinges = gate.node.get_node("DoorAnimation")
		worker.position = gate.node.global_position+Vector3(0,0,1)
		hinges._process(.4)
		_expect(hinges._angle > .1 and hinges._hinges.size()==1,"gate leaf opens near dwarf")
		furniture.dev_remove_installed(gate.installed_id)
		table = _piece(GAME,origin,yaw)
		_expect(table.cells.size()==9,"log game reserves its full 3x3 area in every rotation")
		for cell in table.cells: _expect(not root.get_node("NavGrid").is_walkable(cell),"game area blocks walking")
		var slots: Array = furniture._seating.slots_for(table)
		_expect(slots.size()==2,"two separate stool guides")
		for slot in slots:
			var reason: String = furniture._seating.placement_reason(furniture.get_defs()[STOOL],slot.origin,slot.yaw)
			_expect(reason.is_empty(),"stool fits broad dwarf clearance yaw %d: %s"%[yaw,reason])
			chairs.append(_piece(STOOL,slot.origin,slot.yaw))
		_expect(furniture.get_dining_seats(table.installed_id).size()==2,"both seats associate in every rotation")
		_clear_layout()

func _saved_layout_roundtrip() -> void:
	for yaw in range(4):
		var origin := Vector3i(46,20,42)
		table = _piece(GAME,origin,yaw)
		for slot in furniture._seating.slots_for(table):
			chairs.append(_piece(STOOL,slot.origin,slot.yaw))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		var id: int = table.installed_id
		_clear_layout()
		furniture.restore_state(saved)
		table = furniture._installed[id]
		_expect(table.cells.size()==9 and furniture.get_dining_seats(id).size()==2,"3x3 game and both stool associations survive reload")
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"saved IDs, material, positions, yaw and layout version remain stable")
		var bounds: AABB = furniture.visual_bounds(table.def,table.origin_cell,table.yaw_steps)
		_expect(bounds.size.is_equal_approx(Vector3(2.875,1.5625,2.875)),"native 46-cell outline, 24-cell shared dining-table height and one-cell counters survive every saved rotation")
		_expect(AABB(Vector3(origin+Vector3i.UP),Vector3(3,1.5625,3)).encloses(bounds),"log and counters stay inside their game area")
		_clear_layout()

func _create_partner() -> void:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(142,{})
	data.gender="male"
	data.appearance.beard_style="full_long"
	extra_worker = factory.spawn(data,142)
	scene.add_child(extra_worker)
	extra_worker.set_process(false)
	tasks.register_dwarf(extra_worker)

func _reset_players() -> void:
	for agent in [worker,extra_worker]:
		agent.abort_task()
		agent._mood.restore(_blank_mood(agent))
		agent._food.value = 1.0
		agent.sleep = 1.0
		agent._idle_behavior.config = agent._idle_behavior.config.duplicate(true)
		agent._idle_behavior.config.seat_chance = 0.0
		tasks.notify_dwarf_idle(agent.dwarf_id)
	worker.position = Vector3(43.5,21,39.5)
	extra_worker.position = Vector3(51.5,21,46.5)

func _layout(count := 2, yaw := 0) -> void:
	_clear_layout()
	_reset_players()
	table = _piece(GAME,Vector3i(46,20,42),yaw)
	var slots: Array = furniture._seating.slots_for(table)
	for i in count: chairs.append(_piece(STOOL,slots[i].origin,slots[i].yaw))

func _game_tick(seconds := .1) -> void:
	furniture._games.tick(seconds)
	worker._process(seconds)
	extra_worker._process(seconds)
	await process_frame

func _play_at_each_rotation() -> void:
	for yaw in 4:
		_layout(2,yaw)
		_expect(await _playing(),"two players reach the resized game table at yaw %d"%yaw)
		if not worker.is_recreating(): continue
		var game = worker._recreation
		for index in game.players.size():
			game.elapsed = 1.0+index*2.0
			var player: Dictionary = game.players[index]
			game._pose(player)
			# The hand node mirrors its source +X palm into the actor's -X side.
			var palm: Vector3 = table.node.to_local(player.agent._hand_r.to_global(Vector3(1.0625,1.25,.1875)))
			_expect(absf(palm.x)<.8 and absf(palm.z)<.8,"playing hand reaches the marked board at every rotation")
			_expect(palm.y>1.5625 and palm.y<2.0,"playing palm clears the new top and raised counters")
			# Posed faces, not combined boxes: a long beard hangs in front of the edge (doc 256).
			for part in [player.agent._head,player.agent._body,player.agent._hand_l,player.agent._hand_r]:
				for obstacle in furniture._seating._obstacles(table.def,table.origin_cell,table.yaw_steps):
					_expect(not preload("res://scripts/tests/VoxelFaceClearance.gd").meets(part,obstacle.bounds.grow(-.001)),"playing %s clears slab/counters: %s"%[part.name,obstacle.bounds])
	_clear_layout()

func _partners_with_memory() -> void:
	_layout()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var third = factory.spawn(factory.generate(143,{}),143)
	scene.add_child(third)
	third.position = Vector3(43.5,21,43.5)
	third.set_process(false)
	tasks.register_dwarf(third)
	for agent in [extra_worker,third]:
		agent._food.value = 1.0
		agent.sleep = 1.0
		agent._mood.record_recreation()
		agent._mood.recreation_retry_hours = 6
		_expect(not furniture._games.eligible(agent),"recent player respects the six-hour cooldown")
	for i in 150:
		await _game_tick()
		third._process(.1)
		if worker.is_recreating() and worker._recreation.players[0].arrived: break
	_expect(worker.is_recreating() and worker._recreation.describe(worker).activity=="Playing a board game alone","first dwarf plays alone while both potential partners are cooling down")
	for agent in [extra_worker,third]:
		agent._mood.recreation_retry_hours = 0
		agent._mood.recreation_memory_hours = 5
		_expect(furniture._games.eligible(agent),"idle dwarf with an existing happiness bonus can join after cooldown")
	var started := false
	for i in 180:
		await _game_tick()
		third._process(.1)
		if worker.is_recreating() and worker._recreation.together:
			started = true
			break
	_expect(started,"waiting player recruits one of two available dwarves with recent game memories")
	if started:
		var game = worker._recreation
		_expect(game.players.size()==2 and (extra_worker.is_recreating() != third.is_recreating()),"only one partner occupies the free stool")
		var partner = game.players[1].agent
		for i in 250:
			await _game_tick()
			third._process(.1)
			if not worker.is_recreating(): break
		_expect(partner._mood.recreation_memory_hours>11 and is_equal_approx(partner._mood.value(),.58),"repeat play refreshes one bonus without stacking happiness")
	_clear_layout()
	tasks.deregister_dwarf(third.dwarf_id)
	third.free()

func _playing() -> bool:
	for i in range(250):
		await _game_tick()
		if worker.is_recreating() and worker._recreation.together: return true
	return false

func _games_and_interruptions() -> void:
	_layout(0)
	for i in range(40): await _game_tick()
	_expect(not worker.is_recreating() and furniture._games.games.is_empty(),"no stool cannot start a game")
	_layout()
	_expect(await _playing(),"two dwarves reach opposite stools and begin playing")
	if not worker.is_recreating(): return
	var game = worker._recreation
	var rows: Dictionary = {}
	for row in furniture.get_explorer_data("installed:%d" % table.installed_id).rows: rows[row[0]] = row[1]
	_expect(rows.get("Happiness","").contains("Solo +4 · Together +8 for 12 game hours"),"game inspector distinguishes both happiness rewards")
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(inspection.describe(worker).activity=="Playing a board game" and inspection.roster_state(worker).group=="resting","inspector and roster identify recreation")
	_expect(extra_worker._recreation==game and worker.dwarf_id not in tasks._idle_dwarves,"shared game keeps both workers out of scheduler")
	_expect(root.get_node("NavGrid").is_walkable(worker.current_cell()),"seated save position remains on legal ground")
	var elapsed: float = game.elapsed
	clock_node.set_paused(true)
	await _game_tick(2)
	_expect(game.elapsed==elapsed,"pause freezes game and pose")
	clock_node.set_paused(false)
	clock_node.set_speed(2)
	furniture._process(.25)
	_expect(is_equal_approx(game.elapsed,elapsed+.5),"game duration follows simulation speed")
	clock_node.set_speed(1)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var third = factory.spawn(factory.generate(143,{}),143)
	scene.add_child(third)
	third.position = Vector3(43.5,21,43.5)
	third.set_process(false)
	tasks.register_dwarf(third)
	for i in range(10): await _game_tick()
	_expect(not third.is_recreating() and game.players.size()==2,"third dwarf cannot steal either occupied stool")
	tasks.deregister_dwarf(third.dwarf_id)
	third.free()
	if "--capture" in OS.get_cmdline_user_args(): await _capture_game()
	for i in range(250):
		await _game_tick()
		if not worker.is_recreating(): break
	_expect(worker._mood.recreation_memory_hours>11 and extra_worker._mood.recreation_memory_hours>11,"only completed two-player game rewards both dwarves")
	_expect(is_equal_approx(worker._mood.value(),.58),"game adds eight happiness points")
	_expect(worker._mood.describe().thought.contains("Played a board game with a friend"),"earned happiness explains its source and remaining duration")
	worker._mood.record_recreation()
	_expect(is_equal_approx(worker._mood.value(),.58),"repeat completion refreshes rather than stacks")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	worker.restore_saved_runtime(saved)
	_expect(worker._mood.recreation_memory_hours>11 and worker._mood.recreation_retry_hours>5,"memory and cooldown survive JSON restore")
	_expect(chairs.all(func(c): return c.idle_seat_owner<0),"completion releases both stools")
	_expect(worker.dwarf_id in tasks._idle_dwarves and tasks.lifecycle_errors().is_empty(),"completion returns workers to scheduler")
	worker._mood.tick(13)
	_expect(is_equal_approx(worker._mood.value(),.5),"temporary thought expires")
	_layout()
	extra_worker._mood.recreation_retry_hours = 6
	for i in range(400): await _game_tick()
	_expect(not worker.is_recreating() and worker._mood.recreation_retry_hours>5 and worker._mood.solo_recreation_memory_hours>11 and is_equal_approx(worker._mood.value(),.54),"lone player completes solo play for four happiness points")
	for cause: String in ["stool","table","sleep","hunger","movement","save","blocked","support","profession"]:
		_layout()
		_expect(await _playing(),cause+": starts game")
		if not worker.is_recreating(): continue
		if cause=="stool": chairs[0].set_uninstall(true)
		elif cause=="table": furniture.dev_remove_installed(table.installed_id)
		elif cause=="sleep": worker.sleep = 0
		elif cause=="hunger": worker._food.value = .1
		elif cause=="movement": worker.walk_to(Vector3i(43,20,42))
		elif cause=="save":
			saved = worker.serialize_state()
			worker.restore_saved_runtime(saved)
		elif cause=="blocked":
			world.set_block(worker.current_cell().x,21,worker.current_cell().z,blocks.get_id("base:terrain:rock:rock01"))
		elif cause=="support": world.set_block(table.origin_cell.x,20,table.origin_cell.z,0)
		else: worker._release_for_assignment_change()
		await _frames(2) # WorldData publishes chunk invalidation at its frame boundary.
		await _game_tick()
		_expect(not worker.is_recreating() and not extra_worker.is_recreating(),cause+": cancels both participants safely")
		_expect(chairs.all(func(c): return c.idle_seat_owner<0),cause+": releases seats")
		_expect(worker._mood.recreation_memory_hours==0,cause+": partial game earns no happiness")
		if worker.is_sleeping(): worker._wake_up()
		worker._food.cancel()
		if cause=="blocked":
			for x in range(44,51):
				for z in range(38,48): world.set_block(x,21,z,0)
		elif cause=="support": world.set_block(table.origin_cell.x,20,table.origin_cell.z,blocks.get_id("base:terrain:rock:rock01"))
	_layout()
	worker._mood.record_dining("neither")
	tasks.notify_dwarf_unavailable(extra_worker.dwarf_id)
	# Real work: a placed rock on the floor, mined away again on completion.
	world.set_block(44,21,39,blocks.get_id("base:terrain:rock:rock01"))
	var work_id: int = _post_mine_lease(Vector3i(44,21,39))
	for i in range(60):
		tasks._run_scheduler()
		if worker.current_task_id==work_id: break
		await process_frame
	_expect(worker.current_task_id==work_id,"unhappy worker has a real job")
	_expect(await _playing(),"unhappy worker takes short break despite queued work")
	_expect(tasks.lifecycle_errors().is_empty(),"need interruption safely releases job lease")
	worker.force_interrupt()
	_expect(worker._body.position.is_zero_approx(),"interruption resets seated pose")
	for i in range(150):
		tasks._run_scheduler()
		worker._process(.1)
		await process_frame
		if tasks.get_task(work_id)==null: break
	_expect(tasks.get_task(work_id)==null,"released work resumes and completes after game interruption")
	_clear_mine_leases()
	world.set_block(44,21,39,0)
	_layout()
	drops.restore_loose_item(PINE,worker.position,0,1)
	var cargo: Node3D = drops.nearest_loose_of_key(PINE,worker.current_cell())
	drops.take(cargo)
	worker.add_child(cargo)
	cargo.position = Vector3.ZERO
	worker._carried_entries.append([cargo,PINE])
	_expect(not furniture._games.eligible(worker),"recreation never takes a worker carrying real cargo")
	worker.abort_task()
	_expect(_count(PINE)==1,"cargo remains conserved when work is released")
	for node in drops._loose.keys(): drops.take(node); node.free()
	_expect(await _playing(),"game can start after cargo is safely released")
	furniture._exit_tree()
	_expect(not worker.is_recreating() and not extra_worker.is_recreating(),"scene teardown cancels both players before controller disappears")
	_clear_layout()

func _capture_game() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for node in drops._loose.keys(): drops.take(node); node.free()
	for node in [dock,manager]: node.hide()
	camera.position = table.node.global_position+Vector3(9,8,5)
	camera.look_at(table.node.global_position+Vector3(0,1.1,0))
	camera.size = 9
	var game = worker._recreation
	for elapsed in [1.0,3.0]:
		game.elapsed = elapsed
		for player in game.players: game._pose(player)
		await _frames(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"playing_%d.png"%int(elapsed))
	worker.hide()
	extra_worker.hide()
	camera.size = 7
	camera.look_at(table.node.global_position+Vector3(0,.45,0))
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"log_game.png")
	worker.show()
	extra_worker.show()
	manager.show()
	dock.show()
	dock._open_place_catalog()
	dock._place_catalog.show_all = true
	dock._place_catalog._all_toggle.set_pressed_no_signal(true)
	dock._place_catalog._select(GAME)
	await _frames(5)
	_expect(dock._place_catalog.facts_text().contains("3 × 3") and dock._place_catalog._note.text.contains("outside"),"Place card explains game area and separate stools")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"place.png")
	dock._place_window.hide()

## A saved mood with every timer at zero (solo memory is only written above zero).
func _blank_mood(agent) -> Dictionary:
	var mood: Dictionary = agent._mood.serialize()
	for key: String in mood: mood[key] = "" if key == "dining_outcome" else 0.0
	mood.erase("solo_recreation_memory_hours")
	return mood
