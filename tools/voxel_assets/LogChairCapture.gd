extends "res://tools/voxel_assets/FurnitureCapture.gd"

func _capture_all() -> void:
	var definition: Dictionary=source.get_defs()["base:furniture:log_chair"]
	for wood in ["pine","oak","juniper","applewood"]:
		_show(definition,"",30,wood);await _capture(wood)
		for angle in [30.0,90.0]:
			_show(definition,"Sit",angle,wood)
			await _capture(wood+"_seated_"+str(int(angle)))
	for pair in pairs: pair.free()
	pairs.clear()
	for label in labels: label.hide()
	title_label.text="DEEPDRAFT / PLAYER LOG STOOL / FOUR WOODS"
	caption.text="Original shape · Bark exterior · Cut wood and growth rings"
	var center:=Vector3(40,21.4,40)
	camera.position=center+Vector3(0,4,6);camera.look_at(center);camera.size=4
	var woods: Array[String]=["pine","oak","juniper","applewood"]
	for i in woods.size():
		var prop: Node3D=source._instance_model("",source._make_solid_material(),definition)
		add_child(prop);prop.position=Vector3(40+(i-1.5)*1.5,21,40)
		CraftMaterials.apply_palette(prop,definition,"base:material:"+woods[i])
		var label:=Label.new();title_label.get_parent().add_child(label)
		label.text=woods[i].capitalize();label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.size=Vector2(260,40);label.add_theme_font_size_override("font_size",24)
		label.position=camera.unproject_position(prop.position+Vector3(0,-.05,.8))-Vector2(130,0)
	await _capture("four_woods")
	print("LOG_CHAIR_REVIEW_OK: four material variants, opposite views and eight seated views")
	get_tree().quit()
