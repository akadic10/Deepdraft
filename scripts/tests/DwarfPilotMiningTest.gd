extends "res://scripts/tests/MiningAnimationTest.gd"

func _setup_mining_fixture() -> void:
	var assets := preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd")
	var owner := root.get_node("DwarfAssets")
	var saved: Dictionary = assets.install(owner)
	await super._setup_mining_fixture()
	assets.restore(owner,saved)
