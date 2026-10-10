extends SceneTree

## Headless integration regression for validated save replacement and backup
## recovery. Run from the project root:
##
## godot --headless --path . --script res://scripts/tests/SaveManagerRoundTripTest.gd

const TEST_DIRECTORY := "user://save_manager_round_trip_test"
const TEST_PRIMARY := TEST_DIRECTORY + "/quicksave.json"
const TEST_BACKUP := TEST_DIRECTORY + "/quicksave.backup.json"
const TEST_TEMP := TEST_DIRECTORY + "/quicksave.tmp.json"
const TEST_BACKUP_STAGE := TEST_DIRECTORY + "/quicksave.backup.tmp.json"
const TEST_AUTOSAVE := TEST_DIRECTORY + "/autosave.json"
const TEST_AUTOSAVE_BACKUP := TEST_DIRECTORY + "/autosave.backup.json"
const TEST_AUTOSAVE_TEMP := TEST_DIRECTORY + "/autosave.tmp.json"
const TEST_AUTOSAVE_BACKUP_STAGE := TEST_DIRECTORY + "/autosave.backup.tmp.json"
const WORLD_TIMEOUT_MSEC := 90000
const LOAD_TIMEOUT_MSEC := 90000
const OWNER_GROUP := "save_state_owner"

var _load_completed := false
var _load_succeeded := false
var _load_used_backup := false
var _save_manager: Node = null
var _world_generator: Node = null
var _world_clock: Node = null
## Full scene-owner snapshot captured right after the colony state is built.
## Every load is deep-diffed against it (content equality, not section sizes —
## a chest losing its inventory or a ghost losing its yaw used to pass).
var _content_reference: Dictionary = {}
var _terrain_reference: String = ""
var _fixture_origin: Vector2i


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_save_manager = root.get_node_or_null("SaveManager")
	_world_generator = root.get_node_or_null("WorldGenerator")
	_world_clock = root.get_node_or_null("WorldClock")
	if _save_manager == null or _world_generator == null or _world_clock == null:
		_fail("required autoloads are unavailable")
		return
	_cleanup_test_storage()
	if not bool(_save_manager.call("configure_storage_for_testing", TEST_DIRECTORY)):
		_fail("could not isolate test storage")
		return

	var scene_error := change_scene_to_file("res://scenes/main/debug_world.tscn")
	if scene_error != OK:
		_fail("could not load debug_world.tscn (%s)" % error_string(scene_error))
		return
	await process_frame
	await process_frame
	if not await _wait_for_world_ready(WORLD_TIMEOUT_MSEC):
		_fail("world generation timed out")
		return

	var expected_seed := int(_world_generator.get("world_seed"))
	_terrain_reference = _terrain_fingerprint()
	if not _choose_fixture_origin():
		_fail("could not find natural ground for the save fixture")
		return
	var setup_error := _build_nonempty_colony_state()
	if not setup_error.is_empty():
		_fail(setup_error)
		return
	_content_reference = _collect_scene_state()

	# Advancing the timer by one interval must write only the independent
	# autosave slot and must not mutate authoritative scene state.
	var scene_before_autosave := JSON.stringify(_collect_scene_state())
	_save_manager.call("_tick_autosave", 300.0)
	if not FileAccess.file_exists(TEST_AUTOSAVE):
		_fail("five-minute timer did not create an autosave")
		return
	if FileAccess.file_exists(TEST_PRIMARY):
		_fail("autosave overwrote or created the manual quick-save slot")
		return
	var autosave_result: Dictionary = _save_manager.call("_read_snapshot", TEST_AUTOSAVE)
	if not bool(autosave_result.get("ok", false)):
		_fail("autosave did not validate")
		return
	_save_manager.call("_tick_autosave", 300.0)
	if not FileAccess.file_exists(TEST_AUTOSAVE_BACKUP):
		_fail("second autosave did not rotate the previous autosave to backup")
		return
	if scene_before_autosave != JSON.stringify(_collect_scene_state()):
		_fail("autosaving mutated authoritative scene state")
		return

	var scene_before := JSON.stringify(_collect_scene_state())
	if not bool(_save_manager.call("request_save")):
		_fail("first validated save failed")
		return
	var scene_after := JSON.stringify(_collect_scene_state())
	if scene_before != scene_after:
		_fail("saving mutated authoritative scene state")
		return

	# The second save must rotate the first valid snapshot to the backup.
	_world_clock.call("restore_state", {
		"day": 9,
		"season": "winter",
		"year": 4,
		"hour": 18.5,
		"speed": 3.0,
		"paused": true,
	})
	if not bool(_save_manager.call("request_save")):
		_fail("second save/backup rotation failed")
		return
	if not FileAccess.file_exists(TEST_BACKUP):
		_fail("validated backup was not created")
		return

	# The autosave must be independently loadable and must not use the manual
	# primary or backup created above.
	# Furniture added after the save must leave no stale light-blocking doors
	# or heat/light registrations when an earlier world is restored.
	var later_furniture := _owner("furniture")
	for pair in [["base:furniture:door", 36], ["base:furniture:brazier", 38]]:
		later_furniture.call("_install", pair[0], later_furniture.call("get_defs")[pair[0]], _surface_cell(pair[1], 0), 0)
	_load_completed = false
	_load_succeeded = false
	_load_used_backup = false
	_save_manager.connect("load_finished", _on_load_finished, CONNECT_ONE_SHOT)
	if not bool(_save_manager.call("request_load_autosave")):
		_fail("autosave load did not start")
		return
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC):
		_fail("autosave load timed out")
		return
	if not _load_succeeded or _load_used_backup:
		_fail("autosave did not load from its independent primary slot")
		return
	var autosave_verification_error := _verify_restored_state(expected_seed)
	if not autosave_verification_error.is_empty():
		_fail("autosave: %s" % autosave_verification_error)
		return
	var autosave_content_diff := _deep_diff(_content_reference, _collect_scene_state(), "scene")
	if not autosave_content_diff.is_empty():
		_fail("autosave content did not round-trip — %s" % autosave_content_diff)
		return

	# Fault injection stays inside SaveManager, the sole save-file I/O owner.
	var corrupt_error := String(_save_manager.call("_write_text_file", TEST_PRIMARY, "{invalid json"))
	if not corrupt_error.is_empty():
		_fail("could not inject a corrupt primary: %s" % corrupt_error)
		return

	_load_completed = false
	_load_succeeded = false
	_load_used_backup = false
	_save_manager.connect("load_finished", _on_load_finished, CONNECT_ONE_SHOT)
	if not bool(_save_manager.call("request_load")):
		_fail("backup load did not start")
		return
	if not await _wait_for_load(LOAD_TIMEOUT_MSEC):
		_fail("backup load timed out")
		return
	if not _load_succeeded or not _load_used_backup:
		_fail("load did not complete through the backup path")
		return

	var verification_error := _verify_restored_state(expected_seed)
	if not verification_error.is_empty():
		_fail(verification_error)
		return
	var backup_content_diff := _deep_diff(_content_reference, _collect_scene_state(), "scene")
	if not backup_content_diff.is_empty():
		_fail("backup-load content did not round-trip — %s" % backup_content_diff)
		return

	var repaired_primary: Dictionary = _save_manager.call("_read_snapshot", TEST_PRIMARY)
	if not bool(repaired_primary.get("ok", false)):
		_fail("backup load did not repair the primary slot")
		return

	var inflight_error := _run_inflight_carried_case()
	if not inflight_error.is_empty():
		_fail(inflight_error)
		return

	print("SAVE_MANAGER_ROUND_TRIP_OK")
	_cleanup_and_quit(0)


func _build_nonempty_colony_state() -> String:
	var mining := _owner("mining")
	var flora := _owner("flora")
	var flag := _owner("settlement_flag")
	var stockpiles := _owner("stockpiles")
	var furniture := _owner("furniture")
	var items := _owner("items")
	var dwarves := _owner("dwarves")
	var camera := _owner("camera")
	var slice := _owner("slice")
	var crafting := _owner("worker_crafting")
	var details := _owner("surface_details")
	if [mining, flora, flag, stockpiles, furniture, items, dwarves, camera, slice, crafting, details].has(null):
		return "one or more save-state owners are missing"
	details.call("initialize_layout")
	var detail_ids: Array = details.get("_records").keys().filter(func(id): return String(id).begins_with("boulder:"))
	detail_ids.sort()
	if detail_ids.size() < 3:
		return "not enough generated boulders for save fixture"
	var scree_ids: Array = details.get("_records").keys().filter(func(id): return String(id).begins_with("scree:"))
	scree_ids.sort()
	if scree_ids.size() < 3: return "not enough generated scree for save fixture"
	var shrub_ids: Array = details.get("_records").keys().filter(func(id): return String(id).begins_with("elderberry:"))
	shrub_ids.sort()
	if shrub_ids.size() < 4: return "not enough generated elderberries for save fixture"
	var flower_ids: Array = details.get("_records").keys().filter(func(id): return String(id).begins_with("flowers:"))
	flower_ids.sort()
	if flower_ids.size() < 3: return "not enough generated flowers for save fixture"
	var reed_ids: Array = details.get("_records").keys().filter(func(id): return String(id).begins_with("reeds:"))
	reed_ids.sort()
	if reed_ids.size() < 3: return "not enough generated reeds for save fixture"
	details.call("restore_state", {"changes": [
		{"id": reed_ids[0], "removed": true, "reason": "cleared", "work_seconds": 1.5},
		{"id": reed_ids[1], "removed": false, "designated": true, "work_seconds": .5},
		{"id": reed_ids[2], "removed": false, "designated": false, "work_seconds": .75},
		{"id": flower_ids[0], "removed": true, "reason": "cleared", "work_seconds": 1.5},
		{"id": flower_ids[1], "removed": false, "designated": true, "work_seconds": .5},
		{"id": flower_ids[2], "removed": false, "designated": false, "work_seconds": .75},
		{"id": detail_ids[0], "removed": true, "reason": "cleared", "work_seconds": 7.0},
		{"id": detail_ids[1], "removed": false, "designated": true, "work_seconds": 2.25},
		{"id": detail_ids[2], "removed": false, "designated": false, "work_seconds": 1.5},
		{"id": scree_ids[0], "removed": true, "reason": "cleared", "work_seconds": 3.0},
		{"id": scree_ids[1], "removed": false, "designated": true, "work_seconds": 1.25},
		{"id": scree_ids[2], "removed": false, "designated": false, "work_seconds": .5},
		{"id": shrub_ids[0], "removed": true, "reason": "cleared", "action": "clear", "work_seconds": 2.0},
		{"id": shrub_ids[1], "removed": false, "designated": true, "action": "harvest", "work_seconds": 1.25, "clear_work_seconds": .4},
		{"id": shrub_ids[2], "removed": false, "designated": false, "action": "harvest", "work_seconds": .75},
		{"id": shrub_ids[3], "removed": false, "designated": false, "action": "harvest", "work_seconds": 0, "harvested_cycle": "3:autumn"},
	]})
	crafting.restore_state({"orders":[
		{"recipe":"base:recipe:worker:crude_workbench","quantity":2,"maintain":false,"paused":true,"progress":2.25,
			"allowed_ingredients":["base:resources:wood:pine_log","base:resources:wood:juniper_log"]},
		{"recipe":"base:recipe:worker:wooden_torch","quantity":8,"maintain":true,"paused":false,"progress":0.0,
			"allowed_ingredients":["base:resources:wood:apple_wood"]},
		{"recipe":"base:recipe:worker:carpentry_kit","quantity":1,"maintain":false,"paused":true,"progress":3.5,
			"allowed_ingredients":["base:resources:wood:oak_log"]}]})

	var flag_cell := _surface_cell(0, 0)
	var dwarf_cell := _surface_cell(2, 0)
	var stockpile_cell := _surface_cell(4, 0)
	var furniture_cell := _surface_cell(6, 0)
	var ghost_cell := _surface_cell(8, 0)
	var item_cell := _surface_cell(10, 0)
	var mined_cell := _surface_cell(12, 0)
	var designated_cell := _surface_cell(14, 0)
	# Five authoritative forestry states, including picked/partial juniper crops.
	# The focused felling/harvest tests cover real
	# workers/visuals; this regression verifies the actual save/reload pipeline.
	flora.call("restore_state", {"trees": [
		{"species": "base:flora:oak_tree", "stage": "mature", "origin": _pack_v3i(_surface_cell(20, 0)),
			"work_seconds": 1.25, "designated": true, "felled": false},
		{"species": "base:flora:pine_tree", "stage": "mature", "origin": _pack_v3i(_surface_cell(24, 0)),
			"work_seconds": .75, "designated": false, "felled": false},
		{"species": "base:flora:apple_tree", "stage": "mature", "origin": _pack_v3i(_surface_cell(28, 0)),
			"work_seconds": 8.0, "designated": false, "felled": true},
		{"species": "base:flora:juniper_tree", "stage": "mature", "origin": _pack_v3i(_surface_cell(32, 0)),
			"work_seconds": 0.0, "action": "harvest", "harvested_cycle": "3:autumn", "harvest_work_cycle": "3:autumn", "designated": false},
		{"species": "base:flora:juniper_tree", "stage": "ancient", "origin": _pack_v3i(_surface_cell(36, 0)),
			"work_seconds": .75, "action": "harvest", "harvest_work_cycle": "3:autumn", "fell_work_seconds": .5, "designated": true},
	]})

	mining.call("restore_state", {
		"mined_blocks": [_pack_v3i(mined_cell)],
		"zones": [{ "id": 101, "blocks": [_pack_v3i(designated_cell)] }],
	})
	var caves: Array = _world_generator.get_cave_catalog()
	if caves.is_empty(): return "no cave for discovery/save fixture"
	var cave: Dictionary = caves[0]
	var cave_index := int(cave["columns"][0])
	var cave_wall := Vector3i(cave_index / 1024 - 1, int(cave["floor_y"]) + 1, cave_index % 1024)
	mining._mine_block_world(cave_wall)
	if not root.get_node("InteriorTracker").is_cave_discovered(0): return "cave discovery fixture failed"
	flag.call("restore_state", {
		"placed": true,
		"cell": _pack_v3i(flag_cell),
	})
	stockpiles.call("restore_state", {
		"zones": [{
			"id": 201,
			"cells": [_pack_v3i(stockpile_cell)],
			"filter_tags": ["stockpile_seed"],
			"storage_filter": {"tags": ["stockpile_seed"], "items": ["base:resources:wood:oak_log"],
				"excluded_items": ["base:resources:seed:oak_acorn"]},
			"stacks": [{
				"cell": _pack_v3i(stockpile_cell),
				"item": "base:resources:seed:oak_acorn",
				"count": 21,
			}],
		}],
	})
	furniture.call("restore_state", {
		"ghosts": [{
			"id": 301,
			"key": "base:furniture:storage_shelf",
			"origin": _pack_v3i(ghost_cell),
			"yaw": 1,
		}],
		"installed": [{
			"id": 401,
			"key": "base:furniture:barrel",
			"origin": _pack_v3i(furniture_cell),
			"yaw": 0,
			"flagged_uninstall": false,
			"storage_filter": {"tags": ["stockpile_stone"], "items": ["base:resources:wood:oak_log"], "excluded_items": []},
			"inventory": { "base:resources:stone:rough_stone": 2, "base:resources:flora:apple": 27 },
		}, {
			"id": 402, "key": "base:furniture:door",
			"origin": _pack_v3i(_surface_cell(32, 0)), "yaw": 0,
		}, {
			"id": 403, "key": "base:furniture:brazier",
			"origin": _pack_v3i(_surface_cell(34, 0)), "yaw": 0,
		}],
	})
	items.call("restore_state", {
		"loose": [{
			"item_key": "base:resources:flora:juniper_berry",
			"count": 17,
			"position": _pack_v3(Vector3(
				float(item_cell.x) + 0.5, float(item_cell.y) + 1.05, float(item_cell.z) + 0.5)),
			"rotation_y": 0.25,
		}],
	})
	for tool in ["stone_hoe", "hunting_spear", "carpentry_kit", "stone_hammer"]:
		items.restore_loose_item("base:resources:tools:"+tool, Vector3(item_cell)+Vector3(.5,1,.5),0,1)
	dwarves.call("restore_state", {
		"birth_index": 1,
		"settlement_anchor": _pack_v3i(flag_cell),
		"roster": [{
			"id": 0,
			"name": "Testur",
			"gender": "male",
			"appearance": {
				"gender": "male",
				"age_tier": "adult",
				"skin_tone": "medium",
				"eye_color": "grey",
				"hair_color": "brown",
				"hair_style": "short_back",
				"eyebrow_style": "thick_flat",
				"beard_style": "",
				"scar": "none",
			},
			"traits": [],
			"profession": "base:profession:miner",
			"profession_experience": { "base:profession:worker": 7, "base:profession:miner": 123 },
			"work_permissions": {"haul": false, "mine": true, "gather": false},
			"position": _pack_v3(Vector3(
				float(dwarf_cell.x) + 0.5, float(dwarf_cell.y) + 1.0, float(dwarf_cell.z) + 0.5)),
			"rotation_y": 0.5,
			"sleep": 0.4,
			"sleeping": true,
			"sleep_hours_left": 2.5,
			"carried_items": [],
		}],
	})
	var carpenter_state: Dictionary = dwarves.serialize_state().roster[0].duplicate(true)
	carpenter_state.id = 1
	carpenter_state.name = "Toolur"
	carpenter_state.profession = "base:profession:carpenter"
	carpenter_state.equipment = {"tool":"base:resources:tools:carpentry_kit", "pending_role":""}
	var pending_state: Dictionary = carpenter_state.duplicate(true)
	pending_state.id = 2
	pending_state.name = "Apprentice"
	pending_state.profession = "base:profession:worker"
	pending_state.sleeping = false
	pending_state.sleep = 1.0
	pending_state.equipment = {"tool":"", "pending_role":"base:profession:carpenter"}
	dwarves.restore_state({"birth_index":3, "settlement_anchor":_pack_v3i(flag_cell), "roster":[carpenter_state,pending_state]})
	camera.call("restore_state", {
		"target_position": _pack_v3(Vector3(520.0, 64.0, 500.0)),
		"zoom": 42.0,
		"pitch": -55.0,
		"orbit_y": 25.0,
	})
	slice.call("restore_state", {
		"active": true,
		"seeded": true,
		"slice_y": 25,
		"last_slice_y": 25,
	})
	_add_transplant_fixtures(details, stockpiles, furniture, items)
	_add_flower_fixtures(details, stockpiles, furniture, items)
	_world_clock.call("restore_state", {
		"day": 7,
		"season": "autumn",
		"year": 3,
		"hour": 6.25,
		"speed": 2.0,
		"paused": true,
	})
	_add_cutting_fixtures(details, furniture, items)
	if not _add_ladder_fixtures(): return "could not find two natural ladder sites"
	var wildlife := _owner("wildlife")
	if wildlife == null: return "wildlife save owner missing"
	if not wildlife.initialized: wildlife.initialize_population()
	if wildlife.animals.is_empty(): return "seeded rabbit population missing"
	var rabbit: Node3D = wildlife.animals[0]
	rabbit.hunger = 0.61
	rabbit.fatigue = 0.73
	rabbit.activity = "Sleeping"
	rabbit._pose()
	var deer: Array = wildlife.animals_of_species("deer")
	if deer.size() < 12: return "seeded deer herds missing"
	deer[0].hunger = 0.67
	deer[0].activity = "Grazing"
	deer[0].timer = 3.5
	deer[0]._pose()
	var wolves: Array = wildlife.animals_of_species("wolf")
	if wolves.size() != 4: return "seeded wolves missing"
	wolves[0].begin_meal(wildlife.wolf_definition.hunting.prey["base:animal:deer"])
	wolves[0].timer = 3.25
	# Store a meal cooldown separately from another wolf's in-flight target.
	var prey: Node3D = wildlife.animals_of_species("rabbit")[0]
	wolves[1].hunger = .9
	wolves[1].satisfied_hours = 0
	wolves[1].retry_hours = 0
	wolves[1].begin_hunt(prey)
	var events := _owner("world_events")
	if events == null: return "arrival save owner missing"
	events.initialize_schedule()
	# Persist an actual edge corridor, one partially entered member, two pending
	# members, a future decision and unrelated local hunting pressure.
	for i in range(3): wildlife.remove_animal(wildlife.animals_of_species("rabbit").back(), "predation")
	var event: Dictionary = events.config.events[0]
	var batch: Dictionary = events.schedules.rabbit_arrival.next.duplicate(true)
	batch.merge({"due": _world_clock.elapsed_days(), "count": 3, "seed": "875323", "issued": 0, "wait": 0.0, "route": [], "edge": ""}, true)
	for attempt in range(64):
		batch.attempt = attempt
		var result: Dictionary = wildlife.prepare_arrival(event, batch, events)
		if result.get("status", "") == "ready":
			batch.merge(result, true)
			break
	if batch.route.is_empty(): return "no arrival corridor for save fixture"
	if wildlife.spawn_arrival_member(event, batch, events) != "spawned": return "could not enter arrival save fixture"
	batch.issued = 1
	batch.wait = .77
	events.schedules.rabbit_arrival.active = batch
	events.schedules.rabbit_arrival.next.due = _world_clock.elapsed_days()+3
	events.record_player_hunt(_surface_cell(0, 0))
	var arrival: Node3D = wildlife.animals.back()
	arrival.advance(.1, 0.0, [])
	arrival.advance(.1, 0.0, [])
	for species in ["deer", "wolf"]:
		for i in range(2): wildlife.remove_animal(wildlife.animals_of_species(species).back(), "test")
		var settings: Dictionary = {}
		for candidate: Dictionary in events.config.events:
			if candidate.species == species: settings = candidate
		var state: Dictionary = events.schedules[settings.id]
		var group: Dictionary = state.next.duplicate(true)
		group.merge({"due": _world_clock.elapsed_days(), "count": 2 if species == "deer" else 1, "seed": "875323", "issued": 0, "wait": 0.0, "route": [], "edge": ""}, true)
		for attempt in range(int(settings.entry_attempts)):
			group.attempt = attempt
			var candidate: Dictionary = wildlife.prepare_arrival(settings, group, events)
			if candidate.get("status", "") == "ready":
				group.merge(candidate, true)
				break
		if group.route.is_empty(): return "no %s arrival corridor for save fixture" % species
		if wildlife.spawn_arrival_member(settings, group, events) != "spawned": return "could not enter %s save fixture" % species
		group.issued = 1
		group.wait = .85
		state.active = group
		state.next.due = _world_clock.elapsed_days()+float(settings.interval_days[0])
		var member: Node3D = wildlife.animals.back()
		member.advance(.1, 0.0, [])
		member.advance(.1, 0.0, [])
		if int(group.issued) == int(group.count): events._finish(settings, state, "arrived")
	return ""


func _add_ladder_fixtures() -> bool:
	var ladders := _owner("ladders")
	if ladders == null: return false
	var entries: Array = []
	for x in range(32, 992, 3):
		for z in range(32, 992, 3):
			var y: int = _world_generator.get_surface_y(x, z)
			var base := Vector3i(x,y,z)
			for yaw in range(4):
				var wall: Vector3i = base + ladders.facing(yaw)
				if _world_generator.get_surface_y(wall.x,wall.z) - y < 5: continue
				var spec: Dictionary = ladders.describe(base,yaw)
				if not String(spec.reason).is_empty() or int(spec.height) < 5: continue
				if not entries.is_empty() and Vector3(base - root.get_node("SaveManager").unpack_v3i(entries[0].base)).length() < 8: continue
				entries.append({"id":entries.size()+1,"key":"base:furniture:crude_ladder","base":_pack_v3i(base),"yaw":yaw,
					"height":int(spec.height),"built":4 if entries.is_empty() else int(spec.height),
					"mode":"build" if entries.is_empty() else "remove", "progress":.7})
				if entries.size() == 2:
					ladders.restore_state({"routes":entries,"next_id":3})
					return true
				break
	return false


func _add_transplant_fixtures(details: Node, stockpiles: Node, furniture: Node, items: Node) -> void:
	var ids: Array = details._records.keys().filter(func(id): return String(id).begins_with("blueberry:"))
	ids.sort()
	assert(ids.size() >= 6)
	var key := "base:resources:plant:blueberry_bush"
	# Planted position/yaw and four physical packed-plant locations.
	for i in range(5):
		var state: Dictionary = details._state(ids[i])
		state["harvested_cycle"] = "3:summer"
		state["packed"] = true
		details._remove(ids[i], "uprooted")
	var planted: Dictionary = details._state(ids[0])
	var destination: Vector3i = details._records[ids[0]].origin + Vector3i.RIGHT
	planted["origin"] = _pack_v3i(destination)
	planted["yaw"] = 1
	planted.packed = false
	planted.removed = false
	planted.reason = "transplanted"
	details._relocate_record(ids[0], destination, 1)
	var working: Dictionary = details._state(ids[5])
	working.action = "uproot"
	working.designated = true
	working.work_seconds = .65
	details._ensure_source(ids[5])
	var ground := _surface_cell(18,0)
	stockpiles.restore_state({"zones":[{"id":202,"cells":[_pack_v3i(ground)],"stacks":[
		{"cell":_pack_v3i(ground),"item":key,"count":1,"instance_id":ids[1]}]}]})
	furniture.restore_state({"installed":[{"id":404,"key":"base:furniture:storage_chest",
		"origin":_pack_v3i(_surface_cell(40,0)),"inventory":{key:1},
		"instances":[{"item":key,"count":1,"instance_id":ids[2]}]}],
		"ghosts":[{"id":302,"key":"base:flora:blueberry_bush","origin":_pack_v3i(_surface_cell(44,0)),
			"plant_id":ids[4],"plant_work":1.25,"yaw":2}]})
	for i in [3,4]:
		items.restore_loose_item(key,Vector3(_surface_cell(42,i-3))+Vector3(.5,1,.5),0,1,ids[i])


func _add_flower_fixtures(details: Node, stockpiles: Node, furniture: Node, items: Node) -> void:
	var ids: Array = details._records.keys().filter(func(id): return String(id).begins_with("flowers:"))
	ids.sort()
	var registry := root.get_node("SurfaceDetailRegistry")
	for i in range(3,7):
		details._state(ids[i])["packed"] = true
		details._remove(ids[i], "uprooted")
	var item_key: String = registry.packed_item("base:detail:flowers", int(details._records[ids[3]].variant))
	var ground := _surface_cell(18,3)
	stockpiles.restore_state({"zones":[{"id":203,"cells":[_pack_v3i(ground)],"stacks":[
		{"cell":_pack_v3i(ground),"item":item_key,"count":1,"instance_id":ids[3]}]}]})
	item_key = registry.packed_item("base:detail:flowers", int(details._records[ids[4]].variant))
	furniture.restore_state({"installed":[{"id":405,"key":"base:furniture:storage_chest",
		"origin":_pack_v3i(_surface_cell(40,5)),"inventory":{item_key:1},
		"instances":[{"item":item_key,"count":1,"instance_id":ids[4]}]}]})
	for i in [5,6]:
		item_key = registry.packed_item("base:detail:flowers", int(details._records[ids[i]].variant))
		items.restore_loose_item(item_key,Vector3(_surface_cell(42,i))+Vector3(.5,1,.5),0,1,ids[i])
	furniture._restore_ghost({"id":304,"key":registry.place_key("base:detail:flowers",int(details._records[ids[6]].variant)),
		"origin":_pack_v3i(_surface_cell(44,7)),"plant_id":ids[6],"plant_work":.7,"yaw":1})
	var state: Dictionary = details._state(ids[7])
	state.action = "uproot"
	state.designated = true
	state.work_seconds = .6
	state.clear_work_seconds = .3
	details._ensure_source(ids[7])
	var moved: Dictionary = details._state(ids[8])
	var destination: Vector3i = details._records[ids[8]].origin + Vector3i.RIGHT
	moved["origin"] = _pack_v3i(destination)
	moved["yaw"] = 2
	moved.reason = "transplanted"
	details._relocate_record(ids[8],destination,2)


func _add_cutting_fixtures(details: Node, furniture: Node, items: Node) -> void:
	var ids: Array = details._records.keys().filter(func(id): return String(id).begins_with("blueberry:"))
	ids.sort()
	for i in range(4):
		var original: String = ids[6+i]
		var origin: Vector3i = details._records[original].origin
		details._remove(original, "cleared")
		var id: String = details.plant_cutting("base:flora:blueberry_bush",origin,i)
		details._changes[id].planted_at = _world_clock.elapsed_days() - 1.25
		if i == 1:
			details.dev_mature_shrub(id)
			details._changes[id]["harvested_cycle"] = "3:summer"
		elif i == 2:
			details._remove(id,"cleared")
		elif i == 3:
			details.dev_mature_shrub(id)
			details._changes[id]["packed"] = true
			details._remove(id,"uprooted")
			items.restore_loose_item("base:resources:plant:blueberry_bush",Vector3(_surface_cell(42,2))+Vector3(.5,1,.5),0,1,id)
	furniture._restore_ghost({"id":303,"key":"base:flora:blueberry_cutting",
		"origin":_pack_v3i(_surface_cell(44,3)),"plant_work":.8,"yaw":1})


func _verify_restored_state(expected_seed: int) -> String:
	if int(_world_generator.get("world_seed")) != expected_seed:
		return "world seed did not round-trip"
	if _terrain_fingerprint() != _terrain_reference:
		return "regenerated terrain/cave maps changed during save/load"
	if not root.get_node("InteriorTracker").is_cave_discovered(0):
		return "mining did not reconstruct discovered cave after load"
	if current_scene.get_node("Renderer")._discovered_cave_blocks.is_empty():
		return "restored cave is absent from renderer"
	if int(_world_clock.get("day")) != 7 \
			or String(_world_clock.get("season")) != "autumn" \
			or int(_world_clock.get("year")) != 3:
		return "calendar did not restore from the saved snapshot"
	if not is_equal_approx(float(_world_clock.get("hour")), 6.25) \
			or not is_equal_approx(float(_world_clock.get("speed")), 2.0):
		return "clock hour/speed did not restore from the backup snapshot"
	if not bool(_world_clock.get("paused")):
		return "clock paused state did not round-trip"

	var scene_state := _collect_scene_state()
	var expected_keys := [
		"mining", "flora", "settlement_flag", "stockpiles", "furniture",
		"items", "dwarves", "camera", "slice", "worker_crafting", "surface_details", "ladders",
		"wildlife", "world_events",
	]
	for key in expected_keys:
		if not scene_state.has(key):
			return "restored scene is missing section %s" % key
	if (scene_state["mining"] as Dictionary).get("mined_blocks", []).size() != 2:
		return "mined blocks did not round-trip"
	if (scene_state["flora"] as Dictionary).get("trees", []).size() != 5:
		return "forestry progress/designations/removals did not round-trip"
	if (scene_state["mining"] as Dictionary).get("zones", []).size() != 1:
		return "mining zones did not round-trip"
	if not bool((scene_state["settlement_flag"] as Dictionary).get("placed", false)):
		return "settlement flag did not round-trip"
	if (scene_state["stockpiles"] as Dictionary).get("zones", []).size() != 3:
		return "stockpile state did not round-trip"
	var furniture_state := scene_state["furniture"] as Dictionary
	if furniture_state.get("ghosts", []).size() != 4 or furniture_state.get("installed", []).size() != 5:
		return "furniture state did not round-trip"
	var rooms := root.get_node("RoomManager")
	if rooms.get_door_boundaries().size() != 10 or int(rooms.get_stats().doors) != 1:
		return "door light boundaries did not rebuild from saved furniture"
	var light_cells := {_surface_cell(34, 0) + Vector3i.UP: true}
	if rooms.count_room_lights(light_cells) != 1 or rooms._sum_heat(light_cells) != 600:
		return "installed light/heat duplicated across world reload"
	if (scene_state["items"] as Dictionary).get("loose", []).size() != 10:
		return "loose items did not round-trip"
	var roster: Array = (scene_state["dwarves"] as Dictionary).get("roster", [])
	if roster.size() != 3 or not bool((roster[0] as Dictionary).get("sleeping", false)):
		return "dwarf roster/runtime state did not round-trip"
	if roster[0].profession != "base:profession:miner" or int(roster[0].profession_experience.get("base:profession:miner", 0)) != 123 or roster[0].work_permissions != {"haul": false, "mine": true, "gather": false}:
		return "profession, retained experience or work permissions did not round-trip"
	if roster[1].profession != "base:profession:carpenter" or roster[1].equipment.tool != "base:resources:tools:carpentry_kit":
		return "equipped Carpenter tool did not round-trip"
	if roster[2].profession != "base:profession:worker" or roster[2].equipment.pending_role != "base:profession:carpenter":
		return "pending promotion did not retain current profession and appointment intent"
	var inventory_read_model = load("res://scripts/components/ColonyInventory.gd")
	var equipment_stock: Dictionary = inventory_read_model.snapshot(_owner("items"), _owner("furniture"))
	if int(equipment_stock["base:resources:tools:carpentry_kit"].total) != 2 or int(equipment_stock["base:resources:tools:carpentry_kit"].equipped) != 1:
		return "equipment duplicated or disappeared across scene replacement"
	var camera_state := scene_state["camera"] as Dictionary
	if not is_equal_approx(float(camera_state.get("zoom", 0.0)), 42.0):
		return "camera state did not round-trip"
	var slice_state := scene_state["slice"] as Dictionary
	if not bool(slice_state.get("active", false)) or int(slice_state.get("slice_y", -1)) != 25:
		return "slice state did not round-trip"
	return ""


func _collect_scene_state() -> Dictionary:
	var result: Dictionary = {}
	for state_owner in get_nodes_in_group(OWNER_GROUP):
		if state_owner.has_method("save_section_key") and state_owner.has_method("serialize_state"):
			result[String(state_owner.call("save_section_key"))] = state_owner.call("serialize_state")
	return result


## Recursive content-equality diff. Floats compare with a small tolerance —
## JSON round-trips numbers through text and node transforms through 32-bit
## Vector3 components, so exact bit equality is not the contract. Returns ""
## when equal, otherwise a "path: detail" description of the FIRST difference,
## so a regression names the exact field it ate (e.g. a container inventory
## clamped on load, a ghost yaw reset, a stack count collapsing to 1).
func _deep_diff(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary and actual is Dictionary:
		var exp_dict := expected as Dictionary
		var act_dict := actual as Dictionary
		for key in exp_dict:
			if not act_dict.has(key):
				return "%s: missing key '%s'" % [path, str(key)]
			var child := _deep_diff(exp_dict[key], act_dict[key], "%s.%s" % [path, str(key)])
			if not child.is_empty():
				return child
		for key in act_dict:
			if not exp_dict.has(key):
				return "%s: unexpected key '%s'" % [path, str(key)]
		return ""
	if expected is Array and actual is Array:
		var exp_arr := expected as Array
		var act_arr := actual as Array
		if exp_arr.size() != act_arr.size():
			return "%s: array size %d != %d" % [path, exp_arr.size(), act_arr.size()]
		for i in range(exp_arr.size()):
			var child := _deep_diff(exp_arr[i], act_arr[i], "%s[%d]" % [path, i])
			if not child.is_empty():
				return child
		return ""
	if (expected is float or expected is int) and (actual is float or actual is int):
		if absf(float(expected) - float(actual)) > 0.002:
			return "%s: %s != %s" % [path, str(expected), str(actual)]
		return ""
	if typeof(expected) != typeof(actual) or expected != actual:
		return "%s: %s != %s" % [path, str(expected), str(actual)]
	return ""


## In-flight case: a save written mid-haul stores carried item KEYS on the
## dwarf (DwarfAgent.serialize_state). The load contract is Hard Rule 12
## shaped: carried items are re-dropped as loose at the dwarf's feet — never
## destroyed, never left on the freed agent. restore_state is invoked here
## exactly as SaveManager invokes it for the dwarves section, so this is the
## same code path a real load takes.
func _run_inflight_carried_case() -> String:
	var dwarves := _owner("dwarves")
	var items := _owner("items")
	if dwarves == null or items == null:
		return "in-flight case: save-state owners missing after reload"
	var loose_before := ((items.call("serialize_state") as Dictionary).get("loose", []) as Array).size()
	var carrier_cell := _surface_cell(16, 0)
	var details := _owner("surface_details")
	var plant_ids: Array = details._records.keys().filter(func(id): return String(id).begins_with("blueberry:"))
	plant_ids.sort()
	var plant_id := String(plant_ids[10])
	details._state(plant_id)["packed"] = true
	details._state(plant_id)["harvested_cycle"] = "3:summer"
	details._remove(plant_id,"uprooted")
	var flower_ids: Array = details._records.keys().filter(func(id): return String(id).begins_with("flowers:"))
	flower_ids.sort()
	var flower_id := String(flower_ids[9])
	var flower_variant := int(details._records[flower_id].variant)
	var flower_item: String = root.get_node("SurfaceDetailRegistry").packed_item("base:detail:flowers",flower_variant)
	details._state(flower_id)["packed"] = true
	details._remove(flower_id,"uprooted")
	dwarves.call("restore_state", {
		"birth_index": 5,
		"settlement_anchor": _pack_v3i(_surface_cell(0, 0)),
		"roster": [{
			"id": 4,
			"name": "Carrier",
			"gender": "male",
			"appearance": {
				"gender": "male",
				"age_tier": "adult",
				"skin_tone": "medium",
				"eye_color": "grey",
				"hair_color": "brown",
				"hair_style": "short_back",
				"eyebrow_style": "thick_flat",
				"beard_style": "",
				"scar": "none",
			},
			"traits": [],
			"profession": "base:profession:worker",
			"profession_experience": {},
			"position": _pack_v3(Vector3(
				float(carrier_cell.x) + 0.5, float(carrier_cell.y) + 1.0, float(carrier_cell.z) + 0.5)),
			"rotation_y": 0.0,
			"sleep": 0.9,
			"sleeping": true,
			"sleep_hours_left": 5.0,
			"carried_items": [
				"base:resources:stone:rough_stone",
				{"item_key": "base:resources:seed:pine_cone", "count": 24},
				{"item_key": "base:resources:plant:blueberry_bush", "count": 1, "instance_id": plant_id},
				{"item_key": flower_item, "count": 1, "instance_id": flower_id},
			],
		}],
	})
	var loose_after := ((items.call("serialize_state") as Dictionary).get("loose", []) as Array).size()
	if loose_after != loose_before + 4:
		return "in-flight case: carried items not conserved as loose drops (loose %d -> %d, expected +4)" \
			% [loose_before, loose_after]
	var carried_cones := 0
	for drop in (items.call("serialize_state") as Dictionary).get("loose", []):
		if String(drop.item_key) == "base:resources:seed:pine_cone":
			carried_cones += int(drop.count)
	if carried_cones != 24:
		return "in-flight case: crate contents were not conserved"
	var plant_count := 0
	for drop: Dictionary in items.serialize_state().loose:
		if drop.get("instance_id", "") == plant_id: plant_count += int(drop.count)
	if plant_count != 1 or details._changes[plant_id].harvested_cycle != "3:summer":
		return "in-flight case: mature shrub identity/crop not conserved"
	var flower_count := 0
	for drop: Dictionary in items.serialize_state().loose:
		if drop.get("instance_id", "") == flower_id and drop.item_key == flower_item: flower_count += int(drop.count)
	if flower_count != 1 or int(details._records[flower_id].variant) != flower_variant or details.flower_blooming(flower_id):
		return "in-flight case: flower identity/variant/dormancy not conserved"
	var roster: Array = (dwarves.call("serialize_state") as Dictionary).get("roster", [])
	for raw in roster:
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		if int(entry.get("id", -1)) == 4:
			if not ((entry.get("carried_items", []) as Array).is_empty()):
				return "in-flight case: restored dwarf still reports carried items"
			return ""
	return "in-flight case: carrier dwarf missing from the roster after restore"


func _owner(section_key: String) -> Node:
	for state_owner in get_nodes_in_group(OWNER_GROUP):
		if state_owner.has_method("save_section_key") \
				and String(state_owner.call("save_section_key")) == section_key:
			return state_owner
	return null


func _surface_cell(offset_x: int, offset_z: int) -> Vector3i:
	var x := _fixture_origin.x + offset_x
	var z := _fixture_origin.y + offset_z
	return Vector3i(x, int(_world_generator.call("get_surface_y", x, z)), z)


## Locate existing flat lowland for the fixture's row of objects. This never
## changes terrain, clears trees, or adds a production starting-area contract.
func _choose_fixture_origin() -> bool:
	for x in range(36, 956, 32):
		for z in range(48, 976, 32):
			var valid := true
			for dx in range(-4, 44):
				for dz in range(-4, 8):
					if _world_generator.get_surface_y(x + dx, z + dz) != 19 or _world_generator.get_waterline(x + dx, z + dz) >= 0:
						valid = false
						break
				if not valid: break
			if valid:
				_fixture_origin = Vector2i(x, z)
				return true
	return false


func _terrain_fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_world_generator.get("heightmap")))
	context.update(var_to_bytes(_world_generator.get("domain_map")))
	context.update(var_to_bytes(_world_generator.get("waterline_map")))
	context.update(var_to_bytes(_world_generator.get("_cave_layout")))
	return context.finish().hex_encode()


func _wait_for_world_ready(timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var stats: Dictionary = _world_generator.call("get_streaming_stats")
		if bool(stats.get("maps_ready", false)) and not bool(_world_generator.call("is_generating")):
			return true
		await process_frame
	return false


func _wait_for_load(timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not _load_completed and Time.get_ticks_msec() < deadline:
		await process_frame
	return _load_completed


func _on_load_finished(success: bool, used_backup: bool) -> void:
	_load_succeeded = success
	_load_used_backup = used_backup
	_load_completed = true


func _fail(message: String) -> void:
	push_error("SAVE_MANAGER_ROUND_TRIP_FAIL: %s" % message)
	_cleanup_and_quit(1)


func _cleanup_and_quit(exit_code: int) -> void:
	if _save_manager != null:
		_save_manager.call("reset_storage_after_testing")
	_cleanup_test_storage()
	quit(exit_code)


func _pack_v3i(value: Vector3i) -> Array:
	return [value.x, value.y, value.z]


func _pack_v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _cleanup_test_storage() -> void:
	for path in [
		TEST_PRIMARY, TEST_BACKUP, TEST_TEMP, TEST_BACKUP_STAGE,
		TEST_AUTOSAVE, TEST_AUTOSAVE_BACKUP, TEST_AUTOSAVE_TEMP,
		TEST_AUTOSAVE_BACKUP_STAGE,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		# The fixed test directory is removed only when the exact files above left it empty.
		DirAccess.remove_absolute(absolute_directory)
