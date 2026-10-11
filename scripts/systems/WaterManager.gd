extends Node

## Each functional stone has one identity, whether placed or packed. Additional
## scenario stones use the same records and physical item path as the first pair.
var stones: Dictionary = {}
var next_stone_id := 1

## Owns live water, independently of streaming or mesh visibility. Terrain
## generation supplies the initial volume once; only the spring replenishes it.
const Flow := preload("res://scripts/components/WaterFlow.gd")
const Moisture := preload("res://scripts/components/SoilMoisture.gd")
var flow: RefCounted
var moisture: RefCounted
var show_moisture := false
var _moisture_heads: Dictionary = {}
var _soil_kinds: Dictionary = {}
var initialized := false
var restoring := false
var standing_depth := 0.0625
var source_enabled := true
var outlet_enabled := true
var elapsed_usec := 0
var accumulator_usec := 0
var elapsed: float:
	get: return float(elapsed_usec)/1000000.0
var revision := 0
var last_step_usec := 0
var edited_columns: Dictionary = {}
var dirty_tiles: Dictionary = {}
var _nav_tops: Dictionary = {}
var _seed := 0
var _water_id := 0
var _config: Dictionary = {}
var test_dam: Array = []
var _last_flood_warning := -600.0
signal levels_changed(cells: Array)
signal flood_warning

func _ready() -> void:
	add_to_group("save_state_owner")
	WorldData.block_changed.connect(_on_block_changed)

func reset() -> void:
	stones.clear()
	next_stone_id = 1
	initialized = false
	flow = null
	moisture = null
	_moisture_heads.clear()
	_soil_kinds.clear()
	show_moisture = false
	edited_columns.clear()
	dirty_tiles.clear()
	_nav_tops.clear()
	accumulator_usec = 0
	elapsed_usec = 0
	source_enabled = true
	outlet_enabled = true
	test_dam.clear()
	_last_flood_warning = -600.0
	revision += 1

func initialize() -> void:
	if initialized or not WorldGenerator._maps_ready or WorldGenerator.river_layout.is_empty(): return
	_config = WorldGenerator.water_profile
	standing_depth = float(_config.simulation.standing_depth)
	_water_id = BlockRegistry.get_id("base:terrain:water:source")
	flow = Flow.new()
	flow.spans_at = _spaces
	flow.conductance = float(_config.simulation.conductance)
	flow.epsilon = float(_config.simulation.epsilon)
	flow.level_reach = int(_config.simulation.level_reach)
	for x in 1024:
		for z in 1024:
			var i := x*1024+z
			var water := WorldGenerator.waterline_map[i]
			if water < 0: continue
			var bottom := WorldGenerator.heightmap[i]+1
			var river: bool = WorldGenerator.river_layout.columns.has(Vector2i(x,z))
			var volume := float(WorldGenerator.river_layout.initial_units[Vector2i(x,z)])/Flow.UNITS if river else float(water-bottom+1)
			flow.seed_column(Vector3i(x,bottom,z),volume,river)
			_nav_tops[Vector3i(x,bottom,z)] = _occupied_top(Vector3i(x,bottom,z))
			dirty_tiles[Vector2i(x/32,z/32)] = true
	for key: Vector3i in WorldGenerator.spring_cave.get("water",{}):
		flow.seed_column(key,float(WorldGenerator.spring_cave.water[key])/Flow.UNITS)
		_nav_tops[key] = _occupied_top(key)
		dirty_tiles[Vector2i(key.x/32,key.z/32)] = true
	_seed = WorldGenerator.world_seed
	initialized = true
	var layout := WorldGenerator.river_layout
	stones = {
		"wet": {"kind":"wet", "cell":WorldGenerator.spring_cave.stone, "intake":layout.spring, "level":layout.spring_level, "placed":true, "disallowed":true, "packing":false, "work":0.0},
		"dry": {"kind":"dry", "cell":layout.dry_stone, "intake":layout.outlet, "level":layout.outlet_level, "placed":true, "disallowed":true, "packing":false, "work":0.0}}
	InteriorTracker.reveal_surface_caves()
	_rebuild_moisture()
	revision += 1

func _rebuild_moisture() -> void:
	moisture = Moisture.new()
	moisture.wet_usec = roundi(float(_config.irrigation.wet_hours)*WorldClock._real_seconds_per_game_hour*1000000.0)
	moisture.dry_usec = roundi(float(_config.irrigation.dry_hours)*WorldClock._real_seconds_per_game_hour*1000000.0)
	_moisture_heads.clear()
	for key: Vector3i in flow.mass:
		_update_moisture_contact(key)

func _update_moisture_contact(key: Vector3i) -> void:
	var head := floori(flow.level(key)*4.0) if flow.volume(key)>=0.125 else key.y*4
	if int(_moisture_heads.get(key,-1))==head: return
	_moisture_heads[key] = head
	var reached: Dictionary = {}
	if head>key.y*4:
		var radius := int(_config.irrigation.radius)
		for dx in range(-radius,radius+1):
			for dz in range(-radius,radius+1):
				var distance := absi(dx)+absi(dz)
				if distance==0 or distance>radius: continue
				var col := Vector2i(key.x+dx,key.z+dz)
				for span: Vector2i in flow.spans(col):
					var soil := Vector3i(col.x,span.x-1,col.y)
					# Root-zone seepage only at the water's elevation, never through
					# a whole rock shelf or into a field above the supplying head.
					if soil.y<float(head)/4.0-1.0 or soil.y>float(head)/4.0+0.5 or soil.y<key.y-1: continue
					if not _soil_kinds.has(soil):
						var kind: String = BlockRegistry.get_def(BlockRegistry.get_key(WorldData.get_terrain_block(soil.x,soil.y,soil.z))).get("kind","")
						_soil_kinds[soil] = kind in ["dirt","grass"]
					if _soil_kinds[soil]: reached[soil] = roundi(float(radius+1-distance)*Moisture.SCALE/radius)
	moisture.set_source(key,reached,elapsed_usec)

func soil_moisture_at(cell: Vector3i) -> float:
	return float(moisture.value_units(cell,elapsed_usec))/Moisture.SCALE if initialized else 0.0

func _process(delta: float) -> void:
	if not WorldGenerator._maps_ready:
		if initialized: reset()
		return
	if initialized and _seed != WorldGenerator.world_seed: reset()
	initialize()
	if not initialized or WorldClock.paused or SaveManager.is_loading() or WorldClock.speed <= 0: return
	advance(delta * WorldClock.speed)

func advance(seconds: float) -> void:
	if not initialized: return
	accumulator_usec += roundi(seconds*1000000.0)
	var tick := float(_config.simulation.tick_seconds)
	var tick_usec := roundi(tick*1000000.0)
	# Retain debt rather than losing simulation time during a slow frame.
	for _i in 4:
		if accumulator_usec < tick_usec: break
		accumulator_usec -= tick_usec
		step(tick)

func step(seconds: float) -> void:
	var started := Time.get_ticks_usec()
	var ids := stones.keys()
	ids.sort_custom(func(a: String,b: String): return stones[a].kind=="wet" if stones[a].kind!=stones[b].kind else a<b)
	for id: String in ids:
		var stone: Dictionary = stones[id]
		if not stone.placed: continue
		if stone.kind == "wet" and source_enabled: flow.add_at(stone.intake, seconds * float(_config.simulation.spring_rate), stone.level)
		if stone.kind == "dry" and outlet_enabled: flow.remove_at(stone.intake, seconds * float(_config.simulation.outlet_rate), stone.level, true)
	flow.step(seconds, int(_config.simulation.max_cells_per_tick))
	elapsed_usec += roundi(seconds*1000000.0)
	_flush_changes()
	last_step_usec = Time.get_ticks_usec()-started

func _flush_changes() -> void:
	if flow.changed.is_empty(): return
	var cells: Array = flow.changed.keys()
	var occupancy: Array = []
	for cell: Vector3i in cells:
		_update_moisture_contact(cell)
		var top := _occupied_top(cell)
		if top != int(_nav_tops.get(cell,cell.y)):
			_nav_tops[cell] = top
			occupancy.append(cell)
			if top>WorldGenerator.get_surface_y(cell.x,cell.z)+1 and WorldGenerator.get_waterline(cell.x,cell.z)<0 and elapsed-_last_flood_warning>60.0:
				_last_flood_warning = elapsed
				flood_warning.emit()
		for offset: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var col := Vector2i(cell.x,cell.z)+offset
			dirty_tiles[Vector2i(col.x/32,col.y/32)] = true
	flow.changed.clear()
	if not occupancy.is_empty(): levels_changed.emit(occupancy)

func _spaces(col: Vector2i) -> Array:
	if col.x < 0 or col.y < 0 or col.x >= 1024 or col.y >= 1024: return []
	var result: Array = []
	if edited_columns.has(col):
		var start := -1
		for y in range(4,128):
			var solid := BlockRegistry.is_solid(WorldData.get_terrain_block(col.x,y,col.y))
			if not solid and start < 0: start = y
			if solid and start >= 0:
				result.append(Vector2i(start,y))
				start = -1
		if start >= 0: result.append(Vector2i(start,128))
	else:
		var index := col.x*1024+col.y
		var cave: Vector3i = WorldGenerator._cave_layout.columns.get(index,Vector3i(-1,-1,-1))
		var surface := WorldGenerator.heightmap[index]+1
		if cave.x>=0 and cave.y+1>=surface:
			result.append(Vector2i(mini(cave.x+1,surface),128))
		else:
			if cave.x >= 0: result.append(Vector2i(cave.x+1,cave.y+1))
			result.append(Vector2i(surface,128))
	return result

func _on_block_changed(cell: Vector3i, _old: int, _new: int) -> void:
	if not initialized: return
	var col := Vector2i(cell.x,cell.z)
	# Cache the OLD topology before enabling scans of the edited terrain.
	flow.spans(col)
	edited_columns[col] = true
	flow.terrain_changed(col)
	_soil_kinds.clear()
	# A new exposed soil floor can be irrigated by an unchanged nearby pool.
	var radius := int(_config.irrigation.radius)
	for dx in range(-radius,radius+1):
		for dz in range(-radius,radius+1):
			for span: Vector2i in flow.spans(col+Vector2i(dx,dz)):
				var key := Vector3i(col.x+dx,span.x,col.y+dz)
				_moisture_heads.erase(key)
				_update_moisture_contact(key)
	_flush_changes()

func depth_at(cell: Vector3i) -> float:
	return flow.depth_at(cell) if initialized else 0.0

func has_standing_water(cell: Vector3i) -> bool:
	return depth_at(cell) >= standing_depth

func _occupied_top(key: Vector3i) -> int:
	return maxi(key.y,floori(flow.level(key)-standing_depth)+1)

func live_block(cell: Vector3i, terrain_id: int) -> int:
	if not initialized or (terrain_id != BlockRegistry.AIR_ID and terrain_id != _water_id): return terrain_id
	return _water_id if has_standing_water(cell) else BlockRegistry.AIR_ID

## Measured withdrawal boundary for future hauling/brewing. Never grants water
## remotely or invents containers; the caller must first reach a collection site.
func extract(cell: Vector3i, requested: float) -> float:
	if not initialized or requested <= 0 or depth_at(cell) <= 0: return 0.0
	var amount: float = flow.remove_at(cell,requested,cell.y)
	_flush_changes()
	return amount

func save_section_key() -> String: return "water"
func save_restore_priority() -> int: return 11

func serialize_state() -> Dictionary:
	initialize()
	var saved_stones := {}
	for id: String in stones:
		saved_stones[id] = stones[id].duplicate(true)
		saved_stones[id].cell = SaveManager.pack_v3i(stones[id].cell)
		saved_stones[id].intake = SaveManager.pack_v3i(stones[id].intake)
	return {"layout_version":preload("res://scripts/components/RiverLayout.gd").VERSION,"flow":flow.serialize(),"source_enabled":source_enabled,"outlet_enabled":outlet_enabled,
		"stones":saved_stones,"next_stone_id":next_stone_id,
		"elapsed_usec":elapsed_usec,"accumulator_usec":accumulator_usec,"terrain":WorldData.serialize_solid_edits(),"test_dam":test_dam.duplicate(true),"moisture":moisture.serialize()}

func restore_state(state: Dictionary) -> void:
	initialize()
	restoring = true
	stones = state.stones.duplicate(true)
	next_stone_id = int(state.next_stone_id)
	for stone: Dictionary in stones.values():
		stone.cell = SaveManager.unpack_v3i(stone.cell)
		stone.intake = SaveManager.unpack_v3i(stone.intake)
	var previous_wet: Dictionary = flow.mass.duplicate()
	for entry: Dictionary in state.terrain:
		var p: Array = entry.cell
		WorldData.set_block(int(p[0]),int(p[1]),int(p[2]),BlockRegistry.get_id(entry.block))
	flow.restore(state.flow)
	source_enabled = state.source_enabled
	outlet_enabled = state.outlet_enabled
	elapsed_usec = int(state.elapsed_usec)
	accumulator_usec = int(state.accumulator_usec)
	test_dam = state.test_dam.duplicate(true)
	_rebuild_moisture()
	moisture.restore(state.moisture)
	_nav_tops.clear()
	for key: Vector3i in flow.mass:
		dirty_tiles[Vector2i(key.x/32,key.z/32)] = true
		_nav_tops[key] = _occupied_top(key)
		previous_wet[key] = true
	levels_changed.emit(previous_wet.keys())
	revision += 1
	restoring = false


func place_stone(id: String, cell: Vector3i) -> void:
	assert(stones.has(id) and not stones[id].placed)
	var stone: Dictionary = stones[id]
	stone.cell = cell
	stone.intake = cell
	# A relocated drain retains the receiving water surface; a dry basin fills
	# to the stone's top. Natural stones retain their authored levels until moved.
	stone.level = maxf(float(cell.y+1), flow.level(flow.space_at(cell))) if stone.kind=="dry" else float(cell.y+1)
	stone.placed = true
	stone.packing = false
	stone.disallowed = false


## Future reward/scenario boundary: grants one real, inactive, non-stacking item.
## No scenario schedule or extra starting stones are introduced here.
func grant_stone(kind: String, cell: Vector3i, disallowed: bool = true) -> String:
	if not initialized or not _config.stones.has(kind): return ""
	if cell.x<0 or cell.x>=1024 or cell.y<4 or cell.y>=128 or cell.z<0 or cell.z>=1024: return ""
	var items := get_tree().get_first_node_in_group("item_drop_manager")
	if items == null: return ""
	var id := "water_stone:%d" % next_stone_id
	next_stone_id += 1
	stones[id] = {"kind":kind,"cell":cell,"intake":cell,"level":float(cell.y+1),"placed":false,"disallowed":disallowed,"packing":false,"work":0.0}
	items.restore_loose_item(String(_config.stones[kind].item_key),Vector3(cell)+Vector3(.5,0,.5),0,1,id,disallowed)
	return id

## Explicit developer experiment, using the same terrain edits as construction.
## Never mines natural banks or destroys placed colony entities.
func dev_toggle_dam() -> Vector3i:
	if not initialized: return Vector3i.ZERO
	if not test_dam.is_empty():
		var focus := SaveManager.unpack_v3i(test_dam[0].cell)
		for entry: Dictionary in test_dam:
			var cell := SaveManager.unpack_v3i(entry.cell)
			WorldData.set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id(entry.block))
		test_dam.clear()
		return focus
	var route: Array = WorldGenerator.river_layout.route
	for i in range(15,route.size()-15):
		var col: Vector2i = route[i]
		var ground := WorldGenerator.get_surface_y(col.x,col.y)
		if ground > WorldGenerator.river_layout.spring.y-10 or ground<25: continue
		var ahead: Vector2i = route[i+10]
		var behind: Vector2i = route[i-10]
		if WorldGenerator.get_surface_y(ahead.x,ahead.y)!=ground or WorldGenerator.get_surface_y(behind.x,behind.y)!=ground: continue
		# Follow the reach, not one sideways stair-step in a winding centerline.
		var travel := ahead-behind
		var dir := Vector2i(signi(travel.x),0) if absi(travel.x)>absi(travel.y) else Vector2i(0,signi(travel.y))
		var side := Vector2i(-dir.y,dir.x)
		var cells: Array[Vector3i] = []
		var blocked := false
		for j in range(-6,7):
			var p := col+side*j
			for y in range(ground+1,ground+6):
				var cell := Vector3i(p.x,y,p.y)
				if PlacedEntityRegistry.occupies(cell): blocked = true
				if not BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,cell.y,cell.z)): cells.append(cell)
		if blocked: continue
		for cell: Vector3i in cells:
			test_dam.append({"cell":[cell.x,cell.y,cell.z],"block":String(BlockRegistry.get_key(WorldData.get_terrain_block(cell.x,cell.y,cell.z)))})
			WorldData.set_block(cell.x,cell.y,cell.z,BlockRegistry.get_id("base:terrain:rock:rock07"))
		return Vector3i(col.x,ground+1,col.y)
	return Vector3i.ZERO
