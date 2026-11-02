extends SceneTree

## Sliced-away torches keep lighting their room (doc 287). A hall and the room beside it share a
## wall; a torch hangs high in the hall and the slice cuts below it. The piece stays hidden and
## unpickable while its light comes on beside it once the shadow-only rock covers its reach.
## That rock stops the light past the cut wall (into the next room and onto the wall's cut top)
## and leaves its own room clear; digging through it opens the way without the light blinking;
## the sun never casts from it; a cold light stops its flicker; raising the slice brings the
## light home and lowering it again reuses the rock, the next layer down already built; removing
## the piece takes the light along.
## Headless: rays against the shadow meshes stand in for rendered shadows.
## godot --headless --path . --script res://scripts/tests/SlicedTorchLightTest.gd

const TORCH := "base:furniture:wooden_torch"
const SLICE := 21                        # shows the floor and the first layer of wall
const MOUNT := Vector3i(80, 25, 83)      # on the hall's west wall, facing east

var failures: Array[String] = []
# Loaded at run time: game scripts name autoloads, which a --script file's compile cannot see.
var Lighting
var TerrainLighting
var SlicedLights
var world
var blocks
var scene: Node3D
var renderer
var occluders: Node3D
var furniture


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Sliced torch light test timed out"); quit(1))
	for id in ["SaveManager", "TaskManager", "RoomManager", "StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var generator = root.get_node("WorldGenerator")
	generator.world_seed = 1234
	generator._cache_block_ids()
	generator.heightmap.resize(1024 * 1024)
	generator.heightmap.fill(20)
	generator.waterline_map.resize(1024 * 1024)
	generator.waterline_map.fill(-1)
	generator._maps_ready = true
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	Lighting = load("res://scripts/components/FurnitureLighting.gd")
	TerrainLighting = load("res://scripts/components/TerrainLighting.gd")
	SlicedLights = load("res://scripts/components/SlicedFurnitureLights.gd")
	_build_ground()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	# The production renderer keeps the cut sets; it stays out of the tree so no terrain builds.
	renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	world.block_changed.connect(renderer._terrain_block_changed)
	occluders = load("res://scripts/components/SliceLightOccluders.gd").new(renderer)
	scene.add_child(occluders)
	renderer.light_occluders = occluders
	_build_rooms()
	renderer._flush_terrain_changes()
	furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture.name = "Furniture"
	scene.add_child(furniture)
	furniture.set_process(false)
	furniture._sliced_lights.renderer = renderer
	var def: Dictionary = furniture.get_defs()[TORCH]
	furniture.install_now(TORCH, MOUNT - Vector3i.UP * 2, 1)
	var piece = furniture.get_installed_pieces()[0]
	var light = Lighting.light_of(piece.node)
	var at: Vector3 = light.global_position
	_expect(light != null and light.get_parent() == piece.node and piece.node.visible, "an unsliced torch carries its own light")
	_expect(at.distance_to(Vector3(80.8125, 26.6875, 83.5)) < .01, "the flame hangs high in the hall: %s" % at)

	await _slice(SLICE)
	_expect(not piece.node.visible and furniture.pick_explorer_object(at + Vector3.UP * 20, at - Vector3.UP * 4).is_empty(),
		"the slice still hides the torch, and it cannot be picked")
	_expect(light.get_parent() != piece.node and light.is_visible_in_tree() and light.global_position.distance_to(at) < .001,
		"its light burns on at the same spot, beside the hidden model")
	_expect(piece.node.get_node("FlameAnimation").is_processing(), "the sliced light keeps flickering")
	var shown := occluders.get_children().filter(func(node: Node) -> bool: return node is MeshInstance3D and node.visible)
	_expect(not shown.is_empty() and shown.all(func(node: MeshInstance3D) -> bool:
		return node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and node.layers == TerrainLighting.SLICE_OCCLUDER_LAYER),
		"the rock behind it is shadow-only, on its own layer")
	var hall_floor := Vector3(84.5, 21.05, 84.5)
	var next_floor := Vector3(91.5, 21.05, 83.5)
	var wall_top := Vector3(88.5, 22.02, 83.5)
	_expect(not _blocked(at, hall_floor) and not _blocked(at, Vector3(87.5, 21.05, 87.5)), "nothing shades the torch's own room")
	_expect(_blocked(at, next_floor), "the sliced-away wall still keeps its light out of the next room")
	_expect(_blocked(at, wall_top), "and off the wall's cut top")
	var sun := DirectionalLight3D.new()
	TerrainLighting.configure_sun(sun)
	_expect(sun.shadow_caster_mask & TerrainLighting.SLICE_OCCLUDER_LAYER == 0 and sun.shadow_caster_mask & TerrainLighting.TERRAIN_LAYER != 0,
		"the sun casts from terrain but never from the sliced-off rock")
	sun.free()
	_expect(SlicedLights.reach_box(light, 4).size == Vector3.ZERO and SlicedLights.reach_box(light, SLICE).has_volume(),
		"a light whose range ends above the cut asks for nothing")

	Lighting.set_lit(piece.node, def, false)
	_expect(not light.visible and not piece.node.get_node("FlameAnimation").is_processing(), "a lifted light still goes cold, and its flicker stops")
	Lighting.set_lit(piece.node, def, true)
	_expect(light.visible and piece.node.get_node("FlameAnimation").is_processing(), "and lights again")

	# Dig through the wall where the leaking ray would pass, above the cut.
	world.set_block(88, 22, 83, blocks.AIR_ID)
	renderer._flush_terrain_changes()
	var blinked := false
	for i in 30:
		await _frame()
		blinked = blinked or light.get_parent() == piece.node
		if not _blocked(at, next_floor): break
	_expect(not _blocked(at, next_floor), "digging through the rock opens the way for the light")
	_expect(not blinked, "the light stays on while the rock rebuilds")

	await _slice(world.MAX_Y)
	_expect(piece.node.visible and light.get_parent() == piece.node, "raising the slice brings the light home")
	_expect(occluders.get_children().all(func(node: Node) -> bool: return not (node as Node3D).visible), "and hides the shadow rock")
	furniture._on_slice_changed(SLICE)
	_expect(light.get_parent() != piece.node and light.is_visible_in_tree(), "lowering it again reuses the rock at once")
	furniture._on_slice_changed(SLICE - 7)
	_expect(light.get_parent() != piece.node, "a step down into the next chunk layer finds its rock built ahead")
	furniture._on_slice_changed(SLICE)

	furniture.dev_remove_installed(piece.installed_id)
	await _frame()
	await _frame()
	_expect(not is_instance_valid(light), "removing the sliced torch takes its light along")
	renderer.free()
	for failure: String in failures: push_error(failure)
	print("SLICED_TORCH_LIGHT_OK: hidden piece, lifted light, shadow rock, own room clear, neighbour dark, edits, sun, cold light, slice up, removal"
		if failures.is_empty() else "SLICED_TORCH_LIGHT_FAIL")
	quit(0 if failures.is_empty() else 1)


## Stone up to y 20 under the site, as the synthetic heightmap says.
func _build_ground() -> void:
	var chunk_script = load("res://scripts/systems/Chunk.gd")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for cx in range(3, 8):
		for cz in range(3, 8):
			for cy in range(3):
				var chunk = chunk_script.new()
				for ly in range(16):
					if cy * 16 + ly > 20: continue
					for lz in range(16):
						for lx in range(16):
							chunk.blocks[lx + 16 * lz + 256 * ly] = stone
				world.submit_chunk(cx, cy, cz, chunk)


## The hall (inside x 80-87) and the room beside it (x 89-93) share the wall at x 88; both run
## z 80-87, walls up to y 28 under a roof at y 29.
func _build_rooms() -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(79, 95):
		for z in range(79, 89):
			for y in range(21, 30):
				if y == 29 or x in [79, 88, 94] or z in [79, 88]: world.set_block(x, y, z, stone)


func _slice(height: int) -> void:
	renderer.slice_y = height
	furniture._on_slice_changed(height)
	for i in 60:
		await _frame()
		if not occluders._queue.is_empty(): continue
		if furniture._sliced_lights.dirty: continue
		break


func _frame() -> void:
	await process_frame
	furniture._process(.016)


## Whether a segment crosses any shown shadow-rock triangle.
func _blocked(from: Vector3, to: Vector3) -> bool:
	for node: Node in occluders.get_children():
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or not mesh_node.visible or mesh_node.mesh == null or mesh_node.is_queued_for_deletion(): continue
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			if Geometry3D.segment_intersects_triangle(from, to, verts[indices[t]], verts[indices[t + 1]], verts[indices[t + 2]]) != null:
				return true
	return false


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
