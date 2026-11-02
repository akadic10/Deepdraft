extends FurnitureGhostComponent

## Bring one log to a cold nightly fire and light it (doc 279). The fire's owner
## (FurnitureFires) adds this source at dusk and retires it once the fire is lit
## or at dawn. It is the placement fetch with any log as the item: the planner
## quotes every fuel key, and the delivered log's key and wood are kept so the
## fire shows the very log it burns.

var installed_id := -1                  # the fire's installed id: the order's saved identity
var fuel_keys: Array[String] = []       # every log that may burn here
var log_contact := Vector3.ZERO         # world point the log is set down on
var front_stands := false               # a hearth is fed through its opening (local +Z)
var light_callback: Callable = Callable()     # (source) -> the owner lights the fire
var can_light_callback: Callable = Callable() # (source) -> still cold, installed and night
var delivered_key := ""


func fetch_keys() -> Array[String]:
	return fuel_keys


func lease_id() -> int:
	return _lease_id


## A hearth's worker stands before the opening; any side when that is blocked.
func work_stands(from: Vector3i) -> Array[Vector3i]:
	var stands := super.work_stands(from)
	var front := _front(stands)
	return front if not front.is_empty() else stands


func nearest_stand_target(dwarf_cell: Vector3i) -> Vector3i:
	var front := _front(work_stands(dwarf_cell))
	if front.is_empty():
		return super.nearest_stand_target(dwarf_cell)
	var best := front[0]
	for stand: Vector3i in front:
		if (stand - dwarf_cell).length_squared() < (best - dwarf_cell).length_squared(): best = stand
	return best


func display_name() -> String:
	return "Light the %s" % String(def.get("display_name", "fire")).to_lower()


func work_waiting_reason() -> String:
	return "Waiting for a log"


## Any log, loose or stored. The claim keeps the nearest loose one from haulers.
func item_available() -> bool:
	if _claim_valid():
		return true
	for key: String in fuel_keys:
		if StockpileManager.get_available_total(key) > 0:
			return true
		if is_instance_valid(drop_manager) and drop_manager.nearest_loose_of_key(key, origin_cell) != null:
			return true
	return false


## Posts the one FETCH_BUILD lease. Unlike a placement it never redirects a
## storage haul: a hauler keeps its whole load of logs.
func update_lease() -> void:
	if source_id < 0:
		return
	if not has_committed_item():
		item_key = _nearest_key()
	ensure_claim()
	if _lease_id < 0 and item_available():
		_lease_id = int(TaskManager.add_task(Task.Type.FETCH_BUILD, origin_cell, {"installed_id": installed_id}, source_id))


## The planner may quote a different wood than the soft claim; fetch that one.
func reserve_fetch(dwarf_id: int, dwarf_cell: Vector3i) -> Dictionary:
	if not _preferred_fetch.is_empty():
		item_key = String(_preferred_fetch.get("material", {}).get("key", item_key))
	return super.reserve_fetch(dwarf_id, dwarf_cell)


func placement_contact(_from: Vector3) -> Vector3:
	return log_contact


func capture_item_properties(cargo: Node3D) -> void:
	super.capture_item_properties(cargo)
	delivered_key = String(cargo.get_meta("item_key", item_key))


func complete_build(_dwarf_id: int) -> void:
	if light_callback.is_valid():
		light_callback.call(self)


func can_complete_build() -> bool:
	return not can_light_callback.is_valid() or bool(can_light_callback.call(self))


## The stands just in front of the opening, when the fire is fed from the front.
func _front(stands: Array[Vector3i]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not front_stands:
		return result
	var ahead: Vector3i = [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)][posmod(yaw_steps, 4)]
	var cells := footprint_cells()
	for cell: Vector3i in cells:
		if cell + ahead in stands and not cell + ahead in cells and not cell + ahead in result: result.append(cell + ahead)
	return result


## The nearest loose log's key, else any wood in storage, else the current key.
func _nearest_key() -> String:
	var best := item_key if item_key in fuel_keys else (fuel_keys[0] if not fuel_keys.is_empty() else "")
	var distance := INF
	if is_instance_valid(drop_manager):
		for key: String in fuel_keys:
			var item: Node3D = drop_manager.nearest_loose_of_key(key, origin_cell)
			if item != null and item.global_position.distance_squared_to(Vector3(origin_cell)) < distance:
				best = key
				distance = item.global_position.distance_squared_to(Vector3(origin_cell))
	if distance == INF:
		for key: String in fuel_keys:
			if StockpileManager.get_available_total(key) > 0:
				return key
	return best
