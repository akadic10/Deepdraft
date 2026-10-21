extends "res://tools/voxel_assets/WorldBenchmark.gd"

## Paused, identical full-world camera to isolate import / material / shadow defects.
func _sample(label: String, _active: bool, _pan := false) -> void:
	if label!="paused_close": return
	var meshes: Array[MeshInstance3D]=[]
	for entry: Dictionary in scene.get_node("SurfaceFloraSpawner")._trees.values():
		if is_instance_valid(entry.node): meshes.append_array(preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(entry.node))
	await _capture("original")
	var threshold := root.mesh_lod_threshold
	root.mesh_lod_threshold=0
	await _capture("no_lod")
	root.mesh_lod_threshold=threshold
	for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_enabled=false
	await _capture("no_sun_shadows")
	for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_enabled=true
	for mesh in meshes:
		var mat := mesh.material_override as ShaderMaterial
		if mat!=null: mat.shader=preload("res://scripts/shaders/underground_lighting_closed.gdshader")
	await _capture("closed")
	var nearest: Node3D
	var distance := INF
	for entry: Dictionary in scene.get_node("SurfaceFloraSpawner")._trees.values():
		if entry.stage!="ancient" or not is_instance_valid(entry.node): continue
		var d: float=entry.node.position.distance_to(Vector3(camp))
		if d<distance: distance=d; nearest=entry.node
	if nearest!=null:
		_view(nearest.position+Vector3(0,3,0),9,Vector3(-.7,.3,1))
		await _capture("trunk_close")
		for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_enabled=false
		await _capture("trunk_no_shadow")
		for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_enabled=true
	_view(Vector3(camp)+Vector3(0,3,0),48,Vector3(-.7,1,1))
	for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_normal_bias=0
	await _capture("no_normal_bias")
	for entry: Dictionary in scene.get_node("SurfaceFloraSpawner")._trees.values():
		if is_instance_valid(entry.node): preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(entry.node,false)
	await _capture("no_tree_proxy")
	print("TREE_WORLD_DIAGNOSTIC_PASS ",meshes.size())
	quit()
	await process_frame

func _capture(label: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")
