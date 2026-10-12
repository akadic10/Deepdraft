extends "res://scripts/systems/NavGrid.gd"

## Test-only cost oracle: explore the real movement graph without a heuristic.
func _heuristic(_a: Vector3i, _b: Vector3i) -> float:
	return 0.0

func _heuristic_to_box(_a: Vector3i, _lo: Vector3i, _hi: Vector3i) -> float:
	return 0.0
