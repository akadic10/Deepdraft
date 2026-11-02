extends Node

## Dwarf asset + data registry autoload ("DwarfAssets" in project.godot).
##
## Owns BOTH halves of dwarf creation inputs (Registry Pattern, CLAUDE.md):
##   1. The ~41 modular part GLBs (doc 41b) — preloaded once, queried by key.
##      No `preload`/`load` calls for dwarf parts anywhere else in the codebase.
##   2. Generation pools (names/appearance/traits) and profession definitions.
##      No other script may FileAccess these files.
##
## Parts are PackedScenes (imported GLBs), instantiated per dwarf by
## DwarfFactory. Colors are NOT baked per file: parts are authored in neutral
## near-white palettes and tinted at runtime (SKIN_TONES / HAIR_COLORS /
## EYE_COLORS below, from doc 41b).

const NAMES_PATH      := "res://data/entities/dwarves/names.json"
const APPEARANCE_PATH := "res://data/entities/dwarves/appearance.json"
const TRAITS_PATH     := "res://data/entities/dwarves/traits.json"
const TASTES_PATH     := "res://data/entities/dwarves/tastes.json"
const STATS_PATH      := "res://data/entities/dwarves/stats.json"

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

## Hearthblock tunic colours (doc 256): sRGB tunic / dark (hem, cuffs) / light
## (placket). The body and cuff meshes are baked in teal and recoloured per dwarf,
## one shared mesh per colour. Order is the by-ID assignment, so neighbours differ.
const CLOTHING := {
	"teal":  {"tunic": "3F7C76", "tunic_dark": "2D5D59", "tunic_light": "5C9B91"},
	"rust":  {"tunic": "A9563B", "tunic_dark": "84412C", "tunic_light": "C47050"},
	"moss":  {"tunic": "6F8C3E", "tunic_dark": "536A2E", "tunic_light": "8CA851"},
	"slate": {"tunic": "4E6B8F", "tunic_dark": "3A516D", "tunic_light": "6B89AD"},
	"ochre": {"tunic": "B08B3A", "tunic_dark": "86692B", "tunic_light": "C9A655"},
	"plum":  {"tunic": "7B4F72", "tunic_dark": "5C3A55", "tunic_light": "98698E"},
}

# ── Part tables (doc 41b §GLB File Inventory) — PackedScenes ─────────────────

var heads: Dictionary = {
	"young":  preload("res://assets/models/characters/dwarves/body/head_young.glb"),
	"adult":  preload("res://assets/models/characters/dwarves/body/head_adult.glb"),
	"middle": preload("res://assets/models/characters/dwarves/body/head_middle.glb"),
	"elder":  preload("res://assets/models/characters/dwarves/body/head_elder.glb"),
}
var eyes: PackedScene = preload("res://assets/models/characters/dwarves/body/eyes.glb")
var body: PackedScene = preload("res://assets/models/characters/dwarves/body/body_base.glb")
var hand: PackedScene = preload("res://assets/models/characters/dwarves/body/hand.glb")
var foot: PackedScene = preload("res://assets/models/characters/dwarves/body/foot.glb")
var rest_eyelids: PackedScene = preload("res://assets/models/presentation/eyelids.glb")
var meal_servings: Dictionary = {
	"berries": preload("res://assets/models/presentation/serving_berries.glb"),
	"apple": preload("res://assets/models/presentation/serving_apple.glb"),
	"fish": preload("res://assets/models/presentation/serving_fish.glb"),
}
## Shared right-limb geometry; keep imported meshes immutable for left parts.
## Implicit work equipment: presentation only, with no inventory requirement.
var felling_axe: PackedScene = preload("res://assets/models/characters/dwarves/tools/felling_axe.glb")
var mining_pickaxe: PackedScene = preload("res://assets/models/characters/dwarves/tools/mining_pickaxe.glb")
## Fishing (doc 289): the rod in the hand, and the float and each fish on the line.
var fishing_rod: PackedScene = preload("res://assets/models/characters/dwarves/tools/fishing_rod.glb")
var fishing_float: PackedScene = preload("res://assets/models/characters/dwarves/tools/fishing_float.glb")
## Grilling (doc 290): each fresh fish on its stick, raw and grilled, by item key.
var grill_sticks: Dictionary = {
	"base:resources:fish:perch": {"raw": preload("res://assets/models/characters/dwarves/tools/grill_stick_perch.glb"),
		"grilled": preload("res://assets/models/characters/dwarves/tools/grill_stick_perch_grilled.glb")},
	"base:resources:fish:trout": {"raw": preload("res://assets/models/characters/dwarves/tools/grill_stick_trout.glb"),
		"grilled": preload("res://assets/models/characters/dwarves/tools/grill_stick_trout_grilled.glb")},
	"base:resources:fish:char": {"raw": preload("res://assets/models/characters/dwarves/tools/grill_stick_char.glb"),
		"grilled": preload("res://assets/models/characters/dwarves/tools/grill_stick_char_grilled.glb")},
	"base:resources:fish:cave_fish": {"raw": preload("res://assets/models/characters/dwarves/tools/grill_stick_cave_fish.glb"),
		"grilled": preload("res://assets/models/characters/dwarves/tools/grill_stick_cave_fish_grilled.glb")},
}
var caught_fish: Dictionary = {
	"base:resources:fish:perch": preload("res://assets/models/characters/dwarves/tools/caught_perch.glb"),
	"base:resources:fish:trout": preload("res://assets/models/characters/dwarves/tools/caught_trout.glb"),
	"base:resources:fish:char": preload("res://assets/models/characters/dwarves/tools/caught_char.glb"),
	"base:resources:fish:cave_fish": preload("res://assets/models/characters/dwarves/tools/caught_cave_fish.glb"),
}
## A Ranger's big catch on the line (doc 292): each fish's own heavier model.
var big_fish: Dictionary = {
	"base:resources:fish:perch": preload("res://assets/models/characters/dwarves/tools/big_perch.glb"),
	"base:resources:fish:trout": preload("res://assets/models/characters/dwarves/tools/big_trout.glb"),
	"base:resources:fish:char": preload("res://assets/models/characters/dwarves/tools/big_char.glb"),
	"base:resources:fish:cave_fish": preload("res://assets/models/characters/dwarves/tools/big_cave_fish.glb"),
}

var hair_male: Dictionary = {
	"short_back":   preload("res://assets/models/characters/dwarves/hair/hair_m_short_back.glb"),
	"shaved":       preload("res://assets/models/characters/dwarves/hair/hair_m_shaved.glb"),
	"wild_loose":   preload("res://assets/models/characters/dwarves/hair/hair_m_wild_loose.glb"),
	"braided_back": preload("res://assets/models/characters/dwarves/hair/hair_m_braided_back.glb"),
	"bald":         null,
}
var hair_female: Dictionary = {
	"bun":             preload("res://assets/models/characters/dwarves/hair/hair_f_bun.glb"),
	"braid_side":      preload("res://assets/models/characters/dwarves/hair/hair_f_braid_side.glb"),
	"braid_long":      preload("res://assets/models/characters/dwarves/hair/hair_f_braid_long.glb"),
	"short_practical": preload("res://assets/models/characters/dwarves/hair/hair_f_short_practical.glb"),
	"twin_braids":     preload("res://assets/models/characters/dwarves/hair/hair_f_twin_braids.glb"),
	"half_up":         preload("res://assets/models/characters/dwarves/hair/hair_f_half_up.glb"),
	"loose_long":      preload("res://assets/models/characters/dwarves/hair/hair_f_loose_long.glb"),
	"shaved_sides":    preload("res://assets/models/characters/dwarves/hair/hair_f_shaved_sides.glb"),
	"cropped":         preload("res://assets/models/characters/dwarves/hair/hair_f_cropped.glb"),
	"wild":            preload("res://assets/models/characters/dwarves/hair/hair_f_wild.glb"),
}
var beards: Dictionary = {
	"full_long":     preload("res://assets/models/characters/dwarves/beards/beard_full_long.glb"),
	"full_braided":  preload("res://assets/models/characters/dwarves/beards/beard_full_braided.glb"),
	"short_trimmed": preload("res://assets/models/characters/dwarves/beards/beard_short_trimmed.glb"),
	"forked":        preload("res://assets/models/characters/dwarves/beards/beard_forked.glb"),
	"mutton_chops":  preload("res://assets/models/characters/dwarves/beards/beard_mutton_chops.glb"),
	"goatee":        preload("res://assets/models/characters/dwarves/beards/beard_goatee.glb"),
	"braided_long":  preload("res://assets/models/characters/dwarves/beards/beard_braided_long.glb"),
}
var brows_male: Dictionary = {
	"thick_flat": preload("res://assets/models/characters/dwarves/eyebrows/brows_m_thick_flat.glb"),
	"bushy":      preload("res://assets/models/characters/dwarves/eyebrows/brows_m_bushy.glb"),
	"arched":     preload("res://assets/models/characters/dwarves/eyebrows/brows_m_arched.glb"),
	"unibrow":    preload("res://assets/models/characters/dwarves/eyebrows/brows_m_unibrow.glb"),
}
var brows_female: Dictionary = {
	"thin_arched":  preload("res://assets/models/characters/dwarves/eyebrows/brows_f_thin_arched.glb"),
	"thick_flat":   preload("res://assets/models/characters/dwarves/eyebrows/brows_f_thick_flat.glb"),
	"bushy":        preload("res://assets/models/characters/dwarves/eyebrows/brows_f_bushy.glb"),
	"sharp_angled": preload("res://assets/models/characters/dwarves/eyebrows/brows_f_sharp_angled.glb"),
}
var scars: Dictionary = {
	"cheek_slash": preload("res://assets/models/characters/dwarves/scars/scar_cheek_slash.glb"),
	"brow_notch":  preload("res://assets/models/characters/dwarves/scars/scar_brow_notch.glb"),
	"nose_bridge": preload("res://assets/models/characters/dwarves/scars/scar_nose_bridge.glb"),
	"chin_split":  preload("res://assets/models/characters/dwarves/scars/scar_chin_split.glb"),
}

# ── Generation pools (loaded once at boot) ────────────────────────────────────

var _names: Dictionary = {}        # { male: {prefixes, suffixes}, female: {...} }
var _appearance: Dictionary = {}   # { shared: {...}, male: {...}, female: {...} }
var _traits: Dictionary = {}       # { generation_config, exclusion_groups, traits }
var _tastes: Dictionary = {}       # { counts, felt, things }
var _stats: Dictionary = {}        # { words, average, shifts, per_step, groups, stats }
var _work_stats: Dictionary = {}   # kind of work -> the stat that speeds it
var _professions: Dictionary = {}
var _work_categories: Dictionary = {}
var _task_types: Dictionary = {}   # profession -> Array[int], from profession_task_types()
var _craft_tools: Dictionary = {}  # craft_tool path -> PackedScene, loaded on first use (doc 293)
var _proportions: Dictionary = {}


func _ready() -> void:
	_names = _load_json(NAMES_PATH)
	_appearance = _load_json(APPEARANCE_PATH)
	_traits = _load_json(TRAITS_PATH)
	_tastes = _load_json(TASTES_PATH)
	_stats = _load_json(STATS_PATH)
	for id: String in stat_ids():
		for kind: String in stat_definition(id).get("work", []): _work_stats[kind] = id
	_proportions = _load_json("res://data/entities/dwarves/proportions.json")
	_professions = _load_json("res://data/professions/professions.json")
	for entry: Dictionary in work_permissions():
		for type: String in entry.tasks: _work_categories[type] = String(entry.id)
	print("DwarfAssets: parts loaded; pools — names %s, appearance %s, traits %s." % [
		"ok" if not _names.is_empty() else "MISSING",
		"ok" if not _appearance.is_empty() else "MISSING",
		"ok" if not _traits.is_empty() else "MISSING",
	])


# ── Part queries ──────────────────────────────────────────────────────────────

## A saved clothing id, or one assigned from the dwarf's id so earlier saves and
## new dwarves both get varied, stable colours without changing any other roll.
func clothing_for(appearance: DwarfAppearanceData, dwarf_id: int) -> String:
	if appearance != null and CLOTHING.has(appearance.clothing): return appearance.clothing
	return CLOTHING.keys()[posmod(dwarf_id, CLOTHING.size())]


## Recolours the baked teal tunic and cuffs under `root` to `clothing`.
func dress(root: Node, clothing: String) -> void:
	if clothing == "teal" or not CLOTHING.has(clothing): return
	CraftMaterials.apply_colors(root, {"colors": CLOTHING.teal}, "clothing:" + clothing, CLOTHING[clothing])


func hair_for(appearance: DwarfAppearanceData) -> PackedScene:
	var table: Dictionary = hair_male if appearance.gender == "male" else hair_female
	return table.get(appearance.hair_style)


func brows_for(appearance: DwarfAppearanceData) -> PackedScene:
	var table: Dictionary = brows_male if appearance.gender == "male" else brows_female
	return table.get(appearance.eyebrow_style)


# ── Derived limb geometry (shared; callers must not mutate) ─────────────────

## Closed, unskinned triangle limbs use a baked X reflection with reversed
## winding. A counter-reflection on the mesh node cancels the rig's negative
## scale, so the renderer sees an ordinary positive-handed transform. The rig
## itself keeps its existing signed scale, palm anchors and animation poses.
func mirrored_limb_mesh(source: Mesh) -> ArrayMesh:
	return preload("res://scripts/components/RigidMeshReflection.gd").mirrored(source)


# ── Pool queries (read-only views; callers must not mutate) ──────────────────

func get_name_pools() -> Dictionary:
	return _names


func get_appearance_pools() -> Dictionary:
	return _appearance


func get_trait_data() -> Dictionary:
	return _traits


## Personal tastes (doc 41 "Tastes"): how many of each a dwarf has, what a found taste adds
## to the appeal they feel, and the things a taste can name with their pictures.
func get_taste_data() -> Dictionary:
	return _tastes


## Dwarf stats (doc 41 "Stats"): the five words, the starting step and the shifts that shape a new
## dwarf, the sheet's groups, and each stat's name, group, icon, description and effect.
func get_stat_data() -> Dictionary:
	return _stats


## Every stat id in stats.json, in the sheet's order.
func stat_ids() -> Array:
	return (_stats.get("stats", {}) as Dictionary).keys()


func stat_definition(id: String) -> Dictionary:
	return (_stats.get("stats", {}) as Dictionary).get(id, {})


## The highest step: one for each word.
func stat_steps() -> int:
	return (_stats.get("words", []) as Array).size()


## A step's word, Poor to Excellent.
func stat_word(step: int) -> String:
	var words: Array = _stats.get("words", [])
	return "" if words.is_empty() else String(words[clampi(step, 1, words.size()) - 1])


## The stat that speeds a kind of work (mining, felling, crafting, building), "" for none.
func work_stat(kind: String) -> String:
	return String(_work_stats.get(kind, ""))


## How fast a dwarf with these stats does a kind of work (doc 41 "Stats"): `per_step` for each step
## from Average, faster above and slower below; 1 for work no stat speeds.
func work_rate(kind: String, stats: Dictionary) -> float:
	var id := work_stat(kind)
	if id.is_empty(): return 1.0
	var average := int(_stats.get("average", 3))
	return 1.0 + (int(stats.get(id, average)) - average) * float(_stats.get("per_step", 0.0))


## A profession's main and second stat, [] when it names none.
func profession_stats(key: String) -> Array:
	return profession_definition(key).get("stats", [])


## How well a dwarf's stats suit a profession (doc 41 "Stats"): the main stat twice and the second
## once, averaged and rounded to a step. 0 when the profession names no stats.
func profession_fit(key: String, stats: Dictionary) -> int:
	var pair := profession_stats(key)
	if pair.size() < 2: return 0
	var average := int(_stats.get("average", 3))
	return roundi((2.0 * int(stats.get(pair[0], average)) + int(stats.get(pair[1], average))) / 3.0)


func get_proportions() -> Dictionary:
	return _proportions


# ── Professions and work policy ─────────────────────────────────────────────

func profession_definition(key: String) -> Dictionary:
	return _professions.get("professions", {}).get(key, {})


## Every profession id in professions.json, in file order.
func profession_ids() -> Array:
	return _professions.get("professions", {}).keys()


func promotion_entries() -> Array:
	return _professions.get("promotion_screen", [])


func work_permissions() -> Array:
	return _professions.get("work_permissions", [])


func profession_enabled(key: String) -> bool:
	# Historical "active" tags describe design readiness, not runtime support.
	return bool(profession_definition(key).get("promotion_enabled", false))


func work_category(task_name: String) -> String:
	return _work_categories.get(task_name, "")


func profession_tool(key: String) -> String:
	return String(profession_definition(key).get("required_tool", ""))


## The task types a career takes before permissions: those its `work` names (the Ranger's
## fishing, drying and hauling, doc 292), or the common work, with CRAFT for a craft section.
func profession_task_types(key: String) -> Array[int]:
	if _task_types.has(key): return _task_types[key]
	var types: Array[int] = []
	var named: Array = profession_definition(key).get("work", [])
	if named.is_empty():
		types.assign(Task.COMMON_WORK)
		if not craft_section(key).is_empty(): types.append(Task.Type.CRAFT)
	for type_name: String in named: types.append(int(Task.Type[type_name]))
	_task_types[key] = types
	return types


## A career that names its `work` does it in that order (doc 292: the Ranger dries, then
## fishes, then hauls); [] for a career that takes the common work.
func profession_work_order(key: String) -> Array[int]:
	var order: Array[int] = []
	if not profession_definition(key).get("work", []).is_empty(): order = profession_task_types(key)
	return order


## The work a career that takes the common work does before it (`work_first`, doc 293: the
## Carpenter and the Stonemason craft first); [] for the rest.
func profession_work_first(key: String) -> Array[int]:
	var first: Array[int] = []
	for type_name: String in profession_definition(key).get("work_first", []): first.append(int(Task.Type[type_name]))
	return first


## The hand tool a career's crafting swing holds (`craft_tool`, doc 293: the Carpenter's stone
## adze, the Stonemason's maul); null for the axe every other career swings.
func craft_tool(key: String) -> PackedScene:
	var path := String(profession_definition(key).get("craft_tool", ""))
	if path.is_empty(): return null
	if not _craft_tools.has(path): _craft_tools[path] = load(path)
	return _craft_tools[path]


## The kind of work a career's crafting counts as for the stats (doc 41 "Stats"): Wits'
## "crafting", or the Stonemason's Strength "stonework" (doc 293).
func craft_work(key: String) -> String:
	return String(profession_definition(key).get("craft_work", "crafting"))


## The strike a career's crafting makes: "hammer" for the Stonemason's maul on stone (doc 293),
## else the axe's "chop".
func craft_sound(key: String) -> String:
	return String(profession_definition(key).get("craft_sound", "chop"))


## Whether a career can do a Labor column's work at all; its box stays off when not.
func profession_allows(key: String, permission: String) -> bool:
	var types := profession_task_types(key)
	for entry: Dictionary in work_permissions():
		if entry.id != permission: continue
		for type_name: String in entry.tasks:
			if int(Task.Type[type_name]) in types: return true
	return false


## The crafting section whose orders a career makes, "" for none or one still planned.
func craft_section(key: String) -> String:
	var section := String(profession_definition(key).get("craft_section", ""))
	var entry: Dictionary = ContentRegistry.recipe_sections.get(section, {})
	return section if not entry.is_empty() and not bool(entry.get("planned", false)) else ""


## The career that makes a crafting section's orders, "" for none.
func section_profession(section: String) -> String:
	for key: String in profession_ids():
		if craft_section(key) == section: return key
	return ""


## Whether a career earns experience (doc 41): the Miner by the block, the Ranger by the catch.
func earns_experience(key: String) -> bool:
	return profession_definition(key).has("experience")


## Whether finishing this task type (its name, "MINE", "FISH") earns the career one experience.
func earns_by(key: String, task_name: String) -> bool:
	return String(profession_definition(key).get("experience", {}).get("earned_by", "")) == task_name


func profession_level(key: String, experience: Dictionary) -> int:
	if not earns_experience(key): return 1
	var count := maxi(0, int(experience.get(key, 0)))
	var level := 1
	for next in range(2, 6):
		if count >= experience_threshold(next, key): level = next
	return level


## The count that reaches `level`: the career's own thresholds, else the shared ones.
func experience_threshold(level: int, key := "") -> int:
	var own: Dictionary = profession_definition(key).get("experience", {}).get("thresholds", {})
	var table: Dictionary = own if not own.is_empty() else _professions.get("experience_thresholds", {})
	return int(table.get("level_%d" % level, 0))


## A career's experience words for a count (`field`: "noun", "to_go"): for one, its noun_one or
## to_go_one where the plural differs ("1 batch made", "1 more batch").
func experience_words(key: String, field: String, count: int) -> String:
	var info: Dictionary = profession_definition(key).get("experience", {})
	var plural := String(info.get(field, ""))
	if count != 1: return plural
	return String(info.get({"noun": "noun_one", "to_go": "to_go_one"}.get(field, ""), plural))


## A career's level rewards, lowest first: {level, text} and what each gives. The time saved at
## its own work comes from work_speed_bonus_per_level, worded by experience.speed_text: the
## Miner's digging, the Carpenter's and the Stonemason's crafting (doc 293).
func level_rewards(key: String) -> Array:
	var definition := profession_definition(key)
	var rewards: Array = (definition.get("experience", {}).get("rewards", []) as Array).duplicate(true)
	if definition.has("work_speed_bonus_per_level"):
		var words := String(definition.get("experience", {}).get("speed_text", "%d%% less digging time"))
		for level in range(2, 6):
			rewards.append({"level": level, "text": words % roundi((level - 1) * float(definition.work_speed_bonus_per_level) * 100.0)})
	return rewards


## What a dwarf's level gives for `field` (big_chance, season_speed): the highest earned
## reward that names it, else `default`.
func level_reward(key: String, experience: Dictionary, field: String, default: Variant = null) -> Variant:
	var level := profession_level(key, experience)
	var value: Variant = default
	for reward: Dictionary in level_rewards(key):
		if int(reward.level) <= level and reward.has(field): value = reward[field]
	return value


func mining_duration_multiplier(key: String, experience: Dictionary) -> float:
	if key != "base:profession:miner": return 1.0
	return 1.0 - (profession_level(key, experience) - 1) * float(profession_definition(key).get("work_speed_bonus_per_level", .05))


## The work time a crafting career's level leaves at its own crafts (doc 293): 5% less a level for
## the Carpenter and the Stonemason; 1 for careers that earn nothing by crafting.
func craft_duration_multiplier(key: String, experience: Dictionary) -> float:
	if not earns_by(key, "CRAFT"): return 1.0
	return 1.0 - (profession_level(key, experience) - 1) * float(profession_definition(key).get("work_speed_bonus_per_level", 0.0))


func _load_json(path: String) -> Dictionary:
	return preload("res://scripts/registries/JsonData.gd").read_dict(path)
