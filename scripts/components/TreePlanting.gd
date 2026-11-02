extends RefCounted

## Planted trees (doc 284). A seed placed through Place → Plants becomes a sapling
## that grows to mature and then ancient by the calendar. This helper holds the rules
## a planted tree keeps: where a seed may go, the ground and area its grown tree
## needs, and when it takes its next stage. SurfaceFloraSpawner owns the records,
## visuals, occupancy and saves, and hands its two tables over at construction (the
## FurniturePlacementRules way). No class_name: preloaded where used.
##
## Two squares, both centred on the seed:
## - the trunk box is the ancient trunk (placement.footprint.ancient by its
##   clearance_height): level, open-sky ground that no other plant may share, so the
##   trunk never runs out of room as it grows;
## - the area (planting.area) is the mature crown, the owner's pick: no other tree may
##   stand in it, and planted areas may touch but never overlap. Mature crowns never
##   meet; ancient ones may overlap a few blocks, as the wild forest's do.
## Below four blocks a tree is only its trunk (doc 63's walking clearance), so
## bushes, flowers, furniture and paths may still go under the crown.

const STAGES: Array[String] = ["sapling", "mature", "ancient"]
const WORLD_EDGE_MARGIN := 2
const WILD_REACH := 5.0 # The widest wild trunk; candidates this far out can still reach an area.

var flora: Node3D
var trees: Dictionary         # tree id -> live record (SurfaceFloraSpawner's)
var changes: Dictionary       # tree id -> saved forestry state; planted trees carry "planted"
var columns: Dictionary = {}  # Vector2i chunk column -> Array of planted tree ids
var waiting: Dictionary = {}  # tree id -> why its next stage waits; never saved


func _init(owner: Node3D, live: Dictionary, saved: Dictionary) -> void:
	flora = owner
	trees = live
	changes = saved


# ── Geometry (pure) ─────────────────────────────────────────────────────────────

## The trunk's minimum corner at `stage` for a tree planted on `anchor`, the seed's
## ground cell. Odd trunks stay centred on the seed; an even one takes its +X/+Z side.
static func stage_origin(species: Dictionary, stage: String, anchor: Vector3i) -> Vector3i:
	var offset := floori((int(species.placement.footprint[stage]) - 1) / 2.0)
	return anchor - Vector3i(offset, 0, offset)


## The space the ancient trunk will fill, from the ground up.
static func trunk_box(species: Dictionary, anchor: Vector3i) -> AABB:
	var width := int(species.placement.footprint.ancient)
	return AABB(Vector3(stage_origin(species, "ancient", anchor)) + Vector3.UP,
		Vector3(width, int(species.stages.ancient.clearance_height), width))


## The square no other tree may stand in: the mature crown, centred on the seed.
static func area_box(species: Dictionary, anchor: Vector3i) -> AABB:
	var size := int(species.planting.area)
	var half := floori(size / 2.0)
	return AABB(Vector3(anchor.x - half, anchor.y + 1, anchor.z - half),
		Vector3(size, int(species.stages.ancient.clearance_height), size))


## Growth days since planting: saved credit plus calendar days weighted by season.
static func grown_days(species: Dictionary, state: Dictionary) -> float:
	return float(state.get("growth_credit", 0.0)) + WorldClock.seasonal_days_between(
		float(state.planted_at), WorldClock.elapsed_days(), species.planting.seasonal_growth)


## Growth days from planting to reaching `stage`.
static func days_to(species: Dictionary, stage: String) -> float:
	var total := 0.0
	for name: String in STAGES:
		if name == stage: break
		total += float(species.stages[name].growth_duration_days)
	return total


## Any tree's saved state before work touches it: every felling field, nothing done.
static func base_state(key: String, stage: String, origin: Vector3i) -> Dictionary:
	return {"species": key, "stage": stage, "origin": origin, "work_seconds": 0.0,
		"designated": false, "felled": false, "action": "fell", "fell_work_seconds": 0.0,
		"harvest_work_seconds": 0.0, "harvest_work_cycle": "", "harvested_cycle": ""}


## The saved state of a seed just planted on `anchor`, with every felling field.
static func new_state(key: String, anchor: Vector3i) -> Dictionary:
	var origin := stage_origin(ContentRegistry.tree_species(key), "sapling", anchor)
	return base_state(key, "sapling", origin).merged({"planted": true, "anchor": anchor,
		"planted_at": WorldClock.elapsed_days(), "growth_credit": 0.0})


# ── Planted index ───────────────────────────────────────────────────────────────

func track(id: Vector2i) -> void:
	var column := Vector2i(id.x >> 4, id.y >> 4)
	if not columns.has(column): columns[column] = []
	if not id in columns[column]: columns[column].append(id)


func column_ids(column: Vector2i) -> Array:
	return columns.get(column, [])


func clear() -> void:
	columns.clear()
	waiting.clear()


## Standing planted trees, felled ones left out.
func standing() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for ids: Array in columns.values():
		for id: Vector2i in ids:
			var state: Dictionary = changes.get(id, {})
			if bool(state.get("planted", false)) and not bool(state.get("felled", false)): result.append(id)
	return result


## Whether a standing planted tree's trunk box meets `box`. Other plants keep off it.
func trunk_reserved(box: AABB) -> bool:
	for id: Vector2i in standing():
		var state: Dictionary = changes[id]
		if box.intersects(trunk_box(ContentRegistry.tree_species(String(state.species)), state.anchor)): return true
	return false


# ── Where a seed may go ─────────────────────────────────────────────────────────

## Why a seed of `key` cannot go on `anchor`, or "". The grown trunk's ground must be
## suitable, level, open to the sky and clear; the area must hold no other tree,
## standing, planted or queued. `ignore_ghost` is the plan checking its own site.
func reason(key: String, anchor: Vector3i, ignore_ghost := -1) -> String:
	var species := ContentRegistry.tree_species(key)
	if species.get("planting", {}).is_empty(): return "plant_soil"
	var ground := String(BlockRegistry.get_def(String(BlockRegistry.get_key(_block(anchor)))).get("kind", ""))
	if ground not in species.planting.ground_kinds: return "plant_soil"
	var trunk := trunk_box(species, anchor)
	if anchor.y + int(trunk.size.y) >= WorldData.WORLD_SIZE_Y: return "tree_ground"
	var placer: Node = flora.get_tree().get_first_node_in_group("furniture_controller")
	var zones: Node = flora.get_tree().get_first_node_in_group("stockpile_controller")
	for x in range(int(trunk.position.x), int(trunk.end.x)):
		for z in range(int(trunk.position.z), int(trunk.end.z)):
			if x < WORLD_EDGE_MARGIN or z < WORLD_EDGE_MARGIN or x >= WorldData.WORLD_SIZE_X - WORLD_EDGE_MARGIN \
					or z >= WorldData.WORLD_SIZE_Z - WORLD_EDGE_MARGIN:
				return "tree_ground"
			var cell := Vector3i(x, anchor.y, z)
			if not BlockRegistry.is_solid(_block(cell)) or WorldGenerator.lake_columns.has(Vector2i(x, z)) \
					or WorldGenerator.tarn_columns.has(Vector2i(x, z)):
				return "tree_ground"
			for y in range(anchor.y + 1, WorldData.WORLD_SIZE_Y):
				if _block(Vector3i(x, y, z)) != BlockRegistry.AIR_ID: return "tree_sky"
			if zones != null and zones.is_zone_cell(cell): return "plant_clearance"
			if placer != null and placer.get_installed_at(cell) != null: return "plant_clearance"
			for y in range(anchor.y + 1, anchor.y + int(trunk.size.y) + 1):
				if PlacedEntityRegistry.occupies(Vector3i(x, y, z)): return "plant_clearance"
	var details: Node = flora.get_tree().get_first_node_in_group("surface_details")
	if details != null and details.detail_in(trunk): return "plant_clearance"
	if placer != null and placer.plant_area_reserved(trunk, ignore_ghost): return "plant_clearance"
	var area := area_box(species, anchor)
	if _tree_in(area) or (placer != null and placer.tree_area_reserved(area, ignore_ghost)): return "tree_spacing"
	return ""


## Whether another tree stands in `area`: a wild tree's trunk, from the seeded
## candidates so trees not yet streamed in count, or a planted tree's whole area.
func _tree_in(area: AABB) -> bool:
	var size := maxi(1, int(flora.scatter_cell_size))
	var reach := area.grow(WILD_REACH)
	for cell_x in range(floori(reach.position.x / size), floori(reach.end.x / size) + 1):
		for cell_z in range(floori(reach.position.z / size), floori(reach.end.z / size) + 1):
			var wild: Dictionary = flora.generated_tree_candidate(cell_x, cell_z, size)
			if wild.is_empty(): continue
			var origin: Vector3i = wild.origin
			var state: Dictionary = changes.get(Vector2i(origin.x, origin.z), {})
			if bool(state.get("felled", false)) or bool(state.get("planted", false)): continue
			var width := int(wild.footprint)
			if area.intersects(AABB(Vector3(origin) + Vector3.UP, Vector3(width, int(wild.stage_data.clearance_height), width))):
				return true
	for id: Vector2i in standing():
		var state: Dictionary = changes[id]
		if area.intersects(area_box(ContentRegistry.tree_species(String(state.species)), state.anchor)): return true
	return false


# ── Growth ──────────────────────────────────────────────────────────────────────

## The stage a planted tree takes now, or "". Growth waits for room, and for any
## order on the tree to finish, so felling and picking keep the trunk they began on.
func next_stage(id: Vector2i) -> String:
	waiting.erase(id)
	var state: Dictionary = changes.get(id, {})
	if not bool(state.get("planted", false)) or bool(state.get("felled", false)) or bool(state.get("designated", false)):
		return ""
	var index := STAGES.find(String(state.stage))
	if index < 0 or index >= STAGES.size() - 1: return ""
	var species := ContentRegistry.tree_species(String(state.species))
	var next: String = STAGES[index + 1]
	if grown_days(species, state) + .000001 < days_to(species, next): return ""
	var why := room_reason(id, next)
	if not why.is_empty():
		waiting[id] = why
		return ""
	return next


## Why a planted tree cannot take `stage` yet, or "": its new trunk needs level
## ground and open air to its clearance, with nothing built, stored, standing or
## lying in the way. Its own current trunk does not count.
func room_reason(id: Vector2i, stage: String) -> String:
	var state: Dictionary = changes[id]
	var species := ContentRegistry.tree_species(String(state.species))
	var anchor: Vector3i = state.anchor
	var origin := stage_origin(species, stage, anchor)
	var width := int(species.placement.footprint[stage])
	var height := int(species.stages[stage].clearance_height)
	var size := "%d × %d" % [width, width]
	var own: Array[int] = [int(trees.get(id, {}).get("occupancy_id", -1))]
	var placer: Node = flora.get_tree().get_first_node_in_group("furniture_controller")
	var zones: Node = flora.get_tree().get_first_node_in_group("stockpile_controller")
	for x in range(origin.x, origin.x + width):
		for z in range(origin.z, origin.z + width):
			var ground := Vector3i(x, anchor.y, z)
			if not BlockRegistry.is_solid(_block(ground)): return "Its %s trunk needs level ground" % size
			if zones != null and zones.is_zone_cell(ground): return "A stockpile covers its %s trunk" % size
			if placer != null and (placer.get_installed_at(ground) != null or placer.get_ghost_at(ground) != null):
				return "Furniture stands where its %s trunk grows" % size
			for y in range(anchor.y + 1, anchor.y + height + 1):
				if _block(Vector3i(x, y, z)) != BlockRegistry.AIR_ID: return "Blocks fill its %s × %d trunk space" % [size, height]
				if PlacedEntityRegistry.occupies(Vector3i(x, y, z), own): return "Something stands where its %s trunk grows" % size
	var box := AABB(Vector3(origin) + Vector3.UP, Vector3(width, height, width))
	for dwarf: DwarfAgent in TaskManager.get_agents():
		if box.has_point(Vector3(dwarf.current_cell()) + Vector3(.5, 1.5, .5)): return "A dwarf stands where its %s trunk grows" % size
	var wildlife: Node = flora.get_tree().get_first_node_in_group("wildlife")
	if wildlife != null:
		for animal: Node3D in wildlife.animals:
			if is_instance_valid(animal) and box.has_point(animal.global_position + Vector3(0, .5, 0)):
				return "An animal stands where its %s trunk grows" % size
	var drops := ItemDropManager.find(flora.get_tree())
	if drops != null:
		for item: Node3D in drops.loose_items():
			if is_instance_valid(item) and box.has_point(Vector3(drops.item_floor_cell(item)) + Vector3(.5, 1.5, .5)):
				return "Items lie where its %s trunk grows" % size
	return ""


## DEV: enough growth credit for the next stage. Room still decides when it grows.
func dev_grow(id: Vector2i) -> void:
	var state: Dictionary = changes.get(id, {})
	var index := STAGES.find(String(state.get("stage", "")))
	if not bool(state.get("planted", false)) or index < 0 or index >= STAGES.size() - 1: return
	var species := ContentRegistry.tree_species(String(state.species))
	var short := days_to(species, STAGES[index + 1]) - grown_days(species, state)
	state.growth_credit = float(state.get("growth_credit", 0.0)) + maxf(0.0, short)


# ── Panel ───────────────────────────────────────────────────────────────────────

## A planted tree's growth for its panel: a row, its status and a note.
func describe(id: Vector2i) -> Dictionary:
	var state: Dictionary = changes[id]
	var species := ContentRegistry.tree_species(String(state.species))
	var stage := String(state.stage)
	var trunk := int(species.placement.footprint.ancient)
	var area := int(species.planting.area)
	var note := "Planted from a seed. It grows to mature and then ancient with the seasons; winter pauses growth. " \
		+ "Its grown trunk needs %d × %d of open ground, and no other tree may stand in its %d × %d area." % [trunk, trunk, area, area]
	var index := STAGES.find(stage)
	if index >= STAGES.size() - 1:
		return {"row": ["Growth", "Fully grown"], "status": stage.capitalize(), "tone": "fine", "note": note}
	var next: String = STAGES[index + 1]
	var start := days_to(species, stage)
	var need := days_to(species, next)
	var grown := grown_days(species, state)
	var percent := floori(clampf((grown - start) / maxf(need - start, .001), 0.0, 1.0) * 100)
	if waiting.has(id):
		return {"row": ["Growth", "Waiting · " + String(waiting[id])], "status": "%s · waiting for room" % stage.capitalize(),
			"tone": "blocked", "note": note}
	var row := "%s in %.1f growth days" % [next.capitalize(), maxf(0.0, need - grown)]
	var status := "%s · growing %d%%" % [stage.capitalize(), percent]
	if float(species.planting.seasonal_growth.get(WorldClock.season, 1.0)) <= 0.0:
		status = "%s · dormant" % stage.capitalize()
		row += " · paused in %s" % WorldClock.season
	return {"row": ["Growth", row], "status": status, "tone": "fine", "note": note}


func _block(pos: Vector3i) -> int:
	if WorldData.get_chunk_if_exists(pos.x >> 4, pos.y >> 4, pos.z >> 4) != null:
		return WorldData.get_block(pos.x, pos.y, pos.z)
	return WorldData.get_live_block(pos.x, pos.y, pos.z)
