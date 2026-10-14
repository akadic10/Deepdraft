extends "res://scripts/tests/BedroomTest.gd"

func _setup_crafting_fixture() -> void:
	preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd").install(root.get_node("DwarfAssets"))
	await super._setup_crafting_fixture()
	preload("res://tools/furniture_pilot/FurniturePilotAssets.gd").install(furniture)
