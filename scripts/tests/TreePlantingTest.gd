extends "res://scripts/tests/ShrubCuttingTest.gd"

## Tree seeds (doc 284): Place → Plants plants one seed with a real dwarf, and the
## sapling grows to mature and ancient by the calendar. Its ancient trunk ground and
## area keep other plants and trees away from the start; growth waits for room;
## planted trees fell, save and restore like wild ones.
## godot --headless --path . --script res://scripts/tests/TreePlantingTest.gd
const PINE := "base:flora:pine_tree"
const JUNIPER := "base:flora:juniper_tree"
const CONE := "base:flora:pine_cone"
const CONE_ITEM := "base:resources:seed:pine_cone"
const SITE := Vector3i(50, 20, 52)
const STONE := "base:resources:stone:rough_stone"
var content
var occupancy
var Planting # TreePlanting.gd, loaded once the autoloads it names exist.


func _run() -> void:
	_setup_cuttings()
	Planting = load("res://scripts/components/TreePlanting.gd")
	content = root.get_node("ContentRegistry")
	occupancy = root.get_node("PlacedEntityRegistry")
	var gen = root.get_node("WorldGenerator")
	gen.domain_map.resize(1024 * 1024)
	gen.domain_map.fill(-1) # Cleared land: no wild tree stands anywhere until the wild check.
	gen.noise_moisture = FastNoiseLite.new()
	gen.waterline_map.resize(1024 * 1024) # Block edits compare against the flat baseline.
	gen.waterline_map.fill(-1)
	gen._cache_block_ids()
	flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	flora.name = "Flora"
	scene.add_child(flora)
	flora.set_process(false)
	for column: Vector2i in [Vector2i(2, 3), Vector2i(3, 3)]: flora._loaded_columns[column] = [] # Streamed in.
	await process_frame
	_season("summer")
	_check_definitions()
	_check_site_rules()
	_check_wild_trees()
	var id := await _check_planting()
	_check_growth(id)
	_check_juniper()
	await _check_save(id)
	await _check_felling(id)
	for failure: String in failures: push_error(failure)
	print("TREE_PLANTING_OK" if failures.is_empty() else "TREE_PLANTING_FAIL: %s" % failures)
	quit(0 if failures.is_empty() else 1)


func _check_definitions() -> void:
	var listed: Array = root.get_node("UIRegistry").get_place_catalog().items.map(func(entry: Dictionary): return entry.key)
	for pair: Array in [["base:flora:oak_acorn", "base:flora:oak_tree"], ["base:flora:apple_seed", "base:flora:apple_tree"],
			[CONE, PINE], ["base:flora:juniper_seed", JUNIPER]]:
		var definition: Dictionary = content.furniture_def(pair[0])
		_expect(definition.get("tree_species") == pair[1] and bool(definition.get("plant")) and content.has_item(String(definition.item_key))
			and furniture.get_defs().has(pair[0]) and pair[0] in listed, "%s is a Place → Plants entry for its tree" % pair[0])
	var oak: Dictionary = content.tree_species("base:flora:oak_tree")
	_expect(Planting.trunk_box(oak, SITE) == AABB(Vector3(48, 21, 50), Vector3(5, 10, 5)), "an oak keeps a 5 × 5 trunk centred on its acorn")
	_expect(Planting.area_box(oak, SITE).size.x == 13 and Planting.area_box(oak, SITE).get_center().x == SITE.x + .5, "and a 13 × 13 area, its mature crown, centred on it")


func _check_site_rules() -> void:
	_expect(flora.planting_reason(PINE, SITE).is_empty(), "clear level grass takes a pine cone")
	_expect(flora.planting_reason(PINE, Vector3i(20, 20, 50)) == "plant_soil", "bare rock is no seed bed")
	world.set_block(51, 30, 53, blocks.get_id("base:terrain:rock:rock01"))
	_expect(flora.planting_reason(PINE, SITE) == "tree_sky", "rock over the grown trunk refuses the seed")
	world.set_block(51, 30, 53, blocks.AIR_ID)
	world.set_block(49, 20, 51, blocks.AIR_ID)
	_expect(flora.planting_reason(PINE, SITE) == "tree_ground", "a hole in the grown trunk's ground refuses the seed")
	world.set_block(49, 20, 51, blocks.get_id("base:terrain:surface:grass"))
	_expect(flora.planting_reason(PINE, Vector3i(42, 20, 41)) == "plant_clearance", "a bush on the grown trunk's ground refuses the seed")
	_expect(flora.planting_reason(PINE, SITE).is_empty(), "the site is clear again")


## Wild trees count from their seeded candidates, streamed in or not.
func _check_wild_trees() -> void:
	var gen = root.get_node("WorldGenerator")
	gen.domain_map.fill(2) # Mountain: pines and junipers may stand anywhere.
	var anchor := Vector3i(-1, -1, -1)
	for cell_x in range(2, 5):
		for cell_z in range(3, 5):
			var wild: Dictionary = flora.generated_tree_candidate(cell_x, cell_z, flora.scatter_cell_size)
			if wild.is_empty() or anchor.x >= 0: continue
			var origin: Vector3i = wild.origin
			if origin.x >= 40 and origin.x <= 62 and origin.z >= 44 and origin.z <= 60: anchor = origin - Vector3i(3, 0, 0)
	_expect(anchor.x >= 0, "the fixture holds a wild tree to plant beside")
	if anchor.x >= 0: _expect(flora.planting_reason(PINE, anchor) == "tree_spacing", "a wild tree inside the area refuses the seed")
	gen.domain_map.fill(-1)
	if anchor.x >= 0: _expect(flora.planting_reason(PINE, anchor).is_empty(), "the same spot takes it once the land is clear")


func _check_planting() -> Vector2i:
	drops.spawn_drop(CONE_ITEM, 3, Vector3i(37, 21, 43))
	var plan := _seed_plan(CONE, SITE)
	_expect(int(furniture.get_catalog_stock()[CONE].available) == 2, "one plan reserves one cone, not the crate")
	_expect(flora.planting_reason(PINE, SITE + Vector3i(6, 0, 0)) == "tree_spacing", "a queued seed keeps its 7 × 7 area from other trees")
	_expect(flora.planting_reason(PINE, SITE + Vector3i(7, 0, 0)).is_empty(), "tree areas may touch")
	_expect(details.planting_reason("base:flora:blueberry_bush", SITE + Vector3i(1, 0, 1)) == "plant_spacing", "a queued seed keeps bushes off its grown trunk")
	_expect(await _wait_for(func(): return not furniture._ghosts.has(plan)), "a dwarf plants the cone")
	var id := Vector2i(SITE.x, SITE.z)
	var state: Dictionary = flora._tree_changes.get(id, {})
	_expect(bool(state.get("planted", false)) and state.get("stage") == "sapling" and _cutting_count("pine_cone") == 2, "one cone makes one sapling")
	_expect(flora._trees.has(id) and is_instance_valid(flora._trees[id].node) and not flora._trees[id].node is StaticBody3D, "the sapling stands without a body")
	_expect(details.planting_reason("base:flora:blueberry_bush", SITE + Vector3i(1, 0, 1)) == "plant_spacing", "a planted sapling keeps bushes off its grown trunk")
	_expect(details.planting_reason("base:flora:blueberry_bush", SITE + Vector3i(3, 0, 0)).is_empty(), "bushes may grow under its crown")
	var panel: Dictionary = flora.get_explorer_data(id)
	_expect(panel.rows[1][0] == "Growth" and String(panel.status.text).begins_with("Sapling · growing"), "its panel shows its growth")
	worker.position = Vector3(36.5, 21, 40.5) # Out of the way of the growing trunk.
	return id


func _check_growth(id: Vector2i) -> void:
	var pine: Dictionary = content.tree_species(PINE)
	clock_node.advance_hours(float(pine.stages.sapling.growth_duration_days) * 24.0 - 1.0)
	_expect(flora._tree_changes[id].stage == "sapling", "a sapling waits for its growth days")
	clock_node.advance_hours(1.0)
	_expect(flora._tree_changes[id].stage == "mature" and flora._tree_changes[id].origin == SITE, "summer growth days make a mature pine")
	_expect(flora._trees[id].node is StaticBody3D and occupancy.occupies(Vector3i(51, 21, 53)) and not occupancy.occupies(Vector3i(49, 21, 51)),
		"its 2 × 2 trunk stands on the seed's +X/+Z side and blocks")
	drops.spawn_drop(STONE, 1, Vector3i(49, 21, 51))
	clock_node.advance_hours(float(pine.stages.mature.growth_duration_days) * 24.0)
	_expect(flora._tree_changes[id].stage == "mature" and flora._planting.waiting.has(id), "a stone where the trunk would grow holds it at mature")
	var panel: Dictionary = flora.get_explorer_data(id)
	_expect(String(panel.status.text).contains("waiting") and String(panel.rows[1][1]).begins_with("Waiting"), "its panel says it waits for room")
	for node: Node3D in drops._loose.keys():
		if drops.item_key_of(node) == STONE: drops.discard(node)
	clock_node.advance_hours(1.0)
	_expect(flora._tree_changes[id].stage == "ancient" and flora._tree_changes[id].origin == Vector3i(49, 20, 51), "with room it grows ancient")
	_expect(occupancy.occupies(Vector3i(49, 21, 51)) and occupancy.occupies(Vector3i(51, 42, 53)) and not occupancy.occupies(Vector3i(52, 21, 52)),
		"its 3 × 3 trunk is centred on the seed again, 22 high")
	_expect(flora.get_explorer_data(id).rows[1][1] == "Fully grown", "an ancient tree is fully grown")


## Winter dormancy, then DEV growth to an ancient juniper, whose 3 × 3 trunk centres on the seed.
func _check_juniper() -> void:
	_season("winter")
	var anchor := Vector3i(43, 20, 58)
	_expect(flora.planting_reason(JUNIPER, anchor).is_empty(), "a juniper fits beside the pine; their areas touch")
	var id: Vector2i = flora.plant_tree(JUNIPER, anchor)
	clock_node.advance_hours(48.0)
	var juniper: Dictionary = content.tree_species(JUNIPER)
	_expect(is_zero_approx(Planting.grown_days(juniper, flora._tree_changes[id])) and flora._tree_changes[id].stage == "sapling", "winter pauses growth")
	_expect(String(flora.get_explorer_data(id).status.text).ends_with("dormant"), "its panel says it is dormant")
	for i in range(2): flora.perform_explorer_action(id, "dev_grow")
	_expect(flora._tree_changes[id].stage == "ancient" and flora._tree_changes[id].origin == anchor - Vector3i(1, 0, 1), "DEV growth reaches ancient")
	_expect(occupancy.occupies(Vector3i(42, 21, 57)) and occupancy.occupies(Vector3i(44, 21, 59)) and not occupancy.occupies(Vector3i(45, 21, 60)),
		"the ancient juniper's 3 × 3 trunk is centred on its seed")
	_season("summer", 2)


func _check_save(id: Vector2i) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(flora.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(validator._validate(saved, validator.SCENE.flora, "save.scene.flora", content.save_catalogs()).is_empty(), "the save schema takes planted trees")
	var fresh = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	fresh.name = "RestoredFlora"
	scene.add_child(fresh)
	fresh.set_process(false)
	fresh._loaded_columns[Vector2i(3, 3)] = []
	fresh.restore_state(saved)
	_expect(fresh._tree_changes[id].stage == "ancient" and fresh._tree_changes[id].origin == Vector3i(49, 20, 51)
		and is_instance_valid(fresh._trees[id].node), "a fresh owner rebuilds the planted pine at its stage")
	_expect(JSON.parse_string(JSON.stringify(fresh.serialize_state())) == saved, "planted trees round-trip")
	var wild_stage: Dictionary = fresh._species_for_key(PINE).stages.mature
	_expect(fresh._instance_tree("pine", "", "mature", wild_stage, SITE.x, SITE.z, SITE.y, 2) == null, "a wild tree of that column never returns")
	scene.remove_child(fresh)
	fresh.free()
	_expect(occupancy.occupies(Vector3i(50, 21, 52)), "freeing the copy leaves the live trunk's occupancy")
	await process_frame


func _check_felling(id: Vector2i) -> void:
	flora.designate_felling(id)
	_expect(await _wait_for(func(): return bool(flora._tree_changes[id].felled)), "a dwarf fells the planted pine")
	var logs := 0
	for node: Node3D in drops._loose.keys():
		if drops.item_key_of(node) == "base:resources:wood:pine_log": logs += drops.quantity_of(node)
	_expect(logs == 10 and not occupancy.occupies(Vector3i(50, 21, 52)), "it gives an ancient pine's logs and frees its trunk")
	_expect(flora.planting_reason(PINE, SITE).is_empty(), "its spot takes a new seed")
	flora.plant_tree(PINE, SITE)
	_expect(flora._tree_changes[id].stage == "sapling" and not flora._tree_changes[id].felled, "a felled tree's column holds a new sapling")


func _seed_plan(key: String, target: Vector3i) -> int:
	furniture.activate_for(key, true)
	furniture._hover_cell = target
	furniture._hover_valid = furniture._placement_valid(target)
	_expect(furniture._hover_valid, "the seed site is valid")
	var id: int = furniture._next_ghost_id
	furniture._confirm_ghost()
	furniture.deactivate()
	return id
