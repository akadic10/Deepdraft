class_name ItemDropManager
extends Node3D

const Permission = preload("res://scripts/components/ItemPermission.gd")

## Spawns and owns dropped-item entities. Doc 18 Phase 2 grew this into the
## LOOSE-ITEM INDEX: every drop is registered on spawn, reservable by hauling
## dwarves, takeable (picked up off the ground), and placeable back as a
## STORED node on a stockpile cell. The index is event-maintained (spawn /
## take / drop / place) — never rebuilt by scanning (doc 16 §2.5 discipline).
## Scene node in debug_world.tscn (presentation lives in the scene, not an
## autoload — the SurfaceFloraSpawner pattern), found by producers via the
## "item_drop_manager" group.
##
## Node states: LOOSE (in _loose, restockable), RESERVED (in _loose and
## _reserved — visible but claimed), CARRIED (taken — reparented under the
## dwarf, absent from the index), STORED (child of this manager on a zone
## cell, meta "stored", absent from _loose — zones own the counts).
##
## REGISTRY PATTERN (AGENT.md): this node is the ONE owner of
## data/entities/items/resources.json — no other script may open it. Item defs
## load lazily on first spawn (the file's own contract: "loaded on demand, NOT
## held in memory at boot").
##
## VISUALS (doc 61): ordinary drops use 8 vox/block, produce crates use 16.
## Both bake scale into vertices and instance at 1.0 with the project vertex
## material. A stable root owns quantity and swaps its child at fill thresholds.
##
## SLICE RULE (doc 11 Phase 5): drops obey the slice like flora and dwarves —
## hidden when their block is above the cut.

@export var slice_controller_path: NodePath

const RESOURCES_PATH := "res://data/entities/items/resources.json"
const SLICE_OFF_Y := 127
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var _picking = Picking.new()

## A new loose item entered the world (spawned or dropped by an interrupted
## hauler). StockpileManager wakes zone lease posting on this (doc 18 §2.2).
signal drop_spawned(item_key: String)
## Presentation wake for availability changes, including reservations and pickup.
signal loose_items_changed()

var _defs: Dictionary = {}          # item key (String) -> def Dictionary
var _defs_loaded: bool = false
var _scene_cache: Dictionary = {}   # model path -> PackedScene (null cached as absent)
var _material: Material = null
var _surface_materials: Dictionary = {} # item key -> shared optional glossy material
var _slice_y: int = SLICE_OFF_Y
var _drop_count: int = 0
var _missing_models: Dictionary = {}   # path -> true (warn once per model)

# ── Loose-item index (doc 18 Phase 2) ─────────────────────────────────────────
var _loose: Dictionary = {}         # Node3D -> item_key (String)
var _reserved: Dictionary = {}      # Node3D -> dwarf_id (int)
## Read-only inventory accounting for objects between pickup and deposit.
## Weak references never own cargo; dwarves/storage keep lifecycle authority.
var _inventory_transit: Dictionary = {} # instance_id -> WeakRef
var _unsupported_columns: Dictionary = {} # coalesced terrain edits, never a per-frame scan
var _instance_promises: Dictionary = {} # plant identity -> standing Move claim owner


func _ready() -> void:
	drop_spawned.connect(func(_key: String): loose_items_changed.emit())
	WorldData.block_changed.connect(_on_support_changed)
	WorldClock.season_changed.connect(func(_season: String):
		for node: Node3D in get_tree().get_nodes_in_group("packed_shrubs"):
			if not node.is_queued_for_deletion(): set_quantity(node, quantity_of(node)))
	add_to_group("item_drop_manager")
	add_to_group("object_explorer_provider")
	add_to_group(SaveManager.OWNER_GROUP)
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)
	var source := StandardMaterial3D.new()
	source.vertex_color_use_as_albedo = true
	source.roughness = 1.0
	source.metallic = 0.0
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	source.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var lighting := get_tree().get_first_node_in_group("underground_lighting")
	_material = lighting.make_material(source) if lighting != null else source


# ── Public API ────────────────────────────────────────────────────────────────

## Spawns `count` units of an item at a mined block position. The drop rests
## on the first solid floor at or below the block (mined columns drop their
## loot to the pit floor). Position jitter and yaw are cosmetic randomness —
## runtime behaviour, not worldgen (Hard Rule 8 does not apply to drops).
func spawn_drop(item_key: String, count: int, block: Vector3i) -> void:
	if count <= 0:
		return
	_ensure_defs()
	var def: Dictionary = _defs.get(item_key, {})
	if def.is_empty():
		push_warning("ItemDropManager: unknown item '%s' — drop skipped." % item_key)
		return
	var rest_y := _rest_y(block)
	var remaining := count
	# Only unclaimed nearby crates can be topped up. A worker's reservation is
	# an exact quantity and must never change underneath that worker.
	if item_capacity(item_key) > 1:
		for existing: Node3D in _loose:
			if not Permission.allowed(existing) or _reserved.has(existing) or String(_loose[existing]) != item_key:
				continue
			if item_floor_cell(existing) != Vector3i(block.x, rest_y - 1, block.z):
				continue
			var added := mini(remaining, item_capacity(item_key) - quantity_of(existing))
			if added > 0:
				set_quantity(existing, quantity_of(existing) + added)
				remaining -= added
	while remaining > 0:
		var amount := mini(remaining, item_capacity(item_key))
		var node := create_item_visual(item_key, amount)
		remaining -= amount
		var jitter := Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
		node.position = Vector3(float(block.x) + 0.5, float(rest_y), float(block.z) + 0.5) + jitter
		node.rotation.y = float(randi_range(0, 3)) * PI / 2.0 if item_capacity(item_key) > 1 else randf_range(0.0, TAU)
		node.set_meta("base_y", rest_y)
		node.set_meta("item_key", item_key)
		# Same rule as DwarfAgent.apply_slice: floor(position.y) <= slice_y.
		node.visible = rest_y <= _slice_y
		add_child(node)
		_loose[node] = item_key
	drop_spawned.emit(item_key)


func promise_instance(id: String, owner: int) -> void:
	if int(_instance_promises.get(id, -1)) == owner: return
	_instance_promises[id] = owner
	for node: Node3D in _loose:
		if Permission.allowed(node) and String(node.get_meta("instance_id", "")) == id and not _reserved.has(node):
			_reserved[node] = owner


func release_instance_promise(id: String, owner: int) -> void:
	if int(_instance_promises.get(id, -1)) != owner: return
	_instance_promises.erase(id)
	for node: Node3D in _loose:
		if is_instance_valid(node) and String(node.get_meta("instance_id", "")) == id: unreserve(node, owner)


func instance_promised(id: String, except_owner: int = -1) -> bool:
	return not id.is_empty() and _instance_promises.has(id) and int(_instance_promises[id]) != except_owner


func _reserve_promised_instance(node: Node3D) -> void:
	var id := String(node.get_meta("instance_id", ""))
	if Permission.allowed(node) and _instance_promises.has(id): _reserved[node] = int(_instance_promises[id])


func get_stats() -> Dictionary:
	return { "drops": _drop_count, "loose": _loose.size(), "reserved": _reserved.size() }


func save_section_key() -> String:
	return "items"


func save_restore_priority() -> int:
	return 50


func serialize_state() -> Dictionary:
	var entries: Array = []
	for node: Node3D in _loose:
		if not is_instance_valid(node):
			continue
		entries.append({
			"item_key": String(_loose[node]),
			"position": SaveManager.pack_v3(node.position),
			"rotation_y": node.rotation.y,
			"count": quantity_of(node), "disallowed": not Permission.allowed(node),
		})
		if node.has_meta("instance_id"): entries.back()["instance_id"] = node.get_meta("instance_id")
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ak := "%s:%s" % [String(a["item_key"]), str(a["position"])]
		var bk := "%s:%s" % [String(b["item_key"]), str(b["position"])]
		return ak < bk)
	return { "loose": entries }


func restore_state(state: Dictionary) -> void:
	for raw in state.get("loose", []):
		if not (raw is Dictionary):
			continue
		var entry := raw as Dictionary
		var key := String(entry.get("item_key", ""))
		restore_loose_item(
			key,
			SaveManager.unpack_v3(entry.get("position", [])),
			float(entry.get("rotation_y", 0.0)), int(entry.get("count", 1)), String(entry.get("instance_id", "")), bool(entry.get("disallowed", false)))


## Builds one unindexed item visual for save restoration consumers (shelf
## anchors and ground-stockpile stored nodes).
func create_item_visual(item_key: String, count: int = 1, instance_id: String = "") -> Node3D:
	_ensure_defs()
	var def: Dictionary = _defs.get(item_key, {})
	if def.is_empty():
		push_warning("ItemDropManager: unknown restored item '%s'." % item_key)
		return null
	var node := Node3D.new()
	node.name = "Drop_%s_%d" % [item_key.get_slice(":", item_key.get_slice_count(":") - 1), _drop_count]
	node.set_meta("item_key", item_key)
	if not instance_id.is_empty():
		node.set_meta("instance_id", instance_id)
		if def.has("plant_definition"): node.add_to_group("packed_shrubs")
	set_quantity(node, count)
	_drop_count += 1
	return node


func restore_stored_item(item_key: String, cell: Vector3i, count: int = 1, instance_id: String = "", disallowed: bool = false) -> void:
	var node := create_item_visual(item_key, count, instance_id)
	if node == null:
		return
	add_child(node)
	node.set_meta("disallowed", disallowed)
	place_stored(node, cell)


## Restores loose goods without random jitter. Old unsupported positions settle
## onto the current terrain after mining has been restored. Also
## used for items that were in transit at snapshot time: tasks are transient,
## so those materialize safely at their saved carrier's feet on load.
func restore_loose_item(item_key: String, restored_position: Vector3,
		rotation_y: float = 0.0, count: int = 1, instance_id: String = "", disallowed: bool = false) -> void:
	if count <= 0:
		return
	var amount := mini(count, item_capacity(item_key))
	var node := create_item_visual(item_key, amount, instance_id)
	if node == null:
		return
	node.set_meta("disallowed", disallowed)
	node.position = restored_position
	node.rotation.y = rotation_y
	_settle_item(node)
	node.set_meta("base_y", node.position.y)
	node.set_meta("stored", false)
	node.visible = floori(node.position.y) <= _slice_y
	add_child(node)
	_loose[node] = item_key
	_reserve_promised_instance(node)
	drop_spawned.emit(item_key)
	if count > amount:
		restore_loose_item(item_key, restored_position, rotation_y, count - amount, "", disallowed)


# ── Loose-item index API (doc 18 §2.1) ────────────────────────────────────────

## Public item-definition accessor (Registry Pattern: this node owns
## resources.json; everyone else queries through here). {} if unknown.
func get_item_def(item_key: String) -> Dictionary:
	_ensure_defs()
	return _defs.get(item_key, {})


func get_item_defs() -> Dictionary:
	_ensure_defs()
	return _defs.duplicate(true)


## Presentation snapshot of non-stored goods. Counts are contents, not crates.
## Ground/container storage is counted exclusively by StockpileManager.
func get_inventory_items() -> Dictionary:
	var result := {"loose": [], "carried": [], "equipped": []}
	for node in _loose:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			result.loose.append({"node": node, "key": String(_loose[node]),
				"count": quantity_of(node), "disallowed": not Permission.allowed(node), "reserved": _reserved.has(node)})
	for id: int in _inventory_transit.keys():
		var node = (_inventory_transit[id] as WeakRef).get_ref()
		if not is_instance_valid(node) or node.is_queued_for_deletion() or bool(node.get_meta("stored", false)):
			_inventory_transit.erase(id)
			continue
		var category := "equipped" if bool(node.get_meta("equipped", false)) else "carried"
		result[category].append({"node": node, "key": item_key_of(node), "count": quantity_of(node)})
	return result


func _track_inventory_transit(node: Node3D) -> void:
	var id := node.get_instance_id()
	_inventory_transit[id] = weakref(node)
	var changed := _inventory_node_exited.bind(id)
	if not node.tree_exited.is_connected(changed): node.tree_exited.connect(changed)


func _inventory_node_exited(id: int) -> void:
	_prune_inventory_transit.call_deferred(id)


func _prune_inventory_transit(id: int) -> void:
	if not _inventory_transit.has(id): return
	var node = (_inventory_transit[id] as WeakRef).get_ref()
	if not is_instance_valid(node) or node.is_queued_for_deletion() or bool(node.get_meta("stored", false)):
		_inventory_transit.erase(id)
		loose_items_changed.emit()


## Nearest unreserved loose item whose material_tags overlap accepted_tags,
## by flat Manhattan distance from `from`. `exclude` is a per-dwarf blacklist
## (Node -> true) of items that failed pathing this round. Null if none.
func nearest_loose(accepted_tags: Array, from: Vector3i, exclude: Dictionary = {}, can_store: Callable = Callable()) -> Node3D:
	_ensure_defs()
	var best: Node3D = null
	var best_dist: int = 0x7FFFFFFF
	for node: Node3D in _loose:
		if not Permission.allowed(node) or _reserved.has(node) or exclude.has(node):
			continue
		var def: Dictionary = _defs.get(_loose[node], {})
		if can_store.is_valid() and not bool(can_store.call(String(_loose[node]))):
			continue
		var tags: Array = def.get("material_tags", [])
		var accepted := false
		for tag: String in accepted_tags:
			if tags.has(tag):
				accepted = true
				break
		if not accepted:
			continue
		var cell := item_floor_cell(node)
		if exclude.has(cell): continue
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


## Read-only scheduler query. Unlike a hauling reservation, this can span
## wakes without claiming anything. The scheduler invalidates it on item changes.
func advance_nearest_haul_query(from: Vector3i, accepts_key: Callable, query: Dictionary, deadline_usec: int, exclude_cells: Dictionary = {}) -> bool:
	if query.is_empty():
		query.merge({"nodes": _loose.keys(), "index": 0, "best": null, "distance": 0x7FFFFFFF})
	while int(query.index) < query.nodes.size():
		if Time.get_ticks_usec() >= deadline_usec: return false
		var node = query.nodes[query.index]
		query.index += 1
		if not Permission.allowed(node) or not _loose.has(node) or _reserved.has(node): continue
		if not bool(accepts_key.call(String(_loose[node]))): continue
		var cell := item_floor_cell(node)
		if exclude_cells.has(cell): continue
		var distance := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
		if distance < int(query.distance):
			query.best = node
			query.distance = distance
	return true


## Read-only single-unit crafting quote; the chosen physical item is retained
## so route exclusions are not lost when execution claims the material.
func advance_material_quote(keys: Array[String], from: Vector3i, query: Dictionary, deadline: int, excluded: Dictionary) -> bool:
	if query.is_empty(): query.merge({"nodes":_loose.keys(), "index":0, "best":{}, "distance":0x7FFFFFFF})
	while int(query.index) < query.nodes.size():
		if Time.get_ticks_usec() >= deadline: return false
		var node = query.nodes[query.index]
		query.index += 1
		if not Permission.allowed(node) or not _loose.has(node) or _reserved.has(node): continue
		if String(_loose[node]) not in keys or quantity_of(node) != 1: continue
		var cell := item_floor_cell(node)
		if excluded.has(cell): continue
		var delta := cell-from
		var distance := absi(delta.x)+absi(delta.y)+absi(delta.z)
		if distance < int(query.distance):
			query.distance = distance
			query.best = {"node":node, "key":String(_loose[node]), "cell":cell, "distance":distance}
	return true


## Nearest unreserved loose item of EXACTLY this key (type-matched fetch,
## doc 19 §3.3 — SH parity: any item of the URI satisfies a ghost).
func nearest_loose_of_key(item_key: String, from: Vector3i, exclude: Dictionary = {}, instance_id: String = "", claim_owner: int = -1) -> Node3D:
	var best: Node3D = null
	var best_dist: int = 0x7FFFFFFF
	for node: Node3D in _loose:
		if (_reserved.has(node) and int(_reserved[node]) != claim_owner) or exclude.has(node) or not Permission.allowed(node):
			continue
		if String(_loose[node]) != item_key:
			continue
		if not instance_id.is_empty() and String(node.get_meta("instance_id", "")) != instance_id: continue
		var cell := item_floor_cell(node)
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


## Unreserved loose accepted items within `radius` blocks (flat Chebyshev) of
## `center`, nearest first, capped at `limit` (0 returns all nearby candidates).
## The carry-cost selector needs all candidates to skip bulky nearby objects
## and still find smaller ones that fit. The pouch bundle search (doc 18
## pouch — SH NearbyItemSearch equivalent). `exclude` = blacklist + main item.
func loose_near(accepted_tags: Array, center: Vector3i, radius: int, limit: int, exclude: Dictionary = {}, can_store: Callable = Callable()) -> Array[Node3D]:
	_ensure_defs()
	var found: Array = []   # [dist, node] pairs
	for node: Node3D in _loose:
		if not Permission.allowed(node) or _reserved.has(node) or exclude.has(node):
			continue
		if can_store.is_valid() and not bool(can_store.call(String(_loose[node]))):
			continue
		var cell := item_floor_cell(node)
		if exclude.has(cell): continue
		var dx := absi(cell.x - center.x)
		var dz := absi(cell.z - center.z)
		if maxi(dx, dz) > radius or absi(cell.y - center.y) > 2:
			continue
		var tags: Array = (_defs.get(_loose[node], {}) as Dictionary).get("material_tags", [])
		var accepted := false
		for tag: String in accepted_tags:
			if tags.has(tag):
				accepted = true
				break
		if accepted:
			found.append([dx + dz, node])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]))
	var result: Array[Node3D] = []
	for pair: Array in found:
		result.append(pair[1] as Node3D)
		if limit > 0 and result.size() >= limit:
			break
	return result


## Unreserved loose items whose tags overlap accepted_tags, capped at `cap`
## (lease posting only needs "are there at least N?", doc 18 §2.2).
func count_loose(accepted_tags: Array, cap: int, can_store: Callable = Callable()) -> int:
	_ensure_defs()
	var found: int = 0
	for node: Node3D in _loose:
		if _reserved.has(node) or not Permission.allowed(node):
			continue
		if can_store.is_valid() and not bool(can_store.call(String(_loose[node]))):
			continue
		var tags: Array = (_defs.get(_loose[node], {}) as Dictionary).get("material_tags", [])
		for tag: String in accepted_tags:
			if tags.has(tag):
				found += 1
				break
		if found >= cap:
			return found
	return found


## The FLOOR cell a dwarf stands on to pick this item up (the item rests on
## that cell's top face — spawn_drop sets position.y to floor top).
func item_floor_cell(node: Node3D) -> Vector3i:
	return Vector3i(
		floori(node.position.x),
		int(round(node.position.y)) - 1,
		floori(node.position.z))


func item_key_of(node: Node3D) -> String:
	return String(_loose.get(node, node.get_meta("item_key", "")))


## Stored counts belong to StockpileManager. This query excludes every claim;
## placement separately adds reclaimable HAUL stock through TaskManager.
## Called on catalog wakes, never by a per-frame UI scan.
func get_unreserved_counts() -> Dictionary:
	var counts := {}
	for node: Node3D in _loose:
		if not Permission.allowed(node) or node.is_queued_for_deletion() or _reserved.has(node):
			continue
		var key: String = _loose[node]
		counts[key] = int(counts.get(key, 0)) + quantity_of(node)
	return counts


func item_capacity(item_key: String) -> int:
	return maxi(int(get_item_def(item_key).get("crate_capacity", 1)), 1)


func quantity_of(node: Node3D) -> int:
	return int(node.get_meta("quantity", 1))


func set_quantity(node: Node3D, count: int) -> void:
	var key := String(node.get_meta("item_key", ""))
	assert(count > 0 and count <= item_capacity(key))
	node.set_meta("quantity", count)
	if _loose.has(node): loose_items_changed.emit()
	var def := get_item_def(key)
	var models: Array = def.get("crate_models", [])
	var path := String(def.get("model", ""))
	if def.has("plant_definition") and node.has_meta("instance_id"):
		var plants := get_tree().get_first_node_in_group("surface_details")
		if plants != null:
			var packed_path: String = plants.packed_model(String(node.get_meta("instance_id")))
			if not packed_path.is_empty(): path = packed_path
	if models.size() == 3:
		path = String(models[mini((count - 1) / 8, 2)])
	if String(node.get_meta("visual_path", "")) == path and node.get_child_count() > 0:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
	node.add_child(_build_drop_node(key, _model_scene(path)))
	node.set_meta("visual_path", path)
	if def.has("plant_definition") and bool(node.get_meta("stored", false)) and node.has_meta("storage_anchor_position"):
		node.position = node.get_meta("storage_anchor_position")
		preload("res://scripts/components/StorageItemLayout.gd").fit(node,
			node.get_meta("storage_anchor_max_size"), float(node.get_meta("storage_anchor_scale")))


## Take just the reserved quantity. The remainder is still a loose crate.
func take_quantity(node: Node3D, count: int, dwarf_id: int) -> Node3D:
	if not Permission.allowed(node) or not _loose.has(node) or int(_reserved.get(node, -1)) != dwarf_id or count <= 0 or count > quantity_of(node):
		return null
	if count == quantity_of(node):
		take(node)
		return node
	var cargo := create_item_visual(item_key_of(node), count)
	_track_inventory_transit(cargo)
	set_quantity(node, quantity_of(node) - count)
	unreserve(node, dwarf_id)
	drop_spawned.emit(item_key_of(node))
	return cargo


func reserve(node: Node3D, dwarf_id: int) -> bool:
	if not Permission.allowed(node) or not _loose.has(node) or _reserved.has(node):
		return false
	_reserved[node] = dwarf_id
	loose_items_changed.emit()
	return true


func reserved_by(node: Node3D, owner: int) -> bool:
	return Permission.allowed(node) and _loose.has(node) and int(_reserved.get(node, -1)) == owner


## Owner-guarded (doc 18 spam-robustness pass): pass the reserving dwarf_id so
## a stale unreserve (an interrupted hauler cancelling a bundle whose skipped
## items were re-reserved by another hauler in the meantime) cannot clobber
## the new owner's reservation. -1 = unconditional (trusted callers only).
func unreserve(node: Node3D, dwarf_id: int = -1) -> void:
	if dwarf_id >= 0 and int(_reserved.get(node, -1)) != dwarf_id:
		return
	_reserved.erase(node)
	loose_items_changed.emit()


## Pickup: removes the node from the index and this manager; the caller
## (the hauling dwarf) reparents it as its carried visual. Returns the
## item key, or "" if the node was not a loose item.
func take(node: Node3D) -> String:
	if not Permission.allowed(node) or not _loose.has(node):
		return ""
	var key: String = _loose[node]
	_loose.erase(node)
	_reserved.erase(node)
	remove_child(node)
	_track_inventory_transit(node)
	loose_items_changed.emit()
	return key


## Deposit: re-adopts a carried node as a STORED item centred on a stockpile
## floor cell. Stored nodes are NOT in the loose index — the zone's
## cell_stacks own the counts (doc 18 §2.4: storage is physical).
func place_stored(node: Node3D, cell: Vector3i) -> void:
	_inventory_transit.erase(node.get_instance_id())
	_loose.erase(node)
	_reserved.erase(node)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	node.position = Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE
	node.set_meta("base_y", cell.y + 1)
	node.set_meta("stored", true)
	node.visible = cell.y + 1 <= _slice_y
	loose_items_changed.emit()


## Release protocol (doc 18 §2.3 step 5 / Hard Rule 12): an interrupted
## hauler drops its carried node at its feet as a normal loose item.
## Position jitter matches spawn_drop: a full pouch dropped on one cell must
## read as N items, not one (the WYSIWYG rule that drove one-item-per-tile).
func drop_loose(node: Node3D, floor_cell: Vector3i) -> void:
	_inventory_transit.erase(node.get_instance_id())
	var key := String(node.get_meta("item_key", ""))
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	var jitter := Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
	node.position = Vector3(float(floor_cell.x) + 0.5, float(floor_cell.y + 1), float(floor_cell.z) + 0.5) + jitter
	_settle_item(node)
	node.set_meta("base_y", node.position.y)
	node.set_meta("stored", false)
	node.scale = Vector3.ONE
	node.visible = floori(node.position.y) <= _slice_y
	_loose[node] = key
	_reserve_promised_instance(node)
	drop_spawned.emit(key)


## Container withdraw (doc 19 Phase 4): spawn ONE item at a floor cell,
## pre-reserved for the withdrawing dwarf — containers hold counts, not
## nodes. No drop_spawned emit (the item is claimed the instant it exists).
func spawn_reserved(item_key: String, floor_cell: Vector3i, dwarf_id: int, instance_id: String = "") -> Node3D:
	_ensure_defs()
	var def: Dictionary = _defs.get(item_key, {})
	if def.is_empty():
		push_warning("ItemDropManager: unknown item '%s' — spawn_reserved skipped." % item_key)
		return null
	var node := create_item_visual(item_key, 1, instance_id)
	node.position = Vector3(float(floor_cell.x) + 0.5, float(floor_cell.y + 1), float(floor_cell.z) + 0.5)
	node.set_meta("base_y", floor_cell.y + 1)
	node.set_meta("item_key", item_key)
	node.visible = floor_cell.y + 1 <= _slice_y
	add_child(node)
	_loose[node] = item_key
	_reserved[node] = dwarf_id
	loose_items_changed.emit()
	return node


## The STORED node sitting on a zone cell, or null (fetch withdraw, doc 19
## §3.3 — zones store one item per tile, so cell -> node is unique).
func stored_node_at(cell: Vector3i) -> Node3D:
	for child in get_children():
		if child is Node3D and bool(child.get_meta("stored", false)) \
				and item_floor_cell(child as Node3D) == cell:
			return child as Node3D
	return null


## Withdraw (doc 19 §3.3): a stored node re-enters the loose index already
## RESERVED by the withdrawing dwarf — no other hauler can grab it between
## withdrawal and pickup.
func withdraw_stored(node: Node3D, dwarf_id: int) -> void:
	node.set_meta("stored", false)
	var key := String(node.get_meta("item_key", ""))
	_loose[node] = key
	_reserved[node] = dwarf_id
	loose_items_changed.emit()


## Zone removal: stored nodes on the given cells become loose again, and
## Each visible node already represents its full stack quantity. Only legacy
## counts beyond that node respawn, so removing a zone never duplicates goods.
func release_stored_cells(stacks: Dictionary) -> void:
	var by_cell: Dictionary = {}
	for child in get_children():
		if child is Node3D and bool(child.get_meta("stored", false)):
			var node := child as Node3D
			by_cell[item_floor_cell(node)] = node
	for cell: Vector3i in stacks:
		var stack: Dictionary = stacks[cell]
		var key := String(stack.get("item", ""))
		var count := int(stack.get("count", 0))
		if by_cell.has(cell):
			var node: Node3D = by_cell[cell]
			node.set_meta("stored", false)
			_loose[node] = key
			_reserve_promised_instance(node)
			drop_spawned.emit(key)
			count -= quantity_of(node)
		if count > 0:
			spawn_drop(key, count, Vector3i(cell.x, cell.y + 1, cell.z))


# ── Internals ─────────────────────────────────────────────────────────────────

## A drop can outlive the ledge it originally landed on. Coalesce mining edits
## and only rest-scan loose items in affected columns; stored/carried goods
## retain their respective owners. Slicing and streamed mesh changes do nothing.
func _on_support_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if not BlockRegistry.is_solid(old_id) or BlockRegistry.is_solid(new_id): return
	if _unsupported_columns.is_empty(): _settle_changed_columns.call_deferred()
	_unsupported_columns[Vector2i(pos.x, pos.z)] = true


func _settle_changed_columns() -> void:
	var columns := _unsupported_columns
	_unsupported_columns = {}
	var moved := false
	# Releasing a pickup may drop other cargo and mutate the loose index.
	for node in _loose.keys():
		if not is_instance_valid(node) or not _loose.has(node): continue
		if not columns.has(Vector2i(floori(node.position.x), floori(node.position.z))): continue
		moved = _settle_item(node) or moved
	if moved: loose_items_changed.emit()


func _settle_item(node: Node3D) -> bool:
	var rest_y := _rest_y(Vector3i(floori(node.position.x), ceili(node.position.y - .001), floori(node.position.z)))
	if float(rest_y) >= node.position.y - .001: return false
	# A worker must not complete a reach against the old world transform.
	if _reserved.has(node):
		TaskManager.invalidate_dwarf_task(int(_reserved[node]))
		_reserved.erase(node) # also covers an orphaned claim without a live task
	node.position.y = rest_y
	node.set_meta("base_y", rest_y)
	node.visible = rest_y <= _slice_y
	return true


func pick_explorer_object(start: Vector3, end: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var nearest := INF
	for child in get_children():
		if not (child is Node3D) or not child.has_meta("item_key") or child.is_queued_for_deletion():
			continue
		var distance: float = _picking.hit_distance(child, start, end)
		if distance < nearest:
			nearest = distance
			result = {"id": child, "distance": distance}
	return result


func get_explorer_bounds(id: Variant) -> AABB:
	return Picking.world_bounds(id) if _inspectable(id) else AABB()


func _inspectable(id: Variant) -> bool:
	return is_instance_valid(id) and id is Node3D and id.get_parent() == self \
		and id.is_visible_in_tree() and not id.is_queued_for_deletion()


func get_explorer_data(id: Variant) -> Dictionary:
	if not _inspectable(id):
		return {}
	var key := item_key_of(id)
	var def := get_item_def(key)
	var crated := item_capacity(key) > 1
	var actions := [Permission.action(not Permission.allowed(id))]
	if def.has("water_stone") and Permission.allowed(id): actions.append({"id":"place","text":"Place stone"})
	return {
		"title": String(def.get("display_name", key)),
		"kind": "Produce crate" if crated else "Resource",
		"rows": [
			["Contents", String(def.get("display_name", key))],
			["Quantity", "%d / %d" % [quantity_of(id), item_capacity(key)] if crated else str(quantity_of(id))],
			["Colony access", "Disallowed" if not Permission.allowed(id) else "Allowed"],
			["Location", "In storage" if bool(id.get_meta("stored", false)) else "Awaiting collection"],
		],
		"details": String(def.get("description", "")),
		"actions": actions,
	}


func perform_explorer_action(id: Variant, action_id: String) -> void:
	if not _inspectable(id): return
	if action_id == "permission": set_disallowed(id, Permission.allowed(id))
	elif action_id == "place" and Permission.allowed(id) and get_item_def(item_key_of(id)).has("water_stone"):
		var controller := get_tree().get_first_node_in_group("furniture_controller")
		if controller != null: controller.begin_water_stone_move(String(id.get_meta("instance_id", "")))


func set_disallowed(node: Node3D, value: bool) -> void:
	if not is_instance_valid(node): return
	node.set_meta("disallowed", value)
	if bool(node.get_meta("stored", false)):
		StockpileManager.set_node_disallowed(node, value)
	if value:
		var owner := int(_reserved.get(node, -1))
		_reserved.erase(node)
		if owner >= 0: TaskManager.invalidate_dwarf_task(owner)
		var parent := node.get_parent()
		while parent != null:
			if parent is DwarfAgent:
				TaskManager.invalidate_dwarf_task(parent.dwarf_id)
				break
			parent = parent.get_parent()
		var furniture := get_tree().get_first_node_in_group("furniture_controller")
		if furniture != null:
			for ghost_id in furniture._ghosts.keys():
				var ghost: FurnitureGhostComponent = furniture._ghosts[ghost_id]
				if ghost._claim == node or node in ghost._fetches.values() or (not ghost.required_instance_id.is_empty() and ghost.required_instance_id == String(node.get_meta("instance_id", ""))):
					furniture.cancel_ghost(ghost_id)
	else:
		_reserve_promised_instance(node)
	loose_items_changed.emit()
	drop_spawned.emit(item_key_of(node))
	StockpileManager.permissions_changed()

func _build_drop_node(item_key: String, scene: PackedScene) -> Node3D:
	var node: Node3D = null
	if scene != null:
		node = scene.instantiate() as Node3D
	if node == null:
		# Fallback: a small neutral cube so a missing model is visible, not silent.
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		mesh_instance.mesh = box
		node = mesh_instance
	node.name = "Drop_%s_%d" % [item_key.get_slice(":", item_key.get_slice_count(":") - 1), _drop_count]
	_apply_material(node, _material_for(item_key))
	return node


func _material_for(item_key: String) -> Material:
	var surface: Dictionary = get_item_def(item_key).get("surface", {})
	if surface.is_empty(): return _material
	if _surface_materials.has(item_key): return _surface_materials[item_key]
	var source := StandardMaterial3D.new()
	source.vertex_color_use_as_albedo = true
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	source.roughness = clampf(float(surface.get("roughness", 1.0)), 0.05, 1.0)
	source.metallic_specular = clampf(float(surface.get("specular", 0.0)), 0.0, 1.0)
	var lighting := get_tree().get_first_node_in_group("underground_lighting")
	var material: Material = lighting.make_material(source, true) if lighting != null else source
	_surface_materials[item_key] = material
	return material


func _apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material(child, material)


## Top face of the first solid block at or below the drop position.
## Scans all the way down to bedrock (2026-08-06 bugfix): the old fixed
## REST_SCAN_DEPTH=8 cap silently gave up on any column whose straight-down
## air ran deeper than 8 blocks before hitting a floor — common when mining
## a wall/ceiling block of a deep or diagonal tunnel, where the actual floor
## is well below the mined block but not directly beneath it within 8 cells.
## Past that cap the function fell back to `return block.y`, leaving the
## drop hovering at its original mined height with nothing under it —
## reported as "floating blocks that were recently mined". A plain downward
## scan to bedrock is still O(~100) dictionary/array lookups worst case, and
## runs on spawn/restore or a relevant support change, never every frame.
func _rest_y(block: Vector3i) -> int:
	var y := block.y - 1
	while y > WorldGenerator.BEDROCK_MAX_Y:
		if BlockRegistry.is_solid(_block_id(block.x, y, block.z)):
			return y + 1
		y -= 1
	# Nothing solid found all the way to bedrock (should not happen — Hard
	# Rule 1 forbids mining bedrock itself) — rest one cell above it as a
	# guaranteed-solid last resort rather than floating.
	return WorldGenerator.BEDROCK_MAX_Y + 1


func _block_id(wx: int, wy: int, wz: int) -> int:
	if WorldData.chunk_exists(wx >> 4, wy >> 4, wz >> 4):
		return WorldData.get_block(wx, wy, wz)
	return WorldData.get_live_block(wx, wy, wz)


func _model_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	if scene == null and not _missing_models.has(path):
		_missing_models[path] = true
		push_warning("ItemDropManager: model missing at '%s' — using fallback cube." % path)
	_scene_cache[path] = scene
	return scene


func _ensure_defs() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	var file := FileAccess.open(RESOURCES_PATH, FileAccess.READ)
	if file == null:
		push_error("ItemDropManager: cannot open %s." % RESOURCES_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ItemDropManager: JSON parse error in %s — %s" % [RESOURCES_PATH, json.get_error_message()])
		return
	var root: Dictionary = json.data
	for raw_key: String in root:
		if raw_key.begins_with("__"):
			continue
		var def = root[raw_key]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		_defs[raw_key] = def
	print("ItemDropManager: loaded %d item definitions." % _defs.size())


# ── Slice culling (doc 11 Phase 5 — same hook as flora and dwarves) ──────────

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for child in get_children():
		if child is Node3D and child.has_meta("base_y"):
			(child as Node3D).visible = int(child.get_meta("base_y")) <= _slice_y
