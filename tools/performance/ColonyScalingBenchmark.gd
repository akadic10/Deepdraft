extends "res://tools/performance/CameraBenchmark.gd"

## Fixed elevated work yard in a fully simulated generated world. Uses actual
## work sources/executors; only population changes between fresh isolated runs.
const BASE := Vector3i(432,124,432)
const STONE := "base:resources:stone:rough_stone"
const LOG := "base:resources:wood:oak_log"
const TaskType = preload("res://scripts/systems/Task.gd")
var population := 5
var yard_zones: Array = []
var activity := {}
var activity_frames := 0
var observed_frames := 0
var mining: Node
var build_targets: Array[Vector3i] = []
var construction: Node
var director: Node
var phase_started_usec := 0
var first_assignment_seconds := {}
var assignment_counts := {}

func _prepare_workload() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): population=int(arg.trim_prefix("--population="))
	if population not in [5,20,30,50,100]: push_error("Unsupported scaling population"); quit(2); return
	var world := root.get_node("WorldData")
	var blocks := root.get_node("BlockRegistry")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	# A static fixture floor lives in chunk data, not the player-edit journal.
	# Otherwise each real dig rebuilds >11,000 artificial added-terrain cells,
	# measuring the test scaffold rather than colony work. No save is produced.
	var chunks: Dictionary={}
	for x in range(BASE.x,BASE.x+120):
		for z in range(BASE.z,BASE.z+96):
			var key:=Vector3i(x/16,BASE.y/16,z/16)
			var chunk=world.get_chunk(key.x,key.y,key.z)
			chunk.blocks[(x%16)+16*(z%16)+256*(BASE.y%16)]=stone
			chunks[key]=true
			for y in range(BASE.y+1,128):
				chunk.blocks[(x%16)+16*(z%16)+256*(y%16)]=blocks.AIR_ID
	for key: Vector3i in chunks: world.mark_chunk_dirty(key.x,key.y,key.z)
	var floor_mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(120,1,96)
	floor_mesh.mesh=box
	floor_mesh.position=Vector3(BASE)+Vector3(60,.5,48)
	var material:=StandardMaterial3D.new()
	material.albedo_color=blocks.get_terrain_color(stone,root.get_node("WorldClock").season)
	floor_mesh.material_override=material
	scene.add_child(floor_mesh)
	mining=scene.get_node("MiningDesignationController")
	construction=scene.get_node("ConstructionController")
	director=scene.get_node("DwarfDirector")
	var drops := scene.get_node("ItemDropManager")
	var storage := root.get_node("StockpileManager")
	for pod in 20:
		var at := BASE+Vector3i((pod%5)*24,0,(pod/5)*24)
		var dig: Array[Vector3i]=[]
		var build: Array[Vector3i]=[]
		var cells: Array[Vector3i]=[]
		for x in range(2,10):
			for z in range(2,5):
				var cell := at+Vector3i(x,1,z)
				world.set_block(cell.x,cell.y,cell.z,stone)
				dig.append(cell)
			for z in range(11,15): cells.append(at+Vector3i(x,0,z))
		for z in range(3,15): build.append(at+Vector3i(17,1,z))
		build_targets.append_array(build)
		mining._create_zone(dig)
		if construction.create_order(build)<0: push_error("Scaling construction rejected"); quit(2); return
		var zone=load("res://scripts/components/StockpileZoneComponent.gd").new()
		zone.setup(1000+pod,cells)
		zone.filter_tags.assign(["stockpile_wood"])
		storage.register_zone(zone)
		yard_zones.append(zone)
		for i in 16:
			drops.restore_loose_item(STONE,Vector3(at+Vector3i(15+i%2,1,17+i/2))+Vector3(.5,0,.5))
			drops.restore_loose_item(LOG,Vector3(at+Vector3i(2+i%8,1,18+i/8))+Vector3(.5,0,.5))
	for i in population:
		var pod: int=i/5
		var at := BASE+Vector3i((pod%5)*24,0,(pod/5)*24)
		var data: Dictionary=director._factory.generate(i,director._used_names)
		var role: String=["mine","mine","build","haul","haul"][i%5]
		data.work_permissions={"mine":role=="mine","build":role=="build","haul":role=="haul","craft":false,"gather":false}
		var dwarf=director._factory.spawn(data,i)
		dwarf.position=Vector3(at+Vector3i(5+i%5,1,8))+Vector3(.5,0,.5)
		director.add_child(dwarf)
		load("res://scripts/components/UndergroundLighting.gd").bind_world_tree(dwarf)
		director._agents.append(dwarf)
		root.get_node("TaskManager").register_dwarf(dwarf)
	director._birth_index=population
	director.set_settlement_anchor(BASE+Vector3i(12,0,12))
	var first=construction.orders.values()[0]
	var probe_start:=Time.get_ticks_usec()
	var stands: Array=first.work_stands(director.get_roster()[2].current_cell())
	var setup_probe: Dictionary={"stands":stands.size(),"work_stands_ms":(Time.get_ticks_usec()-probe_start)/1000.0,"supply_available":first.item_available()}
	if stands.is_empty() or not setup_probe.supply_available: push_error("Construction fixture has no feasible work/supply"); quit(2); return
	print("COLONY_CONSTRUCTION_PROBE ",JSON.stringify(setup_probe))
	await process_frame
	var deadline:=Time.get_ticks_msec()+120000
	while not _ready_for_sampling():
		if Time.get_ticks_msec()>deadline: push_error("Work yard did not settle"); quit(2); return
		await process_frame
	print("COLONY_WORKLOAD_READY ",population," ",JSON.stringify(_work_stats()))

func _set_sampling_camera() -> void:
	origin=Vector3(BASE)+Vector3(42,4,30)
	rig._target_pos=origin
	rig.global_position=rig._target_pos
	rig._target_zoom=65.0

func _install_markers() -> void:
	super._install_markers()
	for before: bool in [true,false]:
		var marker=load("res://tools/performance/ProcessMarker.gd").new()
		marker.label="Dwarves"
		marker.before=before
		marker.measurements=measurements
		marker.starts=starts
		marker.process_priority=0
		scene.add_child(marker)
		scene.move_child(marker,director.get_index() if before else director.get_index()+1)

func _benchmark_modes() -> Array[String]:
	return ["paused_pan","active_pan","active_pan_repeat"]

func _sample(mode: String) -> void:
	activity.clear()
	activity_frames=0
	first_assignment_seconds.clear()
	assignment_counts.clear()
	phase_started_usec=Time.get_ticks_usec()
	root.get_node("TaskManager").task_assigned.connect(_record_assignment)
	process_frame.connect(_record_activity)
	var before:=_work_stats()
	await super._sample(mode)
	process_frame.disconnect(_record_activity)
	root.get_node("TaskManager").task_assigned.disconnect(_record_assignment)
	report.phases[mode]["work_before"]=before
	report.phases[mode]["work_after"]=_work_stats()
	report.phases[mode]["worker_samples"]=activity.duplicate()
	report.phases[mode]["worker_sample_frames"]=activity_frames
	report.phases[mode]["first_assignment_seconds"]=first_assignment_seconds.duplicate()
	report.phases[mode]["assignment_counts"]=assignment_counts.duplicate()
	report.phases[mode]["assignment_window_seconds"]=(Time.get_ticks_usec()-phase_started_usec)/1000000.0
	report["workload"]={"kind":"fixed elevated work yard","dwarves":population,"mining_blocks":480,
		"construction_cells":240,"loose_stone":320,"loose_logs":320,"storage_zones":20,"floor_y":BASE.y,
		"note":"Same sources/terrain/supplies at all populations. Static floor uses live chunk data and a fixed box mesh, outside the player-edit journal. Artificial open work yard, not a mature colony save."}
	for path in ["scripts/entities/DwarfAgent.gd","scripts/systems/TaskManager.gd","scripts/systems/NavGrid.gd","scripts/systems/ItemDropManager.gd","scripts/systems/StockpileManager.gd","scripts/components/StorageComponent.gd","scripts/systems/ConstructionController.gd","scripts/components/ConstructionWork.gd","scripts/components/FurnitureFetchPlanner.gd"]:
		report[path.get_file()+"_sha256"]=FileAccess.get_sha256("res://"+path)
	_save_report()
	if mode=="active_pan_repeat":
		var done:=_work_stats()
		report["all_work_types_progressed"]=done.mined>0 and done.built>0 and done.stored>0
		var waits: Array=[]
		for order in construction.orders.values():
			var task=root.get_node("TaskManager").get_task(order._lease_id)
			if task!=null: waits.append({"order":order.ghost_id,"assigned":task.assigned_to,"reason":task.wait_reason,"planning":str(task.planning_context).left(800)})
		report["construction_waits"]=waits
		_save_report()
		print("COLONY_WORK_RESULTS ",JSON.stringify(done))
		if not root.get_node("TaskManager").lifecycle_errors().is_empty(): push_error("Work lifecycle violation"); quit(1)
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png(output+"colony.png")

func _record_assignment(task: RefCounted, _dwarf_id: int) -> void:
	var kind: String=TaskType.type_name(task.type)
	if not first_assignment_seconds.has(kind): first_assignment_seconds[kind]=(Time.get_ticks_usec()-phase_started_usec)/1000000.0
	assignment_counts[kind]=int(assignment_counts.get(kind,0))+1

func _record_activity() -> void:
	observed_frames+=1
	if observed_frames%15!=0: return
	activity_frames+=1
	for dwarf in director.get_roster():
		var key: String="idle"
		var task=root.get_node("TaskManager").get_task(dwarf.current_task_id)
		if task!=null: key=TaskType.type_name(task.type)
		activity[key]=int(activity.get(key,0))+1

func _work_stats() -> Dictionary:
	var stored:=0
	for zone in yard_zones: stored+=zone.stored_count()
	return {"mined":mining._mined_blocks.size(),"built":build_targets.filter(func(cell): return root.get_node("BlockRegistry").is_solid(root.get_node("WorldData").get_terrain_block(cell.x,cell.y,cell.z))).size(),"stored":stored,
		"active":root.get_node("TaskManager")._active.size(),"idle":root.get_node("TaskManager")._idle_dwarves.size(),
		"navigation":root.get_node("NavGrid").get_stats()}
