extends SceneTree

## Native pre-activation review of staged GLBs using Godot's glTF importer.
## Each contact-sheet cell is an independent lit viewport; no production override.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var output := "res://tmp/settlement_art_20261013/voxel_gallery/"
var source := "res://tmp/voxel_migration_20261018/staged/"
var only := ""
var family := "trees"
var failures: Array[String] = []
var checked := 0
var hashes := {}
var no_lod := false
var double_sided := false
var no_proxy := false
var rows := 3
var categories := PackedStringArray()

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
		if arg.begins_with("--family="): family=arg.trim_prefix("--family=")
		if arg=="--production": source="res://"
		if arg=="--no-lod": no_lod=true
		if arg=="--double-sided": double_sided=true
		if arg=="--no-proxy": no_proxy=true
		if arg.begins_with("--rows="): rows=clampi(arg.trim_prefix("--rows=").to_int(),1,4)
		if arg.begins_with("--categories="): categories=arg.trim_prefix("--categories=").split(",")
	_run.call_deferred()

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	root.size=Vector2i(1600,maxi(1000,54+rows*310))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var paths: Array[String] = []
	var bases := ["assets/models/flora/trees/"] if family=="trees" else ["assets/models/"+family+"/"]
	if family=="plants": bases=["assets/models/flora/bushes/","assets/models/flora/flowers/","assets/models/flora/reeds/"]
	if family=="crops": bases=["assets/models/flora/crops/"]
	if family=="dwarves": bases=["assets/models/characters/dwarves/"]
	if family=="wildlife": bases=["assets/models/animals/"]
	for base: String in bases: _collect(source+base,paths)
	paths.sort()
	if paths.is_empty(): push_error("Empty gallery selection"); quit(1); return
	var page_size := rows*4
	for page in range(ceili(float(paths.size())/page_size)):
		var canvas := Control.new()
		root.add_child(canvas)
		var backdrop := ColorRect.new()
		backdrop.color=Color("182322")
		backdrop.size=Vector2(root.size)
		canvas.add_child(backdrop)
		var heading := Label.new()
		heading.text="DEEPDRAFT  /  1:16 "+family.to_upper()+"  /  %d"%(page+1)
		heading.position=Vector2(22,12)
		heading.add_theme_font_size_override("font_size",23)
		canvas.add_child(heading)
		for slot in range(page_size):
			var index := page*page_size+slot
			if index>=paths.size(): break
			var cell := Control.new()
			cell.position=Vector2((slot%4)*400,54+(slot/4)*310)
			canvas.add_child(cell)
			var model: Node3D
			if source=="res://":
				var packed := load(paths[index]) as PackedScene
				if packed!=null: model=packed.instantiate() as Node3D
			else:
				var document := GLTFDocument.new()
				var state := GLTFState.new()
				if document.append_from_file(paths[index],state)==OK:
					model=document.generate_scene(state) as Node3D
			if model==null:
				failures.append("Cannot import "+paths[index]); continue
			if Shadows.configure(model)<1 and family!="presentation" and not "/animations/" in paths[index]: failures.append("No proxy pair: "+paths[index])
			if no_proxy: Shadows.set_casting(model,false)
			var viewport := SubViewport.new()
			viewport.size=Vector2i(396,274)
			viewport.own_world_3d=true
			viewport.msaa_3d=Viewport.MSAA_2X
			if no_lod: viewport.mesh_lod_threshold=0
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			var display := TextureRect.new()
			display.size=Vector2(396,274)
			cell.add_child(display)
			display.add_child(viewport)
			display.texture=viewport.get_texture()
			viewport.add_child(model)
			var bounds := AABB()
			var first := true
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo=true
			material.roughness=1
			if double_sided: material.cull_mode=BaseMaterial3D.CULL_DISABLED
			for mesh in Shadows.visual_meshes(model):
				mesh.material_override=material
				var box: AABB = model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
				bounds=box if first else bounds.merge(box)
				first=false
				if mesh.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: failures.append("Visual casts: "+paths[index])
			checked+=1
			hashes[paths[index].trim_prefix(source)]=FileAccess.get_sha256(paths[index])
			var environment := WorldEnvironment.new()
			environment.environment=Environment.new()
			environment.environment.background_mode=Environment.BG_COLOR
			environment.environment.background_color=Color("293a39")
			environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color=Color("d6e2df")
			environment.environment.ambient_light_energy=.55
			viewport.add_child(environment)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees=Vector3(-48,-32,0)
			sun.light_color=Color("ffe4bf")
			sun.light_energy=1.0
			sun.shadow_enabled=true
			sun.directional_shadow_max_distance=100
			viewport.add_child(sun)
			var ground := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size=Vector2.ONE*maxf(12,bounds.size.length()*2)
			ground.mesh=plane
			var soil := StandardMaterial3D.new()
			soil.albedo_color=Color("71846b")
			ground.material_override=soil
			ground.position.y=bounds.position.y-.015
			viewport.add_child(ground)
			var camera := Camera3D.new()
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL
			viewport.add_child(camera)
			camera.position=bounds.get_center()+Vector3(1,.5,1.5).normalized()*60
			camera.look_at(bounds.get_center())
			var projected := Vector2.ZERO
			for corner in range(8):
				var p: Vector3 = camera.basis.inverse()*(bounds.get_endpoint(corner)-bounds.get_center())
				projected.x=maxf(projected.x,absf(p.x)*2)
				projected.y=maxf(projected.y,absf(p.y)*2)
			camera.size=maxf(projected.y,projected.x/(396.0/274))*1.18
			camera.current=true
			var title := Label.new()
			title.text=paths[index].get_file().get_basename()+"  ·  %.1fm"%bounds.size.y
			title.position=Vector2(10,278)
			title.size=Vector2(380,28)
			title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			title.add_theme_font_size_override("font_size",13)
			cell.add_child(title)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"gallery_%02d.png"%page)
		canvas.free()
	FileAccess.open(output+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify({"count":checked,"source":source,"paths":paths,"hashes":hashes,"failures":failures},"  "))
	print("VOXEL_GALLERY_PASS " if failures.is_empty() else "VOXEL_GALLERY_FAIL ",checked)
	quit(0 if failures.is_empty() else 1)

func _collect(path: String, result: Array[String]) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".glb") and (only.is_empty() or only in file) and (categories.is_empty() or path.trim_suffix("/").get_file() in categories): result.append(path.path_join(file))
	for directory in DirAccess.get_directories_at(path): _collect(path.path_join(directory),result)
