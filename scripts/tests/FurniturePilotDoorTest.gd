extends "res://scripts/tests/LogFurnitureTest.gd"

func _run() -> void:
	await super._run()
	if failures.is_empty(): print("FURNITURE_PILOT_DOOR_OK")

func _setup_crafting_fixture() -> void:
	preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd").install(root.get_node("DwarfAssets"))
	await super._setup_crafting_fixture()
	preload("res://tools/furniture_pilot/FurniturePilotAssets.gd").install(furniture)
