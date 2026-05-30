extends Node

# ── File paths ────────────────────────────────────────────────────────────────
const BLOCKS_PATH   := "res://data/terrain/terrain_blocks.json"
const PALETTES_PATH := "res://data/terrain/surface_palettes.json"

# ── Internal tables ───────────────────────────────────────────────────────────
# Keys with "__" prefix in the JSON are documentation comments — always skipped.
#
# Runtime integer IDs are session-local array indices. They must NEVER be written
# to save files. Save files always store the full namespaced StringName key.

var _key_to_id:        Dictionary = {}   # StringName  →  int
var _id_to_key:        Array      = []   # int         →  StringName
var _id_to_def:        Array      = []   # int         →  Dictionary (full block def)
var _surface_palettes: Dictionary = {}   # variant_suffix  →  { season: Color }

## Runtime ID of "base:terrain:void" — the zero/air value used everywhere.
## Set after _load_blocks() completes.
var AIR_ID: int = 0


func _ready() -> void:
	_load_blocks()
	_load_palettes()
	AIR_ID = get_id(&"base:terrain:void")
	print("BlockRegistry: loaded %d block types." % _id_to_key.size())


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_blocks() -> void:
	var file := FileAccess.open(BLOCKS_PATH, FileAccess.READ)
	if file == null:
		push_error("BlockRegistry: cannot open %s (error %d)" % [BLOCKS_PATH, FileAccess.get_open_error()])
		return

	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("BlockRegistry: JSON parse error in %s — %s" % [BLOCKS_PATH, json.get_error_message()])
		return

	var root: Dictionary       = json.data
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
	var file := FileAccess.open(PALETTES_PATH, FileAccess.READ)
	if file == null:
		push_warning("BlockRegistry: cannot open %s — seasonal surface colors will use hex_color fallback." % PALETTES_PATH)
		return

	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("BlockRegistry: JSON parse error in %s — %s" % [PALETTES_PATH, json.get_error_message()])
		return

	var root: Dictionary = json.data

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


# ── Public API ────────────────────────────────────────────────────────────────

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
