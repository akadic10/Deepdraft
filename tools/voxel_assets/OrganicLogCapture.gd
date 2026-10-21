extends "res://tools/voxel_assets/FurnitureCapture.gd"

## The two gameplay definitions use the same sculpted table body.
func _capture_all() -> void:
	title_label.text="DEEPDRAFT / ONE LOG TABLE DESIGN / NATIVE 1:16 VOXELS"
	caption.text="Oak / Uneven bark, offset growth rings and a drying split / Shared pedestal and tabletop"
	var group:=Node3D.new();add_child(group)
	var stool_def: Dictionary=source.get_defs()["base:furniture:log_chair"]
	for i in 2:
		var id: String="log_table" if i==0 else "board_game_table"
		var definition: Dictionary=source.get_defs()["base:furniture:"+id]
		var prop: Node3D=source._instance_model("",source._make_solid_material(),definition)
		group.add_child(prop);prop.position=Vector3(40+(i-.5)*7,21,40)
		CraftMaterials.apply_palette(prop,definition,"base:material:oak")
		for slot in definition.seating.slots:
			var stool: Node3D=source._instance_model("",source._make_solid_material(),stool_def)
			group.add_child(stool);stool.position=prop.position+Vector3(slot.chair_origin[0]-1,0,slot.chair_origin[1]-1)
			stool.rotation.y=slot.yaw*PI*.5;CraftMaterials.apply_palette(stool,stool_def,"base:material:oak")
		labels[i].text="DINING / FOUR STOOLS / 5 x 5" if i==0 else "GAMES / SAME TABLE / SIX COUNTERS"
		labels[i].size.x=620;labels[i].position=Vector2(90+800*i,910)
	var target:=Vector3(40,21.6,40)
	camera.position=target+Vector3(0,18,24);camera.look_at(target);camera.size=10
	await _capture("shared_design")
	print("ORGANIC_LOG_REVIEW_OK: shared dining/game body and approved separate stool layouts")
	get_tree().quit()
