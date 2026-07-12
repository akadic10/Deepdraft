class_name InstalledFurnitureComponent
extends RefCounted

## An installed furniture piece (doc 19 §3.4) — occupancy-registered, solid,
## and a WORK SOURCE for its own removal: the 📤 flag is a TOGGLE (SH
## should_restock parity) that posts ONE UNINSTALL lease; clicking 📤 again
## clears flag and lease, leaving the piece untouched. The uninstalling
## dwarf walks to the stand cell, works the timer, and complete_uninstall
## hands off to the controller's teardown (contents dumped loose, occupancy
## freed, the packed item-form drop spawned — everything re-enters ordinary
## hauling).
##
## Phase 4 attaches the ContainerStorageComponent to pieces whose def
## carries a `storage` block; this component stays the placement/lifecycle
## half. Owned by FurniturePlacementController.

var installed_id: int = -1
var furniture_key: String = ""
var item_key: String = ""
var def: Dictionary = {}
var origin_cell: Vector3i = Vector3i(-1, -1, -1)
var yaw_steps: int = 0
var node: Node3D = null              # solid in-world visual (controller-owned)
var occupancy_ids: Array[int] = []   # PlacedEntityRegistry handles
var cells: Array[Vector3i] = []      # footprint floor cells

# ── Work-source state (doc 19 §3.4 — injected by the controller) ──────────────
var source_id: int = -1
var flagged_uninstall: bool = false
var uninstall_callback: Callable = Callable()   # (component) -> controller teardown

var _lease_id: int = -1              # the ONE UNINSTALL lease, -1 = none


func setup(id: int, key: String, definition: Dictionary, cell: Vector3i, yaw: int) -> void:
	installed_id = id
	furniture_key = key
	def = definition
	item_key = String(definition.get("item_key", ""))
	origin_cell = cell
	yaw_steps = yaw


func display_name() -> String:
	return String(def.get("display_name", furniture_key))


## 📤 toggle (SH parity). Posting/cancelling the lease happens here — the
## flag and the lease can never disagree.
func set_uninstall(flag: bool) -> void:
	if flag == flagged_uninstall:
		return
	flagged_uninstall = flag
	if flag:
		if _lease_id < 0 and source_id >= 0:
			_lease_id = int(TaskManager.add_task(
				Task.Type.UNINSTALL, origin_cell, { "installed_id": installed_id }, source_id))
	else:
		if _lease_id >= 0:
			TaskManager.cancel_task(_lease_id)
			_lease_id = -1


func on_task_gone(task_id: int, _dwarf_id: int) -> void:
	if task_id == _lease_id:
		_lease_id = -1
		# Lease died without completing (cancel/fail while flagged): re-post
		# so the flag keeps meaning "will be uninstalled" (toggle clears it).
		if flagged_uninstall and source_id >= 0:
			_lease_id = int(TaskManager.add_task(
				Task.Type.UNINSTALL, origin_cell, { "installed_id": installed_id }, source_id))


## Scheduler probe target / dwarf walk target: the nearest walkable cell
## bordering the footprint (the footprint itself is occupied once installed).
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


## The uninstall swing finished — hand off to the controller's teardown.
func complete_uninstall(_dwarf_id: int) -> void:
	if uninstall_callback.is_valid():
		uninstall_callback.call(self)
