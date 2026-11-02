extends "res://scripts/tests/DwarfDiningTest.gd"

## Grilling at the campfire (doc 290): a hungry dwarf takes a fresh fish to a burning campfire,
## grills it on a stick and eats it there. The meal fills as the raw fish does, adds 0.05 Rest
## and leaves "Grilled fish by the fire" in place of the dining memory, or "with company" when
## another dwarf sits by the fire. A cold fire, dried fish, a fire with no room or one beyond the
## meal's reach mean an ordinary meal; a release mid-grill drops the raw fish whole; the
## memories save.
const PERCH := "base:resources:fish:perch"
const DRIED := "base:resources:fish:dried_fish"


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Campfire grill test timed out"); quit(1))
	await _setup_crafting_fixture()
	# Hold food and Rest still, so the meal's own effects measure exactly.
	worker._sleep_drain = 0.0
	worker._food.config = worker._food.config.duplicate(true)
	worker._food.config.drain_per_hour = 0.0
	await _grill_alone()
	await _grill_with_company()
	await _ordinary_meals()
	await _release_mid_grill()
	_saves()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CAMPFIRE_GRILL_OK: a grilled perch at a burning fire, its food, Rest and memory, company, four ordinary meals, a release and saves")
	quit(0 if failures.is_empty() else 1)


func _lit_fire(origin := Vector3i(48, 20, 44)):
	var fire = _piece(CAMPFIRE, origin)
	furniture.get_fires().light(fire, PINE, "base:material:pine")
	return fire


func _reset_mood() -> void:
	var mood = worker._mood
	mood.grill_memory_hours = 0.0
	mood.grill_together_memory_hours = 0.0
	mood.dining_memory_hours = 0.0
	mood.dining_outcome = ""


func _grill_alone() -> void:
	_clear_layout()
	_reset_mood()
	var fire = _lit_fire()
	var stool = _piece(STOOL, Vector3i(49, 20, 42), 1)
	_store(PERCH, 2)
	_hungry(worker)
	worker.sleep = 0.5
	_expect(await _food_phase("grilling"), "a hungry dwarf takes a fresh perch to the burning campfire and grills it")
	var food = worker._food
	_expect(food.grilled and food._dining.choice.get("seat") == stool and stool.idle_seat_owner == worker.dwarf_id
		and food.grilling_fire_id() == fire.installed_id, "on the stool that faces the fire")
	var pose = worker.get_grill_pose()
	var sticks: Dictionary = root.get_node("DwarfAssets").grill_sticks.get(PERCH, {})
	if not sticks.is_empty():
		_expect(is_instance_valid(pose.tool) and pose.tool.visible and pose._stick == sticks.raw, "the raw perch on its stick, over the flames")
	_expect(await _food_phase("eating"), "the grilled perch is eaten at the fire")
	if not sticks.is_empty():
		_expect(pose._stick == sticks.grilled, "browned before it is eaten")
	await _finish_food()
	_expect(is_equal_approx(food.value, 0.9) and food.last_dining == "fire" and food.last_meal == PERCH, "the meal fills as a raw fish does: 0.3 + 0.6")
	_expect(is_equal_approx(worker.sleep, 0.55), "and adds 0.05 Rest: %.3f" % worker.sleep)
	_expect(is_equal_approx(worker._mood.grill_memory_hours, 12.0) and is_zero_approx(worker._mood.dining_memory_hours),
		"Grilled fish by the fire for 12 game hours, and no dining memory")
	var thought: Array = worker._mood.thoughts().filter(func(row: Dictionary) -> bool: return row.id == "grilled_alone")
	_expect(thought.size() == 1 and int(thought[0].points) == 6 and thought[0].text == "Grilled fish by the fire", "+6 happiness")
	_expect(is_equal_approx(worker._mood.value(), 0.56), "happiness 56: %.3f" % worker._mood.value())
	_expect(bool(food.describe().rested_by_fire) and food.describe().meal.ends_with("Ate grilled fish by the fire"), "the sheet says Rested by the fire")
	_expect(_food_total(PERCH) == 1, "one perch eaten")
	_expect(worker._idle_behavior.state == "sitting" and worker.fire_watched() == fire.installed_id, "they sit on by the fire")
	_expect(not is_instance_valid(pose.tool) or not pose.tool.visible, "the stick is put away")


func _grill_with_company() -> void:
	_clear_layout()
	_reset_mood()
	var fire = _lit_fire()
	_piece(STOOL, Vector3i(49, 20, 42), 1)
	var other_stool = _piece(STOOL, Vector3i(47, 20, 46), 3)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	second = factory.spawn(factory.generate(142, {}), 142)
	scene.add_child(second)
	second.position = Vector3(47.5, 21, 47.5)
	second.set_process(false)
	tasks.register_dwarf(second)
	other_stool.idle_seat_owner = second.dwarf_id
	second._idle_behavior.continue_seated(other_stool, furniture, Vector3i(47, 20, 47), fire.installed_id)
	_expect(second.fire_watched() == fire.installed_id, "a second dwarf sits by the fire")
	_store(PERCH, 1)
	_hungry(worker)
	_expect(await _food_phase("grilling"), "the hungry one grills beside them")
	await _finish_food()
	var thought: Array = worker._mood.thoughts().filter(func(row: Dictionary) -> bool: return row.id == "grilled_together")
	_expect(is_equal_approx(worker._mood.grill_together_memory_hours, 12.0) and thought.size() == 1 and int(thought[0].points) == 8
		and thought[0].text == "Grilled fish with company", "Grilled fish with company: +8")
	_expect(is_equal_approx(worker._mood.value(), 0.58), "only the stronger memory counts: %.3f" % worker._mood.value())
	_clear_food()


func _ordinary_meals() -> void:
	# A cold campfire, by day: the perch is eaten as it is, on the stool facing the fire.
	_clear_layout()
	_reset_mood()
	_piece(CAMPFIRE, Vector3i(48, 20, 44))
	_piece(STOOL, Vector3i(49, 20, 42), 1)
	_store(PERCH, 1)
	_hungry(worker)
	_expect(await _food_phase("eating") and not worker._food.grilled and worker._food._dining.outcome() == "seat_only",
		"a cold campfire grills nothing: the perch is eaten raw on the stool")
	await _finish_food()
	_expect(is_zero_approx(worker._mood.grill_memory_hours) and worker._food.last_dining == "seat_only", "an ordinary meal leaves no grill memory")
	# Dried fish are never grilled, even by a burning fire.
	_clear_layout()
	_reset_mood()
	_lit_fire()
	_piece(STOOL, Vector3i(49, 20, 42), 1)
	_store(DRIED, 1)
	_hungry(worker)
	_expect(await _food_phase("eating") and not worker._food.grilled, "dried fish are eaten as they are")
	await _finish_food()
	# No room at the fire: its stool taken and every place at its sides claimed.
	_clear_layout()
	_reset_mood()
	var full = _lit_fire()
	var taken = _piece(STOOL, Vector3i(49, 20, 42), 1)
	taken.idle_seat_owner = 999
	for cell: Vector3i in full.cells:
		for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			if cell + offset not in full.cells: full.dining_claims[cell + offset] = 999
	_store(PERCH, 1)
	_hungry(worker)
	_expect(await _food_phase("eating") and not worker._food.grilled, "a fire with no room: the perch is eaten as usual")
	await _finish_food()
	_expect(worker._food.last_dining != "fire" and is_zero_approx(worker._mood.grill_memory_hours), "and no grill memory")
	# A fire beyond the meal's reach.
	_clear_layout()
	_reset_mood()
	_lit_fire(Vector3i(90, 20, 44))
	_store(PERCH, 1)
	_hungry(worker)
	_expect(await _food_phase("eating") and not worker._food.grilled, "a burning fire beyond the meal's 32 blocks is passed over")
	await _finish_food()


func _release_mid_grill() -> void:
	_clear_layout()
	_reset_mood()
	_lit_fire()
	_piece(STOOL, Vector3i(49, 20, 42), 1)
	_store(PERCH, 1)
	_hungry(worker)
	_expect(await _food_phase("grilling"), "grilling once more")
	worker._food.cancel()
	var pose = worker.get_grill_pose()
	_expect(_food_total(PERCH) == 1 and is_equal_approx(worker._food.value, 0.3) and is_zero_approx(worker._mood.grill_memory_hours),
		"a release mid-grill drops the raw perch whole: no food, no memory")
	_expect(not is_instance_valid(pose.tool) or not pose.tool.visible, "and puts the stick away")


func _saves() -> void:
	var mood = worker._mood
	mood.grill_memory_hours = 5.0
	mood.grill_together_memory_hours = 3.0
	mood.record_dining("fire")
	var copy = load("res://scripts/components/DwarfMood.gd").new()
	copy.restore(mood.serialize())
	_expect(is_equal_approx(copy.grill_memory_hours, 5.0) and is_equal_approx(copy.grill_together_memory_hours, 3.0)
		and copy.dining_outcome == "fire" and is_zero_approx(copy.dining_memory_hours), "the grill memories and the fire outcome save and load")
