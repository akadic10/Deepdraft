extends SceneTree

const KEY := "base:furniture:wall_torch"
const ITEM := "base:resources:furniture:wall_torch"
var controller
var manager
var dwarf
var data
var blocks
var nav
var rooms
var registry
var mount
var stone: int
var def: Dictionary
var origin := Vector3i(10,20,10)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Wall torch checks timed out"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	rooms = root.get_node("RoomManager")
	rooms.set_process(false)
	data = root.get_node("WorldData")
	blocks = root.get_node("BlockRegistry")
	nav = root.get_node("NavGrid")
	registry = root.get_node("PlacedEntityRegistry")
	stone = blocks.get_id("base:terrain:rock:rock01")
	mount = load("res://scripts/components/WallFurnitureMount.gd")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	manager = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(manager)
	controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	controller._process(0)
	dwarf = load("res://scripts/entities/DwarfAgent.gd").new()
	dwarf.dwarf_id = 100
	scene.add_child(dwarf)
	dwarf.set_process(false)
	def = controller.get_defs()[KEY]
	assert(def.placement=="wall" and def.collision_regions.is_empty() and not def.blocks_movement)
	assert(def.footprint.width==0 and def.footprint.depth==0 and def.heat_source.heat_units==200)
	assert(manager.get_item_def(ITEM).model=="res://assets/models/items/furniture/packed_furniture.glb")
	var spawner = load("res://scripts/systems/StockpileDesignationController.gd")
	assert(spawner.DEV_FURNITURE_MIX[ITEM]==4)
	for x in range(6,18):
		for z in range(6,18):
			data.set_block(x,20,z,stone)
			for y in range(21,29):
				data.set_block(x,y,z,blocks.AIR_ID)
	await process_frame
	controller._active_key = KEY
	controller._yaw = 0
	assert(not controller._placement_valid(origin)) # empty space cannot support a torch
	manager.spawn_drop(ITEM,1,Vector3i(8,21,8))
	var saved: Dictionary = {}
	var camera := Camera3D.new()
	camera.current = true
	scene.add_child(camera)
	for yaw in range(4):
		_set_wall(yaw,true)
		await process_frame
		controller._active_key = KEY
		controller._yaw = yaw
		assert(controller._placement_valid(origin))
		var ghost = _ghost(origin,yaw)
		assert(ghost.footprint_cells().is_empty() and not controller.blocks_zone_cell(origin))
		assert(ghost.nearest_stand_target(origin)==origin and nav.is_walkable(origin))
		assert(ghost.node.find_children("*","Light3D",true,false).is_empty())
		assert(rooms._heat_cells.is_empty() and not controller._placement_valid(origin))
		for mesh: MeshInstance3D in ghost.node.find_children("*","MeshInstance3D",true,false):
			assert(is_equal_approx(mesh.material_override.albedo_color.a,.3))
			assert(not mesh.material_override.emission_enabled)
		var ghost_save: Dictionary = controller.serialize_state()
		controller.cancel_ghost(ghost.ghost_id)
		controller.restore_state(ghost_save)
		assert(controller.serialize_state()==ghost_save)
		ghost = controller._ghosts.values()[0]
		_pick_up(ghost)
		dwarf._fetch_complete()
		assert(controller._ghosts.is_empty() and manager.get_stats().loose==0)
		var piece = controller._installed.values()[0]
		_check_installed(piece,yaw)
		assert(not controller._placement_valid(origin))
		saved = controller.serialize_state()
		# Actual camera DDA resolves each wall face and selects the mount ahead of terrain.
		var bounds: AABB = mount.bounds_for(def,origin,yaw)
		camera.position = bounds.get_center() - Vector3(mount.back(yaw))*8 + Vector3.UP*2
		camera.look_at(bounds.get_center())
		await process_frame
		var screen: Vector2 = camera.unproject_position(bounds.get_center())
		var hit: Dictionary = controller._surface_cell_for(screen)
		var floor_hit: Dictionary = controller._wall_floor_hit(hit)
		assert(Vector3i(floor_hit.x,floor_hit.y,floor_hit.z)==origin and controller._yaw==yaw)
		assert(controller._try_select_at_screen(screen) and controller._window_installed_id==piece.installed_id)
		# A nearer solid terrain face blocks selection through rock.
		assert(not controller._try_select_wall(screen,{"distance":1.0}))
		controller._on_slice_changed(23)
		var light: OmniLight3D = piece.node.find_child("FurnitureLight",true,false)
		assert(not piece.node.visible and not light.is_visible_in_tree())
		assert(not controller._try_select_wall(screen,{}))
		controller._on_slice_changed(24)
		assert(light.is_visible_in_tree())
		controller._on_slice_changed(127)
		piece.complete_uninstall(100)
		assert(controller._installed.is_empty() and registry.get_stats().entities==0)
		assert(nav.is_walkable(origin) and manager.get_stats().loose==1 and rooms._heat_cells.is_empty())
		_set_wall(yaw,false)
	# Restore a live torch, including its light, heat and uninstall flag.
	_set_wall(3,true)
	_clear_loose()
	controller.restore_state(saved)
	assert(controller.serialize_state()==saved)
	_check_installed(controller._installed.values()[0],3)
	var piece = controller._installed.values()[0]
	var animation_report: Dictionary = _check_animation(piece)
	piece.set_uninstall(true)
	assert(piece.flagged_uninstall and piece._lease_id>=0)
	var flagged: Dictionary = controller.serialize_state()
	controller.dev_remove_installed(piece.installed_id)
	_clear_loose()
	controller.restore_state(flagged)
	piece = controller._installed.values()[0]
	assert(piece.flagged_uninstall and piece._lease_id>=0 and controller.serialize_state()==flagged)
	# A real support edit triggers normal teardown, refunds once and removes heat/light.
	var support: Vector3i = mount.supports(def,origin,3)[0]
	data.set_block(support.x,support.y,support.z,blocks.AIR_ID)
	await process_frame
	controller._process(0)
	assert(controller._installed.is_empty() and controller._wall_to_installed.is_empty())
	assert(rooms._heat_cells.is_empty() and manager.get_stats().loose==1)
	controller._process(0)
	assert(manager.get_stats().loose==1)
	_set_wall(3,false)
	_set_wall(0,true)
	await process_frame
	controller._active_key = KEY
	controller._yaw = 0
	# Three-high ceilings cannot intersect the raised flame.
	data.set_block(origin.x,24,origin.z,stone)
	assert(not controller._placement_valid(origin))
	data.set_block(origin.x,24,origin.z,blocks.AIR_ID)
	# A low floor container may share the anchor without losing either index.
	var chest_def: Dictionary = controller.get_defs()["base:furniture:storage_chest"]
	controller._install(chest_def.furniture_key,chest_def,origin,0)
	assert(controller._placement_valid(origin))
	controller._install(KEY,def,origin,0)
	assert(controller._cell_to_installed.has(origin) and controller._wall_to_installed.size()==1)
	var wall_id: int = controller._wall_to_installed.values()[0]
	controller.dev_remove_installed(wall_id)
	assert(controller._cell_to_installed.has(origin))
	controller.dev_remove_installed(controller._cell_to_installed[origin])
	_clear_loose()
	manager.spawn_drop(ITEM,1,Vector3i(8,21,8))
	# A tall pending floor piece must not overlap a torch, in either placement order.
	var door_def: Dictionary = controller.get_defs()["base:furniture:door"]
	controller._install(KEY,def,origin,0)
	controller._active_key = door_def.furniture_key
	assert(not controller._placement_valid(origin))
	controller.dev_remove_installed(controller._wall_to_installed.values()[0])
	_clear_loose()
	controller._active_key = door_def.furniture_key
	controller._hover_cell = origin
	controller._confirm_ghost()
	controller._active_key = KEY
	controller._yaw = 0
	assert(not controller._placement_valid(origin))
	controller.cancel_ghost(controller._ghosts.keys()[0])
	manager.spawn_drop(ITEM,1,Vector3i(8,21,8))
	var ghost = _ghost(origin,0)
	_pick_up(ghost)
	# Lose support immediately before completion, without waiting for notification.
	support = mount.supports(def,origin,0)[0]
	data.set_block(support.x,support.y,support.z,blocks.AIR_ID)
	dwarf._fetch_complete()
	assert(controller._installed.is_empty() and dwarf._carried_entries.is_empty())
	assert(manager.get_stats().loose==1) # intact crate dropped at worker's feet
	await process_frame
	controller._process(0)
	assert(controller._ghosts.is_empty() and controller._wall_to_ghost.is_empty())
	assert(manager.get_stats().loose==1)
	var heat_report: Dictionary = await _check_room_heat()
	var layouts: Array = await _check_menu(scene)
	_check_live_terrain_shadow_paths()
	var report := {"placeable_definitions":controller.get_defs().size(),"four_wall_orientations":true,
		"real_camera_wall_hits_and_selection":true,"occlusion_and_slice_gate":true,
		"no_floor_reservation_or_nav_occupancy":true,"ghosts_have_no_light_or_heat":true,
		"ghost_and_installed_save_restore":true,"uninstall_flag_restore":true,
		"real_dwarf_fetch_and_build":true,"release_and_reclaim":true,
		"support_mining_refunds_once":true,"support_loss_during_completion_preserves_crate":true,
		"low_furniture_coexistence":true,"tall_furniture_overlap_rejected_both_orders":true,
		"sealed_room_heat":heat_report,"build_panel_layouts":layouts,
		"all_four_live_terrain_shadow_paths":true,"flame_animation":animation_report,
		"player_saves_touched":false}
	var file := FileAccess.open("res://tmp/wall_torch_preview/runtime_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("LIVE_WALL_TORCH_OK: ",JSON.stringify(report))
	quit(0)

func _set_wall(yaw: int, solid: bool) -> void:
	var cell: Vector3i = origin + mount.back(yaw)
	for y in range(21,25):
		data.set_block(cell.x,y,cell.z,stone if solid else blocks.AIR_ID)

func _ghost(at: Vector3i,yaw: int):
	controller._active_key = KEY
	controller._yaw = yaw
	controller._hover_cell = at
	var id: int = controller._next_ghost_id
	controller._confirm_ghost()
	return controller._ghosts[id]

func _pick_up(ghost) -> void:
	ghost._ensure_claim()
	var pull: Dictionary = ghost.reserve_fetch(100,origin)
	assert(not pull.is_empty() and pull.heavy)
	ghost.cancel_fetch(100)
	pull = ghost.reserve_fetch(100,origin)
	assert(not pull.is_empty())
	dwarf.position = Vector3(origin)+Vector3(.5,1,.5)
	dwarf._fetch_source_id = ghost.source_id
	dwarf._fetch_item = pull.item
	dwarf._fetch_heavy = pull.heavy
	dwarf._fetch_pickup()
	assert(dwarf._fetch_picked_up and dwarf._fetch_item.get_parent()==dwarf)
	assert(ghost.can_complete_build())

func _check_installed(piece,yaw: int) -> void:
	assert(piece.cells.is_empty() and piece.occupancy_ids.is_empty() and piece.storage==null)
	assert(piece.node.scale==Vector3.ONE and piece.nearest_stand_target(origin)==origin)
	assert(nav.is_walkable(origin) and not controller.blocks_zone_cell(origin))
	assert(rooms._heat_cells[origin]==200 and registry.get_stats().entities==0)
	var meshes: Array = piece.node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==2)
	var combined: AABB = meshes[0].global_transform*meshes[0].get_aabb()
	combined = combined.merge(meshes[1].global_transform*meshes[1].get_aabb())
	var expected: AABB = mount.bounds_for(def,origin,yaw)
	assert(expected.grow(.0001).encloses(combined)) # every animated frame fits the original mount
	for mesh: MeshInstance3D in meshes:
		var mat: StandardMaterial3D = mesh.material_override
		assert(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb)
		assert(mat.emission_enabled==(mesh.name=="torch_flame"))
	var light: OmniLight3D = piece.node.find_child("FurnitureLight",true,false)
	assert(light!=null and light.shadow_enabled and is_equal_approx(light.omni_range,7))
	assert(light.light_energy>=1.44 and light.light_energy<=1.76)
	assert(piece.node.find_child("FlameAnimation",true,false)!=null)

func _check_animation(piece) -> Dictionary:
	var animator = piece.node.find_child("FlameAnimation",true,false)
	assert(animator!=null and animator._frames.size()==8)
	var flame: MeshInstance3D = piece.node.find_child("torch_flame",true,false)
	var body: MeshInstance3D = piece.node.find_child("torch_body",true,false)
	var original_body: Mesh = body.mesh
	var light: OmniLight3D = piece.node.find_child("FurnitureLight",true,false)
	var frames := {}
	var energies := {}
	var emissions := {}
	var expected: AABB = mount.bounds_for(def,piece.origin_cell,piece.yaw_steps)
	for sample in range(240):
		animator._process(1.0/60.0)
		frames[flame.mesh.get_instance_id()] = true
		energies[snappedf(light.light_energy,.0001)] = true
		emissions[snappedf(flame.material_override.emission_energy_multiplier,.0001)] = true
		assert(expected.grow(.0001).encloses(flame.global_transform*flame.get_aabb()))
		assert(body.mesh==original_body and body.transform==Transform3D.IDENTITY)
		assert(light.light_energy>=1.44 and light.light_energy<=1.76)
		assert(flame.material_override.emission_energy_multiplier>=.92 and flame.material_override.emission_energy_multiplier<=1.08)
	assert(frames.size()==8 and energies.size()>20 and emissions.size()>20)
	var before_save: Dictionary = controller.serialize_state()
	assert(rooms._heat_cells[origin]==200 and registry.get_stats().entities==0)
	# The second instance shares the mesh library but not phase or emissive material.
	var second: Node3D = controller._instance_model(KEY,controller._make_solid_material())
	current_scene.add_child(second)
	second.position = Vector3(15.5,23.5,10)
	load("res://scripts/components/FurnitureLighting.gd").attach(second,def)
	var other = second.find_child("FlameAnimation",true,false)
	assert(other._phase!=animator._phase)
	assert(other._frames[0]==animator._frames[0] and other._material!=animator._material)
	second.free()
	# Hidden slices stop animation work and resume the same frame on reveal.
	controller._on_slice_changed(23)
	assert(not animator.is_processing())
	var time_before: float = animator._elapsed
	animator._process(1.0)
	assert(animator._elapsed==time_before)
	controller._on_slice_changed(127)
	assert(animator.is_processing())
	animator._process(.1)
	assert(animator._elapsed>time_before)
	assert(controller.serialize_state()==before_save)
	return {"visible_frames":frames.size(),"distinct_light_samples":energies.size(),
		"distinct_emission_samples":emissions.size(),"original_bounds_respected":true,
		"bracket_and_handle_static":true,"shared_clip_independent_phases":true,
		"hidden_slice_suspends_updates":true,"heat_and_saved_state_unchanged":true}

func _clear_loose() -> void:
	for child in manager.get_children():
		if child is Node3D and child.has_meta("item_key"):
			manager.take(child)
			child.free()

func _check_room_heat() -> Dictionary:
	# A 5x5x4 sealed volume with a two-wide door; heat is tested through the
	# actual flood fill/formula, including a hearth sharing the torch's anchor.
	for x in range(27,34):
		for z in range(27,34):
			for y in range(20,26):
				var shell := x in [27,33] or z in [27,33] or y in [20,25]
				data.set_block(x,y,z,stone if shell else blocks.AIR_ID)
	for x in [29,30]:
		for y in range(21,25):
			data.set_block(x,y,33,blocks.AIR_ID)
	await process_frame
	var door: Dictionary = controller.get_defs()["base:furniture:door"]
	controller._install(door.furniture_key,door,Vector3i(29,20,33),0)
	rooms._rebuild_all_rooms()
	var room: Dictionary = rooms.get_room_at(Vector3i(30,21,30))
	assert(not room.is_empty() and room.volume==100 and room.heat_units==0)
	var baseline: float = room.temp_c
	var anchor := Vector3i(28,20,28)
	controller._install(KEY,def,anchor,0)
	var torch_id: int = controller._wall_to_installed[controller._wall_key(anchor,0)]
	var hearth: Dictionary = controller.get_defs()["base:furniture:hearth"]
	controller._install(hearth.furniture_key,hearth,anchor,0)
	controller._install(KEY,def,Vector3i(32,20,28),0)
	assert(rooms._heat_cells[anchor]==600)
	rooms._rebuild_all_rooms()
	room = rooms.get_room_at(Vector3i(30,21,30))
	assert(room.heat_units==800 and is_equal_approx(room.temp_c-baseline,8.0))
	controller.dev_remove_installed(torch_id)
	assert(rooms._heat_cells[anchor]==400)
	rooms._rebuild_all_rooms()
	room = rooms.get_room_at(Vector3i(30,21,30))
	assert(room.heat_units==600 and is_equal_approx(room.temp_c-baseline,6.0))
	for id: int in controller._installed.keys():
		controller.dev_remove_installed(id)
	assert(rooms._heat_cells.is_empty() and rooms._door_cells.is_empty())
	return {"volume":100,"two_torches_and_hearth":800,"temperature_bonus_c":8,
		"one_torch_removed":600,"remaining_bonus_c":6,"shared_anchor_heat_preserved":true}

func _check_menu(scene: Node) -> Array:
	var dock = load("res://tools/BedBuildPanelFixture.gd").new()
	scene.add_child(dock)
	dock.set_process(false)
	dock._furniture_controller = controller
	root.get_node("WorldGenerator")._maps_ready = true
	var layouts: Array = []
	for viewport_size in [Vector2i(1280,800),Vector2i(2560,1440)]:
		root.size = viewport_size
		dock._open_action_panel("build")
		for frame in range(4):
			await process_frame
		var panel: Rect2 = dock._panel_container.get_global_rect()
		assert(panel.position.x>=0 and panel.end.x<=viewport_size.x)
		assert(panel.position.y>=0 and panel.end.y<=viewport_size.y-dock.PANEL_BOTTOM_MARGIN+.1)
		assert(dock._panel_body.get_child_count()==14)
		var torch_button: Button
		var rows := {}
		for button: Button in dock._panel_body.get_children():
			var rect: Rect2 = button.get_global_rect()
			assert(panel.encloses(rect))
			rows[rect.position.y] = true
			if button.text=="📥 Wall Torch":
				torch_button = button
		assert(rows.size()==3 and torch_button!=null)
		torch_button.pressed.emit()
		assert(controller._active and controller._active_key==KEY)
		controller.deactivate()
		layouts.append({"viewport":str(viewport_size),"panel":str(panel),"buttons":14,"rows":3})
	dock.queue_free()
	return layouts

func _check_live_terrain_shadow_paths() -> void:
	var helper = load("res://scripts/components/TerrainLighting.gd")
	# Exercise each actual node factory without starting world generation.
	var renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	renderer._material = renderer._create_material()
	var meshes: Array[MeshInstance3D] = [renderer._get_or_create_node(Vector3i.ZERO,0,0,0),
		renderer._get_or_create_region_node(Vector2i.ZERO),
		renderer._get_or_create_overview_tile_node(Vector2i.ZERO)]
	renderer._rebuild_cavity_shell()
	meshes.append(renderer._cavity_shell_node)
	for mesh in meshes:
		assert(mesh.layers==helper.TERRAIN_LAYER)
		assert(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		assert(mesh.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	renderer.free()
