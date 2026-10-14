extends Node3D

## Native art review using actual DwarfAgent parts, tints and procedural rigs.
const OUTPUT := "res://tmp/dwarf_pilot_20261013/captures/"
var actors: Array[DwarfAgent] = []
var props: Array[Node3D] = []
var seats: Array[InstalledFurnitureComponent] = []
var beds: Array[InstalledFurnitureComponent] = []
var cargo: Array[Node3D] = []
var camera: Camera3D
var title: Label
var caption: Label
var labels: Array[Label] = []
var pose := "Idle"
var view := "Three-quarter"
var playing := true
var phase := 0.0
var captures := false
var review_environment: WorldEnvironment
var review_sun: DirectionalLight3D
var review_look: Environment

func _ready() -> void:
	captures = "--capture" in OS.get_cmdline_user_args()
	get_window().title = "Deepdraft - Dwarf art review"
	SaveManager.configure_storage_for_testing("user://dwarf_pilot")
	WorldGenerator.world_seed=1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector"]:
		var singleton := get_tree().root.get_node_or_null(id)
		if singleton != null: singleton.set_process(false)
	WorldClock.set_paused(true)
	_stage()
	# Deferred sky startup binds once even when processing is disabled. Restore
	# the paired study lighting afterwards, including color-sourced ambient.
	for j in 3: await get_tree().process_frame
	SkyController.set_process(false)
	WeatherManager.set_process(false)
	review_environment.environment=review_look
	review_sun.rotation_degrees=Vector3(-48,-35,0)
	review_sun.light_energy=1.15
	review_sun.light_color=Color("FFF1D8")
	for light in get_children():
		if light is DirectionalLight3D and light!=review_sun: light.queue_free()
	_actors()
	_ui()
	_set_view("Three-quarter")
	_set_pose("Idle")
	print("DWARF_PILOT_READY: native comparison, live animation rigs, isolated profile")
	if captures: _capture_all.call_deferred()

func _stage() -> void:
	var world_environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("303E40")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("D5E3ED")
	env.ambient_light_energy = .48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = env
	review_environment=world_environment
	review_look=env.duplicate()
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("FFF1D8")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)
	review_sun=sun
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(80,1,80)
	ground.mesh = box
	ground.position = Vector3(40,-.5,40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("69835A")
	mat.roughness = 1
	ground.material_override = mat
	add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)

func _actors() -> void:
	var factory := DwarfFactory.new()
	var owner := FurniturePlacementController.new()
	owner._load_defs()
	var definitions := owner.get_defs().duplicate(true)
	owner.free()
	for i in range(2):
		var data := factory.generate(141,{})
		data.gender = "male"
		var a := DwarfAppearanceData.new()
		a.age_tier = "adult"; a.gender = "male"; a.skin_tone = "medium"
		a.hair_color = "brown"; a.eye_color = "blue"
		a.hair_style = "short_back"; a.beard_style = "forked"; a.eyebrow_style = "thick_flat"
		data.appearance = a
		if i==1: a.hair_style="braided_back"; a.beard_style="full_long"
		var actor := factory.spawn(data,900+i)
		add_child(actor)
		actor.position = Vector3(37.5+i*5,0,40)
		actor.set_process(false)
		actor.get_node("Readability").set_process(false)
		actors.append(actor)
		# Props use the existing definitions and models; they are study instances.
		var chair := InstalledFurnitureComponent.new()
		chair.def = definitions["base:furniture:wooden_chair"]
		chair.node = load(chair.def.model).instantiate()
		add_child(chair.node)
		chair.node.position = actor.position
		seats.append(chair); props.append(chair.node)
		var bed := InstalledFurnitureComponent.new()
		bed.def = definitions["base:furniture:log_bed"]
		bed.node = load(bed.def.model).instantiate()
		add_child(bed.node)
		bed.node.position = actor.position
		beds.append(bed); props.append(bed.node)
		var item := load("res://assets/models/items/stone/rough_stone.glb") as PackedScene
		var node := item.instantiate() as Node3D
		actor.add_child(node)
		cargo.append(node)
		actor._carry_pose._material(node)
		for prop in [chair.node,bed.node]: actor._carry_pose._material(prop)

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	title = Label.new()
	title.text = "DEEPDRAFT  /  DWARF ART REVIEW"
	title.position = Vector2(32,22)
	title.add_theme_font_size_override("font_size",28)
	layer.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(32,70)
	layer.add_child(buttons)
	for text in ["Idle","Walk","Mine","Fell","Carry","Sit","Sleep"]:
		var b := Button.new(); b.text = text
		b.pressed.connect(_set_pose.bind(text)); buttons.add_child(b)
	var views := HBoxContainer.new()
	views.position = Vector2(32,110); layer.add_child(views)
	for text in ["Front","Three-quarter","Side","Rear","Colony"]:
		var b := Button.new(); b.text = text
		b.pressed.connect(_set_view.bind(text)); views.add_child(b)
	var pause := Button.new(); pause.text = "Pause / play"
	pause.pressed.connect(func(): playing=not playing); views.add_child(pause)
	caption = Label.new(); caption.position = Vector2(32,157)
	caption.add_theme_font_size_override("font_size",18); layer.add_child(caption)
	for text in ["SWEPT / FORKED", "BRAIDED / FULL BEARD"]:
		var label := Label.new(); label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",22)
		layer.add_child(label); labels.append(label)

func _set_view(value: String) -> void:
	view = value
	var yaw := 0.0
	var elevation := 22.0
	match view:
		"Three-quarter": yaw = 30
		"Side": yaw = 90
		"Rear": yaw = 150
		"Colony": yaw = 30; elevation = 52
	for i in actors.size():
		actors[i].rotation_degrees.y = yaw
		seats[i].node.rotation_degrees.y = yaw
		beds[i].node.rotation_degrees.y = yaw-90
	camera.size = 23.0 if view=="Colony" else 10.8
	var target := Vector3(40,1.5,40)
	camera.position = target+Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*24
	camera.look_at(target)
	_apply()

func _set_pose(value: String) -> void:
	pose=value; phase=0
	for actor in actors:
		actor._rest_behavior.bed_rest.bed = null
		actor._rest_behavior._eyes(false)
		actor._carried_entries.clear()
		actor._reset_part_offsets()
	for prop in props: prop.hide()
	for node in cargo: node.hide()
	caption.text = {
		"Idle":"Two adult appearances · common scale and lighting",
		"Walk":"Live walking rig · planted boots and floating hands",
		"Mine":"Live mining rig · two-handed pick attachment",
		"Fell":"Live felling rig · mirrored grip and swing",
		"Carry":"Live carry rig · rough stone at its actual item size",
		"Sit":"Existing wooden chair · unchanged seat offsets",
		"Sleep":"Existing log bed · live rest rig and closed eyes"
	}.get(pose,"")
	_apply()

func _process(delta: float) -> void:
	if captures: return
	if playing: phase=fposmod(phase+delta*.55,1.0)
	_apply()
	for i in labels.size():
		labels[i].position = camera.unproject_position(actors[i].position+Vector3(0,-.35,0))-Vector2(130,0)
		labels[i].size=Vector2(260,35)

func _apply() -> void:
	for i in actors.size():
		var a := actors[i]
		a._reset_part_offsets()
		match pose:
			"Walk": a._walk_cycle=phase; a._walk_bob(0)
			"Mine": a._mining_pose.apply(phase,Vector3(0,1.6,1.4))
			"Fell": a._felling_pose.apply(phase,Vector3(0,1.2,1.4))
			"Carry":
				cargo[i].show()
				a._carry_pose.hold([[cargo[i],"base:resources:stone:rough_stone"]],sin(phase*TAU)*.02)
			"Sit":
				seats[i].node.show()
				a._idle_behavior.seat=seats[i]
				# _pose only queries installed focus props, so an empty study owner suffices.
				a._idle_behavior._furniture=self
				a._idle_behavior._sitting_blend=1
				a._idle_behavior.elapsed=phase*2
				a._idle_behavior._pose()
			"Sleep":
				beds[i].node.show()
				a._rest_behavior.bed_rest.bed=beds[i]
				a._rest_behavior.pose="lying"; a._rest_behavior.blend=1
				a._rest_behavior.elapsed=phase*4
				a._rest_behavior._apply_pose()

var _installed := {} # Only the existing seat look-at code reads this in the study.

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for v in ["Front","Three-quarter","Side","Rear","Colony"]:
		_set_pose("Idle"); _set_view(v)
		await _capture(v.to_snake_case())
	_set_view("Three-quarter")
	for p in ["Walk","Mine","Fell","Carry","Sit","Sleep"]:
		_set_pose(p)
		for f in [.2,.55,.93]:
			phase=f; _apply()
			await _capture(p.to_lower()+"_%02d" % roundi(f*100))
	_set_pose("Idle")
	await _capture_portraits()
	print("DWARF_PILOT_CAPTURE_OK: 23 native comparisons and 2 production portraits")
	get_tree().quit()

func _capture_portraits() -> void:
	var portrait := preload("res://scripts/ui/DwarfPortrait.gd")
	for i in actors.size():
		var texture := TextureRect.new()
		texture.visible=false
		add_child(texture)
		var viewport: SubViewport = portrait.create_viewport(texture)
		portrait.create_model(viewport,actors[i])
		for j in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(OUTPUT+("current" if i==0 else "pilot")+"_portrait.png")
		texture.queue_free()

func _capture(id: String) -> void:
	for i in labels.size():
		labels[i].position = camera.unproject_position(actors[i].position+Vector3(0,-.35,0))-Vector2(130,0)
		labels[i].size=Vector2(260,35)
	for j in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT+id+".png")
