extends Node3D

## Art-only comparison. Real rigs, terrain IDs, furniture palettes and lighting.
## No world generator, save writes, task execution, or production asset switch.
const Assets = preload("StudyAssets.gd")
const Terrain = preload("res://tools/scale_study/ScaleTerrain.gd")
const Lighting = preload("res://scripts/components/UndergroundLighting.gd")
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
const OUT := "res://tmp/voxel_shadow_study/"
var terrain: Node3D
var lighting: Node
var source: FurniturePlacementController
var wildlife: Node3D
var environment: WorldEnvironment
var look: Environment
var sun: DirectionalLight3D
var camera: Camera3D
var torch: Node3D
var side_torch: Node3D
var variants: Array[Node3D] = []
var small_sets: Array[Node3D] = []
var actors: Array[DwarfAgent] = []
var deer: Array[Node3D] = []
var seats: Array[InstalledFurnitureComponent] = []
var cargo: Array[Node3D] = []
var population: Array[Node3D] = []
var specimens: Array[Dictionary] = []
var neutral: StandardMaterial3D
var heading: Label
var footer: Label
var style := 1
var view := "Close"
var light_mode := "Daylight"
var pose := "Idle"
var phase := .55
var playing := true
var capturing := false
var measuring := false
var proxy_shadows := true
var ready_for_review := false
var orbit := 28.0
var elevation := 22.0
var zoom := 1.0
var _installed := {} # Production sitting pose queries nearby focus furniture.
var report := {"assets": [], "shadow_assets": [], "population": [], "checks": []}
var failures: Array[String] = []

func _ready() -> void:
	capturing = "--capture" in OS.get_cmdline_user_args()
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600,1000)
	get_window().title = "Deepdraft - 1:16 voxel art study"
	SaveManager.configure_storage_for_testing("user://micro_voxel_study")
	WorldGenerator.world_seed = 1234
	for id in ["SaveManager","TaskManager","WorldClock","SkyController","WeatherManager","RoomManager","StockpileManager","WorldEventDirector"]:
		var service := get_tree().root.get_node_or_null(id)
		if service != null: service.set_process(false)
	WorldClock.restore_state({"year":1,"season":"summer","day":1,"hour":12.0,"speed":1,"paused":true})
	_stage()
	for i in 3: await get_tree().process_frame
	for child in get_children():
		if child is DirectionalLight3D and child != sun: child.queue_free()
	environment.environment = look
	source = FurniturePlacementController.new()
	source._load_defs()
	wildlife = load("res://scripts/systems/WildlifeManager.gd").new()
	add_child(wildlife)
	wildlife.set_process(false)
	_build_variants()
	_build_torch()
	_ui()
	_apply_selection()
	for i in 300:
		if not lighting.is_updating(): break
		await get_tree().process_frame
	_check(not lighting.is_updating(),"bounded underground lighting settled")
	_measure_assets()
	ready_for_review = true
	print("MICRO_VOXEL_STUDY_READY: toggle matched current / 1:16 views; isolated profile")
	if capturing: _capture_all.call_deferred()

func _stage() -> void:
	environment = WorldEnvironment.new()
	look = Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color("293A3B")
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("D5E3ED")
	look.ambient_light_energy = .5
	look.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = look.duplicate()
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160
	preload("res://scripts/components/TerrainLighting.gd").configure_sun(sun)
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 400
	add_child(camera)
	camera.make_current()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	neutral = StandardMaterial3D.new()
	neutral.vertex_color_use_as_albedo = true
	neutral.roughness = 1
	terrain = Terrain.new()
	add_child(terrain)
	terrain.create_world()
	lighting = Lighting.new()
	add_child(lighting)
	terrain.excavate_rooms()
	terrain.slice_y = 24
	var material := ShaderMaterial.new()
	material.shader = preload("res://tools/scale_study/review_terrain.gdshader")
	BlockRegistry.configure_terrain_material(material)
	terrain.rebuild(material,neutral,false,false,"shader")

func _build_variants() -> void:
	for variant in 2:
		var root := Node3D.new()
		root.name = "Current" if variant == 0 else "Voxel16"
		add_child(root)
		variants.append(root)
		var group := Node3D.new()
		root.add_child(group)
		small_sets.append(group)
		var saved := Assets.install() if variant == 1 else {}
		var factory := DwarfFactory.new()
		var data := factory.generate(141,{})
		data.gender = "male"
		var appearance := DwarfAppearanceData.new()
		appearance.age_tier="adult"; appearance.gender="male"; appearance.skin_tone="medium"
		appearance.hair_color="brown"; appearance.eye_color="blue"
		appearance.hair_style="short_back"; appearance.beard_style="forked"; appearance.eyebrow_style="thick_flat"
		data.appearance = appearance
		var actor := factory.spawn(data,2210+variant)
		Assets.restore(saved)
		group.add_child(actor)
		actor.position = Vector3(-1,0,0)
		actor.set_process(false)
		actor.get_node("Readability").set_process(false)
		Lighting.bind_world_tree(actor)
		actors.append(actor)
		_record(actor,"dwarf",variant)
		var chair := InstalledFurnitureComponent.new()
		chair.def = source.get_defs()["base:furniture:log_chair"]
		chair.node = _prop(group,"log_chair","stool",Vector3(1.2,0,.7),variant)
		seats.append(chair)
		_record(chair.node,"stool",variant)
		_record(_prop(group,"barrel","barrel",Vector3(-3,0,-.5),variant),"barrel",variant)
		var bush_path := Assets.ROOT+"bush.glb" if variant == 1 else "res://assets/models/flora/bushes/blueberry/blueberry_summer.glb"
		_record(_model(group,bush_path,Vector3(3.4,0,-1)),"bush",variant)
		var old_parts: Dictionary = wildlife._deer_models
		if variant == 1: wildlife._deer_models = Assets.deer_parts()
		var animal: Node3D = wildlife.add_deer("study:"+str(variant),Vector3i(48,21,51),221)
		wildlife._deer_models = old_parts
		animal.reparent(group)
		animal.position = Vector3(6,0,1)
		animal.rotation_degrees.y = 120
		animal.visible = true
		animal.activity="Idle"; animal.hop_progress=1.0; animal.pose_time=0.0
		animal._pose()
		deer.append(animal)
		_record(animal,"deer",variant)
		var tree_path := Assets.ROOT+"pine.glb" if variant == 1 else "res://assets/models/flora/trees/pine/pine_mature.glb"
		_record(_model(root,tree_path,Vector3(58,21,49)),"pine",variant)
		var item := _model(actor,"res://assets/models/items/stone/rough_stone.glb",Vector3.ZERO)
		item.hide()
		cargo.append(item)
		# One world block beside the specimens makes art-cell density unambiguous.
		_box(group,Vector3(-4.6,.5,.5),Vector3.ONE,Color("7D8790"))

func _record(node: Node3D, id: String, variant: int) -> void:
	specimens.append({"node":node,"id":id,"variant":variant})

func _prop(parent: Node3D, id: String, pilot_id: String, at: Vector3, variant: int) -> Node3D:
	var definition: Dictionary = source.get_defs()["base:furniture:"+id]
	var path: String = Assets.ROOT+pilot_id+".glb" if variant == 1 else definition.model
	var node := _model(parent,path,at,false)
	CraftMaterials.apply_palette(node,definition,"base:material:oak")
	Lighting.bind_world_tree(node)
	return node

func _model(parent: Node3D, path: String, at: Vector3, bind := true) -> Node3D:
	var node: Node3D = load(path).instantiate()
	parent.add_child(node)
	node.position = at
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false): mesh.material_override = neutral
	if bind: Lighting.bind_world_tree(node)
	return node

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color=color; material.roughness=1
	node.material_override=material
	parent.add_child(node)

func _build_torch() -> void:
	var definition: Dictionary = source.get_defs()["base:furniture:wooden_torch"]
	torch = _model(self,definition.model,Vector3(40,22.15,36.08),false)
	preload("res://scripts/components/FurnitureLighting.gd").attach(torch,definition)
	for animation in torch.find_children("FlameAnimation","Node",true,false): animation.set_process(false)
	Lighting.bind_world_tree(torch)
	side_torch = _model(self,definition.model,Vector3(43.9,22.15,42.5),false)
	side_torch.rotation.y = -PI/2
	preload("res://scripts/components/FurnitureLighting.gd").attach(side_torch,definition)
	for animation in side_torch.find_children("FlameAnimation","Node",true,false): animation.set_process(false)
	Lighting.bind_world_tree(side_torch)

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position=Vector2(22,18)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	heading=Label.new(); heading.add_theme_font_size_override("font_size",24); column.add_child(heading)
	var row := HBoxContainer.new(); column.add_child(row)
	for option in ["Current","Voxel 1:16"]:
		var value := 0 if option == "Current" else 1
		_button(option,func(): style=value; _apply_selection(),row)
	for option in ["Close","Colony","Pine","Animals","Room","Population"]:
		_button(option,func(): view=option; zoom=1; _apply_selection(),row)
	var row2 := HBoxContainer.new(); column.add_child(row2)
	for option in ["Daylight","Torchlight"]:
		_button(option,func(): light_mode=option; _apply_selection(),row2)
	for option in ["Idle","Walk","Mine","Carry","Sit","Graze"]:
		_button(option,func(): pose=option; _apply_pose(); _refresh(),row2)
	_button("Pause / play",func(): playing=not playing,row2)
	var row3 := HBoxContainer.new(); column.add_child(row3)
	_button("Proxy shadows",func(): proxy_shadows=true; _apply_shadows(),row3)
	_button("Detailed shadows",func(): proxy_shadows=false; _apply_shadows(),row3)
	footer=Label.new(); footer.add_theme_font_size_override("font_size",15); column.add_child(footer)

func _button(text: String, action: Callable, parent: Node) -> void:
	var button := Button.new(); button.text=text; button.pressed.connect(action); parent.add_child(button)

func _apply_selection() -> void:
	if view == "Population" and population.is_empty(): _build_population()
	for i in 2:
		variants[i].visible = i == style and view != "Population"
		small_sets[i].position = Vector3(39.5,21,41) if view == "Room" else Vector3(42,21,50)
		if not population.is_empty(): population[i].visible = i == style and view == "Population"
	terrain.visible = view != "Population"
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color("FFF1D8")
	sun.light_energy=1.15 if light_mode=="Daylight" else 0.0
	look.ambient_light_energy=.5 if light_mode=="Daylight" else .025
	torch.visible = light_mode == "Torchlight"
	side_torch.visible = light_mode == "Torchlight"
	# The same production torch is moved with the selected review location.
	torch.position = Vector3(40,22.15,36.08) if view == "Room" else Vector3(42,22.15,46)
	side_torch.position = Vector3(43.9,22.15,42.5) if view == "Room" else Vector3(47,22.15,52)
	_apply_pose()
	_apply_shadows()
	_update_camera()
	_refresh()

func _update_camera() -> void:
	var target := Vector3(43,22.9,50)
	var extent := 8.8
	match view:
		"Colony": target=Vector3(47,27,46); extent=38
		"Pine": target=Vector3(58,30.5,49); extent=24
		"Animals": target=Vector3(48,22.7,51); extent=6.2
		"Room": target=Vector3(39.5,22.8,41); extent=9.5
		"Population": target=Vector3(150,27,150); extent=120
	var pitch := deg_to_rad(35 if view in ["Colony","Population","Room"] else elevation)
	var yaw := deg_to_rad(orbit)
	camera.size=extent*zoom
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*160
	camera.look_at(target)

func _refresh() -> void:
	if heading == null: return
	heading.text = "DEEPDRAFT  /  %s  /  %s" % ["CURRENT FACETED ART" if style==0 else "VOXEL ART · 16 CELLS PER BLOCK",view.to_upper()]
	footer.text = "%s · %s · A/B: Tab · Orbit: drag · Zoom: wheel · Esc: close\nSame scale, camera and lighting. Art study; simulation is paused." % [light_mode,pose]
	footer.text += "\nVoxel shadow geometry: "+("coarse proxy" if proxy_shadows else "detailed mesh")

func _apply_shadows() -> void:
	for root in variants: Shadows.configure(root,proxy_shadows)
	for root in population: Shadows.configure(root,proxy_shadows)
	_refresh()

func _apply_pose() -> void:
	for i in actors.size():
		var actor := actors[i]
		actor.position=Vector3(-1,0,0)
		actor._reset_part_offsets()
		cargo[i].hide()
		match pose:
			"Walk": actor._walk_cycle=phase*TAU; actor._walk_bob(0)
			"Mine": actor._mining_pose.apply(phase,Vector3(0,1.6,1.4))
			"Carry": cargo[i].show(); actor._carry_pose.hold([[cargo[i],"base:resources:stone:rough_stone"]],sin(phase*TAU)*.02)
			"Sit":
				actor.position=seats[i].node.position
				actor._idle_behavior.seat=seats[i]
				actor._idle_behavior._furniture=self
				actor._idle_behavior._sitting_blend=1
				actor._idle_behavior.elapsed=phase*2
				actor._idle_behavior._pose()
		deer[i].activity="Grazing" if pose=="Graze" else "Idle"
		deer[i].hop_progress=phase if pose=="Walk" else 1.0
		deer[i].pose_time=phase*2
		deer[i]._pose()

func _process(delta: float) -> void:
	if not ready_for_review or capturing or measuring: return
	if playing:
		phase=fmod(phase+delta*.5,1)
		_apply_pose()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: get_tree().quit()
		if event.keycode==KEY_TAB: style=1-style; _apply_selection()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		orbit-=event.relative.x*.3; elevation=clampf(elevation+event.relative.y*.2,5,70); _update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom=maxf(.4,zoom*.9); _update_camera()
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom=minf(3,zoom/ .9); _update_camera()

func _measure_assets() -> void:
	for spec in specimens:
		var node: Node3D = spec.node
		var triangles := 0
		var shadow_triangles := 0
		var proxy_count := 0
		var roles_valid := true
		var surfaces := 0
		var bounds := AABB()
		var first := true
		var grid_valid := true
		var cubic := true
		var max_grid_error := 0.0
		var max_normal_error := 0.0
		for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null or not _part_visible(mesh,node): continue
			if Shadows.is_proxy(mesh):
				proxy_count+=1
				var visual := mesh.get_parent().get_node("VoxelVisual") as MeshInstance3D
				roles_valid = roles_valid and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
					and visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mesh.transform.is_equal_approx(visual.transform)
				roles_valid = roles_valid and mesh.find_children("OccludedSilhouette","MeshInstance3D",true,false).is_empty()
				for surface in mesh.mesh.get_surface_count():
					shadow_triangles+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
				continue
			var transform := node.global_transform.affine_inverse()*mesh.global_transform
			cubic = cubic and transform.basis.get_scale().abs().is_equal_approx(Vector3.ONE)
			var quantization := mesh.get_aabb().size*16.0/65535.0+Vector3.ONE*.0001
			var box := transform*mesh.get_aabb()
			bounds=box if first else bounds.merge(box)
			first=false
			for surface in mesh.mesh.get_surface_count():
				surfaces+=1
				var arrays := mesh.mesh.surface_get_arrays(surface)
				triangles += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
				if spec.variant == 1:
					for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
						var error := (vertex*16-(vertex*16).round()).abs()
						max_grid_error=maxf(max_grid_error,error.length())
						grid_valid=grid_valid and error.x<=quantization.x and error.y<=quantization.y and error.z<=quantization.z
					for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
						max_normal_error=maxf(max_normal_error,(normal-normal.round()).length())
						grid_valid=grid_valid and is_equal_approx(normal.round().length(),1.0)
		report.assets.append({"style":spec.variant,"id":spec.id,"triangles":triangles,"surfaces":surfaces,"size":[bounds.size.x,bounds.size.y,bounds.size.z]})
		_check(triangles>0,"%s/%s imported geometry" % [spec.variant,spec.id])
		if spec.variant == 1:
			_check(roles_valid and proxy_count==surfaces,"%s has one shadow-only sibling per visible mesh, shared pivots, no proxy silhouettes" % spec.id)
			report.shadow_assets.append({"id":spec.id,"visual_triangles":triangles,"shadow_triangles":shadow_triangles,"proxy_meshes":proxy_count})
			print("IMPORTED_GRID ",spec.id," vertex_error_cells=",max_grid_error," normal_error=",max_normal_error," cubic=",cubic)
			# The source GLB is exact. Godot's default importer quantizes positions
			# across the mesh AABB into 16-bit UNORM and compresses normal frames.
			# Allow one position quantization interval and <0.00025 normal error.
			_check(grid_valid and cubic and max_normal_error<.00025,"%s imported 1:16 grid within compression precision; axis normals and unit scale" % spec.id)
			report.assets[-1].max_grid_error_cells=max_grid_error
			report.assets[-1].max_normal_error=max_normal_error
			if spec.id in ["dwarf","stool","barrel","pine"]:
				var heights := {"dwarf":3.3125,"stool":.75,"barrel":1.0,"pine":20.0}
				_check(is_equal_approx(bounds.size.y,heights[spec.id]) and absf(bounds.position.y)<.001,"%s grounded height contract" % spec.id)
	_check(actors[1]._head.scale.is_equal_approx(Vector3.ONE) and actors[1]._body.scale.is_equal_approx(Vector3.ONE),"voxel head/body retain cubic cells")
	_check(is_equal_approx(float(DwarfAssets.get_proportions().body_width),.8),"production proportions restored after assembly")
	report.renderer=RenderingServer.get_video_adapter_name()
	report.rendering_method=RenderingServer.get_current_rendering_method()
	report.driver=RenderingServer.get_current_rendering_driver_name()
	report.resolution=[get_viewport().size.x,get_viewport().size.y]
	report.vsync=DisplayServer.window_get_vsync_mode()
	report.terrain_fingerprint=terrain.fingerprint()

func _build_population() -> void:
	# Render-only snapshots, including the actual articulated rest transforms.
	# 96 dwarves, 96 deer, 288 props, 24 pines = 504 objects per style.
	for variant in 2:
		var root := Node3D.new(); add_child(root); population.append(root)
		_box(root,Vector3(150,20.5,150),Vector3(110,1,100),Color("667563"))
		for index in 96:
			var origin := Vector3(105+(index%12)*8,21,112+(index/12)*10)
			for spec in specimens:
				if spec.variant!=variant or (spec.id=="pine" and index%4!=0): continue
				var node: Node3D = spec.node
				var part_copies := {}
				var offset := Vector3(-2,0,-3) if spec.id=="pine" else node.position
				for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
					# Keep disabled proxies so entering Population in detailed-shadow
					# mode still permits switching back to proxy shadows later.
					if not _part_visible(mesh,node) and not Shadows.is_proxy(mesh): continue
					var copy := MeshInstance3D.new()
					copy.name=mesh.name
					copy.mesh=mesh.mesh
					copy.material_override=mesh.material_override
					copy.cast_shadow=mesh.cast_shadow
					copy.gi_mode=mesh.gi_mode
					for surface in mesh.mesh.get_surface_count(): copy.set_surface_override_material(surface,mesh.get_surface_override_material(surface))
					var parent := mesh.get_parent()
					if not part_copies.has(parent):
						part_copies[parent]=Node3D.new()
						root.add_child(part_copies[parent])
					part_copies[parent].add_child(copy)
					copy.transform=Transform3D(node.basis,origin+offset)*node.global_transform.affine_inverse()*mesh.global_transform
		root.hide()

func _part_visible(mesh: Node3D, root: Node3D) -> bool:
	var node: Node = mesh
	while node != root:
		if node is Node3D and not node.visible: return false
		node = node.get_parent()
	return true

func _check(ok: bool, message: String) -> void:
	report.checks.append({"ok":ok,"message":message})
	if not ok: failures.append(message); push_error("MICRO_VOXEL_CHECK: "+message)

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	playing=false
	_check_shadow_component()
	for selected in ["Close","Colony","Pine","Animals","Room"]:
		view=selected; pose="Idle"; light_mode="Torchlight" if view=="Room" else "Daylight"
		for variant in 2:
			style=variant; _apply_selection()
			await _capture(selected.to_lower()+"_"+str(variant))
	view="Close"; style=1; light_mode="Daylight"
	for selected in ["Walk","Mine","Carry","Sit"]:
		pose=selected
		for point in [.2,.55,.92]:
			phase=point; _apply_selection()
			_check_shadow_pose(selected+" "+str(point))
			await _capture(selected.to_lower()+"_%02d" % roundi(point*100))
	view="Animals"; pose="Graze"; phase=.55; _apply_selection(); await _capture("graze")
	_check_shadow_pose("Graze")
	await _check_proxy_invisible()
	# Compare the same detailed voxel art with only its shadow geometry changed.
	pose="Idle"; style=1
	for selected in ["Pine","Close","Room"]:
		view=selected; light_mode="Torchlight" if view=="Room" else "Daylight"
		for enabled in [false,true]:
			proxy_shadows=enabled; _apply_selection()
			await _capture("shadow_"+selected.to_lower()+"_"+("proxy" if enabled else "detailed"))
	proxy_shadows=false
	pose="Idle"; view="Close"; _apply_selection()
	# Build snapshots with both styles visible. Restore selection immediately.
	for root in variants: root.show()
	_build_population()
	var expected_pairs := 96*(10+9+1+1+1)+24
	_check(Shadows.configure(population[1])==expected_pairs,"population built with detailed shadows retains all %d proxy pairs for toggling" % expected_pairs)
	view="Population"; light_mode="Daylight"
	for mode in ["current","voxel_detailed","voxel_proxy"]:
		style=0 if mode=="current" else 1
		proxy_shadows=mode!="voxel_detailed"
		_apply_selection()
		for i in 90: await get_tree().process_frame
		var samples: Array[float] = []
		var gpu_samples: Array[float] = []
		var cpu_samples: Array[float] = []
		var previous := Time.get_ticks_usec()
		for i in 120:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0); previous=now
			gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			cpu_samples.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		samples.sort()
		gpu_samples.sort(); cpu_samples.sort()
		report.population.append({"style":style,"shadow_mode":mode,"objects":504,"samples":120,"frame_median_ms":samples[60],"frame_p95_ms":samples[114],"gpu_median_ms":gpu_samples[60],"gpu_p95_ms":gpu_samples[114],"render_cpu_median_ms":cpu_samples[60],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"note":"Render-only static snapshots; VSync retained. Not a simulation or low-end hardware benchmark."})
		await _capture("population_"+mode)
	_check(terrain.fingerprint()==report.terrain_fingerprint,"poses and comparisons leave fixture terrain unchanged")
	var file := FileAccess.open(OUT+"native_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("MICRO_VOXEL_STUDY_CAPTURE_OK: native matched views, poses, population; ",failures.size()," failed checks")
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_shadow_component() -> void:
	# A raw GLB plus the component must work without the world lighting loader.
	var fixture: Node3D = load(Assets.ROOT+"pine.glb").instantiate()
	fixture.hide()
	fixture.add_child(Shadows.new())
	add_child(fixture)
	var visual := fixture.find_child("VoxelVisual",true,false) as MeshInstance3D
	var proxy := fixture.find_child("VoxelShadowProxy",true,false) as MeshInstance3D
	_check(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and proxy.visible,"standalone component configures visual Off and proxy Shadows Only")
	_check(Shadows.configure(fixture)==1 and Shadows.configure(fixture)==1,"repeated setup is idempotent")
	Shadows.configure(fixture,false)
	_check(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not proxy.visible,"detailed-shadow comparison restores visual casting and hides proxy")
	var unrelated := MeshInstance3D.new()
	unrelated.mesh=BoxMesh.new()
	unrelated.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	fixture.add_child(unrelated)
	Shadows.configure(fixture)
	_check(unrelated.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,"setup leaves unrelated meshes unchanged")
	fixture.free()

func _check_shadow_pose(label: String) -> void:
	var valid := true
	var pairs := 0
	for actor in [actors[1],deer[1]]:
		for proxy: MeshInstance3D in actor.find_children("VoxelShadowProxy","MeshInstance3D",true,false):
			var visual := proxy.get_parent().get_node("VoxelVisual") as MeshInstance3D
			valid=valid and proxy.global_transform.is_equal_approx(visual.global_transform)
			pairs+=1
	_check(valid and pairs==19,"all 19 dwarf/deer proxies follow actual rig pose: "+label)

func _check_proxy_invisible() -> void:
	# With light shadows disabled, toggling proxies must not change visible pixels.
	view="Close"; pose="Idle"; light_mode="Daylight"; _apply_selection()
	var lights := {}
	for light: Light3D in find_children("*","Light3D",true,false):
		lights[light]=light.shadow_enabled
		light.shadow_enabled=false
	for layer: CanvasLayer in find_children("*","CanvasLayer",true,false): layer.hide()
	var pictures: Array[Image] = []
	for enabled in [false,true]:
		proxy_shadows=enabled; _apply_shadows()
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		pictures.append(get_viewport().get_texture().get_image())
	_check(pictures[0].get_data()==pictures[1].get_data(),"proxy visibility has zero pixel effect when light shadows are disabled")
	for light in lights: light.shadow_enabled=lights[light]
	for layer: CanvasLayer in find_children("*","CanvasLayer",true,false): layer.show()

func _capture(id: String) -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT+id+".png")

func _exit_tree() -> void:
	if source != null: source.free()
