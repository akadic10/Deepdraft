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
## Owned by FurniturePlacementController.

## A workshop's batch is drawn as parts of its node (the controller's show_batch): the unfinished
## batch, and the finished one where the workshop shows that apart (the smelter's bar in its mould).
const BATCH_PART := "Batch"
const BATCH_DONE_PART := "BatchDone"

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
var uninstall_callback: Callable = Callable()   # (component, worker_id) -> owner teardown

var material_id := ""
var idle_seat_owner := -1 # Transient exclusive rest use; never serialized.
var idle_seat_yaw_steps := -1 # A round stool's occupant can face independently.
var dining_claims: Dictionary = {} # Transient table access positions, worker IDs.
var sleep_owner := -1 # Transient bed use; released on wake/removal and rebuilt on load.
var assigned_dwarf_id := -1 # Persistent ownership, separate from the current sleeper.
var fire_log := "" # A nightly fire's burning log (doc 279): its item key, "" while cold. Saved.
var storage: StorageComponent = null # A container's store (doc 294, FurnitureStorage), else null.
var fire_log_material := ""

var _lease_id: int = -1              # the ONE UNINSTALL lease, -1 = none


func setup(id: int, key: String, definition: Dictionary, cell: Vector3i, yaw: int) -> void:
	installed_id = id
	furniture_key = key
	def = definition
	item_key = String(definition.get("item_key", ""))
	origin_cell = cell
	yaw_steps = yaw


func display_name() -> String:
	return CraftMaterials.product_name(String(def.get("display_name", furniture_key)), material_id)


## 📤 toggle (SH parity). Posting/cancelling the lease happens here — the
## flag and the lease can never disagree.
func set_uninstall(flag: bool) -> void:
	if flag == flagged_uninstall:
		return
	flagged_uninstall = flag
	if storage != null:
		# Marked for uninstall, a container takes nothing more and its haulers stand down (doc 294).
		storage.set("suspended", flag)
		if flag: TaskManager.cancel_source_tasks(storage.source_id)
		StockpileManager.storage_rules_changed()
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


# WorkSourceTable routing contract. Releases keep the pending lease as it is.
func work_task_gone(task: Task, dwarf_id: int) -> void:
	on_task_gone(task.id, dwarf_id)


func work_task_released(_task: Task, _dwarf_id: int) -> void:
	pass


func work_source_retired() -> void:
	pass


## Scheduler probe target / dwarf walk target: the nearest walkable cell
## bordering the footprint (the footprint itself is occupied once installed).
## `batch` stands at the cell a workshop's batches are worked at (work_cells).
func nearest_stand_target(dwarf_cell: Vector3i, batch := false) -> Vector3i:
	if def.has("grid_fence"): return preload("GridFence.gd").nearest_stand(def,origin_cell,yaw_steps,dwarf_cell)
	if String(def.get("placement", "floor")) == "wall":
		return preload("res://scripts/components/WallFurnitureMount.gd").nearest_stand(def,origin_cell,yaw_steps,dwarf_cell)
	var best := Vector3i(-1, -1, -1)
	var best_dist: int = 0x7FFFFFFF
	for stand: Vector3i in work_stands(batch):
		var d := stand - dwarf_cell
		var dist := absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best = stand
			best_dist = dist
	return best


## The floor cells a craft is worked from: the free cells beside its work cells. A batch whose
## workshop has a fire hole is worked from the cell before it alone, whenever a dwarf can stand
## there (the basic smelter's fire has to be blown on; doc 300).
func work_stands(batch := false) -> Array[Vector3i]:
	var stands: Array[Vector3i] = []
	if batch:
		var front := fire_stand()
		if front.x >= 0:
			stands.append(front)
			return stands
	var spots := work_cells(batch)
	var narrowed := spots.size() < cells.size()   # a spot's neighbour may be the piece's other cell
	for cell: Vector3i in spots:
		for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var stand := cell + offset
			if (narrowed and stand in cells) or not NavGrid.is_walkable(stand) or stand in stands: continue
			stands.append(stand)
	return stands


## Whether its unfinished batch is on show: the fish hung on a drying rack, the basic smelter's
## coals from when the whole charge is in the pot until the copper has set (doc 300).
func batch_showing() -> bool:
	if not is_instance_valid(node): return false
	var part := node.get_node_or_null(BATCH_PART) as Node3D
	return part != null and part.visible


## A workshop's fire hole (`batch_fire_hole`, a point of its model in blocks from the model's
## origin): where the fire under its batch is blown on. The basic smelter's is in its boulder's foot.
func fire_hole() -> Vector3:
	var at: Array = def.get("batch_fire_hole", [0, 0, 0])
	return node.to_global(Vector3(float(at[0]), float(at[1]), float(at[2])))


## The floor cell before the fire hole: a batch is worked from there whenever a dwarf can stand on
## it, as its fire has to be blown on. (-1, -1, -1) when the workshop has no fire hole or the cell
## is not free; the batch is then worked from any side of its spot.
func fire_stand() -> Vector3i:
	var none := Vector3i(-1, -1, -1)
	if not def.has("batch_fire_hole") or not is_instance_valid(node): return none
	var spot: Vector3i = work_cells(true)[0]
	var out := fire_hole() - (Vector3(spot) + Vector3(.5, 0, .5))
	var stand := spot + (Vector3i(signi(roundi(out.x * 2.0)), 0, 0) if absf(out.x) > absf(out.z) else Vector3i(0, 0, signi(roundi(out.z * 2.0))))
	return stand if stand != spot and not stand in cells and NavGrid.is_walkable(stand) else none


## The footprint cells a craft is worked at (doc 44, "A workshop's work spots"): a batch at the
## workshop's `batch_cell`, any other craft at its `crafting_cell`, each a footprint-local [x, z]
## turned with the piece; the whole footprint when it names no spot. The basic smelter's charge
## goes into its boulder, and the trades' tools are hammered on its casting stone.
func work_cells(batch := false) -> Array[Vector3i]:
	var spot = def.get("batch_cell" if batch else "crafting_cell")
	if not spot is Array or (spot as Array).size() != 2: return cells
	var x := int(spot[0])
	var z := int(spot[1])
	var box: Dictionary = preload("res://scripts/components/FurniturePlacementRules.gd").region_occupancy_box(
		def, {"min": [x, 0, z], "max": [x + 1, 1, z + 1]}, origin_cell, yaw_steps)
	var cell: Vector3i = box.min - Vector3i.UP
	if not cell in cells: return cells
	var spots: Array[Vector3i] = [cell]
	return spots


## Wall removal can use any reachable floor within bracket reach.
func wall_work_stands() -> Array[Vector3i]:
	if def.has("grid_fence"): return preload("GridFence.gd").work_stands(def,origin_cell,yaw_steps)
	return preload("res://scripts/components/WallFurnitureMount.gd").work_stands(def,origin_cell,yaw_steps)


func can_uninstall_from(cell: Vector3i) -> bool:
	if def.has("grid_fence"): return cell in wall_work_stands()
	return String(def.get("placement","floor")) != "wall" or cell in wall_work_stands()


## The uninstall swing finished — hand off to the controller's teardown.
func complete_uninstall(dwarf_id: int) -> void:
	if uninstall_callback.is_valid():
		uninstall_callback.call(self, dwarf_id)
