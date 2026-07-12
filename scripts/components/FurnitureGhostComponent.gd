class_name FurnitureGhostComponent
extends RefCounted

## A placed-but-unbuilt furniture designation (doc 19 §3.2–3.3) — the SH
## ghost form translated: a translucent placed-form marker that persists in
## the world as a standing request until a dwarf fetches the matching item
## and installs it.
##
## Phase 2 scope: designation bookkeeping only (footprint cells, the marker
## node, window data). Phase 3 grows this into the FETCH-AND-BUILD work
## source (one lease, type-matched against the loose-item index and storage
## aggregates — doc 19 §3.3). Owned by FurniturePlacementController, the
## MiningZone/StockpileZone ownership shape.
##
## Ghosts are NON-SOLID (SH parity): no PlacedEntityRegistry registration,
## no nav impact — nav changes only when the piece is actually installed.

var ghost_id: int = -1
var furniture_key: String = ""      # base:furniture:* (namespaced — Hard Rule 3)
var item_key: String = ""           # the resources.json item form to fetch
var def: Dictionary = {}            # parsed data/furniture/*.json definition
var origin_cell: Vector3i = Vector3i(-1, -1, -1)   # footprint min-corner FLOOR cell
var yaw_steps: int = 0              # 0..3 — 90° each (R key)
var node: Node3D = null             # translucent in-world marker (controller-owned)


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
