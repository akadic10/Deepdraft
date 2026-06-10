extends Node

## Dwarf asset + data registry autoload ("DwarfAssets" in project.godot).
##
## Owns BOTH halves of dwarf creation inputs (Registry Pattern, AGENT.md):
##   1. The ~41 modular part GLBs (doc 41b) — preloaded once, queried by key.
##      No `preload`/`load` calls for dwarf parts anywhere else in the codebase.
##   2. The three generation JSON pools — names.json / appearance.json /
##      traits.json. No other script may FileAccess these files.
##
## Parts are PackedScenes (imported GLBs), instantiated per dwarf by
## DwarfFactory. Colors are NOT baked per file: parts are authored in neutral
## near-white palettes and tinted at runtime (SKIN_TONES / HAIR_COLORS /
## EYE_COLORS below, from doc 41b).

const NAMES_PATH      := "res://data/entities/dwarves/names.json"
const APPEARANCE_PATH := "res://data/entities/dwarves/appearance.json"
const TRAITS_PATH     := "res://data/entities/dwarves/traits.json"

# ── Runtime tint palettes (doc 41b §Color Application Strategy) ───────────────

const SKIN_TONES := {
	"pale":   Color(0.96, 0.84, 0.77),
	"medium": Color(0.85, 0.65, 0.50),
	"tan":    Color(0.71, 0.50, 0.35),
	"dark":   Color(0.42, 0.28, 0.18),
}

const HAIR_COLORS := {
	"black":      Color(0.10, 0.08, 0.08),
	"dark_brown": Color(0.25, 0.15, 0.10),
	"brown":      Color(0.42, 0.26, 0.14),
	"auburn":     Color(0.58, 0.25, 0.10),
	"red":        Color(0.78, 0.22, 0.08),
	"blonde":     Color(0.88, 0.76, 0.44),
	"grey":       Color(0.62, 0.62, 0.62),
	"white":      Color(0.92, 0.92, 0.92),
}

const EYE_COLORS := {
	"grey":  Color(0.55, 0.60, 0.62),
	"blue":  Color(0.25, 0.55, 0.85),
	"green": Color(0.25, 0.65, 0.30),
	"brown": Color(0.48, 0.30, 0.12),
	"amber": Color(0.82, 0.55, 0.10),
	"red":   Color(0.80, 0.10, 0.10),
}

# ── Part tables (doc 41b §GLB File Inventory) — PackedScenes ─────────────────

var heads: Dictionary = {
	"young":  preload("res://assets/dwarves/body/head_young.glb"),
	"adult":  preload("res://assets/dwarves/body/head_adult.glb"),
	"middle": preload("res://assets/dwarves/body/head_middle.glb"),
	"elder":  preload("res://assets/dwarves/body/head_elder.glb"),
}
var eyes: PackedScene = preload("res://assets/dwarves/body/eyes.glb")
var body: PackedScene = preload("res://assets/dwarves/body/body_base.glb")
var hand: PackedScene = preload("res://assets/dwarves/body/hand.glb")
var foot: PackedScene = preload("res://assets/dwarves/body/foot.glb")

var hair_male: Dictionary = {
	"short_back":   preload("res://assets/dwarves/hair/hair_m_short_back.glb"),
	"shaved":       preload("res://assets/dwarves/hair/hair_m_shaved.glb"),
	"wild_loose":   preload("res://assets/dwarves/hair/hair_m_wild_loose.glb"),
	"braided_back": preload("res://assets/dwarves/hair/hair_m_braided_back.glb"),
	"bald":         null,
}
var hair_female: Dictionary = {
	"bun":             preload("res://assets/dwarves/hair/hair_f_bun.glb"),
	"braid_side":      preload("res://assets/dwarves/hair/hair_f_braid_side.glb"),
	"braid_long":      preload("res://assets/dwarves/hair/hair_f_braid_long.glb"),
	"short_practical": preload("res://assets/dwarves/hair/hair_f_short_practical.glb"),
	"twin_braids":     preload("res://assets/dwarves/hair/hair_f_twin_braids.glb"),
	"half_up":         preload("res://assets/dwarves/hair/hair_f_half_up.glb"),
	"loose_long":      preload("res://assets/dwarves/hair/hair_f_loose_long.glb"),
	"shaved_sides":    preload("res://assets/dwarves/hair/hair_f_shaved_sides.glb"),
	"cropped":         preload("res://assets/dwarves/hair/hair_f_cropped.glb"),
	"wild":            preload("res://assets/dwarves/hair/hair_f_wild.glb"),
}
var beards: Dictionary = {
	"full_long":     preload("res://assets/dwarves/beards/beard_full_long.glb"),
	"full_braided":  preload("res://assets/dwarves/beards/beard_full_braided.glb"),
	"short_trimmed": preload("res://assets/dwarves/beards/beard_short_trimmed.glb"),
	"forked":        preload("res://assets/dwarves/beards/beard_forked.glb"),
	"mutton_chops":  preload("res://assets/dwarves/beards/beard_mutton_chops.glb"),
	"goatee":        preload("res://assets/dwarves/beards/beard_goatee.glb"),
	"braided_long":  preload("res://assets/dwarves/beards/beard_braided_long.glb"),
}
var brows_male: Dictionary = {
	"thick_flat": preload("res://assets/dwarves/eyebrows/brows_m_thick_flat.glb"),
	"bushy":      preload("res://assets/dwarves/eyebrows/brows_m_bushy.glb"),
	"arched":     preload("res://assets/dwarves/eyebrows/brows_m_arched.glb"),
	"unibrow":    preload("res://assets/dwarves/eyebrows/brows_m_unibrow.glb"),
}
var brows_female: Dictionary = {
	"thin_arched":  preload("res://assets/dwarves/eyebrows/brows_f_thin_arched.glb"),
	"thick_flat":   preload("res://assets/dwarves/eyebrows/brows_f_thick_flat.glb"),
	"bushy":        preload("res://assets/dwarves/eyebrows/brows_f_bushy.glb"),
	"sharp_angled": preload("res://assets/dwarves/eyebrows/brows_f_sharp_angled.glb"),
}
var scars: Dictionary = {
	"cheek_slash": preload("res://assets/dwarves/scars/scar_cheek_slash.glb"),
	"brow_notch":  preload("res://assets/dwarves/scars/scar_brow_notch.glb"),
	"nose_bridge": preload("res://assets/dwarves/scars/scar_nose_bridge.glb"),
	"chin_split":  preload("res://assets/dwarves/scars/scar_chin_split.glb"),
}

# ── Generation pools (loaded once at boot) ────────────────────────────────────

var _names: Dictionary = {}        # { male: {prefixes, suffixes}, female: {...} }
var _appearance: Dictionary = {}   # { shared: {...}, male: {...}, female: {...} }
var _traits: Dictionary = {}       # { generation_config, exclusion_groups, traits }


func _ready() -> void:
	_names = _load_json(NAMES_PATH)
	_appearance = _load_json(APPEARANCE_PATH)
	_traits = _load_json(TRAITS_PATH)
	print("DwarfAssets: parts loaded; pools — names %s, appearance %s, traits %s." % [
		"ok" if not _names.is_empty() else "MISSING",
		"ok" if not _appearance.is_empty() else "MISSING",
		"ok" if not _traits.is_empty() else "MISSING",
	])


# ── Part queries ──────────────────────────────────────────────────────────────

func hair_for(appearance: DwarfAppearanceData) -> PackedScene:
	var table: Dictionary = hair_male if appearance.gender == "male" else hair_female
	return table.get(appearance.hair_style)


func brows_for(appearance: DwarfAppearanceData) -> PackedScene:
	var table: Dictionary = brows_male if appearance.gender == "male" else brows_female
	return table.get(appearance.eyebrow_style)


# ── Pool queries (read-only views; callers must not mutate) ──────────────────

func get_name_pools() -> Dictionary:
	return _names


func get_appearance_pools() -> Dictionary:
	return _appearance


func get_trait_data() -> Dictionary:
	return _traits


# ── Loader ────────────────────────────────────────────────────────────────────

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DwarfAssets: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("DwarfAssets: JSON parse error in %s — %s" % [path, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	return {}
