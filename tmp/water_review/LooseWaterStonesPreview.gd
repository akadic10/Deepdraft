extends SceneTree

const OUTPUT := "res://tmp/water_review/loose_stones"
var Picking
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func picture(name: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
func _run() -> void:
	Picking = load("res://scripts/components/ObjectPicking.gd")
	create_timer(180).timeout.connect(func(): push_error("Loose stone preview timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("WorldClock").paused = true
	root.get_node("SaveManager").set_process(false)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",2795346874))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	await process_frame
	var terrain = current_scene.get_node("Renderer")
	var gen = root.get_node("WorldGenerator")
	var world = root.get_node("WorldData")
	var water = root.get_node("WaterManager")
	var blocks = root.get_node("BlockRegistry")
	while not terrain._overview_built or terrain._overview_tile_nodes.size()!=1024: await process_frame
	while not water.initialized or not water.dirty_tiles.is_empty(): await process_frame
	var stones = terrain.get_node("Water/Stones")
	check(stones.stones.size()==2,"world does not have exactly two water stones")
	var wet: Node3D = stones.stones.wet
	var dry: Node3D = stones.stones.dry
	check(wet.visible and not dry.visible,"cave stone must be visible; fully submerged lake stone must be hidden")
	check(stones.get_explorer_data("wet").title=="Wet stone","visible stone inspection missing")
	check(stones.get_explorer_data("dry").is_empty(),"underwater stone remains pickable")
	var state: Dictionary = water.serialize_state()
	for node in current_scene.find_children("*","CanvasLayer",true,false): node.visible = false
	root.size = Vector2i(1200,850)
	root.get_node("SkyController").rebind_to_current_scene()
	root.get_node("WorldClock").hour = 11.0
	root.get_node("SkyController")._update(11.0)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	current_scene.add_child(camera)
	camera.make_current()
	# Compare imported topology, scale and silhouette to the existing copper ore.
	var reference = load("res://assets/models/items/ore/copper_ore.glb").instantiate()
	current_scene.add_child(reference)
	var reference_arrays: Array = reference.find_children("*","MeshInstance3D",true,false)[0].mesh.surface_get_arrays(0)
	for node: Node3D in [wet,dry]:
		var mesh: MeshInstance3D = node.find_children("*","MeshInstance3D",true,false)[0]
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		for kind in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_INDEX]:
			check(arrays[kind]==reference_arrays[kind],node.name+" does not use exact ore topology")
		check(mesh.material_override is ShaderMaterial,node.name+" lacks normal underground lighting")
		var bounds: AABB = Picking.world_bounds(node)
		check(bounds.size.is_equal_approx(Vector3.ONE) and is_equal_approx(bounds.position.y,node.position.y),node.name+" scale or grounding differs from ore")
	# Native art comparison above the world, using the same runtime material.
	var stage := Node3D.new()
	current_scene.add_child(stage)
	stage.position = Vector3(400,170,400)
	reference.reparent(stage)
	stones._apply_material(reference)
	reference.position = Vector3(-2,0,0)
	for i in 2:
		var kind: String = ["wet","dry"][i]
		var model: Node3D = load(String(gen.water_profile.stones[kind].model)).instantiate()
		stones._apply_material(model)
		stage.add_child(model)
		model.position = Vector3(i*2,0,0)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(7,0.125,3)
	floor_mesh.mesh = plane
	var matte := StandardMaterial3D.new()
	matte.albedo_color = Color("858A86")
	floor_mesh.material_override = matte
	stage.add_child(floor_mesh)
	floor_mesh.position.y = -.0625
	camera.size = 8
	camera.position = stage.position+Vector3(3,5,9)
	camera.look_at(stage.position+Vector3(0,.25,0))
	await picture("ore_wet_dry")
	stage.free()
	var point := dry.position+Vector3(0,.5,0)
	var toward_lake := Vector3(gen.lake_center.x-point.x,0,gen.lake_center.y-point.z).normalized()
	camera.size = 12
	camera.position = point+toward_lake*12+Vector3(0,12,0)
	camera.look_at(point)
	await picture("lake_submerged")
	check(water.serialize_state()==state,"creating or viewing stones changes simulation state")
	var back2: Vector2i = gen.river_layout.spring_back
	var back := Vector3(back2.x,0,back2.y)
	var side := Vector3(-back2.y,0,back2.x)
	var slices = current_scene.get_node("SliceController")
	slices.restore_state({"active":true,"slice_y":floori(wet.position.y)+1})
	while not terrain._dirty_overview_tiles.is_empty(): await process_frame
	point = wet.position+Vector3(0,.25,0)
	camera.size = 8
	camera.position = point-back*5-side*2+Vector3(0,7,0)
	camera.look_at(point)
	await picture("wet_cave_daylight")
	var lamp := OmniLight3D.new()
	current_scene.add_child(lamp)
	lamp.position = wet.position-back*2+Vector3(0,2,0)
	lamp.omni_range = 8
	lamp.light_energy = 2
	lamp.light_color = Color("FFCD88")
	lamp.shadow_enabled = true
	await picture("wet_cave_lit")
	lamp.free()
	var pick: Dictionary = stones.pick_explorer_object(wet.position+Vector3(0,3,0),wet.position-Vector3.UP)
	check(pick.get("id","")=="wet","ore-shaped wet stone cannot be selected")
	slices.restore_state({"active":true,"slice_y":floori(wet.position.y)-1})
	await process_frame
	await process_frame
	check(not wet.visible and stones.get_explorer_data("wet").is_empty(),"stone above slice remains visible/selectable")
	slices.deactivate()
	while not terrain._dirty_overview_tiles.is_empty(): await process_frame
	# Isolated drawdown exposes the real lakebed model, no material overrides.
	var cell: Vector3i = gen.river_layout.dry_stone
	for dx in range(-5,6):
		for dz in range(-5,6):
			var x := cell.x+dx
			var z := cell.z+dz
			if x<0 or z<0 or x>=1024 or z>=1024: continue
			water.extract(Vector3i(x,gen.get_surface_y(x,z)+1,z),100)
	while not water.dirty_tiles.is_empty(): await process_frame
	await process_frame
	check(dry.visible and stones.get_explorer_data("dry").title=="Dry stone","drawdown does not expose dry stone")
	point = dry.position+Vector3(0,.5,0)
	camera.size = 7
	camera.position = point+toward_lake*7+Vector3(0,12,0)
	camera.look_at(point)
	await picture("dry_lakebed_exposed")
	# Mining support settles the loose model; restoring water recreates exactly
	# two models on the same edited terrain, without changing the fixed intake.
	var original_position := dry.position
	var support := cell-Vector3i.UP
	world.set_block(support.x,support.y,support.z,0)
	await process_frame
	check(dry.position.y==original_position.y-1,"dry stone floats after support is mined")
	var settled_position := dry.position
	var restore: Dictionary = water.serialize_state()
	water.restore_state(restore)
	await process_frame
	await process_frame
	check(stones.stones.size()==2 and stones.get_child_count()==2,"water restore duplicates stones")
	check(stones.stones.dry.position==settled_position,"stone does not settle consistently after restore")
	check(gen.river_layout.outlet==cell and is_equal_approx(gen.river_layout.outlet_level,19),"stone presentation moved the drain")
	print("LooseWaterStonesPreview: ","PASS exact ore meshes; grounding; lighting; submerged/slice/picking guards; support edits; restoration" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
