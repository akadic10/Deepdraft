extends Node3D

## Native production art review. Poses call the production DeerAgent rig.
const Assets = preload("AnimalPilotAssets.gd")
const OUTPUT := "res://tmp/animal_pilot_20261013/captures/"
var wildlife: Node3D
var actors: Array[Node3D] = []
var reference: DwarfAgent
var camera: Camera3D
var environment: WorldEnvironment
var look: Environment
var sun: DirectionalLight3D
var caption: Label
var labels: Array[Label] = []
var mode := "Stand"
var view := "Three-quarter"
var playing := true
var phase := 0.0
var capture := false
var ready_for_review := false

func _ready() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	get_window().title="Deepdraft - Deer art review"
	SaveManager.configure_storage_for_testing("user://animal_pilot")
	WorldGenerator.world_seed=1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector"]:
		var singleton := get_tree().root.get_node_or_null(id)
		if singleton!=null: singleton.set_process(false)
	WorldClock.set_paused(true)
	_stage()
	for i in 3: await get_tree().process_frame
	SkyController.set_process(false); WeatherManager.set_process(false)
	environment.environment=look
	sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.15; sun.light_color=Color("FFF1D8")
	for child in get_children():
		if child is DirectionalLight3D and child!=sun: child.queue_free()
	_build_actors()
	_ui()
	_set_view("Three-quarter")
	_set_mode("Stand")
	ready_for_review=true
	print("ANIMAL_PILOT_READY: deer, live poses, approved dwarf scale reference")
	if capture: _capture_all.call_deferred()

func _stage() -> void:
	environment=WorldEnvironment.new()
	look=Environment.new()
	look.background_mode=Environment.BG_COLOR
	look.background_color=Color("303E40")
	look.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color=Color("D5E3ED")
	look.ambient_light_energy=.48
	look.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=look.duplicate()
	add_child(environment)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.shadow_enabled=true; sun.directional_shadow_max_distance=60
	add_child(sun)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size=Vector3(80,1,80)
	ground.mesh=box; ground.position=Vector3(40,20.5,40)
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color("69835A"); mat.roughness=1
	ground.material_override=mat; add_child(ground)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true; add_child(camera)
	# A real supported strip keeps the study's species/navigation contract concrete.
	for cx in [1,2,3]:
		for cz in [1,2,3]: WorldData.get_chunk(cx,1,cz)
	var grass := BlockRegistry.get_id("base:terrain:surface:grass_01")
	for x in range(24,58):
		for z in range(30,50): WorldData.set_block(x,20,z,grass)

func _build_actors() -> void:
	wildlife=load("res://scripts/systems/WildlifeManager.gd").new()
	add_child(wildlife); wildlife.set_process(false)
	var current_models: Dictionary=wildlife._deer_models
	actors.append(wildlife.add_deer("deer:study:current",Vector3i(36,21,40),151,"study:current"))
	wildlife._deer_models=Assets.models()
	actors.append(wildlife.add_deer("deer:study:pilot",Vector3i(42,21,40),151,"study:pilot"))
	wildlife._deer_models=current_models
	var factory := DwarfFactory.new()
	var data := factory.generate(141,{})
	data.gender="male"
	var appearance := DwarfAppearanceData.new()
	appearance.hair_style="short_back"; appearance.beard_style="forked"
	appearance.eye_color="blue"
	data.appearance=appearance
	var dwarf_assets := preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd")
	var saved: Dictionary=dwarf_assets.install(DwarfAssets)
	reference=factory.spawn(data,951)
	dwarf_assets.restore(DwarfAssets,saved)
	add_child(reference); reference.position=Vector3(40,21,41)
	reference.set_process(false); reference.get_node("Readability").set_process(false)
	reference.hide()

func _ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var title := Label.new(); title.text="DEEPDRAFT  /  DEER ART REVIEW"
	title.position=Vector2(32,22); title.add_theme_font_size_override("font_size",28); layer.add_child(title)
	var modes := HBoxContainer.new(); modes.position=Vector2(32,70); layer.add_child(modes)
	for value in ["Stand","Walk","Flee","Graze","Rest"]:
		var button := Button.new(); button.text=value
		button.pressed.connect(_set_mode.bind(value)); modes.add_child(button)
	var views := HBoxContainer.new(); views.position=Vector2(32,110); layer.add_child(views)
	for value in ["Front","Three-quarter","Side","Rear","Colony","Dwarf scale"]:
		var button := Button.new(); button.text=value
		button.pressed.connect(_set_view.bind(value)); views.add_child(button)
	var pause := Button.new(); pause.text="Pause / play"
	pause.pressed.connect(func(): playing=not playing); views.add_child(pause)
	caption=Label.new(); caption.position=Vector2(32,157)
	caption.add_theme_font_size_override("font_size",18); layer.add_child(caption)
	for value in ["VIEW A","OPPOSITE VIEW"]:
		var label := Label.new(); label.text=value; label.size=Vector2(280,36)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",22); layer.add_child(label); labels.append(label)

func _set_mode(value: String) -> void:
	mode=value; phase=0
	caption.text={"Stand":"One deer · existing scale, pivots and species settings", "Walk":"Production walking pose · four independent legs", "Flee":"Production escape cadence · unchanged speed", "Graze":"Production neck and head joints · muzzle and antler clearance", "Rest":"Production folded rest · full-size torso"}[mode]
	_apply()

func _set_view(value: String) -> void:
	view=value
	var yaw := 180.0
	var elevation := 22.0
	match view:
		"Three-quarter","Dwarf scale": yaw=145
		"Side": yaw=90
		"Rear": yaw=35
		"Colony": yaw=145; elevation=52
	for i in actors.size(): actors[i].rotation_degrees.y=yaw+180*i
	reference.visible=view=="Dwarf scale"
	reference.rotation_degrees.y=30
	camera.size=24.0 if view=="Colony" else 12.0
	var target := Vector3(40,22.65,41)
	camera.position=target+Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*26
	camera.look_at(target)
	_labels()

func _apply() -> void:
	for actor in actors:
		actor.activity={"Stand":"Idle","Walk":"Wandering","Flee":"Fleeing","Graze":"Grazing","Rest":"Sleeping"}[mode]
		actor.hop_progress=phase if mode in ["Walk","Flee"] else 1.0
		actor.pose_time=phase*5.0
		actor._pose()
	_labels()

func _labels() -> void:
	for i in labels.size():
		labels[i].position=camera.unproject_position(actors[i].position+Vector3(0,-.65,1))-Vector2(140,0)

func _process(delta: float) -> void:
	if not ready_for_review or capture: return
	if playing:
		var duration := float(wildlife.deer_definition.navigation.flee_hop_seconds if mode=="Flee" else wildlife.deer_definition.navigation.hop_seconds) if mode in ["Walk","Flee"] else 5.0
		phase=fposmod(phase+delta/duration,1)
	_apply()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for value in ["Front","Three-quarter","Side","Rear","Colony","Dwarf scale"]:
		_set_mode("Stand"); _set_view(value)
		await _capture(value.to_snake_case())
	for value in ["Walk","Flee","Graze","Rest"]:
		_set_mode(value)
		for angle in ["Three-quarter","Side"]:
			_set_view(angle)
			for time in [.0,.25,.75]:
				phase=time; _apply()
				await _capture(value.to_lower()+"_"+angle.to_snake_case()+"_%02d"%roundi(time*100))
	print("ANIMAL_PILOT_CAPTURE_OK: 30 native production views")
	get_tree().quit()

func _capture(id: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT+id+".png")
