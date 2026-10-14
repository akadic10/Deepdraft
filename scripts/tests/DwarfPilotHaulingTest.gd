extends "res://scripts/tests/HaulingAnimationTest.gd"

func _new_trip(key := ACORN, amount := 12) -> void:
	var assets := preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd")
	var owner := root.get_node("DwarfAssets")
	var saved: Dictionary = assets.install(owner)
	await super._new_trip(key,amount)
	assets.restore(owner,saved)
