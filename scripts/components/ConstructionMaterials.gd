extends StorageComponent

## A project-only destination using the normal hauling bundle/handling budget.
## Stock remains reserved for this project, never offered to other consumers.
const INVALID := Vector3i(-1,-1,-1)
var ghost_id := -1
var project_ref: WeakRef
var crate_cell := INVALID
var visual: Node3D
var occupancy := -1
var staged: Dictionary = {} # material id -> actual delivered stone count
var reservations: Dictionary = {}
var _next_token := 1
var _retry := 0.0
var _shown_count := -1
var _contents: Node3D

func setup(project: RefCounted) -> void:
	project_ref = weakref(project)
	ghost_id = project.ghost_id
	drop_manager = project.drop_manager
	filter_items = [project.item_key]
	var hauling := TaskManager.get_config_section("hauling")
	carry_capacity = maxi(1,int(hauling.get("carry_capacity",4)))
	carry_speed_mult_heavy = float(hauling.get("carry_speed_mult_heavy",.7))
	pouch_bundle_radius = int(hauling.get("pouch_bundle_radius",8))
	max_haulers = mini(2,maxi(1,int(hauling.get("max_haulers_per_zone",2))))

func project() -> RefCounted:
	return project_ref.get_ref() if project_ref != null else null

func display_name() -> String: return "Construction materials crate"

func count() -> int:
	var amount := 0
	for value in staged.values(): amount += int(value)
	return amount

func in_transit() -> int:
	var amount := 0
	for token: Dictionary in reservations.values(): amount += int(token.count)
	return amount

func _has_any_room() -> bool:
	var order := project()
	return order != null and crate_cell != INVALID and order.cells.size() > count()+in_transit()

func _reserve_deposit(key: String, _near: Vector3i, dwarf_id: int, amount := 1, material_id := "") -> Variant:
	if not _has_any_room() or not accepts_key(key): return null
	var quantity := mini(amount,project().cells.size()-count()-in_transit())
	var token := {"id":_next_token,"item":key,"count":quantity,"owner":dwarf_id,"active":true,"material_id":material_id}
	_next_token += 1
	reservations[token.id] = token
	return token

func _release_deposit(token: Variant) -> void:
	token.active = false
	reservations.erase(token.id)

func _commit_one(token: Variant, _key: String) -> void:
	var material := String(token.get("material_id",""))
	staged[material] = int(staged.get(material,0))+int(token.count)
	_release_deposit(token)

func consume_one() -> bool:
	for material: String in staged:
		if int(staged[material]) > 0:
			staged[material] -= 1
			if int(staged[material]) == 0: staged.erase(material)
			return true
	return false

func delivery_stand_cells(_target: Vector3i, _dwarf_id := -1) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if crate_cell == INVALID: return result
	for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var stand := crate_cell+offset
		if NavGrid.is_walkable(stand): result.append(stand)
	return result

func nearest_stand_target(from: Vector3i) -> Vector3i:
	var stands := delivery_stand_cells(crate_cell)
	stands.sort_custom(func(a: Vector3i,b: Vector3i): return from.distance_squared_to(a)<from.distance_squared_to(b))
	return stands[0] if not stands.is_empty() else INVALID

func _deposit_walk_target(_token: Variant) -> Vector3i: return crate_cell

func delivery_contact(_stand: Vector3i) -> Vector3:
	return Vector3(crate_cell)+Vector3(.5,1.48,.5)

func commit_haul(dwarf_id: int, carried: Array) -> bool:
	var worker: DwarfAgent = TaskManager._agents.get(dwarf_id)
	if not is_instance_valid(worker) or worker.current_cell() not in delivery_stand_cells(crate_cell): return false
	if not site_supported(): return false
	return super.commit_haul(dwarf_id,carried)

func advance_haul_quote(from: Vector3i, query: Dictionary, deadline: int) -> bool:
	if int(query.get("stock_revision",-1)) != scheduling_revision() or query.get("from") != from:
		query.erase("loose")
		query.erase("stored")
		query.stock_revision = scheduling_revision()
		query.from = from
	if not _has_any_room() or not _can_haul_key(filter_items[0]):
		query.cell = INVALID
		return true
	if not query.has("loose"): query.loose = {}
	if not query.has("pickup_snapshot"): query.pickup_snapshot = {}
	var exclude: Dictionary = query.get("exclude",{})
	if not drop_manager.advance_nearest_haul_query(from,_can_haul_key,query.loose,query.pickup_snapshot,deadline,exclude): return false
	if is_instance_valid(query.loose.best):
		query.cell = drop_manager.item_floor_cell(query.loose.best)
		return true
	if not query.has("stored"): query.stored = {}
	if not StockpileManager.advance_material_quote(filter_items,from,query.stored,deadline,exclude): return false
	query.cell = query.stored.best.get("cell",INVALID)
	return true

## Loose bundles use StorageComponent unchanged. Stored bundles reserve real
## portions, collect each at contact, then deposit together at the project.
func _reserve_relocation(dwarf_id: int, near: Vector3i, exclude: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for origin: StorageComponent in StockpileManager._zones.values()+StockpileManager._containers.values():
		if origin is ContainerStorageComponent and origin.suspended: continue
		for slot in origin.stored_entries():
			var stack: Dictionary = origin.stored_entries()[slot]
			var cell := origin.withdrawal_item_cell(slot)
			if not origin.slot_allowed(slot) or not _can_haul_key(String(stack.item)): continue
			if origin._outgoing.has(slot) or exclude.has(cell) or exclude.has(origin.relocation_id(slot)): continue
			if drop_manager.instance_promised(String(stack.get("instance_id",""))): continue
			candidates.append({"source":origin,"slot":slot,"cell":cell,"distance":near.distance_squared_to(cell),"stack":stack})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
	var items: Array[Node3D] = []
	var deposits := {}
	var transfers := {}
	var budget := carry_capacity
	var first := INVALID
	for candidate: Dictionary in candidates:
		var key := String(candidate.stack.item)
		var cost := _carry_cost(key)
		if cost > budget: continue
		if first != INVALID and Vector3(candidate.cell-first).length() > pouch_bundle_radius: continue
		var origin: StorageComponent = candidate.source
		var deposit = _reserve_deposit(key,near,dwarf_id,1,String(candidate.stack.get("material_id","")))
		if deposit == null: break
		var outgoing := origin.reserve_portion(candidate.slot,key,dwarf_id)
		if outgoing.is_empty():
			_release_deposit(deposit)
			continue
		var marker: Node3D = drop_manager.create_item_visual(key,1,"",String(deposit.material_id))
		if marker == null:
			origin.release_outgoing(outgoing)
			_release_deposit(deposit)
			continue
		marker.set_meta("relocation_id",origin.relocation_id(candidate.slot))
		drop_manager.add_child(marker)
		marker.position = origin.withdrawal_contact(candidate.slot)
		marker.hide()
		items.append(marker)
		deposits[marker] = deposit
		transfers[marker] = {"source":origin,"token":outgoing}
		if first == INVALID: first = candidate.cell
		budget -= cost
		if budget == 0: break
	if items.is_empty(): return {}
	_pulls[dwarf_id] = {"items":items,"deposits":deposits,"cargo":{},"picked":{},"transfers":transfers}
	return {"items":items,"deposit_target":crate_cell,"carry_mult":carry_speed_mult_heavy if drop_manager.get_item_def(filter_items[0]).get("weight_class")=="heavy" else 1.0}

func pickup_stand_cells(dwarf_id: int, index: int) -> Array[Vector3i]:
	var pull: Dictionary = _pulls.get(dwarf_id,{})
	if pull.has("transfers") and index < pull.items.size():
		var transfer: Dictionary = pull.transfers[pull.items[index]]
		return transfer.source.withdrawal_stands(transfer.token.slot)
	return super.pickup_stand_cells(dwarf_id,index)

func take_item(dwarf_id: int, index: int) -> Node3D:
	var pull: Dictionary = _pulls.get(dwarf_id,{})
	if not pull.has("transfers"): return super.take_item(dwarf_id,index)
	if index < 0 or index >= pull.items.size(): return null
	var marker: Node3D = pull.items[index]
	if pull.picked.has(marker) or not bool(pull.deposits[marker].active): return null
	var transfer: Dictionary = pull.transfers[marker]
	var worker: DwarfAgent = TaskManager._agents.get(dwarf_id)
	if not is_instance_valid(worker): return null
	var cargo: Node3D = transfer.source.take_portion(transfer.token,dwarf_id,worker.current_cell())
	if cargo != null:
		pull.cargo[cargo] = pull.deposits[marker]
		pull.picked[marker] = true
	return cargo

func skip_item(dwarf_id: int, index: int) -> void:
	var pull: Dictionary = _pulls.get(dwarf_id,{})
	if pull.has("transfers") and index < pull.items.size():
		var transfer: Dictionary = pull.transfers[pull.items[index]]
		transfer.source.release_outgoing(transfer.token)
	super.skip_item(dwarf_id,index)

func cancel_haul(dwarf_id: int) -> void:
	var pull: Dictionary = _pulls.get(dwarf_id,{})
	if pull.has("transfers"):
		for marker: Node3D in pull.transfers:
			var transfer: Dictionary = pull.transfers[marker]
			transfer.source.release_outgoing(transfer.token)
			if is_instance_valid(marker): marker.queue_free()
	super.cancel_haul(dwarf_id)

func update_leases() -> void:
	if _lease_ids.size() >= max_haulers or not _has_any_room(): return
	if StockpileManager.get_available_total(filter_items[0]) <= 0 and drop_manager.count_loose(_query_tags(),1,_can_haul_key) <= 0: return
	var wanted := mini(max_haulers,project().cells.size()-count())
	while _lease_ids.size() < wanted:
		var id := TaskManager.add_task(Task.Type.HAUL,crate_cell,{"zone_id":source_id},source_id)
		_lease_ids[id] = true

func site_supported() -> bool:
	return crate_cell != INVALID and BlockRegistry.is_solid(WorldData.get_terrain_block(crate_cell.x,crate_cell.y,crate_cell.z)) \
		and WorldData.get_live_block(crate_cell.x,crate_cell.y+1,crate_cell.z) == BlockRegistry.AIR_ID \
		and not WaterManager.has_standing_water(crate_cell+Vector3i.UP)

func tick_site(delta: float, slice_y: int) -> void:
	_retry -= delta
	if _retry <= 0:
		_retry = .5
		if crate_cell != INVALID and not site_supported():
			TaskManager.cancel_source_tasks(source_id)
			refund()
			remove_visual()
			crate_cell = INVALID
		if not is_instance_valid(visual): project().controller.place_materials_crate(self)
	if is_instance_valid(visual): visual.visible = crate_cell.y+1 <= slice_y
	if is_instance_valid(visual) and _shown_count != count(): _refresh_contents()

func _refresh_contents() -> void:
	if is_instance_valid(_contents): _contents.free()
	_contents = Node3D.new()
	visual.add_child(_contents)
	_shown_count = count()
	for i in range(mini(6,_shown_count)):
		var stone: Node3D = drop_manager.create_item_visual(filter_items[0])
		_contents.add_child(stone)
		stone.position = Vector3((i%3-1)*.19,.12+(i/3)*.10,-.11+(i/3)*.22)
		preload("StorageItemLayout.gd").fit(stone,Vector3(.23,.22,.23),1.0)

func refund() -> void:
	if is_instance_valid(drop_manager):
		var floor := crate_cell if crate_cell != INVALID else Vector3i(project().origin_cell)
		for material: String in staged: drop_manager.spawn_drop(filter_items[0],int(staged[material]),floor+Vector3i.UP,material)
	staged.clear()

func remove_visual() -> void:
	if occupancy >= 0: PlacedEntityRegistry.unregister(occupancy)
	occupancy = -1
	if is_instance_valid(visual): visual.queue_free()
	visual = null
	_contents = null
	_shown_count = -1
