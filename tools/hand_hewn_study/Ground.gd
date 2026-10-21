extends "res://tools/visual_study/StudyTerrain.gd"

## Existing block IDs, ChunkMesher and terrain shader on a flat rock fixture.
func surface_height(_x: int, _z: int) -> int:
	return 20

func create_world() -> void:
	super.create_world()
	for x in 32:
		for z in 32:
			_set_cell(Vector3i(x,20,z),stone_id)
