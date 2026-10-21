extends "res://tools/voxel_assets/FurnitureCapture.gd"

func _capture_all() -> void:
	var definition: Dictionary=source.get_defs()["base:furniture:log_table"]
	title_label.text="DEEPDRAFT / LOG DINING TABLE / NATIVE 1:16 VOXELS"
	var woods:= ["pine","oak","juniper","applewood"]
	for wood in woods:
		_show(definition,"",30,wood);await _capture(wood)
	_show(definition,"",30,"oak")
	var target:=Vector3(40,21.65,40)
	camera.position=target+Vector3(0,4,30);camera.look_at(target)
	caption.text="Oak / Authored four-cell tabletop / Centered 16 x 16 x 16 log pedestal"
	await _capture("pedestal")
	for pair in pairs:pair.free()
	pairs.clear()
	for label in labels:label.hide()
	var group:=Node3D.new();add_child(group)
	var prop: Node3D=source._instance_model("",source._make_solid_material(),definition)
	group.add_child(prop);prop.position=Vector3(40,21,40)
	CraftMaterials.apply_palette(prop,definition,"base:material:oak")
	var stool_def: Dictionary=source.get_defs()["base:furniture:log_chair"]
	for slot in definition.seating.slots:
		var stool: Node3D=source._instance_model("",source._make_solid_material(),stool_def)
		group.add_child(stool);stool.position=prop.position+Vector3(slot.chair_origin[0]-1,0,slot.chair_origin[1]-1)
		stool.rotation.y=slot.yaw*PI*.5;CraftMaterials.apply_palette(stool,stool_def,"base:material:oak")
	target=Vector3(40,21.6,40);camera.position=target+Vector3(12,12,16);camera.look_at(target);camera.size=10
	caption.text="Oak / Four separate log stools / Complete 5 x 5 dining layout"
	var grid:=ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 6:
		grid.surface_add_vertex(Vector3(37.5+i,21.01,37.5));grid.surface_add_vertex(Vector3(37.5+i,21.01,42.5))
		grid.surface_add_vertex(Vector3(37.5,21.01,37.5+i));grid.surface_add_vertex(Vector3(42.5,21.01,37.5+i))
	grid.surface_end()
	var lines:=MeshInstance3D.new();lines.mesh=grid;group.add_child(lines)
	var line_material:=StandardMaterial3D.new();line_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color=Color("647744");lines.material_override=line_material
	lines.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _capture("with_stools");group.free()
	camera.position=target+Vector3(0,12,16);camera.look_at(target);camera.size=12
	caption.text="Player-authored tabletop / 16-cell pedestal / Centered in a 3 x 3 space"
	for i in 4:
		prop=source._instance_model("",source._make_solid_material(),definition)
		add_child(prop);prop.position=Vector3(40+(i%2-.5)*5,21,40+(i/2-.5)*6.5)
		CraftMaterials.apply_palette(prop,definition,"base:material:"+woods[i])
		var label:=Label.new();title_label.get_parent().add_child(label)
		label.text=String(woods[i]).capitalize();label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.size=Vector2(260,40);label.add_theme_font_size_override("font_size",24)
		label.position=camera.unproject_position(prop.position+Vector3(0,0,1.7))-Vector2(130,0)
	await _capture("four_woods")
	print("LOG_TABLE_REVIEW_OK: four woods, opposite views, pedestal and separate stools")
	get_tree().quit()
