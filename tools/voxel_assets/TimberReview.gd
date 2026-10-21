extends "res://tools/voxel_assets/ItemGallery.gd"

## Production owners: identical stool/log geometry, full-size ground storage,
## and actual carry poses. The log's horizontal orientation is baked into vertices.
func _review() -> void:
	var names := ["pine_log","oak_log","juniper_log","apple_wood"]
	var woods := ["pine","oak","juniper","applewood"]
	var furniture=load("res://scripts/systems/FurniturePlacementController.gd").new();furniture._load_defs()
	var definition: Dictionary=furniture.get_defs()["base:furniture:log_chair"]
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(32,32)
	var soil:=StandardMaterial3D.new();soil.albedo_color=Color("71846b")
	ground.material_override=soil;ground.position.y=-.01;scene.add_child(ground)
	var stored: Array[Node3D]=[]
	_clear();_view(Vector3(-1,.25,.5),9.5,true)
	caption.text="DEEPDRAFT / SAME MODEL & SIZE / STOOL AND CHOPPED WOOD"
	for i in 4:
		var prop: Node3D=items.create_item_visual(_key_for(names[i]))
		items.place_stored(prop,Vector3i(-3+5*(i%2),-1,-2+4*(i/2)));stored.append(prop)
		var stool: Node3D=furniture._instance_model("",furniture._make_solid_material(),definition)
		content.add_child(stool);stool.position=prop.position-Vector3(1.5,0,0)
		root.get_node("CraftMaterials").apply_palette(stool,definition,"base:material:"+woods[i])
		labels[i].text=String(woods[i]).capitalize()+" / stool + log";labels[i].show()
		labels[i].position=camera.unproject_position(prop.position+Vector3(-.75,0,1.2))-Vector2(170,0)
	await _capture("stool_and_logs")
	for prop in stored: prop.free()
	stored.clear();_clear();_view(Vector3(0,.3,.5),5.8,true)
	caption.text="DEEPDRAFT / SIDEWAYS LOGS / FULL-SIZE GROUND STOCKPILE"
	for i in 12:
		var prop: Node3D=items.create_item_visual(_key_for(names[i%4]))
		items.place_stored(prop,Vector3i(i%4-2,-1,i/4-1));stored.append(prop)
	await _capture("ground_stockpile")
	for prop in stored: prop.free()
	for i in 4:
		_clear();var dwarf:=_actor();var entries:=[]
		var key:=_key_for(names[i])
		for j in 2:
			var prop: Node3D=items.create_item_visual(key)
			dwarf.add_child(prop);entries.append([prop,key])
		dwarf._carry_pose.hold(entries);_view(Vector3(0,1.6,.6),5.6,true)
		caption.text="DEEPDRAFT / TWO FULL-SIZE LOGS / "+String(woods[i]).to_upper()
		await _capture("carry_"+woods[i])
		camera.size=16;await _capture("colony_"+woods[i])
	furniture.free()
	print("TIMBER_REVIEW_OK: four stool/log pairs, 12 stored logs and four two-log carry poses at close/colony scale")
	quit()
