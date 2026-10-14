extends Node3D

## A posed scale lab. Current assets and terrain palettes; fixed studio lighting.
## Trial transforms stay on these instances. Never loaded by the shipping scene.
const OUT := "res://tmp/scale_study_20261013/"
const Terrain = preload("ScaleTerrain.gd")
const REFERENCE := "res://tools/scale_study/settlement_reference.png"
var terrain: Node3D
var terrain_material: ShaderMaterial
var floor_material: StandardMaterial3D
var source: FurniturePlacementController
var wildlife: Node3D
var settlement: Node3D
var lineup: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var look: Environment
var caption: Label
var detail: Label
var footer: Label
var reference_panel: PanelContainer
var buttons: Dictionary = {}
var labels: Array[Dictionary] = []
var specimens: Array[Dictionary] = []
var dwarf_trial := false
var animal_trial := false
var tree_trial := false
var compact := false
var framing := "Wide"
var view := "Settlement"
var pose := "Stand"
var time_of_day := "Day"
var playing := false
var phase := 0.0
var capture_mode := false
var ready_for_review := false
var target := Vector3(48, 26, 47)
var yaw := -28.0
var pitch := 40.0
var zoom := 49.0
var orbiting := false
var checks := 0
var failures: Array[String] = []
var report := {"measurements": {}, "captures": {}, "checks": 0, "failures": []}


func _ready() -> void:
	get_window().title = "Deepdraft - Visual scale study"
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	SaveManager.configure_storage_for_testing("user://scale_study")
	WorldGenerator.world_seed = 1234
	for id in ["SaveManager", "TaskManager", "WorldClock", "SkyController", "WeatherManager", "RoomManager", "StockpileManager", "WorldEventDirector"]:
		var service := get_tree().root.get_node_or_null(id)
		if service!=null: service.set_process(false)
	WorldClock.restore_state({"year": 1, "season": "summer", "day": 1, "hour": 12.0, "speed": 1, "paused": true})
	_build_stage()
	for i in 3: await get_tree().process_frame
	# Autoload startup can bind lights once even with its process loop disabled.
	for light in get_children():
		if light is DirectionalLight3D and light != sun: light.queue_free()
	environment.environment = look
	_set_light("Day")
	source = FurniturePlacementController.new()
	source._load_defs()
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	add_child(wildlife)
	wildlife.set_process(false)
	_build_settlement()
	_build_lineup()
	_build_ui()
	_measure()
	_select_view("Lineup")
	ready_for_review = true
	print("SCALE_STUDY_READY: current assets, unit ruler, rooms, matched camera and independent scale trials")
	if capture_mode: _capture_all.call_deferred()


func _build_stage() -> void:
	environment = WorldEnvironment.new()
	look = Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color("293A3B")
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("D5E3ED")
	look.ambient_light_energy = .5
	look.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = look.duplicate()
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	preload("res://scripts/components/TerrainLighting.gd").configure_sun(sun)
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 250
	add_child(camera)
	camera.make_current()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.create_world()
	terrain.excavate_rooms()
	terrain.slice_y = 24
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("review_terrain.gdshader")
	BlockRegistry.configure_terrain_material(terrain_material)
	floor_material = StandardMaterial3D.new()
	floor_material.vertex_color_use_as_albedo = true
	floor_material.roughness = 1
	_rebuild_terrain()
	settlement = Node3D.new()
	add_child(settlement)
	lineup = Node3D.new()
	add_child(lineup)
	_box(lineup, Vector3(116,20.5,40), Vector3(37,1,11), Color("667563"))
	# A measured world-unit grid under the line-up, independent of model detail.
	for x in range(98,135):
		_box(lineup, Vector3(x,21.004,40), Vector3(.015,.006,11), Color("47574F"))
	for z in range(35,46):
		_box(lineup, Vector3(116,21.004,z), Vector3(37,.006,.015), Color("47574F"))


func _rebuild_terrain() -> void:
	terrain.rebuild(terrain_material, floor_material, false, false, "shader")


func _build_settlement() -> void:
	for spec in [["log_bed",Vector3(38.5,21,39.5)], ["crude_workbench",Vector3(50,21,40)],
		["log_chair",Vector3(40,21,42)], ["wooden_table",Vector3(51.5,21,41.5)],
		["barrel",Vector3(37.7,21,41.5)], ["barrel",Vector3(52.5,21,39)],
		["campfire",Vector3(45,21,49)], ["door",Vector3(40,21,44.5)],
		["wooden_torch",Vector3(41,22.15,36.08)], ["wooden_torch",Vector3(51,22.15,36.08)]]:
		_prop(settlement, spec[0], spec[1])
	for spec in [[Vector3(42,21,41.5),0], [Vector3(50.7,21,44),1], [Vector3(44,21,51),2]]:
		_dwarf(settlement, spec[0], spec[1])
	_animal(settlement,"deer",Vector3(56,21,53))
	_animal(settlement,"wolf",Vector3(53,21,55))
	_animal(settlement,"rabbit",Vector3(43,21,53))
	_animal(settlement,"duck",Vector3(46,21,54))
	for spec in [["pine/pine_mature",Vector3(33,21,51)], ["oak/oak_mature",Vector3(61,21,43)],
		["pine/pine_sapling",Vector3(59,21,58)], ["oak/oak_sapling",Vector3(37,21,58)]]:
		var tree := _model(settlement, "res://assets/models/flora/trees/"+spec[0]+".glb", spec[1])
		specimens.append({"node":tree,"family":"trees","id":spec[0],"stage":"settlement"})
	for at in [Vector3(34,21,57),Vector3(55,21,59),Vector3(39,21,53)]:
		_model(settlement,"res://assets/models/flora/bushes/wild_strawberry/wild_strawberry_summer.glb",at)


func _build_lineup() -> void:
	for i in 4:
		_box(lineup,Vector3(100.5,21.5+i,39),Vector3(1,1,1),Color("89939C") if i%2==0 else Color("747F89"))
	_label_at("4 blocks",Vector3(100.5,20.1,42),lineup)
	_dwarf(lineup,Vector3(105,21,40),0)
	_dwarf(lineup,Vector3(108,21,40),1)
	for spec in [["deer",113], ["wolf",118], ["rabbit",122], ["duck",125]]:
		_animal(lineup,spec[0],Vector3(spec[1],21,40))
	_prop(lineup,"door",Vector3(130,21,40))
	_label_at("2-wide door",Vector3(130,20.1,42),lineup)
	# Height ticks do not depend on the art's voxel density or import scale.
	for y in range(0,5):
		_box(lineup,Vector3(115,21+y,37),Vector3(33,.035,.025),Color("97ABA6"))
		_label_at(str(y),Vector3(98,21+y,37),lineup,true)


func _dwarf(parent: Node3D, at: Vector3, variant: int) -> Node3D:
	var factory := DwarfFactory.new()
	var data := factory.generate(162+variant,{})
	data.gender = "female" if variant==1 else "male"
	var appearance := DwarfAppearanceData.new()
	appearance.gender=data.gender
	appearance.hair_style="twin_braids" if variant==1 else "short_back"
	appearance.beard_style="" if variant==1 else "forked"
	appearance.eye_color="blue"
	data.appearance=appearance
	var dwarf := factory.spawn(data,1620+specimens.size())
	parent.add_child(dwarf)
	dwarf.position=at
	dwarf.rotation_degrees.y=25
	dwarf.set_process(false)
	dwarf.get_node("Readability").set_process(false)
	dwarf._reset_part_offsets()
	var id := "Dwarf (braids)" if variant==1 else "Dwarf (beard)"
	specimens.append({"node":dwarf,"family":"dwarves","id":id,"stage":"lineup" if parent==lineup else "settlement","original_position":at})
	if parent==lineup: _label_at("Dwarf B" if variant==1 else "Dwarf A",at+Vector3(0,-.9,2),parent)
	return dwarf


func _animal(parent: Node3D, species: String, at: Vector3) -> Node3D:
	var actor: Node3D=wildlife.call("add_"+species,"scale:"+str(specimens.size()),Vector3i(at),162)
	actor.reparent(parent)
	actor.position=at
	actor.rotation_degrees.y=115
	actor.visible=true
	actor.activity="Idle"
	actor.hop_progress=1.0
	actor.pose_time=0.0
	actor._pose()
	specimens.append({"node":actor,"family":"animals","id":species.capitalize(),"stage":"lineup" if parent==lineup else "settlement"})
	if parent==lineup: _label_at(species.capitalize(),at+Vector3(0,-.9,2),parent)
	return actor


func _prop(parent: Node3D, id: String, at: Vector3) -> Node3D:
	var key := "base:furniture:"+id
	var def: Dictionary=source.get_defs()[key]
	var node: Node3D=source._instance_model(key,source._make_solid_material())
	parent.add_child(node)
	node.position=at
	CraftMaterials.apply_palette(node,def,"base:material:oak")
	preload("res://scripts/components/FurnitureLighting.gd").attach(node,def)
	for animation in node.find_children("FlameAnimation","Node",true,false): animation.set_process(false)
	specimens.append({"node":node,"family":"furniture","id":id,"stage":"lineup" if parent==lineup else "settlement","original_position":at})
	return node


func _model(parent: Node3D, path: String, at: Vector3) -> Node3D:
	var node: Node3D=load(path).instantiate()
	parent.add_child(node)
	node.position=at
	for mesh in node.find_children("*","MeshInstance3D",true,false): mesh.material_override=floor_material
	return node


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=size
	mesh.mesh=box
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=1
	mesh.material_override=mat
	mesh.position=at
	parent.add_child(mesh)


func _label_at(text: String, at: Vector3, parent: Node3D, small := false) -> void:
	labels.append({"text":text,"at":at,"parent":parent,"small":small})


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=18; top.offset_top=14; top.offset_right=-18
	top.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	layer.add_child(top)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	top.add_child(column)
	var title := Label.new()
	title.text="DEEPDRAFT  /  VISUAL SCALE STUDY"
	UITheme.apply_title(title,23)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for value in ["Lineup","Rooms","Settlement"]: _button(value,func(): _select_view(value),row)
	_button("A · Current",func(): _preset("A"),row)
	_button("B · Framing",func(): _preset("B"),row)
	_button("C · Tree trial",func(): _preset("C"),row)
	_button("Concept",func(): reference_panel.visible=not reference_panel.visible,row)
	var trials := HBoxContainer.new()
	column.add_child(trials)
	_button("Dwarves",func(): dwarf_trial=not dwarf_trial; _apply_scales(),trials)
	_button("Animals",func(): animal_trial=not animal_trial; _apply_scales(),trials)
	_button("Trees",func(): tree_trial=not tree_trial; _apply_scales(),trials)
	_button("Rooms size",_toggle_rooms,trials)
	_button("Pose",_toggle_pose,trials)
	_button("Light",func(): _set_light("Dusk" if time_of_day=="Day" else "Day"); _refresh_ui(),trials)
	_button("Reset",func(): _preset("A"),trials)
	caption=Label.new(); column.add_child(caption)
	caption.add_theme_font_size_override("font_size",15)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=18; bottom.offset_right=-18; bottom.offset_top=-93; bottom.offset_bottom=-14
	bottom.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	layer.add_child(bottom)
	var bottom_column := VBoxContainer.new(); bottom.add_child(bottom_column)
	detail=Label.new(); bottom_column.add_child(detail)
	footer=Label.new(); bottom_column.add_child(footer)
	footer.text="RMB orbit · Wheel zoom · 1 / 2 / 3 presets · R reference · Esc close   |   Posed study; gameplay and saves unchanged"
	footer.add_theme_font_size_override("font_size",13)
	footer.add_theme_color_override("font_color",UITheme.HEARTH_MUTED)
	for spec in labels:
		var label := Label.new()
		label.text=spec.text
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",15 if spec.small else 18)
		label.add_theme_color_override("font_color",Color("E8DBC0"))
		label.add_theme_color_override("font_shadow_color",Color("152120"))
		label.add_theme_constant_override("shadow_offset_x",2)
		label.add_theme_constant_override("shadow_offset_y",2)
		layer.add_child(label); spec["label"]=label
	reference_panel=PanelContainer.new()
	reference_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reference_panel.offset_left=55; reference_panel.offset_right=-55
	reference_panel.offset_top=200; reference_panel.offset_bottom=-140
	reference_panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	layer.add_child(reference_panel)
	var ref_column := VBoxContainer.new(); reference_panel.add_child(ref_column)
	var heading := Label.new()
	heading.text="EARLIER SETTLEMENT CONCEPT · composition reference; painted block sizes are not a measured grid"
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ref_column.add_child(heading)
	var image := TextureRect.new()
	image.texture=load(REFERENCE)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical=Control.SIZE_EXPAND_FILL
	ref_column.add_child(image)
	_button("Close concept",func(): reference_panel.hide(),ref_column)
	reference_panel.hide()


func _button(text: String, action: Callable, parent: Node) -> void:
	var button := UITheme.make_button(text,"",Vector2(90,31))
	UITheme.apply_hearth_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[text]=button


func _preset(id: String) -> void:
	dwarf_trial=false; animal_trial=false; tree_trial=id=="C"
	framing="Wide" if id=="A" else "Close"
	if compact: _toggle_rooms()
	_apply_scales()
	_select_view(view)


func _toggle_rooms() -> void:
	compact=not compact
	terrain.compact=compact
	# submit_chunk reapplies edits; clear only this disposable study's world first.
	WorldData.clear_world()
	terrain.create_world()
	terrain.excavate_rooms()
	for spec in specimens:
		if spec.family not in ["furniture","dwarves"] or spec.stage!="settlement": continue
		spec.node.position=spec.original_position
		if compact and spec.id=="log_bed": spec.node.position.x+=.5
		if compact and spec.id=="wooden_torch": spec.node.position.z+=2
		# Keep the same contents clear of the smaller room's walls.
		if compact and spec.id=="barrel" and spec.original_position.x<45: spec.node.position.x+=.5
		if compact and spec.family=="dwarves" and spec.original_position.z<43: spec.node.position.x-=.65
	_rebuild_terrain()
	_refresh_ui()


func _apply_scales() -> void:
	for spec in specimens:
		var factor := .9 if (spec.family=="dwarves" and dwarf_trial) or (spec.family=="animals" and animal_trial) else .75 if spec.family=="trees" and tree_trial else 1.0
		spec.node.scale=Vector3.ONE*factor
	_refresh_ui()


func _select_view(value: String) -> void:
	view=value
	lineup.visible=view=="Lineup"
	settlement.visible=view!="Lineup"
	terrain.visible=view!="Lineup"
	for spec in specimens:
		if spec.family=="trees": spec.node.visible=view=="Settlement"
	match view:
		"Lineup": target=Vector3(116,22.7,40); yaw=0; pitch=0; zoom=26
		"Rooms": target=Vector3(45.7,22.5,40); yaw=-15; pitch=50; zoom=26 if framing=="Wide" else 21
		"Settlement": target=Vector3(48,26,47); yaw=-28; pitch=40; zoom=49 if framing=="Wide" else 36
	_update_camera()
	_refresh_ui()


func _set_light(value: String) -> void:
	time_of_day=value
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color("FFF1D8")
	sun.light_energy=1.15 if value=="Day" else .22
	look.ambient_light_energy=.5 if value=="Day" else .28
	look.background_color=Color("293A3B") if value=="Day" else Color("1B2633")


func _toggle_pose() -> void:
	pose="Walk" if pose=="Stand" else "Stand"
	playing=pose=="Walk"
	phase=0
	_apply_pose()
	_refresh_ui()


func _apply_pose() -> void:
	for spec in specimens:
		if spec.family=="dwarves":
			spec.node._reset_part_offsets()
			if pose=="Walk": spec.node._walk_cycle=phase; spec.node._walk_bob(0)
		elif spec.family=="animals":
			spec.node.activity="Wandering" if pose=="Walk" else "Idle"
			spec.node.hop_progress=phase if pose=="Walk" else 1.0
			spec.node.pose_time=phase*5
			spec.node._pose()


func _update_camera() -> void:
	camera.size=zoom
	var direction := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(pitch)),sin(deg_to_rad(pitch)),cos(deg_to_rad(yaw))*cos(deg_to_rad(pitch)))
	camera.position=target+direction*85
	camera.look_at(target)


func _refresh_ui() -> void:
	if caption==null: return
	caption.text="%s · %s framing · %s · one block = one world unit" % [view,"Fixed" if view=="Lineup" else framing,time_of_day]
	buttons.Dwarves.text="Dwarves: %s" % ("90%" if dwarf_trial else "100%")
	buttons.Animals.text="Animals: %s" % ("90%" if animal_trial else "100%")
	buttons.Trees.text="Trees: %s" % ("75%" if tree_trial else "100%")
	buttons["Rooms size"].text="Rooms: %s" % ("6 × 6" if compact else "8 × 8")
	buttons.Pose.text="Pose: "+pose
	buttons.Light.text="Light: "+time_of_day
	var dwarf_height: float=report.measurements.get("Dwarf (beard)",{}).get("height",3.32)*(.9 if dwarf_trial else 1)
	detail.text="Dwarf %.2f blocks · doorway 4 blocks · fixed studio lighting · display instances only\n" % dwarf_height
	detail.text+="Lineup holds its camera fixed. B changes framing only; C adds 75% trees. Room size and actor trials are independent."


func _process(delta: float) -> void:
	if not ready_for_review: return
	if playing and not capture_mode:
		phase=fposmod(phase+delta*.9,1)
		_apply_pose()
	for spec in labels:
		var label: Label=spec.label
		label.visible=spec.parent.is_visible_in_tree() and not reference_panel.visible
		if label.visible:
			label.size=Vector2(110,30)
			label.position=camera.unproject_position(spec.at)-Vector2(55,15 if spec.small else 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: orbiting=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom=clampf(zoom*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),10,75)
			_update_camera()
	if event is InputEventMouseMotion and orbiting:
		yaw-=event.relative.x*.25
		pitch=clampf(pitch+event.relative.y*.2,8,80)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if reference_panel.visible: reference_panel.hide()
				else: get_tree().quit()
			KEY_1: _preset("A")
			KEY_2: _preset("B")
			KEY_3: _preset("C")
			KEY_R: reference_panel.visible=not reference_panel.visible


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if not mesh.visible or mesh.mesh==null: continue
		# Hidden tools are not part of a standing dwarf's size.
		var parent: Node=mesh
		var visible := true
		while parent!=node:
			if parent is Node3D and not parent.visible: visible=false
			parent=parent.get_parent()
		if not visible: continue
		var part: AABB=node.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		box=part if first else box.merge(part)
		first=false
	return box


func _measure() -> void:
	for spec in specimens:
		if report.measurements.has(spec.id): continue
		var box := _bounds(spec.node)
		report.measurements[spec.id]={"height":snappedf(box.size.y,.001),"width":snappedf(box.size.x,.001),
			"depth":snappedf(box.size.z,.001),"bottom":snappedf(box.position.y,.001),"family":spec.family}
		if spec.family=="dwarves":
			report.measurements[spec.id]["head_width"] = snappedf(_bounds(spec.node._head).size.x,.001)
			report.measurements[spec.id]["torso_width"] = snappedf(_bounds(spec.node._body).size.x,.001)


func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition: failures.append(message)


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var fingerprint: String=terrain.fingerprint()
	_preset("A"); _select_view("Lineup")
	await _capture("lineup_current")
	var fixed_camera := camera.global_transform
	buttons.Dwarves.pressed.emit()
	_check(camera.global_transform.is_equal_approx(fixed_camera),"Dwarf trial retains camera")
	await _capture("lineup_dwarves_90")
	buttons.Dwarves.pressed.emit(); buttons.Animals.pressed.emit()
	_check(camera.global_transform.is_equal_approx(fixed_camera),"Animal trial retains camera")
	await _capture("lineup_animals_90")
	_preset("A"); _select_view("Rooms")
	await _capture("rooms_current")
	buttons["Rooms size"].pressed.emit()
	await _capture("rooms_compact")
	_check(terrain.floor_cells.size()==72,"Two compact rooms each have 36 floor cells")
	_check(terrain.fingerprint()!=fingerprint,"Compact rooms alter only the study fixture")
	_toggle_rooms()
	_check(terrain.floor_cells.size()==128,"Two current rooms each have 64 floor cells")
	_check(terrain.fingerprint()==fingerprint,"Room reset restores exact block data")
	for light in ["Day","Dusk"]:
		_set_light(light)
		for preset in ["A","B","C"]:
			_preset(preset); _select_view("Settlement")
			await _capture("settlement_"+preset.to_lower()+"_"+light.to_lower())
	_preset("A"); _set_light("Day"); _select_view("Lineup")
	buttons.Pose.pressed.emit(); phase=.25; _apply_pose()
	await _capture("lineup_walk")
	buttons.Pose.pressed.emit()
	buttons.Concept.pressed.emit()
	_check(reference_panel.visible,"Concept button opens the reference")
	await _capture("concept_reference")
	buttons["Close concept"].pressed.emit()
	_check(not reference_panel.visible,"Reference close button works")
	for spec in specimens:
		_check(spec.node.scale.is_equal_approx(Vector3.ONE),"Reset restores size: "+spec.id)
		_check(is_finite(_bounds(spec.node).size.y),"Finite bounds: "+spec.id)
	_check(terrain.fingerprint()==fingerprint,"Art/camera trials preserve voxel data")
	_check(SaveManager._save_directory_path=="user://scale_study" and not SaveManager.is_processing(),"Save system isolated and disabled")
	_check(WorldClock.paused and not wildlife.is_processing(),"Simulation remains paused")
	report.checks=checks; report.failures=failures
	report["passed"]=failures.is_empty()
	report["camera_projection"]="orthographic for reliable comparisons; production camera is perspective"
	report["lighting"]="fixed neutral studio day/dusk; current terrain detail shader, no study terrain chamfers or grass caps"
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("SCALE_STUDY_CAPTURE_OK" if failures.is_empty() else "SCALE_STUDY_CAPTURE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture(id: String) -> void:
	_refresh_ui()
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(OUT+id+".png")==OK,"Capture "+id)
	report.captures[id]={"camera_size":camera.size,"camera_position":str(camera.position),"camera_rotation":str(camera.rotation),
		"dwarf_scale":.9 if dwarf_trial else 1,"animal_scale":.9 if animal_trial else 1,"tree_scale":.75 if tree_trial else 1,
		"room_width":6 if compact else 8,"light":time_of_day}


func _exit_tree() -> void:
	if is_instance_valid(source): source.free()
