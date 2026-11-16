extends "res://scripts/tests/TreeFellingTest.gd"

## Farming (doc 309), in the flat test world with a patch of grass. A field's ground rules and
## its plan; a real Farmer hoeing, sowing and pulling; growth by the day, in damp soil and in
## winter; a crop that needs water and one that is picked again and again; what each level may
## sow; work kept on the tile across a release; a bush in a field picked by the Farmer alone;
## the field's window; saves; and a real drag.
const FARMER := "base:profession:farmer"
const RADISH := "base:flora:radish"
const CARROT := "base:flora:carrot"
const TURNIP := "base:flora:turnip"
const CABBAGE := "base:flora:cabbage"
const ONION := "base:flora:onion"
const PUMPKIN := "base:flora:pumpkin"
const KALE := "base:flora:kale"
const CARROTS := "base:item:carrot"
const BLUE := "field_blueberry"
var farming: Node
var details: Node
var grass: int
var tilled: int


func _run() -> void:
	create_timer(170).timeout.connect(func(): push_error("Farming test timed out"); quit(1))
	_setup_fixture()
	root.get_node("StockpileManager").set_process(false)
	grass = blocks.get_id("base:terrain:surface:grass")
	tilled = blocks.get_id("base:terrain:soil:tilled")
	for x in range(28, 46):
		for z in range(28, 42): world.set_block(x, 20, z, grass)
	_clock("summer", 1, 8.0)
	details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	farming = load("res://scripts/systems/FarmingSystem.gd").new()
	farming.name = "Farming"
	farming.window_manager_path = NodePath("../Windows")
	scene.add_child(farming)
	farming.set_process(false)
	await process_frame
	farming_started()
	var crops: Dictionary = root.get_node("ContentRegistry").crops
	_expect(crops.keys() == [RADISH, CARROT, TURNIP, CABBAGE, ONION, PUMPKIN, KALE], "the seven vegetables, in the order a Farmer learns them: %s" % [crops.keys()])
	_check_data(crops)
	# The ground a field takes.
	_expect(farming.tile_reason(Vector3i(30, 20, 30)) == "" and farming.ground_of(Vector3i(30, 20, 30)) == "untilled", "open grass is a field's ground")
	_expect(farming.tile_reason(Vector3i(60, 20, 60)) == "Fields need grass or dirt", "rock is refused, and the tool says why")
	# Ground the colony has never touched has no chunk of its own, and WorldData.get_block reads it
	# as air: a field reads the terrain itself (found in the live world, 2026-11-14, where every
	# cell of open grass was refused).
	var far := Vector3i(300, 20, 300)
	_expect(not world.chunk_exists(far.x >> 4, far.y >> 4, far.z >> 4) and world.get_block(far.x, far.y, far.z) == blocks.AIR_ID
		and farming.ground_of(far) == ("untilled" if String(blocks.get_def(blocks.get_key(world.get_terrain_block(far.x, far.y, far.z))).get("kind", "")) in ["grass", "dirt"] else ""),
		"untouched ground is read from the terrain, not from a chunk that is not there: %s" % farming.ground_of(far))
	_expect(farming.ground_of(far) == "untilled" and farming.tile_reason(far) == "", "so open ground far from the colony can be a field: %s" % farming.tile_reason(far))
	world.set_block(44, 24, 40, blocks.get_id("base:terrain:rock:rock01"))
	_expect(farming.tile_reason(Vector3i(44, 20, 40)) == "Fields need the open sky", "ground under a roof is refused")
	world.set_block(44, 24, 40, blocks.AIR_ID)
	# A field of twelve tiles takes the starter crops for its plan.
	var cells: Array[Vector3i] = []
	for x in range(30, 34):
		for z in range(30, 33): cells.append(Vector3i(x, 20, z))
	var field: int = farming.create_zone(cells)
	_expect(field == 1 and farming.is_zone_cell(cells[0]) and not farming.create_zone(cells) > 0, "a field, and no tile in two fields")
	_expect(farming.zone_data(field).plan.map(func(row): return row.crop) == [RADISH, CARROT, TURNIP, ""], "a new field plans radish, carrot and turnip, and rests in winter")
	_expect(farming.tile_reason(cells[0]) == "Already a field", "a tile of a field is refused to another")
	_check_wet_ground(field, cells)
	# With no Farmer a field waits.
	farming.refresh_work()
	_expect(_leases(field) == 0 and bool(farming.zone_data(field).no_farmer), "with no Farmer the field posts no work")
	worker = _farmer(601, Vector3i(26, 20, 31))
	farming.refresh_work()
	_expect(_leases(field) == 2, "a Farmer in the colony: the field posts a lease for each of its two places: %d" % _leases(field))
	_expect(not tasks._scheduler.takes(_plain(602, Vector3i(26, 20, 34)), Task.Type.FARM), "a Worker takes no field work")
	# A real Farmer hoes each tile and sows the season's crop.
	var sounds: Array = []
	root.get_node("WorkFeedback").sound_started.connect(func(kind, _at, _voice): sounds.append(kind))
	camera.set_meta("work_focus", Vector3(31, 21, 31))
	camera.set_meta("work_zoom", 12.0)
	_expect(await _until(func(): return worker._task_phase == worker.TaskPhase.FELL_WORKING), "the Farmer walks to a tile and sets to work")
	var place = _held_place(field)
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(place != null and place.job == "till" and inspection.describe(worker).activity == "Hoeing the ground" and inspection.roster_state(worker).summary == "Farming",
		"its first job is to hoe, and the inspector says so: %s" % [inspection.describe(worker).activity])
	_expect(farming.zone_data(field).farmers == [{"name": worker.dwarf_name, "doing": "hoeing the ground"}], "the field's window names the Farmer at work")
	# A release keeps the work on the tile (Hard Rule 12).
	worker._process(.5)
	var hoed: Vector3i = place.origin
	var begun: float = farming.tile_at(hoed).get("work", 0.0)
	worker.force_interrupt()
	_expect(begun > 0.0 and place.reserved_by < 0 and is_equal_approx(farming.tile_at(hoed).work, begun) and farming.ground_of(hoed) == "untilled",
		"a release keeps the hoeing begun on the tile and frees the place")
	_expect(await _until(func(): return farming.ground_of(hoed) == "tilled"), "the tile is hoed into tilled soil")
	_expect(world.get_block(hoed.x, hoed.y, hoed.z) == tilled and farming.stage_of(hoed) in ["bare", "sprout"], "tilled soil is a block of its own, and the tile shows its furrows")
	_expect(await _until(func(): return _sown(field, CARROT) == 12), "every tile is hoed and sown with the summer's carrots: %d" % _sown(field, CARROT))
	_expect("farm_hoe" in sounds and "farm_sow" in sounds and not "mining_soil" in sounds, "the hoe is heard in the soil, and each tile as it is sown: %s" % [sounds.slice(0, 8)])
	var hoe: Node3D = worker._rig.hoe_pose.tool
	_expect(is_instance_valid(hoe) and hoe.get_parent() == worker._hand_r and not hoe.visible, "the copper hoe is the Farmer's, in its right hand while it hoes and put away after")
	var edge: Vector3 = load("res://scripts/components/DwarfHoePose.gd").HOE_EDGE
	var nearest := INF
	for mesh: MeshInstance3D in load("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(hoe):
		# The edge runs across the blade, so its middle is no vertex: measure to the line it lies on.
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if absf(vertex.x) <= .32: nearest = minf(nearest, Vector2(vertex.y - edge.y, vertex.z - edge.z).length())
	_expect(nearest <= 0.0885, "the hoe's blade ends where the pose strikes with it, cell (0, 22, 10): %.3f away" % nearest)
	_expect(farming.stage_of(cells[0]) == "sprout" and farming._visuals.model_of(cells[0]).ends_with("carrot_sprout.glb"), "a sown tile shows the crop's sprout")
	_expect(_leases(field) == 0 and worker.current_task_id < 0, "with nothing due the field posts no work and the Farmer is free")
	# Growth by the day.
	clock_node.advance_hours(24.0 * 3.0)
	_expect(is_equal_approx(farming.tile_at(cells[0]).credit, 3.0) and farming.stage_of(cells[0]) == "growing", "three days on, the carrots are half grown: %.2f" % farming.tile_at(cells[0]).credit)
	clock_node.advance_hours(24.0 * 3.0)
	_expect(farming.tile_at(cells[0]).ripe and farming.stage_of(cells[0]) == "ripe" and farming.zone_data(field).counts.ripe == 12, "six days from sowing they are ripe")
	# Pulling: three carrots a tile into few crates, the Farmer's experience, and the tile sown again.
	_expect(await _until(func(): return _count(CARROTS) == 36), "twelve tiles give 36 carrots: %d" % _count(CARROTS))
	_expect(_item_count(CARROTS) <= 3, "the pulls fill one crate after another, not a crate a tile: %d crates" % _item_count(CARROTS))
	_expect("farm_pull" in sounds, "a ripe tile is heard as it is pulled: %s" % [sounds.slice(maxi(0, sounds.size() - 6))])
	_sound_banks()
	_expect(int(worker.profession_experience.get(FARMER, 0)) == 12 and farming.level_of(worker) == 1, "one experience a tile harvested: %s" % [worker.profession_experience.get(FARMER, 0)])
	_expect(await _until(func(): return _sown(field, CARROT) == 12), "pulled tiles are sown again while a round can still ripen")
	# Too late in the season the Farmer sows no more.
	_clock("summer", 16, 8.0)
	_expect(not farming.can_sow(field, CARROT) and farming.sow_until(field, CARROT) == 14, "carrots are sown until Summer 14: %d" % farming.sow_until(field, CARROT))
	# When the season turns, what is not ripe is hoed under and the new crop sown.
	for cell: Vector3i in cells: farming.tile_at(cell).credit = 1.0
	farming.tile_at(cells[0]).credit = 6.0
	farming.tile_at(cells[0]).ripe = true
	var log_before: int = root.get_node("EventLog").entries().size()
	_clock("autumn", 1, 8.0)
	clock_node.season_changed.emit("autumn")
	_expect(farming.tile_job(field, cells[0]).job == "harvest" and farming.tile_job(field, cells[1]).job == "clear", "in autumn a ripe carrot is still pulled and an unripe one hoed under")
	var told: Array = root.get_node("EventLog").entries().filter(func(entry): return entry.line == "crop_late")
	_expect(told.size() == 1 and told[0].fields == {"count": 11, "crop": CARROT, "field": field, "season": "autumn"}
		and told[0].text == "11 tiles of carrots in Field 1 were not ripe when autumn came." and told[0].detail == "A Farmer will hoe them under."
		and root.get_node("EventLog").entries().size() > log_before, "Events says what did not ripen: %s" % [told])
	_expect(await _until(func(): return _sown(field, TURNIP) == 12), "the field changes over to turnips")
	_expect(_count(CARROTS) == 39, "the one ripe tile was pulled at the changeover, not lost: %d" % _count(CARROTS))
	# Winter: nothing grows, and nothing is sown.
	_clock("winter", 2, 8.0)
	farming.grow()
	var before_winter: float = farming.tile_at(cells[3]).credit
	clock_node.advance_hours(24.0 * 4.0)
	_expect(is_equal_approx(farming.tile_at(cells[3]).get("credit", -1.0), before_winter) or farming.tile_at(cells[3]).is_empty(), "nothing grows in winter")
	await _until(func(): return _sown(field, TURNIP) == 0)
	_expect(_sown(field, TURNIP) == 0 and farming.tile_job(field, cells[3]).is_empty(), "winter's rest: the turnips that did not ripen are hoed under, and nothing is sown")
	await _plans_and_levels(field, cells)
	await _water_and_regrowth(field, cells)
	await _bush(field)
	_window(field)
	_saves(field, cells)
	await _drag()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("FARMING_OK: ground, plan, hoeing, sowing, growth, pulling, seasons, levels, water, regrowth, bushes, the window, saves and a drag")
	quit(0 if failures.is_empty() else 1)


## The Farmer's three cues are banks of their own recorded one-shots, each with a level (doc 13).
func _sound_banks() -> void:
	var feedback: Node = root.get_node("WorkFeedback")
	var lengths := {"farm_hoe": [0.2, 0.7], "farm_pull": [0.25, 0.9], "farm_sow": [0.15, 0.7]}
	for kind: String in lengths:
		var bank: Array = feedback._streams.get(kind, [])
		var recorded := bank.size() >= 3
		for stream: AudioStreamWAV in bank:
			recorded = recorded and not stream.stereo and stream.mix_rate == 48000 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED \
				and stream.resource_path.contains("/work/" + kind + "_") and stream.get_length() >= lengths[kind][0] and stream.get_length() <= lengths[kind][1]
		_expect(recorded and feedback._profile(kind).has("level_db"), "%s is a bank of its own recorded one-shots with a level: %d" % [kind, bank.size()])


## Each crop's data agrees with what the Farmer's levels promise, and the docs' sowing days.
func _check_data(crops: Dictionary) -> void:
	var assets: Node = root.get_node("DwarfAssets")
	_expect(assets.profession_enabled(FARMER) and assets.profession_tool(FARMER) == "base:item:copper_hoe"
		and Task.Type.FARM in assets.profession_task_types(FARMER) and Task.Type.HAUL in assets.profession_task_types(FARMER)
		and assets.profession_work_first(FARMER) == [Task.Type.FARM], "the Farmer is promoted with a copper hoe, works its fields first and keeps the common work")
	_expect(assets.tool_maker("base:item:copper_hoe") == "base:profession:blacksmith", "a Blacksmith makes the hoe")
	_expect(assets.earns_by(FARMER, "FARM") and [2, 3, 4, 5].map(func(level): return assets.experience_threshold(level, FARMER)) == [25, 100, 250, 800], "levels at 25, 100, 250 and 800 tiles")
	_expect(assets.work_stat("farming") == "base:stat:wisdom" and assets.profession_allows(FARMER, "farm") and not assets.profession_allows("base:profession:worker", "farm"),
		"Wisdom speeds field work, and Farm is the Farmer's box in Labor")
	var rewards: Array = assets.level_rewards(FARMER)
	for key: String in crops:
		var crop: Dictionary = crops[key]
		var level := int(crop.farmer_level)
		var told := level == 1
		for reward: Dictionary in rewards:
			if int(reward.level) == level and String(reward.text).to_lower().contains(String(crop.display_name).to_lower()): told = true
		_expect(told, "level %d's reward names %s" % [level, crop.display_name])
		var item: Dictionary = root.get_node("ContentRegistry").item_def(String(crop.item))
		_expect(bool(item.get("food", {}).get("edible", false)) and "stockpile_food" in item.material_tags, "%s is food a store takes" % crop.display_name)


## The plan's pairs, the sowing days of the crops that take two seasons, and what a level may sow.
func _plans_and_levels(field: int, cells: Array[Vector3i]) -> void:
	_expect(not farming.set_plan(field, "summer", RADISH), "a spring crop can't be planned for summer")
	_expect(farming.set_plan(field, "spring", ONION) and _plan(field) == [ONION, ONION, TURNIP, ""], "onions sown in spring hold the summer too: %s" % [_plan(field)])
	_clock("spring", 1, 8.0)
	_expect(farming.sow_until(field, ONION) == 13, "onions are sown until Spring 13: %d" % farming.sow_until(field, ONION))
	_expect(farming.set_plan(field, "summer", CARROT) and _plan(field) == ["", CARROT, TURNIP, ""], "a summer crop over the onions' second season puts spring to rest")
	_expect(farming.set_plan(field, "summer", PUMPKIN) and _plan(field) == ["", PUMPKIN, PUMPKIN, ""], "pumpkins take summer and autumn")
	_clock("summer", 1, 8.0)
	_expect(farming.sow_until(field, PUMPKIN) == 11, "pumpkins are sown until Summer 11: %d" % farming.sow_until(field, PUMPKIN))
	_expect(farming.set_plan(field, "autumn", KALE) and _plan(field) == ["", "", KALE, KALE], "kale over the pumpkins' second season rests the summer, and holds the winter")
	_clock("autumn", 1, 8.0)
	_expect(farming.sow_until(field, KALE) == 10, "kale is sown until Autumn 10: %d" % farming.sow_until(field, KALE))
	_expect(farming.set_plan(field, "winter", "") and _plan(field) == ["", "", "", ""], "resting the winter rests the kale's autumn too")
	# What a level may sow: cabbage is a level 2 Farmer's.
	_clock("spring", 1, 8.0)
	farming.set_plan(field, "spring", CABBAGE)
	farming.refresh_work()
	var place = farming.place_of(field, 0)
	_expect(farming.tile_job(field, cells[0]) == {"job": "sow", "crop": CABBAGE, "level": 2} and not place.allows_worker(worker) and _leases(field) == 0,
		"a level 1 Farmer is offered no cabbage to sow: %s" % [farming.tile_job(field, cells[0])])
	_expect(String(farming.zone_data(field).plan[0].locked) == "Needs a level 2 Farmer", "and the window says what the cabbage needs")
	worker.profession_experience[FARMER] = 25
	farming.refresh_work()
	_expect(farming.level_of(worker) == 2 and place.allows_worker(worker) and _leases(field) == 2 and String(farming.zone_data(field).plan[0].locked).is_empty(),
		"at 25 tiles the Farmer is level 2 and may sow it")
	_expect(await _until(func(): return _sown(field, CABBAGE) == 12), "and sows the cabbages")


## Damp soil, a crop that grows nowhere else, and a crop picked again and again through winter.
## Water on a field's ground (doc 33: a film thinner than standing water is damp ground and
## blocks no placement). Open grass under a film can be a field and a field's tile under one is
## still worked; under standing water the grass is refused and the tile is left alone. Found in
## the owner's colony, 2026-11-16, where a stone crossing held the river back and a film a
## fiftieth of a block deep lay over its banks: the rule counted any water at all. The fixture
## has no water of its own, so this borrows a still one and puts things back.
func _check_wet_ground(field: int, cells: Array[Vector3i]) -> void:
	var water := root.get_node("WaterManager")
	var kept := [water.flow, water.initialized, water.is_processing()]
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(_column: Vector2i): return [Vector2i(21, 128)]
	water.initialized = true
	water.set_process(false)
	var open := Vector3i(36, 20, 36)
	var zone: Dictionary = farming._zones[field]
	for film: bool in [true, false]:
		for cell: Vector3i in [open, cells[1]]: water.flow.seed_column(cell + Vector3i.UP, .02 if film else .25, false)
		farming._survey(zone)
		var reason: String = farming.tile_reason(open)
		_expect(water.depth_at(open + Vector3i.UP) > 0.0 and water.has_standing_water(open + Vector3i.UP) != film
			and reason == ("" if film else "This ground is under water") and zone.taken.has(cells[1]) != film,
			"%s: open grass reads '%s', and the field's own tile is %s" % ["under a film thinner than standing water" if film else "under standing water",
			reason, "left alone" if zone.taken.has(cells[1]) else "still worked"])
	water.flow = kept[0]
	water.initialized = kept[1]
	water.set_process(kept[2])
	farming._survey(zone)


func _water_and_regrowth(field: int, cells: Array[Vector3i]) -> void:
	var weather: Node = root.get_node("WeatherManager")
	weather.set_weather("base:weather:clear")
	farming.grow()
	for cell: Vector3i in cells: farming.tile_at(cell).credit = 0.0
	clock_node.advance_hours(24.0)
	var dry: float = farming.tile_at(cells[0]).credit
	weather.set_weather("base:weather:rain")
	_expect(farming.wet_sky() and farming.is_damp(cells[0]), "rain makes every open field damp")
	clock_node.advance_hours(24.0)
	_expect(is_equal_approx(dry, 1.0) and is_equal_approx(farming.tile_at(cells[0]).credit - dry, 1.25), "a day in damp soil grows a crop a quarter more: %.2f then %.2f" % [dry, farming.tile_at(cells[0]).credit - dry])
	# Pumpkins: sown and grown only in damp soil.
	worker.profession_experience[FARMER] = 800
	for cell: Vector3i in cells: farming._zones[field].tiles.erase(cell)
	farming.set_plan(field, "spring", "")
	_clock("summer", 1, 8.0)
	farming.set_plan(field, "summer", PUMPKIN)
	weather.set_weather("base:weather:clear")
	_expect(not farming.is_damp(cells[0]) and farming.tile_job(field, cells[0]).is_empty(), "in dry soil no pumpkin is sown")
	weather.set_weather("base:weather:rain")
	_expect(farming.tile_job(field, cells[0]) == {"job": "sow", "crop": PUMPKIN, "level": 4}, "in damp soil it is")
	farming._zones[field].tiles[cells[0]] = {"crop": PUMPKIN, "credit": 0.0, "ripe": false}
	farming.grow()
	clock_node.advance_hours(24.0)
	var wet: float = farming.tile_at(cells[0]).credit
	weather.set_weather("base:weather:clear")
	clock_node.advance_hours(24.0)
	_expect(is_equal_approx(wet, 1.0) and is_equal_approx(farming.tile_at(cells[0]).credit, wet), "a pumpkin grows a day in damp soil and not at all in dry: %.2f, %.2f" % [wet, farming.tile_at(cells[0]).credit])
	# Kale: ripe after ten days, picked, and ripe again three days on, in winter too.
	for cell: Vector3i in cells: farming._zones[field].tiles.erase(cell)
	farming.set_plan(field, "summer", "")
	farming.set_plan(field, "autumn", KALE)
	_clock("autumn", 1, 8.0)
	farming._zones[field].tiles[cells[0]] = {"crop": KALE, "credit": 0.0, "ripe": false}
	farming.grow()
	clock_node.advance_hours(24.0 * 10.0)
	_expect(farming.tile_at(cells[0]).ripe, "kale is ripe ten days from sowing")
	var before: int = _count("base:item:kale")
	_expect(await _until(func(): return _count("base:item:kale") == before + 1), "a picking gives one a tile")
	_expect(farming.stage_of(cells[0]) == "picked" and farming._visuals.model_of(cells[0]).ends_with("kale_picked.glb") and farming.tile_job(field, cells[0]).is_empty(), "the plant stays, picked, with nothing to do until it regrows")
	_clock("winter", 3, 8.0)
	farming.grow()
	clock_node.advance_hours(24.0 * 3.0)
	_expect(farming.tile_at(cells[0]).ripe and farming.tile_job(field, cells[0]).job == "harvest", "three days on it is ripe again, in winter too")
	_clock("spring", 1, 8.0)
	farming.tile_at(cells[0]).ripe = false
	farming.tile_at(cells[0]).picked = true
	_expect(farming.tile_job(field, cells[0]).job == "clear", "in spring the plan has moved on, and the kale is hoed under")
	for cell: Vector3i in cells: farming._zones[field].tiles.erase(cell)
	farming.set_plan(field, "autumn", "")
	weather.set_weather("base:weather:clear")


## From the owner (2026-11-06): a bush in a farming zone is picked by the Farmer, with no order.
func _bush(field: int) -> void:
	_clock("summer", 2, 8.0)
	var worker_two = _plain(603, Vector3i(36, 20, 36))
	var bush_cells: Array[Vector3i] = []
	for x in range(36, 41):
		for z in range(36, 41): bush_cells.append(Vector3i(x, 20, z))
	var orchard: int = farming.create_zone(bush_cells)
	for season: String in ["spring", "summer", "autumn"]: farming.set_plan(orchard, season, "")
	details.register_record({"id": BLUE, "definition": "base:flora:blueberry_bush", "origin": Vector3i(38, 20, 38), "variant": 0, "yaw": 0})
	farming._zones[orchard].stale = true
	farming._on_hour(8)
	var data: Dictionary = farming.zone_data(orchard)
	_expect(int(data.bushes) == 1 and int(data.counts.alone) == 9, "the field counts its bush, and leaves the bush's nine tiles alone: %s" % [data.counts])
	_expect(bool(details.get_change(BLUE).get("designated", false)) and details.work.has(BLUE), "a ripe bush in a field is marked for picking with no order")
	var source = details.work.get_source(BLUE)
	_expect(source.allows_worker(worker) and not source.allows_worker(worker_two), "picking it is the Farmer's, not a Worker's")
	var experience := int(worker.profession_experience[FARMER])
	_expect(await _until(func(): return _count("base:item:blueberry") == 3), "the Farmer picks it")
	_expect(int(worker.profession_experience[FARMER]) == experience + 1, "and earns one experience for the bush")
	_expect(farming.tile_job(orchard, Vector3i(37, 20, 37)).is_empty() and farming.ground_of(Vector3i(40, 20, 40)) == "untilled", "a field resting all year is an orchard: nothing is hoed")
	farming.remove_zone(orchard)
	tasks.deregister_dwarf(worker_two.dwarf_id)
	worker_two.queue_free()
	farming.remove_zone(field)
	_expect(world.get_block(30, 20, 30) == tilled and farming.zone_ids().is_empty() and farming._visuals.model_of(Vector3i(30, 20, 30)).is_empty(),
		"a field removed leaves its tilled soil and takes its plants")


func _window(_field: int) -> void:
	var cells: Array[Vector3i] = [Vector3i(30, 20, 30), Vector3i(31, 20, 30)]
	_clock("summer", 3, 8.0)
	var field: int = farming.create_zone(cells)
	farming._zones[field].tiles[cells[0]] = {"crop": CARROT, "credit": 3.0, "ripe": false}
	var data: Dictionary = farming.zone_data(field)
	_expect(data.title == "Field %d" % field and data.counts.tiles == 2 and data.counts.tilled == 2 and data.counts.sown == 1 and data.growing == "Carrots: ripe in about 3 days",
		"the window's data: %s, %s" % [data.counts, data.growing])
	_expect(data.plan[1].now and data.plan[1].note == "Sown until Summer 14" and data.plan[0].note == "4 days, 2 a tile" and data.plan[3].note == "Nothing grows in winter",
		"each season's line: %s" % [data.plan.map(func(row): return row.note)])
	var names: Array = data.plan[0].choices.map(func(choice): return choice.name)
	_expect(names == ["Rest", "Radish", "Cabbage", "Onion"], "spring's choices are the crops sown in spring: %s" % [names])
	var panel = load("res://scripts/ui/FarmFieldPanel.gd").new()
	scene.add_child(panel)
	panel.show_field(data)
	_expect(panel._counts.text == "2 tiles · 2 hoed · 1 sown · 0 ripe" and panel._seasons.summer.crop.text == "Carrot" and panel._seasons.summer.name.text == "SUMMER" and panel._seasons.summer.now.text == "NOW" and panel._seasons.spring.now.text == "",
		"the window reads the field: %s" % panel._counts.text)
	var asked: Array = []
	panel.plan_requested.connect(func(season, crop): asked.append([season, crop]))
	panel._seasons.spring.button.pressed.emit()
	panel._show_choices(data)
	var rows: Array = panel._choices.get_children().filter(func(child): return not child.is_queued_for_deletion())
	_expect(rows.size() == 4 and not rows[2].disabled, "an opened season lists its crops: %d" % rows.size())
	rows[2].pressed.emit()
	_expect(asked == [["spring", CABBAGE]], "choosing one asks the field for it: %s" % [asked])
	panel.queue_free()
	farming.remove_zone(field)


func _saves(_field: int, _cells: Array[Vector3i]) -> void:
	var cells: Array[Vector3i] = [Vector3i(30, 20, 30), Vector3i(31, 20, 30), Vector3i(32, 20, 30)]
	_clock("autumn", 2, 8.0)
	var field: int = farming.create_zone(cells)
	farming.set_plan(field, "autumn", KALE)
	farming._zones[field].tiles[cells[0]] = {"crop": KALE, "credit": 10.0, "ripe": false, "picked": true, "regrow": 1.5}
	farming._zones[field].tiles[cells[1]] = {"crop": "", "credit": 0.0, "ripe": false, "work": 0.6, "job": "sow"}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(farming.serialize_state()))
	var Validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(Validator._validate(saved, Validator.SCENE.farming, "save.scene.farming", {}).is_empty(), "the section matches the save's rules")
	farming.restore_state(saved)
	var tile: Dictionary = farming.tile_at(cells[0])
	_expect(farming.zone_ids() == [field] and _plan(field) == [RADISH, CARROT, KALE, KALE] and tile.crop == KALE and tile.picked and is_equal_approx(tile.regrow, 1.5)
		and is_equal_approx(farming.tile_at(cells[1]).work, 0.6) and farming.tile_at(cells[2]).is_empty(), "fields, plans, plants and work begun survive a save")
	farming.refresh_work()
	farming._visuals.flush()
	_expect(_leases(field) > 0 and farming._visuals.model_of(cells[0]).ends_with("kale_picked.glb"), "a restored field posts its work and shows its plants again")
	_expect(farming.order_is_pending({"zone_id": field}) and farming.undo_order({"zone_id": field}) == 3 and farming.zone_ids().is_empty(), "the tool bar's Undo takes the field back")


## A real drag past the object explorer, which takes any world click unless it knows the tool.
func _drag() -> void:
	var state: SceneState = (load("res://scenes/main/debug_world.tscn") as PackedScene).get_state()
	var listed := false
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "ObjectExplorerController": continue
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == "click_tool_paths": listed = NodePath("../FarmingSystem") in (state.get_node_property_value(i, p) as Array)
	_expect(listed, "the main scene lists FarmingSystem among the explorer's click tools")
	explorer._tools.append(farming)
	_aim_above(Vector3(41, 20, 31))
	await process_frame
	farming.activate()
	var from: Vector2 = camera.unproject_position(Vector3(40.5, 21, 30.5))
	var to: Vector2 = camera.unproject_position(Vector3(42.5, 21, 31.5))
	_mouse_motion(from)
	_mouse_button(from, true)
	_mouse_motion(to)
	farming._tool.update_hover()   # the tool follows the pointer each frame; this fixture runs no frames
	_expect(farming.tool_bar_state().get("selection", {}).get("count", "") == "6 tiles", "the tool bar counts the tiles a drag takes: %s" % [farming.tool_bar_state()])
	_mouse_button(to, false)
	await process_frame
	var painted: Array = farming.zone_ids()
	_expect(painted.size() == 1 and farming.zone_data(painted[0]).counts.tiles == 6, "a real drag lays out a field of six tiles")
	farming.deactivate()


func _clock(season: String, day: int, hour: float) -> void:
	clock_node.year = 1
	clock_node.season = season
	clock_node.day = day
	clock_node.hour = hour
	clock_node._last_hour_int = int(hour)
	farming_started()


## The clock was set by hand: growth starts afresh from here.
func farming_started() -> void:
	if farming != null:
		farming._grown_at = clock_node.elapsed_days()
		farming.refresh_work()


func _farmer(id: int, cell: Vector3i) -> Node3D:
	var agent = _plain(id, cell)
	agent.profession = FARMER
	return agent


func _plain(id: int, cell: Vector3i) -> Node3D:
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var agent = factory.spawn(factory.generate(id, {}), id)
	scene.add_child(agent)
	agent.position = Vector3(cell) + Vector3(.5, 1, .5)
	agent.set_process(false)
	for stat: String in agent.stats: agent.stats[stat] = 3
	tasks.register_dwarf(agent)
	return agent


## Runs the scheduler and the Farmer until `done`, at most 300 game seconds.
func _until(done: Callable) -> bool:
	for i in range(3000):
		worker.get_food().value = 1.0   # a fed Farmer: no vegetable is eaten while they are counted
		worker.sleep = 1.0
		farming.refresh_work()
		tasks._run_scheduler()
		worker._process(.1)
		if done.call(): return true
		if i % 40 == 0: await process_frame
	return false


func _leases(field: int) -> int:
	var count := 0
	for index in range(2):
		var place = farming.place_of(field, index)
		if place != null and place.lease_id >= 0: count += 1
	return count


func _held_place(field: int) -> RefCounted:
	for index in range(2):
		var place = farming.place_of(field, index)
		if place != null and place.reserved_by == worker.dwarf_id: return place
	return null


func _sown(field: int, crop: String) -> int:
	var count := 0
	for tile: Dictionary in farming._zones[field].tiles.values():
		if String(tile.get("crop", "")) == crop: count += 1
	return count


func _plan(field: int) -> Array:
	var plan: Dictionary = farming._zones[field].plan
	return [plan.spring, plan.summer, plan.autumn, plan.winter]


## Units of a good lying loose, whatever crates they are in.
func _count(key: String) -> int:
	var count := 0
	for node: Node3D in drops._loose:
		if drops._loose[node] == key: count += drops.quantity_of(node)
	return count
