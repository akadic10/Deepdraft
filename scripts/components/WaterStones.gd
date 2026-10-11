extends Node3D

## Placed forms and worker packing jobs. WaterManager owns persistent identity
## and effects; ItemDropManager/storage own the inactive packed forms.
const Picking = preload("res://scripts/components/ObjectPicking.gd")
const Permission = preload("res://scripts/components/ItemPermission.gd")
const Packing = preload("res://scripts/components/WaterStonePacking.gd")
var terrain: Node3D
var stones: Dictionary = {}
var jobs: Dictionary = {}
var _revision := -1
var _material: Material
var _picking := Picking.new()

func _ready() -> void:
	add_to_group("object_explorer_provider")
	add_to_group("water_stones")
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	base.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material = terrain.underground_lighting.make_material(base)
	WorldData.block_changed.connect(_on_support_changed)
	TaskManager.task_completed.connect(_task_gone)
	TaskManager.task_cancelled.connect(_task_gone)
	TaskManager.task_failed.connect(func(task: Task, _reason: String): _task_gone(task))

func _task_gone(task: Task) -> void:
	for job in jobs.values():
		if job.source_id==task.source_id: job.on_task_gone(task.id,task.assigned_to)

func _exit_tree() -> void:
	for id in stones.keys(): _forget(id)

func _process(_delta: float) -> void:
	visible = WaterManager.initialized
	if not visible: return
	if _revision != WaterManager.revision:
		for id in stones.keys(): _forget(id)
		_revision = WaterManager.revision
	_sync()
	for id: String in stones:
		var node: Node3D = stones[id]
		var record: Dictionary = WaterManager.stones[id]
		var cell: Vector3i = record.cell
		var exposed: bool = cell.y>WorldGenerator.get_surface_y(cell.x,cell.z) or terrain.is_revealed_air(cell)
		node.visible = cell.y<=terrain.slice_y and exposed and WaterManager.depth_at(cell)<1.0-0.00001 and not BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,cell.y,cell.z))

func _sync() -> void:
	for id in stones.keys():
		if not WaterManager.stones.has(id) or not WaterManager.stones[id].placed: _forget(id)
	for id: String in WaterManager.stones:
		var record: Dictionary = WaterManager.stones[id]
		if not record.placed: continue
		if not stones.has(id):
			var definition: Dictionary = WorldGenerator.water_profile.stones[record.kind]
			var model := load(String(definition.model)) as PackedScene
			var node := model.instantiate() as Node3D
			node.name = String(definition.display_name).replace(" ","")
			_apply_material(node)
			add_child(node)
			node.position = Vector3(record.cell)+Vector3(.5,0,.5)
			stones[id] = node
			_settle(id)
			var job := Packing.new()
			job.record = record
			job.setup(0,"base:water:"+record.kind+"_stone",definition,record.cell-Vector3i.UP,0)
			job.source_id = TaskManager.allocate_source_id()
			job.uninstall_callback = func(_component): _pack_complete(id)
			TaskManager.register_work_source(job.source_id,job)
			jobs[id] = job
		jobs[id].set_uninstall(record.packing and not record.disallowed)

func _forget(id: String) -> void:
	if jobs.has(id):
		var job = jobs[id]
		job.set_uninstall(false)
		TaskManager.unregister_work_source(job.source_id)
		jobs.erase(id)
	if stones.has(id):
		stones[id].queue_free()
		stones.erase(id)

func _apply_material(node: Node) -> void:
	if node is MeshInstance3D: node.material_override = _material
	for child in node.get_children(): _apply_material(child)

func _on_support_changed(cell: Vector3i, old_id: int, new_id: int) -> void:
	if WaterManager.restoring or _revision != WaterManager.revision: return
	if not BlockRegistry.is_solid(old_id) or BlockRegistry.is_solid(new_id): return
	for id: String in stones:
		var p: Vector3i = WaterManager.stones[id].cell
		if p.x==cell.x and p.z==cell.z and cell.y<p.y:
			cancel_pack(id)
			_settle(id)
			jobs[id].origin_cell = WaterManager.stones[id].cell-Vector3i.UP

func _settle(id: String) -> void:
	var record: Dictionary = WaterManager.stones[id]
	var cell: Vector3i = record.cell
	var y := cell.y-1
	while y>WorldGenerator.BEDROCK_MAX_Y and not BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,y,cell.z)): y-=1
	var fall := y+1-cell.y
	record.cell += Vector3i(0,fall,0)
	record.intake += Vector3i(0,fall,0)
	record.level += fall
	stones[id].position = Vector3(record.cell)+Vector3(.5,0,.5)

func request_pack(id: String) -> bool:
	if not WaterManager.stones.has(id): return false
	var record: Dictionary = WaterManager.stones[id]
	if not record.placed or record.disallowed: return false
	record.packing = true
	_sync()
	return true

func cancel_pack(id: String) -> void:
	if not WaterManager.stones.has(id): return
	WaterManager.stones[id].packing = false
	if jobs.has(id): jobs[id].set_uninstall(false)

func _pack_complete(id: String) -> void:
	var record: Dictionary = WaterManager.stones[id]
	var items := get_tree().get_first_node_in_group("item_drop_manager")
	if record.disallowed or not record.placed or items==null: return
	record.placed = false
	record.packing = false
	record.work = 0.0
	jobs[id].flagged_uninstall = false
	items.restore_loose_item(String(WorldGenerator.water_profile.stones[record.kind].item_key),Vector3(record.cell)+Vector3(.5,0,.5),0,1,id,false)
	# The completing worker still owns its lease until the normal callback ends.
	TaskManager.unregister_work_source(jobs[id].source_id)
	jobs.erase(id)
	stones[id].queue_free()
	stones.erase(id)

func set_disallowed(id: String, value: bool) -> void:
	if not WaterManager.stones.has(id): return
	WaterManager.stones[id].disallowed = value
	if value:
		cancel_pack(id)
		var placement := get_tree().get_first_node_in_group("furniture_controller")
		if placement != null: placement.cancel_water_stone_moves(id)

func placement_reason(cell: Vector3i, ignore_id: String = "") -> String:
	if cell.x<0 or cell.z<0 or cell.x>=1024 or cell.z>=1024 or cell.y<=WorldGenerator.BEDROCK_MAX_Y or cell.y>=125: return "cell"
	if not BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,cell.y,cell.z)): return "cell"
	for y in range(cell.y+1,cell.y+4):
		if BlockRegistry.is_solid(WorldData.get_terrain_block(cell.x,y,cell.z)) or PlacedEntityRegistry.occupies(Vector3i(cell.x,y,cell.z)): return "cell"
	for id: String in WaterManager.stones:
		if id!=ignore_id and WaterManager.stones[id].placed and WaterManager.stones[id].cell==cell+Vector3i.UP: return "overlap"
	for stand in StorageComponent.ground_access_cells(cell):
		if NavGrid.is_walkable(stand): return ""
	return "stone_access"

func get_explorer_bounds(id: Variant) -> AABB:
	var node: Node3D = stones.get(id)
	return Picking.world_bounds(node) if is_instance_valid(node) and node.is_visible_in_tree() else AABB()

func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result := {}
	var nearest := start.distance_to(end)
	for id: String in stones:
		var distance := _picking.hit_distance(stones[id],start,end)
		if distance<nearest:
			nearest=distance
			result={"id":id,"distance":distance}
	return result

func get_explorer_data(id: Variant) -> Dictionary:
	if get_explorer_bounds(id).size==Vector3.ZERO: return {}
	var record: Dictionary = WaterManager.stones[id]
	var definition: Dictionary = WorldGenerator.water_profile.stones[record.kind]
	var actions := [Permission.action(record.disallowed)]
	if not record.disallowed:
		actions.append({"id":"pack", "text":"Cancel packing" if record.packing else "Pack for storage"})
		if not record.packing: actions.append({"id":"move", "text":"Move"})
	return {"title":definition.display_name,"kind":"Water stone", "rows":[
		["Colony access","Disallowed" if record.disallowed else "Allowed"],
		["Water","Active while placed"],["Order","Packing requested" if record.packing else "None"]],
		"details":"Feeds water up to level %.1f. Allowing colony access does not stop the spring or automatically move it." % record.level if record.kind=="wet" else "Absorbs water above level %.1f. Packing stops the drain; allowing access alone leaves it working." % record.level,
		"actions":actions}

func perform_explorer_action(id: Variant, action: String) -> void:
	if get_explorer_bounds(id).size==Vector3.ZERO: return
	var record: Dictionary = WaterManager.stones[id]
	if action=="permission": set_disallowed(id,not record.disallowed)
	elif not record.disallowed and action=="pack":
		if record.packing: cancel_pack(id)
		else: request_pack(id)
	elif not record.disallowed and action=="move":
		var placement := get_tree().get_first_node_in_group("furniture_controller")
		if placement != null: placement.begin_water_stone_move(id)
