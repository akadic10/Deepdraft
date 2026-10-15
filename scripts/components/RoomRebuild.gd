extends RefCounted

## Resumable, main-thread room detection. Only RoomManager publishes results.
## All world reads are tracked so a changed, already-read chunk cancels this job.
## The traversal and 4096-cell leak approximation match the original detector.
enum Stage { BOUNDARY, SEEDS, FILL, LEAK, CELLS, COLUMNS, HEAT, LIGHTS, BEDS, DONE }
var stage := Stage.BOUNDARY
var rooms := {}
var cell_to_room := {}
var read_chunks := {}
var next_room_id: int
var operations := 0
var owner: Node
var boundary := {}
var leaked := {}
var door_floors: Array
var boundary_keys: Array = []
var door_index := 0
var seed_index := 0
var offset_index := 0
var visited := {}
var door_tiles := {}
var queue: Array[Vector3i] = []
var head := 0
var cells: Array = []
var cursor := 0
var columns := {}
var column_keys: Array = []
var floor_total := 0
var floor_finished := 0
var floor_y_total := 0
var exposure := 0.0
var room := {}
var furniture_keys: Array = []
var first_bed := Vector3i.ZERO

func _init(manager: Node) -> void:
	owner = manager
	next_room_id = owner._next_room_id
	door_floors = owner._door_cells.keys()

## A batch is deliberately small; one world query remains indivisible.
func advance(deadline_usec: int, batch_size: int) -> void:
	while stage != Stage.DONE:
		for i in batch_size:
			if stage == Stage.DONE: return
			_step()
			operations += 1
		if Time.get_ticks_usec() >= deadline_usec: return

func _block_id(cell: Vector3i) -> int:
	read_chunks[Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)] = true
	return owner._block_id(cell)

func _step() -> void:
	match stage:
		Stage.BOUNDARY:
			if door_index < door_floors.size():
				var floor_cell: Vector3i = door_floors[door_index]
				for dy in range(owner.DOOR_SEAL_HEIGHT + 1):
					boundary[floor_cell + Vector3i.UP * dy] = owner._door_cells[floor_cell]
				door_index += 1
			else:
				boundary_keys = boundary.keys()
				stage = Stage.SEEDS
		Stage.SEEDS:
			if seed_index >= boundary_keys.size():
				stage = Stage.DONE
				return
			var start: Vector3i = boundary_keys[seed_index] + owner.NEIGHBOR_OFFSETS[offset_index]
			offset_index += 1
			if offset_index == owner.NEIGHBOR_OFFSETS.size():
				offset_index = 0
				seed_index += 1
			if boundary.has(start) or cell_to_room.has(start) or leaked.has(start): return
			if BlockRegistry.is_solid(_block_id(start)): return
			visited = {start: true}
			door_tiles = {}
			queue = [start]
			head = 0
			stage = Stage.FILL
		Stage.FILL:
			if head == queue.size():
				_begin_room()
				return
			var current := queue[head]
			head += 1
			for offset: Vector3i in owner.NEIGHBOR_OFFSETS:
				var next := current + offset
				if visited.has(next): continue
				if boundary.has(next):
					door_tiles[boundary[next]] = true
					continue
				if BlockRegistry.is_solid(_block_id(next)): continue
				visited[next] = true
				if visited.size() > owner.MAX_ROOM_CELLS:
					cells = visited.keys()
					cursor = 0
					stage = Stage.LEAK
					return
				queue.append(next)
		Stage.LEAK:
			if cursor < cells.size():
				leaked[cells[cursor]] = true
				cursor += 1
			else: stage = Stage.SEEDS
		Stage.CELLS:
			if cursor == cells.size():
				column_keys = columns.keys()
				cursor = 0
				stage = Stage.COLUMNS
				return
			var cell: Vector3i = cells[cursor]
			cursor += 1
			cell_to_room[cell] = next_room_id
			var column := Vector2i(cell.x, cell.z)
			if not columns.has(column) or cell.y < int(columns[column]): columns[column] = cell.y
			if not visited.has(cell + Vector3i.UP) or not visited.has(cell + Vector3i.UP * 2): return
			var id := _block_id(cell + Vector3i.DOWN)
			if not BlockRegistry.is_solid(id): return
			floor_total += 1
			if BlockRegistry.get_def(BlockRegistry.get_key(id)).get("kind", "") == "constructed_floor": floor_finished += 1
		Stage.COLUMNS:
			if cursor == column_keys.size():
				room.mean_floor_y = float(floor_y_total) / maxi(1, column_keys.size())
				room.seasonal_influence = float(owner.temperature_config.sealed_exposure) * exposure / maxi(1, column_keys.size())
				room.floor_tiles = floor_total
				room.finished_floor_tiles = floor_finished
				room.flooring_complete = floor_total > 0 and floor_finished == floor_total
				room.flooring_appeal = float(owner.appeal_config.complete_floor_bonus) if room.flooring_complete else 0.0
				furniture_keys = owner._heat_cells.keys()
				cursor = 0
				stage = Stage.HEAT
				return
			var column: Vector2i = column_keys[cursor]
			cursor += 1
			floor_y_total += int(columns[column])
			var height := WorldGenerator.get_overview_surface_height(column.x, column.y)
			var cover := maxf(0.0, float(height - int(columns[column]) - owner.DOOR_SEAL_HEIGHT))
			exposure += exp(-cover / float(owner.temperature_config.cover_damping_blocks))
		Stage.HEAT:
			if cursor < furniture_keys.size():
				var cell: Vector3i = furniture_keys[cursor]
				cursor += 1
				if visited.has(cell + Vector3i.UP): room.heat_units += int(owner._heat_cells[cell])
			else:
				furniture_keys = owner._light_cells.keys()
				cursor = 0
				stage = Stage.LIGHTS
		Stage.LIGHTS:
			if cursor < furniture_keys.size():
				var cell: Vector3i = furniture_keys[cursor]
				cursor += 1
				if visited.has(cell + Vector3i.UP): room.light_count += int(owner._light_cells[cell])
			else:
				furniture_keys = owner._bed_cells.keys()
				cursor = 0
				stage = Stage.BEDS
		Stage.BEDS:
			if cursor < furniture_keys.size():
				var origin: Vector3i = furniture_keys[cursor]
				cursor += 1
				for cell: Vector3i in owner._bed_cells[origin]:
					if not visited.has(cell + Vector3i.UP): return
				if room.bed_count == 0: first_bed = origin
				room.bed_count += 1
			else:
				if room.bed_count > 0 and room.light_count > 0 and not door_tiles.is_empty():
					if room.bed_count > 1: room.room_type = "barracks"
					else:
						room.owner_id = int(owner._bed_assignments.get(first_bed, -1))
						room.room_type = "personal_bedroom" if room.owner_id >= 0 else "bedroom"
				rooms[next_room_id] = room
				next_room_id += 1
				stage = Stage.SEEDS

func _begin_room() -> void:
	cells = visited.keys()
	cursor = 0
	columns = {}
	floor_total = 0
	floor_finished = 0
	floor_y_total = 0
	exposure = 0.0
	room = {"cells": visited, "door_cells": door_tiles, "volume": visited.size(),
		"heat_units": 0, "temp_c": 0.0, "is_frozen_vault": false,
		"bed_count": 0, "light_count": 0, "room_type": "room", "owner_id": -1}
	stage = Stage.CELLS
