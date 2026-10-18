extends "res://scripts/tests/DwarfFoodTest.gd"

const CHAIR := "base:furniture:wooden_chair"
const TABLE := "base:furniture:wooden_table"
const STOOL := "base:furniture:log_chair"
const LOG_BENCH := "base:furniture:bench"
var details
var bush_id := "blueberry:1234:1:1"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Dining test timed out"); quit(1))
	await _setup_crafting_fixture()
	await _arrangements()
	await _interruptions()
	await _foraging()
	_effects_and_save()
	await _presentation()
	for failure in failures: push_error(failure)
	print("DWARF_DINING_OK: four dining outcomes, seat contention, interruption, emergency crops, claims, conservation, season, saved work, mood, work speed and UI" if failures.is_empty() else "DWARF_DINING_FAIL")
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
		if expected in ["proper","table_only"]: _piece(TABLE,Vector3i(45,20,42))
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
			for i in 12:
				worker._process(.05)
				if seat.idle_seat_owner<0: break
			_expect(seat.idle_seat_owner<0 and worker._body.position.is_zero_approx(),"standing releases the meal's seat")
		for piece in furniture._installed.values():
			_expect(piece.dining_claims.is_empty(),"finished meal releases its dining-table claim")
	# The back of a chair beside a table does not count as dining at that table.
	_clear_layout()
	_piece(CHAIR,Vector3i(45,20,40),2)
	_piece(TABLE,Vector3i(45,20,42))
	_expect(await _meal_start(),"reversed chair remains usable")
	_expect(worker._food._dining.outcome()!="proper","backed chair must face table; obstructed seating falls back")
	await _finish_food()
	for key: String in [STOOL,LOG_BENCH]:
		_clear_layout()
		var seat = _piece(key,Vector3i(45,20,40))
		_piece(TABLE,Vector3i(45,20,42))
		_expect(await _meal_start(),"simple seat reaches eating")
		_expect(worker._food._dining.outcome()=="proper",key+" can dine at a properly spaced table")
		worker._process(.75)
		var seated_body: Vector3 = worker._body.position
		await _finish_food()
		_expect(worker._body.position.is_equal_approx(seated_body) and seat.idle_seat_owner==worker.dwarf_id,key+" keeps its meal pose and claim on completion")
		_expect(worker.walk_to(Vector3i(40,20,39)),"player movement can interrupt rest after eating")
		_expect(seat.idle_seat_owner<0 and not worker._idle_behavior.active() and worker._body.position.is_zero_approx(),"movement after a meal releases the transferred seat and pose")

func _interruptions() -> void:
	_clear_layout()
	var chair = _piece(CHAIR,Vector3i(45,20,40))
	var table = _piece(TABLE,Vector3i(45,20,42))
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
	table = _piece(TABLE,Vector3i(45,20,42))
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
	var warning = load("res://scripts/ui/ColonyFoodWarning.gd").new()
	dock._root.add_child(warning)
	warning.refresh()
	await _frames(3)
	_expect(warning.visible and warning.label.text.contains("1 dwarf"),"failed searches expose a persistent colony warning")
	_expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(warning.get_global_rect()),"food warning stays inside the viewport")
	_store(APPLE,4)
	_hungry(worker); worker._food.value=.1
	_expect(await _food_phase("eating"),"famished dwarf still takes stored food first")
	_expect(worker._food._quote.key==APPLE and details.forage_available(bush_id),"emergency never overrides reachable storage")
	warning.refresh()
	_expect(not warning.visible,"collecting food clears the shortage warning")
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
	warning.queue_free()
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
		worker._task_phase=worker.TaskPhase.EXECUTING
		worker._exec_timer=10
		worker._work_execution.tick(worker,1)
		_expect(is_equal_approx(worker._exec_timer,10-entry[1]),"productive labor gets correct hunger multiplier")
		_expect(is_equal_approx(worker._mood.value(),entry[2]),"live hunger mood tier")
	worker._task_phase=worker.TaskPhase.NONE
	worker._food.value=1
	_expect(worker._food.work_multiplier()==1 and is_equal_approx(worker._mood.value(),.5),"feeding removes hunger effects immediately")

func _presentation() -> void:
	_clear_layout()
	_piece(CHAIR,Vector3i(45,20,40))
	_piece(TABLE,Vector3i(45,20,42))
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
	_expect(inspector._meal.text.contains("Blueberry") and inspector._meal.text.contains("seated at a table"),"last-meal panel reports real food and arrangement")
	if "--capture" in OS.get_cmdline_user_args():
		_clear_food()
		_hungry(worker)
		worker._process(.05)
		await _finish_food()
		dock._root.get_node("ColonyFoodWarning").refresh()
		inspector.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker),false)
		inspector._show_tab(1)
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			root.size=size
			await _frames(4)
			inspector._scroll.scroll_vertical=120
			await _frames(3)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/dining_20261012/details_warning_%d.png" % size.x)
