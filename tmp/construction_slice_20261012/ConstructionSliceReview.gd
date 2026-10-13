extends "res://tools/UndergroundWorldReview.gd"

const REVIEW_DIR := "res://tmp/construction_slice_20261012/"
var builder
var camera: Camera3D
var registry
var samples: Array = []
var baseline := "--baseline" in OS.get_cmdline_user_args()

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Construction slice review timed out"); quit(1))
	root.get_node("SaveManager").configure_storage_for_testing("user://construction_slice_review")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.size = Vector2i(1400,900)
	node_added.connect(func(node: Node):
		if node.name=="Renderer" and node.get_script()!=null: node.set("world_seed",1234))
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	await process_frame
	generator = root.get_node("WorldGenerator")
	registry = root.get_node("BlockRegistry")
	while not generator.get_streaming_stats().get("maps_ready",false) or generator.is_generating(): await process_frame
	renderer = current_scene.get_node("Renderer")
	field = renderer.underground_lighting
	var entrance := _find_cliff()
	_expect(entrance.x>=0,"native cliff fixture exists")
	if entrance.x<0: quit(1); return
	var mining = current_scene.get_node("MiningDesignationController")
	var cells: Array[Vector3i] = []
	# Excavate a room, then restore one column in its rear wall, directly
	# adjoining intact natural stone and still covered by the natural roof.
	for x in range(1,14):
		for z in range(6):
			for y in range(1,5): cells.append(entrance+Vector3i(x,y,z))
	var top := entrance+Vector3i(7,4,6)
	for y in range(1,5): cells.append(Vector3i(top.x,entrance.y+y,top.z))
	mining._mine_blocks_world(cells)
	builder = current_scene.get_node("ConstructionController")
	var saved := []
	for y in range(1,5):
		var cell := Vector3i(top.x,entrance.y+y,top.z)
		saved.append({"cell":[cell.x,cell.y,cell.z],"block":String(registry.get_key(generator.construction_stone_id(cell)))})
	builder.restore_state({"next_id":1,"built":saved,"orders":[]})
	var slice = current_scene.get_node("SliceController")
	slice.restore_state({"active":true,"seeded":true,"slice_y":top.y,"last_slice_y":top.y})
	var rig = current_scene.get_node("CameraRig")
	rig.set_process(false)
	camera = rig.camera_node
	camera.reparent(current_scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.position = Vector3(entrance)+Vector3(-10,28,-21)
	camera.look_at(Vector3(entrance)+Vector3(7,1,3))
	camera.current = true
	root.get_node("SkyController").set_process(false)
	root.get_node("SkyController")._update(12.0)
	await _settle()
	_expect(builder.built.size()==4,"restored backfill survives scene updates")
	await _check_cap(top,"upper_cut")
	slice._set_slice_y(top.y-1)
	await _settle()
	await _check_cap(top+Vector3i.DOWN,"lower_cut")
	slice._set_slice_y(top.y)
	await _settle()
	await _check_cap(top,"restored_slice")
	# Remove the roof: its real exposed top must retain ordinary stone color.
	var roof: Array[Vector3i] = []
	for y in range(top.y+1,generator.get_surface_y(top.x,top.z)+1): roof.append(Vector3i(top.x,y,top.z))
	mining._mine_blocks_world(roof)
	await _settle()
	var expected: Color = registry.get_color(generator.construction_stone_id(top),root.get_node("WorldClock").season)
	_expect(_colors_match(_face_color(top,Vector3.UP),expected),"exposed top stays undimmed when its roof is mined")
	slice._set_slice_y(127)
	await _settle()
	_expect(_colors_match(_face_color(top,Vector3.UP),expected),"full view keeps exposed stone's ordinary color")
	var report := {"baseline":baseline,"entrance":str(entrance),"samples":samples,"failures":failures}
	FileAccess.open(REVIEW_DIR+("before" if baseline else "after")+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CONSTRUCTION_SLICE_REVIEW: ",JSON.stringify(report))
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_SLICE_OK" if failures.is_empty() else "CONSTRUCTION_SLICE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_cap(cell: Vector3i,label: String) -> void:
	var natural := cell+Vector3i.RIGHT
	var tile: MeshInstance3D = renderer._overview_tile_nodes[Vector2i(natural.x/32,natural.z/32)]
	var natural_color := _array_face_color(tile.mesh.surface_get_arrays(0),natural,Vector3.UP)
	var built_color := _face_color(cell,Vector3.UP)
	_expect(natural_color.a>0,"comparison finds natural cap")
	if not baseline: _expect(_colors_match(built_color,natural_color),label+": constructed and natural caps have identical vertex colors")
	var side_color: Color = registry.get_color(generator.construction_stone_id(cell),root.get_node("WorldClock").season)
	_expect(_colors_match(_face_color(cell,Vector3.FORWARD),side_color),"vertical faces keep ordinary stone color")
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var built_pixel := frame.get_pixelv(Vector2i(camera.unproject_position(Vector3(cell)+Vector3(.5,1,.5))))
	var natural_pixel := frame.get_pixelv(Vector2i(camera.unproject_position(Vector3(natural)+Vector3(.5,1,.5))))
	var difference := Vector3(built_pixel.r-natural_pixel.r,built_pixel.g-natural_pixel.g,built_pixel.b-natural_pixel.b).length()
	if not baseline: _expect(difference<0.015,label+": native cap pixels match adjacent natural stone")
	samples.append({"case":label,"built_color":str(built_color),"natural_color":str(natural_color),"built_pixel":str(built_pixel),"natural_pixel":str(natural_pixel),"pixel_difference":difference})
	frame.save_png(REVIEW_DIR+("before_" if baseline else "after_")+label+".png")

func _face_color(cell: Vector3i,normal: Vector3) -> Color:
	return _array_face_color(builder._solid.mesh.surface_get_arrays(0),cell,normal)

func _array_face_color(arrays: Array,cell: Vector3i,normal: Vector3) -> Color:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var point := Vector3(cell)+Vector3(.5,.5,.5)+normal*.5
	for i in range(0,vertices.size(),4):
		if normals[i].dot(normal)<.999: continue
		var bounds := AABB(vertices[i],Vector3.ZERO)
		for j in range(1,4): bounds = bounds.expand(vertices[i+j])
		if bounds.grow(.001).has_point(point): return colors[i]
	return Color(0,0,0,0)

func _colors_match(a: Color,b: Color) -> bool:
	# ArrayMesh packs its colors to bytes.
	return maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),maxf(absf(a.b-b.b),absf(a.a-b.a)))<=1.0/255.0+.00001
