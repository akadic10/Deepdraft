extends RefCounted

## The climate (doc 34): how warm any spot is, from its height, the rock above it, the open
## air it can reach, the season, the time of day and the weather. RoomManager owns it and its
## data (`temperature.json`), and adds a sealed room's heat on top.
## - Height sets the year's mean: `mean_at_reference_c` at `reference_y`, a degree colder for
##   every `blocks_per_degree` blocks up and warmer below.
## - The outside swing is the season plus the time of day and the weather. Open sky (no solid
##   block above, built roofs included) feels all of it.
## - Rock damps the season only: under `cover` solid blocks a spot feels
##   exp(-cover / season_damping_blocks) of it. Day and night travel only through open air.
## - Under a roof, outside air reaches `outside_air_reach_blocks` steps of walking distance,
##   fading on the way, and doors stop it. A sealed room feels only its rock.
## Derived and never saved. Column profiles and reach searches are cached; block, door and
## cave-discovery changes clear what they touch. Caves the colony has not found count as rock
## (Hard Rule 11), so temperature never gives them away.

const NEIGHBORS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
## A reach search gives up after this many cells, and the spot then counts as out of reach.
const MAX_SEARCH_CELLS := 4096
## About 13 MB of column profiles: the view round the camera needs some 20,000.
const MAX_CACHED_COLUMNS := 65536

var owner: Node
var _columns: Dictionary = {}   # Vector2i column -> PackedByteArray: solid blocks above each height
var _solid := PackedByteArray()   # block id -> 1 when solid
var _reach: Dictionary = {}     # Vector2i 16 x 16-column tile -> {air cell: steps to open sky, -1 for none}


func _init(manager: Node) -> void:
	owner = manager


func clear() -> void:
	_columns.clear()
	_reach.clear()


# ── The rule ──────────────────────────────────────────────────────────────────

## The year's mean temperature at a height.
func mean_c(height: float) -> float:
	var config: Dictionary = owner.temperature_config
	return float(config.mean_at_reference_c) - (height - float(config.reference_y)) / float(config.blocks_per_degree)


## The season's offset from the mean, as open air feels it now.
func season_c() -> float:
	return float(owner.temperature_config.seasonal_swing_c) * WorldClock.solstice_cosine(WorldClock.day_of_year())


## The time of day's and the weather's offset, as open air feels them now.
func day_and_weather_c() -> float:
	var weather := weather_effect()
	var day := sin((float(WorldClock.hour) - 8.0) / 24.0 * TAU)
	return float(owner.temperature_config.daily_swing_c) * float(weather.get("daily_swing_scale", 1.0)) * day \
		+ float(weather.get("offset_c", 0.0))


## The current weather's `temperature` block from its JSON: offset_c, daily_swing_scale, wet.
func weather_effect() -> Dictionary:
	return WeatherManager.current_definition().get("temperature", {})


func is_wet() -> bool:
	return bool(weather_effect().get("wet", false))


## A spot's temperature now, from its height and the shares of the swing it feels.
func temperature(height: float, season_share: float, air_share: float) -> float:
	return mean_c(height) + season_c() * season_share + day_and_weather_c() * air_share


## The lowest and highest the same spot reaches over a year in clear weather.
func year_range(height: float, season_share: float, air_share: float) -> Vector2:
	return form_range(Vector3(mean_c(height), season_share, air_share))


## A temperature as a linear form, Vector3(base, season share, day-and-weather share), now:
## how sealed rooms carry their doors' leaks (HeatSpread).
func form_temperature(form: Vector3) -> float:
	return form.x + form.y * season_c() + form.z * day_and_weather_c()


## A form's lowest and highest over a year in clear weather.
func form_range(form: Vector3) -> Vector2:
	var config: Dictionary = owner.temperature_config
	var swing := float(config.seasonal_swing_c) * form.y + float(config.daily_swing_c) * form.z
	return Vector2(form.x - swing, form.x + swing)


## The share of the season felt under `cover` solid blocks.
func rock_share(cover: int) -> float:
	return exp(-float(maxi(cover, 0)) / float(owner.temperature_config.season_damping_blocks))


# ── The place ────────────────────────────────────────────────────────────────

## Solid blocks above a cell in its column: rock, built blocks and caves not yet found.
func cover_above(cell: Vector3i) -> int:
	if cell.y < 0 or cell.y > WorldData.MAX_Y: return 0
	return _column(Vector2i(cell.x, cell.z))[cell.y]


func is_open_sky(cell: Vector3i) -> bool:
	return is_air(cell) and cover_above(cell) == 0


## Whether a cell is air as the climate reads it: caves the colony has not found are rock,
## as the slice shows them; outside the world is not air, above it is.
func is_air(cell: Vector3i) -> bool:
	if cell.x < 0 or cell.z < 0 or cell.x >= WorldData.WORLD_SIZE_X or cell.z >= WorldData.WORLD_SIZE_Z: return false
	if cell.y <= 0 or cell.y > WorldData.MAX_Y: return cell.y > WorldData.MAX_Y
	var above := _column(Vector2i(cell.x, cell.z))
	return above[cell.y - 1] == above[cell.y]


## The highest solid block at or under `top` in a column, read from its cached profile in a
## few steps: rock, built blocks and caves not yet found. Bedrock (0) when nothing else is.
func highest_solid(x: int, z: int, top: int) -> int:
	var ceiling := clampi(top, 0, WorldData.MAX_Y)
	var above := _column(Vector2i(x, z))
	var over := int(above[ceiling])   # the solid blocks over the ceiling
	if ceiling < 1 or int(above[0]) <= over: return 0
	# above[y - 1] counts the solid blocks at y and over: the highest y with more than `over`.
	var low := 1
	var high := ceiling
	while low < high:
		var middle := (low + high + 1) >> 1
		if int(above[middle - 1]) > over: low = middle
		else: high = middle - 1
	return low


## Walking steps through air from a cell to the nearest open sky: 0 under open sky, -1 when
## none lies within reach. Doors stop the search.
func outside_air_steps(cell: Vector3i) -> int:
	if is_open_sky(cell): return 0
	var tile := Vector2i(cell.x >> 4, cell.z >> 4)
	var known: Dictionary = _reach.get(tile, {})
	if known.has(cell): return int(known[cell])
	var steps := _search_open_sky(cell)
	known[cell] = steps
	_reach[tile] = known
	return steps


## How much of the outside swing an unsealed cell feels, and why: {kind, steps, cover,
## season_share, air_share}. kind is "open_sky", "sheltered" or "rock" (solid, or a cave not
## yet found); rock gives what a sealed room dug there would feel.
func exposure(cell: Vector3i) -> Dictionary:
	var cover := cover_above(cell)
	if not is_air(cell):
		return {"kind": "rock", "steps": -1, "cover": cover, "season_share": rock_share(cover), "air_share": 0.0}
	if cover == 0:
		return {"kind": "open_sky", "steps": 0, "cover": 0, "season_share": 1.0, "air_share": 1.0}
	var steps := outside_air_steps(cell)
	var reach := float(owner.temperature_config.outside_air_reach_blocks)
	var air := 0.0 if steps < 0 else maxf(0.0, 1.0 - float(steps) / reach)
	return {"kind": "sheltered", "steps": steps, "cover": cover, "season_share": maxf(air, rock_share(cover)), "air_share": air}


# ── Changes ───────────────────────────────────────────────────────────────────

func on_block_changed(cell: Vector3i, _old_id: int, _new_id: int) -> void:
	_columns.erase(Vector2i(cell.x, cell.z))
	_forget_reach_near(cell)


func on_doors_changed(cells: Array[Vector3i]) -> void:
	for cell: Vector3i in cells: _forget_reach_near(cell)


## A found cave's air stops counting as rock.
func on_caves_discovered(cells: Array[Vector3i]) -> void:
	var tiles := {}
	for cell: Vector3i in cells:
		_columns.erase(Vector2i(cell.x, cell.z))
		tiles[Vector2i(cell.x >> 4, cell.z >> 4)] = true
	for tile: Vector2i in tiles:
		for dx in range(-1, 2):
			for dz in range(-1, 2): _reach.erase(tile + Vector2i(dx, dz))


# ── Internals ─────────────────────────────────────────────────────────────────

## above[y] counts the solid blocks over height y, read a chunk at a time. Unloaded chunks are
## the generator's: solid up to its surface, its cave span air (its ore noise never changes
## whether a block is solid). A cave the colony has not found is rock either way.
func _column(column: Vector2i) -> PackedByteArray:
	if _columns.has(column): return _columns[column]
	var above := PackedByteArray()
	above.resize(WorldData.WORLD_SIZE_Y)
	# Before the maps exist every column reads as air; keep nothing from that moment.
	if not WorldGenerator.is_maps_ready(): return above
	if _solid.is_empty():
		_solid.resize(256)
		for id in range(256): _solid[id] = 1 if BlockRegistry.is_solid(id) else 0
	var surface := WorldGenerator.get_surface_y(column.x, column.y)   # -1 outside the world
	var cave := WorldGenerator.get_cave_column(column.x * WorldData.WORLD_SIZE_Z + column.y) if surface >= 0 else Vector3i(-1, -1, -1)
	var hidden := cave.z >= 0 and not InteriorTracker.is_cave_discovered(cave.z)
	var base := Chunk.local_index(column.x & 15, 0, column.y & 15)
	var layer := Chunk.local_index(0, 1, 0)
	var count := 0
	for section in range((WorldData.WORLD_SIZE_Y >> 4) - 1, -1, -1):
		var chunk: Chunk = WorldData.get_chunk_if_exists(column.x >> 4, section, column.y >> 4)
		for y in range(section * 16 + 15, section * 16 - 1, -1):
			above[y] = count
			var in_cave := y > cave.x and y <= cave.y
			if in_cave and hidden: count += 1
			elif chunk != null: count += _solid[chunk.blocks[base + (y & 15) * layer]]
			elif not in_cave and y <= surface: count += 1
	# The Temperature view reads many columns; past the cap the cache starts again.
	if _columns.size() >= MAX_CACHED_COLUMNS: _columns.clear()
	_columns[column] = above
	return above


func _search_open_sky(start: Vector3i) -> int:
	var reach := int(owner.temperature_config.outside_air_reach_blocks)
	var doors: Dictionary = owner.get_door_boundaries()
	var seen := {start: true}
	var frontier: Array[Vector3i] = [start]
	for step in range(1, reach + 1):
		var next: Array[Vector3i] = []
		for cell: Vector3i in frontier:
			for offset: Vector3i in NEIGHBORS:
				var neighbour := cell + offset
				if seen.has(neighbour): continue
				seen[neighbour] = true
				if doors.has(neighbour) or not is_air(neighbour): continue
				if cover_above(neighbour) == 0: return step
				next.append(neighbour)
		if next.is_empty() or seen.size() > MAX_SEARCH_CELLS: return -1
		frontier = next
	return -1


## A change can alter the reach of any cell within reach of it, in these tiles.
func _forget_reach_near(cell: Vector3i) -> void:
	var reach := int(owner.temperature_config.outside_air_reach_blocks)
	for tile_x in range((cell.x - reach) >> 4, ((cell.x + reach) >> 4) + 1):
		for tile_z in range((cell.z - reach) >> 4, ((cell.z + reach) >> 4) + 1):
			_reach.erase(Vector2i(tile_x, tile_z))
