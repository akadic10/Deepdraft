extends "res://scripts/tests/RoomLightingTest.gd"

var xray
var slice
var mining
var builder
var hud
var base: Vector3i

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("X-ray test timed out"); quit(1))
	review_output = "res://tmp/xray_20261017/view/"
	DirAccess.make_dir_recursive_absolute(review_output)
	root.get_node("SaveManager").configure_storage_for_testing("user://xray_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(960,540)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	await _settle()
	while current_scene.get_node("WorldLoadingScreen").visible: await process_frame
	base = _find_cliff()-Vector3i(0,6,0)
	_expect(base.x>=0,"fixture cliff exists")
	if base.x<0: quit(1); return
	xray = current_scene.get_node("XrayController")
	slice = current_scene.get_node("SliceController")
	mining = current_scene.get_node("MiningDesignationController")
	builder = current_scene.get_node("ConstructionController")
	furniture = current_scene.get_node("FurniturePlacementController")
	hud = current_scene.get_node("DockUI")._time_slice_hud
	_expect(not hud.xray_panel.get_global_rect().intersects(hud.row.get_global_rect()),"compact startup lays out X-ray before any resize")
	root.size = Vector2i(1280,720)
	for i in range(5): await process_frame
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	camera.position = Vector3(base)+Vector3(22,35,32)
	camera.look_at(Vector3(base)+Vector3(9,3,6))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12)
	var air: Array[Vector3i] = []
	for x in range(2,18):
		for z in range(2,12):
			for y in range(1,10):
				if (x<=13 and z<=9 and y<=4) or (x>=6 and z>=4 and y>=6) or (x>=3 and x<=8 and z in [6,7]):
					air.append(base+Vector3i(x,y,z))
	mining._mine_blocks_world(air)
	var rock_key: String = root.get_node("BlockRegistry").get_key(generator.construction_stone_id(base))
	for step in range(5):
		for y in range(1,step+2):
			for z in [6,7]: builder._place_block(base+Vector3i(3+step,y,z),rock_key)
	var step_cell := base+Vector3i(5,3,6)
	_expect(not root.get_node("InteriorTracker").contains_air(step_cell),"constructed steps are removed from interior air")
	var stool_id := _install("base:furniture:log_chair",base+Vector3i(3,0,3))
	_install("base:furniture:wooden_torch",base+Vector3i(2,0,3),1)
	slice.show_at_height(base.y+4)
	await _settle()
	var original_mask := camera.cull_mask
	var original_environment := camera.environment
	var physical_shell: Mesh = renderer._cavity_shell_node.mesh
	_click_hud(hud.xray_button)
	await _xray_settle()
	_expect(renderer._cavity_shell_node.mesh==physical_shell,"inspection chunk uploads retain the unchanged physical terrain shell")
	_expect(xray.mode=="full" and slice.is_active(),"X-ray button enables Full without disabling slice")
	_expect(xray.reference_y==base.y+4,"enabling X-ray pins current reference level")
	_expect(camera.cull_mask==xray.XRAY_LAYER,"inspection camera hides the bulk terrain")
	_expect(furniture.find_children("*","OmniLight3D",true,false).any(func(light): return light.layers&xray.XRAY_LAYER!=0),"inspection retains installed light sources")
	var floor_target := base+Vector3i(3,0,3)
	var direct_hit: Dictionary = load("res://scripts/components/ObjectPicking.gd").terrain_hit(
		Vector3(floor_target)+Vector3(.5,30,.5),Vector3.DOWN,slice.get_slice_y(),60,Callable(),xray.is_terrain_face_visible)
	_expect(not direct_hit.is_empty() and Vector3i(direct_hit.x,direct_hit.y,direct_hit.z)==floor_target,"inspection picks the visible floor through hidden overburden")
	_expect(not xray.is_terrain_face_visible(base+Vector3i(1,1,3),Vector3i.UP),"hidden tops of shell walls cannot intercept selection")
	await _review_capture("lower_full")
	_click_hud(hud.step_buttons.up_four)
	_click_hud(hud.step_buttons.up_one)
	await _xray_settle()
	_expect(slice.get_slice_y()==base.y+9 and xray.reference_y==base.y+4,"raising slice preserves the lower reference")
	_expect(xray._reference.visible and xray._reference.mesh!=null,"lower room outline survives overlapping upper floor")
	var vertices: PackedVector3Array = xray._reference.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(Array(vertices).all(func(v: Vector3): return absf(v.y-(base.y+10.025))<.001),"reference projects vertically onto the current working plane")
	_expect(xray.is_terrain_visible(base+Vector3i(3,0,3)),"lower known floor belongs to Full shell")
	_expect(not xray.is_terrain_visible(base+Vector3i(30,0,30)),"unexcavated rock is absent from X-ray")
	var full_vertices := _vertex_count("full")
	await _review_capture("stacked_full")
	await _check_slice_cache()
	var full_meshes := _shell_meshes("full")
	var flat_meshes := _shell_meshes("flat")
	physical_shell = renderer._cavity_shell_node.mesh
	_click_hud(hud.xray_modes.flat)
	_expect(xray._dirty.is_empty() and xray._job.is_empty(),"Full to Flat switches cached meshes without queuing terrain work")
	await _xray_settle()
	_expect(_shell_meshes("full")==full_meshes and _shell_meshes("flat")==flat_meshes,"Full and Flat retain their mesh resources across a mode switch")
	_expect(renderer._cavity_shell_node.mesh==physical_shell,"mode switching does not rebuild physical terrain")
	_expect(xray.mode=="flat" and _vertex_count("flat")<full_vertices,"Flat removes tall wall faces")
	await _review_capture("stacked_flat")
	# A fixture plant outside all excavations is excluded from this camera.
	var outside := MeshInstance3D.new()
	outside.mesh = BoxMesh.new()
	current_scene.add_child(outside)
	outside.position = Vector3(base)+Vector3(25,2,4)
	for i in range(30): await process_frame
	_expect(outside.layers&xray.XRAY_LAYER==0,"outdoor props stay out of underground inspection")
	var stool: Node3D = furniture._installed[stool_id].node
	_expect(stool.find_children("*","MeshInstance3D",true,false).any(func(node): return node.layers&xray.XRAY_LAYER!=0),"known interior furniture remains visible")
	var picker = load("res://scripts/components/ObjectPicking.gd").new()
	_expect(picker.hit_distance(outside,outside.position+Vector3.UP*10,outside.position-Vector3.UP*10)==INF,"hidden props cannot intercept selection")
	var stool_bounds: AABB = picker.world_bounds(stool)
	_expect(picker.hit_distance(stool,stool_bounds.get_center()+Vector3.UP*10,stool_bounds.get_center()-Vector3.UP*10)<INF,"visible furniture remains selectable")
	var water = root.get_node("WaterManager")
	water.set_process(false)
	var pool := base+Vector3i(10,1,3)
	var reference_mesh: Mesh = xray._reference.mesh
	full_meshes = _shell_meshes("full")
	flat_meshes = _shell_meshes("flat")
	var water_added: float = water.flow.add_at(pool,.5,pool.y+1)
	print("XRAY_POOL ",pool," added=",water_added," depth=",water.depth_at(pool)," known=",root.get_node("InteriorTracker").contains_air(pool))
	water._flush_changes()
	await _xray_settle()
	_expect(_vertex_count("water")>0,"known pools remain visible in underground inspection")
	_expect(_shell_meshes("full")==full_meshes and _shell_meshes("flat")==flat_meshes,"water uploads preserve both terrain meshes")
	_expect(xray._reference.mesh==reference_mesh and renderer._cavity_shell_node.mesh==physical_shell,"water updates preserve the guide and physical shadow geometry")
	var wet_mesh: ArrayMesh = xray._chunks[Vector3i(pool.x>>4,pool.y>>4,pool.z>>4)].water.mesh
	var wet_vertices: PackedVector3Array = wet_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if wet_mesh!=null else PackedVector3Array()
	_expect(Array(wet_vertices).any(func(v: Vector3): return absf(v.y-(pool.y+.5))<.001 and int(v.x)==pool.x),"inspection water follows the live fractional height")
	water.flow.remove_at(pool,.5,pool.y)
	water._flush_changes()
	await _xray_settle()
	_expect(_vertex_count("water")==0,"draining the pool removes its inspection surface")
	# A dormant slice variant must see water changes when revisited.
	var pool_level: int = slice.get_slice_y()
	slice.show_at_height(pool.y)
	await _xray_settle()
	slice.show_at_height(pool_level)
	await _xray_settle()
	water.flow.add_at(pool,.5,pool.y+1)
	water._flush_changes()
	await _xray_settle()
	slice.show_at_height(pool.y)
	await _xray_settle()
	_expect(_vertex_count("water")>0,"cached lower slice refreshes water added while it was dormant")
	xray.set_mode("off")
	water.flow.remove_at(pool,.5,pool.y)
	water._flush_changes()
	xray.set_mode("flat")
	await _xray_settle()
	_expect(_vertex_count("water")==0,"water draining while X-ray is off invalidates cached water")
	slice.show_at_height(pool_level)
	await _xray_settle()
	_expect(_vertex_count("water")==0,"other cached slices also retire drained water")
	# Working tools restore actual terrain and normal picking, while the guide
	# stays visual-only and cannot alter the mined or construction data.
	mining._on_tool_requested("mine_precision")
	await _xray_settle()
	_expect(xray.working and camera.cull_mask==original_mask,"mining restores the real work slice")
	_expect(xray._reference.visible,"lower guide remains visible while mining")
	var target := base+Vector3i(15,9,2)
	var point := camera.unproject_position(Vector3(target)+Vector3(.5,1,.5))
	var hit: Dictionary = mining._raycast_voxel(point)
	_expect(not hit.is_empty() and hit.block_pos.y==slice.get_slice_y(),"mining hits current slice rock rather than the lower reference")
	await _review_capture("mining_reference")
	mining._deactivate_tool()
	builder._on_tool_requested("construct_stone")
	await _xray_settle()
	_expect(xray.working and camera.cull_mask==original_mask,"construction also keeps real terrain and references")
	var mined_count: int = mining._mined_blocks.size()
	var built_count: int = root.get_node("WorldData").serialize_edits().size()
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1680,720),Vector2i(2560,720)]:
		root.size = size
		for i in range(10): await process_frame
		var bounds := Rect2(Vector2.ZERO,Vector2(size))
		for rect in hud.occupied_rects():
			_expect(bounds.encloses(rect),"X-ray controls fit %s" % size)
			_expect(not rect.intersects(current_scene.get_node("DockUI")._dock_panel.get_global_rect()),"X-ray controls clear dock %s" % size)
		_expect(not hud.xray_panel.get_global_rect().intersects(hud.row.get_global_rect()),"X-ray controls clear time row %s" % size)
		await _review_capture("working_%d" % size.x)
	_expect(mining._mined_blocks.size()==mined_count and root.get_node("WorldData").serialize_edits().size()==built_count,"view changes never edit world data")
	builder._on_tool_requested("construct_stone")
	await _xray_settle()
	_expect(xray.is_inspecting(),"closing work returns to chosen Flat inspection")
	# Build and then mine another step while the view is active.
	var added := base+Vector3i(4,1,3)
	builder._place_block(added,rock_key)
	await _xray_settle()
	_expect(xray.is_terrain_visible(added),"new constructed stone appears in the active shell")
	var removed: Array[Vector3i] = [added]
	mining._mine_blocks_world(removed)
	await _xray_settle()
	_expect(not xray.is_terrain_visible(added),"removed construction retires its shell face")
	_expect(renderer._cavity_shell_node.mesh!=physical_shell,"actual slice and terrain changes still rebuild the physical shell")
	xray.set_mode("off")
	builder._place_block(added,rock_key)
	xray.set_mode("flat")
	await _xray_settle()
	_expect(xray.is_terrain_visible(added),"terrain edited while X-ray is off refreshes cached geometry")
	mining._mine_blocks_world(removed)
	await _xray_settle()
	_click_hud(hud.reference_toggle)
	await process_frame
	_expect(not xray._reference.visible,"lower reference can be hidden independently")
	_click_hud(hud.reference_toggle)
	_click_hud(hud.reference_pin)
	await _xray_settle()
	_expect(xray.reference_y==slice.get_slice_y() and not xray._reference.visible,"pinning the current level updates and hides the coplanar reference")
	_click_hud(hud.step_buttons.up_one)
	await _xray_settle()
	_expect(xray._reference.visible,"new pinned reference appears after stepping upward")
	_click_hud(hud.xray_button)
	await process_frame
	_expect(xray.mode=="off" and camera.cull_mask==original_mask and not xray._reference.visible,"turning X-ray off restores camera and hides references")
	_expect(camera.environment==original_environment,"turning X-ray off restores normal atmosphere")
	outside.free()
	FileAccess.open(review_output+"checks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"full_vertices":full_vertices,"flat_vertices":_vertex_count("flat"),"base":str(base)},"  "))
	for failure in failures: push_error(failure)
	print("XRAY_VIEW_OK" if failures.is_empty() else "XRAY_VIEW_FAIL")
	quit(0 if failures.is_empty() else 1)

func _click_hud(button: BaseButton) -> void:
	var at := button.get_global_rect().get_center()
	_mouse(at,true)
	_mouse(at,false)

func _xray_settle() -> void:
	await _settle()
	for i in range(5): await process_frame
	while not xray._job.is_empty() or not xray._dirty.is_empty() or not xray._scan.is_empty() or xray._reference_dirty: await process_frame
	for i in range(5): await process_frame

func _vertex_count(kind: String) -> int:
	var count := 0
	for entry in xray._chunks.values():
		var mesh: ArrayMesh = entry[kind].mesh
		if mesh!=null: count += mesh.surface_get_array_len(0)
	return count

func _shell_meshes(kind: String) -> Dictionary:
	var result := {}
	for key in xray._chunks: result[key] = xray._chunks[key][kind].mesh
	return result

func _check_slice_cache() -> void:
	var height: int = slice.get_slice_y()
	var meshes := _shell_meshes("full")
	var reference: Mesh = xray._reference.mesh
	slice.show_at_height(height)
	_expect(xray._dirty.is_empty() and xray._job.is_empty() and xray._reference.mesh==reference,"same-height slice notification does not invalidate geometry")
	slice.deactivate()
	var retained := 0
	for key in meshes:
		if xray._variant_level(key,height)==xray._variant_level(key,127):
			retained += 1
			_expect(xray._chunks.has(key) and xray._chunks[key].full.mesh==meshes[key],"slice off immediately retains an unaffected chunk")
	_expect(retained>0,"fixture includes fully visible chunks below the cutoff")
	await _xray_settle()
	var all_meshes := _shell_meshes("full")
	for i in 3:
		slice.activate()
		_expect(xray._dirty.is_empty() and xray._job.is_empty(),"returning to the cached slice schedules zero mesh rebuilds")
		_expect(_shell_meshes("full")==meshes,"slice on restores the exact previous meshes immediately")
		for key in xray._chunks:
			_expect(xray._chunks[key].full.visible,"restored chunks are visible before another frame")
		slice.deactivate()
		_expect(xray._dirty.is_empty() and _shell_meshes("full")==all_meshes,"repeated slice off reuses the full-height view")
	slice.activate()
	await _xray_settle()
	xray.set_mode("off")
	xray.set_mode("full")
	_expect(xray._dirty.is_empty() and _shell_meshes("full")==meshes,"X-ray off/on reuses unchanged geometry")
	await _xray_settle()
	# Several intermediate heights cannot grow the cache indefinitely.
	for offset in [1,2,3,4]:
		slice.show_at_height(height+offset)
		await _xray_settle()
		for cache in xray._chunk_cache.values():
			_expect(cache.size()<=xray.CACHED_LEVELS_PER_CHUNK,"slice cache stays bounded")
	slice.show_at_height(height)
	await _xray_settle()
