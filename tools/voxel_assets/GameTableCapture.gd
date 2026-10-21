extends "res://tools/voxel_assets/FurnitureCapture.gd"

func _capture_all() -> void:
	var definition: Dictionary=source.get_defs()["base:furniture:board_game_table"]
	title_label.text="DEEPDRAFT / LOG GAME TABLE / 1:16 VOXELS / SHARED DINING TABLE"
	var woods:= ["pine","oak","juniper","applewood"]
	for wood in woods:
		_show(definition,"",30,wood);await _capture(wood)
	_show(definition,"",30,"oak")
	var target:=Vector3(40,21.7,40)
	camera.position=target+Vector3(0,24,12);camera.look_at(target)
	caption.text="Oak / Scratched board / Three dark and three light stone counters"
	await _capture("oak_board")
	for pair in pairs:pair.free()
	pairs.clear()
	for label in labels:label.hide()
	target=Vector3(40,21.6,40)
	camera.position=target+Vector3(0,12,16);camera.look_at(target);camera.size=12
	caption.text="Shared 46 x 46-cell tabletop / 20-cell pedestal table / Six game pieces"
	for i in 4:
		var prop: Node3D=source._instance_model("",source._make_solid_material(),definition)
		add_child(prop);prop.position=Vector3(40+(i%2-.5)*5,21,40+(i/2-.5)*6.5)
		CraftMaterials.apply_palette(prop,definition,"base:material:"+woods[i])
		var label:=Label.new();title_label.get_parent().add_child(label)
		label.text=String(woods[i]).capitalize();label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.size=Vector2(260,40);label.add_theme_font_size_override("font_size",24)
		label.position=camera.unproject_position(prop.position+Vector3(0,0,1.7))-Vector2(130,0)
	await _capture("four_woods")
	print("GAME_TABLE_REVIEW_OK: four woods, opposite views and close board/counters")
	get_tree().quit()
