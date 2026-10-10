class_name StorageComponent
extends RefCounted

## Shared hauling contract for ground zones and furniture. Each physical
## slot holds one item, or one automatic produce crate with up to 24 units.
## StorageStackSlots reserves quantity-bearing tokens; this base keeps each
## token paired with its source and picked cargo through reordering/skips.
## Ground token.slot is a floor cell; furniture token.slot is an anchor index.
## All task state is transient. Release frees claims and the dwarf drops cargo.

var source_id: int = -1                       # TaskManager work-source key
var max_haulers: int = 2
var carry_speed_mult_heavy: float = 0.7
var carry_capacity: int = 4                   # sum of per-object carry_cost points
var pouch_bundle_radius: int = 8              # extras within this radius of the MAIN item
var drop_manager: Node3D = null               # ItemDropManager (guard is_instance_valid)
var changed_callback: Callable = Callable()   # (item_key, delta) -> StockpileManager signal
var filter_tags: Array[String] = []
var filter_items: Array[String] = []
var excluded_items: Array[String] = []
signal changed

# One outgoing claim per physical stack. Goods stay stored until fist contact.
var _outgoing: Dictionary = {}

var _lease_ids: Dictionary = {}               # task_id -> true (live HAUL leases)
var _pulls: Dictionary = {}                   # dwarf_id -> {items, deposits, cargo, picked}


# ── Subclass surface (abstract — override all of these) ───────────────────────

## True while at least one more deposit could be reserved.
func _has_any_room() -> bool:
	return false


## Reserve one deposit for `item_key`. Returns a token, or null when full.
func _reserve_deposit(_item_key: String, _near: Vector3i, _dwarf_id: int, _amount: int = 1) -> Variant:
	return null


func _has_room_for_key(_key: String) -> bool:
	return _has_any_room()


func _item_capacity(key: String) -> int:
	return int(drop_manager.call("item_capacity", key)) if is_instance_valid(drop_manager) else 1


func _carry_cost(key: String) -> int:
	var def: Dictionary = drop_manager.call("get_item_def", key)
	return maxi(1, int(def.get("carry_cost", 1)))


func _can_haul_key(key: String) -> bool:
	return accepts_key(key) and _carry_cost(key) <= carry_capacity and _has_room_for_key(key)


## Free an unused reservation token.
func _release_deposit(_token: Variant) -> void:
	pass


## Commit a token's quantity (the base fires changed_callback in units).
func _commit_one(_token: Variant, _item_key: String) -> void:
	pass


## Delivery reference (zone: the first reserved cell; container: a stand cell).
## delivery_stand_cells separates the worker's position from the item slot.
func _deposit_walk_target(_first_token: Variant) -> Vector3i:
	return Vector3i(-1, -1, -1)


## Cosmetic bundle handoff; the reserved tokens still own final placement.
func delivery_contact(stand: Vector3i) -> Vector3:
	return Vector3(stand.x + .5, stand.y + 1.0, stand.z + .5)


func delivery_stand_cells(target: Vector3i, _dwarf_id: int = -1) -> Array[Vector3i]:
	return [target]


## Cardinal access avoids reaching diagonally through a wall corner. Include
## neighbouring steps; the agent checks clearance and a real path to each.
static func ground_access_cells(item_floor: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for offset: Vector3i in [Vector3i(0,0,-1), Vector3i(-1,0,0), Vector3i(1,0,0), Vector3i(0,0,1)]:
		for dy in [0, -1, 1]:
			cells.append(item_floor + offset + Vector3i(0,dy,0))
	return cells


## What happens to the carried node on deposit. Default: absorbed (freed) —
## the container look. The zone overrides to place_stored (WYSIWYG).
func _place_visual(node: Node3D, _token: Variant) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


## Scheduler probe / hauler walk target nearest this dwarf.
func nearest_stand_target(_dwarf_cell: Vector3i) -> Vector3i:
	return Vector3i(-1, -1, -1)


# ── Shared queries ────────────────────────────────────────────────────────────

## Tag acceptance (capacity is the reserve step's problem). `item_tags` is
## the item's material_tags from resources.json, queried through
## ItemDropManager — the registry pattern.
func accepts(item_tags: Array) -> bool:
	for tag: String in filter_tags:
		if item_tags.has(tag):
			return true
	return false


func accepts_key(key: String) -> bool:
	if key in excluded_items: return false
	if key in filter_items: return true
	if not is_instance_valid(drop_manager): return false
	return accepts(drop_manager.get_item_def(key).get("material_tags", []))


func serialize_filter() -> Dictionary:
	return {"tags": filter_tags.duplicate(), "items": filter_items.duplicate(),
		"excluded_items": excluded_items.duplicate()}


## Missing rules preserve the legacy accept-all default. Explicit empty arrays
## mean accept nothing. Restore does not cancel tasks while owners are loading.
func restore_filter(saved: Dictionary) -> void:
	filter_tags.assign(saved.get("tags", StockpileZoneComponent.DEFAULT_FILTER_TAGS))
	filter_items.assign(saved.get("items", []))
	excluded_items.assign(saved.get("excluded_items", []))


func set_all_accepted(allowed: bool) -> void:
	filter_tags.assign(StockpileZoneComponent.DEFAULT_FILTER_TAGS if allowed else [])
	filter_items.clear()
	excluded_items.clear()
	_filters_changed()


func set_item_accepted(key: String, allowed: bool) -> void:
	filter_items.erase(key)
	excluded_items.erase(key)
	var from_category := accepts(drop_manager.get_item_def(key).get("material_tags", []))
	if allowed and not from_category: filter_items.append(key)
	if not allowed and from_category: excluded_items.append(key)
	_filters_changed()


func set_category_accepted(tag: String, allowed: bool) -> void:
	filter_tags.erase(tag)
	if allowed: filter_tags.append(tag)
	# A category click replaces its individual exceptions, including items the
	# colony has not gathered yet. Identity still comes from the item registry.
	for key: String in drop_manager.get_item_defs():
		if tag in drop_manager.get_item_def(key).get("material_tags", []):
			filter_items.erase(key)
			excluded_items.erase(key)
	_filters_changed()


func _filters_changed() -> void:
	var invalid_owners := {}
	for dwarf_id: int in _pulls:
		for token: Dictionary in _pulls[dwarf_id].deposits.values():
			if bool(token.active) and not accepts_key(String(token.item)):
				invalid_owners[dwarf_id] = true
	if StockpileManager.is_registered(self):
		for task_id: int in _lease_ids.keys():
			var task := TaskManager.get_task(task_id)
			if task != null and (task.assigned_to < 0 or invalid_owners.has(task.assigned_to)):
				TaskManager.cancel_task(task_id)
	# Also covers callers holding a pull without a scheduler lease (fixtures).
	# Compatible deliveries continue; a mixed invalid bundle drops safely.
	for dwarf_id: int in invalid_owners: cancel_haul(dwarf_id)
	StockpileManager.storage_rules_changed()
	changed.emit()


func _query_tags() -> Array[String]:
	var result := filter_tags.duplicate()
	for key in filter_items:
		for tag: String in drop_manager.get_item_def(key).get("material_tags", []):
			if not tag in result: result.append(tag)
	return result


## Subclasses expose authoritative physical stacks; UI and relocation derive
## their views here, without introducing another inventory store.
func stored_entries() -> Dictionary:
	return {}


func storage_capacity() -> int:
	return 0


func slot_cell(_slot: Variant) -> Vector3i:
	return Vector3i(-1, -1, -1)


## Physical spawn location used by the legacy fetch withdrawal executor.
func withdrawal_item_cell(slot: Variant) -> Vector3i:
	return slot_cell(slot)


func withdrawal_stands(slot: Variant) -> Array[Vector3i]:
	return ground_access_cells(slot_cell(slot))


func withdrawal_contact(slot: Variant) -> Vector3:
	return Vector3(slot_cell(slot)) + Vector3(.5, 1, .5)


func withdraw_stack(_slot: Variant, _amount: int, _dwarf_id: int) -> Node3D:
	return null


func contents() -> Dictionary:
	var result := {}
	for stack: Dictionary in stored_entries().values():
		var key := String(stack.item)
		result[key] = int(result.get(key, 0)) + int(stack.count)
	return result


func relocation_id(slot: Variant) -> String:
	return "%d/%s" % [source_id, str(slot)]


func release_outgoing(token: Dictionary) -> void:
	if not bool(token.get("active", false)): return
	token.active = false
	_outgoing.erase(token.slot)
	StockpileManager.storage_rules_changed()
	changed.emit()


func pickup_stand_cells(dwarf_id: int, index: int) -> Array[Vector3i]:
	var pull: Dictionary = _pulls.get(dwarf_id, {})
	if pull.is_empty() or index >= pull.items.size(): return []
	if pull.has("transfer"):
		return pull.transfer.source.withdrawal_stands(pull.transfer.token.slot)
	return ground_access_cells(drop_manager.item_floor_cell(pull.items[index]))


func scheduling_revision() -> int:
	return StockpileManager.hauling_revision


## Quote the same first pickup reserve_haul would choose, without claiming
## goods. Incremental scans keep the scheduler's time budget meaningful.
func advance_haul_quote(from: Vector3i, query: Dictionary, deadline_usec: int) -> bool:
	if not is_instance_valid(drop_manager) or not _has_any_room():
		query.cell = Vector3i(-1, -1, -1)
		return true
	if not query.has("loose"): query.loose = {}
	var exclude: Dictionary = query.get("exclude", {})
	if not drop_manager.advance_nearest_haul_query(from, _can_haul_key, query.loose, deadline_usec, exclude): return false
	if is_instance_valid(query.loose.best):
		query.cell = drop_manager.item_floor_cell(query.loose.best)
		return true
	if not query.has("relocation"): query.relocation = {}
	if not StockpileManager.advance_relocation_quote(self, from, query.relocation, deadline_usec, exclude): return false
	query.cell = query.relocation.cell
	return true


## Destination owns the HAUL lease. A hidden handoff marker supplies the
## existing reach animation; it is never a loose, stored or saved item.
func _reserve_relocation(dwarf_id: int, near: Vector3i, exclude: Dictionary) -> Dictionary:
	for candidate: Dictionary in StockpileManager.relocation_candidates(self, near, exclude):
		var origin: StorageComponent = candidate.source
		var outgoing: Dictionary = candidate.token
		var deposit: Variant = _reserve_deposit(outgoing.item, near, dwarf_id, outgoing.count)
		if deposit == null: continue
		outgoing.count = int(deposit.count)
		outgoing.active = true
		origin._outgoing[outgoing.slot] = outgoing
		var marker: Node3D = drop_manager.create_item_visual(outgoing.item, outgoing.count)
		if marker == null:
			_release_deposit(deposit)
			origin.release_outgoing(outgoing)
			continue
		marker.set_meta("relocation_id", origin.relocation_id(outgoing.slot))
		marker.position = origin.withdrawal_contact(outgoing.slot)
		drop_manager.add_child(marker)
		marker.visible = false
		var items: Array[Node3D] = [marker]
		_pulls[dwarf_id] = {"items": items, "deposits": {marker: deposit}, "cargo": {}, "picked": {},
			"transfer": {"source": origin, "token": outgoing, "marker": marker}}
		StockpileManager.storage_rules_changed()
		origin.changed.emit()
		var definition: Dictionary = drop_manager.get_item_def(outgoing.item)
		return {"items": items, "deposit_target": _deposit_walk_target(deposit),
			"carry_mult": carry_speed_mult_heavy if definition.get("weight_class") == "heavy" else 1.0}
	return {}


func _take_relocation(transfer: Dictionary, dwarf_id: int) -> Node3D:
	var origin: StorageComponent = transfer.source
	var token: Dictionary = transfer.token
	if not bool(token.active) or not StockpileManager.is_registered(origin) or origin.accepts_key(token.item): return null
	var stack: Dictionary = origin.stored_entries().get(token.slot, {})
	if stack.get("item") != token.item or int(stack.get("count", 0)) < int(token.count): return null
	var cargo := origin.withdraw_stack(token.slot, token.count, dwarf_id)
	if cargo == null: return null
	origin.release_outgoing(token)
	return drop_manager.take_quantity(cargo, token.count, dwarf_id)


func _release_transfer(pull: Dictionary) -> void:
	if not pull.has("transfer"): return
	var transfer: Dictionary = pull.transfer
	transfer.source.release_outgoing(transfer.token)
	if is_instance_valid(transfer.marker): transfer.marker.queue_free()


## Teardown also covers reservations whose worker no longer exists. Tokens
## held by another destination become invalid, so it cannot withdraw twice.
func release_storage_claims() -> void:
	for dwarf_id: int in _pulls.keys(): cancel_haul(dwarf_id)
	for token: Dictionary in _outgoing.values(): release_outgoing(token)
	_lease_ids.clear()


# ── Work source: lease posting (doc 18 §2.2 / doc 16 §2.1) ────────────────────

## Posts/top-ups HAUL leases: min(max_haulers, accepted loose items) while
## this storage has room, minus live leases. Called on wake events, never
## per frame. The payload key stays "zone_id" — the DwarfAgent HAUL executor
## resolves any storage family through it.
func update_leases() -> void:
	if source_id < 0 or drop_manager == null or not is_instance_valid(drop_manager):
		return
	if not _has_any_room():
		return
	var candidates := int(drop_manager.call("count_loose", _query_tags(), max_haulers, _can_haul_key))
	if candidates < max_haulers:
		candidates += StockpileManager.relocation_candidates(self, Vector3i.ZERO, {}, max_haulers - candidates).size()
	var wanted := mini(max_haulers, candidates)
	var missing := wanted - _lease_ids.size()
	for i: int in range(missing):
		var target := nearest_stand_target(Vector3i.ZERO)
		var task_id := int(TaskManager.add_task(
			Task.Type.HAUL, target, { "zone_id": source_id }, source_id))
		_lease_ids[task_id] = true


## A lease left the system FOR GOOD (completed / cancelled / failed).
## NOT for releases — a released lease returns to PENDING and still counts
## against max_haulers. Reservation cleanup is idempotent.
func on_task_gone(task_id: int, dwarf_id: int) -> void:
	_lease_ids.erase(task_id)
	if dwarf_id >= 0:
		cancel_haul(dwarf_id)


# ── Carry-budget haul loop (doc 49) ─────────────────────────────────────────

## Step 1+2: reserve a BUNDLE within carry_capacity points. Each physical
## object pays its JSON carry_cost once, including partially filled crates.
## Nearby objects that do not fit are skipped so a cheaper one can fill the
## remaining budget. Only successful paired item/deposit claims spend points.
func reserve_haul(dwarf_id: int, dwarf_cell: Vector3i, exclude: Dictionary) -> Dictionary:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return {}
	var main := drop_manager.call("nearest_loose", _query_tags(), dwarf_cell, exclude, _can_haul_key) as Node3D
	if main == null:
		return _reserve_relocation(dwarf_id, dwarf_cell, exclude)
	var main_cell: Vector3i = drop_manager.call("item_floor_cell", main)

	var items: Array[Node3D] = [main]
	if _carry_cost(String(drop_manager.call("item_key_of", main))) < carry_capacity:
		var near_exclude := exclude.duplicate()
		near_exclude[main] = true
		var extras: Array[Node3D] = drop_manager.call(
			"loose_near", _query_tags(), main_cell, pouch_bundle_radius,
			0, near_exclude, _can_haul_key)
		for extra: Node3D in extras:
			items.append(extra)

	var reserved_items: Array[Node3D] = []
	var deposits: Dictionary = {}             # source node -> quantity reservation
	var any_heavy := false
	var remaining := carry_capacity
	for item: Node3D in items:
		var key := String(drop_manager.call("item_key_of", item))
		var cost := _carry_cost(key)
		if cost > remaining:
			continue
		var token: Variant = _reserve_deposit(key, main_cell, dwarf_id, int(drop_manager.call("quantity_of", item)))
		if token == null:
			continue
		if not bool(drop_manager.call("reserve", item, dwarf_id)):
			_release_deposit(token)
			continue   # raced another hauler; try the next candidate
		reserved_items.append(item)
		deposits[item] = token
		remaining -= cost
		var def: Dictionary = drop_manager.call("get_item_def", key)
		if String(def.get("weight_class", "light")) == "heavy":
			any_heavy = true
		if remaining == 0:
			break
	if reserved_items.is_empty():
		return {}

	var ordered := _visit_order(reserved_items, dwarf_cell)
	_pulls[dwarf_id] = { "items": ordered, "deposits": deposits, "cargo": {}, "picked": {} }
	return {
		"items": ordered,
		"deposit_target": _deposit_walk_target(deposits[ordered[0]]),
		"carry_mult": carry_speed_mult_heavy if any_heavy else 1.0,
	}


## Read-only placement offers from this haul. A relocation marker represents
## an outgoing stored claim, never an extra physical item. Picked cargo replaces
## its original node (which may have been split from a larger crate).
func placement_haul_items(dwarf_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pull: Dictionary = _pulls.get(dwarf_id, {})
	if pull.is_empty() or not is_instance_valid(drop_manager): return result
	for item: Node3D in pull.items:
		if not is_instance_valid(item) or item.is_queued_for_deletion() or pull.picked.has(item): continue
		var token: Dictionary = pull.deposits.get(item, {})
		if not bool(token.get("active", false)): continue
		var stored: bool = pull.has("transfer")
		if not stored and not drop_manager.reserved_by(item, dwarf_id): continue
		var instance_id := String(item.get_meta("instance_id", ""))
		if stored:
			var stack: Dictionary = pull.transfer.source.stored_entries().get(pull.transfer.token.slot, {})
			instance_id = String(stack.get("instance_id", ""))
		result.append({"item": item, "key": String(token.item),
			"count": int(token.count) if stored else int(drop_manager.quantity_of(item)),
			"instance_id": instance_id, "carried": false})
	for item: Node3D in pull.cargo:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and bool(pull.cargo[item].active):
			result.append({"item": item, "key": String(pull.cargo[item].item),
				"count": int(drop_manager.quantity_of(item)),
				"instance_id": String(item.get_meta("instance_id", "")), "carried": true})
	return result


## Release protocol: frees every remaining reservation. Safe to call twice.
func cancel_haul(dwarf_id: int) -> void:
	if not _pulls.has(dwarf_id):
		return
	var pull: Dictionary = _pulls[dwarf_id]
	_pulls.erase(dwarf_id)
	_release_transfer(pull)
	for token: Variant in pull["deposits"].values():
		_release_deposit(token)
	if drop_manager == null or not is_instance_valid(drop_manager):
		return
	var items: Array = pull["items"]
	for i: int in range(items.size()):
		var item: Node3D = items[i]
		if item != null and is_instance_valid(item):
			# Owner-guarded: skipped items in this range may have been
			# re-reserved by another hauler since (spam-robustness pass).
			drop_manager.call("unreserve", item, dwarf_id)


## Step 3: pick up the item at `index` in the visit order.
func take_item(dwarf_id: int, index: int) -> Node3D:
	if not _pulls.has(dwarf_id):
		return null
	var pull: Dictionary = _pulls[dwarf_id]
	var items: Array = pull["items"]
	if index < 0 or index >= items.size():
		return null
	var item: Node3D = items[index]
	if item == null or not is_instance_valid(item) \
			or drop_manager == null or not is_instance_valid(drop_manager):
		return null
	if not pull.deposits.has(item) or not bool(pull.deposits[item].active):
		return null
	if pull.picked.has(item):
		return null
	if not accepts_key(String(pull.deposits[item].item)): return null
	var cargo: Node3D = _take_relocation(pull.transfer, dwarf_id) if pull.has("transfer") else drop_manager.call("take_quantity", item, int(pull.deposits[item].count), dwarf_id)
	if cargo != null:
		pull.cargo[cargo] = pull.deposits[item]
		pull.picked[item] = true
	return cargo


## An unpickable/unpathable bundle item: free its reservation and one
## deposit token; the rest of the bundle continues.
func skip_item(dwarf_id: int, index: int) -> void:
	if not _pulls.has(dwarf_id):
		return
	var pull: Dictionary = _pulls[dwarf_id]
	_release_transfer(pull)
	var items: Array = pull["items"]
	if index >= 0 and index < items.size():
		var item: Node3D = items[index]
		if item != null and is_instance_valid(item) \
				and drop_manager != null and is_instance_valid(drop_manager):
			drop_manager.call("unreserve", item, dwarf_id)
		if pull.deposits.has(item):
			_release_deposit(pull.deposits[item])


## Step 4: multi-deposit. `carried` = [[node, item_key], ...].
func commit_haul(dwarf_id: int, carried: Array) -> bool:
	if not _pulls.has(dwarf_id):
		return false
	var pull: Dictionary = _pulls[dwarf_id]
	# Validate the whole delivery before changing counts. A failed commit leaves
	# every node with the dwarf, whose release path drops all cargo safely.
	for entry: Array in carried:
		if not accepts_key(String(entry[1])): return false
		if not pull.cargo.has(entry[0]) or not bool(pull.cargo[entry[0]].active):
			return false
		var token: Dictionary = pull.cargo[entry[0]]
		if String(token.item) != String(entry[1]) or int(token.count) != int(drop_manager.call("quantity_of", entry[0])):
			return false
	for entry: Array in carried:
		var node: Node3D = entry[0]
		var key: String = entry[1]
		var token: Dictionary = pull.cargo[node]
		if node.has_meta("instance_id"): token["instance_id"] = node.get_meta("instance_id")
		_commit_one(token, key)
		_place_visual(node, token)
		if changed_callback.is_valid():
			changed_callback.call(key, int(token.count))
	cancel_haul(dwarf_id)
	changed.emit()
	return not carried.is_empty()


## Greedy nearest-neighbour ordering of bundle items starting at `from_cell`.
func _visit_order(items: Array[Node3D], from_cell: Vector3i) -> Array[Node3D]:
	var remaining := items.duplicate()
	var ordered: Array[Node3D] = []
	var here := from_cell
	while not remaining.is_empty():
		var best_idx := 0
		var best_dist: int = 0x7FFFFFFF
		for i: int in range(remaining.size()):
			var cell: Vector3i = drop_manager.call("item_floor_cell", remaining[i])
			var d := cell - here
			var dist := absi(d.x) + absi(d.z)
			if dist < best_dist:
				best_idx = i
				best_dist = dist
		var next: Node3D = remaining[best_idx]
		remaining.remove_at(best_idx)
		ordered.append(next)
		here = drop_manager.call("item_floor_cell", next)
	return ordered
