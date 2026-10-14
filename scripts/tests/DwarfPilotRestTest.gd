extends "res://scripts/tests/DwarfRestTest.gd"

func _run() -> void:
	# This dedicated test process uses the one pilot shape for all fixture actors.
	# It exercises existing behavior, not the unconverted appearance variants.
	preload("res://tools/dwarf_pilot/DwarfPilotAssets.gd").install(root.get_node("DwarfAssets"))
	await super._run()
