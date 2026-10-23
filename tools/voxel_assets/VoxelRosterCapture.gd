extends "res://tools/DwarfRosterPreview.gd"

var output := "res://tmp/settlement_art_20261013/dwarves_roster_gallery/"

func _title_text() -> String:
	return "DEEPDRAFT / 1:16 DWARF ROSTER"

func _page(specs: Array) -> void:
	for actor in _actors: actor.free()
	_actors.clear()
	for i in specs.size():
		var spec: Array = specs[i]
		var actor := _make_actor(spec)
		actor.position.x=(float(i)-1.5)*3.7
		_lineup.add_child(actor)
		actor.get_node("Readability").set_process(false)
		_actors.append(actor)
		_labels[i].text="VOXEL / "+String(spec[7])
	_set_view("Three-quarter")

func _spec(gender: String, hair: String, beard := "", age := "adult", brow := "thick_flat", label := "") -> Array:
	return [gender,hair,beard,age,"medium","brown",brow,label if label!="" else hair]

func _capture_all() -> void:
	SaveManager.configure_storage_for_testing("user://dwarf_voxel_review")
	_validate_registry()
	DirAccess.make_dir_recursive_absolute(output)
	var pages := []
	for keys in [["bun","braid_side","braid_long","short_practical"],
		["twin_braids","half_up","loose_long","shaved_sides"],
		["cropped","wild","bun","braid_side"]]:
		var specs := []
		for key in keys: specs.append(_spec("female",key))
		pages.append(specs)
	var males := []
	for key in ["short_back","shaved","wild_loose","braided_back"]: males.append(_spec("male",key))
	pages.append(males)
	for keys in [["full_long","full_braided","short_trimmed","forked"],
		["mutton_chops","goatee","braided_long",""]]:
		var specs := []
		for key in keys: specs.append(_spec("male","short_back",key,"adult","thick_flat",key if key!="" else "No beard"))
		pages.append(specs)
	var ages := []
	for key in ["young","adult","middle","elder"]: ages.append(_spec("male","bald","",key,"arched",key))
	pages.append(ages)
	for gender in ["male","female"]:
		var specs := []
		var table: Dictionary = DwarfAssets.brows_male if gender=="male" else DwarfAssets.brows_female
		for key in table: specs.append(_spec(gender,"shaved" if gender=="male" else "cropped","","adult",key,key))
		pages.append(specs)
	for i in pages.size():
		_page(pages[i])
		await _snapshot("voxel_page_%02d"%i)
		var studio_lights := get_children().filter(func(node): return node is DirectionalLight3D)
		for light in studio_lights: light.visible=false
		var studio_environment: Environment=get_children().filter(func(node): return node is WorldEnvironment)[0].environment
		studio_environment.ambient_light_energy=.08
		var torch := OmniLight3D.new()
		torch.position=Vector3(0,3.0,4.0)
		torch.light_color=Color("ffb45e")
		torch.light_energy=5.0
		torch.omni_range=20
		torch.shadow_enabled=true
		add_child(torch)
		await _snapshot("voxel_torch_%02d"%i)
		torch.free()
		studio_environment.ambient_light_energy=.4
		for light in studio_lights: light.visible=true
		if i<6:
			_set_view("Rear")
			await _snapshot("voxel_rear_%02d"%i)
	_page(pages[1])
	_set_view("RTS")
	await _snapshot("colony")
	for i in _actors.size():
		var actor := _actors[i] as DwarfAgent
		actor.appearance.scar=DwarfAssets.scars.keys()[i]
		actor.appearance.skin_tone=DwarfAssets.SKIN_TONES.keys()[i]
		actor.appearance.hair_color=["red","black","blonde","white"][i]
		actor._rig.apply_tints()
		var texture := TextureRect.new()
		add_child(texture)
		var viewport := preload("res://scripts/ui/DwarfPortrait.gd").create_viewport(texture,Vector2i(384,448))
		preload("res://scripts/ui/DwarfPortrait.gd").create_model(viewport,actor)
		for j in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output+"portrait_%d.png"%i)
		texture.free()
	_page([
		["male","short_back","full_long","adult","medium","red","thick_flat","Swept locks / full beard"],
		["female","twin_braids","","adult","tan","black","thin_arched","Twin braids"],
		["male","wild_loose","forked","elder","dark","white","bushy","Elder / forked beard"],
		["female","cropped","","young","pale","blonde","sharp_angled","Cropped fringe"],
	])
	await _snapshot("hand_hewn_lineup")
	_page([_spec("female","bun"),_spec("female","loose_long"),
		_spec("male","braided_back","full_long"),_spec("male","wild_loose","braided_long")])
	for pose in ["walk","mine","fell","rest"]:
		for actor in _actors:
			actor._reset_part_offsets()
			match pose:
				"walk": actor._walk_cycle=.55; actor._movement.walk_bob(0)
				"mine": actor._mining_pose.apply(.55,Vector3(0,1.2,1.4))
				"fell": actor._felling_pose.apply(.55,Vector3(0,1.2,1.4))
				"rest":
					actor._rest_behavior.pose="lying"; actor._rest_behavior.blend=1
					actor._rest_behavior._apply_pose()
		_set_view("Three-quarter")
		await _snapshot("pose_"+pose)
	print("DWARF_VOXEL_CAPTURE_OK: complete roster, production views and production portraits")
	get_tree().quit()

func _snapshot(capture_name: String) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().root.size=Vector2i(1600,1000)
	for i in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(output+capture_name+".png")==OK)

func _make_actor(spec: Array) -> DwarfAgent:
	var actor := super._make_actor(spec)
	preload("res://scripts/components/VoxelShadowSetup.gd").configure(actor)
	for mesh in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(actor):
		if mesh.material_override is StandardMaterial3D: mesh.material_override.cull_mode=BaseMaterial3D.CULL_BACK
	return actor

func _validate_registry() -> void:
	# The 800-combination native fixture runs headless. Creating/freeing all of
	# them synchronously here exhausts D3D12 descriptors before a render flush.
	for table in [DwarfAssets.heads,DwarfAssets.hair_female,DwarfAssets.beards,DwarfAssets.scars]:
		for packed in table.values(): assert(packed!=null)

