extends "res://scripts/tests/CraftMaterialTest.gd"

func _setup_crafting_fixture() -> void:
	await super._setup_crafting_fixture()
	preload("res://tools/furniture_pilot/FurniturePilotAssets.gd").install(furniture)
