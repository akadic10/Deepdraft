extends SceneTree

## Offline art review: fixed cameras and real GLBs, never modifies the live world.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var output := "res://tmp/settlement_art_20261013/chibi_plants_gallery/"
var production := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg=="--production": production=true
	_run.call_deferred()

func _path(species: String, state: String) -> String:
	if species.begins_with("flowers_"): return "assets/models/flora/flowers/"+species+"_"+state+".glb"
	if species.begins_with("reeds_"): return "assets/models/flora/reeds/"+species+"_"+state+".glb"
	return "assets/models/flora/bushes/"+species+"/"+species+"_"+state+".glb"

func _spec(label: String, species: String, state: String, size: float=4.0) -> Dictionary:
	return {"label":label,"models":[[_path(species,state),Vector3.ZERO]],"size":size}

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	root.size=Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(output)
	var hero := [_spec("BLUEBERRY / ripe summer","blueberry","summer"),
		_spec("ELDERBERRY / autumn clusters","elderberry","autumn"),
		_spec("STRAWBERRY / spring flowers and fruit","wild_strawberry","spring",2.6)]
	hero.append({"label":"WILDFLOWERS / three varieties","size":5.0,"models":[
		[_path("flowers_1","summer"),Vector3(-1.4,0,0)],[_path("flowers_2","summer"),Vector3.ZERO],[_path("flowers_3","summer"),Vector3(1.4,0,0)]]})
	hero.append({"label":"REEDS / short and tall","size":4.0,"models":[
		[_path("reeds_1","summer"),Vector3(-.85,0,0)],[_path("reeds_2","autumn"),Vector3(.85,0,0)]]})
	hero.append({"label":"YOUNG / MATURE / PACKED","size":6.2,"models":[
		[_path("blueberry","young_summer"),Vector3(-1.8,0,0)],[_path("blueberry","summer"),Vector3.ZERO],[_path("blueberry","packed_summer"),Vector3(1.8,0,0)]]})
	await _page("hand_hewn_plants",hero,3)
	for species in ["blueberry","elderberry","wild_strawberry"]:
		var seasons := []; var young := []
		for season in ["spring","summer","autumn","winter"]:
			seasons.append(_spec(species+" / "+season,species,season))
			young.append(_spec(species+" / young "+season,species,"young_"+season,2.6))
		await _page(species+"_seasons",seasons,4)
		await _page(species+"_young",young,4)
	var harvest := []
	for pair in [["blueberry","summer"],["elderberry","autumn"],["wild_strawberry","spring"]]:
		for picked in [false,true]:
			harvest.append(_spec(pair[0]+(" / picked" if picked else " / ripe"),pair[0],pair[1]+("_picked" if picked else "")))
	await _page("harvest_pairs",harvest,2)
	var packed := []
	for pair in [["blueberry","summer"],["elderberry","autumn"],["wild_strawberry","spring"],["flowers_1","summer"],["flowers_2","summer"],["flowers_3","summer"]]:
		packed.append(_spec(pair[0]+" / root bundle",pair[0],"packed_"+pair[1]))
	await _page("packed_plants",packed,3)
	for species in ["flowers_1","flowers_2","flowers_3","reeds_1","reeds_2"]:
		var seasons := []
		for season in ["spring","summer","autumn","winter"]:
			seasons.append(_spec(species+" / "+season,species,season,3.0))
		await _page(species+"_seasons",seasons,4)
	await _page("dwarf_scale",[{"label":"UNCHANGED DWARF SCALE / blueberry and elderberry","size":8.0,"dwarf":true,"models":[
		[_path("blueberry","summer"),Vector3(-2,0,0)],[_path("elderberry","autumn"),Vector3(2,0,0)],
		[_path("wild_strawberry","summer"),Vector3(0,0,2)]]}],1)
	print("PLANT_GALLERY_OK: species, young, seasons, harvest, root bundles and actual dwarf scale")
	quit()

func _model(path: String) -> Node3D:
	if production: return (load("res://"+path) as PackedScene).instantiate()
	var document := GLTFDocument.new(); var state := GLTFState.new()
	assert(document.append_from_file("res://tmp/voxel_migration_20261018/staged/"+path,state)==OK)
	return document.generate_scene(state)

func _page(name_: String, specs: Array, columns: int) -> void:
	var canvas := Control.new(); root.add_child(canvas)
	var bg := ColorRect.new(); bg.color=Color("202b29"); bg.size=Vector2(root.size); canvas.add_child(bg)
	var title := Label.new(); title.text="DEEPDRAFT / HEARTHBLOCK PLANTS / "+name_.replace("_"," ").to_upper()
	title.position=Vector2(24,20); title.add_theme_font_size_override("font_size",25); canvas.add_child(title)
	var note := Label.new(); note.text="Actual Godot models  ·  Native 1:16 cells  ·  Fixed framing for before/after review"
	note.position=Vector2(24,958); note.add_theme_font_size_override("font_size",20); canvas.add_child(note)
	var rows := ceili(float(specs.size())/columns)
	var width := 1600/columns; var height := 870/rows
	for i in specs.size():
		var spec: Dictionary=specs[i]
		var host := SubViewportContainer.new(); host.position=Vector2((i%columns)*width+3,(i/columns)*height+70); canvas.add_child(host)
		var viewport := SubViewport.new(); viewport.size=Vector2i(width-6,height-38); viewport.own_world_3d=true
		viewport.msaa_3d=Viewport.MSAA_2X; host.add_child(viewport)
		var env := WorldEnvironment.new(); env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("adb9af")
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color("e2e9e2"); env.environment.ambient_light_energy=.48; viewport.add_child(env)
		var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-32,0)
		sun.light_color=Color("ffe9cb"); sun.light_energy=.9; sun.shadow_enabled=true; viewport.add_child(sun)
		var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(100,100); ground.mesh=plane
		var soil := StandardMaterial3D.new(); soil.albedo_color=Color("959a7f"); ground.material_override=soil; ground.position.y=-.02; viewport.add_child(ground)
		var material := StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=1
		for entry: Array in spec.models:
			var model := _model(entry[0]); viewport.add_child(model); model.position=entry[1]
			assert(Shadows.configure(model)==1)
			for mesh in Shadows.visual_meshes(model): mesh.material_override=material
		if spec.get("dwarf",false):
			var factory=load("res://scripts/entities/DwarfFactory.gd").new()
			var dwarf=factory.spawn(factory.generate(191,{}),9391); viewport.add_child(dwarf)
			dwarf.set_process(false); dwarf.get_node("Readability").set_process(false); dwarf.rotation.y=.3
		var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=spec.size; viewport.add_child(camera)
		# Wide panels use horizontal keep-aspect, tall panels use vertical framing.
		camera.keep_aspect=Camera3D.KEEP_HEIGHT if viewport.size.x>viewport.size.y else Camera3D.KEEP_WIDTH
		var target := Vector3(0,1.05 if spec.size>=4 else .45,0)
		camera.position=target+Vector3(5,4.5,9); camera.look_at(target); camera.current=true
		var label := Label.new(); label.text=spec.label; label.position=host.position+Vector2(9,height-34)
		label.add_theme_font_size_override("font_size",18); canvas.add_child(label)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output+name_+".png")==OK)
	canvas.free()
	for frame in 3: await process_frame
