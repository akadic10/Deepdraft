extends "res://scripts/tests/DwarfFoodTest.gd"

const CHAIR := "base:furniture:log_stool"
const TABLE := "base:furniture:dining_table"
const STOOL := "base:furniture:log_stool"
const LOG_BENCH := "base:furniture:bench"
const CAMPFIRE := "base:furniture:campfire"
var details
var bush_id := "blueberry:1234:1:1"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Dining test timed out"); quit(1))
	await _setup_crafting_fixture()
	await _arrangements()
	await _facing()
	await _famished_seating_range()
	await _busy_room_at_speed()
	await _reach_as_the_player_sees_it()
	await _place_taken_while_looking()
	await _interruptions()
	await _foraging()
	_effects_and_save()
	await _presentation()
	for failure in failures: push_error(failure)
	print("DWARF_DINING_OK: four dining outcomes, fire and table facing, room-wide reach, busy room at x3, reach as seen, a taken place, seat contention, interruption, emergency crops, claims, conservation, season, saved work, mood, work speed and UI" if failures.is_empty() else "DWARF_DINING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _clear_layout() -> void:
	worker._food.cancel()
	worker._idle_behavior.cancel()
	for piece in furniture._installed.values(): furniture.dev_remove_installed(piece.installed_id)
	_clear_food()
	worker._food.last_meal = ""
	worker._food.last_dining = ""

func _piece(key: String, origin: Vector3i, yaw := 0):
	furniture._install(key,furniture.get_defs()[key],origin,yaw)
	return furniture._installed[furniture._cell_to_installed[origin]]

func _meal_start() -> bool:
	_store(BLUEBERRY,4)
	_hungry(worker)
	return await _food_phase("eating")

func _arrangements() -> void:
	for expected: String in ["proper","seat_only","table_only","neither"]:
		_clear_layout()
		var seat = null
		if expected in ["proper","seat_only"]: seat = _piece(CHAIR,Vector3i(45,20,40))
		if expected in ["proper","table_only"]: _piece(TABLE,Vector3i(44,20,41))
		_expect(await _meal_start(),expected+": reaches eating")
		_expect(worker._food._dining.outcome()==expected,expected+": chooses the best actual arrangement")
		if seat != null: _expect(seat.idle_seat_owner==worker.dwarf_id,"meal claims the seat")
		worker._process(.75)
		var seated_body: Vector3 = worker._body.position
		var seated_feet: Vector3 = worker._foot_l.position
		await _finish_food()
		_expect(worker._food.last_dining==expected,"completed meal records "+expected)
		_expect(is_equal_approx(worker._mood.value(),.5-float(worker._mood.config.dining.get(expected,0))),"exactly one dining penalty")
		if seat != null:
			_expect(seat.idle_seat_owner==worker.dwarf_id and worker._idle_behavior.state=="sitting","finished meal hands the occupied seat to idle rest")
			_expect(worker._body.position.is_equal_approx(seated_body) and worker._foot_l.position.is_equal_approx(seated_feet),"completion frame preserves the seated body and feet")
			worker._process(.05)
			_expect(worker._body.position.is_equal_approx(seated_body),"next idle frame stays seated without a second sit-down")
			_expect(worker.dwarf_id in tasks._idle_dwarves,"resting after eating remains available for work")
			worker._idle_behavior.timer = 0
			worker._process(.05)
			worker._process(.05)
			_expect(not worker._body.position.is_zero_approx() and worker._body.position.length()<seated_body.length(),"rest ends with a gradual stand-up")
			for i in 24:
				worker._process(.05)
				if seat.idle_seat_owner<0: break
			_expect(seat.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"standing releases the meal's seat")
		for piece in furniture._installed.values():
			_expect(piece.dining_claims.is_empty(),"finished meal releases its dining-table claim")
	# The current buildable log stool is backless and may face the table from
	# either stored rotation. The removed backed chair is no longer a fixture.
	_clear_layout()
	_piece(CHAIR,Vector3i(45,20,40),2)
	_piece(TABLE,Vector3i(44,20,41))
	_expect(await _meal_start(),"reversed chair remains usable")
	_expect(worker._food._dining.outcome()=="proper","backless stool can turn toward its table")
	await _finish_food()
	for key: String in [STOOL,LOG_BENCH]:
		_clear_layout()
		var seat = _piece(key,Vector3i(45,20,40))
		# The bench uses its ordinary posture; only the matching stool gets the
		# table's compact raised-head profile. Leave its normal extra clearance.
		_piece(TABLE,Vector3i(44,20,42 if key==LOG_BENCH else 41))
		_expect(await _meal_start(),"simple seat reaches eating")
		_expect(worker._food._dining.outcome()=="proper",key+" can dine at a properly spaced table")
		worker._process(.75)
		var seated_body: Vector3 = worker._body.position
		await _finish_food()
		_expect(worker._body.position.is_equal_approx(seated_body) and seat.idle_seat_owner==worker.dwarf_id,key+" keeps its meal pose and claim on completion")
		_expect(worker.walk_to(Vector3i(40,20,39)),"player movement can interrupt rest after eating")
		_expect(seat.idle_seat_owner<0 and not worker._idle_behavior.active() and worker._body.position.is_zero_approx(),"movement after a meal releases the transferred seat and pose")

## The owner's report (2026-10-29): a dwarf ate on a campfire stool facing away from
## the fire. A stool faces a table its front meets, else a campfire, eating or resting.
func _facing() -> void:
	_clear_layout()
	var fire = _piece(CAMPFIRE,Vector3i(48,20,44))
	var stool = _piece(STOOL,Vector3i(49,20,42),1) # side-on to the ring south of it
	# Cold by day, then lit at night: the owner chose that both draw the stool.
	for lit: bool in [false,true]:
		if lit: furniture.get_fires().light(fire,PINE,"base:material:pine")
		var fire_state := "burning" if lit else "cold"
		_expect(await _meal_start(),fire_state+" campfire: diner reaches eating")
		var dining = worker._food._dining
		_expect(dining.outcome()=="seat_only" and dining.choice.get("seat")==stool and dining.choice.yaw==0 and stool.idle_seat_yaw_steps==0 and is_zero_approx(worker.rotation.y),
			"a diner on a stool turns to face the "+fire_state+" campfire")
		await _finish_food()
		var idle = worker._idle_behavior
		_expect(idle.state=="sitting" and idle.seat==stool and is_zero_approx(worker.rotation.y) and idle._focus_fire_id==fire.installed_id,
			"resting after the meal keeps facing the "+fire_state+" fire, head turn included")
		idle.cancel()
		_expect(furniture._seating.facing(stool,6.0)=={"yaw":0,"fire_id":fire.installed_id},"idle sitting picks the same "+fire_state+" fire")
	# A table one tile north, which the stool's front can meet, comes before the fire.
	var table = _piece(TABLE,Vector3i(48,20,38))
	_expect(furniture._seating.facing(stool,6.0)=={"yaw":2},"an idle stool by a table turns to the table, not the fire")
	_expect(await _meal_start(),"table and fire: diner reaches eating")
	var dining = worker._food._dining
	_expect(dining.outcome()=="proper" and dining.choice.get("table")==table and dining.choice.yaw==2,"a diner beside both eats facing the table")
	await _finish_food()
	_expect(worker._idle_behavior.state=="sitting" and worker._idle_behavior._focus_fire_id<0,"resting after a table meal keeps facing the table")
	_clear_layout()

## The owner's report (2026-10-30): in the lobby every dwarf ate standing at the food
## pile. The free table and stools were 17-20 blocks away, past the old sixteen-block reach.
func _famished_seating_range() -> void:
	_clear_layout()
	# Keep both near and distant furniture genuinely walkable, so rejection
	# outside the dining limit cannot pass merely because terrain is missing.
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(38,80):
		for z in range(38,49):
			world.set_block(x,20,z,rock)
			for y in range(21,25): world.set_block(x,y,z,0)
	await _frames(2)
	for start_food: float in [.3,.05]:
		_clear_layout()
		var seat = _piece(CHAIR,Vector3i(58,20,41))
		var table = _piece(TABLE,Vector3i(57,20,42))
		_store(BLUEBERRY,4)
		_hungry(worker)
		worker._food.value = start_food
		_expect(await _food_phase("dining"),"hungry/famished dwarf collects a real portion before dining")
		var pickup: Vector3i = worker.current_cell()
		_expect(worker._carried_entries.size()==1 and _food_total(BLUEBERRY)==4,"dining search owns one uneaten portion")
		_expect(await _food_phase("eating"),"hungry/famished dwarf reaches dining seat")
		var dining = worker._food._dining
		_expect(dining.choice.get("seat")==seat and dining.choice.get("table")==table,"both hunger tiers choose the free seat and table across the room")
		_expect(Vector3(worker.current_cell()-pickup).length()>16 and seat.idle_seat_owner==worker.dwarf_id,"dwarf carries food past the old sixteen-block reach and claims the chair")
		await _finish_food()
		_expect(worker._food.last_dining=="proper" and _food_total(BLUEBERRY)==3,"proper meal consumes exactly one berry without a dining penalty")
	_clear_layout()
	_piece(CHAIR,Vector3i(76,20,41))
	_piece(TABLE,Vector3i(75,20,42))
	_store(BLUEBERRY,4)
	_hungry(worker)
	worker._food.value = .05
	_expect(await _food_phase("eating"),"famished dwarf still eats promptly when dining is too far away")
	_expect(worker._food._dining.outcome()=="neither","the thirty-two-block reach still excludes distant furniture")
	await _finish_food()
	_expect(_food_total(BLUEBERRY)==3,"distance fallback also consumes exactly one berry")

## A wider reach brings more seats into the search, one checked per frame. At ×3 the
## search budget ends before every seat here is checked, so the nearest seat at a table
## must be routed as soon as it is found.
func _busy_room_at_speed() -> void:
	_clear_layout()
	var seat = _piece(CHAIR,Vector3i(45,20,40))
	var table = _piece(TABLE,Vector3i(44,20,41))
	var budget_frames := ceili(float(worker._food.config.dining_search_seconds)/(.05*3))
	for i in budget_frames+2: _piece(STOOL,Vector3i(48+i,20,47))
	clock_node.set_speed(3)
	_expect(await _meal_start(),"busy room: diner reaches eating at ×3")
	clock_node.set_speed(1)
	var dining = worker._food._dining
	_expect(dining.outcome()=="proper" and dining.choice.get("seat")==seat and dining.choice.get("table")==table,
		"the nearest seat at a table is used before every lone stool is checked")
	await _finish_food()
	_clear_layout()

## The owner's report (2026-11-10): the dining table stood 23 blocks from the food shelves as the
## crow flies, but the walk to it was 34 to 42 blocks, and the reach was counted along the walk,
## so every dwarf ate where it stood. The reach is how far away a place is (`dining_distance`);
## the walk to it has its own, wider bound (`dining_walk_distance`).
func _reach_as_the_player_sees_it() -> void:
	_clear_layout()
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	# Two walls across the corridor _famished_seating_range laid, and well past its sides, each
	# with one gap, so the walk to the table winds through both.
	var walls := [[50, 48], [60, 38]]   # the wall's x, its gap's z
	for wall: Array in walls:
		for z in range(26, 61):
			if z == int(wall[1]): continue
			for y in range(21, 25): world.set_block(int(wall[0]), y, z, rock)
	await _frames(4)
	var seat = _piece(CHAIR, Vector3i(67, 20, 45))
	var table = _piece(TABLE, Vector3i(66, 20, 46))
	_store(BLUEBERRY, 4)
	_hungry(worker)
	_expect(await _food_phase("dining"), "winding walk: the diner collects its portion")
	var pickup: Vector3i = worker.current_cell()
	var nav := root.get_node("NavGrid")
	var goals := {}
	for cell: Vector3i in load("res://scripts/components/FurnitureSeating.gd").access_cells(seat.def, seat.origin_cell, 0):
		if nav.is_walkable(cell): goals[cell] = true
	var probe := {}
	var result := 0
	for i in 4000:
		result = load("res://scripts/components/WorkRouteProbe.gd").advance(probe, pickup, goals.keys()[0], 64, Time.get_ticks_usec() + 250, false, goals)
		if result != nav.ProbeResult.SEARCHING: break
	var walked: float = load("res://scripts/components/DwarfForaging.gd").path_length(pickup, probe.get("path", []))
	var config: Dictionary = worker._food.config
	var reach := float(config.dining_distance)
	_expect(result == nav.ProbeResult.REACHABLE and Vector3(seat.origin_cell - pickup).length() <= reach and walked > reach and walked <= float(config.dining_walk_distance),
		"the table is within reach as the crow flies and a longer walk away (walked %.1f, straight %.1f)" % [walked, Vector3(seat.origin_cell - pickup).length()])
	# A winding route takes some sixty frames to search, a second of the search's two at the
	# game's sixty frames a second; this fixture's usual twentieths would spend three on it.
	_expect(await _food_phase_at_game_rate("eating"), "winding walk: the diner reaches eating")
	var dining = worker._food._dining
	_expect(dining.outcome() == "proper" and dining.choice.get("seat") == seat and dining.choice.get("table") == table,
		"a table within reach is used though the walk to it is longer than the reach")
	await _finish_food()
	_expect(worker._food.last_dining == "proper", "the meal at the far side of the walls is a proper one")
	# The walk keeps a bound of its own: within reach but too long a walk away is left alone.
	# The search is given all the time it wants, so that only the walk's bound can refuse the table.
	var bound: float = float(config.dining_walk_distance)
	var patience: float = float(config.dining_search_seconds)
	config["dining_walk_distance"] = reach
	config["dining_search_seconds"] = 60.0
	_hungry(worker)
	_expect(await _food_phase_at_game_rate("eating"), "bounded walk: the diner still eats")
	_expect(worker._food._dining.outcome() == "neither" and worker._food._dining.elapsed < 60.0, "a walk past its own bound is not taken")
	await _finish_food()
	config["dining_walk_distance"] = bound
	config["dining_search_seconds"] = patience
	for wall: Array in walls:
		for z in range(26, 61):
			for y in range(21, 25): world.set_block(int(wall[0]), y, z, 0)
	await _frames(4)
	_clear_layout()

func _food_phase_at_game_rate(target: String, limit := 6000) -> bool:
	for i in limit:
		if worker._food.state == target: return true
		worker._process(1.0 / 60.0)
		await process_frame
	return false

## The owner's colony at x3 (2026-11-10): with both stools taken, two diners routed to the same
## place at the table; the one that lost it gave the table up and ate where it stood. And the
## search's budget, counted in game seconds, was a third as many frames at x3.
func _place_taken_while_looking() -> void:
	_clear_layout()
	var table = _piece(TABLE, Vector3i(44, 20, 41))
	clock_node.set_speed(3)
	_store(BLUEBERRY, 4)
	_hungry(worker)
	_expect(await _food_phase("dining"), "taken place: the diner collects its portion")
	var dining = worker._food._dining
	for i in 200:
		if not dining.candidates.is_empty() or not dining.choice.is_empty(): break
		worker._process(.05)
		await process_frame
	_expect(dining.choice.is_empty() and dining.candidates.size() == 1 and dining.candidates[0].get("table") == table and dining.candidates[0].get("seat") == null,
		"with no stool the diner's one candidate is a place at the table")
	# Where its route will end: the same search, run to its end now, before the diner starts its own.
	var nav := root.get_node("NavGrid")
	var goals: Dictionary = (dining.candidates[0].goals as Dictionary).duplicate()
	var probe := {}
	var result := 0
	for i in 4000:
		result = load("res://scripts/components/WorkRouteProbe.gd").advance(probe, worker.current_cell(), goals.keys()[0], int(worker._food.config.search_nodes),
			Time.get_ticks_usec() + 250, false, goals)
		if result != nav.ProbeResult.SEARCHING: break
	var first: Vector3i = probe.path.back() if not (probe.get("path", []) as Array).is_empty() else worker.current_cell()
	table.dining_claims[first] = 9999   # another diner takes that place while this one still looks
	_expect(await _food_phase("eating"), "taken place: the diner still reaches eating")
	_expect(dining.outcome() == "table_only" and dining.goal != first and int(table.dining_claims.get(dining.goal, -1)) == worker.dwarf_id,
		"a diner whose place was taken while it looked takes another place at the same table (first %s, took %s)" % [first, dining.goal])
	await _finish_food()
	table.dining_claims.erase(first)
	_clear_layout()
	var search = load("res://scripts/components/DwarfDining.gd").new(worker)
	search.tick(.15)
	_expect(is_equal_approx(search.elapsed, .05), "the search's budget is real time: x3 does not spend it three times as fast")
	search.release()
	clock_node.set_speed(1)

func _interruptions() -> void:
	_clear_layout()
	var chair = _piece(CHAIR,Vector3i(45,20,40))
	var table = _piece(TABLE,Vector3i(44,20,41))
	_expect(await _meal_start(),"first dwarf starts proper meal")
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	second = factory.spawn(factory.generate(142,{}),142)
	scene.add_child(second)
	second.set_process(false)
	second.position = Vector3(41.5,21,42.5)
	tasks.register_dwarf(second)
	_hungry(second)
	for i in 600:
		second._process(.05)
		await process_frame
		if second._food.state=="eating": break
	_expect(second._food.state=="eating" and second._food._dining.choice.get("seat")==null,"second diner cannot steal occupied chair")
	second._food.cancel()
	var before := _food_total(BLUEBERRY)
	worker._food.cancel()
	_expect(chair.idle_seat_owner<0 and table.dining_claims.is_empty(),"cancel releases seat and table claims")
	_expect(_food_total(BLUEBERRY)==before,"interrupted serving remains one real recoverable portion")
	_expect(worker._body.position.is_zero_approx(),"interrupted seating restores body")
	_clear_layout()
	chair = _piece(CHAIR,Vector3i(45,20,40))
	table = _piece(TABLE,Vector3i(44,20,41))
	_expect(await _meal_start(),"new proper meal")
	furniture.dev_remove_installed(table.installed_id)
	worker._process(.1)
	_expect(worker._food._dining.outcome()=="seat_only" and chair.idle_seat_owner==worker.dwarf_id,"table loss preserves usable chair and changes outcome")
	chair.set_uninstall(true)
	worker._process(.1)
	_expect(worker._food._dining.outcome()=="neither" and chair.idle_seat_owner<0,"seat removal releases safely and falls back")
	await _finish_food()

func _foraging() -> void:
	_clear_layout()
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	clock_node.restore_state({"year":1,"season":"summer","day":1,"hour":12,"speed":1,"paused":false})
	details.register_record({"id":bush_id,"definition":"base:flora:blueberry_bush","origin":Vector3i(45,20,40),"variant":0,"yaw":0})
	_hungry(worker)
	worker._process(.05)
	await _finish_food()
	_expect(worker._food.last_meal.is_empty() and details._forage_claims.is_empty(),"ordinary hunger does not pick a bush")
	var events := root.get_node("EventLog")
	events.check_food()
	var shortage: Dictionary = events.warning("food")
	_expect(shortage.get("text","")=="1 dwarf cannot find reachable food." and shortage.get("dwarves",[])==[worker.dwarf_id],"failed searches pin the food warning in Events")
	_store(APPLE,4)
	_hungry(worker); worker._food.value=.1
	_expect(await _food_phase("eating"),"famished dwarf still takes stored food first")
	_expect(worker._food._quote.key==APPLE and details.forage_available(bush_id),"emergency never overrides reachable storage")
	events.check_food()
	_expect(events.warning("food").is_empty() and events.entries().any(func(entry:Dictionary)->bool: return entry.id==shortage.get("id",-1) and entry.text=="1 dwarf could not find reachable food."),
		"collecting food resolves the shortage warning, in past words")
	await _finish_food()
	_clear_food()
	worker._food.last_meal=""
	_hungry(worker); worker._food.value=.1
	_expect(await _forage_phase("picking"),"famished dwarf reaches nearby bush")
	worker._process(.2)
	var progress: float = details._state(bush_id).harvest_work_seconds
	clock_node.set_paused(true)
	worker._process(2)
	_expect(details._state(bush_id).harvest_work_seconds==progress,"pause freezes emergency harvest")
	clock_node.set_paused(false)
	_expect(progress>0 and not details.claim_forage(bush_id,999),"crop has exclusive claim and persistent work")
	worker._food.cancel()
	_expect(details._forage_claims.is_empty() and details._state(bush_id).harvest_work_seconds==progress,"interruption preserves crop work and releases claim")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(details.serialize_state()))
	# Restoration validates stable seeded IDs; fixture uses the real shrub category.
	details.restore_state(snapshot)
	_expect(is_equal_approx(float(details._state(bush_id).get("harvest_work_seconds",0)),progress),"partial emergency harvest survives save/load")
	_hungry(worker); worker._food.value=.1
	clock_node.set_speed(3)
	_expect(await _food_phase("eating"),"resumed emergency crop yields a carried serving")
	clock_node.set_speed(1)
	_expect(_food_total(BLUEBERRY)==2 and worker._carried_entries.size()==1 and drops.quantity_of(worker._food.portion)==1,"one carried portion plus the normal two surplus berries")
	_expect(not details.forage_available(bush_id) and not details.claim_forage(bush_id,999),"committed crop enters normal regrowth immediately")
	await _finish_food()
	_expect(_food_total(BLUEBERRY)==2 and worker._food.last_meal==BLUEBERRY,"only one harvested berry is consumed")
	_expect(details.take_forage_portion(bush_id,worker.dwarf_id,worker.current_cell())==null,"stale completion cannot create more berries")
	# No self-care harvesting of an ordered plant, off-season crop or distant bush.
	details._changes.erase(bush_id)
	_expect(details.designate_detail(bush_id,"harvest_plants"),"ordinary harvest can reserve ripe crop")
	_expect(not details.forage_available(bush_id),"designated crop is excluded from personal foraging")
	details.cancel_clearing(bush_id)
	clock_node.season="winter"
	_expect(not details.forage_available(bush_id),"off-season fruit is excluded")
	clock_node.season="summer"
	_clear_food()
	worker.position=Vector3(10.5,21,40.5)
	_hungry(worker); worker._food.value=.1
	worker._process(.05)
	await _finish_food()
	_expect(details.forage_available(bush_id) and not worker.is_eating(),"emergency search does not walk across the map")
	var travel = load("res://scripts/components/DwarfForaging.gd")
	_expect(travel.path_length(Vector3i.ZERO,[Vector3i(12,0,0),Vector3i(12,0,12),Vector3i(1,0,1)])>24,"range measures routed travel, not straight-line endpoint")
	details.free()

func _forage_phase(target: String) -> bool:
	for i in 600:
		worker._process(.05)
		await process_frame
		if worker._food.state=="foraging" and worker._food._foraging.state==target: return true
	return false

func _effects_and_save() -> void:
	_clear_food()
	worker._food.value=1
	worker._mood.record_dining("neither")
	_expect(is_equal_approx(worker._mood.value(),.42),"neither is minus eight, not stacked")
	worker._mood.record_dining("neither")
	_expect(is_equal_approx(worker._mood.value(),.42),"repeat dining thoughts replace")
	worker._mood.tick(3)
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(worker.serialize_state()))
	worker._mood.record_dining("proper")
	worker.restore_saved_runtime(snapshot)
	_expect(is_equal_approx(worker._mood.dining_memory_hours,5) and is_equal_approx(worker._mood.value(),.42),"dining thought and remaining time survive current save")
	worker._mood.tick(5)
	_expect(is_equal_approx(worker._mood.value(),.5),"dining thought expires after eight game hours")
	worker._mood.record_dining("seat_only")
	worker._mood.record_dining("proper")
	_expect(is_equal_approx(worker._mood.value(),.5),"proper meal clears previous penalty")
	for entry in [[1.0,1.0,.5],[.3,.9,.45],[.1,.75,.35]]:
		worker._food.value=entry[0]
		worker._task_phase=worker.TaskPhase.UNINSTALL_WORKING
		worker._exec_timer=10
		worker._work_execution.tick(1)
		_expect(is_equal_approx(worker._exec_timer,10-entry[1]),"productive labor gets correct hunger multiplier")
		_expect(is_equal_approx(worker._mood.value(),entry[2]),"live hunger mood tier")
	worker._task_phase=worker.TaskPhase.NONE
	worker._food.value=1
	_expect(worker._food.work_multiplier()==1 and is_equal_approx(worker._mood.value(),.5),"feeding removes hunger effects immediately")

func _presentation() -> void:
	_clear_layout()
	_piece(CHAIR,Vector3i(45,20,40))
	_piece(TABLE,Vector3i(44,20,41))
	_expect(await _meal_start(),"visual fixture reaches real dining")
	worker._process(.9)
	_expect(is_instance_valid(worker._food._serving) and worker._food._serving.visible and not worker._food.portion.visible,"visible serving replaces shipping-crate artwork")
	_expect(not worker._body.position.is_zero_approx(),"dining poses body into real chair")
	var inspector=load("res://scripts/ui/DwarfInspectorPanel.gd").new()
	var layer:=CanvasLayer.new(); scene.add_child(layer); layer.add_child(inspector)
	inspector.position=Vector2(20,75)
	inspector.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker),false)
	_expect(inspector._food_effects.text.contains("10%"),"inspector exposes work-speed effect")
	if "--capture" in OS.get_cmdline_user_args():
		camera.position=Vector3(52,29,52)
		camera.look_at(Vector3(45.5,22.5,41.5))
		camera.size=17
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size=size
			await _frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/dining_20261012/dining_%d.png" % size.x)
	await _finish_food()
	inspector.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker),false)
	_expect(inspector._food.panel.tooltip_text.contains("Blueberry") and inspector._food.panel.tooltip_text.contains("seated at a table"),"Food reports the real last meal and arrangement")
	if "--capture" in OS.get_cmdline_user_args():
		_clear_food()
		_hungry(worker)
		worker._process(.05)
		await _finish_food()
		root.get_node("EventLog").check_food()
		inspector.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker),false)
		inspector._show_tab(0)
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size=size
			await _frames(4)
			inspector._scroll.scroll_vertical=120
			await _frames(3)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/dining_20261012/details_warning_%d.png" % size.x)
