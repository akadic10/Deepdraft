extends "res://scripts/systems/WildlifeManager.gd"

## Dedicated test owner; gameplay definitions and all other species stay live.
func _ready() -> void:
	super._ready()
	_deer_models=preload("AnimalPilotAssets.gd").models()
