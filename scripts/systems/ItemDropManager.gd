class_name ItemDropManager
extends Node3D

## Spawns and owns dropped-item entities (doc 16 step 6 v1: simple inert
## micro-voxel nodes — hauling, stacking, and pickup are a later milestone).
## Scene node in debug_world.tscn (presentation lives in the scene, not an
## autoload — the SurfaceFloraSpawner pattern), found by producers via the
## "item_drop_manager" group.
##
## REGISTRY PATTERN (AGENT.md): this node is the ONE owner of
## data/entities/items/resources.json — no other script may open it. Item defs
## load lazily on first spawn (the file's own contract: "loaded on demand, NOT
## held in memory at boot").
##
## VISUALS (doc 61 §5.7): item GLBs are authored at 8 vox/block with the 0.125
## scale baked into vertex positions — instanced at scale 1.0 with the
## project-standard vertex-colour material (lit per-pixel, double-sided).
##
## SLICE RULE (doc 11 Phase 5): drops obey the slice like flora and dwarves —
## hidden when their block is above the cut.

@export var slice_controller_path: NodePath

const RESOURCES_PATH := "res://data/entities/items/resources.json"
const SLICE_OFF_Y := 127
const REST_SCAN_DEPTH := 8   # blocks scanned downward for a resting floor

var _defs: Dictionary = {}          # item key (String) -> def Dictionary
var _defs_loaded: bool = false
var _scene_cache: Dictionary = {}   # model path -> PackedScene (null cached as absent)
var _material: StandardMaterial3D = null
var _slice_y: int = SLICE_OFF_Y
var _drop_count: int = 0
var _missing_models: Dictionary = {}   # path -> true (warn once per model)


func _ready() -> void:
	add_to_group("item_drop_manager")
	var slice_controller := get_node_or_null(slice_controller_path)
	if slice_controller != null and slice_controller.has_signal("slice_changed"):
		slice_controller.connect("slice_changed", _on_slice_changed)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic = 0.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


# ── Public API ────────────────────────────────────────────────────────────────

## Spawns `count` units of an item at a mined block position. The drop rests
## on the first solid floor at or below the block (mined columns drop their
## loot to the pit floor). Position jitter and yaw are cosmetic randomness —
## runtime behaviour, not worldgen (Hard Rule 8 does not apply to drops).
func spawn_drop(item_key: String, count: int, block: Vector3i) -> void:
	if count <= 0:
		return
	_ensure_defs()
	var def: Dictionary = _defs.get(item_key, {})
	if def.is_empty():
		push_warning("ItemDropManager: unknown item '%s' — drop skipped." % item_key)
		return
	var scene := _model_scene(String(def.get("model", "")))
	var rest_y := _rest_y(block)
	for i in range(count):
		var node := _build_drop_node(item_key, scene)
		var jitter := Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
		node.position = Vector3(float(block.x) + 0.5, float(rest_y), float(block.z) + 0.5) + jitter
		node.rotation.y = randf_range(0.0, TAU)
		node.set_meta("base_y", rest_y)
		# Same rule as DwarfAgent.apply_slice: floor(position.y) <= slice_y.
		node.visible = rest_y <= _slice_y
		add_child(node)
		_drop_count += 1


func get_stats() -> Dictionary:
	return { "drops": _drop_count }


# ── Internals ─────────────────────────────────────────────────────────────────

func _build_drop_node(item_key: String, scene: PackedScene) -> Node3D:
	var node: Node3D = null
	if scene != null:
		node = scene.instantiate() as Node3D
	if node == null:
		# Fallback: a small neutral cube so a missing model is visible, not silent.
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		mesh_instance.mesh = box
		node = mesh_instance
	node.name = "Drop_%s_%d" % [item_key.get_slice(":", item_key.get_slice_count(":") - 1), _drop_count]
	_apply_material(node)
	return node


func _apply_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _material
	for child in node.get_children():
		_apply_material(child)


## Top face of the first solid block at or below the drop position.
func _rest_y(block: Vector3i) -> int:
	for k in range(1, REST_SCAN_DEPTH + 1):
		var y := block.y - k
		if y < 0:
			break
		if BlockRegistry.is_solid(_block_id(block.x, y, block.z)):
			return y + 1
	return block.y


func _block_id(wx: int, wy: int, wz: int) -> int:
	@warning_ignore("integer_division")
	if WorldData.chunk_exists(wx / 16, wy / 16, wz / 16):
		return WorldData.get_block(wx, wy, wz)
	return WorldGenerator.get_generated_block_id(wx, wy, wz)


func _model_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	if scene == null and not _missing_models.has(path):
		_missing_models[path] = true
		push_warning("ItemDropManager: model missing at '%s' — using fallback cube." % path)
	_scene_cache[path] = scene
	return scene


func _ensure_defs() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	var file := FileAccess.open(RESOURCES_PATH, FileAccess.READ)
	if file == null:
		push_error("ItemDropManager: cannot open %s." % RESOURCES_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ItemDropManager: JSON parse error in %s — %s" % [RESOURCES_PATH, json.get_error_message()])
		return
	var root: Dictionary = json.data
	for raw_key: String in root:
		if raw_key.begins_with("__"):
			continue
		var def = root[raw_key]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		_defs[raw_key] = def
	print("ItemDropManager: loaded %d item definitions." % _defs.size())


# ── Slice culling (doc 11 Phase 5 — same hook as flora and dwarves) ──────────

func _on_slice_changed(new_slice_y: int) -> void:
	if new_slice_y == _slice_y:
		return
	_slice_y = new_slice_y
	for child in get_children():
		if child is Node3D and child.has_meta("base_y"):
			(child as Node3D).visible = int(child.get_meta("base_y")) <= _slice_y
