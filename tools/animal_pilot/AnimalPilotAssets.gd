extends RefCounted

## Study/QA only. The live WildlifeManager remains the definition/model owner.
const DIRECTORY := "res://assets/models/animals/deer/"

static func models() -> Dictionary:
	var result := {}
	for part in ["body","neck","head","ears","antlers","leg"]:
		result[part]=load(DIRECTORY+part+".glb")
	return result
