extends SceneTree

## The mining drag cap (dig_tool.max_drag_length = 32) is a hard limit on both
## horizontal axes (review doc 254 §4.5). Before the fix an over-long drag lost
## only one brush step, so a 100-block drag still planned 99 blocks per axis.

const CAP := 32
const DRAGS: Array[Vector2i] = [Vector2i(100,100), Vector2i(-100,-100), Vector2i(100,-100), Vector2i(-100,100),
	Vector2i(32,0), Vector2i(-32,0), Vector2i(0,32), Vector2i(0,-32), Vector2i(31,0), Vector2i(5,-5), Vector2i.ZERO]
const NORMALS: Array[Vector3i] = [Vector3i.UP, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]

var failures: Array[String] = []


func _init() -> void: _run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _run() -> void:
	var mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	mining._load_config()
	_expect(mining._max_drag_length == CAP, "mining_config.json sets max_drag_length %d (got %d)" % [CAP, mining._max_drag_length])
	var anchor := Vector3i(500, 40, 500)
	for size in range(1, int(mining._max_horizontal) + 1):
		var cap := CAP - CAP % size
		for normal: Vector3i in NORMALS:
			for drag: Vector2i in DRAGS:
				var region: Array[Vector3i] = mining._build_precision_region(anchor, anchor + Vector3i(drag.x, 0, drag.y), normal, size, 1)
				var span := _span(region)
				var label := "brush %d, face %s, drag %s" % [size, normal, drag]
				_expect(span.x <= CAP and span.y <= CAP, "%s stays within %d blocks (got %s)" % [label, CAP, span])
				_expect(region.has(anchor), "%s keeps the anchor block" % label)
				if absi(drag.x) >= CAP: _expect(span.x == cap, "%s stops at the %d-block cap on x (got %d)" % [label, cap, span.x])
				if absi(drag.y) >= CAP: _expect(span.y == cap, "%s stops at the %d-block cap on z (got %d)" % [label, cap, span.y])
	var short: Array[Vector3i] = mining._build_precision_region(anchor, anchor + Vector3i(5, 0, 0), Vector3i.UP, 1, 1)
	_expect(_span(short) == Vector2i(6, 1), "short drags keep their exact length")
	mining.free()
	for failure in failures.slice(0, 20): push_error(failure)
	if failures.is_empty():
		print("MINING_DRAG_LIMIT_OK: every brush size and drag direction stops at the 32-block cap and keeps its anchor")
	quit(0 if failures.is_empty() else 1)


func _span(region: Array[Vector3i]) -> Vector2i:
	if region.is_empty(): return Vector2i.ZERO
	var low := region[0]
	var high := region[0]
	for cell: Vector3i in region:
		low = low.min(cell)
		high = high.max(cell)
	return Vector2i(high.x - low.x + 1, high.z - low.z + 1)
