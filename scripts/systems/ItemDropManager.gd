class_name ItemDropManager
extends Node3D

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
## VISUALS (doc 61 §5.7): item GLBs are authored at 8 vox/block with the 0.125
## scale baked into vertex positions — instanced at scale 1.0 with the
## project-standard vertex-colour material (lit per-pixel, double-sided).
##
## SLICE RULE (doc 11 Phase 5): drops obey the slice like flora and dwarves —
## hidden when their block is above the cut.

@export var slice_controller_path: NodePath

const RESOURCES_PATH := "res://data/entities/items/resources.json"
const SLICE_OFF_Y := 127
const REST_SCAN_DEPTH := 8   # blocks scanned downward for a resting floor

## A new loose item entered the world (spawned or dropped by an interrupted
## hauler). StockpileManager wakes zone lease posting on this (doc 18 §2.2).
signal drop_spawned(item_key: String)

var _defs: Dictionary = {}          # item key (String) -> def Dictionary
var _defs_loaded: bool = false
var _scene_cache: Dictionary = {}   # model path -> PackedScene (null cached as absent)
var _material: StandardMaterial3D = null
var _slice_y: int = SLICE_OFF_Y
var _drop_count: int = 0
var _missing_models: Dictionary = {}   # path -> true (warn once per model)

# ── Loose-item index (doc 18 Phase 2) ─────────────────────────────────────────
var _loose: Dictionary = {}         # Node3D -> item_key (String)
var _reserved: Dictionary = {}      # Node3D -> dwarf_id (int)


func _ready() -> void:
	add_to_group("item_drop_manager")
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic = 0.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


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
	var scene := _model_scene(String(def.get("model", "")))
	var rest_y := _rest_y(block)
	for i in range(count):
		var node := _build_drop_node(item_key, scene)
		var jitter := Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
		node.position = Vector3(float(block.x) + 0.5, float(rest_y), float(block.z) + 0.5) + jitter
		node.rotation.y = randf_range(0.0, TAU)
		node.set_meta("base_y", rest_y)
		node.set_meta("item_key", item_key)
		# Same rule as DwarfAgent.apply_slice: floor(position.y) <= slice_y.
		node.visible = rest_y <= _slice_y
		add_child(node)
		_drop_count += 1
		_loose[node] = item_key
		drop_spawned.emit(item_key)


func get_stats() -> Dictionary:
	return { "drops": _drop_count, "loose": _loose.size(), "reserved": _reserved.size() }


# ── Loose-item index API (doc 18 §2.1) ────────────────────────────────────────

## Public item-definition accessor (Registry Pattern: this node owns
## resources.json; everyone else queries through here). {} if unknown.
func get_item_def(item_key: String) -> Dictionary:
	_ensure_defs()
	return _defs.get(item_key, {})


## Nearest unreserved loose item whose material_tags overlap accepted_tags,
## by flat Manhattan distance from `from`. `exclude` is a per-dwarf blacklist
## (Node -> true) of items that failed pathing this round. Null if none.
func nearest_loose(accepted_tags: Array, from: Vector3i, exclude: Dictionary = {}) -> Node3D:
	_ensure_defs()
	var best: Node3D = null
	var best_dist: int = 0x7FFFFFFF
	for node: Node3D in _loose:
		if _reserved.has(node) or exclude.has(node) or not is_instance_valid(node):
			continue
		var def: Dictionary = _defs.get(_loose[node], {})
		var tags: Array = def.get("material_tags", [])
		var accepted := false
		for tag: String in accepted_tags:
			if tags.has(tag):
				accepted = true
				break
		if not accepted:
			continue
		var cell := item_floor_cell(node)
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


## Nearest unreserved loose item of EXACTLY this key (type-matched fetch,
## doc 19 §3.3 — SH parity: any item of the URI satisfies a ghost).
func nearest_loose_of_key(item_key: String, from: Vector3i, exclude: Dictionary = {}) -> Node3D:
	var best: Node3D = null
	var best_dist: int = 0x7FFFFFFF
	for node: Node3D in _loose:
		if _reserved.has(node) or exclude.has(node) or not is_instance_valid(node):
			continue
		if String(_loose[node]) != item_key:
			continue
		var cell := item_floor_cell(node)
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y) + absi(cell.z - from.z)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


## Unreserved loose accepted items within `radius` blocks (flat Chebyshev) of
## `center`, nearest first, capped at `limit`. The pouch bundle search (doc 18
## pouch — SH NearbyItemSearch equivalent). `exclude` = blacklist + main item.
func loose_near(accepted_tags: Array, center: Vector3i, radius: int, limit: int, exclude: Dictionary = {}) -> Array[Node3D]:
	_ensure_defs()
	var found: Array = []   # [dist, node] pairs
	for node: Node3D in _loose:
		if _reserved.has(node) or exclude.has(node) or not is_instance_valid(node):
			continue
		var cell := item_floor_cell(node)
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
		if result.size() >= limit:
			break
	return result


## Unreserved loose items whose tags overlap accepted_tags, capped at `cap`
## (lease posting only needs "are there at least N?", doc 18 §2.2).
func count_loose(accepted_tags: Array, cap: int) -> int:
	_ensure_defs()
	var found: int = 0
	for node: Node3D in _loose:
		if _reserved.has(node) or not is_instance_valid(node):
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


func reserve(node: Node3D, dwarf_id: int) -> bool:
	if not _loose.has(node) or _reserved.has(node):
		return false
	_reserved[node] = dwarf_id
	return true


## Owner-guarded (doc 18 spam-robustness pass): pass the reserving dwarf_id so
## a stale unreserve (an interrupted hauler cancelling a bundle whose skipped
## items were re-reserved by another hauler in the meantime) cannot clobber
## the new owner's reservation. -1 = unconditional (trusted callers only).
func unreserve(node: Node3D, dwarf_id: int = -1) -> void:
	if dwarf_id >= 0 and int(_reserved.get(node, -1)) != dwarf_id:
		return
	_reserved.erase(node)


## Pickup: removes the node from the index and this manager; the caller
## (the hauling dwarf) reparents it as its carried visual. Returns the
## item key, or "" if the node was not a loose item.
func take(node: Node3D) -> String:
	if not _loose.has(node):
		return ""
	var key: String = _loose[node]
	_loose.erase(node)
	_reserved.erase(node)
	remove_child(node)
	return key


## Deposit: re-adopts a carried node as a STORED item centred on a stockpile
## floor cell. Stored nodes are NOT in the loose index — the zone's
## cell_stacks own the counts (doc 18 §2.4: storage is physical).
func place_stored(node: Node3D, cell: Vector3i) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	node.position = Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	node.rotation = Vector3.ZERO
	node.set_meta("base_y", cell.y + 1)
	node.set_meta("stored", true)
	node.visible = cell.y + 1 <= _slice_y


## Release protocol (doc 18 §2.3 step 5 / Hard Rule 12): an interrupted
## hauler drops its carried node at its feet as a normal loose item.
## Position jitter matches spawn_drop: a full pouch dropped on one cell must
## read as N items, not one (the WYSIWYG rule that drove one-item-per-tile).
func drop_loose(node: Node3D, floor_cell: Vector3i) -> void:
	var key := String(node.get_meta("item_key", ""))
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	var jitter := Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
	node.position = Vector3(float(floor_cell.x) + 0.5, float(floor_cell.y + 1), float(floor_cell.z) + 0.5) + jitter
	node.set_meta("base_y", floor_cell.y + 1)
	node.set_meta("stored", false)
	node.visible = floor_cell.y + 1 <= _slice_y
	_loose[node] = key
	drop_spawned.emit(key)


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


## Zone removal: stored nodes on the given cells become loose again, and
## stacked counts beyond the one visible node respawn as fresh drops so no
## items are lost (doc 18 §2.4 one-node-per-stack rule).
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
			drop_spawned.emit(key)
			count -= 1
		if count > 0:
			spawn_drop(key, count, Vector3i(cell.x, cell.y + 1, cell.z))


# ── Internals ─────────────────────────────────────────────────────────────────

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
	_apply_material(node)
	return node


func _apply_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _material
	for child in node.get_children():
		_apply_material(child)


## Top face of the first solid block at or below the drop position.
func _rest_y(block: Vector3i) -> int:
	for k in range(1, REST_SCAN_DEPTH + 1):
		var y := block.y - k
		if y < 0:
			break
		if BlockRegistry.is_solid(_block_id(block.x, y, block.z)):
			return y + 1
	return block.y


func _block_id(wx: int, wy: int, wz: int) -> int:
	@warning_ignore("integer_division")
	if WorldData.chunk_exists(wx / 16, wy / 16, wz / 16):
		return WorldData.get_block(wx, wy, wz)
	return WorldGenerator.get_generated_block_id(wx, wy, wz)


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
