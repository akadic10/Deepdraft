extends SceneTree

var failures: Array[String] = []
var checks := 0
var blocks: Node
var generator: Node
var renderer: Node

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	blocks = root.get_node("BlockRegistry")
	generator = root.get_node("WorldGenerator")
	_palette_contract()
	_full_grass_faces()
	_cuts_and_merging()
	_async_revisions()
	_generation_and_concealment()
	_added_terrain_faces()
	renderer.free()
	for failure in failures: push_error(failure)
	print("TerrainAppearanceTest: ","PASS" if failures.is_empty() else "FAIL"," (",checks," checks)")
	quit(0 if failures.is_empty() else 1)

func _palette_contract() -> void:
	var stone: Color = blocks.get_color(blocks.get_id("base:terrain:rock:rock01"))
	for i in range(1,12):
		var id: int = blocks.get_id("base:terrain:rock:rock%02d"%i)
		_check(blocks.get_color(id) == stone,"Natural rock has no altitude colour bands: %d"%i)
	var grass_seasons := {}
	for season in ["spring","summer","autumn","winter"]:
		var grass: Color = blocks.get_color(blocks.get_id("base:terrain:surface:grass_01"),season)
		grass_seasons[grass] = true
		for i in range(1,9):
			_check(blocks.get_color(blocks.get_id("base:terrain:surface:grass_%02d"%i),season) == grass,"Grass has one family in "+season)
		var dirt: Color = blocks.get_color(blocks.get_id("base:terrain:surface:dirt_01"),season)
		for i in range(1,5):
			_check(blocks.get_color(blocks.get_id("base:terrain:surface:dirt_%02d"%i),season) == dirt,"Dirt has no decorative shelf stripes in "+season)
		for id in blocks._id_to_key.size():
			var appearance: Dictionary = blocks.get_appearance_profile(id)
			var source: Color = blocks.get_color(id,season)
			var terrain: Color = blocks.get_terrain_color(id,season)
			if appearance.is_empty():
				_check(terrain == source,"Untagged material stays unchanged")
			else:
				var linear := source.srgb_to_linear()
				_check(is_equal_approx(terrain.r,linear.r) and is_equal_approx(terrain.g,linear.g) and is_equal_approx(terrain.b,linear.b),"Terrain converts sRGB exactly once")
				_check(roundi(terrain.a*16) == int(appearance.id),"Terrain tag matches the visible block profile")
	_check(grass_seasons.size() == 4,"Four seasons retain distinct authored grass colours")
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/underground_lighting.gdshader")
	_check(not material.get_shader_parameter("terrain_surface"),"Actors/props/water do not opt into terrain detail by default")
	blocks.configure_terrain_material(material)
	_check(material.get_shader_parameter("terrain_surface"),"Terrain material explicitly enables appearance profiles")
	_check(material.get_shader_parameter("terrain_profiles").size() == 8,"All profile slots bind to the shader")

func _full_grass_faces() -> void:
	var chunk := Chunk.new()
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	chunk.blocks[Chunk.local_index(8,8,8)] = grass
	chunk.has_void = true
	# Load after autoload startup; a SceneTree entry script is parsed before the
	# WorldClock singleton required by the static mesher has been registered.
	var mesher = load("res://scripts/systems/ChunkMesher.gd")
	var arrays: Array = mesher.build_arrays(chunk,3,2,3)
	_check(arrays[0].size() == 24,"An isolated full grass voxel emits six faces")
	var normals := {}
	for i in arrays[0].size():
		normals[arrays[1][i]] = true
		var color: Color = arrays[2][i]
		_check(color == blocks.get_terrain_color(grass,"summer"),"Every grass face uses grass; no dirt/turf band")
	_check(normals.size() == 6,"Grass sides and underside are covered")

func _cuts_and_merging() -> void:
	renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	var stone: Color = blocks.get_terrain_color(blocks.get_id("base:terrain:rock:rock01"))
	var cut: Color = renderer.slice_cut_color(stone)
	_check(is_equal_approx(cut.r,stone.r*.5) and roundi(cut.a*16) == 9,"Slice dims stone and marks it for quiet shading")
	_check(renderer.slice_cut_color(Color.WHITE).a == 1,"Imported floor art retains opaque untagged alpha")
	var a := {"wy":20,"block_id":1,"sliced":false,"color":stone}
	var b := {"wy":20,"block_id":2,"sliced":false,"color":stone}
	_check(renderer._overview_top_cells_merge(a,b),"Equivalent appearance merges across decorative IDs")
	b.sliced = true
	b.color = cut
	_check(not renderer._overview_top_cells_merge(a,b),"Cut and exposed tops never merge")
	b.sliced = false
	b.color = blocks.get_terrain_color(blocks.get_id("base:terrain:ore:copper"))
	_check(not renderer._overview_top_cells_merge(a,b),"Different visible materials never merge")
	renderer._added_terrain_dirty = false
	renderer._on_season_changed("winter")
	_check(renderer._added_terrain_dirty,"Added terrain participates in seasonal recolouring")

func _async_revisions() -> void:
	var key := Vector2i(3,3)
	renderer._ovt_batch.assign([key])
	renderer._ovt_revisions.assign([4])
	renderer._overview_revisions[key] = 4
	renderer._ovt_epoch = renderer._overview_epoch
	renderer._ovt_slice = renderer.slice_y
	renderer._ovt_season = root.get_node("WorldClock").season
	_check(renderer._overview_result_is_current(0),"Unchanged asynchronous result can be committed")
	renderer._enqueue_overview_tile(key)
	_check(not renderer._overview_result_is_current(0),"A newer edit invalidates an in-flight result")
	renderer._ovt_revisions[0] = renderer._overview_revisions[key]
	renderer._ovt_slice -= 1
	_check(not renderer._overview_result_is_current(0),"An older slice result cannot overwrite the current slice")
	renderer._ovt_slice = renderer.slice_y
	renderer._ovt_season = "winter"
	_check(not renderer._overview_result_is_current(0),"An older season result cannot overwrite the current palette")
	renderer._ovt_season = root.get_node("WorldClock").season
	renderer._overview_epoch += 1
	_check(not renderer._overview_result_is_current(0),"Global rebuild rejects results from the old world view")


func _generation_and_concealment() -> void:
	generator._cache_block_ids()
	generator.world_seed = 1234
	var pick: int = generator._grass_variant(48,48)
	generator.heightmap.resize(1024*1024)
	generator.heightmap.fill(40)
	generator.domain_map.resize(1024*1024)
	generator.domain_map.fill(2)
	generator.waterline_map.resize(1024*1024)
	generator.waterline_map.fill(-1)
	_check(generator._grass_variant(48,48) == pick,"Grass variation does not depend on height/edge maps")
	generator.heightmap[47*1024+48] = 1
	_check(generator._grass_variant(48,48) == pick,"A neighbouring cliff cannot repaint grass")
	generator._maps_ready = true
	var cell := Vector3i(48,22,48)
	var copper: int = blocks.get_id("base:terrain:ore:copper")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	renderer._visual_cut_blocks[cell] = true
	for direction: Vector3i in renderer._SHELL_DIRS:
		renderer._shell_exact_ids[cell+direction] = copper
		renderer._shell_strata_ids[cell+direction] = stone
	renderer._rebuild_cavity_shell()
	var planned: PackedColorArray = renderer._cavity_shell_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for color in planned:
		_check(roundi(color.a*16) == 1,"Designation mesh cannot carry a hidden mineral profile")
	renderer._mined_blocks[cell] = true
	renderer._rebuild_cavity_shell()
	var revealed: PackedColorArray = renderer._cavity_shell_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for color in revealed:
		_check(roundi(color.a*16) == 5,"Real discovery supplies the mineral profile")
	generator._maps_ready = false

func _added_terrain_faces() -> void:
	var world := root.get_node("WorldData")
	var clock := root.get_node("WorldClock")
	var old_season: String = clock.season
	var old_slice: int = renderer.slice_y
	var grass: int = blocks.get_id("base:terrain:surface:grass_01")
	var cell := Vector3i(70,45,70)
	generator._build_noise_instances()
	generator._maps_ready = true
	world.clear_world()
	world.set_block(cell.x,cell.y,cell.z,grass)
	world.set_block(cell.x+1,cell.y,cell.z,grass)
	renderer.slice_y = 127
	renderer._rebuild_added_terrain()
	var arrays: Array = renderer._added_terrain.mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_VERTEX].size() == 40,"Adjacent added voxels cull their shared faces")
	for color: Color in arrays[Mesh.ARRAY_COLOR]:
		_check(_mesh_color_matches(color,blocks.get_terrain_color(grass,clock.season)),"Added grass stays grass on every exposed face")
	world.set_block(cell.x,cell.y+1,cell.z,grass)
	renderer.slice_y = cell.y
	renderer._rebuild_added_terrain()
	arrays = renderer._added_terrain.mesh.surface_get_arrays(0)
	var cut_vertices := 0
	for i in arrays[Mesh.ARRAY_COLOR].size():
		var color: Color = arrays[Mesh.ARRAY_COLOR][i]
		if roundi(color.a*16) == 10:
			cut_vertices += 1
			_check(arrays[Mesh.ARRAY_NORMAL][i].dot(Vector3.UP) > 0.999,"Only the sliced top carries the quiet cut profile")
	_check(cut_vertices == 4,"Added terrain dims exactly the top below the hidden solid block")
	clock.season = "winter"
	renderer._rebuild_added_terrain()
	arrays = renderer._added_terrain.mesh.surface_get_arrays(0)
	var winter: Color = blocks.get_terrain_color(grass,"winter")
	for color: Color in arrays[Mesh.ARRAY_COLOR]:
		_check(_mesh_color_matches(color,winter) or _mesh_color_matches(color,renderer.slice_cut_color(winter)),"Added terrain rebuild uses the current seasonal palette")
	world.clear_world()
	clock.season = old_season
	renderer.slice_y = old_slice
	generator._maps_ready = false

func _mesh_color_matches(actual: Color, expected: Color) -> bool:
	# ArrayMesh stores vertex colours in normalized RGBA8.
	return absf(actual.r-expected.r) <= 1.0/255.0 and absf(actual.g-expected.g) <= 1.0/255.0 and absf(actual.b-expected.b) <= 1.0/255.0 and absf(actual.a-expected.a) <= 1.0/255.0

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
