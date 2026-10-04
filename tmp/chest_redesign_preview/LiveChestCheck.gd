extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Chest asset check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("RoomManager").set_process(false)
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
	# A dedicated in-memory floor. No player saves are read or written.
	for x in range(8,15):
		for z in range(8,15):
			data.set_block(x,20,z,stone)
			for y in range(21,25):
				data.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	var origin := Vector3i(10,20,10)
	for name in ["storage_chest"]:
		var key: String = "base:furniture:"+name
		var definition: Dictionary = controller.get_defs()[key]
		var height := 1
		for yaw in range(4):
			controller._active_key = key
			controller._yaw = yaw
			assert(controller._placement_valid(origin))
			controller._hover_cell = origin
			var ghost_id: int = controller._next_ghost_id
			controller._confirm_ghost()
			var ghost = controller._ghosts[ghost_id]
			assert(ghost.footprint_cells().size()==1)
			for cell in ghost.footprint_cells():
				assert(nav.is_walkable(cell))
			var ghost_meshes: Array = ghost.node.find_children("*","MeshInstance3D",true,false)
			assert(ghost_meshes.size()==1)
			var ghost_material: StandardMaterial3D = ghost_meshes[0].material_override
			assert(is_equal_approx(ghost_material.albedo_color.a,.3))
			var id: int = controller._next_installed_id
			controller._on_ghost_build_complete(ghost)
			var component = controller._installed[id]
			assert(component.storage!=null and component.storage.capacity==24)
			assert(not component.storage.render_contents)
			assert(component.node.scale==Vector3.ONE and component.cells.size()==1)
			var meshes: Array = component.node.find_children("*","MeshInstance3D",true,false)
			assert(meshes.size()==1)
			var local: AABB = meshes[0].get_aabb()
			assert(local.position.is_equal_approx(Vector3(-.5,0,-.5)))
			assert(local.size.is_equal_approx(Vector3(1,height,1)))
			var bounds: AABB = meshes[0].global_transform*local
			assert(bounds.position.is_equal_approx(Vector3(10,21,10)))
			var rotated := Vector3(1,height,1)
			assert(bounds.size.is_equal_approx(rotated))
			var material: StandardMaterial3D = meshes[0].material_override
			assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
			assert(material.cull_mode==BaseMaterial3D.CULL_DISABLED)
			assert(material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
			for cell in component.cells:
				assert(not nav.is_walkable(cell))
				for y in range(1,height+1):
					assert(registry.occupies(cell+Vector3i(0,y,0)))
				assert(not registry.occupies(cell+Vector3i(0,height+1,0)))
			controller.dev_remove_installed(id)
			assert(controller._placement_valid(origin))
	var report := {"models_checked":1,"storage_capacity":24,"rotations_each":4,"ghosts_and_build_completion":true,
		"imported_bounds_fit_rotated_collision":true,"materials_valid":true,
		"placement_and_navigation":true,"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/chest_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_CHEST_ASSET_OK: ",JSON.stringify(report))
	quit(0)
