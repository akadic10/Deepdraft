extends "res://tools/TunnelLightingStudy.gd"

## Native regression using real WorldData edits and the shipped lighting field.
## The study supplies only geometry/assets/camera; its fake light map is unused.
const REVIEW := "res://tmp/water_review/cave_lighting/"
const ORIGIN := Vector3(32,21,32)
var field
var world
var blocks
var mined: Array[Vector3i] = []


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Underground lighting test timed out"); quit(1))
	if not "/underground_lighting_review/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Lighting test requires isolated APPDATA under tmp/underground_lighting_review")
		quit(1)
		return
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("WorldGenerator").world_seed = 1234
	world = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(16,80):
		for z in range(16,80): world.set_block(x,20,z,stone)
	for x in range(32,52):
		for z in range(32,54):
			for y in range(21,31): world.set_block(x,y,z,stone)
	root.size = Vector2i(1400,900)
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	stage.position = ORIGIN
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	environment.environment = env
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55,30,0)
	sun.shadow_enabled = true
	TerrainLight.configure_sun(sun)
	stage.add_child(sun)
	field = load("res://scripts/components/UndergroundLighting.gd").new()
	stage.add_child(field)
	_build_cells()
	for cell: Vector2i in carved:
		for y in range(21,25):
			var pos := Vector3i(cell.x+32,y,cell.y+32)
			mined.append(pos)
			world.set_block(pos.x,pos.y,pos.z,blocks.AIR_ID)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,52)) > .5,"entrance receives sky light")
	_expect(field.sky_at(Vector3i(40,22,40)) == 0,"roofed deep tunnel beyond entrance reach has no daylight")
	_expect(field.sky_at(Vector3i(40,22,48)) < field.sky_at(Vector3i(40,22,51)),"entrance falloff follows air distance")
	var entrance_before: float = field.sky_at(Vector3i(40,22,49))
	for x in range(39,43):
		for y in range(21,25): world.set_block(x,y,51,stone)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,49)) == 0,"a solid barrier stops entrance daylight")
	for x in range(39,43):
		for y in range(21,25): world.set_block(x,y,51,blocks.AIR_ID)
	await _drain()
	_expect(is_equal_approx(field.sky_at(Vector3i(40,22,49)),entrance_before),"reopening the passage restores the same falloff")
	# Installed doors are walkable air, but must stop the skylight flood just
	# like the room-sealing boundary. No terrain edit accompanies this change.
	var rooms = root.get_node("RoomManager")
	var first_door: Array[Vector3i] = [Vector3i(39,20,51), Vector3i(40,20,51)]
	var second_door: Array[Vector3i] = [Vector3i(41,20,51), Vector3i(42,20,51)]
	rooms.on_furniture_changed(rooms.DOOR_KEY, first_door, {}, true)
	rooms.on_furniture_changed(rooms.DOOR_KEY, second_door, {}, true)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,49)) == 0, "installed doors block daylight without blocking navigation")
	var restored_field = load("res://scripts/components/UndergroundLighting.gd").new()
	stage.add_child(restored_field)
	while restored_field.is_updating(): await process_frame
	_expect(restored_field.sky_at(Vector3i(40,22,49)) == 0, "new lighting owner reads existing door boundaries")
	restored_field.queue_free()
	rooms.on_furniture_changed(rooms.DOOR_KEY, first_door, {}, false)
	await process_frame
	rooms.on_furniture_changed(rooms.DOOR_KEY, first_door, {}, true)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,49)) == 0, "door replacement during an update settles to closed")
	rooms.on_furniture_changed(rooms.DOOR_KEY, first_door, {}, false)
	rooms.on_furniture_changed(rooms.DOOR_KEY, second_door, {}, false)
	await _drain()
	_expect(is_equal_approx(field.sky_at(Vector3i(40,22,49)),entrance_before), "uninstall restores daylight from the entrance")
	# Source edits while a previous update is running must settle to current truth.
	var skylight := Vector3i(40,25,44)
	for y in range(25,31): world.set_block(40,y,44,blocks.AIR_ID)
	await process_frame
	world.set_block(skylight.x,skylight.y,skylight.z,stone)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,44)) < .04,"a replacement roof removes direct skylight, including during an update")
	world.set_block(skylight.x,skylight.y,skylight.z,blocks.AIR_ID)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,44)) == 1,"mining a skylight lights the air column below")
	world.set_block(skylight.x,skylight.y,skylight.z,stone)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,44)) < .04,"closing skylight restores the weak entrance light")
	# Restore the original solid roof for the visual reference.
	for y in range(25,31): world.set_block(40,y,44,stone)
	# An upper open gallery must not light the covered tunnel underneath it.
	for y in range(27,31): world.set_block(40,y,44,blocks.AIR_ID)
	await _drain()
	_expect(field.sky_at(Vector3i(40,28,44)) == 1 and field.sky_at(Vector3i(40,22,44)) < .04,"stacked floors have independent roof cover")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.far = 200
	camera.position = Vector3(35,44,52)
	stage.add_child(camera)
	camera.look_at(ORIGIN+Vector3(9,0,12))
	camera.current = true
	_build_terrain()
	_build_props()
	_build_labels()
	_expect(dwarf_count == 3,"all reference dwarves created")
	for i in range(6): await process_frame
	root.get_node("SkyController")._update(12.0)
	env.fog_enabled = false
	var measurements := {}
	for mode in ["current","unlit","torches"]:
		_set_mode(mode)
		subtitle.text = "Live lighting field · real terrain edits · roof hidden for inspection"
		for i in range(10): await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png(REVIEW+mode+".png")
		measurements[mode] = {
			"outside":_luminance(capture,ORIGIN+Vector3(4.5,.02,25.5)),
			"deep":_luminance(capture,ORIGIN+Vector3(8,.02,8.5)),
			"chamber":_luminance(capture,ORIGIN+Vector3(9,.02,3.5)),
		}
	_expect(absf(measurements.current.outside-measurements.unlit.outside) < .025,"outdoor lighting retained")
	_expect(measurements.unlit.deep < measurements.current.deep*.4,"live shader darkens covered terrain")
	_expect(measurements.unlit.deep < .04,"unlit rock retains only a faint visibility floor")
	_expect(measurements.torches.deep > measurements.unlit.deep*1.5,"existing torch lights covered terrain")
	_expect(measurements.torches.chamber > measurements.unlit.chamber*1.5,"chamber torch retains local light")
	root.get_node("SkyController")._update(0.0)
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(REVIEW+"night.png")
	# Save data contains removals, never a lighting cache. Replaying exactly
	# those removals into a fresh field must derive the same covered exposure.
	var reference: float = field.sky_at(Vector3i(40,22,44))
	field.queue_free()
	await process_frame
	for pos in mined: world.set_block(pos.x,pos.y,pos.z,stone)
	field = load("res://scripts/components/UndergroundLighting.gd").new()
	stage.add_child(field)
	for pos in mined: world.set_block(pos.x,pos.y,pos.z,blocks.AIR_ID)
	await _drain()
	_expect(field.sky_at(Vector3i(40,22,44)) == reference,"replayed mining derives lighting without saved cache")
	var report := {"failures":failures,"measurements":measurements,"max_frame_work_ms":field.max_step_usec/1000.0,"allocated_tiles":field._slots.size()}
	var file := FileAccess.open(REVIEW+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("UNDERGROUND_LIGHTING_TEST: ",JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _drain() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while field.is_updating() and Time.get_ticks_msec() < deadline: await process_frame
	_expect(not field.is_updating(),"lighting update finishes within budget")


func _material(mesh: MeshInstance3D, color: Color, _exposure: float, vertex_color: bool = false) -> void:
	var source := StandardMaterial3D.new()
	source.albedo_color = color
	source.roughness = 1.0
	source.vertex_color_use_as_albedo = vertex_color
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	var material: Material = field.make_material(source)
	mesh.material_override = material
	records.append({"mesh":mesh,"current":source,"proposed":material})
