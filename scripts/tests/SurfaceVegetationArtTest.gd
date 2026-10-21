extends SceneTree

## Real imported models, registry coverage and presentation-state integration.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var failures: Array[String] = []
var checks := 0
var paths := {}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Surface art test timeout"); quit(1))
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_process(false)
	root.get_node("TaskManager").set_process(false)
	root.get_node("WorldGenerator").world_seed = 1234
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	world.get_chunk(2,1,2)
	for x in range(32,48):
		for z in range(32,48):
			world.set_block(x,20,z,blocks.get_id("base:terrain:surface:grass_01"))
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var details = load("res://scripts/systems/SurfaceDetailManager.gd").new()
	scene.add_child(details)
	details.set_process(false)
	details._initialized = true
	var drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	var registry = root.get_node("SurfaceDetailRegistry")
	var clock_node = root.get_node("WorldClock")
	var keys: Array[String] = ["base:flora:blueberry_bush","base:flora:elderberry_bush","base:flora:wild_strawberry_bush","base:detail:flowers","base:detail:reeds"]
	for key in keys:
		var definition: Dictionary = registry.get_definition(key)
		_collect(definition)
		var variants := 1 if definition.kind == "shrub" else int(definition.models.size())
		for variant in range(variants):
			for yaw in range(4):
				var id := "vegetation-art:%s:%d:%d"%[key,variant,yaw]
				details.register_record({"id":id,"definition":key,"origin":Vector3i(40,20,40),"variant":variant,"yaw":yaw,"habitat":"fixture"})
				for season: String in ["spring","summer","autumn","winter"]:
					clock_node.restore_state({"year":1,"season":season,"day":1,"hour":12,"speed":1,"paused":true})
					details._spawn_visual(id)
					var record: Dictionary = details._records[id]
					_expect(record.node != null,"live seasonal visual loads: "+id+" "+season)
					if record.node == null: continue
					_expect(_is_plant_path(record.model_path) and record.model_path.contains(season),"live art matches registry season")
					_expect(record.node.position.is_equal_approx(Vector3(40.5,21,40.5)),"single-tile centered support")
					_expect(record.occupancy < 0 and record.node.find_children("*","CollisionShape3D",true,false).is_empty(),"overhang never gains collision")
					var bounds: AABB = details.get_explorer_bounds(id)
					_expect(is_equal_approx(bounds.position.y,21) and bounds.size.y <= float(definition.height)+.001,"grounding and authored clearance in every rotation")
					for mesh in Shadows.visual_meshes(record.node):
						_expect(mesh.material_override == details._material,"shared production plant material")
						_expect(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"live plant visual does not cast")
						var proxy := Shadows.proxy_for_visual(mesh)
						_expect(proxy!=null and proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"live plant proxy is shadow-only")
					if definition.kind == "shrub":
						details._changes[id] = {"planted_at":clock_node.elapsed_days(),"growth_credit":0.0}
						details._spawn_visual(id)
						_expect(record.model_path == definition.young_models[season],"new planting loads young seasonal form")
						details._changes[id] = {"regrow_started_at":clock_node.elapsed_days(),"regrow_credit":0.0}
						details._spawn_visual(id)
						_expect(record.model_path == definition.picked_models.get(season,definition.seasonal_models[season]),"harvest resolves picked seasonal form")
						details._changes[id] = {"packed":true,"regrow_started_at":clock_node.elapsed_days(),"regrow_credit":0.0}
						var packed_key := season+("_picked" if definition.picked_models.has(season) else "")
						_expect(details.packed_model(id) == definition.transplant.models[packed_key],"carried crop keeps seasonal/picked appearance")
						details._changes.erase(id)
					elif definition.kind == "flower":
						_expect(details.packed_model(id) == definition.transplant.models[season][variant],"carried flower retains color variant and season")
					details.apply_slice(19)
					_expect(not details._records[id].node.visible,"slice conceals planted model")
					details.apply_slice(20)
					_expect(details._records[id].node.visible,"slice restores complete plant")
				if is_instance_valid(details._records[id].node): details._records[id].node.free()
				details._records.erase(id)
				details._visual_queue.clear()
				details._columns.clear()
				await process_frame
		if definition.kind == "shrub":
			_expect(drops.get_item_def(definition.transplant.item).model == definition.transplant.models.summer,"loose shrub fallback uses matching packed art")
		elif definition.kind == "flower":
			for variant in range(3):
				_expect(drops.get_item_def(definition.transplant.variants[variant].item).model == definition.transplant.models.summer[variant],"loose flower fallback uses matching packed art")
	for path: String in paths: _check_asset(path)
	_expect(paths.size() == 76,"all 76 live plant models covered")
	print("SURFACE_VEGETATION_ART_PASS " if failures.is_empty() else "SURFACE_VEGETATION_ART_FAIL ",checks," checks; ",paths.size()," models")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _collect(value) -> void:
	if value is String and value.ends_with(".glb") and _is_plant_path(value): paths[value] = true
	elif value is Dictionary:
		for child in value.values(): _collect(child)
	elif value is Array:
		for child in value: _collect(child)

func _is_plant_path(path: String) -> bool:
	for family: String in ["bushes", "flowers", "reeds"]:
		if path.begins_with("res://assets/models/flora/"+family+"/"): return true
	return false

func _check_asset(path: String) -> void:
	var packed = load(path) as PackedScene
	_expect(packed != null,"imported scene: "+path)
	if packed == null: return
	var model := packed.instantiate() as Node3D
	_expect(model.transform.is_equal_approx(Transform3D.IDENTITY),"unit root transform")
	_expect(model.find_children("*","CollisionObject3D",true,false).is_empty(),"no embedded physics")
	var meshes := Shadows.visual_meshes(model)
	_expect(meshes.size() == 1,"one greedy visual mesh per plant")
	_expect(Shadows.configure(model)==1,"one imported proxy per plant")
	for instance: MeshInstance3D in meshes:
		_expect(instance.transform.is_equal_approx(Transform3D.IDENTITY),"baked world scale")
		_expect(instance.mesh.get_surface_count() == 1,"one surface per plant")
		_expect(absf(instance.mesh.get_aabb().position.y) < .001,"grounded asset origin")
		var arrays := instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var opaque := true
		for color in colors:
			if color.a < .999: opaque = false
		_expect(colors.size() == vertices.size() and opaque,"opaque vertex-colored geometry")
	model.free()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
