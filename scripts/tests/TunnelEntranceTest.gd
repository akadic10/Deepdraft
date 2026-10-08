extends "res://tools/UndergroundWorldReview.gd"

## Native production-world A/B: entrance tuning, actor overlap with solid
## designation cells, attached meshes, portraits, and slice invariance.
const REVIEW := "res://tmp/underground_lighting_review/entrance_fix/"
var camera: Camera3D
var measures := {}

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Tunnel entrance test timed out"); quit(1))
	if not "/underground_lighting_review/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("Review requires isolated APPDATA"); quit(1); return
	root.get_node("SaveManager").configure_storage_for_testing("user://entrance_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1400, 900)
	node_added.connect(func(node: Node):
		if node.name == "Renderer" and node.get_script() != null: node.set("world_seed", 1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready", false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	await _settle()
	var entrance := _find_cliff()
	_expect(entrance.x >= 0, "suitable native cliff exists")
	if entrance.x < 0: quit(1); return
	var mining = current_scene.get_node("MiningDesignationController")
	var mined: Array[Vector3i] = []
	for dx in range(1, 18):
		for dz in range(4):
			for dy in range(1, 5): mined.append(entrance + Vector3i(dx, dy, dz))
	field.reach = 7 # render the previous production entrance at the same camera
	mining._mine_blocks_world(mined)
	await _settle()
	var slice = current_scene.get_node("SliceController")
	slice.restore_state({"active":true, "seeded":true, "slice_y":entrance.y+4, "last_slice_y":entrance.y+4})
	await _settle()
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 29
	camera.position = Vector3(entrance) + Vector3(-7, 46, 20)
	camera.look_at(Vector3(entrance) + Vector3(8, 1, 2))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	var prior := await _image("entrance_before")
	measures.before = _floor_samples(prior, entrance)
	field.reach = int(root.get_node("SkyController").underground_settings().entrance_reach_blocks)
	# Retune the derived field without changing terrain or forcing mesh rebuilds.
	var builds: int = renderer._overview_build_count
	for cell in mined: field._pending[cell] = root.get_node("BlockRegistry").AIR_ID
	await _settle()
	var after := await _image("entrance_after")
	measures.after = _floor_samples(after, entrance)
	_expect(renderer._overview_build_count == builds, "retuning light does not rebuild terrain")
	_expect(measures.after.four > measures.before.four * 1.35, "four blocks in stays visibly brighter")
	_expect(measures.after.eight > measures.before.eight + .03, "eight blocks in retains entrance light")
	_expect(absf(measures.after.deep - measures.before.deep) < .01, "deep darkness floor is unchanged")
	_expect(absf(measures.after.outside - measures.before.outside) < .01, "outdoor lighting is unchanged")
	_expect(field.sky_at(entrance + Vector3i(4,2,2)) >= .4, "four blocks receives at least 40 percent skylight")
	_expect(field.sky_at(entrance + Vector3i(13,2,2)) == 0, "deep tunnel still needs placed lighting")
	await _check_actor(entrance, mining)
	var update_count: int = field.completed_updates
	slice._set_slice_y(entrance.y + 3)
	await _settle()
	_expect(field.completed_updates == update_count, "slice never rebuilds physical lighting")
	var report := {"failures":failures, "luminance":measures, "entrance":str(entrance), "lighting_max_frame_ms":field.max_step_usec/1000.0}
	FileAccess.open(REVIEW + "entrance_checks.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TUNNEL_ENTRANCE_TEST: ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_actor(entrance: Vector3i, mining: Node) -> void:
	var director = current_scene.get_node("DwarfDirector")
	_expect(director._spawn_one(entrance.x-2, entrance.z+1), "native director spawns a lit actor")
	if director._agents.is_empty(): return
	var actor = director._agents.back()
	actor.set_process(false)
	actor.position = Vector3(entrance) + Vector3(15.5,1,1.5)
	actor.apply_slice(entrance.y+4)
	await _settle()
	_check_actor_parameters(actor, 0.0, "deep air")
	# Preserve the player's observed case: the plan reveals a cell visually,
	# while its actual terrain is still solid. Move deliberately; no nav changes.
	var planned: Array[Vector3i] = []
	for z in range(4):
		for y in range(1,5): planned.append(entrance+Vector3i(18,y,z))
	mining._create_zone(planned)
	actor.position = Vector3(entrance) + Vector3(18.5,1,1.5)
	await _settle()
	_check_actor_parameters(actor, 0.0, "unmined solid")
	_expect(field.actor_sky_at(actor.position+Vector3.UP*1.5) == 0, "physical solid never returns slice daylight")
	var production: Shader = field.SHADER
	var legacy := Shader.new()
	legacy.code = production.code.replace("actor_sky_access >= 0.0 ? actor_sky_access : exposure(world_position+world_normal*0.04)", "exposure(world_position+world_normal*0.04)")
	for material: ShaderMaterial in field._material_cache.values(): material.shader = legacy
	var before := await _image("clipped_dwarf_before")
	for material: ShaderMaterial in field._material_cache.values(): material.shader = production
	var after := await _image("clipped_dwarf_after")
	measures.actor_pixel_drop = _actor_brightness_drop(before, after, actor)
	_expect(measures.actor_pixel_drop > .05, "native clipped actor loses erroneous daylight")
	# Newly equipped meshes inherit actor lighting. A released carried mesh
	# goes back to per-fragment world sampling instead of retaining that override.
	var cargo := MeshInstance3D.new()
	cargo.mesh = BoxMesh.new()
	cargo.material_override = StandardMaterial3D.new()
	actor.add_child(cargo)
	cargo.position = Vector3(0,1,1)
	await _settle()
	_expect(float(cargo.get_instance_shader_parameter("actor_sky_access")) == 0.0, "late attached mesh inherits actor darkness")
	cargo.reparent(current_scene)
	await _settle()
	_expect(float(cargo.get_instance_shader_parameter("actor_sky_access")) == -1.0, "detached cargo returns to world lighting")
	cargo.queue_free()
	actor.position = Vector3(entrance) + Vector3(-1.5,1,1.5)
	await _settle()
	_check_actor_parameters(actor, 1.0, "outdoors")
	actor.position = Vector3(entrance) + Vector3(4.5,1,1.5)
	await _settle()
	var near: float = field.actor_sky_at(actor.position+Vector3.UP*1.5)
	actor.position.x += .1
	await _settle()
	var moved: float = field.actor_sky_at(actor.position+Vector3.UP*1.5)
	_expect(moved < near and near-moved < .02, "moving actor fades smoothly across entrance cells")
	var texture := TextureRect.new()
	current_scene.add_child(texture)
	var portrait = load("res://scripts/ui/DwarfPortrait.gd")
	var viewport: SubViewport = portrait.create_viewport(texture)
	var model: Node3D = portrait.create_model(viewport, actor)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_expect(mesh.material_override is BaseMaterial3D, "portrait retains studio material")
	texture.queue_free()
	actor.queue_free()
	await _settle()
	_expect(field._actor_meshes.is_empty(), "freed actor releases lighting records")

func _check_actor_parameters(actor: Node3D, amount: float, label: String) -> void:
	var count := 0
	for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_active_material(0) is ShaderMaterial:
			count += 1
			_expect(is_equal_approx(float(mesh.get_instance_shader_parameter("actor_sky_access")), amount), label + " shades every actor part")
	_expect(count >= 6, "actor parts are bound " + label)

func _actor_brightness_drop(before: Image, after: Image, actor: Node3D) -> float:
	var center := Vector2i(camera.unproject_position(actor.position+Vector3.UP*1.7))
	var delta := 0.0
	for x in range(center.x-45, center.x+46):
		for y in range(center.y-60, center.y+61):
			delta = maxf(delta, before.get_pixel(x,y).get_luminance()-after.get_pixel(x,y).get_luminance())
	return delta

func _image(label: String) -> Image:
	for i in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(REVIEW+label+".png")
	return result

func _floor_samples(capture: Image, entrance: Vector3i) -> Dictionary:
	var values := {}
	for spec in [["outside",-1.5],["four",4.5],["eight",8.5],["deep",15.5]]:
		# Sample the visible back half of the floor, clear of the near cut wall.
		var point := Vector2i(camera.unproject_position(Vector3(entrance)+Vector3(spec[1],1.02,1.5)))
		var total := 0.0
		for x in range(-2,3):
			for y in range(-2,3): total += capture.get_pixel(point.x+x,point.y+y).get_luminance()
		values[spec[0]] = total/25.0
	return values

func _find_cliff() -> Vector3i:
	for z in range(256,768,4):
		for x in range(256,768):
			var y: int = generator.get_surface_y(x,z)
			if y < 8 or y > 105 or generator.get_surface_y(x+1,z) < y+7: continue
			var valid := true
			for dx in range(-2, 19):
				for dz in range(4):
					var col := Vector2i(x+dx,z+dz)
					if generator.lake_columns.has(col) or generator.tarn_columns.has(col): valid = false
					var height: int = generator.get_surface_y(col.x,col.y)
					if (dx > 0 and height < y+7) or (dx <= 0 and height != y): valid = false
			if valid: return Vector3i(x,y,z)
	return Vector3i(-1,-1,-1)
