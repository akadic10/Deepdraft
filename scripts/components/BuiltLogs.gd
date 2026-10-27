extends Node3D

## Built logs (doc 275): each log block drawn as the Hearthblock piece its neighbours call for,
## from assets/models/construction/logs.glb (tools/voxel_assets/built_logs.py), in its wood's
## colours by CraftMaterials. Logs of one wood in a row join into one long log, and upright
## ones into one post. Where horizontal logs meet across, in a +, T or L, the top log passes
## whole over the lower log's cut shoulders: along X on even layers, along Z on odd ones. Every
## other system still sees a whole solid block. WorldRenderer keeps the faces behind a log
## (BlockRegistry.fills_cell) and calls cell_changed, rescan and refresh.
const MODEL := "res://assets/models/construction/logs.glb"
const PALETTE := {"material_palette": "hand_hewn_timber"}
const VARIANTS := 4
const SIDES := {"x": [Vector3i(-1, 0, 0), Vector3i(1, 0, 0)], "z": [Vector3i(0, 0, -1), Vector3i(0, 0, 1)]}

var lighting: Node   # UndergroundLighting, so logs are lit as goods are
var _material: Material
var _pieces := {}    # wood -> {piece -> Mesh} in that wood's colours
var _shadows := {}   # piece -> Mesh: the coarse shadow proxies, the same for every wood
var _cells := {}     # every built log -> true
var _dirty := false
var _slice := -1
var _drawn: Array[Node] = []


func cell_changed(cell: Vector3i, old_id: int, new_id: int) -> void:
	if BlockRegistry.is_log(new_id):
		_cells[cell] = true
		_dirty = true
	elif BlockRegistry.is_log(old_id) or _cells.has(cell):
		_cells.erase(cell)
		_dirty = true


## Finds every built log again, after a load or a reset.
func rescan() -> void:
	_cells.clear()
	var overrides := WorldData.terrain_overrides()
	for cell: Vector3i in overrides:
		if BlockRegistry.is_log(int(overrides[cell])): _cells[cell] = true
	_dirty = true


func count() -> int:
	return _cells.size()


## Redraws when a log came or went, or the slice moved.
func refresh(slice_y: int) -> void:
	if not _dirty and slice_y == _slice: return
	_dirty = false
	_slice = slice_y
	for node: Node in _drawn: node.queue_free()
	_drawn.clear()
	if _cells.is_empty(): return
	_load_pieces()
	var visual := {}   # "wood|piece" -> transforms
	var shadow := {}   # piece -> transforms
	# The slice hides what is above it, so a log at the cut shows its end grain.
	var lookup := func(at: Vector3i) -> Dictionary:
		return {} if at.y > slice_y else BlockRegistry.log_of(WorldData.get_terrain_block(at.x, at.y, at.z))
	for cell: Vector3i in _cells:
		if cell.y > slice_y: continue
		var held: Dictionary = lookup.call(cell)
		if held.is_empty(): continue
		var chosen := piece_at(cell, held, lookup)
		var placed := _placed(cell, bool(chosen.turn))
		_add(visual, "%s|%s" % [held.wood, chosen.piece], placed)
		_add(shadow, String(chosen.piece), placed)
	for key: String in visual:
		var node := _instances(_pieces[key.get_slice("|", 0)][key.get_slice("|", 1)], visual[key])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = _lit_material()
		_drawn.append(node)
	for piece: String in shadow:
		var node := _instances(_shadows[piece], shadow[piece])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_drawn.append(node)


## Green ghost logs for a drag's preview: `cells` maps each planned cell to its direction. They
## join each other and the built logs as they will once built.
func ghost(cells: Dictionary, wood: String, material: Material) -> Node3D:
	var holder := Node3D.new()
	holder.name = "LogGhost"
	if cells.is_empty() or BlockRegistry.get_wood(wood).is_empty(): return holder
	_load_pieces()
	var lookup := func(at: Vector3i) -> Dictionary:
		if cells.has(at): return {"wood": wood, "direction": cells[at]}
		return BlockRegistry.log_of(WorldData.get_terrain_block(at.x, at.y, at.z))
	var groups := {}
	for cell: Vector3i in cells:
		var chosen := piece_at(cell, {"wood": wood, "direction": cells[cell]}, lookup)
		_add(groups, String(chosen.piece), _placed(cell, bool(chosen.turn)))
	for piece: String in groups:
		var node := _instances(_pieces[wood][piece], groups[piece], holder)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = material
	return holder


## The piece a log at `cell` draws, and whether it is turned a quarter to lie along Z:
## {piece, turn}. `held` is its {wood, direction}; `lookup(cell)` gives any cell's log or {}.
static func piece_at(cell: Vector3i, held: Dictionary, lookup: Callable) -> Dictionary:
	var variant := posmod((cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.z * 83492791), VARIANTS)
	if held.direction == "up":
		var below := _open(lookup.call(cell + Vector3i.DOWN), held)
		var above := _open(lookup.call(cell + Vector3i.UP), held)
		return {"piece": "u%d%d_p%d" % [below, above, variant], "turn": false}
	var arms := {}
	for axis: String in SIDES:
		for i in 2: arms[axis + str(i)] = _joins(held, lookup.call(cell + SIDES[axis][i]), axis)
	var across := "z" if held.direction == "x" else "x"
	if not (arms[across + "0"] or arms[across + "1"]): return _straight(String(held.direction), arms, variant)
	var top := "x" if posmod(cell.y, 2) == 0 else "z"
	var low := "z" if top == "x" else "x"
	if not (arms[low + "0"] or arms[low + "1"]): return _straight(top, arms, variant)
	var ends := "%d%d" % [int(not arms[top + "0"]), int(not arms[top + "1"])]
	if top == "x": return {"piece": "j%s%d%d_p%d" % [ends, int(arms.z0), int(arms.z1), variant], "turn": false}
	# Turned a quarter, the piece's -Z shoulder meets the log from +X and its +Z one the log from -X.
	return {"piece": "j%s%d%d_p%d" % [ends, int(arms.x1), int(arms.x0), variant], "turn": true}


static func _straight(axis: String, arms: Dictionary, variant: int) -> Dictionary:
	return {"piece": "h%d%d_p%d" % [int(not arms[axis + "0"]), int(not arms[axis + "1"]), variant], "turn": axis == "z"}


## A horizontal neighbour joins along `axis` when the line between them runs along either log.
static func _joins(held: Dictionary, near: Dictionary, axis: String) -> bool:
	if near.is_empty() or near.wood != held.wood or "up" in [held.direction, near.direction]: return false
	return axis in [held.direction, near.direction]


## 1 where an upright log's end shows its grain: no upright log of its wood above or below.
static func _open(near: Dictionary, held: Dictionary) -> int:
	return 0 if not near.is_empty() and near.wood == held.wood and near.direction == "up" else 1


## A piece in its block; a turned one lies along Z, turned about the block's middle.
static func _placed(cell: Vector3i, turn: bool) -> Transform3D:
	if not turn: return Transform3D(Basis(), Vector3(cell))
	var basis := Basis(Vector3.UP, -PI * 0.5)
	return Transform3D(basis, Vector3(cell) + Vector3(0.5, 0, 0.5) - basis * Vector3(0.5, 0, 0.5))


static func _add(groups: Dictionary, key: Variant, placed: Transform3D) -> void:
	if not groups.has(key): groups[key] = []
	(groups[key] as Array).append(placed)


func _instances(mesh: Mesh, transforms: Array, parent: Node = self) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size(): multimesh.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	parent.add_child(node)
	return node


## The pieces in every wood's colours, recoloured once from the hand-hewn source palette.
func _load_pieces() -> void:
	if not _pieces.is_empty(): return
	var scene := load(MODEL) as PackedScene
	for wood: String in BlockRegistry.woods():
		var model := scene.instantiate()
		CraftMaterials.apply_palette(model, PALETTE, String(BlockRegistry.get_wood(wood).material))
		var meshes := {}
		for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var piece := String(node.name).get_slice("__", 1)
			if String(node.name).begins_with("VoxelShadowProxy"): _shadows[piece] = node.mesh
			else: meshes[piece] = node.mesh
		_pieces[wood] = meshes
		model.free()


## The goods' material (ItemDropManager): vertex colours, lit underground as goods are.
func _lit_material() -> Material:
	if _material == null:
		var source := StandardMaterial3D.new()
		source.vertex_color_use_as_albedo = true
		source.cull_mode = BaseMaterial3D.CULL_DISABLED
		source.roughness = 1.0
		source.metallic_specular = 0.0
		_material = lighting.make_material(source, true) if lighting != null else source
	return _material
