extends "res://scripts/tests/WorkerCraftingTest.gd"

var Mount
const SITE := Vector3i(60,20,60)
const OUT := "res://tmp/wall_height_20261012/"
var nav
var edits: Array[Vector3i] = []

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Wall mounting test timed out"); quit(1))
	await _setup_crafting_fixture()
	Mount = load("res://scripts/components/WallFurnitureMount.gd")
	nav = root.get_node("NavGrid")
	stockpiles.reset_runtime_state()
	await _aim_cases()
	await _access_cases()
	await _worker_cases()
	await _native_view()
	for failure in failures: push_error(failure)
	print("WALL_MOUNT_HEIGHT_OK: cursor heights, four faces, wheel, access, ceiling/overlap/slice, delivery/removal, save and support" if failures.is_empty() else "WALL_MOUNT_HEIGHT_FAIL")
	quit(0 if failures.is_empty() else 1)

func _edit(cell: Vector3i, solid: bool) -> void:
	world.set_block(cell.x,cell.y,cell.z,blocks.get_id("base:terrain:rock:rock01") if solid else blocks.AIR_ID)
	nav.refresh_mined_block(cell)
	if not edits.has(cell): edits.append(cell)

func _clean(yaw := 0) -> void:
	furniture.deactivate()
	worker.abort_task()
	tasks.release_dwarf_task(worker.dwarf_id,Task.ReleaseReason.PLAYER)
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in furniture._installed.keys(): furniture._teardown_installed(id,true)
	for item in drops._loose.keys(): drops.take(item); item.free()
	for cell in edits: world.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID if cell.y>20 else blocks.get_id("base:terrain:rock:rock01")); nav.refresh_mined_block(cell)
	edits.clear()
	for y in range(21,31): _edit(Vector3i(SITE.x,y,SITE.z)+Mount.back(yaw),true)
	worker.position = Vector3(57.5,21,62.5)
	worker.sleep = 1.0
	clock_node.set_paused(true)
	await _frames(2)

func _aim(key: String, height: int, yaw: int) -> Vector2:
	var cell := SITE+Vector3i.UP*height
	var wall_point := Vector3(cell)+Vector3(.5,.25,.5)+Vector3(Mount.back(yaw))*.5
	camera.position = wall_point-Vector3(Mount.back(yaw))*10+Vector3.UP*2
	camera.look_at(wall_point)
	camera.size = 12
	var point := camera.unproject_position(wall_point)
	# Keep activation's initial mouse ray inside this deliberately small world.
	root.warp_mouse(point)
	furniture.activate_for(key)
	furniture._update_hover(true,point)
	return point

func _click_at(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		root.push_input(event,true)

func _wheel(point: Vector2, up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true; event.alt_pressed = true
	root.push_input(event,true)

func _aim_cases() -> void:
	for yaw in range(4):
		for height in range(1,6):
			await _clean(yaw)
			var point := _aim(TORCH,height,yaw)
			var def: Dictionary = furniture.get_defs()[TORCH]
			_expect(furniture._hover_valid and furniture._yaw==yaw,"valid wall cursor at height %d, yaw %d" % [height,yaw])
			_expect(Mount.mount_cell(def,furniture._hover_cell)==SITE+Vector3i.UP*height,"cursor preserves the exact selected wall cell")
			_click_at(point)
			_expect(furniture._ghosts.size()==1,"real click creates the height-selected plan")
			if furniture._ghosts.is_empty(): continue
			var ghost = furniture._ghosts.values()[0]
			_expect(ghost.node.position.y==SITE.y+height+.5,"preview and placed ghost agree on height")
			var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
			furniture.cancel_ghost(ghost.ghost_id)
			furniture.restore_state(saved)
			_expect(furniture._ghosts.values()[0].node.position.y==SITE.y+height+.5,"pending mount height survives serialization")
	await _clean()
	var point := _aim(TORCH,2,0)
	_wheel(point,true)
	_expect(Mount.mount_cell(furniture.get_defs()[TORCH],furniture._hover_cell).y==23,"Alt wheel nudges one block upward")
	_wheel(point,false)
	_expect(Mount.mount_cell(furniture.get_defs()[TORCH],furniture._hover_cell).y==22,"Alt wheel nudges one block downward")
	_expect(furniture._hint_label.text.contains("Alt + wheel"),"placement explains height controls")
	furniture._slice_y = 22
	furniture._update_hover(true,point)
	_expect(not furniture._hover_valid,"hidden flame cannot be placed through a slice")
	furniture._slice_y = 127

func _access_cases() -> void:
	await _clean()
	_aim(TORCH,6,0)
	_expect(not furniture._hover_valid and furniture._invalid_reason=="access","sixth block needs an elevated work floor")
	_edit(SITE+Vector3i(0,1,1),true)
	var point := _aim(TORCH,6,0)
	_expect(furniture._hover_valid,"raised work floor enables higher mount")
	var high_origin: Vector3i = furniture._hover_cell
	_edit(SITE+Vector3i(0,5,0),true)
	_expect(not Mount.work_stands(furniture.get_defs()[TORCH],high_origin,0).has(SITE+Vector3i(0,1,1)),"intervening ceiling blocks reaching up from the raised work floor")
	await _clean()
	point = _aim(TORCH,2,0)
	_edit(SITE+Vector3i(0,3,0),true)
	furniture._update_hover(true,point)
	_expect(not furniture._hover_valid and furniture._invalid_reason=="wall_clearance","flame cannot intersect ceiling")
	await _clean()
	point = _aim(TORCH,2,0)
	_click_at(point)
	point = _aim(TORCH,3,0)
	_expect(not furniture._hover_valid and furniture._invalid_reason=="overlap","different heights still reject overlapping lights")
	await _clean()
	point = _aim(TORCH,5,0)
	_click_at(point)
	var ghost = furniture._ghosts.values()[0]
	var pos: Vector3 = ghost.node.position
	for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.BACK]: _edit(SITE+offset,false)
	furniture._revalidate_wall_mounts()
	_expect(furniture._ghosts.has(ghost.ghost_id) and ghost.node.position==pos,"lost access leaves the plan at its chosen height")
	_expect(ghost.work_stands(SITE).is_empty() and not furniture._can_build_ghost(ghost),"out-of-reach plan cannot consume a torch")
	_expect(furniture.get_explorer_data("ghost:%d" % ghost.ghost_id).rows[0][1]=="Waiting for reachable work position","plan explains missing access")
	_edit(SITE,true)
	_expect(not ghost.work_stands(SITE).is_empty(),"restoring work floor makes the same plan usable")

func _worker_cases() -> void:
	for yaw in range(4):
		await _clean(yaw)
		drops.restore_loose_item(String(furniture.get_defs()[TORCH].item_key),Vector3(58.5,21,62.5),0,1)
		var point := _aim(TORCH,5,yaw)
		_click_at(point)
		furniture.deactivate()
		clock_node.set_paused(false)
		_expect(await _installed(TORCH),"actual worker fetches and installs at maximum reach, yaw %d" % yaw)
		if furniture._installed.is_empty(): continue
		var piece = furniture._installed.values()[0]
		var position: Vector3 = piece.node.position
		_expect(position.y==25.5,"worker commits at the selected height")
		var heat = root.get_node("RoomManager")._heat_cells
		_expect(heat.has(Vector3i(60,24,60)),"heat belongs to actual mount's air cell, independent of work floor")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		furniture._teardown_installed(piece.installed_id,true)
		for item in drops._loose.keys(): drops.take(item); item.free()
		furniture.restore_state(saved)
		piece = furniture._installed.values()[0]
		_expect(piece.node.position==position,"installed mount restores at exact world height")
		piece.set_uninstall(true)
		for i in range(800):
			if furniture._installed.is_empty(): break
			await _tick()
		_expect(furniture._installed.is_empty() and _count(piece.item_key)==1,"worker removes high mount with exactly one intact refund")
	# Lose reach during the actual placement animation: another valid stand may
	# exist, but this dwarf must not finish from its now-invalid one.
	await _clean()
	drops.restore_loose_item(String(furniture.get_defs()[TORCH].item_key),Vector3(58.5,21,62.5),0,1)
	_click_at(_aim(TORCH,5,0)); furniture.deactivate(); clock_node.set_paused(false)
	_expect(await _phase(worker.TaskPhase.FETCH_DEPOSIT),"worker reaches high-mount handoff")
	worker.position.y -= 1
	worker._process_item_handling(1)
	_expect(furniture._installed.is_empty() and _count(String(furniture.get_defs()[TORCH].item_key))==1,"final reach check preserves carried item after access changes")

func _native_view() -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await _clean()
	for x in range(57,67):
		for y in range(21,30): _edit(Vector3i(x,y,59),true)
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new(); wall.mesh.size = Vector3(10,9,1)
	wall.position = Vector3(62,25.5,59.5)
	var material := StandardMaterial3D.new(); material.albedo_color = Color("737b83")
	wall.material_override = material; scene.add_child(wall)
	for pair in [[58,2],[61,3],[64,5]]:
		var def: Dictionary = furniture.get_defs()[TORCH]
		furniture._install(TORCH,def,Mount.origin_for_mount(def,Vector3i(pair[0],20+pair[1],60)),0)
	camera.size = 15; camera.position = Vector3(73,31,80); camera.look_at(Vector3(62,24,60))
	worker.position = Vector3(62.5,21,62.5)
	await _frames(5)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_texture().get_image().save_png(OUT+"mounting_heights.png")
