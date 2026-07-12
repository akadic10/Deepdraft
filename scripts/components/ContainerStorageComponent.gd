class_name ContainerStorageComponent
extends StorageComponent

## Container storage (doc 19 §3.5) — the density face of the storage
## contract: capacity SLOTS behind one piece of installed furniture (barrel
## 8, chest 24, shelf 8). Deposit tokens are int slot tickets; counts live
## in a flat inventory Dictionary (item_key -> count, flat item count — SH
## parity, decision 6).
##
## VISUALS (the WYSIWYG split, doc 19 §3.0.5): render_contents false (barrel,
## chest) ABSORBS the deposited node — the window shows counts; true (shelf)
## renders items on the def's anchor points — Phase 5 (v1 absorbs with a
## build-log note so hauling works today).
##
## Owned by FurniturePlacementController (attached to the piece's
## InstalledFurnitureComponent); registered with StockpileManager like a
## zone. Withdraw spawns the item back into the world pre-reserved for the
## fetching dwarf (containers hold counts, not nodes).

var capacity: int = 8
var render_contents: bool = false
var inventory: Dictionary = {}       # item_key (String) -> count (int)
var cells: Array[Vector3i] = []      # the installed piece's footprint floor cells
var suspended: bool = false          # 📤 flagged — stop accepting (doc 19 §3.4)

# ── Anchor rendering (doc 19 Phase 5 — SH ATTITEM parity) ─────────────────────
var display_parent: Node3D = null    # the installed piece's visual node
var anchors: Array = []              # local block offsets from data/furniture JSON
var anchor_scale: float = 0.5        # SH sca [0.5,0.5,0.5] (2026-07-11 decision 5)

var _reserved_slots: int = 0
var _anchor_slots: Array = []        # per-anchor: null | [node: Node3D, item_key: String]


func setup_container(def: Dictionary, footprint_cells: Array[Vector3i]) -> void:
	var storage: Dictionary = def.get("storage", {})
	capacity = int(storage.get("capacity", 8))
	render_contents = bool(storage.get("render_contents", false))
	anchors = storage.get("anchors", [])
	anchor_scale = float(storage.get("anchor_scale", 0.5))
	cells = footprint_cells
	filter_tags = StockpileZoneComponent.DEFAULT_FILTER_TAGS.duplicate()
	_anchor_slots.resize(anchors.size())


func stored_count() -> int:
	var total: int = 0
	for key: String in inventory:
		total += int(inventory[key])
	return total


# ── Storage contract (doc 19 §3.5 — the abstract surface) ─────────────────────

func _has_any_room() -> bool:
	if suspended:
		return false
	return stored_count() + _reserved_slots < capacity


func _reserve_deposit(_item_key: String, _near: Vector3i, _dwarf_id: int) -> Variant:
	if not _has_any_room():
		return null
	_reserved_slots += 1
	return _reserved_slots   # int ticket (never null; value is opaque)


func _release_deposit(_token: Variant) -> void:
	_reserved_slots = maxi(_reserved_slots - 1, 0)


func _commit_one(_token: Variant, item_key: String) -> void:
	_reserved_slots = maxi(_reserved_slots - 1, 0)
	inventory[item_key] = int(inventory.get(item_key, 0)) + 1


func _deposit_walk_target(_first_token: Variant) -> Vector3i:
	return nearest_stand_target(Vector3i.ZERO)


## Barrel/chest ABSORB the node; the shelf snaps it onto a free anchor
## (doc 19 Phase 5 — SH ATTITEM parity: scale 0.5, varied yaw per anchor).
## Anchors are footprint-local block coords (origin = bottom-front-left);
## as children of the rotated piece node they follow its yaw for free, and
## slice culling rides the parent's visibility.
func _place_visual(node: Node3D, _token: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not render_contents or display_parent == null or not is_instance_valid(display_parent):
		node.queue_free()
		return
	var slot := _free_anchor_slot()
	if slot < 0:
		node.queue_free()   # capacity > anchors would land here — WYSIWYG says never
		return
	var key := String(node.get_meta("item_key", ""))
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	display_parent.add_child(node)
	var fp_w := 1.0
	var fp_d := 1.0
	var offset: Array = anchors[slot]
	node.position = Vector3(
		float(offset[0]) - fp_w * 0.5,
		float(offset[1]),
		float(offset[2]) - fp_d * 0.5)
	node.scale = Vector3.ONE * anchor_scale
	# Varied per-anchor yaw (SH's scattered hand-placed look) — deterministic.
	node.rotation = Vector3(0.0, float(slot * 2654435761 % 628) / 100.0, 0.0)
	node.visible = true
	_anchor_slots[slot] = [node, key]


func _free_anchor_slot() -> int:
	for i: int in range(_anchor_slots.size()):
		if _anchor_slots[i] == null:
			return i
	return -1


## Frees one anchored node of `item_key` (shelf withdraw/dump bookkeeping).
func _pop_anchor_node(item_key: String) -> bool:
	for i: int in range(_anchor_slots.size()):
		var entry: Variant = _anchor_slots[i]
		if entry != null and String((entry as Array)[1]) == item_key:
			var node: Node3D = (entry as Array)[0]
			if node != null and is_instance_valid(node):
				node.queue_free()
			_anchor_slots[i] = null
			return true
	return false


## Nearest walkable cell bordering the footprint (the footprint itself is
## occupied — the InstalledFurnitureComponent pattern).
func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in cells:
		for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var stand := cell + offset
			if not NavGrid.is_walkable(stand):
				continue
			var d := stand - dwarf_cell
			var dist := absi(d.x) + absi(d.y) + absi(d.z)
			if dist < best_dist:
				best = stand
				best_dist = dist
	return best


# ── Withdraw (doc 19 §3.3 fetch path) ─────────────────────────────────────────

## Containers hold counts, not nodes: withdrawing spawns the item back into
## the world at the stand cell, pre-reserved for the fetching dwarf.
func withdraw_nearest(item_key: String, _near: Vector3i, dwarf_id: int) -> Node3D:
	if int(inventory.get(item_key, 0)) <= 0:
		return null
	if drop_manager == null or not is_instance_valid(drop_manager):
		return null
	var stand := nearest_stand_target(Vector3i.ZERO)
	if stand.x < 0:
		return null
	var node: Node3D = drop_manager.call("spawn_reserved", item_key, stand, dwarf_id)
	if node == null:
		return null
	if render_contents:
		_pop_anchor_node(item_key)   # the shelf visibly loses the piece
	inventory[item_key] = int(inventory[item_key]) - 1
	if int(inventory[item_key]) <= 0:
		inventory.erase(item_key)
	if changed_callback.is_valid():
		changed_callback.call(item_key, -1)
	return node


## Uninstall teardown (doc 19 §3.4 step 2): every stored item re-enters the
## world as an ordinary loose drop at the container's cell. Returns the
## dumped total (build-log verification).
func dump_contents(at_cell: Vector3i) -> int:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return 0
	# Shelf: clear the anchored visuals first (counts respawn as drops below).
	for i: int in range(_anchor_slots.size()):
		var entry: Variant = _anchor_slots[i]
		if entry != null:
			var node: Node3D = (entry as Array)[0]
			if node != null and is_instance_valid(node):
				node.queue_free()
			_anchor_slots[i] = null
	var dumped := 0
	for item_key: String in inventory.keys():
		var count := int(inventory[item_key])
		if count > 0:
			drop_manager.call("spawn_drop", item_key, count, Vector3i(at_cell.x, at_cell.y + 1, at_cell.z))
			if changed_callback.is_valid():
				changed_callback.call(item_key, -count)
			dumped += count
	inventory.clear()
	return dumped
