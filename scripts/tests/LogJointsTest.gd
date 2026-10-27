extends SceneTree

## Built logs (doc 275): the piece each log draws from its neighbours, and the faces next to a log.
## - a lone log shows end grain at both ends; logs of one wood in a row join, and upright ones
##   stack into a post; logs of another wood, or upright beside lying, stay apart;
## - a log along Z is the same piece turned a quarter;
## - where lying logs cross (+), meet (T) or turn a corner (L), the top log alternates by layer:
##   along X on even layers, along Z on odd ones, with the other log's cut shoulders on its sides;
## - a block beside a log keeps the face that touches it, since a log leaves its edges open;
## - every piece loads in all four woods, each wood in its own colours.
var failures: Array[String] = []
var logs := {}   # cell -> {wood, direction}

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var Logs = load("res://scripts/components/BuiltLogs.gd")
	var piece := func(cell: Vector3i) -> String:
		var chosen: Dictionary = Logs.piece_at(cell, logs[cell], func(at: Vector3i) -> Dictionary: return logs.get(at, {}))
		return String(chosen.piece).get_slice("_", 0) + ("~" if bool(chosen.turn) else "")
	_lay("pine", "x", [Vector3i(0, 4, 0)])
	_expect(piece.call(Vector3i(0, 4, 0)) == "h11", "a lone log shows end grain at both ends")
	_lay("pine", "x", [Vector3i(1, 4, 0), Vector3i(2, 4, 0)])
	_expect([piece.call(Vector3i(0, 4, 0)), piece.call(Vector3i(1, 4, 0)), piece.call(Vector3i(2, 4, 0))] == ["h10", "h00", "h01"],
		"a row joins into one long log, end grain only where it stops")
	logs.clear()
	_lay("pine", "z", [Vector3i(0, 4, 0)])
	_lay("oak", "z", [Vector3i(0, 4, 1)])
	_expect(piece.call(Vector3i(0, 4, 0)) == "h11~" and piece.call(Vector3i(0, 4, 1)) == "h11~", "a log along z is turned; another wood never joins it")
	logs.clear()
	_lay("oak", "up", [Vector3i(0, 4, 0), Vector3i(0, 5, 0), Vector3i(0, 6, 0)])
	_lay("oak", "x", [Vector3i(1, 5, 0)])
	_expect([piece.call(Vector3i(0, 4, 0)), piece.call(Vector3i(0, 5, 0)), piece.call(Vector3i(0, 6, 0))] == ["u10", "u00", "u01"],
		"upright logs stack into one post, end grain at its foot and top")
	_expect(piece.call(Vector3i(1, 5, 0)) == "h11", "a lying log against a post just ends")
	# A + crossing on two layers: X on top on the even one, Z on the odd one.
	logs.clear()
	for y in [4, 5]:
		_lay("pine", "x", [Vector3i(-1, y, 0), Vector3i(0, y, 0), Vector3i(1, y, 0)])
		_lay("pine", "z", [Vector3i(0, y, -1), Vector3i(0, y, 1)])
	_expect(piece.call(Vector3i(0, 4, 0)) == "j0011" and piece.call(Vector3i(0, 5, 0)) == "j0011~", "a + crossing: the top log alternates by layer")
	_expect(piece.call(Vector3i(0, 4, 1)) == "h01~" and piece.call(Vector3i(1, 4, 0)) == "h01", "the crossing rows run on through the joint")
	# A T: the through wall along X, the branch coming in from +Z.
	logs.clear()
	for y in [4, 5]:
		_lay("pine", "x", [Vector3i(-1, y, 0), Vector3i(0, y, 0), Vector3i(1, y, 0)])
		_lay("pine", "z", [Vector3i(0, y, 1), Vector3i(0, y, 2)])
	_expect(piece.call(Vector3i(0, 4, 0)) == "j0001" and piece.call(Vector3i(0, 5, 0)) == "j1011~",
		"a T: the through log passes on one layer, the branch's end shows through on the next")
	# An L: the X run goes on to +X, the Z run to +Z.
	logs.clear()
	for y in [4, 5]:
		_lay("pine", "x", [Vector3i(0, y, 0), Vector3i(1, y, 0)])
		_lay("pine", "z", [Vector3i(0, y, 1)])
	_expect(piece.call(Vector3i(0, 4, 0)) == "j1001" and piece.call(Vector3i(0, 5, 0)) == "j1010~",
		"an L: each layer's top log shows its end on its own face")
	_expect(piece.call(Vector3i(0, 4, 1)) == "h01~", "the corner's Z log joins it, with no end grain at the corner")
	_faces_test()
	_pieces_test(Logs)
	for failure: String in failures: push_error(failure)
	print("LOG_JOINTS_OK" if failures.is_empty() else "LOG_JOINTS_FAIL")
	quit(0 if failures.is_empty() else 1)


func _lay(wood: String, direction: String, cells: Array) -> void:
	for cell: Vector3i in cells: logs[cell] = {"wood": wood, "direction": direction}


## A stone block beside a log keeps all six faces; beside stone it loses the one they share.
func _faces_test() -> void:
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	var renderer = load("res://scripts/systems/WorldRenderer.gd").new()
	var stone := Vector3i(42, 60, 40)
	var beside := stone + Vector3i.RIGHT
	world.get_chunk(stone.x >> 4, stone.y >> 4, stone.z >> 4)
	for cell: Vector3i in [stone, beside]:
		for side: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			world.set_block(cell.x + side.x, cell.y + side.y, cell.z + side.z, blocks.AIR_ID)
	var column := Vector2i(stone.x >> 4, stone.z >> 4)
	var faces := func() -> int:
		renderer._rebuild_added_columns([column])
		var node: MeshInstance3D = renderer._added_meshes.get(column)
		return 0 if node == null else (node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	world.set_block(stone.x, stone.y, stone.z, blocks.get_id("base:terrain:rock:rock01"))
	world.set_block(beside.x, beside.y, beside.z, blocks.get_id("base:construction:log:oak:x"))
	_expect(not blocks.fills_cell(blocks.get_id("base:construction:log:oak:x")) and blocks.is_solid(blocks.get_id("base:construction:log:oak:x")),
		"a log is solid but hides no face")
	_expect(faces.call() == 6, "stone beside a log keeps the face toward it, and the log is not drawn as a cube: %d faces" % faces.call())
	world.set_block(beside.x, beside.y, beside.z, blocks.get_id("base:terrain:rock:rock01"))
	_expect(faces.call() == 10, "two stones hide the face they share: %d faces" % faces.call())
	for cell: Vector3i in [stone, beside]: world.set_block(cell.x, cell.y, cell.z, blocks.AIR_ID)
	renderer.free()


## Every piece loads, and each wood takes its own colours from CraftMaterials.
func _pieces_test(Logs: GDScript) -> void:
	var built: Node3D = Logs.new()
	root.add_child(built)
	built._load_pieces()
	_expect(built._pieces.size() == 4 and (built._pieces.oak as Dictionary).size() == 80 and built._shadows.size() == 80,
		"all 80 pieces load for each of the four woods, with their shadows")
	var oak: Mesh = built._pieces.oak.h11_p0
	var apple: Mesh = built._pieces.apple.h11_p0
	_expect(oak.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != apple.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "each wood takes its own colours")
	built.free()


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
