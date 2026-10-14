extends Node3D

## Isolated studio. Furniture owners supply definitions/materials and the live
## dwarf/door components supply interaction poses; gameplay adapters test use.
const Assets = preload("FurniturePilotAssets.gd")
const DwarfArt = preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd")
const OUTPUT := "res://tmp/furniture_pilot_20261013/captures/"
var source: FurniturePlacementController
var groups: Array[Dictionary] = []
var camera: Camera3D
var environment: WorldEnvironment
var look: Environment
var sun: DirectionalLight3D
var caption: Label
var labels: Array[Label] = []
var mode := "Set"
var view := "Three-quarter"
var wood := "Oak"
var phase := 0.0
var playing := true
var capture := false
var ready_for_review := false
var _installed := {} # The production seated look-at code consults this.

func _ready() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	get_window().title="Deepdraft - Starter furniture art review"
	SaveManager.configure_storage_for_testing("user://furniture_pilot")
	WorldGenerator.world_seed=1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector"]:
		var service := get_tree().root.get_node_or_null(id)
		if service!=null: service.set_process(false)
	WorldClock.set_paused(false); WorldClock.set_speed(1)
	_stage()
	for i in 3: await get_tree().process_frame
	SkyController.set_process(false); WeatherManager.set_process(false)
	environment.environment=look
	sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.15; sun.light_color=Color("FFF1D8")
	for child in get_children():
		if child is DirectionalLight3D and child!=sun: child.queue_free()
	source=FurniturePlacementController.new(); source._load_defs()
	_build_groups()
	_ui()
	_set_mode("Set")
	ready_for_review=true
	print("FURNITURE_PILOT_READY: stool, hay bed, frameless door; live wood palettes and poses")
	if capture: _capture_all.call_deferred()

func _stage() -> void:
	environment=WorldEnvironment.new(); look=Environment.new()
	look.background_mode=Environment.BG_COLOR; look.background_color=Color("303E40")
	look.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color=Color("D5E3ED"); look.ambient_light_energy=.48
	look.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=look.duplicate(); add_child(environment)
	sun=DirectionalLight3D.new(); sun.shadow_enabled=true
	sun.directional_shadow_max_distance=60; add_child(sun)
	var ground := MeshInstance3D.new(); var box := BoxMesh.new()
	box.size=Vector3(80,1,80); ground.mesh=box; ground.position=Vector3(40,20.5,40)
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color("69835A"); mat.roughness=1
	ground.material_override=mat; add_child(ground)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true; add_child(camera)

func _build_groups() -> void:
	var factory := DwarfFactory.new()
	for i in 2:
		var group := Node3D.new(); add_child(group)
		var data := factory.generate(141,{})
		data.gender="male"
		var appearance := DwarfAppearanceData.new()
		appearance.hair_style="short_back"; appearance.beard_style="forked"
		appearance.eye_color="blue"; data.appearance=appearance
		var saved := DwarfArt.install(DwarfAssets)
		var dwarf := factory.spawn(data,1520+i)
		DwarfArt.restore(DwarfAssets,saved)
		group.add_child(dwarf); dwarf.set_process(false)
		dwarf.get_node("Readability").set_process(false)
		TaskManager.register_dwarf(dwarf)
		groups.append({"root":group,"dwarf":dwarf,"pieces":{},"hinges":null})
	_build_props()

func _build_props() -> void:
	for i in groups.size():
		var group: Dictionary=groups[i]
		for piece in group.pieces.values(): piece.node.free()
		group.pieces.clear()
		for part in Assets.PARTS:
			var key: String="base:furniture:"+part
			var definition: Dictionary=source.get_defs()[key]
			var model := source._instance_model(key,source._make_solid_material())
			group.root.add_child(model)
			CraftMaterials.apply_palette(model,definition,"base:material:"+("oak" if i==0 else wood.to_lower()))
			var piece := InstalledFurnitureComponent.new()
			piece.def=definition; piece.node=model
			group.pieces[part]=piece
			if part=="door":
				var hinges := preload("res://scripts/components/FurnitureDoorAnimation.gd").new()
				model.add_child(hinges); hinges.setup(model,definition.door_animation)
				hinges.set_process(false); group.hinges=hinges

func _ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var title := Label.new(); title.text="DEEPDRAFT  /  STARTER FURNITURE REVIEW"
	title.position=Vector2(32,22); title.add_theme_font_size_override("font_size",28); layer.add_child(title)
	var modes := HBoxContainer.new(); modes.position=Vector2(32,70); layer.add_child(modes)
	for value in ["Set","Stool","Bed","Door","Sit","Sleep","Open door"]:
		var b := Button.new(); b.text=value; b.pressed.connect(_set_mode.bind(value)); modes.add_child(b)
	var views := HBoxContainer.new(); views.position=Vector2(32,110); layer.add_child(views)
	for value in ["Front","Three-quarter","Side","Rear","Colony"]:
		var b := Button.new(); b.text=value; b.pressed.connect(_set_view.bind(value)); views.add_child(b)
	var pause := Button.new(); pause.text="Pause / play"
	pause.pressed.connect(func(): playing=not playing); views.add_child(pause)
	var woods := HBoxContainer.new(); woods.position=Vector2(32,150); layer.add_child(woods)
	for value in ["Oak","Pine","Juniper","Applewood"]:
		var b := Button.new(); b.text=value; b.pressed.connect(_set_wood.bind(value)); woods.add_child(b)
	caption=Label.new(); caption.position=Vector2(32,192)
	caption.add_theme_font_size_override("font_size",18); layer.add_child(caption)
	for value in ["OAK REFERENCE","SELECTED WOOD"]:
		var label := Label.new(); label.text=value; label.size=Vector2(280,36)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",22); layer.add_child(label); labels.append(label)

func _set_wood(value: String) -> void:
	wood=value; _build_props(); _layout(); _apply(0)

func _set_mode(value: String) -> void:
	mode=value; phase=0
	for group: Dictionary in groups:
		group.dwarf._rest_behavior.bed_rest.bed=null
		group.dwarf._rest_behavior._eyes(false)
		group.dwarf._idle_behavior.seat=null
	_layout(); _apply(0)

func _set_view(value: String) -> void:
	view=value; _layout(); _apply(0)

func _layout() -> void:
	var yaw: float={"Front":0.0,"Three-quarter":30.0,"Side":90.0,"Rear":150.0,"Colony":30.0}[view]
	var focus := "log_chair" if mode in ["Stool","Sit"] else "log_bed" if mode in ["Bed","Sleep"] else "door"
	var spacing := 9.0 if mode=="Set" else 4.0 if mode=="Stool" else 6.5
	for i in groups.size():
		var group: Dictionary=groups[i]
		group.root.position=Vector3(40+(i-.5)*spacing,21,40)
		group.root.rotation_degrees.y=yaw
		for part: String in group.pieces:
			var model: Node3D=group.pieces[part].node
			model.visible=mode=="Set" or part==focus
			model.position={"log_chair":Vector3(-2.1,0,2),"log_bed":Vector3(1.1,0,1),"door":Vector3(-1.8,0,-2)}[part] if mode=="Set" else Vector3.ZERO
		group.dwarf.visible=mode in ["Sit","Sleep","Open door"]
		group.dwarf.position=Vector3.ZERO
		group.dwarf.rotation.y=PI*.5 if mode=="Sleep" else 0.0
	var elevation := 52.0 if view=="Colony" else 26.0 if mode in ["Bed","Sleep","Set"] else 22.0
	camera.size=22 if mode=="Set" else 8 if mode=="Stool" else 14
	if view=="Colony": camera.size*=1.45
	var target := Vector3(40,21+(.4 if mode=="Stool" else 1.1 if mode in ["Bed","Sleep","Set"] else 1.8),40)
	camera.position=target+Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*28
	camera.look_at(target)
	caption.text=wood+" · "+{"Set":"Log stool, hay bed and frameless door", "Stool":"Flat cut seat at the existing height", "Bed":"Rough logs and loose hay · existing sleeping surface", "Door":"One frameless leaf · wooden battens, pegs and pull", "Sit":"Approved dwarf · production stool pose", "Sleep":"Approved dwarf · production bed pose", "Open door":"Production hinges respond to the approaching dwarf"}[mode]
	for i in labels.size():
		labels[i].position=camera.unproject_position(groups[i].root.position+Vector3(0,-.55,3 if mode=="Set" else 1.5))-Vector2(140,0)

func _apply(delta: float) -> void:
	for group: Dictionary in groups:
		var dwarf: DwarfAgent=group.dwarf
		dwarf._reset_part_offsets()
		match mode:
			"Sit":
				dwarf._idle_behavior.seat=group.pieces.log_chair
				dwarf._idle_behavior._furniture=self
				dwarf._idle_behavior._sitting_blend=1
				dwarf._idle_behavior.elapsed=phase*6
				dwarf._idle_behavior._pose()
			"Sleep":
				dwarf._rest_behavior.bed_rest.bed=group.pieces.log_bed
				dwarf._rest_behavior.pose="lying"; dwarf._rest_behavior.blend=1
				dwarf._rest_behavior.elapsed=phase*6; dwarf._rest_behavior._apply_pose()
			"Open door":
				dwarf.position.z=cos(phase*TAU)*4.0
				dwarf.rotation.y=PI if phase<.5 else 0.0
				dwarf._walk_cycle=fposmod(phase*8,1); dwarf._walk_bob(0)
				group.hinges._process(delta)
			_:
				group.hinges._angle=0.0; group.hinges._hold=0.0
				for hinge in group.hinges._hinges: hinge.rotation.y=0

func _process(delta: float) -> void:
	if not ready_for_review or capture or not playing: return
	phase=fposmod(phase+delta/(12.0 if mode=="Open door" else 6.0),1)
	_apply(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for material in ["Oak","Pine","Juniper","Applewood"]:
		_set_wood(material); _set_view("Three-quarter"); _set_mode("Set")
		await _capture("set_"+material.to_lower())
	_set_wood("Oak")
	for value in ["Stool","Bed","Door","Sit","Sleep"]:
		_set_mode(value)
		for angle in ["Three-quarter","Side","Colony"]:
			_set_view(angle); phase=.55; _apply(0)
			await _capture(value.to_lower()+"_"+angle.to_snake_case())
	_set_mode("Open door"); _set_view("Three-quarter")
	for group: Dictionary in groups:
		assert(group.dwarf._head.get_node("MeshEyes").visible,"leaving sleep reopens eyes")
	for tick in 241:
		phase=float(tick)/240.0; _apply(.05)
		if tick in [0,40,60,100,120,160,180,220,240]: await _capture("door_motion_%03d"%tick)
	print("FURNITURE_PILOT_CAPTURE_OK: 28 native comparisons")
	get_tree().quit()

func _capture(id: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT+id+".png")

func _exit_tree() -> void:
	if is_instance_valid(source): source.free()
