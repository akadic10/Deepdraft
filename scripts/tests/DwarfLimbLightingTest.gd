extends SceneTree

const OUT := "res://tmp/dwarf_limb_lighting_20261013/"
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Dwarf limb lighting test requires native rendering"); quit(1); return
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	root.size=Vector2i(1400,850)
	var scene := Node3D.new()
	root.add_child(scene); current_scene=scene
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.07,.08,.10)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=.2
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,0,0)
	light.light_energy=1.0
	light.shadow_enabled=false
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6.5
	scene.add_child(camera)
	camera.position=Vector3(40,24.5,51)
	camera.look_at(Vector3(40,22.4,40))
	var lighting = load("res://scripts/components/UndergroundLighting.gd").new()
	scene.add_child(lighting); lighting.set_process(false)
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var actors := []
	for i in 2:
		var data: Dictionary=factory.generate(191,{})
		data.appearance.skin_tone="medium"
		var actor = factory.spawn(data,800+i)
		scene.add_child(actor); actor.set_process(false)
		actor.get_node("Readability").set_process(false)
		actor.position=Vector3(38 if i==0 else 42,21,40)
		if i==1:
			lighting.bind_tree(actor)
			for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
				if mesh.name!="OccludedSilhouette": mesh.set_instance_shader_parameter("actor_sky_access",1.0)
		actors.append(actor)
	for i in 8: await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var results := []
	var torches := []
	for actor in actors:
		var torch := OmniLight3D.new()
		torch.light_color=Color("ffb45e")
		torch.light_energy=4.0
		torch.omni_range=4.0
		scene.add_child(torch)
		torch.position=actor.position+Vector3(0,1.6,2)
		torches.append(torch)
	for mode in ["daylight","torch"]:
		light.visible=mode=="daylight"
		for torch in torches: torch.visible=mode=="torch"
		if mode=="torch": environment.environment.ambient_light_energy=0.0
		for skin in ["medium","pale","tan","dark"]:
			for i in actors.size():
				var actor = actors[i]
				actor.appearance.skin_tone=skin
				actor._apply_tints()
				if i==1:
					lighting.bind_tree(actor)
					for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
						if mesh.name!="OccludedSilhouette": mesh.set_instance_shader_parameter("actor_sky_access",1.0 if mode=="daylight" else 0.0)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			if skin=="medium": picture.save_png(OUT+label+("" if mode=="daylight" else "_torch")+".png")
			results.append({"lighting":mode,"skin":skin,"actors":_compare(camera,actors,picture)})
	var report:=FileAccess.open(OUT+label+".json",FileAccess.WRITE)
	report.store_string(JSON.stringify(results,"\t"))
	for failure in failures: push_error(failure)
	print("DWARF_LIMB_LIGHTING_OK: 32 paired color samples, all skin tones, daylight and torchlight" if failures.is_empty() else "DWARF_LIMB_LIGHTING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _compare(camera: Camera3D, actors: Array, picture: Image) -> Array:
	var results := []
	for i in actors.size():
		var actor = actors[i]
		var row := {"material":"standard" if i==0 else "world","samples":[]}
		for pair in [[actor._hand_l,actor._hand_r,Vector3(1.09,1.255,.335)],
			[actor._foot_l,actor._foot_r,Vector3(.5,.20,.50)]]:
			var colors := []
			for part: Node3D in [pair[0],pair[1]]:
				var screen := camera.unproject_position(part.to_global(pair[2]))
				colors.append(picture.get_pixelv(Vector2i(screen.round())))
			var difference: float = maxf(absf(colors[0].r-colors[1].r),maxf(absf(colors[0].g-colors[1].g),absf(colors[0].b-colors[1].b)))
			row.samples.append({"part":pair[0].name,"left":colors[0],"right":colors[1],"difference":difference})
			if difference>.025: failures.append("%s %s colors differ by %.3f"%[row.material,pair[0].name,difference])
		results.append(row)
	return results
