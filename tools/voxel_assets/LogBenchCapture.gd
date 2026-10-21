extends "res://tools/voxel_assets/FurnitureCapture.gd"

func _capture_all() -> void:
	var definition: Dictionary = source.get_defs()["base:furniture:bench"]
	title_label.text = "DEEPDRAFT / CHIBI LOG BENCH"
	for wood in ["oak","pine","juniper","applewood"]:
		_show(definition,"",30,wood)
		caption.text += " · 1 × 2 floor cells · native 1:16 voxels"
		await _capture("bench_"+wood)
		if wood=="oak":
			_floor_cells()
			await _capture("bench_footprint")
			camera.size *= 1.8
			caption.text = "Log bench · colony distance"
			await _capture("bench_colony")
	for angle in [30.0,90.0]:
		_show(definition,"Sit",angle,"oak")
		await _capture("bench_seated_"+str(int(angle)))
	for pair in pairs: pair.free()
	pairs.clear()
	for label in labels: label.hide()
	caption.text = "One shape · four woods · two-cell footprint"
	var center := Vector3(40,21.6,40)
	camera.position = center+Vector3(0,5,8)
	camera.look_at(center)
	camera.size = 7.2
	var woods := ["oak","pine","juniper","applewood"]
	for i in woods.size():
		var prop: Node3D = source._instance_model("",source._make_solid_material(),definition)
		add_child(prop)
		prop.position = Vector3(40+(i-1.5)*2.6,21,40)
		CraftMaterials.apply_palette(prop,definition,"base:material:"+woods[i])
		var label := Label.new()
		title_label.get_parent().add_child(label)
		label.text = woods[i].capitalize()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(220,40)
		label.add_theme_font_size_override("font_size",24)
		label.position = camera.unproject_position(prop.position+Vector3(0,-.05,.8))-Vector2(110,0)
	await _capture("bench_four_woods")
	print("LOG_BENCH_REVIEW_OK: four woods, footprint, colony distance and seated views")
	get_tree().quit()

func _floor_cells() -> void:
	for pair in pairs:
		for i in 2:
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(.98,.06,.98)
			tile.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("677F88") if i==0 else Color("8198A0")
			tile.material_override = material
			pair.add_child(tile)
			tile.position = Vector3(i-.5,-.025,0)
