extends RefCounted

## Runs only after the original schema has passed validation. Conversion is
## in-memory; opening an old save never rewrites the player's file.
static func upgrade(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.schema_version) >= 2: return snapshot
	var scene: Dictionary = snapshot.scene
	var final_cells := {}
	for packed: Array in scene.mining.mined_blocks:
		final_cells[Vector3i(packed[0],packed[1],packed[2])] = "base:terrain:void"
	# Preserve the old restore precedence, resolving overlaps before writing.
	for entries: Array in [scene.water.terrain, scene.construction.built]:
		for entry: Dictionary in entries:
			final_cells[Vector3i(entry.cell[0],entry.cell[1],entry.cell[2])] = entry.block
	var edits: Array = []
	for cell: Vector3i in final_cells:
		edits.append({"cell":[cell.x,cell.y,cell.z],"block":final_cells[cell]})
	scene.terrain = {"edits":edits}
	scene.exploration = {"cells":[],"caves":[],"legacy_mined":scene.mining.mined_blocks}
	scene.mining.erase("mined_blocks")
	scene.water.erase("terrain")
	scene.construction.erase("built")
	snapshot.schema_version = 2
	return snapshot
