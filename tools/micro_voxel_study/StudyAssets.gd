extends RefCounted

## Temporary registry substitution for assembly in the isolated review process.
const ROOT := "res://assets/models/studies/micro_voxel_16/"

static func install() -> Dictionary:
	var saved := {}
	for key in ["heads","eyes","body","hand","foot","hair_male","beards","brows_male","_proportions"]:
		saved[key] = DwarfAssets.get(key)
	for pair in [["heads","head"],["hair_male","hair"],["beards","beard"],["brows_male","brows"]]:
		var table: Dictionary = DwarfAssets.get(pair[0]).duplicate()
		for id in table:
			if table[id] != null: table[id] = load(ROOT+"dwarf/"+pair[1]+".glb")
		DwarfAssets.set(pair[0],table)
	for key in ["eyes","body","hand","foot"]: DwarfAssets.set(key,load(ROOT+"dwarf/"+key+".glb"))
	var proportions: Dictionary = DwarfAssets.get_proportions().duplicate()
	proportions.body_width = 1.0
	proportions.head_width = 1.0
	proportions.relaxed_hand_inset = .25
	proportions.relaxed_foot_inset = .0625
	DwarfAssets._proportions = proportions
	return saved

static func restore(saved: Dictionary) -> void:
	for key in saved: DwarfAssets.set(key,saved[key])

static func deer_parts() -> Dictionary:
	var parts := {}
	for key in ["body","neck","head","ears","antlers","leg"]:
		parts[key] = load(ROOT+"deer/"+key+".glb")
	return parts
