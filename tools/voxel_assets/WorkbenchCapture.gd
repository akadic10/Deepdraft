extends "res://tools/voxel_assets/FurnitureCapture.gd"

func _capture_all() -> void:
	var definition: Dictionary=source.get_defs()["base:furniture:crude_workbench"]
	title_label.text="DEEPDRAFT / WORKBENCH / 1:16 VOXELS / 16 CELLS HIGH"
	var woods:= ["pine","oak","juniper","applewood"]
	for wood in woods:
		_show(definition,"",30,wood);await _capture(wood)
	_show(definition,"",30,"oak")
	var target:=Vector3(40,21.7,40)
	camera.position=target+Vector3(0,24,12);camera.look_at(target)
	await _capture("oak_cut_surface")
	await _working(definition)
	for pair in pairs:pair.free()
	pairs.clear()
	for label in labels:label.hide()
	target=Vector3(40,21.6,40)
	camera.position=target+Vector3(0,12,16);camera.look_at(target);camera.size=12
	caption.text="Bark sides / End grain / Axe scars and chipped rim / Four woods"
	for i in 4:
		var prop: Node3D=source._instance_model("",source._make_solid_material(),definition)
		add_child(prop);prop.position=Vector3(40+(i%2-.5)*5,21,40+(i/2-.5)*6.5)
		CraftMaterials.apply_palette(prop,definition,"base:material:"+woods[i])
		var label:=Label.new();title_label.get_parent().add_child(label)
		label.text=String(woods[i]).capitalize();label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.size=Vector2(260,40);label.add_theme_font_size_override("font_size",24)
		label.position=camera.unproject_position(prop.position+Vector3(0,0,1.7))-Vector2(130,0)
	await _capture("four_woods")
	print("WORKBENCH_REVIEW_OK: four wood variants, opposite views and close surface wear")
	get_tree().quit()

func _working(definition: Dictionary) -> void:
	_show(definition,"",30,"oak")
	var items:=ItemDropManager.new();add_child(items)
	for group in pairs:
		var factory:=DwarfFactory.new()
		var dwarf:=factory.spawn(factory.generate(141,{}),141)
		group.add_child(dwarf);dwarf.set_process(false);dwarf.get_node("Readability").set_process(false)
		dwarf.position=Vector3(0,0,2);dwarf.rotation.y=PI
		var item: Node3D=items.create_item_visual("base:resources:wood:oak_log")
		dwarf.add_child(item)
		item.global_position=group.to_global(Vector3(0,definition.crafting_surface_height,definition.crafting_surface_radius))
		dwarf._felling_pose.apply(.54,dwarf.to_local(item.global_position+Vector3.UP*.875))
	var target:=Vector3(40,22.5,40.5)
	camera.position=target+Vector3(0,17,30);camera.look_at(target);camera.size=8.5
	caption.text="Oak / Working height and tool contact / Opposite views"
	await _capture("in_use_oak")
	items.free()
