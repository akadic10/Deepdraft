extends Node

## Blueprints (doc 273, Phase 3): the starters shipped in data/construction/blueprints.json and
## the player's own, one JSON file each in user://blueprints/, shared by copying the file. The
## library owns that folder's JSON (the registry rule): it reads and checks every file, since a
## shared file may come from anyone, writes the player's, renames and deletes them, and renders
## each blueprint's picture once, kept as a PNG beside its file.
##
## A blueprint is {id, name, size (Vector3i), blocks ({kind: Array[Vector3i]}), starter, path}.
## Cells sit relative to the corner. Kinds are construction kinds (data/construction/blocks.json),
## never runtime numbers (Hard Rule 3).

## The list or a picture changed.
signal changed

const JsonData = preload("res://scripts/registries/JsonData.gd")
const FORMAT := 1
const FOLDER := "user://blueprints/"
const STARTERS_PATH := "res://data/construction/blueprints.json"
## The largest blueprint: across, tall and deep.
const MAX_SIZE := Vector3i(32, 16, 32)
const MAX_NAME := 40
const MAX_FILE_BYTES := 1048576
const PICTURE_PIXELS := 160
## Built stone takes its layer's rock; a picture shows the grey they share.
const STONE_LOOK := "base:terrain:rock:rock07"
const LOG_PREFIX := "log:"
## A cube's faces: each outward normal and its corners.
const FACES := [
	[Vector3i(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
	[Vector3i(0, -1, 0), [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]],
	[Vector3i(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]],
	[Vector3i(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
]

var _starters: Array[Dictionary] = []
var _own: Array[Dictionary] = []
var _refused: Array[String] = []
var _pictures: Dictionary = {}   # id -> Texture2D
var _waiting: Array[String] = []   # ids whose picture is still to render, in order
var _rendering := false


func _ready() -> void:
	for entry: Variant in JsonData.read_dict(STARTERS_PATH).get("starters", []):
		var outcome := parse(entry, "")
		if outcome.has("error"):
			push_error("BlueprintLibrary: a starter blueprint is refused: %s" % outcome.error)
			continue
		var blueprint: Dictionary = outcome.blueprint
		blueprint.merge({"id": "starter:" + slug(String(blueprint.name)), "starter": true, "path": ""})
		_starters.append(blueprint)
	rescan()


# ── The list ──────────────────────────────────────────────────────────────────

## The starters first, then the player's own by name.
func blueprints() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_starters)
	result.append_array(_own)
	return result


func get_blueprint(id: String) -> Dictionary:
	for blueprint: Dictionary in blueprints():
		if blueprint.id == id: return blueprint
	return {}


## The files in the folder that could not be read, each "name.json: why".
func refused() -> Array[String]:
	return _refused


## Reads the folder again, for files the player dropped into it.
func rescan() -> void:
	_own.clear()
	_refused.clear()
	DirAccess.make_dir_recursive_absolute(FOLDER)
	for file: String in DirAccess.get_files_at(FOLDER):
		if file.get_extension().to_lower() == "json": _read_file(FOLDER + file)
	_sort()
	changed.emit()


func _read_file(path: String) -> void:
	var stem := path.get_file().get_basename()
	if FileAccess.get_file_as_bytes(path).size() > MAX_FILE_BYTES:
		_refused.append("%s: it is too big to be a blueprint" % path.get_file())
		return
	var outcome := JsonData.inspect(path, TYPE_DICTIONARY)
	var parsed := parse(outcome.data, stem) if String(outcome.error).is_empty() else {"error": "it is not a blueprint file"}
	if parsed.has("error"):
		_refused.append("%s: %s" % [path.get_file(), parsed.error])
		return
	var blueprint: Dictionary = parsed.blueprint
	blueprint.merge({"id": "own:" + stem, "starter": false, "path": path})
	_own.append(blueprint)


func _sort() -> void:
	_own.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)


# ── Files ─────────────────────────────────────────────────────────────────────

## Checks a blueprint read from a file: {"blueprint": {name, size, blocks}} or {"error": why}.
## Only the known fields are read; anything wrong refuses the whole file. A file of another
## format is refused, not converted, while the game is in development (as saves are).
static func parse(data: Variant, fallback_name: String) -> Dictionary:
	if not data is Dictionary or not (data as Dictionary).has("deepdraft_blueprint"): return {"error": "it is not a Deepdraft blueprint"}
	if not _whole(data.deepdraft_blueprint) or int(data.deepdraft_blueprint) != FORMAT:
		return {"error": "it was made for another version of the game"}
	var name := String(data.name).strip_edges().left(MAX_NAME) if data.get("name") is String else ""
	if name.is_empty(): name = fallback_name if not fallback_name.is_empty() else "Blueprint"
	if not _triple(data.get("size")): return {"error": "its size is not three whole numbers"}
	var size := Vector3i(int(data.size[0]), int(data.size[1]), int(data.size[2]))
	if size.x < 1 or size.y < 1 or size.z < 1: return {"error": "its size is empty"}
	if size.x > MAX_SIZE.x or size.y > MAX_SIZE.y or size.z > MAX_SIZE.z:
		return {"error": "it is too large: a blueprint is at most %d × %d × %d" % [MAX_SIZE.x, MAX_SIZE.y, MAX_SIZE.z]}
	if not data.get("blocks") is Dictionary: return {"error": "it has no blocks"}
	var blocks := {}
	var taken := {}
	for kind: Variant in data.blocks:
		if not kind is String or material_parts(kind).is_empty():
			return {"error": "it uses a material the game does not know: %s" % str(kind)}
		if not data.blocks[kind] is Array: return {"error": "its %s blocks are not a list" % kind}
		var cells: Array[Vector3i] = []
		for cell: Variant in data.blocks[kind]:
			if not _triple(cell): return {"error": "a %s block is not three whole numbers" % kind}
			var at := Vector3i(int(cell[0]), int(cell[1]), int(cell[2]))
			if at.x < 0 or at.y < 0 or at.z < 0 or at.x >= size.x or at.y >= size.y or at.z >= size.z:
				return {"error": "a block lies outside its size"}
			if taken.has(at): return {"error": "two blocks share a cell"}
			taken[at] = true
			cells.append(at)
		if not cells.is_empty(): blocks[kind] = cells
	if blocks.is_empty(): return {"error": "it has no blocks"}
	return {"blueprint": {"name": name, "size": size, "blocks": blocks}}


## A blueprint's material (doc 275): a construction kind, or a log as "log:<wood>:<direction>",
## its direction up, x or z. Its kind, wood and direction; {} when the game does not know it.
static func material_parts(material: String) -> Dictionary:
	if material.begins_with(LOG_PREFIX):
		var parts := material.split(":")
		if parts.size() != 3 or BlockRegistry.get_wood(parts[1]).is_empty() or BlockRegistry.log_block(parts[1], parts[2]).is_empty(): return {}
		for kind: String in BlockRegistry.construction_keys():
			var lies := String(BlockRegistry.get_construction_def(kind).get("logs", ""))
			if not lies.is_empty() and (lies == "up") == (parts[2] == "up"): return {"kind": kind, "wood": parts[1], "direction": parts[2]}
		return {}
	var definition := BlockRegistry.get_construction_def(material)
	if definition.is_empty() or definition.has("logs"): return {}
	return {"kind": material, "wood": "", "direction": ""}


## A log's material: "log:pine:x".
static func log_material(wood: String, direction: String) -> String:
	return LOG_PREFIX + wood + ":" + direction


## A material after `turns` quarter turns: a lying log's direction swaps on odd turns.
static func turned_material(material: String, turns: int) -> String:
	var parts := material_parts(material)
	if posmod(turns, 2) == 0 or not String(parts.get("direction", "")) in ["x", "z"]: return material
	return log_material(String(parts.wood), "z" if parts.direction == "x" else "x")


## The blueprint's blocks as plans would build them, one entry a kind and wood:
## [{kind, wood, count}], so the tag and the card can say what it takes.
static func goods(blocks: Dictionary) -> Array:
	var found := {}
	for material: String in blocks:
		var parts := material_parts(material)
		var key := "%s|%s" % [parts.kind, parts.wood]
		if not found.has(key): found[key] = {"kind": String(parts.kind), "wood": String(parts.wood), "count": 0}
		found[key].count += (blocks[material] as Array).size()
	return found.values()


static func _whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))


static func _triple(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 3 and _whole(value[0]) and _whole(value[1]) and _whole(value[2])


## A blueprint's file: its format, name, size and blocks, one line a material.
static func to_text(blueprint: Dictionary) -> String:
	var size: Vector3i = blueprint.size
	var lines: Array[String] = []
	for kind: String in blueprint.blocks:
		var cells: Array = (blueprint.blocks[kind] as Array).map(func(cell: Vector3i) -> Array: return [cell.x, cell.y, cell.z])
		lines.append("    %s: %s" % [JSON.stringify(kind), JSON.stringify(cells)])
	return "{\n  \"deepdraft_blueprint\": %d,\n  \"name\": %s,\n  \"size\": [%d, %d, %d],\n  \"blocks\": {\n%s\n  }\n}\n" \
		% [FORMAT, JSON.stringify(String(blueprint.name)), size.x, size.y, size.z, ",\n".join(lines)]


## A file name made of a blueprint's name: "Stone hut" is stone_hut.
static func slug(name: String) -> String:
	var result := ""
	for character: String in name.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"): result += character
		elif not result.ends_with("_"): result += "_"
	result = result.strip_edges().trim_prefix("_").trim_suffix("_")
	return result if not result.is_empty() else "blueprint"


## Keeps a new blueprint as a file in the player's folder, its file name made free there, and
## queues its picture. The blueprint, or {} when its file cannot be written.
func save(name: String, size: Vector3i, blocks: Dictionary) -> Dictionary:
	var title := name.strip_edges().left(MAX_NAME)
	if title.is_empty(): title = "Blueprint"
	var stem := _free_stem(slug(title), "")
	var blueprint := {"id": "own:" + stem, "name": title, "size": size, "blocks": blocks, "starter": false, "path": FOLDER + stem + ".json"}
	if not _write(blueprint): return {}
	_own.append(blueprint)
	_sort()
	_queue_picture(String(blueprint.id))
	changed.emit()
	return blueprint


## Renames one of the player's blueprints, its file and picture with it. Its new id, or "".
func rename(id: String, name: String) -> String:
	var blueprint := get_blueprint(id)
	var title := name.strip_edges().left(MAX_NAME)
	if blueprint.is_empty() or blueprint.starter or title.is_empty(): return ""
	var old_path := String(blueprint.path)
	var stem := _free_stem(slug(title), old_path.get_file().get_basename())
	blueprint.name = title
	blueprint.path = FOLDER + stem + ".json"
	blueprint.id = "own:" + stem
	if not _write(blueprint): return ""
	if old_path != String(blueprint.path):
		DirAccess.remove_absolute(old_path)
		if FileAccess.file_exists(old_path.get_basename() + ".png"):
			DirAccess.rename_absolute(old_path.get_basename() + ".png", String(blueprint.path).get_basename() + ".png")
		if _pictures.has(id):
			_pictures[blueprint.id] = _pictures[id]
			_pictures.erase(id)
	_sort()
	changed.emit()
	return String(blueprint.id)


## Deletes one of the player's blueprints, its file and picture. False for a starter.
func delete(id: String) -> bool:
	var blueprint := get_blueprint(id)
	if blueprint.is_empty() or blueprint.starter: return false
	DirAccess.remove_absolute(String(blueprint.path))
	DirAccess.remove_absolute(String(blueprint.path).get_basename() + ".png")
	_own.erase(blueprint)
	_pictures.erase(id)
	changed.emit()
	return true


## Where the player's blueprints are kept, as the computer names it.
func folder() -> String:
	return ProjectSettings.globalize_path(FOLDER)


func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	OS.shell_open(folder())


func _write(blueprint: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var file := FileAccess.open(String(blueprint.path), FileAccess.WRITE)
	if file == null:
		push_warning("BlueprintLibrary: could not keep %s: %s" % [blueprint.path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(to_text(blueprint))
	return true


## A file name not yet taken in the folder (`keep` is the blueprint's own, which it may keep).
func _free_stem(base: String, keep: String) -> String:
	var stem := base
	var n := 2
	while stem != keep and FileAccess.file_exists(FOLDER + stem + ".json"):
		stem = "%s_%d" % [base, n]
		n += 1
	return stem


# ── Pictures ──────────────────────────────────────────────────────────────────

## A blueprint's picture, or null until it is rendered; asking queues the render.
func picture(id: String) -> Texture2D:
	if not _pictures.has(id): _queue_picture(id)
	return _pictures.get(id)


func _queue_picture(id: String) -> void:
	var blueprint := get_blueprint(id)
	# A headless run (the tests) draws nothing, so it renders no pictures.
	if blueprint.is_empty() or id in _waiting or DisplayServer.get_name() == "headless": return
	# One of the player's keeps its picture beside its file, made after it.
	var png := String(blueprint.path).get_basename() + ".png"
	if not blueprint.starter and FileAccess.file_exists(png) \
			and FileAccess.get_modified_time(png) >= FileAccess.get_modified_time(String(blueprint.path)):
		var image := Image.load_from_file(png)
		if image != null and not image.is_empty():
			_pictures[id] = ImageTexture.create_from_image(image)
			return
	_waiting.append(id)
	if not _rendering: _render_waiting()


func _render_waiting() -> void:
	_rendering = true
	while not _waiting.is_empty():
		var id: String = _waiting.pop_front()
		var blueprint := get_blueprint(id)
		if blueprint.is_empty(): continue
		var image: Image = await _render(blueprint)
		if image == null or image.is_empty(): continue
		_pictures[id] = ImageTexture.create_from_image(image)
		if not blueprint.starter: image.save_png(String(blueprint.path).get_basename() + ".png")
		changed.emit()
	_rendering = false


## A blueprint seen as the icons are: the 3/4 camera from (10, 8, 12), the studio's ambient fill
## and warm key light, each block a cube in its material's colour and each floor a slab.
func _render(blueprint: Dictionary) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE * PICTURE_PIXELS * 2
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d9e4da")
	environment.environment.ambient_light_energy = 0.9
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.light_color = Color("ffe4bb")
	light.light_energy = 0.85
	light.rotation_degrees = Vector3(-52, -32, 0)
	viewport.add_child(light)
	var model := MeshInstance3D.new()
	model.mesh = _mesh(blueprint)
	viewport.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 400.0
	viewport.add_child(camera)
	var box := model.mesh.get_aabb()
	camera.position = box.get_center() + Vector3(10, 8, 12).normalized() * 150.0
	camera.look_at(box.get_center())
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in range(8):
		var local: Vector3 = camera.global_transform.affine_inverse() * box.get_endpoint(corner)
		low = Vector2(minf(low.x, local.x), minf(low.y, local.y))
		high = Vector2(maxf(high.x, local.x), maxf(high.y, local.y))
	camera.position += camera.basis * Vector3((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, 0)
	camera.size = maxf(high.x - low.x, high.y - low.y) * 1.06
	for frame in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	viewport.queue_free()
	if image == null or image.is_empty(): return null
	image.convert(Image.FORMAT_RGBA8)
	image.resize(PICTURE_PIXELS, PICTURE_PIXELS, Image.INTERPOLATE_LANCZOS)
	return image


## Cubes for blocks, the faces between blocks left out.
static func _mesh(blueprint: Dictionary) -> ArrayMesh:
	var solid := {}
	for kind: String in blueprint.blocks:
		for cell: Vector3i in blueprint.blocks[kind]: solid[cell] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for kind: String in blueprint.blocks:
		var tint := _look(kind)
		for cell: Vector3i in blueprint.blocks[kind]:
			for face: Array in FACES:
				if solid.has(cell + face[0]): continue
				for i: int in [0, 2, 1, 0, 3, 2]:
					tool.set_color(tint)
					tool.set_normal(Vector3(face[0]))
					tool.add_vertex(Vector3(cell) + face[1][i])
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	return mesh


## A material's colour: its block's, a log's bark, stone's rock grey.
static func _look(material: String) -> Color:
	var parts := material_parts(material)
	var key := String(BlockRegistry.get_construction_def(String(parts.get("kind", material))).get("block_key", STONE_LOOK))
	if not String(parts.get("wood", "")).is_empty(): key = String(BlockRegistry.log_block(parts.wood, parts.direction))
	return BlockRegistry.get_color(BlockRegistry.get_id(key), "summer")
