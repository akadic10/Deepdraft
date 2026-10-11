extends SceneTree

## Real imported drops, pickup/storage/restore, and optional native lighting QA.
## Run --headless for contracts, or without it and with -- --capture for PNGs.
const OUT := "res://tmp/gem_drop_review/"
const NAMES := ["jade", "amethyst", "ruby", "sapphire", "emerald", "diamond"]
var Picking
var failures: Array[String] = []
var scene: Node3D
var items
var field
var camera: Camera3D
var sun: DirectionalLight3D
var gems: Array[Node3D] = []
var measurements := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	Picking = load("res://scripts/components/ObjectPicking.gd")
	create_timer(90).timeout.connect(func(): push_error("Gem art test timed out"); quit(1))
	for id in ["SaveManager", "WorldClock", "TaskManager", "RoomManager", "StockpileManager", "SkyController", "WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("WorldGenerator").world_seed = 1234
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	for x in range(16, 48):
		for z in range(16, 48): world.set_block(x, 20, z, blocks.get_id("base:terrain:rock:rock01"))
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	field = load("res://scripts/components/UndergroundLighting.gd").new()
	scene.add_child(field)
	field.set_process(false)
	items = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(items)
	var reference_colours := {}
	for i in range(NAMES.size()):
		var resource: Dictionary = blocks.get_resource_def("base:terrain:gem:" + NAMES[i])
		var key: String = resource.drops[0].item
		_expect(ResourceLoader.exists("res://assets/ui/items/" + key.replace(":", "_") + ".png"), key + " has an inventory thumbnail")
		var cell := Vector3i(24 + (i % 3) * 3, 20, 24 + (i / 3) * 3)
		items.spawn_drop(key, 1, cell + Vector3i.UP)
		var node: Node3D = items.get_children().back()
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		_expect(meshes.size() == 1 and meshes[0].mesh is ArrayMesh, key + " imports real gem geometry")
		var mesh := meshes[0] as MeshInstance3D
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var normal_error := 0.0
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normal_error = maxf(normal_error, normal.distance_to(normal.round()))
		var grid_error := 0.0
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			grid_error = maxf(grid_error, (vertex * 8).distance_to((vertex * 8).round()))
		# Imported vertex/normal compression has tiny quantization error. The
		# generator also checks its uncompressed coordinates/normals exactly.
		_expect(normal_error < .0002 and grid_error < .0002, key + " has only cube faces on the project voxel grid")
		measurements[NAMES[i] + "_geometry"] = {"normal_error": normal_error, "grid_error": grid_error}
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_expect(not reference_colours.has(colors), key + " has a distinct palette")
		reference_colours[colors] = true
		var material := mesh.material_override as ShaderMaterial
		_expect(material != null and float(material.get_shader_parameter("surface_specular")) > .5, key + " uses underground-aware gloss")
		_expect(items.take(node) == key, key + " can be picked up")
		var carrier := Node3D.new()
		scene.add_child(carrier)
		carrier.add_child(node)
		_expect(mesh.material_override == material and items.quantity_of(node) == 1, key + " retains art and quantity in transit")
		items.place_stored(node, cell)
		carrier.free()
		var bounds: AABB = Picking.world_bounds(node)
		_expect(bounds.size.x < 1 and bounds.size.z < 1 and is_equal_approx(bounds.position.y, 21), key + " fits a grounded stockpile tile")
		var slot: Node3D = items.create_item_visual(key)
		scene.add_child(slot)
		load("res://scripts/components/StorageItemLayout.gd").fit(slot, Vector3(.3125,.625,.3125), .5)
		var slot_bounds: AABB = Picking.world_bounds(slot)
		_expect(slot_bounds.size.x <= .313 and slot_bounds.size.z <= .313 and is_zero_approx(slot_bounds.position.y), key + " fits a shelf slot without hovering")
		_expect(slot.find_children("*", "MeshInstance3D", true, false)[0].material_override == material, key + " shares gloss in shelf visuals")
		slot.free()
		items.drop_loose(node, cell)
		# Stable presentation positions after testing the actual loose-drop path.
		node.position = Vector3(cell) + Vector3(.5,1,.5)
		node.rotation.y = .18
		gems.append(node)
	_expect(items._missing_models.is_empty(), "all six gem paths resolve without fallback cubes")
	items._on_slice_changed(20)
	for gem in gems: _expect(not gem.visible, "gem above cut is concealed")
	items._on_slice_changed(21)
	for gem in gems: _expect(gem.visible, "gem at cut is visible")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(items.serialize_state()))
	var restored = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(restored)
	restored.restore_state(saved)
	_expect(restored._loose.size() == 6 and restored._missing_models.is_empty(), "current save restores all six real gem models")
	var round_trip: Array = restored.serialize_state().loose
	for i in range(saved.loose.size()):
		var before: Dictionary = saved.loose[i]
		var after: Dictionary = round_trip[i]
		_expect(before.item_key == after.item_key and int(before.count) == int(after.count)
			and Vector3(before.position[0], before.position[1], before.position[2]).is_equal_approx(Vector3(after.position[0], after.position[1], after.position[2]))
			and is_equal_approx(float(before.rotation_y), float(after.rotation_y)), "save round trip preserves " + before.item_key)
	restored.free()
	var stone: Node3D = items.create_item_visual("base:resources:stone:rough_stone")
	var stone_material := stone.find_children("*", "MeshInstance3D", true, false)[0].material_override as ShaderMaterial
	_expect(float(stone_material.get_shader_parameter("surface_specular")) == 0, "ordinary drops remain matte")
	stone.free()
	if "--capture" in OS.get_cmdline_user_args(): await _native_review()
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"failures": failures, "gems": gems.size(), "measurements": measurements}
	var report_name := "checks.json" if "--capture" in OS.get_cmdline_user_args() else "checks_headless.json"
	FileAccess.open(OUT + report_name, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("GEM_DROP_ART_TEST: ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _native_review() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1320, 900)
	root.msaa_3d = Viewport.MSAA_4X
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111E24")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("DCE9EF")
	env.ambient_light_energy = .6
	environment.environment = env
	scene.add_child(environment)
	var center := Vector3(27.5,21.25,26)
	sun = DirectionalLight3D.new()
	scene.add_child(sun)
	sun.position = center + Vector3(0,7,-9)
	sun.look_at(center)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	for gem in gems:
		var tile := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.6,.12,1.6)
		tile.mesh = box
		var source := StandardMaterial3D.new()
		source.albedo_color = Color("394B50")
		tile.material_override = field.make_material(source)
		scene.add_child(tile)
		tile.position = gem.position - Vector3(0,.06,0)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = center + Vector3(0,7,10)
	camera.look_at(center)
	camera.current = true
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	_label(layer, "FINISHED GEMS", Vector2(56,35), 32)
	_label(layer, "Brilliant from the moment they are mined", Vector2(57,81), 20)
	for gem in gems:
		var name_label := _label(layer, items.get_item_def(gem.get_meta("item_key")).display_name, Vector2.ZERO, 22)
		name_label.position = camera.unproject_position(gem.position + Vector3(0,0,1.03)) - Vector2(65,0)
		name_label.custom_minimum_size.x = 130
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(layer, "Jade  /  Amethyst  /  Ruby  /  Sapphire  /  Emerald  /  Diamond", Vector2(57,811), 18)
	_label(layer, "Native game models and lighting  ·  No cutting or jeweller required", Vector2(57,844), 18)
	# Allow the autoloads' deferred scene binding to finish before fixing this
	# comparison's environment and camera-facing key light.
	for frame in range(4): await process_frame
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("DCE9EF")
	env.ambient_light_energy = .7
	env.ambient_light_sky_contribution = 0
	env.fog_enabled = false
	sun.look_at(center)
	sun.light_color = Color("FFEDD4")
	sun.light_energy = 1.0
	var daylight := await _capture("gems.png")
	# Compare the same pixels with gloss disabled: baked colours alone cannot pass.
	for material: ShaderMaterial in items._surface_materials.values(): material.set_shader_parameter("surface_specular", 0)
	var matte := await _capture("")
	measurements.gloss_difference = _difference(daylight, matte)
	_expect(measurements.gloss_difference > .00001, "real lights produce visible facet reflections")
	for key: String in items._surface_materials:
		items._surface_materials[key].set_shader_parameter("surface_specular", items.get_item_def(key).surface.specular)
	# The solver itself has UndergroundLightingTest coverage. Feed sealed air to
	# this shader probe to isolate gem gloss from world generation and navigation.
	for x in range(21,35):
		for y in range(20,24):
			for z in range(21,32): field._write_cell(Vector3i(x,y,z), 0.0, true)
	field._upload()
	var dark := await _capture("sealed_dark.png")
	sun.visible = false
	var no_sun := await _capture("")
	measurements.sealed_sun_difference = _difference(dark, no_sun)
	_expect(measurements.sealed_sun_difference < .0001, "sealed gems receive neither diffuse nor specular sunlight")
	var torch := OmniLight3D.new()
	scene.add_child(torch)
	torch.position = center + Vector3(0,3,-4)
	torch.light_color = Color("FFD6A2")
	torch.light_energy = 4
	torch.omni_range = 13
	var torchlight := await _capture("torchlight.png")
	measurements.torch_difference = _difference(torchlight, dark)
	_expect(measurements.torch_difference > .0001, "local torchlight reaches sealed gem facets")
	# Native scale beside a real dwarf, with the actual carry pose and shelf
	# container path (both must retain the item material after reparenting).
	torch.free()
	sun.visible = true
	layer.hide()
	for child in scene.get_children():
		if child is MeshInstance3D: child.hide()
	for x in range(21,35):
		for y in range(20,26):
			for z in range(21,32): field._write_cell(Vector3i(x,y,z), 1.0, true)
	field._upload()
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(10,.1,6)
	floor_mesh.mesh = floor_box
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("394B50")
	floor_mesh.material_override = field.make_material(floor_material)
	scene.add_child(floor_mesh)
	floor_mesh.position = Vector3(27.5,20.95,26.5)
	for i in range(gems.size()): gems[i].position = Vector3(26.5 + i,21,28)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var worker = factory.spawn(factory.generate(141, {}), 141)
	scene.add_child(worker)
	worker.set_process(false)
	worker.position = Vector3(25.3,21,26.5)
	worker.rotation.y = -.25
	var cargo := gems[2]
	var cargo_key: String = cargo.get_meta("item_key")
	items.take(cargo)
	worker.add_child(cargo)
	worker._carried_entries.append([cargo, cargo_key])
	worker._carry_pose.hold(worker._carried_entries)
	field.bind_tree(worker)
	field._sync_actors()
	var carried_mesh := cargo.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_expect(carried_mesh.material_override == items._surface_materials[cargo_key], "actual dwarf carry pose retains gem material")
	_expect(float(carried_mesh.get_instance_shader_parameter("actor_sky_access")) >= 0, "carried gem binds to the dwarf's underground exposure")
	var furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	furniture._load_defs()
	var shelf_def: Dictionary = furniture.get_defs()["base:furniture:storage_shelf"]
	var shelf: Node3D = load(shelf_def.model).instantiate()
	furniture._apply_material(shelf, furniture._make_solid_material())
	scene.add_child(shelf)
	shelf.position = Vector3(29.5,21,25.5)
	field.bind_tree(shelf)
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(29,20,25)]
	container.setup_container(shelf_def, cells)
	container.display_parent = shelf
	var stock := {}
	for name in NAMES: stock["base:resources:gem:" + name + "_raw"] = 1
	container.restore_inventory(stock, items)
	_expect(container.stored_count() == 6 and container.occupied_slots() == 6, "actual shelf restores all six gems into individual slots")
	for slot in container._anchor_slots:
		if slot == null: continue
		var stored_mesh := slot[0].find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_expect(stored_mesh.material_override == items._surface_materials[slot[1]], "actual shelf retains gem material")
	furniture.free()
	camera.position = Vector3(33,28,37)
	camera.look_at(Vector3(27.6,22.2,26.4))
	camera.size = 8.8
	var context_layer := CanvasLayer.new()
	scene.add_child(context_layer)
	_label(context_layer, "GEMS AT GAME SCALE", Vector2(56,35), 32)
	_label(context_layer, "Carried ruby  ·  Six gems on a storage shelf  ·  Loose drops", Vector2(57,81), 20)
	await _capture("game_scale.png")


func _capture(filename: String) -> Image:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	if not filename.is_empty(): result.save_png(OUT + filename)
	return result


func _difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(170, 750, 2):
		for x in range(120, 1200, 2):
			var ac := a.get_pixel(x,y)
			var bc := b.get_pixel(x,y)
			total += absf(ac.r-bc.r) + absf(ac.g-bc.g) + absf(ac.b-bc.b)
			count += 3
	return total / count


func _label(layer: CanvasLayer, text: String, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	layer.add_child(label)
	return label


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
