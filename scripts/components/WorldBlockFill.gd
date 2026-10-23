extends RefCounted

## Per-block terrain identity for WorldGenerator (doc 43): authored strata, the
## surface skin and resource veins, plus the block ids, resource windows, shelf
## bands and metal noise fields they read. WorldGenerator owns the column maps,
## caves and noise; this reads them through `generator`.
##
## Thread safety: everything here is written on the main thread before the
## generator thread starts (cache_block_ids, apply_shelf_bands), or by the
## generator phase that owns it before maps_ready (metal_noise,
## build_resource_cover_maps). After that every read is pure, so
## generate_block_id may run on the generator thread and WorkerThreadPool tasks.

# All "/" between two ints here are intentional, exact integer divisions.
@warning_ignore_start("integer_division")

const WorldSize = preload("res://scripts/systems/WorldSize.gd")
const WORLD_SIZE_X: int = WorldSize.WORLD_SIZE_X
const WORLD_SIZE_Y: int = WorldSize.WORLD_SIZE_Y
const WORLD_SIZE_Z: int = WorldSize.WORLD_SIZE_Z
const CHUNK_SIZE: int = 16   # WorldData.CHUNK_SIZE
const CHUNK_COUNT_Y: int = WORLD_SIZE_Y / CHUNK_SIZE

# -- Terrain domain classification ---------------------------------------------
const DOMAIN_MOUNTAIN: int = 2   # Y44+, mountain shelves
const DOMAIN_VALLEY:   int = 1   # Y20..43, foothill shelves (retained API name)
const DOMAIN_LOWLAND:  int = 0   # Y19 and below, lowland / lake basin

# -- Surface elevation ranges (Y in blocks) ------------------------------------
const BEDROCK_MAX_Y: int = 3
const FOUNDATION_ROCK_MAX_Y: int = 11
const LOWLAND_SHELF_MIN_Y: int = 12
const MATERIAL_MACRO_CELL_SIZE: int = 32
const STEEP_SLOPE_ROCK_DELTA: int = 3

# -- Resource distribution order ----------------------------------------------
# Rarest-first. Placement windows are cached from block_resources.json on the
# main thread before generation starts so the worker never touches registries.
const METAL_RESOURCE_KEYS: Array = [&"base:terrain:ore:gold", &"base:terrain:ore:silver",
	&"base:terrain:ore:iron", &"base:terrain:ore:copper", &"base:terrain:ore:tin", &"base:terrain:ore:coal"]
const GEM_RESOURCE_KEYS: Array = [&"base:terrain:gem:diamond", &"base:terrain:gem:emerald",
	&"base:terrain:gem:sapphire", &"base:terrain:gem:ruby", &"base:terrain:gem:amethyst", &"base:terrain:gem:jade"]
const SOIL_RESOURCE_KEYS: Array = [&"base:terrain:soil:cave"]
const RESOURCE_PERIMETER_SUPPRESSION_WIDTH: int = 8

var generator: Node

# Direct references to generator layers that are only ever replaced by assignment;
# the generator's setters call bind_layers, so the per-block path avoids named
# lookups. The packed maps and world_seed stay live reads because tests edit them
# in place through the generator.
var cave_columns: Dictionary = {}
var cave_soil: Dictionary = {}
var noise_gem: FastNoiseLite
var noise_soil: FastNoiseLite
var noise_domain: FastNoiseLite
var lake_columns: Dictionary = {}
var tarn_columns: Dictionary = {}
var water_bank_columns: Dictionary = {}

# Shelf bands from the layout profile's shelf_tops (apply_shelf_bands):
# rank 0 lowland, ranks 1-3 foothill shelves, ranks 4-9 mountain shelves.
var lowland_shelf_max_y := 0
var foothill_shelf_min_y := 0
var foothill_shelf_max_y := 0
var foothill_shelf_height := 0
var mountain_min := 0
var mountain_max := 0
var mountain_shelf_height := 0

# Pre-cached runtime block IDs - looked up on the main thread before generation
# starts so the background thread never calls BlockRegistry directly.
var id_void:      int = 0
var id_bedrock:   int = 0
var id_water:     int = 0
var id_rock07:    int = 0
var id_rock08:    int = 0
var id_rock09:    int = 0
var id_rock10:    int = 0
var id_rock11:    int = 0
var id_cave_soil: int = -1
var mountain_rock_ids: Array[int] = [] # shelf 1..6 -> rock06..rock01
var grass_ids:    Array[int] = []   # [0..7] -> active grass_01..grass_08
var dirt_ids:     Array[int] = []   # [0..3]  -> dirt_01..dirt_04
var resource_replaceable_rock_ids: Dictionary = {}
var metal_windows: Array[Dictionary] = []
var metal_noise: Array[FastNoiseLite] = [] # one field per cached metal window
var resource_cover_maps: Dictionary = {} # burial radius -> natural minimum surface
var gem_windows:   Array[Dictionary] = []
var soil_windows:  Array[Dictionary] = []
var resource_focus_windows: Array[Dictionary] = []


func _init(owner: Node) -> void:
	generator = owner


func bind_layers() -> void:
	var caves: Dictionary = generator.cave_layout()
	cave_columns = caves.get("columns", {})
	cave_soil = caves.get("soil", {})
	noise_gem = generator.noise_gem
	noise_soil = generator.noise_soil
	noise_domain = generator.noise_domain
	lake_columns = generator.lake_columns
	tarn_columns = generator.tarn_columns
	water_bank_columns = generator.water_bank_columns


## Autoloads are resolved at run time so this script also compiles inside
## --script tests, which load it before any autoload exists.
static func _autoload(autoload_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(autoload_name)


## Returns false (and keeps the old bands) when the profile has no valid
## shelf_tops; LayoutValidator.profile_errors reports that case.
func apply_shelf_bands(tops: Array) -> bool:
	if tops.size() != 10: return false
	lowland_shelf_max_y = int(tops[0]);  foothill_shelf_min_y = int(tops[0]) + 1;  foothill_shelf_max_y = int(tops[3])
	foothill_shelf_height = int(tops[1]) - int(tops[0]);  mountain_min = int(tops[3]) + 1
	mountain_max = int(tops[9]);  mountain_shelf_height = int(tops[4]) - int(tops[3])
	return true


# -- ID cache (main thread) ----------------------------------------------------

func cache_block_ids() -> void:
	var registry := _autoload("BlockRegistry")
	id_cave_soil = registry.get_id(&"base:terrain:soil:cave")
	id_void      = registry.get_id(&"base:terrain:void")
	id_bedrock   = registry.get_id(&"base:terrain:bedrock")
	id_water     = registry.get_id(&"base:terrain:water:source")
	id_rock07    = registry.get_id(&"base:terrain:rock:rock07")
	id_rock08    = registry.get_id(&"base:terrain:rock:rock08")
	id_rock09    = registry.get_id(&"base:terrain:rock:rock09")
	id_rock10    = registry.get_id(&"base:terrain:rock:rock10")
	id_rock11    = registry.get_id(&"base:terrain:rock:rock11")
	resource_replaceable_rock_ids.clear()
	for i in range(1, 12):
		resource_replaceable_rock_ids[registry.get_id(StringName("base:terrain:rock:rock%02d" % i))] = true

	mountain_rock_ids.clear()
	for i in range(6, 0, -1):
		mountain_rock_ids.append(registry.get_id(StringName("base:terrain:rock:rock%02d" % i)))

	grass_ids.clear()
	for i in range(1, 9):
		grass_ids.append(registry.get_id(StringName("base:terrain:surface:grass_%02d" % i)))

	dirt_ids.clear()
	for i in range(1, 5):
		dirt_ids.append(registry.get_id(StringName("base:terrain:surface:dirt_%02d" % i)))

	_cache_resource_windows()


func _cache_resource_windows() -> void:
	metal_windows = _build_resource_windows(METAL_RESOURCE_KEYS, "ore")
	gem_windows = _build_resource_windows(GEM_RESOURCE_KEYS, "gem")
	soil_windows = _build_resource_windows(SOIL_RESOURCE_KEYS, "soil")

	resource_focus_windows.clear()
	resource_focus_windows.append_array(gem_windows)
	resource_focus_windows.append_array(metal_windows)
	resource_focus_windows.append_array(soil_windows)


func _build_resource_windows(keys: Array, expected_channel: String) -> Array[Dictionary]:
	var registry := _autoload("BlockRegistry")
	var windows: Array[Dictionary] = []
	for key_variant: Variant in keys:
		var key := key_variant as StringName
		var id: int = registry.get_id(key)
		if id < 0:
			push_warning("WorldGenerator: resource block key is not registered: %s" % String(key))
			continue

		var def: Dictionary = registry.get_resource_def(key)
		if def.is_empty():
			push_warning("WorldGenerator: missing block_resources metadata for %s" % String(key))
			continue

		var channel := String(def.get("noise_channel", ""))
		if channel != expected_channel:
			push_warning("WorldGenerator: %s uses noise_channel '%s', expected '%s'." % [String(key), channel, expected_channel])
			continue

		var depth_bias: Dictionary = def.get("depth_bias", {})
		var noise_field: Dictionary = def.get("noise_field", {})
		if expected_channel == "ore" and (not noise_field.has("seed_offset") or float(noise_field.get("frequency", 0.0)) <= 0.0 or int(noise_field.get("octaves", 0)) < 1 or int(noise_field.get("octaves", 0)) > 10):
			push_error("WorldGenerator: missing or invalid ore noise_field for %s." % String(key))
			continue
		windows.append({
			"key": key,
			"id": id,
			"min_y": int(depth_bias.get("min_y", 0)),
			"max_y": int(depth_bias.get("max_y", WORLD_SIZE_Y - 1)),
			"threshold": float(def.get("noise_threshold", 1.0)),
			"shallow_threshold": float(def.get("shallow_noise_threshold",def.get("noise_threshold",1.0))),
			"channel": channel,
			"noise_field": noise_field.duplicate(true),
			"min_burial": int(def.get("min_burial",0)),
		})
	return windows


# -- Block fill (3D, per chunk) ------------------------------------------------

## Writes one 16x16 chunk column of generated blocks into WorldData. The game
## renders from the generator maps and never calls this; tests use it to
## compare materialised blocks with get_generated_block_id().
func fill_chunk_column(cx: int, cz: int) -> void:
	var top_y := _column_chunk_max_y(cx, cz)
	var top_cy := top_y / CHUNK_SIZE

	for cy in range(CHUNK_COUNT_Y):
		if cy > top_cy:
			continue

		var chunk := Chunk.new()
		for ly in range(CHUNK_SIZE):
			var wy := cy * CHUNK_SIZE + ly
			for lx in range(CHUNK_SIZE):
				var wx := cx * CHUNK_SIZE + lx
				for lz in range(CHUNK_SIZE):
					var wz := cz * CHUNK_SIZE + lz
					chunk.blocks[Chunk.local_index(lx, ly, lz)] = generate_block_id(wx, wy, wz)

		_autoload("WorldData").submit_chunk(cx, cy, cz, chunk)


## Highest world-Y that a chunk column (cx, cz) can contain a non-void block.
## Scans the column's 16x16 surface footprint and clamps to at least the lake
## waterline so water-filled basins above the carved floor are not pruned.
func _column_chunk_max_y(cx: int, cz: int) -> int:
	var heightmap: PackedInt32Array = generator.heightmap
	var waterline_map: PackedInt32Array = generator.waterline_map
	var max_y := 0
	for x in range(cx * CHUNK_SIZE, (cx + 1) * CHUNK_SIZE):
		for z in range(cz * CHUNK_SIZE, (cz + 1) * CHUNK_SIZE):
			var index := x * WORLD_SIZE_Z + z
			max_y = maxi(max_y, maxi(heightmap[index], waterline_map[index]))
	return max_y


# apply_resource_detail: when false, the authored strata rock is returned
# without ore/gem/soil vein replacement and without cave voids. The block-face
# overview uses this for cliff-side coloring, where the 3D resource/cave noise
# is invisible at navigation zoom but dominates the per-column cost. Real chunk
# generation always passes true. The caller checks bounds and maps_ready.
func generate_block_id(x: int, y: int, z: int, apply_resource_detail: bool = true) -> int:
	var index := x * WORLD_SIZE_Z + z
	var surf_y: int = generator.heightmap[index]

	# Absolute floor - four-layer bedrock protocol.
	if y <= BEDROCK_MAX_Y:
		return id_bedrock

	# Stable foundation layer above bedrock.
	if y > BEDROCK_MAX_Y and y <= FOUNDATION_ROCK_MAX_Y:
		return _apply_resource_veins(x, y, z, surf_y, id_rock11) if apply_resource_detail else id_rock11

	# Above surface
	if y > surf_y:
		if y <= generator.waterline_map[index]:
			return id_water
		return id_void

	if apply_resource_detail:
		var cave: Vector3i = cave_columns.get(index, Vector3i(-1, -1, -1))
		if y > cave.x and y <= cave.y: return id_void

	# Shelf membership is a property of the column height (surf_y).
	if _is_lowland_shelf_height(surf_y) and y >= LOWLAND_SHELF_MIN_Y and y <= lowland_shelf_max_y:
		var lowland_block := _lowland_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, lowland_block) if apply_resource_detail else lowland_block

	if _is_foothill_shelf_height(surf_y) and y >= LOWLAND_SHELF_MIN_Y and y < _foothill_shelf_start_for_height(surf_y):
		var foothill_body_block := _foothill_body_rock_id(y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_body_block) if apply_resource_detail else foothill_body_block

	if _is_foothill_shelf_height(surf_y) and y >= foothill_shelf_min_y and y <= foothill_shelf_max_y:
		var foothill_shelf_block := _foothill_shelf_block_id(x, z, y)
		return _apply_resource_veins(x, y, z, surf_y, foothill_shelf_block) if apply_resource_detail else foothill_shelf_block

	if _is_mountain_shelf_height(surf_y) and y >= LOWLAND_SHELF_MIN_Y and y < mountain_min:
		var mountain_body_block := _altitude_rock_body_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_body_block) if apply_resource_detail else mountain_body_block

	if _is_mountain_shelf_height(surf_y) and y >= mountain_min and y <= mountain_max:
		var mountain_shelf_block := _mountain_shelf_block_id(y)
		return _apply_resource_veins(x, y, z, surf_y, mountain_shelf_block) if apply_resource_detail else mountain_shelf_block

	# Surface skin
	if y == surf_y:
		return _pick_surface_block(x, z, Vector2i(x, z))

	# Fallback for columns outside authored strata ranges. Current worldgen
	# should rarely reach this; keep it on the active rock ladder if it does.
	var fallback_rock := fallback_rock_id(y)
	return _apply_resource_veins(x, y, z, surf_y, fallback_rock) if apply_resource_detail else fallback_rock


func _is_foothill_shelf_height(h: int) -> bool:
	return h >= foothill_shelf_min_y and h <= foothill_shelf_max_y


func _is_lowland_shelf_height(h: int) -> bool:
	return h >= LOWLAND_SHELF_MIN_Y and h <= lowland_shelf_max_y


func _is_mountain_shelf_height(h: int) -> bool:
	return h >= mountain_min and h <= mountain_max


func _pick_surface_block(x: int, z: int, col: Vector2i) -> int:
	var idx := x * WORLD_SIZE_Z + z
	var height: int = generator.heightmap[idx]
	var slope := _surface_slope(x, z)
	var domain: int = generator.domain_map[idx]
	var region := _surface_region_value(x, z, 0)

	# Submerged floors and immediate banks are soil/stone, never grass.
	if lake_columns.has(col) or tarn_columns.has(col):
		if _surface_region_value(x, z, 7) > 0.72:
			return _pick_surface_rock(x, z, height)
		return _dirt_variant(x, z)
	if _is_water_bank(x, z):
		if slope >= 2 or _surface_region_value(x, z, 11) > 0.68:
			return _pick_surface_rock(x, z, height)
		return _dirt_variant(x, z)

	if slope >= STEEP_SLOPE_ROCK_DELTA:
		return _pick_surface_rock(x, z, height)

	if domain == DOMAIN_MOUNTAIN:
		var sheltered_shelf: bool = slope <= 1 and height < 96 and generator.domain_n_map[idx] < 0.68
		if sheltered_shelf and region > 0.94:
			return _grass_variant(x, z)
		if sheltered_shelf and region > 0.86:
			return _dirt_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if domain == DOMAIN_VALLEY:
		if slope >= 2 and _surface_region_value(x, z, 17) > 0.35:
			return _pick_surface_rock(x, z, height)
		if region < 0.50:
			return _grass_variant(x, z)
		if region < 0.82:
			return _dirt_variant(x, z)
		return _pick_surface_rock(x, z, height)

	if region < 0.62:
		return _grass_variant(x, z)
	if region < 0.86:
		return _dirt_variant(x, z)
	return _pick_surface_rock(x, z, height)

func _surface_slope(x: int, z: int) -> int:
	var heightmap: PackedInt32Array = generator.heightmap
	var center := heightmap[x * WORLD_SIZE_Z + z]
	var max_delta := 0
	if x > 0:
		max_delta = maxi(max_delta, absi(center - heightmap[(x - 1) * WORLD_SIZE_Z + z]))
	if x < WORLD_SIZE_X - 1:
		max_delta = maxi(max_delta, absi(center - heightmap[(x + 1) * WORLD_SIZE_Z + z]))
	if z > 0:
		max_delta = maxi(max_delta, absi(center - heightmap[x * WORLD_SIZE_Z + z - 1]))
	if z < WORLD_SIZE_Z - 1:
		max_delta = maxi(max_delta, absi(center - heightmap[x * WORLD_SIZE_Z + z + 1]))
	return max_delta


func _is_water_bank(x: int, z: int) -> bool:
	return water_bank_columns.has(Vector2i(x, z))


func _surface_region_value(x: int, z: int, salt: int) -> float:
	var macro := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, salt, z / MATERIAL_MACRO_CELL_SIZE)
	var macro_hash := float(abs(hash(macro)) % 1000) / 999.0
	var field := (noise_domain.get_noise_2d(float(x) * 0.12 + float(salt * 997), float(z) * 0.12 - float(salt * 541)) + 1.0) * 0.5
	return clampf((macro_hash * 0.62) + (field * 0.38), 0.0, 1.0)


## Decorative variants are deterministic and independent of height or edge distance.
## All eight keys share the grass appearance family; actual grass placement is
## still determined by the existing material/geography rules.
func _grass_variant(x: int, z: int) -> int:
	if grass_ids.is_empty(): return id_rock10
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, generator.world_seed, z / MATERIAL_MACRO_CELL_SIZE)
	return grass_ids[posmod(hash(cell), grass_ids.size())]

func _dirt_variant(x: int, z: int) -> int:
	var cell := Vector3i(x / MATERIAL_MACRO_CELL_SIZE, 47, z / MATERIAL_MACRO_CELL_SIZE)
	return dirt_ids[abs(hash(cell)) % dirt_ids.size()]


func _foothill_shelf_block_id(x: int, z: int, y: int) -> int:
	var shelf_y := (y - foothill_shelf_min_y) % foothill_shelf_height
	if shelf_y == foothill_shelf_height - 1:
		return _grass_variant(x, z)
	if shelf_y <= 1:
		return dirt_ids[0]
	if shelf_y <= 3:
		return dirt_ids[1]
	if shelf_y <= 5:
		return dirt_ids[2]
	return dirt_ids[3]


func _foothill_shelf_start_for_height(h: int) -> int:
	var shelf_index := int(floor(float(h - foothill_shelf_min_y) / float(foothill_shelf_height)))
	return foothill_shelf_min_y + (shelf_index * foothill_shelf_height)


func _foothill_body_rock_id(y: int) -> int:
	return _altitude_rock_body_id(y)


func _altitude_rock_body_id(y: int) -> int:
	if y >= foothill_shelf_min_y and y < foothill_shelf_min_y + foothill_shelf_height:
		return id_rock09
	if y >= LOWLAND_SHELF_MIN_Y and y <= lowland_shelf_max_y:
		return id_rock10
	if y >= foothill_shelf_min_y + foothill_shelf_height and y < foothill_shelf_min_y + (foothill_shelf_height * 2):
		return id_rock08
	if y >= foothill_shelf_min_y + (foothill_shelf_height * 2) and y <= foothill_shelf_max_y:
		return id_rock07
	return fallback_rock_id(y)


func _lowland_shelf_block_id(x: int, z: int, y: int) -> int:
	var shelf_y := y - LOWLAND_SHELF_MIN_Y
	if y == lowland_shelf_max_y:
		return _grass_variant(x, z)
	if shelf_y <= 1:
		return dirt_ids[0]
	if shelf_y <= 3:
		return dirt_ids[1]
	if shelf_y <= 5:
		return dirt_ids[2]
	return dirt_ids[3]


func _mountain_shelf_block_id(y: int) -> int:
	if mountain_rock_ids.is_empty():
		return id_rock11
	var shelf_index := int(floor(float(y - mountain_min) / float(mountain_shelf_height)))
	return mountain_rock_ids[clampi(shelf_index, 0, mountain_rock_ids.size() - 1)]


func _pick_surface_rock(x: int, z: int, y: int) -> int:
	var region := _surface_region_value(x, z, 23)
	if y >= 112:
		return mountain_rock_ids[mountain_rock_ids.size() - 1] if not mountain_rock_ids.is_empty() else id_rock07
	if region > 0.82:
		return id_rock08
	if region < 0.18:
		return id_rock09
	return id_rock07


func _apply_resource_veins(x: int, y: int, z: int, surf_y: int, rock_id: int) -> int:
	if y <= BEDROCK_MAX_Y:
		return rock_id
	if y >= surf_y:
		return rock_id
	if not is_resource_replaceable_rock(rock_id):
		return rock_id
	if is_resource_perimeter_column(x, z):
		return rock_id
	if is_natural_exposed_wall(x, y, z):
		return rock_id

	if _y_in_any_resource_window(gem_windows, y):
		var n_gem := (noise_gem.get_noise_3d(x, y, z) + 1.0) * 0.5
		var gem := _pick_buried_gem(x,y,z,n_gem)
		if gem != -1:
			return gem

	var ore := pick_metal_from_fields(x, y, z)
	if ore != -1:
		return ore

	var column_index := x * WORLD_SIZE_Z + z
	if cave_soil.has(column_index) and y == (cave_columns[column_index] as Vector3i).x:
		return id_cave_soil

	if _y_in_any_resource_window(soil_windows, y):
		var n_soil := (noise_soil.get_noise_3d(x, y, z) + 1.0) * 0.5
		var soil := pick_resource_from_windows(soil_windows, y, n_soil)
		if soil != -1:
			return soil

	return rock_id


func is_resource_replaceable_rock(block_id: int) -> bool:
	return resource_replaceable_rock_ids.has(block_id)


func is_resource_perimeter_column(x: int, z: int) -> bool:
	var edge_dist := mini(mini(x, WORLD_SIZE_X - 1 - x), mini(z, WORLD_SIZE_Z - 1 - z))
	return edge_dist < RESOURCE_PERIMETER_SUPPRESSION_WIDTH


func is_natural_exposed_wall(x: int, y: int, z: int) -> bool:
	var heightmap: PackedInt32Array = generator.heightmap
	if x > 0 and heightmap[(x - 1) * WORLD_SIZE_Z + z] < y:
		return true
	if x < WORLD_SIZE_X - 1 and heightmap[(x + 1) * WORLD_SIZE_Z + z] < y:
		return true
	if z > 0 and heightmap[x * WORLD_SIZE_Z + z - 1] < y:
		return true
	if z < WORLD_SIZE_Z - 1 and heightmap[x * WORLD_SIZE_Z + z + 1] < y:
		return true
	return false


func pick_metal_from_fields(x: int, y: int, z: int) -> int:
	# Priority resolves actual spatial overlaps, not intervals of one shared field.
	# Reject depth first so each block only samples fields that could replace it.
	for i in range(metal_windows.size()):
		var window: Dictionary = metal_windows[i]
		if y < window["min_y"] or y > window["max_y"]:
			continue
		if not has_natural_cover(x,y,z,int(window.get("min_burial",0))): continue
		var value := (metal_noise[i].get_noise_3d(x, y, z) + 1.0) * 0.5
		var threshold := float(window.threshold)
		if float(window.get("shallow_threshold",threshold))>threshold and not has_natural_cover(x,y,z,10): threshold = float(window.shallow_threshold)
		if value > threshold:
			return window["id"]
	return -1


func build_resource_cover_maps() -> void:
	resource_cover_maps.clear()
	for window: Dictionary in resource_focus_windows:
		var depth := int(window.get("min_burial",0))
		if depth<=0 or resource_cover_maps.has(depth): continue
		resource_cover_maps[depth] = preload("res://scripts/components/NaturalRockCover.gd").minimum_heights(generator.heightmap,WORLD_SIZE_X,depth)

## Burial is measured against the original exterior in every direction,
## including cliff faces. Mining edits cannot unlock rarer geology beside them.
func has_natural_cover(x: int, y: int, z: int, depth: int) -> bool:
	if depth<=0: return true
	if x-depth<0 or z-depth<0 or x+depth>=WORLD_SIZE_X or z+depth>=WORLD_SIZE_Z: return false
	var heightmap: PackedInt32Array = generator.heightmap
	if heightmap.is_empty() or heightmap[x*WORLD_SIZE_Z+z]<y+depth: return false
	if resource_cover_maps.has(depth):
		return int(resource_cover_maps[depth][x*WORLD_SIZE_Z+z])>=y+depth
	# Small synthetic fixtures may omit map precomputation. This exact fallback
	# is read-only too; real worlds publish every configured radius before use.
	for cx in range(x-depth,x+depth+1):
		for cz in range(z-depth,z+depth+1):
			if heightmap[cx*WORLD_SIZE_Z+cz]<y+depth: return false
	return true

func _pick_buried_gem(x: int, y: int, z: int, value: float) -> int:
	for window: Dictionary in gem_windows:
		if y<int(window.min_y) or y>int(window.max_y) or value<=float(window.threshold): continue
		if has_natural_cover(x,y,z,int(window.min_burial)): return int(window.id)
	return -1


func pick_resource_from_windows(windows: Array[Dictionary], y: int, noise_value: float) -> int:
	for window: Dictionary in windows:
		if y >= int(window.get("min_y", 0)) and y <= int(window.get("max_y", WORLD_SIZE_Y - 1)) and noise_value > float(window.get("threshold", 1.0)):
			return int(window.get("id", -1))
	return -1


func _y_in_any_resource_window(windows: Array[Dictionary], y: int) -> bool:
	for window: Dictionary in windows:
		if y >= int(window.get("min_y", 0)) and y <= int(window.get("max_y", WORLD_SIZE_Y - 1)):
			return true
	return false


func fallback_rock_id(y: int) -> int:
	# Off-ladder heights stay on the authored rock01..rock11 ladder.
	if y <= FOUNDATION_ROCK_MAX_Y:
		return id_rock11
	if y < foothill_shelf_min_y:
		return id_rock10
	if y < foothill_shelf_min_y + foothill_shelf_height:
		return id_rock09
	if y < foothill_shelf_min_y + (foothill_shelf_height * 2):
		return id_rock08
	if y <= foothill_shelf_max_y:
		return id_rock07
	if not mountain_rock_ids.is_empty():
		var shelf_index := int(floor(float(y - mountain_min) / float(mountain_shelf_height)))
		return mountain_rock_ids[clampi(shelf_index, 0, mountain_rock_ids.size() - 1)]
	return id_rock07
