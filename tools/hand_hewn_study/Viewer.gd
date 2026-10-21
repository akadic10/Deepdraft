extends Node3D

## Real imported meshes in an isolated source-project viewer. No save loading.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
const ART := "res://assets/models/studies/hand_hewn_timber/"
const KINDS := ["dining_table","log_stool","game_table","workbench","timber"]
const WOODS := ["oak","pine","juniper","applewood"]
var output := "res://tmp/hand_hewn_study/captures/"
var camera: Camera3D
var sun: DirectionalLight3D
var look: Environment
var environment: WorldEnvironment
var content: Node3D
var wood_surface: StandardMaterial3D
var source: FurniturePlacementController
var heading: Label
var caption: Label
var footer: Label
var annotations: Array[Label]=[]
var anchors: Array[Vector3]=[]
var wood := "oak"
var mode := "Family"
var view := "Close"
var light_mode := "Neutral"
var yaw := 22.0
var zoom := 1.0
var capturing := false
var checks := 0
var failures: Array[String]=[]
var measurements: Array[Dictionary]=[]

func _ready() -> void:
	capturing="--capture" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1600,1000)
	get_window().title="Deepdraft — Hand-hewn timber / native art preview"
	SaveManager.configure_storage_for_testing("user://hand_hewn_study")
	WorldGenerator.world_seed=1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector","AmbientAudio"]:
		var service := get_tree().root.get_node_or_null(id)
		if service!=null: service.set_process(false)
	WorldClock.restore_state({"year":1,"season":"summer","day":1,"hour":12.0,"speed":1,"paused":true})
	_stage()
	for i in 3: await get_tree().process_frame
	for child in get_children():
		if child is DirectionalLight3D and child!=sun: child.queue_free()
	environment.environment=look
	source=FurniturePlacementController.new(); source._load_defs()
	_validate_imports()
	_ui()
	_show()
	print("HAND_HEWN_READY: ",checks," native checks, ",failures.size()," failures")
	if not failures.is_empty():
		for message in failures: push_error(message)
		get_tree().quit(1)
	elif capturing: _capture_all.call_deferred()

func _stage() -> void:
	look=Environment.new()
	look.background_mode=Environment.BG_COLOR
	look.background_color=Color("34383B")
	look.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color=Color("D5E3ED")
	look.ambient_light_energy=.55
	look.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment=WorldEnvironment.new(); environment.environment=look.duplicate(); add_child(environment)
	sun=DirectionalLight3D.new(); sun.shadow_enabled=true
	sun.rotation_degrees=Vector3(-55,-35,0)
	sun.light_color=Color("FFF3DD"); sun.light_energy=1.2
	preload("res://scripts/components/TerrainLighting.gd").configure_sun(sun)
	sun.directional_shadow_max_distance=80
	add_child(sun)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=200; add_child(camera); camera.make_current()
	wood_surface=StandardMaterial3D.new()
	wood_surface.vertex_color_use_as_albedo=true
	wood_surface.roughness=1
	wood_surface.metallic_specular=0
	var ground=preload("Ground.gd").new(); add_child(ground); ground.create_world()
	var material := ShaderMaterial.new()
	material.shader=preload("res://tools/scale_study/review_terrain.gdshader")
	BlockRegistry.configure_terrain_material(material)
	ground.rebuild(material,StandardMaterial3D.new(),false,false,"shader")

func _validate_imports() -> void:
	for species in WOODS:
		for kind in KINDS:
			var path: String=ART+kind+"_"+species+".glb"
			var scene=load(path) as PackedScene
			_expect(scene!=null,"imported "+path)
			if scene==null: continue
			var model: Node3D=scene.instantiate(); add_child(model)
			for visible_mesh in Shadows.visual_meshes(model): visible_mesh.material_override=wood_surface
			_expect(model.scale.is_equal_approx(Vector3.ONE),kind+" unit root scale")
			_expect(Shadows.configure(model)==1,kind+" one visual/proxy pair")
			var meshes := Shadows.visual_meshes(model)
			_expect(meshes.size()==1,kind+" single visual mesh")
			var mesh := meshes[0]
			var proxy := Shadows.proxy_for_visual(mesh)
			_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,kind+" visual casting off")
			_expect(proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,kind+" proxy shadows only")
			_expect(proxy.visible and proxy.gi_mode==GeometryInstance3D.GI_MODE_DISABLED,kind+" proxy policy")
			_expect(mesh.mesh.get_surface_count()==1,kind+" single material surface")
			var grid_ok := true
			var grid_error := 0.0
			var arrays := mesh.mesh.surface_get_arrays(0)
			var distinct_colors := {}
			for color: Color in arrays[Mesh.ARRAY_COLOR]: distinct_colors[color]=true
			_expect(distinct_colors.size()>=8,kind+" authored bark/cut palette retained")
			_expect(mesh.material_override==wood_surface and wood_surface.vertex_color_use_as_albedo,kind+" shared vertex-color material")
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var p: Vector3=model.global_transform.affine_inverse()*mesh.global_transform*vertex*16.0
				grid_error=maxf(grid_error,(p-p.round()).length())
				# Godot's default imported vertex compression introduces a tiny error.
				if (p-p.round()).length()>=.025: grid_ok=false
			_expect(grid_ok,kind+" native 1:16 vertices")
			var box: AABB=model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
			var expected: Vector3={"dining_table":Vector3(46,24,46),"log_stool":Vector3(14,14,14),"game_table":Vector3(46,25,46),"workbench":Vector3(46,16,46),"timber":Vector3(14,14,14)}[kind]/16.0
			_expect(box.size.is_equal_approx(expected) and is_zero_approx(box.position.y),kind+" dimensions and floor contact")
			var visible_tris: int=arrays[Mesh.ARRAY_INDEX].size()/3
			var shadow_tris: int=proxy.mesh.surface_get_array_index_len(0)/3
			_expect(shadow_tris<visible_tris,kind+" proxy triangle reduction")
			measurements.append({"asset":kind+"_"+species,"visible_triangles":visible_tris,"shadow_triangles":shadow_tris,"size":str(box.size),"max_import_grid_error_cells":grid_error})
			model.free()

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func _ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var strip := ColorRect.new(); strip.color=Color(.07,.075,.08,.92)
	strip.position=Vector2.ZERO; strip.size=Vector2(1600,150); layer.add_child(strip)
	heading=Label.new(); heading.text="DEEPDRAFT  /  HAND-HEWN TIMBER"
	heading.position=Vector2(30,16); heading.add_theme_font_size_override("font_size",28); layer.add_child(heading)
	caption=Label.new(); caption.position=Vector2(30,58); caption.add_theme_font_size_override("font_size",18); layer.add_child(caption)
	var modes := HBoxContainer.new(); modes.position=Vector2(30,100); layer.add_child(modes)
	for value in ["Family","Dining","Games","Workbench","Stools + timber","Compare"]:
		var button := Button.new(); button.text=value
		button.pressed.connect(func(): mode=value; zoom=1; _show()); modes.add_child(button)
	var woods := HBoxContainer.new(); woods.position=Vector2(880,20); layer.add_child(woods)
	for value in WOODS:
		var button := Button.new(); button.text=value.capitalize()
		button.pressed.connect(func(): wood=value; _show()); woods.add_child(button)
	var options := HBoxContainer.new(); options.position=Vector2(880,65); layer.add_child(options)
	for value in ["Close","Colony","Top"]:
		var button := Button.new(); button.text=value
		button.pressed.connect(func(): view=value; zoom=1; _frame()); options.add_child(button)
	var toggle := Button.new(); toggle.text="Neutral / warm"
	toggle.pressed.connect(func(): light_mode="Warm" if light_mode=="Neutral" else "Neutral"; _lighting()); options.add_child(toggle)
	footer=Label.new(); footer.position=Vector2(30,953); footer.add_theme_font_size_override("font_size",17)
	footer.text="Actual Godot render  |  1 cell = 1/16 block  |  Arrow keys: orbit  ·  Wheel: zoom  ·  Esc: close"
	layer.add_child(footer)

func _model(kind: String, at: Vector3, species: String="", parent: Node3D=null) -> Node3D:
	if species.is_empty(): species=wood
	var node: Node3D=load(ART+kind+"_"+species+".glb").instantiate()
	(parent if parent!=null else content).add_child(node)
	node.position=at; Shadows.configure(node)
	for mesh in Shadows.visual_meshes(node): mesh.material_override=wood_surface
	return node

func _dining(at: Vector3, old: bool=false) -> void:
	if old:
		_old_prop("log_table",at)
	else: _model("dining_table",at)
	for offset in [Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2)]:
		if old: _old_prop("log_chair",at+offset)
		else: _model("log_stool",at+offset)

func _old_prop(id: String, at: Vector3) -> Node3D:
	var def: Dictionary=source.get_defs()["base:furniture:"+id]
	var node: Node3D=source._instance_model("",source._make_solid_material(),def)
	content.add_child(node); node.position=at
	CraftMaterials.apply_palette(node,def,"base:material:"+wood)
	return node

func _actor(at: Vector3) -> void:
	var factory := DwarfFactory.new()
	var data := factory.generate(141,{})
	var appearance := DwarfAppearanceData.new()
	appearance.age_tier="adult"; appearance.gender="male"; appearance.skin_tone="medium"
	appearance.hair_color="brown"; appearance.eye_color="blue"
	appearance.hair_style="short_back"; appearance.beard_style="forked"; appearance.eyebrow_style="thick_flat"
	data.appearance=appearance; data.gender="male"
	var actor := factory.spawn(data,2360)
	content.add_child(actor); actor.position=at; actor.rotation_degrees.y=15
	actor.set_process(false); actor.get_node("Readability").set_process(false)

func _annotate(text: String, at: Vector3) -> void:
	var label := Label.new(); label.text=text; label.size=Vector2(440,30)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.add_theme_font_size_override("font_size",18)
	label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",2)
	heading.get_parent().add_child(label); annotations.append(label); anchors.append(at)

func _show() -> void:
	if is_instance_valid(content): content.free()
	for label in annotations: label.free()
	annotations.clear(); anchors.clear()
	content=Node3D.new(); add_child(content); content.position=Vector3(48,21,48)
	match mode:
		"Family":
			_dining(Vector3(-3.6,0,.2))
			_model("game_table",Vector3(3,0,-3))
			_model("workbench",Vector3(3,0,1.6))
			for i in 4:
				var log_model:=_model("timber",Vector3(-2.4+i*1.5,0,4.7),WOODS[i])
				log_model.rotation_degrees.y=-12
			_actor(Vector3(-6,0,-.8))
			_annotate("DINING  /  FOUR STOOLS IN 5 × 5",Vector3(-3.6,0,3))
			_annotate("SAME TABLE  /  SIX COUNTERS",Vector3(3,0,-2.2))
			_annotate("WORN LOG WORKBENCH",Vector3(4.5,0,3.5))
			_annotate("TIMBER  /  FOUR WOODS",Vector3(-.2,0,5.8))
		"Dining": _dining(Vector3.ZERO)
		"Games": _model("game_table",Vector3.ZERO)
		"Workbench": _model("workbench",Vector3.ZERO)
		"Stools + timber":
			for i in 4:
				_model("log_stool",Vector3((i-1.5)*1.6,0,-.9),WOODS[i])
				_model("timber",Vector3((i-1.5)*1.6,0,.9),WOODS[i])
				_annotate(WOODS[i].capitalize(),Vector3((i-1.5)*1.6,0,1.8))
		"Compare":
			_dining(Vector3(-3.3,0,0),true); _dining(Vector3(3.3,0,0))
			_annotate("CURRENT PRODUCTION",Vector3(-3.3,0,3))
			_annotate("HAND-HEWN STUDY",Vector3(3.3,0,3))
	_lighting(); _frame()

func _lighting() -> void:
	var warm := light_mode=="Warm"
	sun.light_color=Color("FFD29A") if warm else Color("FFF7EB")
	sun.light_energy=.95 if warm else .85
	look.ambient_light_color=Color("9BA9C1") if warm else Color("D5E3ED")
	look.ambient_light_energy=.32 if warm else .4
	caption.text=wood.capitalize()+"  ·  "+light_mode+" light  ·  "+mode+"  ·  Existing world-block floor"

func _frame() -> void:
	var target := Vector3(48,21.6,48)
	if mode=="Family": target+=Vector3(-.5,0,1)
	var angle := deg_to_rad(52 if view=="Colony" else 82 if view=="Top" else 38)
	var orbit := deg_to_rad(yaw)
	camera.position=target+Vector3(sin(orbit)*cos(angle),sin(angle),cos(orbit)*cos(angle))*35
	camera.look_at(target)
	var sizes := {"Family":12.3,"Dining":6.1,"Games":4.4,"Workbench":3.9,"Stools + timber":5.5,"Compare":9.8}
	camera.size=float(sizes[mode])*(1.65 if view=="Colony" else 1.0)*zoom
	# Reserve the top controls while keeping the subject centered below them.
	camera.v_offset=camera.size*.06
	for i in annotations.size():
		annotations[i].position=camera.unproject_position(content.position+anchors[i])-Vector2(220,0)
		annotations[i].visible=view!="Colony"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: get_tree().quit()
		if event.keycode==KEY_LEFT: yaw-=15; _frame()
		if event.keycode==KEY_RIGHT: yaw+=15; _frame()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom=maxf(.5,zoom*.9); _frame()
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom=minf(3,zoom*1.1); _frame()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for species in WOODS:
		wood=species; mode="Family"; _show(); await _capture("family_"+wood)
	wood="oak"
	for value in ["Dining","Games","Workbench","Stools + timber","Compare"]:
		mode=value; _show(); await _capture(value.to_snake_case().replace("_+_","_"))
	mode="Family"; light_mode="Warm"; _show(); await _capture("family_warm")
	light_mode="Neutral"; view="Colony"; _show(); await _capture("family_colony")
	view="Top"; mode="Dining"; _show(); await _capture("dining_top")
	var report := FileAccess.open(output+"native_checks.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"assets":measurements},"\t")); report.close()
	print("HAND_HEWN_CAPTURE_PASS: 12 native views; ",checks," checks")
	get_tree().quit()

func _capture(id: String) -> void:
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output+id+".png")
	assert(error==OK)

func _exit_tree() -> void:
	if is_instance_valid(source): source.free()
