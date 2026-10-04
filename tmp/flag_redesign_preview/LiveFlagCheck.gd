extends SceneTree

class DirectorProbe extends Node:
	var anchors: Array[Vector3i] = []
	var spawn_calls: Array[Vector2i] = []
	func set_settlement_anchor(cell: Vector3i) -> void:
		anchors.append(cell)
	func spawn_squad_at(x: int,z: int) -> void:
		spawn_calls.append(Vector2i(x,z))

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Flag asset check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("RoomManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var probe := DirectorProbe.new()
	probe.name = "Director"
	scene.add_child(probe)
	var controller = _controller(scene)
	var data := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var registry := root.get_node("PlacedEntityRegistry")
	var nav := root.get_node("NavGrid")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(8,14):
		for z in range(8,14):
			data.set_block(x,20,z,stone)
			for y in range(21,26):
				data.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	var cell := Vector3i(10,20,10)
	assert(controller._is_valid_cell(cell) and nav.is_walkable(cell))
	controller._ensure_ghost()
	var ghosts: Array = controller._ghost.find_children("*","MeshInstance3D",true,false)
	assert(ghosts.size()==1)
	var ghost_material: StandardMaterial3D = ghosts[0].material_override
	assert(ghost_material.vertex_color_use_as_albedo)
	assert(is_equal_approx(ghost_material.albedo_color.a,.55))
	assert(ghost_material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert(registry.get_stats().entities==0 and nav.is_walkable(cell))
	controller._place_flag(cell)
	_check_placed(controller,cell,registry,nav)
	assert(probe.anchors==[cell] and probe.spawn_calls==[Vector2i(10,10)])
	var saved: Dictionary = controller.serialize_state()
	assert(saved.placed and saved.cell==[10,20,10])
	assert(controller.save_section_key()=="settlement_flag" and controller.save_restore_priority()==20)
	# Exercise the actual owner serialization/restore API in memory. The
	# director probe verifies the restore hook does not respawn a squad.
	registry.unregister(controller._flag_occupancy_id)
	controller.free()
	assert(nav.is_walkable(cell))
	controller = _controller(scene)
	controller.restore_state(saved)
	_check_placed(controller,cell,registry,nav)
	assert(controller.serialize_state()==saved)
	assert(probe.anchors==[cell,cell] and probe.spawn_calls.size()==1)
	var report := {"model_checked":true,"ghost_material_and_no_occupancy":true,
		"imported_bounds_fit_1x3x1":true,"linear_vertex_colors_and_lit_material":true,
		"placement_blocks_only_flag_column":true,"settlement_anchor_hook":true,
		"initial_squad_spawn_hook_once":true,"in_memory_save_restore":true,
		"restore_does_not_respawn_squad":true,"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/flag_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_FLAG_ASSET_OK: ",JSON.stringify(report))
	quit(0)

func _controller(scene: Node3D):
	var node = load("res://scripts/systems/FlagPlacementController.gd").new()
	node.dwarf_director_path = NodePath("../Director")
	scene.add_child(node)
	node.set_process(false)
	return node

func _check_placed(controller,cell: Vector3i,registry,nav) -> void:
	assert(controller.flag_scale==1.0 and controller._flag_node.scale==Vector3.ONE)
	assert(controller._flag_node.position.is_equal_approx(Vector3(10.5,21,10.5)))
	var meshes: Array = controller._flag_node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==1)
	var mesh: MeshInstance3D = meshes[0]
	var bounds := mesh.global_transform*mesh.get_aabb()
	assert(bounds.position.is_equal_approx(Vector3(10,21,10.125)))
	assert(bounds.size.is_equal_approx(Vector3(1,3,.75)))
	var mat: StandardMaterial3D = mesh.material_override
	assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
	assert(mat.cull_mode==BaseMaterial3D.CULL_DISABLED)
	assert(mat.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	var colors: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert(colors.size()>0)
	var has_red := false
	var has_gold := false
	for color in colors:
		has_red = has_red or (color.r>color.g*3 and color.r>color.b*2)
		has_gold = has_gold or (color.r>color.g and color.g>color.b*3)
	assert(has_red and has_gold)
	assert(registry.get_stats().entities==1 and registry.get_stats().occupied_columns==1)
	for dy in range(1,4):
		assert(registry.occupies(cell+Vector3i(0,dy,0)))
	assert(not registry.occupies(cell+Vector3i(0,4,0)))
	assert(not nav.is_walkable(cell) and not controller._is_valid_cell(cell))
	for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		assert(nav.is_walkable(cell+offset))
