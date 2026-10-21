extends SceneTree

## Exercises the production consumers, not just exported node names.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
var Picking: GDScript
const FLOOR := "res://assets/models/studies/voxel_pipeline/floor.glb"
const DOOR := "res://assets/models/studies/voxel_pipeline/door.glb"
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	Picking = load("res://scripts/components/ObjectPicking.gd")
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var floor_model: Node3D = load(FLOOR).instantiate()
	scene.add_child(floor_model)
	_expect(Shadows.configure(floor_model)==1,"one imported pair")
	_check_pair(floor_model, true)
	var visual := Shadows.visual_meshes(floor_model)[0]
	var proxy := visual.get_parent().get_node("VoxelShadowProxy") as MeshInstance3D
	var resource_id := visual.mesh.get_instance_id()
	Shadows.configure(floor_model, false)
	_expect(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not proxy.visible,"detailed comparison toggle")
	Shadows.set_casting(floor_model, false)
	load("res://scripts/components/UndergroundLighting.gd").bind_world_tree(floor_model)
	_check_pair(floor_model, false)
	Shadows.configure(floor_model, false)
	_expect(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"comparison respects no-casting policy")
	Shadows.set_casting(floor_model, true)
	_expect(visual.mesh.get_instance_id()==resource_id,"instance policy never copies shared mesh")
	_expect(Shadows.visual_meshes(visual).size()==1,"visual traversal includes root mesh")
	# Deliberately move the proxy away: bounds and ray picking must still ignore it.
	proxy.position.x=10
	var bounds: AABB = Picking.world_bounds(floor_model)
	_expect(bounds.end.x<1.01 and Picking.visible_world_bounds(floor_model).end.x<1.01,"proxy excluded from both bound queries")
	var picking = Picking.new()
	_expect(is_inf(picking.hit_distance(floor_model,Vector3(10.5,.5,2),Vector3(10.5,.5,-2))),"proxy cannot receive selection hits")
	_expect(not is_inf(picking.hit_distance(floor_model,Vector3(.5,.5,2),Vector3(.5,.5,-2))),"visual remains selectable")
	var floor_art = load("res://scripts/components/ConstructionFloorArt.gd").new()
	floor_art._load_faces(FLOOR)
	var triangles := 0
	for face: Array in floor_art._faces[FLOOR].values(): triangles+=face[3].size()/3
	_expect(triangles==12,"floor bake contains exactly one cube, no proxy faces")
	var furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	scene.add_child(furniture)
	furniture.set_process(false)
	var solid := StandardMaterial3D.new()
	var ghost := StandardMaterial3D.new()
	ghost.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	# Special access previews bypass the ordinary furniture model constructor.
	for preview in [false,true]:
		var bridge: Node3D=furniture._bridges.make_visual(3,ghost if preview else solid)
		scene.add_child(bridge)
		Shadows.configure(bridge)
		_check_pair(bridge,not preview)
		bridge.free()
	var ladder: Node3D=furniture._ladders.make_visual(8,4,ghost)
	scene.add_child(ladder)
	Shadows.configure(ladder)
	_check_pair(ladder.get_child(0),true)
	_check_pair(ladder.get_child(1),false)
	ladder.free()
	for preview in [false,true]:
		var placed: Node3D = furniture._instance_model("fixture",ghost if preview else solid,{"model":DOOR})
		scene.add_child(placed)
		_check_pair(placed, not preview)
		if not preview:
			var animation = load("res://scripts/components/FurnitureDoorAnimation.gd").new()
			placed.add_child(animation)
			animation.set_process(false)
			animation.setup(placed,{"width":2.0})
			_expect(animation._hinges.size()==2,"production hinges find articulated roots")
			for hinge: Node3D in animation._hinges:
				hinge.rotation.y=.8
				var leaf_visual := Shadows.visual_meshes(hinge)[0]
				var leaf_proxy := Shadows.proxy_for_visual(leaf_visual)
				_expect(leaf_visual.global_transform.is_equal_approx(leaf_proxy.global_transform),"proxy follows animated rigid pivot")
		var boxes: Array[AABB] = []
		furniture._collect_mesh_bounds(placed,Transform3D.IDENTITY,boxes)
		_expect(boxes.size()==2,"placement bounds contain only two visual leaves")
		placed.free()
	var drops = load("res://scripts/systems/ItemDropManager.gd").new()
	scene.add_child(drops)
	var item: Node3D = drops._build_drop_node("fixture",load(FLOOR))
	scene.add_child(item)
	_check_pair(item,true)
	# Body-shadow suppression survives later world lighting; broad hearths retain it.
	for body_shadows in [false,true]:
		var lamp: Node3D = load(FLOOR).instantiate()
		scene.add_child(lamp)
		load("res://scripts/components/FurnitureLighting.gd").attach(lamp,{"light_source":{"body_shadows":body_shadows}})
		load("res://scripts/components/UndergroundLighting.gd").bind_world_tree(lamp)
		_check_pair(lamp,body_shadows)
		lamp.free()
	item.free()
	floor_model.free()
	# Actual dwarf assembly and portrait cloning must preserve each part's pair.
	var study = load("res://tools/micro_voxel_study/StudyAssets.gd")
	var saved: Dictionary = study.install()
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var actor = factory.spawn(factory.generate(191,{}),800)
	scene.add_child(actor)
	actor.set_process(false)
	actor.get_node("Readability").set_process(false)
	load("res://scripts/components/UndergroundLighting.gd").bind_world_tree(actor)
	_check_pair(actor,true)
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var portrait: Node3D = load("res://scripts/ui/DwarfPortrait.gd").create_model(viewport,actor)
	_check_pair(portrait,false)
	viewport.free()
	actor.free()
	study.restore(saved)
	print("VOXEL_PIPELINE_PASS " if failures.is_empty() else "VOXEL_PIPELINE_FAIL ",checks," checks")
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _check_pair(model: Node, casting: bool) -> void:
	var pair_count := 0
	for node in model.find_children("VoxelShadowProxy*","MeshInstance3D",true,false):
		pair_count+=1
		var visual: MeshInstance3D = Shadows.visual_for_proxy(node)
		_expect(visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"detailed mesh never casts")
		_expect(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and node.visible==casting,"proxy-only casting matches policy")
		_expect(node.gi_mode==GeometryInstance3D.GI_MODE_DISABLED,"proxy cannot contribute GI")
	_expect(pair_count>0,"paired asset exercised")

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
