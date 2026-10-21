extends SceneTree

## Imported-asset and live-spawner contracts for the complete voxel tree family.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var failures: Array[String] = []
var checks := 0
var model_count := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	scene.add_child(flora)
	flora.set_process(false)
	var original_state: Dictionary = flora.serialize_state()
	for species: Dictionary in flora._species:
		for stage_name: String in species.stages:
			var stage: Dictionary = species.stages[stage_name]
			var footprint: int = flora._footprint_for(species.placement,stage_name)
			for group in ["models","picked_models"]:
				for paths in stage.get(group,{}).values():
					for path: String in _paths(paths): _check_asset(flora,path,footprint,stage_name)
			var summer: Array = _paths(stage.get("picked_models",stage.models).summer)
			for season: String in ["spring","summer","autumn","winter"]:
				var models: Dictionary = stage.get("picked_models",stage.models) if season != "autumn" else stage.models
				var season_key: String = "autumn_fruiting" if season == "autumn" and models.has("autumn_fruiting") else season
				var paths: Array = _paths(models.get(season_key,models.summer))
				_expect(paths.size() == summer.size(),"seasonal variant roster matches")
				# Position hash retains variant index through all four seasons.
				for x in range(12):
					var cell := Vector3i(100+x,20,100)
					var summer_path: String = flora.resolve_tree_model_for_season(stage,"summer",cell)
					var seasonal_path: String = flora.resolve_tree_model_for_season(stage,season,cell)
					_expect(summer.find(summer_path) == paths.find(seasonal_path),"stable seasonal identity")
				flora._season = season
				var node: Node3D = flora._instance_tree(species.name,"",stage_name,stage,100,100,20,footprint)
				_expect(is_instance_valid(node),"production spawner loads "+species.name+" "+stage_name+" "+season)
				if node == null: continue
				var record: Dictionary = flora._trees[Vector2i(100,100)]
				flora._loaded_columns[Vector2i(6,6)] = [node]
				_expect(paths.has(record.model_path),"live tree uses expected seasonal model")
				_expect(node.position.is_equal_approx(Vector3(100+footprint*.5,21,100+footprint*.5)),"trunk stays centered on gameplay footprint")
				_expect(record.bounds.position.y >= 20.99,"visual is grounded")
				if stage_name == "sapling":
					_expect(record.occupancy_id == -1 and not node is StaticBody3D,"sapling remains walk-through clutter")
				else:
					_expect(record.occupancy_id >= 0 and node is StaticBody3D,"adult trunk retains occupancy")
					var shapes := node.find_children("*","CollisionShape3D",true,false)
					_expect(shapes.size() == 1,"only the trunk receives collision")
					_expect(shapes[0].shape.size == Vector3(footprint,stage.clearance_height,footprint),"collision dimensions remain data-owned")
				flora._on_slice_changed(19)
				_expect(not node.visible,"slice hides tree below its base")
				flora._on_slice_changed(20)
				_expect(node.visible,"slice at ground restores whole tree")
				flora._on_slice_changed(127)
				if species.name == "juniper" and stage_name != "sapling" and season == "autumn":
					var id := Vector2i(100,100)
					var occupancy: int = record.occupancy_id
					var ripe_path: String = record.model_path
					flora._tree_changes[id] = {"harvested_cycle":flora._fruit_cycle()}
					flora._refresh_tree_crop_visual(id)
					_expect(record.model_path != ripe_path and String(record.model_path).ends_with("_picked.glb"),"picked state removes berry geometry")
					_expect(record.node == node and record.occupancy_id == occupancy,"crop refresh preserves tree body and occupancy")
					flora._tree_changes.erase(id)
				if record.occupancy_id >= 0: root.get_node("PlacedEntityRegistry").unregister(record.occupancy_id)
				node.free()
				flora._trees.clear()
				flora._loaded_columns.clear()
	_expect(model_count == 94,"all 94 imported tree models verified")
	_expect(original_state == flora.serialize_state(),"visual stage/season replacement does not write save deltas")
	print("TREE_PILOT_PASS " if failures.is_empty() else "TREE_PILOT_FAIL ",checks," checks; ",model_count," models")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_asset(flora: Node, path: String, footprint: int, stage: String) -> void:
	model_count += 1
	_expect("/trees/" in path,"model belongs to production tree roster")
	var packed: PackedScene = flora._load_scene(path)
	_expect(packed != null,"imported PackedScene exists: "+path)
	if packed == null: return
	var model := packed.instantiate() as Node3D
	_expect(model.transform.is_equal_approx(Transform3D.IDENTITY),"root unit transform")
	_expect(model.find_children("*","CollisionObject3D",true,false).is_empty(),"authored canopy has no physics")
	var meshes := Shadows.visual_meshes(model)
	_expect(meshes.size() == 1,"one greedy visual mesh per model")
	_expect(Shadows.configure(model)==1,"one imported shadow proxy pair")
	flora._apply_material_recursive(model)
	for instance: MeshInstance3D in meshes:
		var proxy := Shadows.proxy_for_visual(instance)
		_expect(instance.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"visual shadow casting disabled")
		_expect(proxy!=null and proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"proxy casts shadows only")
		_expect(instance.material_override == flora._tree_material,"shared production material")
		_expect(instance.mesh.get_surface_count() == 1,"one surface/material per model")
		var bounds := instance.mesh.get_aabb()
		_expect(absf(bounds.position.y) < .001,"asset base Y=0")
		_expect(maxf(absf(bounds.position.x),absf(bounds.end.x)) < 16 and maxf(absf(bounds.position.z),absf(bounds.end.z)) < 16,"canopy fits flight-query search envelope")
		var arrays := instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var bad_low_vertices := 0
		var off_grid := 0
		for vertex: Vector3 in vertices:
			if stage != "sapling" and vertex.y < 3.99 and (absf(vertex.x) > footprint*.5+.001 or absf(vertex.z) > footprint*.5+.001): bad_low_vertices += 1
			# Godot packs imported positions; the source audit checks exact 1:16.
			for axis in range(3):
				if absf(vertex[axis]*16-roundf(vertex[axis]*16))>.02: off_grid+=1
		_expect(bad_low_vertices == 0,"three-block walking clearance under overhang")
		_expect(off_grid==0,"imported voxel grid survives mesh quantization")
		var opaque := true
		for color: Color in colors:
			if color.a < .999: opaque = false
		_expect(colors.size() == vertices.size() and opaque,"opaque vertex-color surface")
	model.free()

func _paths(value) -> Array:
	return [value] if value is String else value

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
