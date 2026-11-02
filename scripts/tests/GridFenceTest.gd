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
	print("GRID_FENCE_OK: tile posts, rails, corners, gate, routes, previews, support, zones, construction, materials and saves" if failures.is_empty() else "GRID_FENCE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _patterns_and_routes() -> void:
	var origin := Vector3i(46,20,43)
	var a = _put(POST,origin)
	_expect(a.node.position==Vector3(46.5,21,43.5),"post stands in the middle of its tile")
	_expect(furniture._fences.links.is_empty(),"one post has no floating rails")
	_expect(not nav.is_walkable(origin),"a finished post blocks its own tile")
	for side: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		_expect(nav.is_walkable(origin+side),"the tiles beside a post stay walkable")
	var b = _put(POST,origin+Vector3i.RIGHT)
	var c = _put(POST,origin+Vector3i.RIGHT*2)
	_expect(furniture._fences.links.size()==2 and furniture._fences.post_handles.size()==3,"three posts form two spans with no double posts")
	var rail: Node3D = furniture._fences.links[Vector4i(46,20,43,0)].node
	_expect(rail.global_position.is_equal_approx(Vector3(47,21,43.5)),"a rail runs from tile centre to tile centre")
	var north := origin+Vector3i(1,0,-1)
	var south := origin+Vector3i(1,0,1)
	_expect(nav.is_walkable(north) and nav.is_walkable(south),"both sides of the run stay walkable")
	_expect(not nav.line_walkable_flat(north,south),"string pulling cannot cross the run")
	var animal = load("res://scripts/components/AnimalNavigation.gd")
	_expect(animal.standable(north+Vector3i.UP,2) and not animal.can_hop(north+Vector3i.UP,b.origin_cell+Vector3i.UP,2),"small animals keep the ground beside the run but cannot step into it")
	var around: Array = nav.find_path(north,south)
	_expect(around.size()>3,"pathfinding takes a real route around the run")
	for cell: Vector3i in around:
		_expect(not furniture._fences.post_handles.has(cell),"no route step enters a post tile")
	worker.position = Vector3(north)+Vector3(.5,1,.5)
	_expect(worker.walk_to(south),"dwarf accepts the route around the run")
	for i in range(200):
		worker._process(.05)
		_expect(not furniture._fences.post_handles.has(worker.current_cell()),"live movement never enters a post tile")
		await process_frame
		if not worker.is_walking(): break
	_expect(worker.current_cell()==south,"dwarf reaches the other side by walking around")
	var corner = _put(POST,origin+Vector3i(2,0,1))
	var junction = _put(POST,origin+Vector3i(3,0,0))
	_expect(furniture._fences.links.size()==4,"corners and T junctions use the same rail height")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("patterns")
	furniture.dev_remove_installed(b.installed_id)
	_expect(furniture._fences.links.size()==2 and furniture._fences.post_handles.size()==4,"removing a post removes only its own rails")
	_expect(nav.line_walkable_flat(north,south) and nav.find_path(north,south).size()<around.size(),"uninstall immediately opens the tile and invalidates path caches")
	_clear()
	# Diagonal posts get no rail, and no-corner-cutting still closes the gap.
	a = _put(POST,origin)
	b = _put(POST,origin+Vector3i(1,0,1))
	_expect(furniture._fences.links.is_empty() and nav.find_path(origin+Vector3i.RIGHT,origin+Vector3i.BACK).size()>3,"diagonal posts close the gap between them")
	_clear()
	# A gate hangs across one open tile; its end posts reuse existing posts.
	a = _put(POST,origin)
	b = _put(POST,origin+Vector3i(2,0,0))
	_expect(furniture._fences.placement_reason(furniture.get_defs()[GATE],origin,0).is_empty(),"gate can reuse two existing end posts")
	var gate = _put(GATE,origin)
	var opening := origin+Vector3i.RIGHT
	_expect(gate.node.position.is_equal_approx(Vector3(47.5,21,43.5)),"gate is centred on its opening tile")
	_put(POST,origin+Vector3i.LEFT)
	_put(POST,origin+Vector3i.RIGHT*3)
	_expect(furniture._fences.post_handles.size()==4 and furniture._fences.links.size()==2,"gate end posts connect without double posts or a rail across the opening")
	_expect(nav.is_walkable(opening) and nav.line_walkable_flat(opening+Vector3i.FORWARD,opening+Vector3i.BACK),"the opening tile stays walkable straight through")
	_expect(not furniture._fences.placement_reason(furniture.get_defs()[POST],opening,0).is_empty(),"post cannot close the gate opening")
	_expect(not furniture._fences.placement_reason(furniture.get_defs()[GATE],origin,2).is_empty(),"rotated duplicate gate is rejected")
	_expect(not furniture._fences.placement_reason(furniture.get_defs()[GATE],opening+Vector3i.FORWARD,1).is_empty(),"crossing gates cannot share an opening")
	_expect(furniture.blocks_zone_cell(origin) and furniture.blocks_zone_cell(opening) and not furniture.blocks_zone_cell(opening+Vector3i.BACK),"storage zones stay off post and opening tiles only")
	worker.position = gate.node.global_position+Vector3(0,0,1)
	gate.node.get_node("DoorAnimation")._process(.4)
	_expect(gate.node.get_node("DoorAnimation")._angle>.1,"aligned gate still opens near dwarves")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("gate")
	furniture.dev_remove_installed(gate.installed_id)
	_expect(furniture._fences.post_handles.size()==4,"removing gate preserves separately built posts")
	_clear()
	# Mining a post's floor refunds the post and removes its rails.
	a = _put(POST,origin)
	b = _put(POST,origin+Vector3i.RIGHT)
	world.set_block(origin.x,origin.y,origin.z,0)
	furniture._fences.revalidate_support()
	_expect(not furniture._installed.has(a.installed_id) and furniture._fences.links.is_empty(),"lost floor removes the unsupported post and its rails")
	_expect(_count("base:resources:furniture:log_fence")==1,"unsupported post returns exactly one real packed item")
	world.set_block(origin.x,origin.y,origin.z,blocks.get_id("base:terrain:rock:rock01"))
	_clear()

func _actual_build() -> void:
	_put(BENCH,Vector3i(45,20,39))
	drops.spawn_drop(PINE,2,Vector3i(42,21,40))
	var id: int = crafting.queue_order("base:recipe:worker:log_fence",2)
	_expect(await _completed(id),"Worker crafts two real fence posts")
	furniture.activate_for(POST,true)
	for tile in [Vector3i(47,20,44),Vector3i(48,20,44)]:
		furniture._hover_cell = tile
		_expect(furniture._placement_valid(tile),"post plan has valid level ground")
		furniture._confirm_ghost()
	_expect(furniture._ghosts.size()==2 and furniture._fences.links.size()==1,"plans show their future connecting rails")
	_expect(nav.is_walkable(Vector3i(47,20,44)),"planned posts never block walking")
	furniture.deactivate()
	for i in range(1000):
		await _tick()
		if furniture._ghosts.is_empty(): break
	_expect(furniture._ghosts.is_empty() and furniture._fences.links.size()==1,"Worker delivers and installs both posts")
	_expect(not nav.is_walkable(Vector3i(47,20,44)) and not nav.is_walkable(Vector3i(48,20,44)),"finished posts block their tiles")
	_expect(not furniture._fences.post_handles.has(worker.current_cell()),"the installer stays beside the post tiles")
	_expect(_count(PINE)==0 and _count("base:resources:furniture:log_fence")==0,"two timber become exactly two placed posts")
	var installed = furniture._installed.values().filter(func(p): return p.furniture_key==POST)
	_expect(installed.all(func(p): return p.material_id=="base:material:pine"),"crafted timber identity survives installation")
	var relocated = installed.filter(func(p): return p.origin_cell==Vector3i(48,20,44))[0]
	var kept = installed.filter(func(p): return p!=relocated)[0]
	furniture.begin_furniture_move(relocated.installed_id)
	furniture._hover_cell = Vector3i(46,20,44)
	_expect(furniture._placement_valid(furniture._hover_cell),"post Move accepts another tile")
	furniture._confirm_ghost()
	for i in range(1000):
		await _tick()
		if furniture._ghosts.is_empty(): break
	_expect(furniture._ghosts.is_empty() and not furniture._installed.has(relocated.installed_id),"Worker moves the actual selected post")
	_expect(furniture._fences.links.size()==1 and furniture._fences.post_handles.has(Vector3i(46,20,44)),"moving a post reconnects rails at its new tile")
	_expect(nav.is_walkable(Vector3i(48,20,44)),"the vacated tile opens again")
	_expect(_count("base:resources:furniture:log_fence")==0,"Move creates no spare posts")
	kept.set_uninstall(true)
	for i in range(600):
		await _tick()
		if not furniture._installed.has(kept.installed_id): break
	_expect(not furniture._installed.has(kept.installed_id) and furniture._fences.links.is_empty(),"Worker reaches and uninstalls a post")
	_expect(_count("base:resources:furniture:log_fence")==1,"real removal returns one post kit")
	_clear()

func _input_and_save() -> void:
	worker.position = Vector3(42.5,21,39.5)
	for yaw in range(4):
		var origin := Vector3i(46,20,43)
		var axis := Vector3i.RIGHT if yaw%2==0 else Vector3i.BACK
		_put(GATE,origin,yaw)
		_expect(furniture._fences.post_handles.size()==2 and nav.is_walkable(origin+axis) and not nav.is_walkable(origin+axis*2),"a lone gate blocks its own end posts and keeps its opening")
		_put(POST,origin-axis)
		_put(POST,origin+axis*3)
		_expect(furniture._fences.links.size()==2,"gate connects in every orientation")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		_clear()
		furniture.restore_state(saved)
		_expect(furniture._fences.links.size()==2 and furniture._fences.post_handles.size()==4,"reload reconstructs posts and rails once")
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"current save preserves identities, tiles, rotations and material")
		_clear()
	_put(POST,Vector3i(46,20,43))
	furniture.activate_for(POST)
	camera.position = Vector3(52,29,53)
	camera.look_at(Vector3(47,21,43))
	var post_pick: Dictionary = furniture.pick_explorer_object(camera.position,Vector3(46.5,21.9,43.5))
	_expect(not post_pick.is_empty(),"post can be selected by its visible mesh")
	var aim := camera.unproject_position(Vector3(47.5,21,43.5))
	furniture._update_hover(true,aim)
	_expect(furniture._hover_cell==Vector3i(47,20,43),"real camera aim picks the tile under the cursor")
	_expect(furniture._visuals.preview.get_children().any(func(n): return n.has_meta("fence_preview")),"cursor preview shows automatic connecting rails")
	if "--capture" in OS.get_cmdline_user_args(): await _capture_fence("preview")
	# A real click through the viewport plans the post on the tile under the cursor.
	_move(aim)
	_mouse_button(aim,true)
	_mouse_button(aim,false)
	await _frames(2)
	_expect(furniture._ghosts.size()==1 and furniture._ghosts.values()[0].origin_cell==Vector3i(47,20,43),"a real click plans the post on that tile")
	var rail_pick: Dictionary = furniture.pick_explorer_object(camera.position,Vector3(47,22.0,43.5))
	_expect(not rail_pick.is_empty(),"derived rail can be selected with its owning post")
	var saved_plan: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	furniture.deactivate()
	_clear()
	furniture.restore_state(saved_plan)
	_expect(furniture._ghosts.size()==1 and furniture._fences.links.size()==1,"pending post and its connecting preview survive reload")
	_expect(furniture._fences.links.values().all(func(link): return not link.solid) and nav.is_walkable(Vector3i(47,20,43)),"restoring a plan blocks nothing early")
	var ghost = furniture._ghosts.values()[0]
	furniture.cancel_ghost(ghost.ghost_id)
	_expect(furniture._fences.links.is_empty(),"cancelling a plan removes its derived rails")
	# A gate is aimed by its opening tile.
	furniture.activate_for(GATE)
	furniture._yaw = 1
	furniture._update_hover(true,camera.unproject_position(Vector3(47.5,21,44.5)))
	_expect(furniture._hover_cell==Vector3i(47,20,43),"gate cursor centres the opening on the aimed tile")
	furniture.deactivate()
	_clear()

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)

func _mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	root.push_input(event,true)

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
