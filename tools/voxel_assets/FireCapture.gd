extends "res://tools/voxel_assets/FurnitureCapture.gd"

## Native installed flames, including every animated frame and both light levels.
const FIRE_NAMES := ["campfire","wooden_torch","hearth"]

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	title_label.text="DEEPDRAFT / VOXEL FIRE"
	for id: String in FIRE_NAMES:
		var definition: Dictionary=source.get_defs()["base:furniture:"+id]
		for night: bool in [false,true]:
			sun.light_energy=.04 if night else 1.15
			look.ambient_light_energy=.035 if night else .65
			_show(definition)
			caption.text=String(definition.display_name)+(" · night" if night else " · daylight")
			await _save(id+("_night" if night else "_day"))
		# Step through the actual owner's timing rather than swapping meshes
		# manually. Each tile shows native front/back views of one clip frame.
		sun.light_energy=.60; look.ambient_light_energy=.28
		_show(definition)
		var durations: Array=definition.light_source.flame_animation.frame_durations
		var sheet := Image.create(1280,200*ceili(durations.size()/4.0),false,Image.FORMAT_RGBA8)
		var time := 0.0
		for frame in durations.size():
			for pair: Node3D in pairs:
				var animation: Node=pair.find_child("FlameAnimation",true,false)
				animation._elapsed=time+float(durations[frame])*.5
				animation._apply_sample()
				assert(animation._frame_index==frame)
			caption.text=String(definition.display_name)+" · frame "+str(frame+1)
			for i in 3: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var tile := get_viewport().get_texture().get_image()
			tile.convert(Image.FORMAT_RGBA8); tile.resize(320,200,Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(tile,Rect2i(0,0,320,200),Vector2i((frame%4)*320,(frame/4)*200))
			time+=float(durations[frame])
		assert(sheet.save_png(output+id+"_frames.png")==OK)
	print("FIRE_CAPTURE_OK: three installed sources, day/night and all live animation frames")
	get_tree().quit()

func _save(id: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(output+id+".png")==OK)
