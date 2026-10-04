extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Packed furniture check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("RoomManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var manager = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(manager)
	var carrier := Node3D.new()
	scene.add_child(carrier)
	# Load gameplay scripts after autoload initialization in this --script fixture.
	var dwarf_script = load("res://scripts/entities/DwarfAgent.gd")
	var data := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(8,19):
		for z in range(8,15):
			data.set_block(x,20,z,stone)
			for y in range(21,26):
				data.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	var names := ["barrel","storage_chest","storage_shelf","tavern_bar","bench","hearth","door"]
	var shared_mesh: Mesh = null
	for i in range(names.size()):
		var key: String = "base:resources:furniture:"+names[i]
		var def: Dictionary = manager.get_item_def(key)
		assert(def.model=="res://assets/models/items/furniture/packed_furniture.glb")
		assert(def.stack_max==5 and def.weight_class=="heavy")
		manager.spawn_drop(key,1,Vector3i(10+i,21,10))
		var node: Node3D = manager.nearest_loose_of_key(key,Vector3i(10+i,20,10))
		assert(node!=null and node.scale==Vector3.ONE)
		var meshes: Array = node.find_children("*","MeshInstance3D",true,false)
		assert(meshes.size()==1)
		var mesh: MeshInstance3D = meshes[0]
		var local := mesh.get_aabb()
		assert(local.position.is_equal_approx(Vector3(-.25,0,-.25)))
		assert(local.size.is_equal_approx(Vector3(.625,.5,.625)))
		if shared_mesh==null:
			shared_mesh = mesh.mesh
		assert(mesh.mesh==shared_mesh)
		var mat: StandardMaterial3D = mesh.material_override
		assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
		assert(mat.cull_mode==BaseMaterial3D.CULL_DISABLED)
		assert(mat.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
		assert(manager.reserve(node,100+i))
		assert(manager.take(node)==key)
		carrier.add_child(node)
		node.position = dwarf_script.CARRY_OFFSET
		node.rotation = Vector3.ZERO
		assert(node.scale==Vector3.ONE and not manager._loose.has(node))
		assert(local.size.y<dwarf_script.CARRY_STACK_STEP)
		var stored_cell := Vector3i(10+i,20,12)
		manager.place_stored(node,stored_cell)
		assert(manager.stored_node_at(stored_cell)==node and node.get_meta("stored"))
		assert(node.position.is_equal_approx(Vector3(10.5+i,21,12.5)))
		manager.withdraw_stored(node,100+i)
		assert(manager.take(node)==key)
		carrier.add_child(node)
		manager.drop_loose(node,stored_cell)
		assert(manager._loose[node]==key and not node.get_meta("stored"))
	var saved: Dictionary = manager.serialize_state()
	assert(saved.loose.size()==7)
	manager.free()
	manager = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(manager)
	manager.restore_state(saved)
	assert(manager.serialize_state()==saved and manager.get_stats().loose==7)
	# Exercise existing shelf scaling through its real storage component.
	var placement = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(placement)
	placement.set_process(false)
	var shelf_def: Dictionary = placement.get_defs()["base:furniture:storage_shelf"]
	var shelf: Node3D = load(shelf_def.model).instantiate()
	scene.add_child(shelf)
	var storage = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var footprint: Array[Vector3i] = [Vector3i(10,20,10)]
	storage.setup_container(shelf_def,footprint)
	storage.display_parent = shelf
	storage.restore_inventory({"base:resources:furniture:barrel":1},manager)
	assert(storage.stored_count()==1)
	var anchored: Node3D = storage._anchor_slots[0][0]
	assert(anchored.get_parent()==shelf and anchored.scale==Vector3.ONE*.5)
	var report := {"packed_types_checked":7,"all_share_same_imported_mesh":true,
		"original_bounds_and_scale_preserved":true,"lit_linear_vertex_material":true,
		"spawn_reserve_pickup_store_withdraw_drop":true,"existing_carry_attachment_scale":true,
		"in_memory_loose_item_save_restore":true,"shelf_anchor_half_scale":true,
		"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/packed_furniture_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_PACKED_FURNITURE_ASSET_OK: ",JSON.stringify(report))
	quit(0)
