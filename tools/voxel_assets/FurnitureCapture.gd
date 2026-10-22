extends Node3D

## Native comparison using owner-loaded definitions and production interaction poses.
var source: FurniturePlacementController
var camera: Camera3D
var environment: WorldEnvironment
var look: Environment
var sun: DirectionalLight3D
var caption: Label
var labels: Array[Label] = []
var _installed := {} # The production seated look-at code consults this.
var output := "res://tmp/settlement_art_20261013/furniture_native_gallery/"
var pairs: Array[Node3D]=[]
var title_label: Label
var only_ids := PackedStringArray()
var all_woods := false
var colony := false
var staged: Array[PackedScene]=[]

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size=Vector2i(1600,1000)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg.begins_with("--only="): only_ids=arg.trim_prefix("--only=").split(",")
		if arg=="--all-woods": all_woods=true
		if arg=="--colony": colony=true
	if "--staged" in OS.get_cmdline_user_args(): staged=preload("res://tools/voxel_assets/StagedAssets.gd").install("furniture")
	get_window().title="Deepdraft - Furniture review"
	SaveManager.configure_storage_for_testing("user://furniture_review")
	WorldGenerator.world_seed=1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector"]:
		var service := get_tree().root.get_node_or_null(id)
		if service!=null: service.set_process(false)
	_stage()
	for i in 3: await get_tree().process_frame
	SkyController.set_process(false); WeatherManager.set_process(false)
	environment.environment=look
	sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.15; sun.light_color=Color("FFF1D8")
	for child in get_children():
		if child is DirectionalLight3D and child!=sun: child.queue_free()
	source=FurniturePlacementController.new(); source._load_defs()
	_ui()
	DirAccess.make_dir_recursive_absolute(output)
	_capture_all.call_deferred()

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

func _ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	title_label=Label.new(); title_label.text="DEEPDRAFT / FURNITURE"
	title_label.position=Vector2(32,22); title_label.add_theme_font_size_override("font_size",28); layer.add_child(title_label)
	caption=Label.new(); caption.position=Vector2(32,66); caption.add_theme_font_size_override("font_size",20); layer.add_child(caption)
	for text in ["VIEW A","OPPOSITE VIEW"]:
		var label := Label.new(); label.text=text; label.size=Vector2(280,36)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.add_theme_font_size_override("font_size",22)
		layer.add_child(label); labels.append(label)

func _show(definition: Dictionary,pose: String="",angle: float=30,material: String="") -> void:
	for pair in pairs: pair.free()
	pairs.clear()
	var width := 0.0; var height := 0.0; var depth := 0.0
	for i in 2:
		var group := Node3D.new(); add_child(group); pairs.append(group)
		var def := definition
		var prop: Node3D=source._instance_model("",source._make_solid_material(),def)
		group.add_child(prop)
		if not material.is_empty(): CraftMaterials.apply_palette(prop,def,"base:material:"+material)
		if def.has("light_source"):
			preload("res://scripts/components/FurnitureLighting.gd").attach(prop,def)
			prop.get_node("FlameAnimation").set_process(false)
		var bounds := _bounds(prop)
		if "bridge" in String(def.model): prop.position.y=-bounds.position.y
		if pose=="Open":
			var hinges := preload("res://scripts/components/FurnitureDoorAnimation.gd").new()
			prop.add_child(hinges); hinges.setup(prop,def.door_animation); hinges.set_process(false)
			for index in hinges._hinges.size(): hinges._hinges[index].rotation.y=PI*.5*(1 if index==0 else -1)
		if pose in ["Sit","Sleep"]:
			var data := DwarfFactory.new().generate(141,{})
			data.gender="female"; var appearance := DwarfAppearanceData.new()
			appearance.gender="female"; appearance.hair_style="twin_braids"; appearance.eye_color="blue"
			data.appearance=appearance
			var dwarf := DwarfFactory.new().spawn(data,1620+i)
			group.add_child(dwarf); dwarf.set_process(false); dwarf.get_node("Readability").set_process(false)
			var piece := InstalledFurnitureComponent.new(); piece.def=def; piece.node=prop
			if pose=="Sit":
				dwarf._idle_behavior.seat=piece; dwarf._idle_behavior._furniture=self
				dwarf._idle_behavior._sitting_blend=1; dwarf._idle_behavior.elapsed=3; dwarf._idle_behavior._pose()
			else:
				dwarf.rotation.y=PI*.5; dwarf._rest_behavior.bed_rest.bed=piece
				dwarf._rest_behavior.pose="lying"; dwarf._rest_behavior.blend=1
				dwarf._rest_behavior.elapsed=3; dwarf._rest_behavior._apply_pose()
		bounds=_bounds(group)
		width=maxf(width,maxf(bounds.size.x,bounds.size.z)); height=maxf(height,bounds.end.y); depth=maxf(depth,bounds.size.z)
	var spacing := maxf(width+2,4.5)
	for i in 2:
		pairs[i].position=Vector3(40+(i-.5)*spacing,21,40)
		pairs[i].rotation_degrees.y=angle+180*i
	var target := Vector3(40,21+height*.48,40-(depth*.25 if "bridge" in String(definition.model) else 0))
	camera.position=target+Vector3(0,17,30); camera.look_at(target)
	camera.size=maxf((spacing+width+3)/1.6,height*1.4+depth*.5+2.2)
	caption.text=String(definition.get("display_name",String(definition.model).get_file().get_basename())).replace("_"," ")+ (" · "+pose if not pose.is_empty() else "")+(" · "+material if not material.is_empty() else "")
	for i in 2: labels[i].position=Vector2(get_viewport().size.x*(.25 if i==0 else .75)-140,get_viewport().size.y-65)

func _bounds(model: Node3D) -> AABB:
	var bounds := AABB(); var first := true
	for mesh: MeshInstance3D in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(model):
		var box: AABB=model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=box if first else bounds.merge(box); first=false
	return bounds

func _process(_delta: float) -> void: pass

func _capture_all() -> void:
	for key: String in source.get_defs():
		if not String(source.get_defs()[key].model).contains("/furniture/"): continue
		var def: Dictionary=source.get_defs()[key]; var id := key.get_slice(":",2)
		if not only_ids.is_empty() and not id in only_ids: continue
		_show(def); await _capture(id)
		if colony:
			camera.size*=1.8; caption.text+=" · colony distance"
			await _capture(id+"_colony")
		if def.has("door_animation"):
			_show(def,"Open"); await _capture(id+"_open")
		if id in ["log_chair","bench","log_bed"]:
			for angle in [30.0,90.0]:
				_show(def,"Sleep" if def.has("sleep_surface") else "Sit",angle)
				await _capture(id+"_use_"+str(int(angle)))
		if id=="campfire" or (all_woods and def.has("material_palette")):
			for wood in ["pine","juniper","applewood"]:
				_show(def,"",30,wood); await _capture(id+"_"+wood)
	var extras := ["packed_furniture","ladder_kit","bridge_kit"]
	for height in range(1,4): extras.append("crude_ladder_"+str(height))
	for span in range(1,5): extras.append("log_bridge_"+str(span))
	for id in extras:
		if not only_ids.is_empty() and not id in only_ids: continue
		_show({"model":"res://assets/models/furniture/"+id+".glb"})
		await _capture(id)
	print("FURNITURE_VOXEL_CAPTURE_OK: retained catalogue, interaction, material and packed-form views")
	get_tree().quit()

func _capture(id: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(output+id+".png")
	assert(result==OK)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()

func _exit_tree() -> void:
	if is_instance_valid(source): source.free()
