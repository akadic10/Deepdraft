extends SceneTree

## Imported production definitions, every crate threshold, materials and tool anchors.
var failures: Array[String]=[]
var checks := 0
var scene: Node3D
var items
var definitions: Dictionary
var inspected := {}
var keys: Array[String]=[]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Item art test timed out"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("WorldGenerator").world_seed=1234
	scene=Node3D.new(); root.add_child(scene); current_scene=scene
	items=load("res://scripts/systems/ItemDropManager.gd").new(); scene.add_child(items)
	definitions=items.get_item_defs()
	for key: String in definitions:
		var definition: Dictionary=definitions[key]
		if not "/items/" in String(definition.get("model","")): continue
		keys.append(key)
		var counts := [1,8,9,16,17,24] if definition.has("crate_models") else [1]
		var paths := {}
		var bounds_by_stage := {}
		for count in counts:
			var prop: Node3D=items.create_item_visual(key,count)
			scene.add_child(prop)
			var path: String=definition.crate_models[mini((count-1)>>3,2)] if definition.has("crate_models") else definition.model
			var visual: Node3D=prop.get_child(0)
			_expect(visual.scene_file_path==path,"runtime stage path "+key+" "+str(count))
			_expect(items.quantity_of(prop)==count,"quantity retained "+key)
			var box := _inspect(visual,path)
			paths[path]=true; bounds_by_stage[path]=box
			load("res://scripts/components/StorageItemLayout.gd").fit(prop,Vector3(.3125,.625,.3125),.5)
			var fitted: AABB=load("res://scripts/components/ObjectPicking.gd").world_bounds(prop)
			_expect(fitted.size.x<=.314 and fitted.size.z<=.314 and absf(fitted.position.y)<.001,"shelf fit "+key)
			prop.free()
		_expect(paths.size()==(3 if definition.has("crate_models") else 1),"complete forms "+key)
		if definition.has("crate_models"):
			var models: Array=definition.crate_models
			_expect((bounds_by_stage[models[2]] as AABB).size.y>(bounds_by_stage[models[0]] as AABB).size.y,"full crate visibly higher "+key)
		if definition.get("material_palette","")=="starter_tool": _wood_variants(key,definition)
	_expect(keys.size()==62 and inspected.size()==92,"all 62 definitions / 92 presentations imported")
	_expect(items._missing_models.is_empty(),"zero fallback models")
	_work_tools()
	_carry()
	DirAccess.make_dir_recursive_absolute("res://tmp/item_art_20261013")
	var report := {"checks":checks,"failures":failures,"items":keys.size(),"presentations":inspected.size()}
	FileAccess.open("res://tmp/item_art_20261013/imported_checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("ITEM_FACETED_ART_OK: ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _inspect(prop: Node3D,path: String) -> AABB:
	var meshes := prop.find_children("*","MeshInstance3D",true,false)
	if prop is MeshInstance3D: meshes.push_front(prop)
	_expect(prop.transform.is_equal_approx(Transform3D.IDENTITY),"unit export "+path)
	_expect(meshes.size()==1 and meshes[0].mesh is ArrayMesh,"one actual mesh "+path)
	var mesh: MeshInstance3D=meshes[0]
	_expect(mesh.mesh.get_surface_count()==1,"one surface "+path)
	var bounds := mesh.get_aabb()
	_expect(absf(bounds.position.y)<.001,"grounded "+path)
	_expect(prop.find_children("*","CollisionObject3D",true,false).is_empty(),"no embedded gameplay collision "+path)
	if not inspected.has(path):
		var a: Array=mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
		var valid := true
		var radial := 0.0
		for i in vertices.size():
			valid=valid and vertices[i].is_finite() and absf(normals[i].length()-1)<.001
			radial=maxf(radial,Vector2(vertices[i].x,vertices[i].z).length())
		_expect(valid,"finite vertices / unit normals "+path)
		if "/crates/" in path or "/wood/" in path: _expect(radial<=.501,"one-tile yaw footprint "+path)
		inspected[path]=true
	return bounds

func _wood_variants(key: String,definition: Dictionary) -> void:
	var materials=root.get_node("CraftMaterials")
	var original: Node3D=load(definition.model).instantiate()
	var colors := _colors(original)
	var variants := []
	for wood in ["pine","oak","juniper","applewood"]:
		var prop: Node3D=items.create_item_visual(key,1,"","base:material:"+wood)
		var changed := _colors(prop)
		_expect(changed!=colors and not variants.has(changed),"wood variant "+key+" "+wood)
		var retained := 0
		for i in colors.size():
			if colors[i]==changed[i]: retained+=1
		# The spear has only six stone triangles. Check actual material roles,
		# rather than requiring an arbitrary vertex count from a voxel mesh.
		var roles_ok := true
		for i in colors.size():
			var is_wood := false
			for swatch: String in materials.palettes.starter_tool.colors.values():
				var source := Color(swatch).srgb_to_linear()
				source=Color(floorf(source.r*255)/255,floorf(source.g*255)/255,floorf(source.b*255)/255)
				if colors[i].is_equal_approx(source): is_wood=true
			roles_ok=roles_ok and ((colors[i]!=changed[i]) if is_wood else (colors[i]==changed[i]))
		_expect(roles_ok and retained>0 and retained<colors.size(),"only semantic wood changes "+key+" "+wood)
		variants.append(changed); prop.free()
	_expect(_colors(original)==colors,"cached source unchanged "+key)
	_expect(materials.palettes.has("starter_tool"),"owned semantic palette")
	original.free()

func _colors(node: Node) -> PackedColorArray:
	var result := PackedColorArray()
	if node is MeshInstance3D: result.append_array(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	for child in node.get_children(): result.append_array(_colors(child))
	return result

func _work_tools() -> void:
	var assets=root.get_node("DwarfAssets")
	for spec in [[assets.felling_axe,Vector3(0,1.0625,.6875)],[assets.mining_pickaxe,Vector3(0,1.375,.9375)]]:
		var prop: Node3D=spec[0].instantiate()
		_expect("/tools/" in prop.scene_file_path,"new tool routed through registry")
		_expect(prop.transform.is_equal_approx(Transform3D.IDENTITY),"tool grip origin retained")
		var mesh: MeshInstance3D=prop.find_children("*","MeshInstance3D",true,false)[0]
		var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var error := INF
		for vertex in vertices: error=minf(error,vertex.distance_to(spec[1]))
		_expect(error<.001,"actual geometry contains fixed impact point")
		var box := mesh.get_aabb()
		_expect(box.has_point(Vector3.ZERO) and box.has_point(Vector3(0,.625,0)),"shaft covers both grip anchors")
		prop.free()

func _carry() -> void:
	var factory=load("res://scripts/entities/DwarfFactory.gd").new()
	var dwarf=factory.spawn(factory.generate(141,{}),141)
	scene.add_child(dwarf); dwarf.set_process(false)
	for key in keys:
		var prop: Node3D=items.create_item_visual(key,17 if definitions[key].has("crate_models") else 1)
		dwarf.add_child(prop)
		var entries := [[prop,key]]
		dwarf._carry_pose.hold(entries)
		var box: AABB=dwarf._carry_pose.item_bounds(prop)
		_expect(absf((prop.transform*box).position.y-.95)<.001,"carry bottom "+key)
		_expect((prop.transform*box).position.z>=1.149,"cargo clears torso "+key)
		prop.free(); dwarf._carry_pose.clear_items()
	for key in ["base:resources:stone:rough_stone","base:resources:wood:oak_log","base:resources:flora:apple"]:
		var entries := []
		for i in 4:
			var prop: Node3D=items.create_item_visual(key,24 if key.ends_with(":apple") else 1)
			dwarf.add_child(prop); entries.append([prop,key])
		dwarf._carry_pose.hold(entries)
		var boxes: Array[AABB]=[]
		for entry in entries: boxes.append(entry[0].transform*dwarf._carry_pose.item_bounds(entry[0]))
		for i in boxes.size():
			for j in range(i+1,boxes.size()): _expect(not boxes[i].intersects(boxes[j]),"four-item cargo separation "+key)
		for entry in entries: entry[0].free()
		dwarf._carry_pose.clear_items()
	dwarf.free()

func _expect(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
