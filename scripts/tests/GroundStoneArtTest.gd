extends SceneTree

## Imported stone variants, exact mesh picking, collision and slice contracts.
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Ground stone art test timeout"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	world.get_chunk(2,1,2)
	for x in range(32,48):
		for z in range(32,48): world.set_block(x,20,z,blocks.get_id("base:terrain:surface:grass_01"))
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	var saved_before: Dictionary = details.serialize_state()
	var count := 0
	for category: String in ["boulder","scree"]:
		var key := "base:detail:"+category
		var definition: Dictionary = root.get_node("SurfaceDetailRegistry").get_definition(key)
		for variant in range(3):
			count += 1
			var path: String = definition.models[variant]
			_expect(path.begins_with("res://assets/models/rocks/"),"live registry uses new stone art")
			var packed := load(path) as PackedScene
			_expect(packed != null,"imported scene exists")
			if packed == null: continue
			var asset := packed.instantiate() as Node3D
			_expect(asset.transform.is_equal_approx(Transform3D.IDENTITY),"unit model root")
			_expect(asset.find_children("*","CollisionObject3D",true,false).is_empty(),"asset has no embedded collision")
			var meshes := asset.find_children("*","MeshInstance3D",true,false)
			if asset is MeshInstance3D: meshes.append(asset)
			_expect(meshes.size() == 1,"single mesh")
			for mesh: MeshInstance3D in meshes:
				_expect(mesh.mesh.get_surface_count() == 1 and mesh.transform.is_equal_approx(Transform3D.IDENTITY),"one surface in baked world units")
				var colors: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				var opaque := not colors.is_empty()
				for color in colors:
					if color.a < .999: opaque = false
				_expect(opaque,"opaque vertex colors")
			asset.free()
			for yaw in range(4):
				var id := "stone-art:%s:%d:%d"%[category,variant,yaw]
				details.register_record({"id":id,"definition":key,"origin":Vector3i(40,20,40),"variant":variant,"yaw":yaw,"habitat":"fixture"})
				details._spawn_visual(id)
				var record: Dictionary = details._records[id]
				_expect(is_instance_valid(record.node),"production instance loads")
				if not is_instance_valid(record.node): continue
				var width := float(definition.footprint)
				var bounds: AABB = details.get_explorer_bounds(id)
				_expect(record.node.position.is_equal_approx(Vector3(40+width*.5,21,40+width*.5)),"model centered on its gameplay footprint")
				_expect(is_equal_approx(bounds.position.y,21) and bounds.size.y <= (2.0 if category == "boulder" else .5)+.001,"grounded low stone envelope")
				_expect(bounds.position.x >= 40-.001 and bounds.position.z >= 40-.001 and bounds.end.x <= 40+width+.001 and bounds.end.z <= 40+width+.001,"all rotations fit logical support")
				var shapes: Array = record.node.find_children("*","CollisionShape3D",true,false)
				if category == "boulder":
					_expect(record.occupancy >= 0 and shapes.size() == 1,"boulder retains one blocking body")
					if shapes.size() == 1: _expect(shapes[0].shape.size == Vector3(2,2,2),"JSON collision envelope retained")
					_expect(record.node.collision_layer == 2 and record.node.collision_mask == 0,"camera terrain collision unchanged")
				else: _expect(record.occupancy < 0 and shapes.is_empty(),"scree has no obstacle")
				for x in range(int(width)):
					for z in range(int(width)):
						_expect(root.get_node("NavGrid").is_walkable(Vector3i(40+x,20,40+z)) == (category == "scree"),"correct navigation across whole footprint")
				var hit_point := Vector3.ZERO
				for mesh: MeshInstance3D in record.node.find_children("*","MeshInstance3D",true,false):
					_expect(mesh.material_override == details._material,"shared lit stone material")
					var faces := mesh.mesh.get_faces()
					for i in range(0,faces.size(),3):
						var center := (faces[i]+faces[i+1]+faces[i+2])/3.0
						if center.y > hit_point.y: hit_point = center
					hit_point = mesh.global_transform*hit_point
				_expect(details.pick_explorer_object(hit_point+Vector3.UP*5,hit_point-Vector3.UP*5).get("id","") == id,"actual visible stone face is pickable")
				if category == "scree":
					var gap := false
					for ix in range(1,8):
						for iz in range(1,8):
							var point := bounds.position+Vector3(bounds.size.x*ix/8.0,0,bounds.size.z*iz/8.0)
							if details.pick_explorer_object(point+Vector3.UP*5,point-Vector3.UP).is_empty(): gap = true
					_expect(gap,"open gaps do not pick the clump's bounding box")
				var original_node: Node3D = record.node
				root.get_node("WorldClock").season_changed.emit("winter")
				_expect(record.node == original_node,"season does not replace or recolor stone")
				details.apply_slice(19)
				_expect(not record.node.visible and details.get_explorer_bounds(id).size == Vector3.ZERO,"slice conceals visuals and picking")
				_expect(root.get_node("NavGrid").is_walkable(Vector3i(40,20,40)) == (category == "scree"),"slice preserves navigation")
				details.apply_slice(127)
				# Retire the test index before unregister emits occupancy_changed.
				details._columns.clear()
				details._records.erase(id)
				if record.occupancy >= 0: root.get_node("PlacedEntityRegistry").unregister(record.occupancy)
				record.node.free()
				details._visual_queue.clear()
				await process_frame
	_expect(count == 6,"all six live variants")
	_expect(details.serialize_state() == saved_before,"rendering and slice checks do not add save edits")
	print("GROUND_STONE_ART_PASS " if failures.is_empty() else "GROUND_STONE_ART_FAIL ",checks," checks; ",count," models")
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
