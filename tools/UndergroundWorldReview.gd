extends SceneTree

const OUTPUT := "res://tmp/underground_lighting_review/"
var failures: Array[String] = []
var renderer
var field
var generator

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Underground world review timed out"); quit(1))
	if not "/underground_lighting_review/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Review requires isolated APPDATA")
		quit(1)
		return
	root.get_node("SaveManager").configure_storage_for_testing("user://lighting_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1400,900)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	await _settle()
	var entrance := _find_cliff()
	if entrance.x < 0:
		push_error("No suitable native tunnel fixture found")
		quit(1)
		return
	var mining = current_scene.get_node("MiningDesignationController")
	var mined: Array[Vector3i] = []
	for x in range(entrance.x+1,entrance.x+18):
		for z in range(entrance.z,entrance.z+4):
			for y in range(entrance.y+1,entrance.y+5): mined.append(Vector3i(x,y,z))
	var tile_builds: int = renderer._overview_build_count
	mining._mine_blocks_world(mined)
	await _settle()
	var mining_rebuilds: int = renderer._overview_build_count-tile_builds
	_expect(mining_rebuilds <= 12,"mining keeps terrain invalidation local")
	var deep := entrance+Vector3i(12,2,2)
	_expect(field.sky_at(deep) == 0,"generated mountain blocks sky light")
	var slice = current_scene.get_node("SliceController")
	var updates: int = field.completed_updates
	slice._set_slice_y(entrance.y+4)
	await _settle()
	_expect(field.sky_at(deep) == 0 and field.completed_updates == updates,"slicing removes no roof from lighting data")
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34
	camera.position = Vector3(entrance)+Vector3(-13,35,34)
	camera.look_at(Vector3(entrance)+Vector3(8,1,2))
	camera.current = true
	var dwarves = current_scene.get_node("DwarfDirector")
	dwarves._spawn_one(entrance.x-2,entrance.z+1)
	var dwarf = dwarves._agents.back()
	dwarf.position = Vector3(deep)+Vector3(.5,-1,.5)
	dwarf.set_process(false)
	dwarf.apply_slice(entrance.y+4)
	var meshes: Array = dwarf.find_children("*","MeshInstance3D",true,false)
	_expect(meshes[0].material_override is ShaderMaterial,"live director binds dwarf lighting")
	# A portrait copy must keep studio materials after the live actor is shaded.
	var texture := TextureRect.new()
	current_scene.add_child(texture)
	var portrait = load("res://scripts/ui/DwarfPortrait.gd")
	var viewport: SubViewport = portrait.create_viewport(texture)
	var model: Node3D = portrait.create_model(viewport,dwarf)
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		_expect(mesh.material_override is BaseMaterial3D,"portrait retains studio materials")
	texture.queue_free()
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	await _capture("world_unlit")
	var furniture = current_scene.get_node("FurniturePlacementController")
	var key := "base:furniture:wall_torch"
	var def: Dictionary = furniture.get_defs()[key]
	furniture._install(key,def,entrance+Vector3i(7,0,0),0)
	furniture._install(key,def,entrance+Vector3i(14,0,0),0)
	await _capture("world_torches")
	var drops = current_scene.get_node("ItemDropManager")
	_expect(drops._material is ShaderMaterial,"live loose goods use the lighting field")
	# A hidden flame must keep the existing slice visibility contract.
	slice._set_slice_y(entrance.y+2)
	await _settle()
	for installed in furniture._installed.values():
		if installed.furniture_key == key: _expect(not installed.node.visible,"low slice hides torch and its light")
	_expect(field.sky_at(deep) == 0,"lower slice still does not change sky access")
	var report := {"entrance":str(entrance),"failures":failures,"mining_tile_rebuilds":mining_rebuilds,"lighting_max_frame_ms":field.max_step_usec/1000.0,"allocated_tiles":field._slots.size()}
	var file := FileAccess.open(OUTPUT+"world_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("UNDERGROUND_WORLD_REVIEW: ",JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _find_cliff() -> Vector3i:
	for z in range(256,768,4):
		for x in range(256,768):
			var floor_y: int = generator.get_surface_y(x,z)
			if floor_y < 8 or floor_y > 105: continue
			if generator.get_surface_y(x+1,z) < floor_y+7: continue
			var valid := true
			for dx in range(1,19):
				for dz in range(4):
					if generator.get_surface_y(x+dx,z+dz) < floor_y+7: valid = false
			if valid: return Vector3i(x,floor_y,z)
	return Vector3i(-1,-1,-1)

func _settle() -> void:
	for i in range(4): await process_frame
	while field.is_updating() or not renderer._dirty_overview_tiles.is_empty() or renderer._cavity_shell_dirty:
		await process_frame

func _capture(label: String) -> void:
	for i in range(10): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
