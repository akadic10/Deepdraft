extends RefCounted

## Study/QA only. Override the existing owner in this isolated process, then
## restore immediately after assembly. Shipping pools and resources are untouched.
const DIRECTORY := "res://assets/models/characters/dwarves/"
const PARTS := {
	"head_adult":"body/head_adult", "eyes":"body/eyes", "body_base":"body/body_base",
	"hand":"body/hand", "foot":"body/foot", "hair_swept":"hair/hair_m_short_back",
	"beard_forked":"beards/beard_forked", "brows":"eyebrows/brows_m_thick_flat",
}

static func install(registry: Node) -> Dictionary:
	var saved := {}
	for key in ["heads", "eyes", "body", "hand", "foot", "hair_male", "hair_female", "beards", "brows_male", "brows_female"]:
		var original: Variant = registry.get(key)
		saved[key] = original.duplicate() if original is Dictionary else original
	for pair in [["heads","body/head_adult"],["hair_male","hair/hair_m_short_back"],["hair_female","hair/hair_m_short_back"],
		["beards","beards/beard_forked"],["brows_male","eyebrows/brows_m_thick_flat"],["brows_female","eyebrows/brows_m_thick_flat"]]:
		var table: Dictionary = registry.get(pair[0]).duplicate()
		for id in table:
			if table[id] != null: table[id] = load(DIRECTORY+pair[1]+".glb")
		registry.set(pair[0],table)
	for pair in [["eyes","body/eyes"],["body","body/body_base"],["hand","body/hand"],["foot","body/foot"]]:
		registry.set(pair[0],load(DIRECTORY+pair[1]+".glb"))
	return saved

static func restore(registry: Node, saved: Dictionary) -> void:
	for key in saved: registry.set(key,saved[key])
