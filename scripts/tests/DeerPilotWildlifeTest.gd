extends "res://scripts/tests/DeerWildlifeTest.gd"

func _make_wildlife() -> Node3D:
	return load("res://tools/animal_pilot/AnimalPilotWildlife.gd").new()
