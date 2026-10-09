extends SceneTree

const SEEDS := [0, 1, 2, 7, 42, 1234, 65535, 20261007]
const REVIEW_SEEDS := [17,91,2026,8675309]
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var generator := root.get_node("WorldGenerator")
	var world := root.get_node("WorldData")
	var flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var reports: Array = []
	var review := "--review" in OS.get_cmdline_user_args()
	var seeds: Array = SEEDS.duplicate()
	if review: seeds.append_array(REVIEW_SEEDS)
	for seed_value: int in seeds:
		world.clear_world()
		generator._reset_generation_state()
		generator.world_seed = seed_value
		generator._cache_block_ids()
		generator._layout_profile = generator.load_macro_layout_profile()
		generator._build_noise_instances()
		generator._build_seeded_maps()
		generator._apply_edge_detail()
		generator._validate_finished_layout()
		generator._maps_ready = true
		_expect(generator._layout_validation.errors.is_empty(), "terrain guarantees seed %d" % seed_value)
		var terrain_before := hash(generator.heightmap)
		var water_before := hash(generator.waterline_map)
		var trees_before := _tree_fingerprint(flora)
		var forward = load("res://scripts/systems/SurfaceDetailManager.gd").new()
		scene.add_child(forward)
		forward.set_process(false)
		forward.initialize_layout()
		var records := _snapshot(forward)
		var report: Dictionary = forward.diagnostics.duplicate(true)
		if review: report["census"] = load("res://tools/SurfaceDetailCensus.gd").summarize(forward)
		var lowland := 0
		var upland := 0
		var scree := 0
		var reeds_by_water := {"lake":0,"tarn":0}
		var scree_columns: Dictionary = {}
		var planted_areas: Dictionary = {}
		for record: Dictionary in forward._records.values():
			var definition: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition(record.definition)
			if definition.has("planting_radius"):
				var area: AABB = load("res://scripts/components/SurfaceDetailPlacement.gd").planting_area(definition, record.origin)
				for x in range(int(area.position.x),int(area.end.x)):
					for z in range(int(area.position.z),int(area.end.z)):
						for y in range(int(area.position.y),int(area.end.y)):
							var cell := Vector3i(x,y,z)
							_expect(not planted_areas.has(cell), "bush/flower 3x3 areas never overlap")
							planted_areas[cell] = record.id
			if definition.get("kind") == "shrub": _expect(record.origin.y < 44, "wild berries stay below the mountain boundary")
			if record.habitat == "cliff_foot":
				scree += 1
				_expect(int(record.occupancy) < 0, "scree never registers navigation occupancy")
				var near_high := false
				for dx in range(-9, 10):
					for dz in range(-9, 10):
						if generator.get_surface_y(clampi(record.origin.x+dx,0,1023),clampi(record.origin.z+dz,0,1023)) >= record.origin.y + 4: near_high = true
				_expect(near_high, "scree has a nearby higher cliff")
				for x in range(record.origin.x, record.origin.x+int(definition.footprint)):
					for z in range(record.origin.z, record.origin.z+int(definition.footprint)):
						_expect(not scree_columns.has(Vector2i(x,z)), "scree clumps never overlap")
						scree_columns[Vector2i(x,z)] = true
						_expect(not generator.lake_columns.has(Vector2i(x,z)) and not generator.tarn_columns.has(Vector2i(x,z)), "scree support is dry")
			elif String(definition.get("kind", "")) in ["shrub", "flower", "reed"]:
				_expect(int(record.occupancy) < 0, "shrubs never register navigation occupancy")
				var pl: Dictionary = definition.placement
				var moisture: float = generator.get_moisture(record.origin.x, record.origin.z)
				_expect(moisture >= float(pl.min_moisture) and moisture <= float(pl.max_moisture), "shrub moisture habitat is respected")
				_expect(record.origin.y >= int(pl.min_y) and record.origin.y <= int(pl.max_y), "shrub height habitat is respected")
				var key: StringName = root.get_node("BlockRegistry").get_key(generator.get_generated_block_id(record.origin.x, record.origin.y, record.origin.z))
				_expect(root.get_node("BlockRegistry").get_def(key).kind in pl.ground_kinds, "shrub actual ground material is suitable")
				if String(definition.kind) == "reed":
					reeds_by_water[record.water_body] += 1
					var water: Vector2i = record.shore_water
					var waterline: int = generator.get_waterline(water.x,water.y)
					var actual_water: StringName = root.get_node("BlockRegistry").get_key(generator.get_generated_block_id(water.x,waterline,water.y))
					_expect(root.get_node("BlockRegistry").get_def(actual_water).kind == "water", "reed bank faces an actual water block")
					_expect(record.shore_waterline == waterline and record.origin.y-waterline >= int(pl.min_bank_height) and record.origin.y-waterline <= int(pl.max_bank_height), "reed uses local water elevation")
					_expect(record.shore_distance <= int(pl.shore_radius), "reed stays close to shore")
					_expect(forward._placement.shore_info(record.origin + Vector3i(0,10,0),pl).is_empty(), "cliff top above same shore rejected")
					_expect(forward._placement.shore_info(Vector3i(record.origin.x,waterline-1,record.origin.z),pl).is_empty(), "bank below water level rejected")
					_expect(forward._placement.shore_info(Vector3i(water.x,waterline,water.y),pl).is_empty(), "water column itself rejected")
				if String(definition.kind) in ["flower","reed"]:
					for dx in range(-1,2):
						for dz in range(-1,2):
							var col := Vector2i(record.origin.x+dx,record.origin.z+dz)
							_expect(generator.get_surface_y(col.x,col.y) == record.origin.y and not generator.lake_columns.has(col) and not generator.tarn_columns.has(col), "flower envelope is flat and dry")
					for other: Dictionary in forward._records.values():
						if other.id == record.id: continue
						var other_def: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition(other.definition)
						var area := Rect2i(record.origin.x-4,record.origin.z-4,9,9)
						_expect(not area.intersects(Rect2i(other.origin.x,other.origin.z,int(other_def.footprint),int(other_def.footprint))), "flowers preserve gaps from other details")
			else:
				if record.habitat == "lowland": lowland += 1
				else: upland += 1
				_expect(int(record.occupancy) >= 0, "boulders retain navigation occupancy")
			_expect(forward._supported(record), "generated boulder has solid ground and air envelope")
			_expect(not forward._occupied(record), "generated boulder has no other entity overlap")
		_expect(not records.is_empty(), "pilot has suitable habitat on sampled seed")
		report["lowland"] = lowland
		report["upland"] = upland
		report["scree"] = scree
		report["reeds_by_water"] = reeds_by_water
		if seed_value in SEEDS:
			_expect(lowland + upland == [81,83,64,76,62,58,77,51][SEEDS.find(seed_value)], "scree preserves established boulder populations")
		if seed_value in SEEDS:
			_expect(scree == [205,183,227,180,208,192,140,170][SEEDS.find(seed_value)], "shrubs preserve established scree populations")
		for species: String in ["blueberry", "elderberry", "wild_strawberry"]:
			_expect(int(report.categories.get(species, 0)) >= 50, "each sampled seed has at least 50 " + species)
		_expect(int(report.categories.get("flowers",0)) >= 100, "sampled seed retains abundant flowers")
		if seed_value in SEEDS: _expect(reeds_by_water.lake > 0, "sampled lake has suitable reed habitat")
		report["fingerprint"] = JSON.stringify(records).sha256_text()
		forward.free()
		var reverse = load("res://scripts/systems/SurfaceDetailManager.gd").new()
		scene.add_child(reverse)
		reverse.set_process(false)
		reverse.initialize_layout(true)
		_expect(_snapshot(reverse) == records, "reverse candidate order yields same records seed %d" % seed_value)
		_expect(hash(generator.heightmap) == terrain_before and hash(generator.waterline_map) == water_before and _tree_fingerprint(flora) == trees_before, "terrain, water and tree identities unchanged")
		var first := String(reverse._records.keys()[0])
		reverse.designate_clearing(first)
		reverse._changes[first].work_seconds = 1.25
		var scree_ids: Array = reverse._records.keys().filter(func(id): return String(id).begins_with("scree:"))
		if not scree_ids.is_empty(): reverse._remove(scree_ids[0], "cleared")
		var flower_ids: Array = reverse._records.keys().filter(func(id): return String(id).begins_with("flowers:"))
		if not flower_ids.is_empty(): reverse._remove(flower_ids[0], "cleared")
		var reed_ids: Array = reverse._records.keys().filter(func(id): return String(id).begins_with("reeds:"))
		if not reed_ids.is_empty(): reverse._remove(reed_ids[0], "cleared")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(reverse.serialize_state()))
		reverse.free()
		var restored = load("res://scripts/systems/SurfaceDetailManager.gd").new()
		scene.add_child(restored)
		restored.set_process(false)
		restored.restore_state(saved)
		_expect(_snapshot(restored) == records, "fresh owner restore regenerates identical records")
		_expect(restored._sources.size() == 1 and restored._changes[first].work_seconds == 1.25, "pre-generation restore reconstructs one partial job")
		if not scree_ids.is_empty(): _expect(restored._changes[scree_ids[0]].removed and restored._records[scree_ids[0]].occupancy < 0, "fresh owner preserves gathered scree removal")
		if not flower_ids.is_empty(): _expect(restored._changes[flower_ids[0]].removed and restored._records[flower_ids[0]].node == null, "fresh layout restore preserves cleared flower identity")
		if not reed_ids.is_empty(): _expect(restored._changes[reed_ids[0]].removed and restored._records[reed_ids[0]].node == null, "fresh layout restore preserves cleared reed identity")
		restored.free()
		reports.append(report)
		await process_frame
	var output := "res://tmp/surface_review/layout_report.json" if review else "res://tmp/reed_review/layout_report.json"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"seeds": reports, "failures": failures}, "\t"))
	file.close()
	for failure in failures: push_error(failure)
	print("SURFACE_DETAIL_LAYOUT_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _snapshot(owner: Node) -> Array:
	var result: Array = []
	for id: String in owner._records:
		var record: Dictionary = owner._records[id]
		result.append([id, str(record.origin), record.definition, record.variant, record.yaw])
	return result


func _tree_fingerprint(flora: Node) -> int:
	var result: Array = []
	for x in range(74):
		for z in range(74):
			var candidate: Dictionary = flora.generated_tree_candidate(x, z, 14)
			if not candidate.is_empty(): result.append([candidate.origin, candidate.stage, candidate.species.key])
	return hash(result)


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
