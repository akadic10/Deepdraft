extends SceneTree

const KEY := "base:furniture:hearth"
const ORIGIN := Vector3i(8,20,8)
var controller: Node3D
var definition: Dictionary
var rooms: Node
var registry: Node
var nav: Node

func _init() -> void:
	_run.call_deferred()

func _model(node: Node3D,ghost: bool = false) -> void:
	assert(node.scale == Vector3.ONE)
	var meshes := node.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size() == 2)
	var envelope := AABB(Vector3(-1,0,-1),Vector3(2,2,2))
	for mesh: MeshInstance3D in meshes:
		assert(envelope.grow(.0001).encloses(mesh.get_aabb()))
		assert(mesh.transform==Transform3D.IDENTITY)
		var material: StandardMaterial3D = mesh.material_override
		assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
		assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED)
		if ghost:
			assert(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
			assert(is_equal_approx(material.albedo_color.a,.3) and not material.emission_enabled)
		elif mesh.name=="hearth_flame":
			assert(material.emission_enabled and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		else:
			assert(not material.emission_enabled and material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL)
			assert(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	if ghost:
		assert(node.find_children("*","Light3D",true,false).is_empty())
		assert(node.find_child("FlameAnimation",true,false)==null)
	else:
		assert(node.find_children("*","Light3D",true,false).size()==1)
		var light: OmniLight3D = node.find_child("FurnitureLight",true,false)
		assert(light.position==Vector3(0,1.375,0) and light.shadow_enabled)
		assert(light.omni_range==8 and light.is_visible_in_tree())
		assert(node.find_child("FlameAnimation",true,false)!=null)

func _check_animation(piece) -> Dictionary:
	var animator = piece.node.find_child("FlameAnimation",true,false)
	var flame: MeshInstance3D = piece.node.find_child("hearth_flame",true,false)
	var body: MeshInstance3D = piece.node.find_child("hearth_body",true,false)
	var original_body: Mesh = body.mesh
	var light: OmniLight3D = piece.node.find_child("FurnitureLight",true,false)
	var frames := {}
	var energies := {}
	var emissions := {}
	var before_save: Dictionary = controller.serialize_state()
	var envelope := AABB(Vector3(-1,0,-1),Vector3(2,2,2))
	for sample in range(300):
		animator._process(1.0/60.0)
		frames[flame.mesh.get_instance_id()] = true
		energies[snappedf(light.light_energy,.0001)] = true
		emissions[snappedf(flame.material_override.emission_energy_multiplier,.0001)] = true
		assert(envelope.grow(.0001).encloses(flame.get_aabb()))
		assert(body.mesh==original_body and body.transform==Transform3D.IDENTITY)
		assert(light.light_energy>=1.84 and light.light_energy<=2.16)
		assert(flame.material_override.emission_energy_multiplier>=.7905 and flame.material_override.emission_energy_multiplier<=.9095)
		assert(rooms._heat_cells[ORIGIN]==400)
	assert(frames.size()==10 and energies.size()>20 and emissions.size()>20)
	# Separate hearths share mesh resources while keeping individual flicker timing.
	var second: Node3D = controller._instance_model(KEY,controller._make_solid_material())
	current_scene.add_child(second)
	second.position = Vector3(15,21,10)
	load("res://scripts/components/FurnitureLighting.gd").attach(second,definition)
	var other = second.find_child("FlameAnimation",true,false)
	assert(other._phase!=animator._phase)
	assert(other._frames[0]==animator._frames[0] and other._material!=animator._material)
	second.free()
	controller._on_slice_changed(20)
	assert(not animator.is_processing() and not light.is_visible_in_tree())
	var elapsed: float = animator._elapsed
	animator._process(1.0)
	assert(animator._elapsed==elapsed)
	controller._on_slice_changed(127)
	assert(animator.is_processing() and light.is_visible_in_tree())
	animator._process(.1)
	assert(animator._elapsed>elapsed)
	assert(controller.serialize_state()==before_save)
	return {"visible_frames":frames.size(),"distinct_light_samples":energies.size(),
		"distinct_emission_samples":emissions.size(),"original_bounds_respected":true,
		"stone_grate_logs_static":true,"shared_clip_independent_phases":true,
		"hidden_slice_suspends_updates":true,"heat_and_saved_state_unchanged":true}

func _room() -> Dictionary:
	rooms._rebuild_all_rooms()
	var all_rooms: Dictionary = rooms.get_rooms()
	assert(all_rooms.size() == 1)
	var room: Dictionary = all_rooms.values()[0]
	assert(room.volume == 64)
	return room

func _verify_installed(component,heat_temp: float) -> void:
	assert(component.cells.size() == 4 and component.occupancy_ids.size() == 1)
	assert(component.node.position == Vector3(9,21,9))
	_model(component.node)
	for dx in range(2):
		for dz in range(2):
			var cell := ORIGIN+Vector3i(dx,0,dz)
			assert(controller.blocks_zone_cell(cell))
			assert(not nav.is_walkable(cell))
			for dy in range(1,3):
				assert(registry.occupies(cell+Vector3i(0,dy,0)))
			assert(not registry.occupies(cell+Vector3i(0,3,0)))
	assert(not registry.occupies(ORIGIN+Vector3i(2,1,0)))
	assert(nav.is_walkable(ORIGIN+Vector3i(2,0,0)))
	assert(not component.cells.has(component.nearest_stand_target(Vector3i(11,20,11))))
	var room := _room()
	assert(room.heat_units == 400)
	assert(is_equal_approx(float(room.temp_c)-heat_temp,6.25))

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Hearth check timed out");quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	rooms = root.get_node("RoomManager")
	rooms.set_process(false)
	registry = root.get_node("PlacedEntityRegistry")
	nav = root.get_node("NavGrid")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(controller)
	controller.set_process(false)
	definition = controller.get_defs()[KEY]
	assert(int(definition.footprint.width)==2 and int(definition.footprint.depth)==2)
	assert(definition.collision_regions.size()==1)
	for axis in range(3):
		assert(int(definition.collision_regions[0].min[axis])==0)
		assert(int(definition.collision_regions[0].max[axis])==2)
	assert(definition.heat_source.heat_units == 400)
	var data := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	assert(stone>0)
	# Materialized, sealed 4x4x4 room in a dedicated in-memory fixture.
	# Neither player save files nor the main world are loaded or written.
	for x in range(6,14):
		for z in range(6,14):
			for y in range(19,27):
				data.set_block(x,y,z,stone)
	for x in range(8,12):
		for z in range(8,12):
			for y in range(21,25):
				data.set_block(x,y,z,blocks.AIR_ID)
	for x in range(8,10):
		for y in range(21,25):
			data.set_block(x,y,7,blocks.AIR_ID)
	var door: Dictionary = controller.get_defs()["base:furniture:door"]
	controller._install("base:furniture:door",door,Vector3i(8,20,7),0)
	await process_frame
	var baseline := _room()
	assert(baseline.heat_units == 0)
	var baseline_temp: float = baseline.temp_c
	var checked := 0
	var animation_report: Dictionary = {}
	for yaw in range(4):
		controller._active_key = KEY
		controller._yaw = yaw
		assert(controller._placement_valid(ORIGIN))
		# A missing floor in any of the four cells must reject placement.
		for dx in range(2):
			for dz in range(2):
				var cell := ORIGIN+Vector3i(dx,0,dz)
				data.set_block(cell.x,cell.y,cell.z,blocks.AIR_ID)
				await process_frame
				assert(not controller._placement_valid(ORIGIN))
				data.set_block(cell.x,cell.y,cell.z,stone)
				await process_frame
		controller._hover_cell = ORIGIN
		var ghost_id: int = controller._next_ghost_id
		controller._confirm_ghost()
		var ghost = controller._ghosts[ghost_id]
		assert(ghost.footprint_cells().size()==4)
		assert(ghost.node.position == Vector3(9,21,9))
		assert(is_equal_approx(ghost.node.rotation.y,yaw*PI*.5))
		_model(ghost.node,true)
		for cell: Vector3i in ghost.footprint_cells():
			assert(controller.blocks_zone_cell(cell) and nav.is_walkable(cell))
			assert(not registry.occupies(cell+Vector3i.UP))
		var installed_id: int = controller._next_installed_id
		# Exercise the real build-completion path, retaining the common install.
		controller._on_ghost_build_complete(ghost)
		assert(not controller._ghosts.has(ghost_id))
		_verify_installed(controller._installed[installed_id],baseline_temp)
		assert(not controller._placement_valid(ORIGIN+Vector3i(1,0,1)))
		var old_node: Node3D = controller._installed[installed_id].node
		controller.dev_remove_installed(installed_id)
		assert(not old_node.visible and not old_node.find_child("FlameAnimation",true,false).is_processing())
		assert(_room().heat_units==0 and controller._placement_valid(ORIGIN))
		checked += 1
	# Round-trip one installed hearth and one pending 2x2 ghost via the actual
	# furniture save owner, including IDs, rotation and the shared item key.
	controller._install(KEY,definition,ORIGIN,3)
	controller._active_key = KEY
	controller._yaw = 1
	controller._hover_cell = Vector3i(10,20,10)
	controller._confirm_ghost()
	var state: Dictionary = JSON.parse_string(JSON.stringify(controller.serialize_state()))
	for id in controller._ghosts.keys():
		controller.cancel_ghost(id)
	for id in controller._installed.keys():
		controller.dev_remove_installed(id)
	assert(registry.get_stats().entities == 0 and rooms._heat_cells.is_empty())
	controller.restore_state(state)
	assert(controller._installed.size()==2 and controller._ghosts.size()==1)
	for component in controller._installed.values():
		if component.furniture_key == KEY:
			_verify_installed(component,baseline_temp)
			animation_report = _check_animation(component)
			assert(component.yaw_steps==3 and component.item_key=="base:resources:furniture:hearth")
	assert(controller._ghosts.values()[0].footprint_cells().size()==4)
	assert(JSON.parse_string(JSON.stringify(controller.serialize_state()))==state)
	var report := {"rotations_checked":checked,"missing_floor_rejections":16,
		"flame_animation":animation_report,"model_scale_bounds_material_valid":true,"ghost_nonblocking":true,
		"four_cell_placement_and_navigation_valid":true,"collision_size":[2,2,2],
		"room_volume":64,"heat_units":400,"heat_delta_c":6.25,
		"installed_and_ghost_save_round_trip":true,"player_saves_touched":false}
	var out := FileAccess.open("res://tmp/hearth_animation_preview/runtime_checks.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  ")+"\n")
	out.close()
	for id in controller._ghosts.keys():
		controller.cancel_ghost(id)
	for id in controller._installed.keys():
		controller.dev_remove_installed(id)
	print("LIVE_HEARTH_ANIMATION_OK: ",JSON.stringify(report))
	quit(0)
