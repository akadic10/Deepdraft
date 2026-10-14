extends RefCounted

## Study/QA only. Definitions still come from FurniturePlacementController.
const DIRECTORY := "res://assets/models/furniture/"
const PARTS := ["log_chair","log_bed","door"]

static func install(owner: Node) -> Dictionary:
	var saved := {}
	for part in PARTS:
		var key: String="base:furniture:"+part
		saved[key]=owner.get_defs()[key]
		var definition: Dictionary=saved[key].duplicate(true)
		definition.model=DIRECTORY+part+".glb"
		owner.get_defs()[key]=definition
	return saved

static func restore(owner: Node, saved: Dictionary) -> void:
	for key in saved: owner.get_defs()[key]=saved[key]

