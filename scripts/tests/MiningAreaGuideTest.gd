extends SceneTree

## Mine blocks' area guide (doc 24, "Optional mining guide"): solid lines on the multiples
## of 32 and, since 2026-10-26, dotted lines on the 16s between them, thinner and fainter,
## a dash centred on each block. Both follow each column's visible top (the slice and
## planned cuts lower it), split at the boundary where the two sides' tops differ, and climb
## perpendicular cliffs: the solid line in one stripe, the dotted line a dash per block.
## Off, or outside the tool, the guide has no mesh; the switch's card names both lines.

const GROUND := 20
const HILL := 30   # x 40..69, z 40..59: crossed by the dotted x 48 and z 48 and the solid x 64
const STEP := 25   # x 80..95, z 0..31: its west edge runs along the dotted x 80
const SLICE := 25
const LIFT := 0.006   # the guide's offset above the surface and off a cliff face

var failures: Array[String] = []
var world
var mining


func _init() -> void: _run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Mining area guide timed out"); quit(1))
	for id: String in ["SaveManager", "WorldClock", "RoomManager", "TaskManager", "StockpileManager", "WaterManager", "AmbientAudio"]:
		root.get_node(id).set_process(false)
	world = root.get_node("WorldData")
	_build_ground()
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	mining = load("res://scripts/systems/MiningDesignationController.gd").new()
	scene.add_child(mining)
	mining.set_process(false)
	_expect(mining._guide_spacing == 32 and mining._dotted_spacing == 16,
		"mining_config.json: solid lines every 32, dotted every 16 (got %d, %d)" % [mining._guide_spacing, mining._dotted_spacing])
	_expect(mining._dotted_width < mining._guide_width and mining._dotted_color.a < mining._guide_color.a and mining._dot_length < .6,
		"dotted lines are thinner and fainter than the solid ones, with gaps longer than a third of a block")
	_check_lines()
	_check_surface_and_cliffs()
	_check_slice_and_plans()
	await _check_switch()
	for failure: String in failures.slice(0, 30): push_error(failure)
	print("MINING_AREA_GUIDE_OK: solid 32s and dotted 16s follow tops, cliffs, the slice and plans" if failures.is_empty() else "MINING_AREA_GUIDE_FAIL")
	quit(0 if failures.is_empty() else 1)


## Open ground at 20, a hill at 30 and a step at 25 (see the constants).
func _build_ground() -> void:
	var generator = root.get_node("WorldGenerator")
	generator.heightmap.resize(world.WORLD_SIZE_X * world.WORLD_SIZE_Z)
	generator.heightmap.fill(GROUND)
	for x in range(40, 70):
		for z in range(40, 60): generator.heightmap[x * world.WORLD_SIZE_Z + z] = HILL
	for x in range(80, 96):
		for z in range(0, 32): generator.heightmap[x * world.WORLD_SIZE_Z + z] = STEP
	generator.waterline_map.resize(world.WORLD_SIZE_X * world.WORLD_SIZE_Z)
	generator.waterline_map.fill(-1)
	generator._maps_ready = true
	generator._cache_block_ids()
	generator._build_noise_instances()   # the tool's hover ray reads the generated blocks


## Lines sit only on the 16s: solid on the 32s, dotted between, a dash per block.
func _check_lines() -> void:
	var pieces := _pieces(mining._area_guide_mesh(0, 127, 0, 127, world.MAX_Y))
	var at := {}
	for piece: Dictionary in pieces:
		at[piece.at] = true
		var solid: bool = piece.at % 32 == 0
		var label := "%s line %d" % [piece.line, piece.at]
		_expect(piece.at % 16 == 0, "%s: guide lines only on the 16s" % label)
		_expect(_same_colour(piece.color, mining._guide_color if solid else mining._dotted_color), "%s has its own colour" % label)
		_expect(_near(piece.width, mining._guide_width if solid else mining._dotted_width), "%s has its width (%.3f)" % [label, piece.width])
		if piece.cliff: continue
		if solid:
			_expect(_near(piece.to - piece.from, 1.0) and _near(piece.from, roundf(piece.from)), "%s: a solid line covers whole blocks %s" % [label, piece])
		else:
			_expect(_near(piece.to - piece.from, mining._dot_length) and _centred(piece), "%s: a dotted line's dash is centred on its block %s" % [label, piece])
	var lines := at.keys()
	lines.sort()
	_expect(lines == [0, 16, 32, 48, 64, 80, 96, 112, 128], "lines at every 16 from 0 to 128: %s" % [lines])
	# Open ground at z 10: both halves, nothing in the gaps between dashes.
	var dashes := _find(pieces, "x", 16, false, 10.0)
	_expect(dashes.size() == 2 and dashes.all(func(piece: Dictionary) -> bool: return _near(piece.y, GROUND + 1 + LIFT)),
		"the dotted x 16 has both halves on open ground at z 10: %s" % [dashes])
	var dotted := pieces.filter(func(piece: Dictionary) -> bool: return piece.line == "x" and piece.at == 16)
	_expect(dotted.size() == 256 and dotted.all(func(piece: Dictionary) -> bool: return fposmod(piece.from, 1.0) > .2 and fposmod(piece.to, 1.0) < .8),
		"the dotted x 16 is 128 blocks of two half dashes, gaps at every block edge (%d pieces)" % dotted.size())
	var solid_pieces := pieces.filter(func(piece: Dictionary) -> bool: return piece.line == "x" and piece.at == 32)
	_expect(solid_pieces.size() == 256, "the solid x 32 is 128 blocks of two halves (%d pieces)" % solid_pieces.size())


## Each half on its own column's top; cliffs across a line: one solid stripe, dotted dashes.
func _check_surface_and_cliffs() -> void:
	var pieces := _pieces(mining._area_guide_mesh(0, 127, 0, 127, world.MAX_Y))
	for line: Array in [["x", 48], ["z", 48], ["x", 64]]:
		var top := _find(pieces, line[0], line[1], false, 50.0)
		_expect(top.size() == 2 and top.all(func(piece: Dictionary) -> bool: return _near(piece.y, HILL + 1 + LIFT)),
			"%s %d runs over the hill's top: %s" % [line[0], line[1], top])
	_expect_cliff(pieces, "x", 48, 40.0 - LIFT, GROUND + 1, HILL + 1, 2, "the dotted x 48 climbs the hill's south face")
	_expect_cliff(pieces, "x", 48, 60.0 + LIFT, GROUND + 1, HILL + 1, 2, "the dotted x 48 comes down its north face")
	_expect_cliff(pieces, "z", 48, 40.0 - LIFT, GROUND + 1, HILL + 1, 2, "the dotted z 48 climbs the hill's west face")
	_expect_cliff(pieces, "x", 64, 40.0 - LIFT, GROUND + 1, HILL + 1, 2, "the solid x 64 climbs the hill's south face")
	# The step's edge runs along x 80: each half keeps its own top, with nothing joining them.
	var halves := _find(pieces, "x", 80, false, 10.0)
	halves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	_expect(halves.size() == 2 and _near(halves[0].y, GROUND + 1 + LIFT) and halves[0].side == -1
		and _near(halves[1].y, STEP + 1 + LIFT) and halves[1].side == 0,
		"the dotted x 80 splits at the step: west half on the ground, east half on the step: %s" % [halves])
	_expect(_find(pieces, "x", 80, true, 10.0).is_empty(), "no stripe joins the halves along the step")


## The slice and planned cuts lower both kinds of line, with their cliffs.
func _check_slice_and_plans() -> void:
	var sliced := _pieces(mining._area_guide_mesh(0, 127, 0, 127, SLICE))
	for line: Array in [["x", 48], ["x", 64]]:
		var top := _find(sliced, line[0], line[1], false, 50.0)
		_expect(top.size() == 2 and top.all(func(piece: Dictionary) -> bool: return _near(piece.y, SLICE + 1 + LIFT)),
			"%s %d sits on the cut floor under the slice: %s" % [line[0], line[1], top])
	_expect_cliff(sliced, "x", 48, 40.0 - LIFT, GROUND + 1, SLICE + 1, 2, "under the slice the dotted x 48 climbs only to the cut")
	_expect_cliff(sliced, "x", 64, 40.0 - LIFT, GROUND + 1, SLICE + 1, 2, "under the slice the solid x 64 climbs only to the cut")
	mining._zone_by_block[Vector3i(16, GROUND, 10)] = 99   # one block planned for mining
	var planned := _pieces(mining._area_guide_mesh(0, 127, 0, 127, world.MAX_Y))
	mining._zone_by_block.clear()
	var halves := _find(planned, "x", 16, false, 10.0)
	halves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	_expect(halves.size() == 2 and _near(halves[0].y, GROUND + LIFT) and halves[0].side == 0
		and _near(halves[1].y, GROUND + 1 + LIFT), "a planned cut lowers its own half of the dotted line: %s" % [halves])
	_expect_cliff(planned, "x", 16, 10.0 + LIFT, GROUND, GROUND + 1, 1, "the dotted line steps down into the planned cut")
	_expect_cliff(planned, "x", 16, 11.0 - LIFT, GROUND, GROUND + 1, 1, "and back up out of it")


## The tool bar's switch: off by default, no mesh while off or outside the tool.
func _check_switch() -> void:
	var rig = load("res://scripts/systems/Camera.gd").new()
	current_scene.add_child(rig)
	rig.focus_world_position(Vector3(48.5, GROUND + 1, 48.5), 40.0)
	mining._camera_rig = rig
	for i in range(4): await process_frame
	var grid: MeshInstance3D = mining._overlay.grid_node
	mining._on_tool_requested("mine_precision")
	var toggle: Dictionary = mining.tool_bar_state().toggle
	_expect(not toggle.on and not grid.visible and grid.mesh == null, "the guide starts off, with no mesh")
	_expect(toggle.label == "32 × 32 guide" and "every 32 blocks" in String(toggle.tooltip) and "dotted lines every 16" in String(toggle.tooltip),
		"the switch's card names the solid 32s and the dotted 16s: \"%s\"" % toggle.tooltip)
	mining.set_tool_setting("guide", true)
	_expect(grid.visible and _has_both(grid.mesh), "switched on, one mesh holds the solid and the dotted lines")
	_expect(grid.material_override is BaseMaterial3D and not grid.material_override.no_depth_test, "the guide is depth tested: buried lines stay hidden")
	mining.set_tool_setting("guide", false)
	_expect(not grid.visible and grid.mesh == null, "switched off, neither line shows")
	mining.set_tool_setting("guide", true)
	mining.deactivate()
	_expect(not grid.visible and grid.mesh == null, "closing the tool hides both lines")
	mining._on_tool_requested("mine_precision")
	_expect(grid.visible and _has_both(grid.mesh), "reopening Mine blocks shows both again: the switch holds")
	mining.deactivate()


func _has_both(mesh: ArrayMesh) -> bool:
	var solid := 0
	var dotted := 0
	for piece: Dictionary in _pieces(mesh):
		if _same_colour(piece.color, mining._guide_color): solid += 1
		elif _same_colour(piece.color, mining._dotted_color): dotted += 1
		else: return false
	return solid > 0 and dotted > 0


func _expect_cliff(pieces: Array, line: String, at: int, face: float, low: int, high: int, halves: int, label: String) -> void:
	var stripes := pieces.filter(func(piece: Dictionary) -> bool:
		return piece.cliff and piece.line == line and piece.at == at and _near(piece.face, face))
	var solid := at % 32 == 0
	var expected := halves * (1 if solid else high - low)
	var ok := stripes.size() == expected
	for piece: Dictionary in stripes:
		if solid: ok = ok and _near(piece.from, low) and _near(piece.to, high)
		else: ok = ok and _near(piece.to - piece.from, mining._dot_length) and piece.from > low and piece.to < high and _centred(piece)
	_expect(ok, "%s: %d %s from %d to %d (got %d: %s)" % [label, expected, "stripes" if solid else "dashes", low, high, stripes.size(), stripes.slice(0, 4)])


## Surface pieces (cliff false) or cliff pieces (true) of one line at one block along it.
func _find(pieces: Array, line: String, at: int, cliff: bool, along: float) -> Array:
	return pieces.filter(func(piece: Dictionary) -> bool:
		var where: float = piece.face if cliff else piece.from
		return piece.line == line and piece.at == at and piece.cliff == cliff and where >= along and where < along + 1.0)


## The guide's quads, read back as pieces: which line ("x": the line x = at, running along z),
## which side of it, its width, and where it runs: along the line on the surface at y, or up a
## cliff face at `face` along the line, from/to being heights.
func _pieces(mesh: ArrayMesh) -> Array:
	var result := []
	if mesh == null: return result
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(0, verts.size(), 6):
		var low := verts[i]
		var high := verts[i]
		for j in range(1, 6):
			low = low.min(verts[i + j])
			high = high.max(verts[i + j])
		var size := high - low
		var cliff := size.y > 0.0
		var on_x := size.x > size.z if cliff else size.x < size.z   # the line x = at, running along z
		var across := Vector2(low.x, high.x) if on_x else Vector2(low.z, high.z)
		var edge := across.x if _near(across.x, roundf(across.x)) else across.y
		result.append({"line": "x" if on_x else "z", "at": roundi(edge), "side": 0 if _near(across.x, edge) else -1,
			"width": (across.y - across.x) * 2.0, "cliff": cliff, "color": cols[i], "y": low.y,
			"face": (low.z if on_x else low.x) if cliff else 0.0,
			"from": low.y if cliff else (low.z if on_x else low.x), "to": high.y if cliff else (high.z if on_x else high.x)})
	return result


## A dash centred on its block: equal gaps to both block edges.
func _centred(piece: Dictionary) -> bool:
	return _near(piece.from + piece.to, floorf(piece.from) * 2.0 + 1.0)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < .001


## Vertex colours come back from the mesh at 8 bits a channel.
func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < .01 and absf(a.g - b.g) < .01 and absf(a.b - b.b) < .01 and absf(a.a - b.a) < .01
