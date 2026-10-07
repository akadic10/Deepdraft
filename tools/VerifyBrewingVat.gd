extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Brewing vat check timed out");quit(1))
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
	var key := "base:furniture:brewing_vat"
	var item_key := "base:resources:furniture:brewing_vat"
	assert(controller.get_defs().size()>=12 and controller.get_defs().has(key))
	var def: Dictionary = controller.get_defs()[key]
	assert(def.item_key==item_key and def.placement=="floor" and def.yaw_steps==4)
	assert(def.footprint.width==2 and def.footprint.depth==2)
	assert(is_equal_approx(float(def.collision_regions[0].max[1]),2.0))
	assert(not def.room_anchor and not def.has("heat_source") and not def.has("storage"))
	var item_def: Dictionary = manager.get_item_def(item_key)
	assert(item_def.model=="res://assets/models/items/furniture/packed_furniture.glb")
	assert(item_def.weight_class=="heavy" and item_def.stack_max==5)
	var dock = load("res://scripts/ui/DockUI.gd").new()
	assert(dock.FURNITURE_PANEL_ITEMS["📥 Brewing Vat"]==key)
	assert("📥 Brewing Vat" in dock._panel_actions("build"))
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
	# The vat never changes terrain or obstructs neighboring cells.
	for x in range(10,12):
		for z in range(10,12):
			for y in range(21,24):
				assert(data.get_block(x,y,z)==blocks.AIR_ID)
	assert(nav.is_walkable(Vector3i(9,20,10)))
	controller._installed.values()[0].complete_uninstall(100)
	var menu_sizes: Array = await _check_build_menu(scene,controller)
	assert(root.get_node("RoomManager")._heat_cells.is_empty())
	assert(root.get_node("RoomManager")._door_cells.is_empty())
	var report := {"placeable_definitions":controller.get_defs().size(),"build_menu_mapping":true,"dev_spawner_entry":true,
		"four_rotations":true,"two_vertical_layers_occupied":true,"terrain_unchanged":true,
		"ghost_nonblocking":true,"rotated_bounds_match_collision":true,
		"fetch_reservation_release_and_reclaim":true,"dwarf_pickup_and_build_consumes_crate":true,
		"uninstall_refunds_same_item":true,"in_memory_installed_save_restore":true,
		"no_room_heat_or_door_side_effects":true,"player_saves_touched":false,
		"build_panel_layouts":menu_sizes,"actual_vat_button_dispatch":true}
	var file := FileAccess.open("res://tmp/brewing_vat_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_BREWING_VAT_OK: ",JSON.stringify(report))
	quit(0)

func _check_installed(component,origin: Vector3i,yaw: int,nav,registry) -> void:
	assert(component.node.scale==Vector3.ONE and component.cells.size()==4)
	assert(is_equal_approx(component.node.rotation.y,float(yaw)*PI*.5))
	assert(component.storage==null and component.occupancy_ids.size()==1)
	var meshes: Array = component.node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==1)
	var local: AABB = meshes[0].get_aabb()
	assert(local.position.is_equal_approx(Vector3(-1,0,-1)))
	assert(local.size.is_equal_approx(Vector3(2,2,2)))
	var bounds: AABB = meshes[0].global_transform*local
	assert(bounds.position.is_equal_approx(Vector3(origin)+Vector3.UP))
	assert(bounds.size.is_equal_approx(Vector3(2,2,2)))
	var mat: StandardMaterial3D = meshes[0].material_override
	assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
	assert(mat.cull_mode==BaseMaterial3D.CULL_DISABLED and mat.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	for cell in component.cells:
		assert(not nav.is_walkable(cell))
		assert(registry.occupies(cell+Vector3i(0,1,0)))
		assert(registry.occupies(cell+Vector3i(0,2,0)))
		assert(not registry.occupies(cell+Vector3i(0,3,0)))

func _check_build_menu(scene: Node,controller) -> Array:
	var dock = load("res://tools/BedBuildPanelFixture.gd").new()
	scene.add_child(dock)
	dock.set_process(false)
	dock._furniture_controller = controller
	# The in-memory floor is ready; no terrain generation or player save is involved.
	root.get_node("WorldGenerator")._maps_ready = true
	var layouts: Array = []
	for viewport_size in [Vector2i(1280,800),Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._open_action_panel("build")
		for frame in range(4):
			await process_frame
		var panel: Rect2 = dock._panel_container.get_global_rect()
		assert(panel.position.x>=0 and panel.end.x<=viewport_size.x)
		assert(panel.position.y>=0 and panel.end.y<=dock._dock_panel.position.y-dock.PANEL_DOCK_GAP+.1)
		assert(is_equal_approx(panel.get_center().x,viewport_size.x*.5))
		var expected_buttons: int = dock._panel_actions("build").size()
		var expected_rows := ceili(float(expected_buttons)/dock._panel_body.columns)
		assert(dock._panel_body.get_child_count()==expected_buttons)
		var rows := {}
		var vat_button: Button
		for button: Button in dock._panel_body.get_children():
			var rect: Rect2 = button.get_global_rect()
			assert(panel.encloses(rect) and rect.size.x>=128 and rect.size.y>=46)
			rows[rect.position.y] = true
			if button.text=="📥 Brewing Vat":
				vat_button = button
		assert(rows.size()==expected_rows and vat_button!=null)
		layouts.append({"viewport":str(viewport_size),"panel":str(panel),"rows":rows.size(),"buttons":expected_buttons})
		vat_button.pressed.emit()
		assert(controller._active and controller._active_key=="base:furniture:brewing_vat")
		assert(not dock._panel_container.visible)
		controller.deactivate()
		# A smaller action panel remains usable after rebuilding the grid.
		dock._open_action_panel("save_load")
		for frame in range(4):
			await process_frame
		assert(dock._panel_body.get_child_count()==3)
		var first: Rect2 = dock._panel_body.get_child(0).get_global_rect()
		var last: Rect2 = dock._panel_body.get_child(2).get_global_rect()
		assert(is_equal_approx(first.position.y,last.position.y))
	dock.queue_free()
	return layouts
