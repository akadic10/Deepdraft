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
##
## ITEM CLAIMS (2026-08-07, Alen playtest — the HAUL/FETCH_BUILD item race):
## task priority (FETCH_BUILD 45 > HAUL 40) orders ASSIGNMENT, but the
## physical item had none — a stockpile hauler could pouch the last matching
## loose item, and while it rode the pouch item_available() was false, so the
## ghost had NO lease and idle dwarves stood around until the deposit wake
## (then walked to the zone and all the way back). SH restock parity: an item
## pending placement is never restocked. The ghost now CLAIMS the nearest
## matching loose item the moment one exists (wake-driven, like the lease):
## a claim is an ItemDropManager reservation under claim_owner_id(), so every
## hauler scan (unreserved-only) skips it. reserve_fetch hands the claim to
## the fetching dwarf; cancel_fetch re-claims on release; the controller
## releases the claim on ghost teardown. Items already inside a pouch when
## the ghost is placed remain the residual (unavoidable) delay: they become
## claimable only after the hauler deposits or drops them.

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
var _claim: Node3D = null           # ghost-held item claim (see header) — runtime only, never saved


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

## Owner id for the ghost's item claim in ItemDropManager's reservation
## table. POSITIVE and far outside the dwarf-id range, so unreserve()'s
## owner guard stays effective (a negative id would read as "unconditional"
## there). source_id comes from TaskManager.allocate_source_id() (>= 10M),
## so claim owners live at >= 1_010_000_000 — no dwarf id ever collides.
func claim_owner_id() -> int:
	return 1_000_000_000 + source_id


func _claim_valid() -> bool:
	return _claim != null and is_instance_valid(_claim)


## A matching item exists somewhere the fetch can reach it: claimed by this
## ghost, loose and unreserved, or stored in colony storage (aggregates).
func item_available() -> bool:
	if _claim_valid():
		return true
	if StockpileManager.get_total(item_key) > 0:
		return true
	if drop_manager == null or not is_instance_valid(drop_manager):
		return false
	return drop_manager.call("nearest_loose_of_key", item_key, origin_cell, {}) != null


## Posts/retires the single FETCH_BUILD lease, and keeps the item claim
## current (see header — the claim is what stops haulers pouching the item
## out from under a pending lease). Called by the controller on wake events
## (drop spawned, stockpile changed, ghost placed) — never per frame
## (doc 16 §2.5 discipline).
func update_lease() -> void:
	if source_id < 0:
		return
	_ensure_claim()
	if _lease_id < 0 and item_available():
		_lease_id = int(TaskManager.add_task(
			Task.Type.FETCH_BUILD, origin_cell, { "ghost_id": ghost_id }, source_id))


## Claim the nearest matching loose item if we hold none and no fetching
## dwarf already owns one for this ghost. Claimed = reserved under
## claim_owner_id(), invisible to every unreserved-only scan (haul pouches,
## other ghosts' claims and fetches).
func _ensure_claim() -> void:
	if not _fetches.is_empty():
		return                        # a dwarf already holds an item for this ghost
	if _claim_valid():
		return
	_claim = null
	if drop_manager == null or not is_instance_valid(drop_manager):
		return
	var item: Node3D = drop_manager.call("nearest_loose_of_key", item_key, origin_cell, {})
	if item != null and bool(drop_manager.call("reserve", item, claim_owner_id())):
		_claim = item


## Frees the ghost's item claim (owner-guarded). Controller calls this on
## ghost teardown (cancel / build-complete); safe to call with no claim.
func release_claim() -> void:
	if _claim != null and is_instance_valid(_claim) \
			and drop_manager != null and is_instance_valid(drop_manager):
		drop_manager.call("unreserve", _claim, claim_owner_id())
	_claim = null


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


## Step 1 of the fetch (doc 19 §3.3): hand over the ghost's claim if it
## holds one (claimed items are reserved, so the unreserved-only scan below
## would never find them) — else the nearest matching loose item, else a
## storage withdraw. {} = nothing available (the lease completes early and
## re-posts on the next wake).
func reserve_fetch(dwarf_id: int, dwarf_cell: Vector3i) -> Dictionary:
	if drop_manager == null or not is_instance_valid(drop_manager):
		return {}
	var item: Node3D = null
	if _claim_valid():
		# Transfer the claim to the fetching dwarf (owner-guarded swap).
		item = _claim
		_claim = null
		drop_manager.call("unreserve", item, claim_owner_id())
		if not bool(drop_manager.call("reserve", item, dwarf_id)):
			item = null
	if item == null:
		item = drop_manager.call("nearest_loose_of_key", item_key, dwarf_cell, {})
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
## to drop at its feet (Hard Rule 12), not ours to unreserve. The freed item
## is immediately RE-CLAIMED for the ghost so a hauler cannot poach it in
## the gap before the next lease wake.
func cancel_fetch(dwarf_id: int) -> void:
	if not _fetches.has(dwarf_id):
		return
	var item: Node3D = _fetches[dwarf_id]
	_fetches.erase(dwarf_id)
	if item != null and is_instance_valid(item) \
			and drop_manager != null and is_instance_valid(drop_manager):
		drop_manager.call("unreserve", item, dwarf_id)
		if not _claim_valid() and bool(drop_manager.call("reserve", item, claim_owner_id())):
			_claim = item


## The dwarf picked the item up — it left the loose index; our reservation
## bookkeeping for it is done.
func notify_picked_up(dwarf_id: int) -> void:
	_fetches.erase(dwarf_id)


## Step 4: the build swing finished — hand off to the controller's shared
## install path (the same _install the DEV button uses).
func complete_build(_dwarf_id: int) -> void:
	if install_callback.is_valid():
		install_callback.call(self)
