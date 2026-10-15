extends SceneTree
## Run the editor executable from the export directory with --main-pack and
## this absolute script path. The isolated copied save must already exist.
var failures: Array[String]=[]
var output: String
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _run() -> void:
	if output.is_empty() or not "/water_loop_20261014/" in OS.get_user_data_dir().replace("\\","/"):
		push_error("Water check requires isolated water_loop_20261014 profile and output"); quit(2); return
	if FileAccess.file_exists("res://tools/performance/CameraBenchmark.gd"):
		push_error("Packed check must not resolve loose workspace files"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): push_error("Water packed check timeout"); quit(1))
	var clock_node=root.get_node("WorldClock")
	var saves=root.get_node("SaveManager")
	clock_node.set_paused(true)
	var placeholder:=Node3D.new()
	placeholder.scene_file_path="res://scenes/main/debug_world.tscn"
	root.add_child(placeholder)
	current_scene=placeholder
	if not saves.request_load(): quit(1); return
	while saves.is_loading(): await process_frame
	saves.set_process(false)
	clock_node.set_paused(true)
	var terrain=current_scene.get_node("Renderer")
	var water=root.get_node("WaterManager")
	var moisture=_moisture(terrain)
	check(moisture!=null,"packaged tiled moisture renderer exists")
	await _settle(terrain,water)
	var initial:=_units(water.flow)
	var input_before: int=water.flow.added_units-water.flow.drained_units-water.flow.extracted_units
	clock_node.set_speed(1)
	clock_node.set_paused(false)
	await create_timer(8).timeout
	clock_node.set_paused(true)
	var conserved: bool=_units(water.flow)==initial+water.flow.added_units-water.flow.drained_units-water.flow.extracted_units-input_before
	check(conserved,"active simulation conserves integer water units")
	check(terrain.get_node("Water").motion.completed_samples>0,"packaged current samples ran")
	check(not water.flow._reaches.is_empty(),"export includes active topology cache")
	for links: Array in water.flow._links.values():
		for link: Array in links: check(link.size()==3 and int(link[2])==water.flow.ceiling(link[0]),"packaged receiving ceilings match live topology")
	var paused: Dictionary=water.serialize_state()
	await create_timer(.2).timeout
	check(paused==water.serialize_state(),"pause freezes water state")
	await _settle(terrain,water)
	var current_image: PackedByteArray=terrain.get_node("Water").motion.image.get_data()
	await create_timer(.2).timeout
	check(current_image==terrain.get_node("Water").motion.image.get_data(),"paused currents stopped after pending work drained")
	var original_slice: int=terrain.slice_y
	terrain.slice_y=35
	await _settle(terrain,water)
	for node: MeshInstance3D in moisture._nodes.values():
		if not node.visible or node.mesh==null: continue
		for vertex: Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			check(vertex.y<=36.02,"slice conceals moisture above its plane")
	terrain.slice_y=original_slice
	await _settle(terrain,water)
	check(paused==water.serialize_state(),"slice changes preserve water state")
	var result: Dictionary={"failures":failures,"integer_conservation":conserved,"reaches":water.flow._reaches.size(),"ceilings":water.flow._ceilings.size(),
		"dwarves":current_scene.get_node("DwarfDirector").get_roster().size(),"driver":RenderingServer.get_current_rendering_driver_name(),"motion":terrain.get_node("Water").motion.get_stats(),"mesh":terrain.get_node("Water").get_mesh_stats(),"moisture":moisture.get_mesh_stats()}
	FileAccess.open(output+"packed_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WATER_FLOW_EXPORT_PASS " if failures.is_empty() else "WATER_FLOW_EXPORT_FAIL ",JSON.stringify(result))
	root.get_node("WorldGenerator").prepare_for_world_reload()
	quit(0 if failures.is_empty() else 1)
func _units(flow: RefCounted) -> int:
	var amount:=0
	for units: int in flow.mass.values(): amount+=units
	for item: Dictionary in flow.pending: amount+=int(item.units)
	return amount
func _settle(terrain: Node, water: Node) -> void:
	await process_frame
	await process_frame
	var view=terrain.get_node("Water")
	while not terrain._overview_built or not terrain._dirty_overview_tiles.is_empty() or terrain._cavity_shell_dirty or terrain.underground_lighting.is_updating() or not water.dirty_tiles.is_empty() or not view._pending.is_empty() or not view._jobs.is_empty() or _moisture(terrain).is_updating() or view.motion.is_updating():
		await process_frame

func _moisture(terrain: Node) -> Node:
	for child in terrain.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/components/MoistureRenderer.gd": return child
	return null

