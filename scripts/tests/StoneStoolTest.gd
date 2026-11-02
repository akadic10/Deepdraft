extends "res://scripts/tests/DwarfDiningTest.gd"

## The stone stool (doc 293, step 3), the Stonemason's first piece. Only a Stonemason makes it, from
## one Rough Stone at the mason's bench: with no bench the order needs one, and the stone lies on
## the slab in front of them while the maul knocks it square. It seats as the log stool does: it
## takes a dining table's guides beside log stools, a dwarf eats there on it in the table's
## posture, it is a game seat at the board, and its Place card says it snaps to tables. A save
## keeps it at its table.
const STONE_STOOL := "base:furniture:stone_stool"
const STONE_STOOL_ITEM := "base:resources:furniture:stone_stool"
const STONE_STOOL_RECIPE := "base:recipe:worker:stone_stool"
const MASON_BENCH := "base:furniture:mason_bench"
const STONEMASON := "base:profession:stonemason"
const GAME := "base:furniture:board_game_table"


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Stone stool test timed out"); quit(1))
	await _setup_crafting_fixture()
	var recipe: Dictionary = crafting.recipes[STONE_STOOL_RECIPE]
	var keys: Array = crafting.ingredient_keys(recipe)
	_expect(String(recipe.get("section", "")) == "stonemason" and recipe.workshop == MASON_BENCH and String(recipe.category) == "Dining"
		and keys.size() == 1 and keys[0] == STONE and int(recipe.ingredient_count) == 1, "the stone stool: one Rough Stone at the mason's bench, on the Stonemason's page: %s" % [keys])
	var definition: Dictionary = furniture.get_defs()[STONE_STOOL]
	var log_stool: Dictionary = furniture.get_defs()[STOOL]
	_expect(definition.seating_chair == log_stool.seating_chair and definition.footprint == log_stool.footprint
		and definition.collision_regions == log_stool.collision_regions and not definition.has("material_group"), "it seats as the log stool does, and keeps no wood")
	var placed: Array = root.get_node("UIRegistry").get_place_catalog().get("items", []).filter(func(entry): return entry.key == STONE_STOOL)
	_expect(placed.size() == 1 and placed[0].category == "dining" and root.get_node("DwarfAssets").get_taste_data().things.has(STONE_STOOL),
		"Place files it under Dining, and a dwarf may have a taste for it")
	# A Stonemason and no mason's bench yet: the order needs one.
	worker.profession = STONEMASON
	tasks.work_policy_changed()
	drops.spawn_drop(STONE, 1, Vector3i(42, 21, 40))
	var id: int = crafting.queue_order(STONE_STOOL_RECIPE, 1)
	for i in range(20): await _tick()
	var order = crafting.get_order(id)
	var status: String = crafting.status(order, inventory_script.snapshot(drops, furniture))
	_expect(status == "Needs a mason's bench" and order.worker_id < 0 and _count(STONE) == 1, "without a mason's bench the stool waits for one: %s" % status)
	# At the bench the stone lies on the slab in front of the Stonemason, and the maul knocks it.
	var bench = _piece(MASON_BENCH, Vector3i(45, 20, 42))
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "the Stonemason carries the stone to the mason's bench and starts")
	worker._process(.3)
	var stone: Node3D = worker._work_execution._fetch_item
	var bounds: AABB = worker._carry_pose.item_bounds(stone)
	var at: Vector3 = stone.global_position
	var lying := is_equal_approx(at.y + bounds.position.y, bench.node.global_position.y + float(bench.def.crafting_surface_height))
	var inside := at.x + bounds.position.x >= 45.0 and at.x + bounds.end.x <= 48.0 and at.z + bounds.position.z >= 42.0 and at.z + bounds.end.z <= 43.0
	_expect(lying and inside, "the Rough Stone lies on the slab, all of it inside the bench: %s %s" % [at, bounds])
	_expect(at.distance_to(worker.global_position) < 1.6, "in front of the Stonemason: %.2f away" % at.distance_to(worker.global_position))
	_expect(worker._felling_pose.axe.scene_file_path.ends_with("stone_maul.glb"), "the maul knocks it square")
	_expect(await _completed(id) and _count(STONE_STOOL_ITEM) == 1 and _count(STONE) == 0 and int(worker.profession_experience.get(STONEMASON, 0)) == 1,
		"one Rough Stone makes one packed stone stool, and one experience")
	# A dining table's guides take it beside log stools, placed and installed for real. Clearing the
	# layout clears loose goods too, so the packed stool is laid down again.
	_clear_layout()
	drops.spawn_drop(STONE_STOOL_ITEM, 1, Vector3i(42, 21, 44))
	var table = _piece(TABLE, Vector3i(46, 20, 42))
	var slots: Array = furniture._seating.slots_for(table)
	var log_seat = _piece(STOOL, slots[1].origin, slots[1].yaw)
	furniture.activate_for(STONE_STOOL, true)
	furniture._seating.resolve(slots[0].origin)
	var snap: Dictionary = furniture._seating.snap.duplicate()
	_expect(snap.get("origin") == slots[0].origin and snap.get("yaw") == slots[0].yaw, "the stone stool snaps to a dining table's guide")
	_expect(not furniture._seating.guides.is_empty() and furniture._seating.guides.all(func(guide): return guide.scene_file_path == String(definition.model)),
		"the table's free guides show stone stools while one is placed")
	furniture._hover_cell = slots[0].origin
	furniture._yaw = slots[0].yaw
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(STONE_STOOL) and _count(STONE_STOOL_ITEM) == 0, "a dwarf installs it at the guide")
	var stone_seat = furniture.get_installed_at(slots[0].origin)
	var seats: Array = furniture._seating.installed_seats(table.installed_id).map(func(slot): return furniture.get_installed(slot.chair_id).furniture_key)
	_expect(stone_seat != null and stone_seat.furniture_key == STONE_STOOL and stone_seat.yaw_steps == slots[0].yaw and seats.size() == 2
		and STONE_STOOL in seats and STOOL in seats, "the table seats a stone stool and a log stool together: %s" % [seats])
	_expect(furniture._seating.chair_settings(stone_seat).has("meal_hand_lift"), "at the table the stone stool takes the table's posture")
	# A dwarf eats there on it, in the table's posture.
	log_seat.idle_seat_owner = 1900   # the log stool is taken
	_expect(await _meal_start() and worker._food._dining.outcome() == "proper" and stone_seat.idle_seat_owner == worker.dwarf_id,
		"a hungry dwarf eats at the table on the stone stool")
	await _finish_food()
	_expect(worker._food.last_dining == "proper", "a proper meal")
	worker._idle_behavior.cancel()
	log_seat.idle_seat_owner = -1
	# A save keeps it at its table.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for installed_id: int in furniture._installed.keys(): furniture._teardown_installed(installed_id, false)
	furniture.restore_state(saved)
	var tables: Array = furniture._installed.values().filter(func(piece): return piece.furniture_key == TABLE)
	seats = furniture._seating.installed_seats(tables[0].installed_id).map(func(slot): return furniture.get_installed(slot.chair_id).furniture_key) if tables.size() == 1 else []
	_expect(STONE_STOOL in seats and seats.size() == 2, "a save keeps the stone stool at its table: %s" % [seats])
	# The board: a game seat, and its window asks for any stool.
	_clear_layout()
	var game = _piece(GAME, Vector3i(46, 20, 42))
	var rows: Array = furniture.get_explorer_data("installed:%d" % game.installed_id).rows
	_expect(rows.has(["Game", "Needs a stool"]), "a board with no seat needs a stool: %s" % [rows])
	var game_slots: Array = furniture._seating.slots_for(game)
	var player = _piece(STONE_STOOL, game_slots[0].origin, game_slots[0].yaw)
	rows = furniture.get_explorer_data("installed:%d" % game.installed_id).rows
	_expect(furniture._seating.is_recreation_seat(player) and rows.has(["Game", "Ready for solo or shared play"]), "the stone stool is a game seat at the board: %s" % [rows])
	# The Place cards: it snaps to tables, as the log stool does; the board takes separate stools.
	dock.show()
	dock._open_place_catalog()
	dock._place_catalog.show_all = true
	dock._place_catalog._all_toggle.set_pressed_no_signal(true)
	var facts := {}
	for key: String in [STONE_STOOL, STOOL, GAME]:
		dock._place_catalog._select(key)
		await _frames(4)
		facts[key] = dock._place_catalog.facts_text()
	_expect(String(facts[STONE_STOOL]).contains("Snaps to tables") and String(facts[STOOL]).contains("Snaps to tables")
		and String(facts[GAME]).contains("2 separate stools"), "the Place cards: %s" % [facts])
	dock._place_window.hide()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STONE_STOOL_OK: Stonemasons only, at the mason's bench, the stone on the slab, the maul, a dining table's guides beside log stools, a meal on it, saves, the board and the Place cards")
	quit(0 if failures.is_empty() else 1)
