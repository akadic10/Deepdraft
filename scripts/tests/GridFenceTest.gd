extends "res://scripts/tests/WorkerCraftingTest.gd"

const POST := "base:furniture:log_fence"
const GATE := "base:furniture:log_gate"
const OUT := "res://tmp/grid_fence/"
var nav

func _put(key: String, origin: Vector3i, yaw := 0):
	var id: int = furniture._next_installed_id
	furniture._install(key,furniture.get_defs()[key],origin,yaw,"base:material:oak")
	return furniture._installed[id]

func _clear() -> void:
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in furniture._installed.keys(): furniture.dev_remove_installed(id)
	for node in drops._loose.keys(): drops.take(node); node.free()

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Grid fence timed out"); quit(1))
	await _setup_crafting_fixture()
	nav = root.get_node("NavGrid")
	await _patterns_and_routes()
	await _actual_build()
	await _input_and_save()
	if "--capture" in OS.get_cmdline_user_args(): await _presentation()
	for failure in failures: push_error(failure)
	print("GRID_FENCE_OK: shared posts, rails, corners, gate, routes, previews, support, construction, materials and saves" if failures.is_empty() else "GRID_FENCE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _patterns_and_routes() -> void:
	var origin := Vector3i(46,20,43)
	var a = _put(POST,origin)
	_expect(a.node.position==Vector3(46,21,43),"post stands on voxel corner, not cell centre")
	_expect(furniture._fences.links.is_empty(),"one post has no floating rails")
	var b = _put(POST,origin+Vector3i.RIGHT)
	var c = _put(POST,origin+Vector3i.RIGHT*2)
	_expect(furniture._fences.links.size()==2 and furniture._fences.post_handles.size()==3,"three posts form two spans with no double posts")
	var north := origin+Vector3i.FORWARD
	var south := origin
	_expect(nav.is_walkable(north) and nav.is_walkable(south),"both neighboring floor tiles stay walkable")
	_expect(not nav.edge_clear(north,south) and not nav.edge_clear(south,north),"rail blocks crossing in either direction")
	_expect(not nav.line_walkable_flat(north,south),"string pulling cannot cross a rail")
	_expect(not nav.edge_clear(origin+Vector3i(-1,0,-1),origin),"diagonal movement cannot cut through an end post")
	var animal = load("res://scripts/components/AnimalNavigation.gd")
	_expect(animal.standable(north+Vector3i.UP,2) and not animal.can_hop(north+Vector3i.UP,south+Vector3i.UP,2),"small animals keep usable adjacent ground but cannot cross rails")
	var path: Array = nav.find_path(north,south)
	_expect(not path.is_empty() and path.size()>1,"pathfinding takes a real route around the fence end")
	var previous := north
	for cell: Vector3i in path:
		_expect(nav.edge_clear(previous,cell),"every route step avoids fence geometry")
		previous = cell
	worker.position = Vector3(north)+Vector3(.5,1,.5)
	_expect(worker.walk_to(south),"dwarf accepts the route around the fence")
	for i in range(140):
		var before: Vector3 = worker.position
		worker._process(.05)
		_expect(not root.get_node("PlacedEntityRegistry").barrier_blocks_segment(before,worker.position),"live movement never cuts through fence rails or posts")
		await process_frame
		if not worker.is_walking(): break
	_expect(worker.current_cell()==south,"dwarf reaches the other side by walking around")
	var corner = _put(POST,origin+Vector3i(2,0,1))
	var junction = _put(POST,origin+Vector3i(1,0,-1))
	_expect(furniture._fences.links.size()==4,"corners and T junctions use the same rail height")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("patterns")
	furniture.dev_remove_installed(b.installed_id)
	_expect(furniture._fences.links.size()==1 and furniture._fences.post_handles.size()==4,"removing a junction removes only its attached rails")
	_expect(nav.edge_clear(north,south),"uninstall immediately opens the route and invalidates path caches")
	_clear()
	# A gate spans two grid edges. Its end posts share with existing posts.
	a = _put(POST,origin)
	b = _put(POST,origin+Vector3i(2,0,0))
	_expect(furniture._fences.placement_reason(furniture.get_defs()[GATE],origin,0).is_empty(),"gate can reuse two existing end posts")
	var gate = _put(GATE,origin)
	_put(POST,origin+Vector3i.LEFT)
	_put(POST,origin+Vector3i.RIGHT*3)
	_expect(furniture._fences.post_handles.size()==4 and furniture._fences.links.size()==2,"gate endpoints connect without duplicate posts or rails across opening")
	_expect(nav.edge_clear(north,south),"gate opening remains traversable")
	_expect(not furniture._fences.placement_reason(furniture.get_defs()[POST],origin+Vector3i.RIGHT,0).is_empty(),"post cannot close the middle of a gate")
	_expect(not furniture._fences.placement_reason(furniture.get_defs()[GATE],origin,2).is_empty(),"rotated duplicate gate is rejected")
	worker.position = gate.node.global_position+Vector3(.5,0,1)
	gate.node.get_node("DoorAnimation")._process(.4)
	_expect(gate.node.get_node("DoorAnimation")._angle>.1,"aligned gate still opens near dwarves")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("gate")
	furniture.dev_remove_installed(gate.installed_id)
	_expect(furniture._fences.post_handles.size()==4,"removing gate preserves separately built posts")
	_clear()
	# Mining a support refunds the post and removes the connected obstruction.
	a = _put(POST,origin)
	b = _put(POST,origin+Vector3i.RIGHT)
	world.set_block(45,20,42,0)
	furniture._fences.revalidate_support()
	_expect(not furniture._installed.has(a.installed_id) and furniture._fences.links.is_empty(),"lost corner support removes the unsupported post and its rails")
	_expect(_count("base:resources:furniture:log_fence")==1,"unsupported post returns exactly one real packed item")
	world.set_block(45,20,42,blocks.get_id("base:terrain:rock:rock01"))
	_clear()

func _actual_build() -> void:
	_put(BENCH,Vector3i(45,20,39))
	drops.spawn_drop(PINE,2,Vector3i(42,21,40))
	var id: int = crafting.queue_order("base:recipe:worker:log_fence",2)
	_expect(await _completed(id),"Worker crafts two real fence posts")
	furniture.activate_for(POST,true)
	for vertex in [Vector3i(47,20,44),Vector3i(48,20,44)]:
		furniture._hover_cell = vertex
		_expect(furniture._placement_valid(vertex),"post plan has valid level ground")
		furniture._confirm_ghost()
	_expect(furniture._ghosts.size()==2 and furniture._fences.links.size()==1,"plans show their future connecting rails")
	_expect(nav.edge_clear(Vector3i(47,20,43),Vector3i(47,20,44)),"planned rails never block walking")
	furniture.deactivate()
	for i in range(1000):
		await _tick()
		if furniture._ghosts.is_empty(): break
	_expect(furniture._ghosts.is_empty() and furniture._fences.links.size()==1,"Worker delivers and installs both posts")
	_expect(not nav.edge_clear(Vector3i(47,20,43),Vector3i(47,20,44)),"completed pair creates a physical barrier")
	_expect(_count(PINE)==0 and _count("base:resources:furniture:log_fence")==0,"two timber become exactly two placed posts")
	var installed = furniture._installed.values().filter(func(p): return p.furniture_key==POST)
	_expect(installed.all(func(p): return p.material_id=="base:material:pine"),"crafted timber identity survives installation")
	var relocated = installed[1]
	furniture.begin_furniture_move(relocated.installed_id)
	furniture._hover_cell = Vector3i(46,20,44)
	_expect(furniture._placement_valid(furniture._hover_cell),"post Move accepts another grid corner")
	furniture._confirm_ghost()
	for i in range(1000):
		await _tick()
		if furniture._ghosts.is_empty(): break
	_expect(furniture._ghosts.is_empty() and not furniture._installed.has(relocated.installed_id),"Worker moves the actual selected post")
	_expect(furniture._fences.links.size()==1 and furniture._fences.post_handles.has(Vector3i(46,20,44)),"moving a post reconnects rails at its new corner")
	_expect(_count("base:resources:furniture:log_fence")==0,"Move creates no spare posts")
	installed[0].set_uninstall(true)
	for i in range(600):
		await _tick()
		if not furniture._installed.has(installed[0].installed_id): break
	_expect(not furniture._installed.has(installed[0].installed_id) and furniture._fences.links.is_empty(),"Worker reaches and uninstalls a corner post")
	_expect(_count("base:resources:furniture:log_fence")==1,"real removal returns one post kit")
	_clear()

func _input_and_save() -> void:
	worker.position = Vector3(42.5,21,39.5)
	for yaw in range(4):
		var origin := Vector3i(46,20,43)
		var gate = _put(GATE,origin,yaw)
		var axis := Vector3i.RIGHT if yaw%2==0 else Vector3i.BACK
		_put(POST,origin-axis)
		_put(POST,origin+axis*3)
		_expect(furniture._fences.links.size()==2,"gate connects in every orientation")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		_clear()
		furniture.restore_state(saved)
		_expect(furniture._fences.links.size()==2 and furniture._fences.post_handles.size()==4,"reload reconstructs posts and rails once")
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"current save preserves identities, vertices, rotations and material")
		_clear()
	_put(POST,Vector3i(46,20,43))
	furniture.activate_for(POST)
	camera.position = Vector3(52,29,53)
	camera.look_at(Vector3(47,21,43))
	var post_pick: Dictionary = furniture.pick_explorer_object(camera.position,Vector3(46,21.9,43))
	_expect(not post_pick.is_empty(),"corner post can be selected by its visible mesh")
	var aim := camera.unproject_position(Vector3(47.05,21,43.04))
	furniture._update_hover(true,aim)
	_expect(furniture._hover_cell==Vector3i(47,20,43),"real camera aim snaps to nearest grid intersection")
	_expect(furniture._hover_valid,"post beside an installed post is valid")
	_expect(furniture._preview.get_children().any(func(n): return n.has_meta("fence_preview")),"cursor preview shows automatic connecting rails")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("preview")
	furniture._confirm_ghost()
	var rail_pick: Dictionary = furniture.pick_explorer_object(camera.position,Vector3(46.5,22.0,43))
	_expect(not rail_pick.is_empty(),"derived rail can be selected with its owning post")
	var ghost = furniture._ghosts.values()[0]
	var saved_plan: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	furniture.deactivate()
	_clear()
	furniture.restore_state(saved_plan)
	_expect(furniture._ghosts.size()==1 and furniture._fences.links.size()==1,"pending post and its connecting preview survive reload")
	_expect(furniture._fences.links.values().all(func(link): return not link.solid),"restoring a plan does not create physical rails early")
	ghost = furniture._ghosts.values()[0]
	furniture.cancel_ghost(ghost.ghost_id)
	_expect(furniture._fences.links.is_empty(),"cancelling a plan removes its derived rails")
	furniture.deactivate()
	_clear()

func _capture_fence(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for node in drops._loose.keys(): drops.take(node); node.free()
	worker.hide()
	for node in [dock,manager]: node.hide()
	camera.position = Vector3(52,27,51)
	camera.look_at(Vector3(47,21.6,43))
	camera.size = 8
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
	worker.show()

func _presentation() -> void:
	_clear()
	for x in [44,45,46,48,49,50]: _put(POST,Vector3i(x,20,43))
	_put(GATE,Vector3i(46,20,43))
	for z in [44,45,46]: _put(POST,Vector3i(50,20,z))
	_put(POST,Vector3i(45,20,42))
	var grid := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.32,.39,.30)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for x in range(42,53):
		mesh.surface_add_vertex(Vector3(x,21.01,40)); mesh.surface_add_vertex(Vector3(x,21.01,49))
	for z in range(40,50):
		mesh.surface_add_vertex(Vector3(42,21.01,z)); mesh.surface_add_vertex(Vector3(52,21.01,z))
	mesh.surface_end()
	grid.mesh = mesh
	scene.add_child(grid)
	worker.hide()
	for node in [dock,manager]: node.hide()
	camera.position = Vector3(54,29,55)
	camera.look_at(Vector3(47,21.6,44))
	camera.size = 12
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"fence_grid.png")
