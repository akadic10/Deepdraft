extends "res://tools/visual_study/StudyTerrain.gd"

## Two room layouts on the same one-unit grid. Only this study owns these edits.
var compact := false

func surface_height(x: int, z: int) -> int:
	for room in room_rects():
		if room.grow(1).has_point(Vector2i(x,z)): return 27
	return 20

func room_rects() -> Array[Rect2i]:
	var rooms: Array[Rect2i] = [Rect2i(4,4,8,8),Rect2i(15,4,8,8)]
	if compact:
		for i in rooms.size(): rooms[i]=Rect2i(rooms[i].position+Vector2i(1,2),Vector2i(6,6))
	return rooms

func excavate_rooms() -> void:
	floor_cells.clear()
	var floor_def: Dictionary = blocks.get_construction_def("plank_floor")
	for room in room_rects():
		for x in range(room.position.x, room.end.x):
			for z in range(room.position.y, room.end.y):
				for y in range(21, 25): _set_cell(Vector3i(x, y, z), blocks.AIR_ID)
				var cell := Vector3i(x, 20, z)
				_set_cell(cell, blocks.get_id(floor_def.block_key))
				floor_cells[ORIGIN + cell] = "plank_floor"
	for x in [7, 8, 18, 19]:
		for z in range(12, 15):
			for y in range(21, 25): _set_cell(Vector3i(x, y, z), blocks.AIR_ID)
	# Open the display-facing wall down to a low sill to show room proportions.
	# This is a fixed cutaway in both layouts, not a changed production slice rule.
	for x in range(3, 24):
		for z in range(12, 15):
			for y in range(22, 25): _set_cell(Vector3i(x, y, z), blocks.AIR_ID)


func fingerprint() -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for x in range(2, 4):
		for z in range(2, 4):
			for y in range(2): digest.update(var_to_bytes(world.get_chunk(x, y, z).blocks))
	return digest.finish().hex_encode()
