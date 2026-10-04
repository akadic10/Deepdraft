extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Door asset check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	var rooms := root.get_node("RoomManager")
	rooms.set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	var data := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var registry := root.get_node("PlacedEntityRegistry")
	var nav := root.get_node("NavGrid")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	var key := "base:furniture:door"
	var definition: Dictionary = controller.get_defs()[key]
	assert(definition.collision_regions.is_empty() and not definition.blocks_movement)
	assert(definition.footprint.width==2 and definition.footprint.depth==1)
	for yaw in range(4):
		# Two 4x4x4 sealed rooms with a two-wide doorway between them.
		# Transpose the fixture for odd rotations. No player saves are used.
		for x in range(6,19):
			for z in range(6,19):
				for y in range(19,27):
					data.set_block(x,y,z,stone)
		for x in range(8,12):
			for z in range(8,17):
				if z==12 and x not in [9,10]:
					continue
				for y in range(21,25):
					var p := _orient(Vector3i(x,y,z),yaw)
					data.set_block(p.x,p.y,p.z,blocks.AIR_ID)
		await process_frame
		var origin := _orient(Vector3i(9,20,12),yaw)
		controller._active_key = key
		controller._yaw = yaw
		assert(controller._placement_valid(origin))
		controller._hover_cell = origin
		var ghost_id: int = controller._next_ghost_id
		controller._confirm_ghost()
		var ghost = controller._ghosts[ghost_id]
		assert(ghost.footprint_cells().size()==2)
		for cell in ghost.footprint_cells():
			assert(nav.is_walkable(cell))
		var ghost_meshes: Array = ghost.node.find_children("*","MeshInstance3D",true,false)
		assert(ghost_meshes.size()==1)
		assert(is_equal_approx(ghost_meshes[0].material_override.albedo_color.a,.3))
		var id: int = controller._next_installed_id
		controller._on_ghost_build_complete(ghost)
		var component = controller._installed[id]
		assert(component.node.scale==Vector3.ONE and component.cells.size()==2)
		assert(component.occupancy_ids.is_empty())
		assert(component.node.position.is_equal_approx(controller._world_pos(definition,origin,yaw)))
		var meshes: Array = component.node.find_children("*","MeshInstance3D",true,false)
		assert(meshes.size()==1)
		var local: AABB = meshes[0].get_aabb()
		assert(local.position.is_equal_approx(Vector3(-1,0,-.375)))
		assert(local.size.is_equal_approx(Vector3(2,3.875,.75)))
		var bounds: AABB = meshes[0].global_transform*local
		var expected_size := Vector3(2,3.875,.75) if yaw%2==0 else Vector3(.75,3.875,2)
		assert(bounds.size.is_equal_approx(expected_size))
		assert(bounds.position.is_equal_approx(component.node.position-Vector3(expected_size.x/2,0,expected_size.z/2)))
		var material: StandardMaterial3D = meshes[0].material_override
		assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
		assert(material.cull_mode==BaseMaterial3D.CULL_DISABLED)
		assert(material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
		for cell in component.cells:
			assert(nav.is_walkable(cell))
			for dy in range(1,5):
				assert(not registry.occupies(cell+Vector3i(0,dy,0)))
			assert(rooms._door_cells[cell]==origin)
		for x in [9,10]:
			var path: Array[Vector3i] = nav.find_path(_orient(Vector3i(x,20,11),yaw),_orient(Vector3i(x,20,13),yaw))
			assert(path.size()==3 and _orient(Vector3i(x,20,12),yaw) in path)
		assert(rooms._door_cells.size()==2 and rooms._door_boundary_cells().size()==10)
		rooms._rebuild_all_rooms()
		assert(rooms.get_rooms().size()==2)
		for room: Dictionary in rooms.get_rooms().values():
			assert(room.volume==64 and room.door_cells.size()==1)
		assert(rooms.get_stats().doors==1)
		controller.dev_remove_installed(id)
		assert(rooms._door_cells.is_empty() and controller._placement_valid(origin))
		rooms._rebuild_all_rooms()
		assert(rooms.get_rooms().is_empty())
	var report := {"models_checked":1,"rotations":4,"ghosts_and_build_completion":true,
		"imported_bounds_fit_footprint":true,"materials_valid":true,
		"both_door_tiles_remain_walkable":true,"paths_cross_both_tiles":true,
		"two_separate_rooms_of_64_air_cells":true,"two_seal_columns_one_door_identity":true,
		"uninstall_removes_seal":true,"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/door_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_DOOR_ASSET_OK: ",JSON.stringify(report))
	quit(0)

func _orient(p: Vector3i,yaw: int) -> Vector3i:
	return Vector3i(p.z,p.y,p.x) if yaw%2==1 else p
