extends SceneTree

## Matched native views: actual-sized staged/installed trees beside a real dwarf.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var output := "res://tmp/settlement_art_20261013/chibi_trees_gallery/"
var production := false
var definitions := {}

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg=="--production": production=true
	_run.call_deferred()

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	root.size=Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(output)
	# The real flora owner remains the sole definition loader.
	var flora=load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	root.add_child(flora); flora.set_process(false)
	for definition: Dictionary in flora._species: definitions[definition.name]=definition
	await _lineup()
	for stage in ["mature","ancient","sapling"]:
		var specs := []
		for species in ["pine","oak","apple","juniper"]: specs.append([species,stage,"summer",false])
		await _page(stage+"_species",specs,11.0 if stage=="sapling" else (33.0 if stage=="ancient" else 25.0))
	for species in ["pine","oak","apple","juniper"]:
		var specs := []
		for season in ["spring","summer","autumn","winter"]: specs.append([species,"mature",season,false])
		await _page(species+"_seasons",specs,25.0 if species=="pine" else 22.0)
	await _page("juniper_harvest",[["juniper","mature","summer",false],["juniper","mature","summer",true],
		["juniper","mature","winter",false],["juniper","mature","winter",true]],18.0)
	print("TREE_GALLERY_OK: species, all growth stages, seasons, fruit/picked and scale dwarf")
	quit()

func _model(spec: Array) -> Node3D:
	var stage: Dictionary=definitions[spec[0]].stages[spec[1]]
	var models: Dictionary=stage.get("picked_models",stage.models) if spec[3] else stage.models
	var season: String=spec[2]
	if season=="autumn" and models.has("autumn_fruiting"): season="autumn_fruiting"
	var paths=models.get(season,models.summer)
	var path: String=paths if paths is String else paths[0]
	if production: return (load(path) as PackedScene).instantiate()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(path.replace("res://","res://tmp/voxel_migration_20261018/staged/"),state)==OK)
	return document.generate_scene(state)

func _lineup() -> void:
	var world := Node3D.new(); root.add_child(world)
	var ui := CanvasLayer.new(); root.add_child(ui)
	var title := Label.new(); title.text="DEEPDRAFT / HEARTHBLOCK TREES"
	title.add_theme_color_override("font_color",Color("202b26"))
	title.position=Vector2(28,22); title.add_theme_font_size_override("font_size",30); ui.add_child(title)
	var note := Label.new(); note.text="Actual Godot models  ·  Native 1:16 cells  ·  Existing dwarves shown at unchanged scale"
	note.add_theme_color_override("font_color",Color("202b26"))
	note.position=Vector2(28,950); note.add_theme_font_size_override("font_size",21); ui.add_child(note)
	var environment := WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("b3c9c8")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("dce4e4"); environment.environment.ambient_light_energy=.48
	world.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-48,-32,0)
	light.light_color=Color("ffe9cb"); light.light_energy=.9; light.shadow_enabled=true
	light.directional_shadow_max_distance=100; world.add_child(light)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(180,180)
	ground.mesh=plane; var soil := StandardMaterial3D.new(); soil.albedo_color=Color("a3a38e")
	ground.material_override=soil; ground.position.y=-.03; world.add_child(ground)
	var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=31; world.add_child(camera)
	var target := Vector3(2,8,0); camera.position=target+Vector3(10,14,38); camera.look_at(target); camera.current=true
	var material := StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=1
	var locations := [-15.0,-2.0,10.0,20.0]
	var species := ["pine","oak","apple","juniper"]
	for i in species.size():
		var model := _model([species[i],"mature","summer",false]); world.add_child(model)
		model.position.x=locations[i]; assert(Shadows.configure(model)==1)
		for mesh in Shadows.visual_meshes(model): mesh.material_override=material
		var factory=load("res://scripts/entities/DwarfFactory.gd").new()
		var dwarf=factory.spawn(factory.generate(191,{}),9291+i); world.add_child(dwarf)
		dwarf.set_process(false); dwarf.get_node("Readability").set_process(false)
		var footprint: float=float(definitions[species[i]].placement.footprint.mature)
		dwarf.position=Vector3(locations[i]+footprint*.5+1.2,0,3); dwarf.rotation.y=.35
		var label := Label.new(); label.text=String(species[i]).to_upper()
		label.add_theme_color_override("font_color",Color("202b26"))
		label.position=camera.unproject_position(Vector3(locations[i],0,4))+Vector2(-25,32)
		label.add_theme_font_size_override("font_size",24); ui.add_child(label)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output+"lineup.png")==OK)
	ui.free(); world.free()
	for frame in 3: await process_frame

func _page(label: String,specs: Array,size: float) -> void:
	var canvas := Control.new(); root.add_child(canvas)
	var backdrop := ColorRect.new(); backdrop.color=Color("182322"); backdrop.size=Vector2(root.size); canvas.add_child(backdrop)
	var title := Label.new(); title.text="DEEPDRAFT / HEARTHBLOCK TREES / "+label.replace("_"," ").to_upper()
	title.position=Vector2(24,20); title.add_theme_font_size_override("font_size",25); canvas.add_child(title)
	var note := Label.new(); note.text="Actual Godot render  ·  1 cell = 1/16 block  ·  Existing dwarf shown at unchanged scale"
	note.position=Vector2(24,956); note.add_theme_font_size_override("font_size",19); canvas.add_child(note)
	for i in specs.size():
		var spec: Array=specs[i]
		var host := SubViewportContainer.new(); host.position=Vector2(i*400+3,72); canvas.add_child(host)
		var viewport := SubViewport.new(); viewport.size=Vector2i(394,812); viewport.own_world_3d=true
		host.add_child(viewport)
		var environment := WorldEnvironment.new(); environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color("b3c9c8")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color("dce4e4"); environment.environment.ambient_light_energy=.48
		viewport.add_child(environment)
		var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-48,-32,0)
		light.light_color=Color("ffe9cb"); light.light_energy=.9; light.shadow_enabled=true
		light.directional_shadow_max_distance=100; viewport.add_child(light)
		var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(160,160)
		ground.mesh=plane; var soil := StandardMaterial3D.new(); soil.albedo_color=Color("819375")
		ground.material_override=soil; ground.position.y=-.03; viewport.add_child(ground)
		var model := _model(spec); viewport.add_child(model); assert(Shadows.configure(model)==1)
		var material := StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=1
		for mesh in Shadows.visual_meshes(model): mesh.material_override=material
		var factory=load("res://scripts/entities/DwarfFactory.gd").new()
		var dwarf=factory.spawn(factory.generate(191,{}),9191+i); viewport.add_child(dwarf)
		dwarf.set_process(false); dwarf.get_node("Readability").set_process(false)
		var footprint: float=float(definitions[spec[0]].placement.footprint[spec[1]])
		dwarf.position=Vector3(footprint*.5+1.5,0,2.0); dwarf.rotation.y=.35
		var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		# Fixed framing per species/stage fits both the earlier broad canopy and
		# the new crown; before/after captures use exactly the same camera.
		var framing: float=size
		if spec[0]=="oak": framing=maxf(size,34.0 if spec[1]=="mature" else (50.0 if spec[1]=="ancient" else 12.0))
		if spec[0]=="apple": framing=maxf(size,28.0 if spec[1]=="mature" else (44.0 if spec[1]=="ancient" else 11.0))
		camera.size=framing; viewport.add_child(camera)
		var target := Vector3(0,framing*.33,0); camera.position=target+Vector3(18,14,32); camera.look_at(target); camera.current=true
		var caption := Label.new(); caption.text=(String(spec[0])+" / "+String(spec[1])+" / "+String(spec[2]))+(" / picked" if spec[3] else "")
		caption.position=Vector2(i*400+12,900); caption.add_theme_font_size_override("font_size",17); canvas.add_child(caption)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output+label+".png")==OK)
	canvas.free()
	for frame in 3: await process_frame
