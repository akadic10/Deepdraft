extends Node

## Placed-entity occupancy registry (doc 12 §Placed World Entities, doc 32
## §Entity Obstacles, doc 16 step 3a). Autoload.
##
## THE terrain grid never knows about placed entities (doc 12 hard pattern):
## trees, the Settlement Flag, and future workshops/furniture register the grid
## cells their PHYSICAL footprint occupies here, and navigation/interaction
## systems query `occupies()` alongside WorldData solidity. Nothing is ever
## written into the block grid to mark entity presence.
##
## Storage is per-COLUMN Y-ranges, not per-cell — a mature oak occupies
## 3×3 columns × ~16 blocks; storing ranges keeps thousands of trees at a few
## array entries each instead of ~150 dictionary cells each.
##
## Footprint conventions (doc 16 Phase 2 decision, Alen 2026-06-10):
##   - Trees register their TRUNK footprint (1/2/3 blocks XZ per stage) over
##     the stage's clearance_height — dwarves walk around trunks, under
##     canopies (visual overhang carries no occupancy, Hard Rule 5 spirit).
##   - Saplings register nothing (clutter).
##   - The Settlement Flag registers its 1×1×3 box.
##
## NavGrid (step 3b) connects to `occupancy_changed` and invalidates affected
## nav cells through the same chunk-granular path as terrain edits.

## Fired on every register/unregister with the changed box (world cells).
signal occupancy_changed(box_min: Vector3i, box_size: Vector3i)

## Column key (Vector2i wx,wz) -> Array of Vector3i(y_min, y_max, handle_id).
## y range is INCLUSIVE. Arrays are tiny (almost always 1 entry).
var _columns: Dictionary = {}

## handle_id -> { "min": Vector3i, "size": Vector3i } — for unregister.
var _boxes: Dictionary = {}

var _next_id: int = 1


func _ready() -> void:
	print("PlacedEntityRegistry: ready.")


## True if any registered entity's footprint contains the cell. The nav
## walkability check (doc 32) is: WorldData air AND NOT occupies().
func occupies(pos: Vector3i) -> bool:
	var ranges: Array = _columns.get(Vector2i(pos.x, pos.z), [])
	for r in ranges:
		var rv := r as Vector3i
		if pos.y >= rv.x and pos.y <= rv.y:
			return true
	return false


## Registers an axis-aligned box of occupied cells. Returns a handle for
## unregister(). size components must be >= 1.
func register_box(box_min: Vector3i, box_size: Vector3i) -> int:
	var id := _next_id
	_next_id += 1
	var y_min := box_min.y
	var y_max := box_min.y + box_size.y - 1
	for dx in range(box_size.x):
		for dz in range(box_size.z):
			var key := Vector2i(box_min.x + dx, box_min.z + dz)
			if not _columns.has(key):
				_columns[key] = []
			(_columns[key] as Array).append(Vector3i(y_min, y_max, id))
	_boxes[id] = { "min": box_min, "size": box_size }
	occupancy_changed.emit(box_min, box_size)
	return id


## Removes a previously registered box. Safe to call with stale/unknown ids.
func unregister(id: int) -> void:
	if not _boxes.has(id):
		return
	var box: Dictionary = _boxes[id]
	var box_min: Vector3i = box["min"]
	var box_size: Vector3i = box["size"]
	for dx in range(box_size.x):
		for dz in range(box_size.z):
			var key := Vector2i(box_min.x + dx, box_min.z + dz)
			var ranges: Array = _columns.get(key, [])
			for i in range(ranges.size() - 1, -1, -1):
				if (ranges[i] as Vector3i).z == id:
					ranges.remove_at(i)
			if ranges.is_empty():
				_columns.erase(key)
	_boxes.erase(id)
	occupancy_changed.emit(box_min, box_size)


## Debug/overlay helper.
func get_stats() -> Dictionary:
	return { "entities": _boxes.size(), "occupied_columns": _columns.size() }


## Scene-reload boundary. Old scene entities are about to be freed, so a
## single cache reset is preferable to emitting one invalidation per box.
func clear_runtime_state() -> void:
	_columns.clear()
	_boxes.clear()
	_next_id = 1
