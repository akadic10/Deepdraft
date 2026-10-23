extends RefCounted

## Bounded, read-only queries of live habitat. Never reveals a cave or creates
## animals/water. All timers and source choices belong to AmbientAudio.
const Wolf := preload("res://scripts/entities/WolfAgent.gd")

func scan(focus: Vector3, slice_y: int, radius: int, flora: Node, wildlife: Node) -> Dictionary:
	var result := {}
	if WaterManager.initialized:
		for x in range(maxi(0, floori(focus.x) - radius), mini(WorldData.WORLD_SIZE_X, floori(focus.x) + radius + 1)):
			for z in range(maxi(0, floori(focus.z) - radius), mini(WorldData.WORLD_SIZE_Z, floori(focus.z) + radius + 1)):
				if Vector2(x + .5 - focus.x, z + .5 - focus.z).length_squared() > radius * radius: continue
				# Dry ground: a first spans() lookup per column cost up to 79 ms
				# per scan when the camera reached new ground (2026-10-22).
				if not WaterManager.water_columns.has(Vector2i(x, z)): continue
				for span: Vector2i in WaterManager.flow.spans(Vector2i(x, z)):
					var key := Vector3i(x, span.x, z)
					if WaterManager.flow.volume(key) < WaterManager.standing_depth: continue
					var level: float = WaterManager.flow.level(key)
					if level > slice_y + 1 or absf(level - focus.y) > 6: continue
					var point := Vector3(x + .5, level + .05, z + .5)
					if level <= WorldGenerator.get_surface_y(x, z):
						var cave := WorldGenerator.get_cave_id(Vector3i(x, ceili(level), z))
						if cave >= 0 and InteriorTracker.is_cave_discovered(cave): _nearest(result, "drips", point, focus)
						continue
					for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var bank := Vector3i(x + direction.x, floori(level - .1), z + direction.y)
						if bank.x < 0 or bank.z < 0 or bank.x >= WorldData.WORLD_SIZE_X or bank.z >= WorldData.WORLD_SIZE_Z: continue
						if BlockRegistry.is_solid(WorldData.get_terrain_block(bank.x, bank.y, bank.z)):
							_nearest(result, "shoreline", point, focus)
							_nearest(result, "frogs", point, focus)
							break
	if is_instance_valid(flora) and flora.has_method("ambient_trees"):
		for tree: Node3D in flora.ambient_trees(focus, radius):
			if tree.global_position.y > slice_y or absf(tree.global_position.y - focus.y) > 10: continue
			_nearest(result, "creaks", tree.global_position + Vector3.UP * 2, focus, tree)
	if is_instance_valid(wildlife):
		for animal in wildlife.animals:
			if not eligible_wolf(animal, slice_y): continue
			if animal.global_position.distance_to(focus) < radius * 3:
				_nearest(result, "wolves", animal.global_position + Vector3.UP, focus, animal)
	return result

func eligible_wolf(animal: Node, slice_y: int) -> bool:
	return is_instance_valid(animal) and animal is Wolf and animal.is_inside_tree() \
		and not animal.is_queued_for_deletion() and animal.is_visible_in_tree() \
		and animal.global_position.y <= slice_y \
		and animal.activity in ["Idle", "Prowling", "Searching", "Resting"]

func _nearest(result: Dictionary, kind: String, point: Vector3, focus: Vector3, node: Node3D = null) -> void:
	var distance := point.distance_to(focus)
	if not result.has(kind) or distance < float(result[kind].distance):
		result[kind] = {"point": point, "distance": distance}
		if node != null: result[kind].node = weakref(node)
