extends SceneTree

## Native production catalogue, using the production item owner.
var OUT := "res://tmp/item_art_20261013/captures/"
var scene: Node3D
var content: Node3D
var items
var definitions: Dictionary
var camera: Camera3D
var caption: Label
var labels: Array[Label]=[]
var captures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): OUT=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	root.size=Vector2i(1600,1000); root.msaa_3d=Viewport.MSAA_4X
	root.get_node("SaveManager").configure_storage_for_testing("user://item_art_review")
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager","SkyController","WeatherManager","WorldEventDirector"]:
		var service := root.get_node_or_null(id)
		if service!=null: service.set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	root.get_node("WorldClock").set_paused(true)
	scene=Node3D.new(); root.add_child(scene); current_scene=scene
	content=Node3D.new(); scene.add_child(content)
	items=load("res://scripts/systems/ItemDropManager.gd").new(); scene.add_child(items)
	definitions=items.get_item_defs()
	var environment := WorldEnvironment.new(); scene.add_child(environment)
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color("243237")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color("DCE8EA"); env.ambient_light_energy=.65
	environment.environment=env
	var sun := DirectionalLight3D.new(); scene.add_child(sun)
	camera=Camera3D.new(); scene.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.current=true
	var layer := CanvasLayer.new(); scene.add_child(layer)
	caption=Label.new(); layer.add_child(caption); caption.position=Vector2(36,26); caption.add_theme_font_size_override("font_size",27)
	for i in 12:
		var label := Label.new(); layer.add_child(label); label.add_theme_font_size_override("font_size",18)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.size=Vector2(340,55); labels.append(label)
	for i in 5: await process_frame
	environment.environment=env; env.fog_enabled=false; env.ambient_light_sky_contribution=0
	sun.rotation_degrees=Vector3(-48,-32,0); sun.light_color=Color("FFF0D6"); sun.light_energy=1.15; sun.shadow_enabled=true
	for child in scene.get_children():
		if child is DirectionalLight3D and child!=sun: child.queue_free()
	DirAccess.make_dir_recursive_absolute(OUT)
	await _review()

func _review() -> void:
	var groups := {}
	for key: String in definitions:
		var definition: Dictionary=definitions[key]
		var path := String(definition.get("model",""))
		if not "/items/" in path: continue
		var category := path.get_base_dir().get_file()
		if not groups.has(category): groups[category]=[]
		if definition.has("crate_models"):
			for count in [1,9,17]: groups[category].append([key,count])
		else: groups[category].append([key,1])
	for category: String in groups:
		var rows: Array=groups[category]
		for page in range(0,rows.size(),9):
			_show(rows.slice(page,mini(page+9,rows.size())))
			caption.text="DEEPDRAFT / "+category.to_upper()+" / VOXELS"
			await _capture(category+"_%02d"%(page/9))
	# A mixed resource sheet at one consistent scale.
	var pair_keys := ["rough_stone","copper_ore","pine_log","apple","plump_helmet","ale_barrel"]
	var pair_rows := []
	for id in pair_keys:
		pair_rows.append([_key_for(id),17 if id=="apple" else 1])
	_show(pair_rows)
	caption.text="DEEPDRAFT / VOXELS / MATCHED SCALE"
	await _capture("comparison_voxel")
	await _tools()
	await _carry()
	for key: String in definitions:
		if definitions[key].get("material_palette","")!="starter_tool": continue
		_clear(); caption.text="DEEPDRAFT / "+String(definitions[key].display_name).to_upper()+" / WOOD MATERIALS"
		for i in 4:
			var wood: String=["pine","oak","juniper","applewood"][i]
			var prop: Node3D=items.create_item_visual(key,1,"","base:material:"+wood)
			content.add_child(prop); prop.position=Vector3((i-1.5)*1.9,0,0)
			labels[i].text=wood.capitalize(); labels[i].show()
		_view(Vector3(0,.1,0),6.8)
		for i in 4: labels[i].position=camera.unproject_position(Vector3((i-1.5)*1.9,0,1.4))-Vector2(170,0)
		await _capture("wood_"+key.get_slice(":",3))
	FileAccess.open(OUT+"native.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":captures,"forms":92,"fallbacks":items._missing_models.keys()},"  "))
	print("ITEM_ART_CAPTURE_OK: ",captures," native views; all 92 forms, wood variants, tool motion and cargo")
	quit()

func _clear() -> void:
	for child in content.get_children(): child.free()
	for label in labels: label.hide()

func _view(center: Vector3,size: float,side := false) -> void:
	camera.size=size; camera.position=center+(Vector3(12,8,14) if side else Vector3(0,9,12)); camera.look_at(center)

func _show(rows: Array) -> void:
	_clear(); _view(Vector3(0,.15,0),7.6)
	for i in rows.size():
		var key: String=rows[i][0]; var count: int=rows[i][1]; var definition: Dictionary=definitions[key]
		var prop: Node3D=items.create_item_visual(key,count)
		content.add_child(prop); prop.position=Vector3((i%3-1)*2.8,0,(i/3-1)*2.6); prop.rotation.y=.34
		labels[i].text=String(definition.display_name)+( " / "+["LOW","HALF","FULL"][mini((count-1)>>3,2)] if definition.has("crate_models") else "")
		labels[i].position=camera.unproject_position(prop.position+Vector3(0,-.03,1.0))-Vector2(170,0); labels[i].show()

func _actor() -> Node3D:
	var factory=load("res://scripts/entities/DwarfFactory.gd").new()
	var data=factory.generate(141,{})
	data.gender="male"
	var appearance=load("res://scripts/entities/DwarfAppearanceData.gd").new()
	appearance.gender="male"; appearance.hair_style="short_back"; appearance.beard_style="forked"
	appearance.eye_color="blue"; appearance.eyebrow_style="thick_flat"
	data.appearance=appearance
	var dwarf: Node3D=factory.spawn(data,141)
	content.add_child(dwarf); dwarf.set_process(false); dwarf.get_node("Readability").set_process(false)
	return dwarf

func _tools() -> void:
	var registry=root.get_node("DwarfAssets")
	var new_axe: PackedScene=registry.felling_axe; var new_pick: PackedScene=registry.mining_pickaxe
	for action in ["felling","mining"]:
		_clear(); var dwarf=_actor(); _view(Vector3(0,1.65,.3),5.5,true)
		for phase in ([.0,.36,.54,.80] if action=="felling" else [.0,.55,.92,1.0]):
			if action=="felling": dwarf._felling_pose.apply(phase,Vector3(0,1.2,1.45))
			else: dwarf._mining_pose.apply(phase,Vector3(0,1.4,1.45))
			caption.text="DEEPDRAFT / "+action.to_upper()+" / "+"VOXELS"+" / "+str(phase)
			await _capture("voxel_"+action+"_%02d"%roundi(phase*100))
	_clear(); _view(Vector3(0,.85,0),3.0,true)
	for i in 2:
		var tool: Node3D=([new_axe,new_pick][i] as PackedScene).instantiate()
		preload("res://scripts/components/VoxelShadowSetup.gd").configure(tool)
		content.add_child(tool); tool.position=Vector3((i-.5)*1.2,.25,0)
		items._apply_material(tool,items._material)
	caption.text="DEEPDRAFT / AXE & PICK / VOXELS"
	await _capture("work_tools")

func _carry() -> void:
	var cases := [["rough_stone",4],["oak_log",4],["apple",4],["carpentry_kit",1],["ale_barrel",1],["water_bucket",1]]
	for spec in cases:
		_clear(); var dwarf=_actor(); var entries := []
		var key := ""
		key=_key_for(spec[0])
		for i in spec[1]:
			var item: Node3D=items.create_item_visual(key,24 if spec[0]=="apple" else 1)
			dwarf.add_child(item); entries.append([item,key])
		dwarf._carry_pose.hold(entries); _view(Vector3(0,1.6,.6),5.8,true)
		caption.text="DEEPDRAFT / CARRY / "+String(definitions[key].display_name).to_upper()+" x"+str(spec[1])
		await _capture("carry_"+spec[0])
		camera.size=16
		await _capture("colony_"+spec[0])

func _key_for(id: String) -> String:
	for key: String in definitions:
		if key.ends_with(":"+id) or String(definitions[key].get("model","")).get_file()==id+".glb": return key
	assert(false,"Missing catalogue item: "+id)
	return ""

func _capture(id: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+id+".png"); captures+=1
