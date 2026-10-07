extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Chair check timed out");quit(1))
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
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var dwarf = factory.spawn(factory.generate(100, {}), 100)
	scene.add_child(dwarf)
	dwarf.set_process(false)
	var key := "base:furniture:wooden_chair"
	var item_key := "base:resources:furniture:wooden_chair"
	assert(controller.get_defs().size()>=10 and controller.get_defs().has(key))
	var def: Dictionary = controller.get_defs()[key]
	assert(def.item_key==item_key and def.placement=="floor" and def.yaw_steps==4)
	assert(def.footprint.width==2 and def.footprint.depth==2)
	assert(is_equal_approx(float(def.collision_regions[0].max[1]),1.375))
	assert(not def.room_anchor and not def.has("heat_source") and not def.has("storage"))
	var item_def: Dictionary = manager.get_item_def(item_key)
	assert(item_def.model=="res://assets/models/items/furniture/packed_furniture.glb")
	assert(item_def.weight_class=="heavy" and item_def.stack_max==5)
	var dock = load("res://scripts/ui/DockUI.gd").new()
	assert(dock.FURNITURE_PANEL_ITEMS["📥 Wooden Chair"]==key)
	assert("📥 Wooden Chair" in dock._panel_actions("build"))
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
		assert(ghost.footprint_cells().size()==4)
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
		dwarf._process_item_handling(dwarf._handling_duration * .5)
		assert(dwarf._fetch_picked_up and manager.get_stats().loose==0)
		assert(dwarf._fetch_item.get_parent()==dwarf and dwarf._fetch_item.scale.is_equal_approx(Vector3.ONE))
		var carried: Node3D = dwarf._fetch_item
		var installed_id: int = controller._next_installed_id
		dwarf._begin_fetch_deposit()
		dwarf._process_item_handling(dwarf._handling_duration)
		assert(carried.is_queued_for_deletion() and dwarf._carried_entries.is_empty())
		assert(controller._ghosts.is_empty() and controller._installed.size()==1)
		var component = controller._installed[installed_id]
		_check_installed(component,origin,yaw,nav,registry)
		assert(not controller._placement_valid(origin))
		saved = controller.serialize_state()
		assert(saved.installed.size()==1 and saved.installed[0].key==key)
		component.complete_uninstall(100)
		assert(controller._installed.is_empty() and registry.get_stats().entities==0)
		assert(controller._placement_valid(origin) and manager.get_stats().loose==1)
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
	# A table on the neighboring cells remains independent through save/restore and removal.
	var chair_id: int = controller._installed.keys()[0]
	var table_key := "base:furniture:wooden_table"
	var table_origin := origin+Vector3i(3,0,0)
	var table_id: int = controller._next_installed_id
	controller._install(table_key,controller.get_defs()[table_key],table_origin,0)
	assert(controller._installed.size()==2)
	var pair: Dictionary = controller.serialize_state()
	# Restore populates a cleared scene, as SaveManager does during a real load.
	controller._installed[chair_id].complete_uninstall(100)
	controller._installed[table_id].complete_uninstall(100)
	for packed_key in [item_key,"base:resources:furniture:wooden_table"]:
		var drop: Node3D = manager.nearest_loose_of_key(packed_key,origin)
		assert(manager.take(drop)==packed_key)
		drop.free()
	assert(controller._installed.is_empty() and registry.get_stats().entities==0)
	controller.restore_state(pair)
	assert(controller.serialize_state()==pair)
	assert(controller._installed.size()==2)
	controller._installed[chair_id].complete_uninstall(100)
	assert(controller._installed.size()==1 and controller._installed.has(table_id))
	assert(manager.get_stats().loose==1)
	var chair_refund: Node3D = manager.nearest_loose_of_key(item_key,origin)
	assert(chair_refund!=null and chair_refund.get_meta("item_key")==item_key)
	assert(not registry.occupies(origin+Vector3i.UP))
	assert(registry.occupies(table_origin+Vector3i.UP))
	var table_saved: Dictionary = controller.serialize_state()
	assert(table_saved.installed[0].key==table_key)
	controller._installed[table_id].complete_uninstall(100)
	assert(controller._installed.is_empty() and registry.get_stats().entities==0)
	assert(manager.get_stats().loose==2)
	assert(manager.nearest_loose_of_key("base:resources:furniture:wooden_table",table_origin)!=null)
	assert(root.get_node("RoomManager")._heat_cells.is_empty())
	assert(root.get_node("RoomManager")._door_cells.is_empty())
	var report := {"placeable_definitions":controller.get_defs().size(),"build_menu_mapping":true,"dev_spawner_entry":true,
		"four_rotations":true,"two_layers_occupied":true,"terrain_unchanged":true,
		"chair_and_table_independent":true,"ghost_nonblocking":true,"rotated_bounds_match_collision":true,
		"fetch_reservation_release_and_reclaim":true,"dwarf_pickup_and_build_consumes_crate":true,
		"uninstall_refunds_same_item":true,"in_memory_installed_save_restore":true,
		"no_room_heat_or_door_side_effects":true,"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/chair_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_CHAIR_OK: ",JSON.stringify(report))
	quit(0)

func _check_installed(component,origin: Vector3i,yaw: int,nav,registry) -> void:
	assert(component.node.scale==Vector3.ONE and component.cells.size()==4)
	assert(is_equal_approx(component.node.rotation.y,float(yaw)*PI*.5))
	assert(component.storage==null and component.occupancy_ids.size()==1)
	var meshes: Array = component.node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==1)
	var local: AABB = meshes[0].get_aabb()
	assert(local.position.is_equal_approx(Vector3(-1,0,-1)))
	assert(local.size.is_equal_approx(Vector3(2,1.375,2)))
	var bounds: AABB = meshes[0].global_transform*local
	assert(bounds.position.is_equal_approx(Vector3(origin)+Vector3.UP))
	assert(bounds.size.is_equal_approx(Vector3(2,1.375,2)))
	var mat: StandardMaterial3D = meshes[0].material_override
	assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
	assert(mat.cull_mode==BaseMaterial3D.CULL_DISABLED and mat.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	for cell in component.cells:
		assert(not nav.is_walkable(cell))
		assert(registry.occupies(cell+Vector3i(0,1,0)))
		assert(registry.occupies(cell+Vector3i(0,2,0)))
		assert(not registry.occupies(cell+Vector3i(0,3,0)))
