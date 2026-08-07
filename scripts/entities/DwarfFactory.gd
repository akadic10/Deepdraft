class_name DwarfFactory
extends RefCounted

## Procedural dwarf generation (doc 41 §Dwarf Generation, doc 41b).
##
## All rolls are DETERMINISTIC (Hard Rule 8 applied to the roster, per doc 41):
## one RandomNumberGenerator seeded from (world_seed, birth_index) per dwarf,
## so the same world always produces the same sequence of dwarves. Never call
## global randi()/randf() here.
##
## DwarfFactory generates DATA. Scene assembly lives on DwarfAgent.setup() —
## the factory's spawn helper just instantiates the agent and hands the data
## over. Pools come from the DwarfAssets autoload (the owning registry for
## names/appearance/traits JSON).

const WORKER_KEY := "base:profession:worker"

## Profession keys initialised on every new dwarf (doc 41 §Agent Fields).
## Must stay aligned with data/professions/professions.json (drift fixed
## 2026-08-07: carpenter was missing here while present in the JSON;
## weaponsmith/armorsmith stubs were added to the JSON — docs 41/44 define
## them as Blacksmith Level 3 promotions, so their keys belong in every
## dwarf's experience dict from day one; promotion copies the blacksmith
## count into them, doc 44 §Experience Carry-Over).
const PROFESSION_KEYS: Array[String] = [
	"base:profession:worker",
	"base:profession:miner",
	"base:profession:farmer",
	"base:profession:brewer",
	"base:profession:builder",
	"base:profession:merchant",
	"base:profession:innkeeper",
	"base:profession:carpenter",
	"base:profession:blacksmith",
	"base:profession:weaponsmith",
	"base:profession:armorsmith",
]


## Rolls one dwarf's full data set. (Instance method, not static: autoload
## access — WorldGenerator, DwarfAssets — is unreliable from static functions;
## callers hold a DwarfFactory.new() instance.)
##   birth_index — 0-based roster position in this world (drives the seed)
##   used_names  — Dictionary[String -> true] of names already assigned;
##                 mutated: the chosen name is added.
## Returns: { name, gender, appearance: DwarfAppearanceData,
##            traits: Array[String], profession, profession_experience }
func generate(birth_index: int, used_names: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _dwarf_seed(WorldGenerator.world_seed, birth_index)

	var gender := "male" if rng.randf() < 0.5 else "female"
	var dwarf_name := _roll_name(gender, birth_index, used_names, rng)
	var appearance := _roll_appearance(gender, rng)
	var traits := _roll_traits(rng)

	var experience := {}
	for key in PROFESSION_KEYS:
		experience[key] = 0
	# Workers start with a small random task count so new arrivals aren't all
	# identical level-1 dwarves (doc 41).
	experience[WORKER_KEY] = rng.randi_range(0, 9)

	return {
		"name": dwarf_name,
		"gender": gender,
		"appearance": appearance,
		"traits": traits,
		"profession": WORKER_KEY,
		"profession_experience": experience,
	}


## Instantiates a DwarfAgent for already-rolled data. The caller adds it to the
## tree and positions it.
func spawn(data: Dictionary, dwarf_id: int) -> DwarfAgent:
	var agent := DwarfAgent.new()
	agent.setup(dwarf_id, data)
	return agent


# ── Seed mixing ───────────────────────────────────────────────────────────────

static func _dwarf_seed(world_seed: int, birth_index: int) -> int:
	var h := int(world_seed) * 2654435761 + 0x9E3779B9
	h ^= (birth_index + 1) * 83492791
	h ^= (h >> 13)
	h *= 1274126177
	h ^= (h >> 16)
	return h


# ── Name (doc 41: prefix + suffix; re-roll on collision; Roman fallback) ──────

func _roll_name(gender: String, birth_index: int,
		used_names: Dictionary, rng: RandomNumberGenerator) -> String:
	var pools: Dictionary = DwarfAssets.get_name_pools().get(gender, {})
	var prefixes: Array = pools.get("prefixes", [])
	var suffixes: Array = pools.get("suffixes", [])
	if prefixes.is_empty() or suffixes.is_empty():
		return "Dwarf %d" % (birth_index + 1)

	var candidate := ""
	for _attempt in range(10):
		candidate = String(prefixes[rng.randi_range(0, prefixes.size() - 1)]) \
			+ String(suffixes[rng.randi_range(0, suffixes.size() - 1)])
		if not used_names.has(candidate):
			used_names[candidate] = true
			return candidate
	# Pool effectively exhausted (~500 same-gender dwarves): Roman-numeral
	# birth-order fallback, expected never in normal play (doc 41).
	candidate = "%s %s" % [candidate, _roman(birth_index + 1)]
	used_names[candidate] = true
	return candidate


static func _roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	var v := n
	for i in vals.size():
		while v >= vals[i]:
			out += syms[i]
			v -= vals[i]
	return out


# ── Appearance (doc 41 §Appearance Generation) ───────────────────────────────

func _roll_appearance(gender: String, rng: RandomNumberGenerator) -> DwarfAppearanceData:
	var pools: Dictionary = DwarfAssets.get_appearance_pools()
	var shared: Dictionary = pools.get("shared", {})
	var gendered: Dictionary = pools.get(gender, {})

	var a := DwarfAppearanceData.new()
	a.gender = gender
	a.skin_tone = _weighted_id(shared.get("skin_tone", []), rng, "medium")
	a.eye_color = _weighted_id(shared.get("eye_color", []), rng, "grey")
	a.hair_color = _weighted_id(shared.get("hair_color", []), rng, "brown")
	a.age_tier = _weighted_id(shared.get("age_tier", []), rng, "adult")
	a.scar = _weighted_id(shared.get("scar", []), rng, "none")
	a.hair_style = _weighted_id(gendered.get("hair_style", []), rng,
		"short_back" if gender == "male" else "bun")
	a.eyebrow_style = _weighted_id(gendered.get("eyebrow_style", []), rng, "thick_flat")

	a.beard_style = ""
	if gender == "male":
		var beard: Dictionary = gendered.get("beard", {})
		if rng.randf() < float(beard.get("beard_probability", 0.85)):
			a.beard_style = _weighted_id(beard.get("styles", []), rng, "full_long")
	return a


## Weighted pick over an array of { id, weight (default 1) } entries.
static func _weighted_id(options: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	var total := 0.0
	for opt in options:
		if opt is Dictionary:
			total += float((opt as Dictionary).get("weight", 1.0))
	if total <= 0.0:
		return fallback
	var r := rng.randf() * total
	var acc := 0.0
	for opt in options:
		if not (opt is Dictionary):
			continue
		acc += float((opt as Dictionary).get("weight", 1.0))
		if r <= acc:
			return String((opt as Dictionary).get("id", fallback))
	return fallback


# ── Traits (doc 41 §Trait Assignment) ────────────────────────────────────────

func _roll_traits(rng: RandomNumberGenerator) -> Array[String]:
	var data: Dictionary = DwarfAssets.get_trait_data()
	var config: Dictionary = data.get("generation_config", {})
	var all_traits: Dictionary = data.get("traits", {})

	# 1. Slot distribution (weighted bucket roll).
	var buckets := {
		"no_traits": Vector2i(0, 0),                 # (positive, negative) slots
		"one_negative": Vector2i(0, 1),
		"one_positive": Vector2i(1, 0),
		"one_positive_one_negative": Vector2i(1, 1),
		"two_positive": Vector2i(2, 0),
		"two_positive_one_negative": Vector2i(2, 1),
	}
	var total := 0.0
	for key in buckets:
		total += float(config.get(key, 0))
	var slots := Vector2i.ZERO
	if total > 0.0:
		var r := rng.randf() * total
		var acc := 0.0
		for key in buckets:
			acc += float(config.get(key, 0))
			if r <= acc:
				slots = buckets[key]
				break

	# 2. Split pools by polarity (deterministic iteration: sorted keys).
	var positive: Array[String] = []
	var negative: Array[String] = []
	var keys := all_traits.keys()
	keys.sort()
	for key in keys:
		if String(key).begins_with("__"):
			continue
		var def: Dictionary = all_traits[key]
		if String(def.get("polarity", "")) == "positive":
			positive.append(String(key))
		elif String(def.get("polarity", "")) == "negative":
			negative.append(String(key))

	# 3. Fill slots, honouring exclusion groups (re-roll from the remaining
	#    eligible pool on conflict — doc 41).
	var chosen: Array[String] = []
	var used_groups: Dictionary = {}
	for _i in range(slots.x):
		_fill_trait_slot(positive, all_traits, chosen, used_groups, rng)
	for _i in range(slots.y):
		_fill_trait_slot(negative, all_traits, chosen, used_groups, rng)
	return chosen


static func _fill_trait_slot(pool: Array[String], all_traits: Dictionary,
		chosen: Array[String], used_groups: Dictionary, rng: RandomNumberGenerator) -> void:
	var eligible: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for key in pool:
		if key in chosen:
			continue
		var def: Dictionary = all_traits[key]
		var group := String(def.get("exclusion_group", ""))
		if group != "" and used_groups.has(group):
			continue
		var w := float(def.get("rarity_weight", 1.0))
		eligible.append(key)
		weights.append(w)
		total += w
	if eligible.is_empty() or total <= 0.0:
		return
	var r := rng.randf() * total
	var acc := 0.0
	for i in eligible.size():
		acc += weights[i]
		if r <= acc:
			var key := eligible[i]
			chosen.append(key)
			var group := String((all_traits[key] as Dictionary).get("exclusion_group", ""))
			if group != "":
				used_groups[group] = true
			return
