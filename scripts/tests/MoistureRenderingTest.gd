extends SceneTree

class Terrain:
	extends Node3D
	signal visible_volume_changed
	var slice_y := 127
	var revealed := true
	var underground_lighting: Node
	func is_revealed_air(_cell: Vector3i) -> bool: return revealed

var failures: Array[String] = []
var checks := 0
var view: MeshInstance3D
var terrain: Terrain
var water: Node
var blocks: Node
var clock: Node
var cell := Vector3i(70,10,70)

func _init() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	clock = root.get_node("WorldClock")
	clock.set_paused(true)
	blocks = root.get_node("BlockRegistry")
	water = root.get_node("WaterManager")
	water.set_process(false)
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(p: Vector2i) -> Array:
		return [Vector2i(11,128)] if p == Vector2i(cell.x,cell.z) else []
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water.initialized = true
	var gen := root.get_node("WorldGenerator")
	gen.heightmap.resize(1024*1024)
	gen.heightmap.fill(cell.y)
	gen._maps_ready = true
	var world := root.get_node("WorldData")
	world.get_chunk(4,0,4) # Keep this bounded fixture independent of generation.
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	var dirt: int = blocks.get_id("base:terrain:surface:dirt_01")
	var chunk: Chunk = world.get_chunk(4,0,4)
	terrain = Terrain.new()
	root.add_child(terrain)
	terrain.underground_lighting = load("res://scripts/components/UndergroundLighting.gd").new()
	terrain.add_child(terrain.underground_lighting)
	terrain.underground_lighting.set_process(false)
	view = load("res://scripts/components/MoistureRenderer.gd").new()
	view.terrain = terrain
	terrain.add_child(view)
	view.set_process(false)
	_check(view.material_override.get_shader_parameter("terrain_surface"),"Damp soil shares terrain appearance shading")
	for season in ["spring","summer","autumn","winter"]:
		clock.season = season
		for id in [grass,dirt]:
			chunk.blocks[Chunk.local_index(6,10,6)] = id
			var dry: Color = blocks.get_terrain_color(id,season)
			var previous := dry
			for amount in [0.006,0.1,0.5,1.0]:
				_set_moisture(amount)
				var data: Array = view.mesh.surface_get_arrays(0)
				_check(data[Mesh.ARRAY_VERTEX].size() == 4,"Damp soil renders one exposed top")
				var expected := dry.darkened(amount*0.25)
				for color: Color in data[Mesh.ARRAY_COLOR]:
					_check(_matches(color,expected),"Overlay matches the terrain's linear palette and profile")
					_check(color.r <= previous.r+1.0/255 and color.g <= previous.g+1.0/255 and color.b <= previous.b+1.0/255,"Increasing moisture never brightens ground")
				previous = data[Mesh.ARRAY_COLOR][0]
			_set_moisture(0.004)
			_check(view.mesh == null,"Dry-enough ground has no overlay")
			_set_moisture(0.006)
			var near_dry: Color = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
			# Allow one quantization step plus the intended tiny dampening.
			_check(absf(near_dry.r-dry.r)<2.0/255 and absf(near_dry.g-dry.g)<2.0/255 and absf(near_dry.b-dry.b)<2.0/255,"Crossing the visibility threshold cannot create a pale ring")
	# A paused season switch must refresh even though water time has not advanced.
	chunk.blocks[Chunk.local_index(6,10,6)] = grass
	clock.season = "summer"
	_set_moisture(0.5)
	var summer_mesh: Mesh = view.mesh
	clock.season = "winter"
	view._process(0)
	_check(view.mesh != summer_mesh,"Paused seasonal change refreshes wet grass")
	_check(_matches(view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0],blocks.get_terrain_color(grass,"winter").darkened(0.125)),"Wet winter grass uses winter colour")
	var saved: Array = water.moisture.serialize()
	var unchanged: Mesh = view.mesh
	view._process(0)
	_check(view.mesh == unchanged,"Unchanged water/time/season keeps the same mesh")
	_check(water.moisture.serialize() == saved,"Drawing never changes moisture history")
	water.show_moisture = true
	view._process(0)
	var debug_color: Color = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
	_check(_matches(debug_color,Color("#AB8661").lerp(Color("#378FCE"),0.5).srgb_to_linear()),"Explicit moisture coverage uses linear debug colours")
	_check(debug_color.a == 1.0,"Debug coverage opts out of terrain variation")
	water.show_moisture = false
	terrain.slice_y = cell.y-1
	terrain.visible_volume_changed.emit()
	view._process(0)
	_check(view.mesh == null,"Moisture cannot appear above the slice")
	terrain.slice_y = 127
	terrain.revealed = false
	gen.heightmap[cell.x*1024+cell.z] = cell.y+1
	terrain.visible_volume_changed.emit()
	view._process(0)
	_check(view.mesh == null,"Hidden cave soil remains hidden")
	gen.heightmap[cell.x*1024+cell.z] = cell.y
	water.flow.seed_column(cell+Vector3i.UP,0.5)
	terrain.visible_volume_changed.emit()
	view._process(0)
	_check(view.mesh == null,"Standing water hides the soil overlay")
	terrain.free()
	gen._maps_ready = false
	water.reset()
	for failure in failures: push_error(failure)
	print("MoistureRenderingTest: ","PASS" if failures.is_empty() else "FAIL"," (",checks," checks)")
	quit(0 if failures.is_empty() else 1)

func _set_moisture(amount: float) -> void:
	var units := roundi(amount*1000000)
	water.moisture.soils[cell] = {"value":units,"target":units,"since":water.elapsed_usec}
	water.revision += 1
	view._process(0)

func _matches(actual: Color, expected: Color) -> bool:
	return absf(actual.r-expected.r) <= 1.0/255 and absf(actual.g-expected.g) <= 1.0/255 and absf(actual.b-expected.b) <= 1.0/255 and absf(actual.a-expected.a) <= 1.0/255

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures: failures.append(message)
