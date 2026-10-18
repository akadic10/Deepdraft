extends "res://scripts/tests/WorkerCraftingTest.gd"

const CELL := Vector3i(60,23,60)
const OUT := "res://tmp/terrain_explorer_20261012/"
var renderer
var terrain
var Picking

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Terrain explorer timed out"); quit(1))
	await _setup_crafting_fixture()
	Picking = load("res://scripts/components/ObjectPicking.gd")
	var generator = root.get_node("WorldGenerator")
	generator.heightmap.fill(40)
	generator.waterline_map.resize(1024*1024); generator.waterline_map.fill(-1)
	generator._build_noise_instances()
	stockpiles.reset_runtime_state()
	renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	terrain = load("res://scripts/ui/TerrainExplorerProvider.gd").new()
	terrain.renderer = renderer
	terrain.name = "Terrain"
	scene.add_child(terrain)
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	explorer.terrain_provider_path = NodePath("../Terrain")
	explorer.click_tool_paths.append(NodePath("../Furniture"))
	furniture.name = "Furniture"
	scene.add_child(explorer)
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(58,65):
		for y in range(21,28):
			world.set_block(x,y,60,rock)
			var air := Vector3i(x,y,61)
			renderer._mined_blocks[air] = true; renderer._visual_cut_blocks[air] = true
	var surface := CELL+Vector3i.BACK
	var hit := {"x":CELL.x,"y":CELL.y,"z":CELL.z,"normal":Vector3i.BACK}
	for pair in [["base:terrain:soil:cave","Cave soil"],["base:terrain:ore:iron","Iron ore"],["base:terrain:gem:jade","Jade"]]:
		var key: String = pair[0]
		world.set_block(CELL.x,CELL.y,CELL.z,blocks.get_id(key))
		var point := _aim(CELL,Vector3i.BACK)
		_click(point)
		_expect(explorer._provider==terrain and explorer._name_label.text==pair[1],"real wall click names exposed "+key)
		_expect(explorer._outline.visible,"selected terrain has an outline")
		_expect(explorer.pick_at_screen(point).is_empty(),"designation object picking does not acquire terrain fallback")
		for row in explorer._row_values: _expect(not ":terrain:" in row.text,"player facts contain no technical IDs")
	# Planning a hole never earns discovery, even if a valuable block lies behind it.
	root.get_node("InteriorTracker")._known_cells.erase(CELL)
	renderer._mined_blocks.erase(surface)
	_expect(not "Jade" in JSON.stringify(terrain.get_explorer_data(hit)),"planned wall does not reveal gems")
	renderer._mined_blocks[surface] = true
	# Slice tops remain concealed even when the same block has a revealed side.
	renderer.slice_y = CELL.y
	var cap := hit.duplicate(); cap.normal = Vector3i.UP
	_expect(terrain.get_explorer_data(cap).title=="Stone","slice cap cannot disclose hidden material")
	explorer._on_slice_changed(CELL.y-1)
	renderer.slice_y = CELL.y-1; explorer._refresh_selected()
	_expect(not manager.is_open("object_explorer"),"lowered slice closes hidden block selection")
	renderer.slice_y = 127; explorer._on_slice_changed(127)
	# The player ray passes through visible cuts instead of stopping at unmined plan data.
	world.set_block(surface.x,surface.y,surface.z,rock)
	world._edits.get(Vector3i(surface.x>>4,surface.y>>4,surface.z>>4),{}).erase(surface)
	var ray: Dictionary = terrain.terrain_hit(Vector3(CELL)+Vector3(.5,.5,8),Vector3.FORWARD,127,20)
	_expect(Vector3i(ray.x,ray.y,ray.z)==CELL,"visible cut ray reaches the rear face")
	world.set_block(surface.x,surface.y,surface.z,blocks.AIR_ID)
	# Current chunks keep mined air; the developer inspector must not resurrect it.
	_expect(renderer._inspect_block_id(surface).block_id==blocks.AIR_ID,"developer inspector honors live excavated air")
	_expect(explorer.select_object(terrain,hit),"select block before mining it")
	world.set_block(CELL.x,CELL.y,CELL.z,blocks.AIR_ID)
	explorer._refresh_selected()
	_expect(terrain.get_explorer_data(hit).is_empty() and not manager.is_open("object_explorer"),"mined-away block closes its inspector")
	# Natural cave voids stay solid-looking until their connected air is discovered.
	var column: int = CELL.x*1024+CELL.z
	world._edits.get(Vector3i(CELL.x>>4,CELL.y>>4,CELL.z>>4),{}).erase(CELL)
	generator._cave_layout.columns[column] = Vector3i(CELL.y-1,CELL.y,0)
	var concealed: Dictionary = terrain.terrain_hit(Vector3(CELL)+Vector3(.5,.5,8),Vector3.FORWARD,127,20)
	_expect(Vector3i(concealed.x,concealed.y,concealed.z)==CELL and terrain.get_explorer_data(concealed).title=="Stone","undiscovered cave air cannot be inspected through")
	generator._cave_layout.columns.erase(column)
	# Constructed stone and floors identify the finished material, including slice caps.
	for key in ["base:terrain:rock:rock01","base:construction:floor:plank","base:construction:floor:stone"]:
		world.set_block(CELL.x,CELL.y,CELL.z,blocks.get_id(key))
		var data: Dictionary = terrain.get_explorer_data(hit)
		_expect(data.rows.size()==3 and data.title==blocks.get_def(key).inspection.name,"material is identified without construction origin")
	# Furniture remains the first selection in front of a terrain surface.
	var floor := Vector3i(63,20,63)
	furniture._install("base:furniture:barrel",furniture.get_defs()["base:furniture:barrel"],floor,0)
	var point := _aim(floor,Vector3i.UP)
	_expect(explorer.select_at_screen(point) and explorer._provider==furniture,"furniture retains selection priority")
	furniture._active = true
	_expect(not explorer.select_at_screen(point),"active tools keep clicks")
	furniture._active = false
	await _zone_priority()
	await _menu_and_capture()
	renderer.free()
	for failure in failures: push_error(failure)
	print("TERRAIN_EXPLORER_OK: face picking, discovery, cuts, live edits, construction, object/tool priority and development menu" if failures.is_empty() else "TERRAIN_EXPLORER_FAIL")
	quit(0 if failures.is_empty() else 1)

func _aim(cell: Vector3i, normal: Vector3i) -> Vector2:
	var target := Vector3(cell)+Vector3.ONE*.5+Vector3(normal)*.5
	camera.position = target+Vector3(normal)*12+Vector3(3,4,3)
	camera.look_at(target); camera.size = 13
	return camera.unproject_position(target)

func _zone_priority() -> void:
	explorer.clear_selection()
	var storage = load("res://scripts/systems/StockpileDesignationController.gd").new()
	storage.window_manager_path = NodePath("../Windows")
	scene.add_child(storage); storage.set_process(false)
	explorer._tools.append(storage)
	var floor := Vector3i(58,20,64)
	var cells: Array[Vector3i] = [floor]
	var stock = storage._create_zone(cells)
	_click(_aim(floor,Vector3i.UP))
	_expect(storage._window_zone_id==stock.zone_id and manager.is_open(storage.ZONE_WINDOW_ID) and explorer._provider==null,"empty stockpile floor opens its storage inspector")
	storage._close_zone_window(); storage.remove_zone(stock.zone_id)
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining.window_manager_path = NodePath("../Windows")
	scene.add_child(mining); mining.set_process(false)
	var rig = load("res://scripts/systems/Camera.gd").new()
	rig.camera_node = camera
	explorer._tools.append(mining)
	var planned: Array[Vector3i] = [CELL]
	var id: int = mining._create_zone(planned)
	mining._camera_rig = rig
	# The fixture's mined opening sits below its synthetic original mountain.
	for x in range(58,68):
		for y in range(21,40):
			for z in range(61,81): mining._mined_blocks[Vector3i(x,y,z)] = true
	var point := _aim(CELL,Vector3i.BACK)
	var selected: bool = explorer.select_at_screen(point)
	_expect(selected and mining._selected_zone_id==id and manager.is_open(mining.ZONE_WINDOW_ID) and explorer._provider==null,"mining order retains its pending-work inspector: selected=%s zone=%s hit=%s" % [selected,mining._selected_zone_id,mining._raycast_voxel(point)])
	mining._close_zone_window()
	explorer._tools.erase(storage); explorer._tools.erase(mining)
	storage.free(); mining.free(); rig.free()

func _menu_and_capture() -> void:
	var registry = root.get_node("UIRegistry")
	_expect(registry.get_menu("system").items.filter(func(item): return item.target=="block_inspector").is_empty(),"Block inspector removed from Menu")
	_expect(registry.get_menu("development").items.filter(func(item): return item.target=="block_inspector").size()==1,"Block inspector appears once in Development")
	renderer._build_block_inspector_ui()
	dock._set_block_inspector_overlay(renderer._inspector_layer)
	explorer.clear_selection()
	await _frames(5)
	_click(dock._button_by_target.development.get_global_rect().get_center())
	await _frames(4)
	_expect(dock._panel_body.get_child_count()>0,"Development menu opens through dock input")
	if dock._panel_body.get_child_count()==0: return
	_click(dock._panel_body.get_child(0).get_global_rect().get_center())
	_expect(renderer.is_block_inspector_active() and explorer._click_tool_active(),"development action opens diagnostics and prevents competing inspection")
	dock._toggle_block_inspector_overlay()
	world.set_block(CELL.x,CELL.y,CELL.z,blocks.get_id("base:terrain:soil:cave"))
	var point := _aim(CELL,Vector3i.BACK)
	explorer.select_at_screen(point)
	for size in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = size; await _frames(4); explorer._refresh_selected(); await _frames(4)
		_expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(explorer._window.get_global_rect()),"terrain window fits "+str(size))
	if "--capture" in OS.get_cmdline_user_args():
		# Native wall geometry matches the fixture's world cells.
		for x in range(58,65):
			for y in range(21,28):
				var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.mesh.size = Vector3.ONE
				mesh.position = Vector3(x,y,60)+Vector3.ONE*.5
				var mat := StandardMaterial3D.new(); mat.albedo_color = blocks.get_color(world.get_live_block(x,y,60),"summer")
				mesh.material_override = mat; scene.add_child(mesh)
		_aim(CELL,Vector3i.BACK)
		await _frames(5); await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		root.get_texture().get_image().save_png(OUT+"terrain_inspector.png")
