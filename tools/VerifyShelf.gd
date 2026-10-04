extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Shelf check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("RoomManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var manager = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(manager)
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	controller._process(0) # normal lazy hookup to ItemDropManager
	var dwarf = load("res://scripts/entities/DwarfAgent.gd").new()
	dwarf.dwarf_id = 100
	scene.add_child(dwarf)
	dwarf.set_process(false)
	var key := "base:furniture:storage_shelf"
	var item_key := "base:resources:furniture:storage_shelf"
	assert(controller.get_defs().size()>=11 and controller.get_defs().has(key))
	var def: Dictionary = controller.get_defs()[key]
	assert(def.item_key==item_key and def.placement=="floor" and def.yaw_steps==4)
	assert(def.footprint.width==1 and def.footprint.depth==1)
	assert(is_equal_approx(float(def.collision_regions[0].max[1]),2.0))
	assert(not def.room_anchor and not def.has("heat_source"))
	var item_def: Dictionary = manager.get_item_def(item_key)
	assert(item_def.model=="res://assets/models/items/furniture/packed_furniture.glb")
	assert(item_def.weight_class=="heavy" and item_def.stack_max==5)
	var dock = load("res://scripts/ui/DockUI.gd").new()
	assert(dock.FURNITURE_PANEL_ITEMS["📥 Storage Shelf"]==key)
	assert("📥 Storage Shelf" in dock._panel_actions("build"))
	for label in dock.FURNITURE_PANEL_ITEMS:
		assert(label in dock._panel_actions("build"))
		assert(controller.get_defs().has(dock.FURNITURE_PANEL_ITEMS[label]))
	dock.free()
	var spawner_script = load("res://scripts/systems/StockpileDesignationController.gd")
	assert(spawner_script.DEV_FURNITURE_MIX[item_key]==1)
	var data := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var registry := root.get_node("PlacedEntityRegistry")
	var nav := root.get_node("NavGrid")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(7,17):
		for z in range(7,17):
			data.set_block(x,20,z,stone)
			for y in range(21,26):
				data.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	var origin := Vector3i(10,20,10)
	manager.spawn_drop(item_key,1,Vector3i(8,21,8))
	var saved: Dictionary = {}
	for yaw in range(4):
		controller._active_key = key
		controller._yaw = yaw
		controller._hover_cell = origin
		assert(controller._placement_valid(origin))
		var ghost_id: int = controller._next_ghost_id
		controller._confirm_ghost()
		var ghost = controller._ghosts[ghost_id]
		assert(ghost.footprint_cells().size()==1)
		assert(not controller._placement_valid(origin)) # no overlapping ghosts
		for cell in ghost.footprint_cells():
			assert(nav.is_walkable(cell))
		var meshes: Array = ghost.node.find_children("*","MeshInstance3D",true,false)
		assert(meshes.size()==1 and is_equal_approx(meshes[0].material_override.albedo_color.a,.3))
		ghost._ensure_claim()
		assert(ghost.item_available())
		var pull: Dictionary = ghost.reserve_fetch(100,Vector3i(9,20,10))
		assert(not pull.is_empty() and pull.heavy)
		# A released fetch can be reclaimed without losing the packed item.
		ghost.cancel_fetch(100)
		pull = ghost.reserve_fetch(100,Vector3i(9,20,10))
		assert(not pull.is_empty())
		dwarf.position = Vector3(9.5,21,10.5)
		dwarf._fetch_source_id = ghost.source_id
		dwarf._fetch_item = pull.item
		dwarf._fetch_heavy = pull.heavy
		dwarf._fetch_pickup()
		assert(dwarf._fetch_picked_up and manager.get_stats().loose==0)
		assert(dwarf._fetch_item.get_parent()==dwarf and dwarf._fetch_item.scale==Vector3.ONE)
		var carried: Node3D = dwarf._fetch_item
		var installed_id: int = controller._next_installed_id
		dwarf._fetch_complete()
		assert(carried.is_queued_for_deletion() and dwarf._carried_entries.is_empty())
		assert(controller._ghosts.is_empty() and controller._installed.size()==1)
		var component = controller._installed[installed_id]
		_check_installed(component,origin,yaw,nav,registry)
		assert(not controller._placement_valid(origin))
		_check_storage(component,manager,origin)
		saved = controller.serialize_state()
		assert(saved.installed.size()==1 and saved.installed[0].key==key)
		component.complete_uninstall(100)
		assert(controller._installed.is_empty() and registry.get_stats().entities==0)
		assert(controller._placement_valid(origin) and manager.get_stats().loose==9)
		# Teardown returns every stored item at native loose-item scale.
		for drop in manager._loose.keys():
			if drop.get_meta("item_key")!=item_key:
				assert(drop.scale==Vector3.ONE)
				assert(not manager.take(drop).is_empty())
				drop.free()
		assert(manager.get_stats().loose==1)
		var refund: Node3D = manager.nearest_loose_of_key(item_key,origin)
		assert(refund!=null and refund.get_meta("item_key")==item_key)
	# Restore the final orientation through the real persistence owner.
	var last_refund: Node3D = manager.nearest_loose_of_key(item_key,origin)
	assert(manager.take(last_refund)==item_key)
	last_refund.free()
	controller.restore_state(saved)
	assert(controller.serialize_state()==saved)
	_check_installed(controller._installed.values()[0],origin,3,nav,registry)
	assert(root.get_node("RoomManager")._heat_cells.is_empty())
	assert(root.get_node("RoomManager")._door_cells.is_empty())
	# Installing furniture never changes terrain or neighboring walkability.
	for x in range(10,12):
		for z in range(10,12):
			for y in range(21,24):
				assert(data.get_block(x,y,z)==blocks.AIR_ID)
	assert(nav.is_walkable(Vector3i(9,20,10)))
	_check_slots(controller._installed.values()[0].storage)
	controller._installed.values()[0].complete_uninstall(100)
	assert(manager.get_stats().loose==9 and registry.get_stats().entities==0)
	# Other container types remain absorbing containers, with fitting disabled.
	for name in ["barrel","storage_chest"]:
		var old_def: Dictionary = controller.get_defs()["base:furniture:"+name]
		controller._install(old_def.furniture_key,old_def,origin,0)
		var other = controller._installed.values()[0]
		assert(not other.storage.render_contents and other.storage.anchor_max_size==Vector3.ZERO)
		other.complete_uninstall(100)
	var report := {"four_rotations":true,"storage_capacity":8,"visible_anchors":8,
		"ghost_nonblocking":true,"native_model_bounds_and_material":true,"terrain_unchanged":true,
		"fetch_release_and_reclaim":true,"dwarf_pickup_and_build_consumes_crate":true,
		"haul_reserve_take_and_deposit":true,"full_shelf_rejects_ninth_item":true,
		"all_slots_fit_rotated_ores_crates_and_flag":true,"withdraw_returns_native_scale":true,
		"uninstall_refunds_shelf_and_all_eight_contents":true,"stocked_save_restore":true,
		"barrel_and_chest_unchanged":true,"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/shelf_redesign_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_SHELF_OK: ",JSON.stringify(report))
	quit(0)

func _check_installed(component,origin: Vector3i,yaw: int,nav,registry) -> void:
	assert(component.node.scale==Vector3.ONE and component.cells.size()==1)
	assert(is_equal_approx(component.node.rotation.y,float(yaw)*PI*.5))
	assert(component.storage!=null and component.storage.capacity==8 and component.storage.render_contents)
	assert(component.occupancy_ids.size()==1)
	var meshes: Array = component.node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()>=1)
	var local: AABB = meshes[0].get_aabb()
	assert(local.position.is_equal_approx(Vector3(-.5,0,-.5)))
	assert(local.size.is_equal_approx(Vector3(1,2,1)))
	var bounds: AABB = meshes[0].global_transform*local
	assert(bounds.position.is_equal_approx(Vector3(origin)+Vector3.UP))
	assert(bounds.size.is_equal_approx(Vector3(1,2,1)))
	var mat: StandardMaterial3D = meshes[0].material_override
	assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
	assert(mat.cull_mode==BaseMaterial3D.CULL_DISABLED and mat.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	for cell in component.cells:
		assert(not nav.is_walkable(cell))
		assert(registry.occupies(cell+Vector3i(0,1,0)))
		assert(registry.occupies(cell+Vector3i(0,2,0)))
		assert(not registry.occupies(cell+Vector3i(0,3,0)))


func _check_storage(component,manager,origin: Vector3i) -> void:
	var storage = component.storage
	storage.drop_manager = manager
	var cargo := {
		"base:resources:furniture:barrel":2,
		"base:resources:ore:copper":2,
		"base:resources:ore:iron":2,
		"base:resources:stone:rough_stone":1,
		"base:items:special:settlement_flag":1,
	}
	for key in cargo:
		manager.spawn_drop(key,cargo[key],origin+Vector3i(-1,1,0))
	assert(manager.get_stats().loose==8)
	_haul_all(storage,manager,origin)
	assert(storage.inventory==cargo and storage.stored_count()==8)
	assert(storage._reserved_slots==0 and manager.get_stats().loose==0)
	assert(storage._reserve_deposit("base:resources:ore:iron",origin,100)==null)
	_check_slots(storage)
	var pulled: Node3D = storage.withdraw_nearest("base:resources:ore:iron",origin,100)
	assert(pulled!=null and pulled.scale==Vector3.ONE)
	assert(storage.stored_count()==7 and manager.get_stats().reserved==1)
	manager.unreserve(pulled,100)
	_haul_all(storage,manager,origin)
	assert(storage.inventory==cargo and storage.stored_count()==8)
	_check_slots(storage)

func _haul_all(storage,manager,origin: Vector3i) -> void:
	var attempts := 0
	while manager.get_stats().loose>0 and storage._has_any_room():
		attempts += 1
		assert(attempts<=8)
		var pull: Dictionary = storage.reserve_haul(100,origin+Vector3i(-1,0,0),{})
		assert(not pull.is_empty())
		var carried: Array = []
		for index in range(pull.items.size()):
			var item: Node3D = storage.take_item(100,index)
			assert(item!=null)
			carried.append([item,String(item.get_meta("item_key"))])
		assert(storage.commit_haul(100,carried))

func _check_slots(storage) -> void:
	assert(storage._anchor_slots.size()==8)
	var boxes: Array[AABB] = []
	for i in range(8):
		var entry: Array = storage._anchor_slots[i]
		var node: Node3D = entry[0]
		assert(node.get_parent()==storage.display_parent and node.visible)
		assert(node.scale.x>0 and node.scale.x<=.50001)
		assert(is_equal_approx(node.scale.x,node.scale.y) and is_equal_approx(node.scale.x,node.scale.z))
		var meshes: Array = node.find_children("*","MeshInstance3D",true,false)
		assert(not meshes.is_empty())
		var bounds := AABB()
		var found := false
		var inverse: Transform3D = storage.display_parent.global_transform.affine_inverse()
		for mesh in meshes:
			var local: AABB = inverse*mesh.global_transform*mesh.get_aabb()
			bounds = bounds.merge(local) if found else local
			found = true
		var anchor: Array = storage.anchors[i]
		var center := Vector3(anchor[0]-.5,anchor[1],anchor[2]-.5)
		var size: Vector3 = storage.anchor_max_size
		var slot := AABB(center-Vector3(size.x*.5,0,size.z*.5),size)
		assert(slot.grow(.00001).encloses(bounds))
		assert(absf(bounds.position.y-center.y)<.00001)
		assert(absf(bounds.get_center().x-center.x)<.00001)
		assert(absf(bounds.get_center().z-center.z)<.00001)
		for prior in boxes:
			assert(not bounds.intersects(prior))
		boxes.append(bounds)
