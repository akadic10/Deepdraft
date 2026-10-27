extends RefCounted

## A dwarf's personal tastes (doc 41 "Tastes"): a few furniture designs and woods they love,
## like or dislike (tastes.json), given when the dwarf is created and kept for life. A taste
## is found the first time the dwarf uses the thing; from then on it changes the appeal that
## dwarf feels in a room holding it, and the room's thought names the strongest. Saved with
## the dwarf as namespaced ids (`tastes`), with the ones found (`found_tastes`).
const VERBS := {"love": "loves", "like": "likes", "dislike": "dislikes"}
var tastes := {}   # thing id -> "love", "like" or "dislike"
var found := {}    # thing id -> true


func setup(given: Dictionary, already: Array) -> void:
	tastes = given.duplicate()
	found.clear()
	for id: Variant in already:
		if tastes.has(String(id)): found[String(id)] = true


## The dwarf uses these pieces (a bed slept in, a seat, a table, a board): each design and
## wood they hold a taste for and had not found yet, as [{id, kind}], now found.
func meet(pieces: Array) -> Array[Dictionary]:
	var news: Array[Dictionary] = []
	for piece: Variant in pieces:
		if piece == null: continue
		for id: String in [String(piece.furniture_key), String(piece.material_id)]:
			if id.is_empty() or not tastes.has(id) or found.has(id): continue
			found[id] = true
			news.append({"id": id, "kind": String(tastes[id])})
	return news


## The appeal this dwarf feels in a room (RoomManager.room_appeal): its score with each found
## taste for something in it (a design, or anything of the wood) added once, that score's
## word, and the strongest such taste to name ("" for none).
func felt(appeal: Dictionary) -> Dictionary:
	var score := float(appeal.get("score", 0.0))
	var effects: Dictionary = DwarfAssets.get_taste_data().get("felt", {})
	var counted := {}
	var named := ""
	for part: Dictionary in appeal.get("parts", []):
		for id: String in [String(part.get("key", "")), String(part.get("material", ""))]:
			if id.is_empty() or counted.has(id) or not found.has(id): continue
			counted[id] = true
			var effect := float(effects.get(tastes[id], 0.0))
			score += effect
			if named.is_empty() or absf(effect) > absf(float(effects.get(tastes[named], 0.0))): named = id
	return {"score": score, "word": RoomManager.appeal_step(score), "taste": named}


## How a taste reads in a sentence: "loves the log bed", "dislikes pine".
func describe(id: String) -> String:
	var verb := String(VERBS.get(tastes.get(id, ""), "knows"))
	return "%s %s" % [verb, thing_name(id)] if is_material(id) else "%s the %s" % [verb, thing_name(id)]


## A thing's name in a sentence: a design's in lower case ("log stool"), a wood's ("pine").
func thing_name(id: String) -> String:
	return display_name(id).to_lower()


## A thing's name on its own: "Log bed", "Juniper".
func display_name(id: String) -> String:
	if is_material(id): return CraftMaterials.material_name(id)
	return String(ContentRegistry.furniture_def(id).get("display_name", id.get_slice(":", 2).capitalize()))


## A wood (any craft material) rather than a furniture design.
func is_material(id: String) -> bool:
	return CraftMaterials.definitions.has(id)
