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
var pouch_capacity: int = 4                   # items per trip (SH backpack = 4)
var pouch_bundle_radius: int = 8              # extras within this radius of the MAIN item
var drop_manager: Node3D = null               # ItemDropManager (guard is_instance_valid)
var changed_callback: Callable = Callable()   # (item_key, delta) -> StockpileManager signal
var filter_tags: Array[String] = []

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


## Free an unused reservation token.
func _release_deposit(_token: Variant) -> void:
	pass


## Commit a token's quantity (the base fires changed_callback in units).
func _commit_one(_token: Variant, _item_key: String) -> void:
	pass


## Where the hauler walks to deposit (zone: the first reserved cell;
## container: the stand cell).
func _deposit_walk_target(_first_token: Variant) -> Vector3i:
	return Vector3i(-1, -1, -1)


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
	var candidates := int(drop_manager.call("count_loose", filter_tags, max_haulers, _has_room_for_key))
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


# ── The pouch haul loop (doc 18 §2.3 + pouch — hoisted verbatim) ──────────────

## Step 1+2: reserve a BUNDLE — the nearest accepted item plus up to
## pouch_capacity−1 extras within pouch_bundle_radius, each pairwise with a
## reserved deposit token. Items return in greedy nearest-neighbour visit
## order. {} when there is nothing to haul or no room.
func reserve_haul(dwarf_id: int, dwarf_cell: Vector3i, exclude: Dictionary) -> Dictionary:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return {}
	var main := drop_manager.call("nearest_loose", filter_tags, dwarf_cell, exclude, _has_room_for_key) as Node3D
	if main == null:
		return {}
	var main_cell: Vector3i = drop_manager.call("item_floor_cell", main)

	var items: Array[Node3D] = [main]
	if pouch_capacity > 1:
		var near_exclude := exclude.duplicate()
		near_exclude[main] = true
		var extras: Array[Node3D] = drop_manager.call(
			"loose_near", filter_tags, main_cell, pouch_bundle_radius,
			pouch_capacity - 1, near_exclude, _has_room_for_key)
		for extra: Node3D in extras:
			items.append(extra)

	var reserved_items: Array[Node3D] = []
	var deposits: Dictionary = {}             # source node -> quantity reservation
	var any_heavy := false
	for item: Node3D in items:
		var key := String(drop_manager.call("item_key_of", item))
		var token: Variant = _reserve_deposit(key, main_cell, dwarf_id, int(drop_manager.call("quantity_of", item)))
		if token == null:
			continue
		if not bool(drop_manager.call("reserve", item, dwarf_id)):
			_release_deposit(token)
			continue   # raced another hauler; try the next candidate
		reserved_items.append(item)
		deposits[item] = token
		var def: Dictionary = drop_manager.call("get_item_def", key)
		if String(def.get("weight_class", "light")) == "heavy":
			any_heavy = true
	if reserved_items.is_empty():
		return {}

	var ordered := _visit_order(reserved_items, dwarf_cell)
	_pulls[dwarf_id] = { "items": ordered, "deposits": deposits, "cargo": {}, "picked": {} }
	return {
		"items": ordered,
		"deposit_target": _deposit_walk_target(deposits[ordered[0]]),
		"carry_mult": carry_speed_mult_heavy if any_heavy else 1.0,
	}


## Release protocol: frees every remaining reservation. Safe to call twice.
func cancel_haul(dwarf_id: int) -> void:
	if not _pulls.has(dwarf_id):
		return
	var pull: Dictionary = _pulls[dwarf_id]
	_pulls.erase(dwarf_id)
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
	var cargo: Node3D = drop_manager.call("take_quantity", item, int(pull.deposits[item].count), dwarf_id)
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
		if not pull.cargo.has(entry[0]) or not bool(pull.cargo[entry[0]].active):
			return false
		var token: Dictionary = pull.cargo[entry[0]]
		if String(token.item) != String(entry[1]) or int(token.count) != int(drop_manager.call("quantity_of", entry[0])):
			return false
	for entry: Array in carried:
		var node: Node3D = entry[0]
		var key: String = entry[1]
		var token: Dictionary = pull.cargo[node]
		_commit_one(token, key)
		_place_visual(node, token)
		if changed_callback.is_valid():
			changed_callback.call(key, int(token.count))
	cancel_haul(dwarf_id)
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
