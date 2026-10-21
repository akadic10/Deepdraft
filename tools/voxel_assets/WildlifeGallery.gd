extends SceneTree

const Shadows=preload("res://scripts/components/VoxelShadowSetup.gd")
var output := "res://tmp/settlement_art_20261013/wildlife_roster/"

static func stage_models(owner: Node) -> void:
	for table_name in ["_models","_deer_models","_wolf_models","_duck_models"]:
		var table: Dictionary=owner.get(table_name)
		for key in table:
			var path: String=table[key].resource_path
			var doc:=GLTFDocument.new()
			var state:=GLTFState.new()
			assert(doc.append_from_file(path.replace("res://","res://tmp/voxel_migration_20261018/staged/"),state)==OK)
			var node:=doc.generate_scene(state)
			var packed:=PackedScene.new()
			assert(packed.pack(node)==OK)
			packed.take_over_path(path)
			table[key]=packed
			node.free()

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	for node in root.get_children(): node.set_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var holder:=Node3D.new(); root.add_child(holder); current_scene=holder
	var wildlife=load("res://scripts/systems/WildlifeManager.gd").new()
	holder.add_child(wildlife); wildlife.set_process(false)
	if not "--production" in OS.get_cmdline_user_args(): stage_models(wildlife)
	for kind in ["rabbit","deer","wolf","duck_male","duck_female"]:
		var species: String=kind.split("_")[0]
		var canvas:=Control.new(); root.add_child(canvas)
		var backdrop:=ColorRect.new(); backdrop.color=Color("182322"); backdrop.size=Vector2(1600,1000); canvas.add_child(backdrop)
		var heading:=Label.new(); heading.text="DEEPDRAFT / 1:16 / "+kind.to_upper(); heading.position=Vector2(22,12); heading.add_theme_font_size_override("font_size",23); canvas.add_child(heading)
		for slot in 12:
			var cell:=Control.new(); cell.position=Vector2((slot%4)*400,54+(slot/4)*310); canvas.add_child(cell)
			var vp:=SubViewport.new(); vp.size=Vector2i(396,274); vp.own_world_3d=true; vp.msaa_3d=Viewport.MSAA_2X
			vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			var display:=TextureRect.new(); display.size=Vector2(396,274); cell.add_child(display); display.add_child(vp); display.texture=vp.get_texture()
			var actor=load("res://scripts/entities/"+species.capitalize()+"Agent.gd").new()
			vp.add_child(actor)
			if species=="duck": actor.navigation=wildlife.duck_navigation
			var definition: Dictionary=wildlife.get("definition" if species=="rabbit" else species+"_definition")
			var models: Dictionary=wildlife.get("_models" if species=="rabbit" else "_"+species+"_models")
			actor.configure(definition,"gallery:"+str(slot),Vector3i(40,21,40),155,models)
			actor.position=Vector3.ZERO
			actor.activity="Sleeping" if slot in [7,8] else "Eating" if slot==6 and species=="wolf" else "Grazing" if slot==6 else "Wandering" if slot in [4,5] else "Idle"
			actor.hop_progress=.25 if slot==4 else .75 if slot==5 else 1.0
			actor.pose_time=float(slot)*.3
			if species=="duck":
				actor.sex=kind.split("_")[1]; actor.mode="land"
				if slot>=9:
					actor.mode="air"; actor.activity="Flying"; actor.flight_index=2
					actor.flight=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
			actor._pose()
			Shadows.configure(actor)
			var bounds:=AABB(); var first:=true
			for mesh in Shadows.visual_meshes(actor.visual):
				if not mesh.is_visible_in_tree(): continue
				var b: AABB=mesh.global_transform*mesh.get_aabb()
				bounds=b if first else bounds.merge(b); first=false
			var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
			environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("293a39")
			environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color=Color("d6e2df"); environment.environment.ambient_light_energy=.55; vp.add_child(environment)
			var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-32,0); sun.light_color=Color("ffe4bf"); sun.shadow_enabled=true; sun.directional_shadow_max_distance=30; vp.add_child(sun)
			var ground:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(20,20); ground.mesh=plane
			var soil:=StandardMaterial3D.new(); soil.albedo_color=Color("71846b"); ground.material_override=soil; ground.position.y=-.015; vp.add_child(ground)
			var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; vp.add_child(camera)
			var direction:=Vector3(1,.5,-1.5)
			if slot in [1,8]: direction=Vector3(1,.25,0)
			if slot==2: direction=Vector3(1,.5,1.5)
			if slot==3: direction=Vector3(0,.2,-1)
			camera.position=bounds.get_center()+direction.normalized()*20; camera.look_at(bounds.get_center())
			camera.size=maxf(bounds.size.y,bounds.size.length()*.74)*1.18
			if slot==11 and species!="duck": camera.size*=2.5
			camera.current=true
			var title:=Label.new(); title.text=actor.activity+" / "+["¾ front","side","rear","front","stride A","stride B","feeding","rest","rest side","pose","pose","RTS"][slot]
			title.position=Vector2(10,278); title.add_theme_font_size_override("font_size",13); cell.add_child(title)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+kind+".png")
		canvas.free()
	print("WILDLIFE_GALLERY_PASS 5 species/sex pages, 60 views")
	quit()
