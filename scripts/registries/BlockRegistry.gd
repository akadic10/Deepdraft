extends Node

# ── File paths ────────────────────────────────────────────────────────────────
const BLOCKS_PATH    := "res://data/terrain/terrain_blocks.json"
const PALETTES_PATH  := "res://data/terrain/surface_palettes.json"
const RESOURCES_PATH := "res://data/terrain/block_resources.json"
const CONSTRUCTION_PATH := "res://data/construction/blocks.json"
const APPEARANCE_PATH := "res://data/terrain/appearance_profiles.json"
const JsonData = preload("res://scripts/registries/JsonData.gd")

# ── Internal tables ───────────────────────────────────────────────────────────
# Keys with "__" prefix in the JSON are documentation comments — always skipped.
#
# Runtime integer IDs are session-local array indices. They must NEVER be written
# to save files. Save files always store the full namespaced StringName key.

var _key_to_id:        Dictionary = {}   # StringName  →  int
var _id_to_key:        Array      = []   # int         →  StringName
var _id_to_def:        Array      = []   # int         →  Dictionary (full block def)
var _surface_palettes: Dictionary = {}   # variant_suffix  →  { season: Color }
var _resource_defs:    Dictionary = {}
var _construction_defs: Dictionary = {}
var _appearance: Dictionary = {}
var _terrain_color_luts: Dictionary = {}
var _appearance_ids := PackedByteArray()

# Hot-path lookup tables (doc 11 Phase 1d). Built EAGERLY in _ready and never
# mutated afterwards, so WorkerThreadPool mesh builders can read them without
# any locking. get_color() / is_transparent() stay as the general API; these
# LUTs are the per-block fast path for the mesher's inner loops.
var _color_luts:      Dictionary      = {}   # season → PackedColorArray (runtime-id-indexed)

const _LUT_SEASONS := ["spring", "summer", "autumn", "winter"]

## Runtime ID of "base:terrain:void" — the zero/air value used everywhere.
## Set after _load_blocks() completes.
var AIR_ID: int = 0


func _ready() -> void:
	_load_blocks()
	_load_palettes()
	_load_resource_defs()
	_construction_defs = JsonData.read_dict(CONSTRUCTION_PATH)
	_load_appearance()
	AIR_ID = get_id(&"base:terrain:void")
	_build_luts()
	print("BlockRegistry: loaded %d block types." % _id_to_key.size())


func _build_luts() -> void:
	var count := _id_to_key.size()
	_color_luts.clear()
	for season: String in _LUT_SEASONS:
		var lut := PackedColorArray()
		lut.resize(count)
		for id in range(count):
			lut[id] = get_color(id, season)
		_color_luts[season] = lut
		var terrain_lut := PackedColorArray()
		terrain_lut.resize(count)
		for id in range(count):
			terrain_lut[id] = _terrain_color(lut[id], id)
		_terrain_color_luts[season] = terrain_lut


func _load_appearance() -> void:
	_appearance = JsonData.read_dict(APPEARANCE_PATH)
	var used_ids := {}
	for profile_name: String in _appearance.profiles:
		var profile: Dictionary = _appearance.profiles[profile_name]
		var tag := int(profile.id)
		assert(tag > 0 and tag < 8 and not used_ids.has(tag), "Invalid terrain appearance ID: "+profile_name)
		used_ids[tag] = true
		assert(float(profile.bevel_width) > 0.0 and float(profile.bevel_width) < 0.25)
		assert(float(profile.geometry_depth) >= 0.0 and float(profile.geometry_depth) < 0.1)
	_appearance_ids.resize(_id_to_def.size())
	for id in _id_to_def.size():
		var kind: String = _id_to_def[id].get("kind", "")
		var profile_name: String = _appearance.kind_profiles.get(kind, "")
		_appearance_ids[id] = int(_appearance.profiles[profile_name].id) if not profile_name.is_empty() else 0


## A dedicated terrain material opts into these tags. The ordinary get_color API
## remains opaque sRGB for UI/definitions; terrain vertices are explicitly linear.
func _terrain_color(color: Color, id: int) -> Color:
	if id < 0 or id >= _appearance_ids.size() or _appearance_ids[id] == 0: return color
	var linear := color.srgb_to_linear()
	linear.a = float(_appearance_ids[id])/16.0
	return linear


func get_terrain_color(id: int, season: String = "summer") -> Color:
	var lut := get_terrain_color_lut(season)
	return lut[id] if id >= 0 and id < lut.size() else Color.MAGENTA


func get_terrain_color_lut(season: String) -> PackedColorArray:
	return _terrain_color_luts.get(season, _terrain_color_luts.get("summer", PackedColorArray()))


func get_appearance_profile(id: int) -> Dictionary:
	if id < 0 or id >= _id_to_def.size(): return {}
	var profile_name: String = _appearance.kind_profiles.get(_id_to_def[id].get("kind", ""), "")
	return _appearance.profiles.get(profile_name, {})


func configure_terrain_material(material: ShaderMaterial) -> void:
	var surface: Array[Vector4] = []
	var shape: Array[Vector4] = []
	var dressing: Array[Vector4] = []
	surface.resize(8)
	shape.resize(8)
	dressing.resize(8)
	surface.fill(Vector4.ZERO)
	shape.fill(Vector4.ZERO)
	dressing.fill(Vector4.ZERO)
	for profile: Dictionary in _appearance.profiles.values():
		var tag := int(profile.id)
		surface[tag] = Vector4(profile.cell_variation, profile.patch_variation, profile.seam_strength, profile.bevel_width)
		shape[tag] = Vector4(profile.normal_strength, profile.geometry_depth, 0, 0)
		# Hearthblock dressing (doc 256): crack chance positive, worn chance negative.
		var dress: Dictionary = profile.get("dressing", {})
		if not dress.is_empty():
			var marks := float(dress.get("crack", 0.0)) - float(dress.get("worn", 0.0))
			dressing[tag] = Vector4(dress.get("edge", 0.0), dress.get("seam", 0.0), dress.get("flecks", 0.0), marks)
	material.set_shader_parameter("terrain_surface", true)
	material.set_shader_parameter("terrain_profiles", surface)
	material.set_shader_parameter("terrain_shapes", shape)
	material.set_shader_parameter("terrain_dressing", dressing)
	material.set_shader_parameter("terrain_detail_range", Vector3(_appearance.detail_fade.near, _appearance.detail_fade.far, _appearance.detail_fade.patch_scale))


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_blocks() -> void:
	var root := JsonData.read_dict(BLOCKS_PATH)
	var block_types: Dictionary = root.get("block_types", {})

	for raw_key: String in block_types:
		# Skip documentation-comment keys (any key starting with "__")
		if raw_key.begins_with("__"):
			continue

		var key := StringName(raw_key)
		var def  = block_types[raw_key]

		# Defensive: skip any non-dictionary value (shouldn't happen, but guard it)
		if typeof(def) != TYPE_DICTIONARY:
			continue

		var id: int = _id_to_key.size()
		_key_to_id[key] = id
		_id_to_key.append(key)
		_id_to_def.append(def)


func _load_palettes() -> void:
	# On failure, seasonal surface colors fall back to each block's hex_color.
	var root := JsonData.read_dict(PALETTES_PATH)
	for variant: String in root:
		if variant.begins_with("__"):
			continue

		var seasons = root[variant]
		if typeof(seasons) != TYPE_DICTIONARY:
			continue

		var color_map: Dictionary = {}
		for season: String in seasons:
			color_map[season] = Color(seasons[season] as String)

		_surface_palettes[variant] = color_map


func _load_resource_defs() -> void:
	var root := JsonData.read_dict(RESOURCES_PATH)
	_resource_defs.clear()
	for raw_key: String in root:
		if raw_key.begins_with("__"):
			continue

		var def = root[raw_key]
		if typeof(def) != TYPE_DICTIONARY:
			continue

		_resource_defs[StringName(raw_key)] = def


# ── Public API ────────────────────────────────────────────────────────────────

func get_construction_def(key: String) -> Dictionary:
	return _construction_defs.get(key, {})

## Every registered block key (StringName).
func block_keys() -> Array:
	return _key_to_id.keys()

## Every construction definition key.
func construction_keys() -> Array:
	return _construction_defs.keys()

## Returns the runtime integer ID for a namespaced block key.
## Returns -1 if the key is not registered.
func get_id(key: StringName) -> int:
	return _key_to_id.get(key, -1)


## Returns the permanent namespaced StringName for a runtime ID.
## Returns "" if the ID is out of range.
func get_key(id: int) -> StringName:
	if id < 0 or id >= _id_to_key.size():
		return &""
	return _id_to_key[id]


## Returns the full block definition dictionary for a key.
## Returns {} if the key is not registered.
func get_def(key: StringName) -> Dictionary:
	var id := get_id(key)
	if id < 0:
		return {}
	return _id_to_def[id]


## Returns mining/generation metadata for a block key from block_resources.json.
## Returns {} if the key has no resource definition.
func get_resource_def(key: StringName) -> Dictionary:
	return _resource_defs.get(key, {})


## Returns true if the block is physically solid (not void, not water).
## Used by the nav system for walkability. Water is NOT solid — dwarves cannot
## walk on it and physics does not collide with it.
func is_solid(id: int) -> bool:
	if id < 0 or id >= _id_to_def.size():
		return false
	var kind: String = (_id_to_def[id] as Dictionary).get("kind", "void")
	return kind != "void" and kind != "water"


## Returns true if the block is visually transparent (void only).
## Water renders as opaque blue — a face adjacent to water IS rendered,
## but water itself also emits faces (so the lake surface is visible).
## Only pure void is skipped by the mesher.
func is_transparent(id: int) -> bool:
	if id < 0 or id >= _id_to_def.size():
		return true
	var kind: String = (_id_to_def[id] as Dictionary).get("kind", "void")
	return kind == "void"


## Hot-path LUT: season → PackedColorArray indexed by runtime block ID.
## Built once at boot, read-only afterwards (safe from worker threads).
## Unknown seasons fall back to summer.
func get_color_lut(season: String) -> PackedColorArray:
	return _color_luts.get(season, _color_luts.get("summer", PackedColorArray()))


## Returns the display Color for a block at a given season.
##
## For surface grass/dirt variants, reads from surface_palettes.json.
## For all other blocks, uses the hex_color field from terrain_blocks.json.
## Falls back to Color.MAGENTA on any lookup failure (visible error sentinel).
func get_color(id: int, season: String = "summer") -> Color:
	if id < 0 or id >= _id_to_def.size():
		return Color.MAGENTA

	var def: Dictionary = _id_to_def[id]

	# Surface blocks use seasonal palettes.
	# Key format: "base:terrain:surface:grass_04" — last segment is the variant suffix.
	var key: String = _id_to_key[id]
	var parts := key.split(":")
	if parts.size() >= 1:
		var suffix: String = parts[-1]   # e.g. "grass_04", "dirt_02"
		if _surface_palettes.has(suffix):
			var palette: Dictionary = _surface_palettes[suffix]
			if palette.has(season):
				return palette[season] as Color
			# Season key missing — fall through to hex_color below.

	# All other blocks (rock, ore, gem, water, bedrock, soil): use hex_color directly.
	var hex: String = def.get("hex_color", "#FF00FF")
	return Color(hex)
