extends "res://scripts/tests/FlowerPilotTest.gd"


func _run() -> void:
	category = "reeds"
	clear_label = "Clear reeds"
	activity = "Clearing reeds"
	max_height = 2.0
	variants = 2
	review_dir = "reed_review"
	await super._run()
