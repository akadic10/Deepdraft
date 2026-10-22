extends SceneTree

## Imported fire clips and the real installed lighting/animation owner.
var failures: Array[String]=[]
var checks := 0
var staged: Array[PackedScene]=[]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--staged" in OS.get_cmdline_user_args(): staged=preload("res://tools/voxel_assets/StagedAssets.gd").install("furniture")
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager"]: root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var libraries := {}; var frames := 0; var sources := 0
	for id: String in ["campfire","hearth","wooden_torch"]:
		var key := "base:furniture:"+id
		var definition: Dictionary=controller.get_defs()[key]
		var config: Dictionary=definition.light_source.flame_animation
		var model: Node3D=controller._instance_model(key,controller._make_solid_material())
		scene.add_child(model); model.position.x=sources*4
		var flame: MeshInstance3D=model.find_child(definition.light_source.emissive_mesh,true,false)
		var first_mesh := flame.mesh
		load("res://scripts/components/FurnitureLighting.gd").attach(model,definition)
		var animation: Node=model.get_node("FlameAnimation")
		animation.set_process(false)
		var light: OmniLight3D=model.get_node("FurnitureLight")
		_expect(flame.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,id+" self-lit from every angle")
		_expect(flame.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,id+" flame does not occlude its light")
		_expect(is_equal_approx(light.omni_range,float(definition.light_source.range)),id+" existing light range")
		_expect(animation._frames.size()==config.frames.size(),id+" all named frames bind")
		_expect(first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==animation._frames[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX],id+" static preview matches animated first frame")
		var elapsed := 0.0
		var digests := {}
		var roots := {}
		for frame in config.frames.size():
			animation._elapsed=elapsed+float(config.frame_durations[frame])*.5
			animation._apply_sample()
			_expect(animation._frame_index==frame and flame.mesh==animation._frames[frame],id+" timed frame "+str(frame))
			var arrays := flame.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			var axial := true; var opaque := true; var base := {}; var on_grid:=true
			var bottom := flame.mesh.get_aabb().position.y
			for i in vertices.size():
				if normals[i].abs().dot(Vector3.ONE)>1.005: axial=false
				for axis in 3:
					if absf(vertices[i][axis]*16-roundf(vertices[i][axis]*16))>.02: on_grid=false
				if colors[i].a<.999: opaque=false
				if absf(vertices[i].y-bottom)<.0001: base[vertices[i]]=true
			_expect(axial and on_grid,id+" baked 1:16 voxel faces")
			_expect(opaque and colors.size()==vertices.size() and flame.mesh.get_surface_count()==1,id+" one opaque vertex-color surface")
			if frame==0: roots=base
			else: _expect(_same_roots(base,roots),id+" flame roots stay fixed")
			digests[hash(vertices)]=true
			elapsed+=float(config.frame_durations[frame])
		_expect(digests.size()==config.frames.size(),id+" unique moving silhouettes")
		model.hide()
		_expect(not animation.is_processing(),id+" slicing suspends hidden animation")
		var hidden_time: float=animation._elapsed
		animation._process(.3)
		_expect(animation._elapsed==hidden_time,id+" hidden fire does not advance")
		model.show()
		_expect(animation.is_processing(),id+" revealed animation resumes")
		animation.set_process(false)
		if not libraries.has(config.model): frames+=config.frames.size(); libraries[config.model]=true
		sources+=1; model.free()
	_expect(sources==3 and libraries.size()==3 and frames==26,"three sources, three libraries, 26 unique frames")
	controller.free()
	for failure in failures: push_error(failure)
	print("FIRE_VOXEL_ART_OK: %d imported-frame, shading, root, timing and visibility checks"%checks if failures.is_empty() else "FIRE_VOXEL_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures.append(message)

func _same_roots(a: Dictionary,b: Dictionary) -> bool:
	# Godot reorders vertices and quantizes positions against each frame's
	# AABB. Allow 0.00005 world units of import rounding; source checks require
	# exact roots. Observed native differences are approximately 0.00001.
	if a.size()!=b.size(): return false
	for point: Vector3 in a:
		var nearest := INF
		for other: Vector3 in b: nearest=minf(nearest,point.distance_to(other))
		if nearest>.00005: return false
	return true
