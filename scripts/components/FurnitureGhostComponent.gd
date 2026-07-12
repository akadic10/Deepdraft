class_name FurnitureGhostComponent
extends RefCounted

## A placed-but-unbuilt furniture designation (doc 19 §3.2–3.3) — the SH
## ghost form translated: a translucent placed-form marker that persists in
## the world as a standing request until a dwarf fetches the matching item
## and installs it.
##
## Phase 3 made this a WORK SOURCE (the fifth lease family): the ghost posts
## ONE FETCH_BUILD lease, and only while a matching item is AVAILABLE — loose
## and unreserved, or stored in colony storage (type-matched, SH parity: any
## item of the URI satisfies the ghost). The fetching dwarf pulls via
## reserve_fetch (loose first, else a storage withdraw), carries the item to
## the ghost's stand cell, works the build timer, and complete_build hands
## off to the controller's shared _install path.
##
## Ghosts are NON-SOLID (SH parity): no PlacedEntityRegistry registration,
## no nav impact — nav changes only when the piece is actually installed.
## Owned by FurniturePlacementController (the zone/mining ownership shape).

var ghost_id: int = -1
var furniture_key: String = ""      # base:furniture:* (namespaced — Hard Rule 3)
var item_key: String = ""           # the resources.json item form to fetch
var def: Dictionary = {}            # parsed data/furniture/*.json definition
var origin_cell: Vector3i = Vector3i(-1, -1, -1)   # footprint min-corner FLOOR cell
var yaw_steps: int = 0              # 0..3 — 90° each (R key)
var node: Node3D = null             # translucent in-world marker (controller-owned)

# ── Work-source state (doc 19 Phase 3 — injected by the controller) ───────────
var source_id: int = -1             # TaskManager.allocate_source_id()
var drop_manager: Node3D = null     # ItemDropManager (guard is_instance_valid)
var install_callback: Callable = Callable()   # (ghost) -> controller install path

var _lease_id: int = -1             # the ONE FETCH_BUILD lease, -1 = none
var _fetches: Dictionary = {}       # dwarf_id -> Node3D (reserved item, pre-pickup)


func setup(id: int, key: String, definition: Dictionary, cell: Vector3i, yaw: int) -> void:
	ghost_id = id
	furniture_key = key
	def = definition
	item_key = String(definition.get("item_key", ""))
	origin_cell = cell
	yaw_steps = yaw


## Floor cells covered by the footprint (v1 pieces are all 1×1; width/depth
## swap under odd yaw steps so the math stays correct for future 2×1 pieces).
func footprint_cells() -> Array[Vector3i]:
	var fp: Dictionary = def.get("footprint", {})
	var w := int(fp.get("width", 1))
	var d := int(fp.get("depth", 1))
	if yaw_steps % 2 == 1:
		var t := w
		w = d
		d = t
	var cells: Array[Vector3i] = []
	for dx: int in range(w):
		for dz: int in range(d):
			cells.append(origin_cell + Vector3i(dx, 0, dz))
	return cells


func display_name() -> String:
	return String(def.get("display_name", furniture_key))


# ── Work source (doc 19 §3.3) ─────────────────────────────────────────────────

## A matching item exists somewhere the fetch can reach it: loose and
## unreserved, or stored in colony storage (aggregates).
func item_available() -> bool:
	if StockpileManager.get_total(item_key) > 0:
		return true
	if drop_manager == null or not is_instance_valid(drop_manager):
		return false
	return drop_manager.call("nearest_loose_of_key", item_key, origin_cell, {}) != null


## Posts/retires the single FETCH_BUILD lease. Called by the controller on
## wake events (drop spawned, stockpile changed, ghost placed) — never per
## frame (doc 16 §2.5 discipline).
func update_lease() -> void:
	if source_id < 0:
		return
	if _lease_id < 0 and item_available():
		_lease_id = int(TaskManager.add_task(
			Task.Type.FETCH_BUILD, origin_cell, { "ghost_id": ghost_id }, source_id))


func has_lease() -> bool:
	return _lease_id >= 0


## The lease left the system FOR GOOD (completed / cancelled / failed) —
## NOT on releases (a released lease returns to PENDING and stays counted).
func on_task_gone(task_id: int, dwarf_id: int) -> void:
	if task_id == _lease_id:
		_lease_id = -1
	if dwarf_id >= 0:
		cancel_fetch(dwarf_id)


## Scheduler probe / builder stand target: the nearest walkable cell BESIDE
## the footprint — NEVER the footprint itself. DEFECT FIX (Alen, 2026-07-11):
## the first cut returned origin_cell; the builder stood ON the ghost, the
## install registered occupancy around them, and the trapped dwarf's every
## subsequent probe failed — each install silently ate a worker until the
## whole crew stood frozen inside furniture. Build from beside, like mining.
func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for cell: Vector3i in footprint_cells():
		for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var stand := cell + offset
			if _cell_in_footprint(stand):
				continue
			if not NavGrid.is_walkable(stand):
				continue
			var d := stand - dwarf_cell
			var dist := absi(d.x) + absi(d.y) + absi(d.z)
			if dist < best_dist:
				best = stand
				best_dist = dist
	return best


func _cell_in_footprint(cell: Vector3i) -> bool:
	for fp_cell: Vector3i in footprint_cells():
		if fp_cell == cell:
			return true
	return false


## Step 1 of the fetch (doc 19 §3.3): claim the nearest matching item —
## loose first, else withdrawn from the nearest storage. {} = nothing
## available (the lease completes early and re-posts on the next wake).
func reserve_fetch(dwarf_id: int, dwarf_cell: Vector3i) -> Dictionary:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return {}
	var item: Node3D = drop_manager.call("nearest_loose_of_key", item_key, dwarf_cell, {})
	if item != null:
		if not bool(drop_manager.call("reserve", item, dwarf_id)):
			item = null
	if item == null:
		item = StockpileManager.withdraw_item(item_key, dwarf_cell, dwarf_id)
	if item == null:
		return {}
	_fetches[dwarf_id] = item
	var item_def: Dictionary = drop_manager.call("get_item_def", item_key)
	return {
		"item": item,
		"heavy": String(item_def.get("weight_class", "light")) == "heavy",
	}


## Release protocol: frees the item reservation (owner-guarded — doc 18
## spam-robustness pass). Safe to call twice; a carried item is the dwarf's
## to drop at its feet (Hard Rule 12), not ours to unreserve.
func cancel_fetch(dwarf_id: int) -> void:
	if not _fetches.has(dwarf_id):
		return
	var item: Node3D = _fetches[dwarf_id]
	_fetches.erase(dwarf_id)
	if item != null and is_instance_valid(item) \
			and drop_manager != null and is_instance_valid(drop_manager):
		drop_manager.call("unreserve", item, dwarf_id)


## The dwarf picked the item up — it left the loose index; our reservation
## bookkeeping for it is done.
func notify_picked_up(dwarf_id: int) -> void:
	_fetches.erase(dwarf_id)


## Step 4: the build swing finished — hand off to the controller's shared
## install path (the same _install the DEV button uses).
func complete_build(_dwarf_id: int) -> void:
	if install_callback.is_valid():
		install_callback.call(self)
