extends SceneTree

const Assets = preload("res://tools/animal_pilot/AnimalPilotAssets.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Deer art test timed out"); quit(1))
	for id in ["SaveManager","TaskManager","WorldClock","RoomManager","StockpileManager"]:
		root.get_node(id).set_process(false)
	root.get_node("WorldGenerator").world_seed=1234
	var parts := Assets.models()
	for part: String in parts:
		var asset := (parts[part] as PackedScene).instantiate() as Node3D
		expect(asset.transform.is_equal_approx(Transform3D.IDENTITY),part+" unit root")
		expect(asset.find_children("*","CollisionObject3D",true,false).is_empty(),part+" no embedded physics")
		var meshes := asset.find_children("*","MeshInstance3D",true,false)
		expect(meshes.size()==1,part+" one mesh")
		for mesh: MeshInstance3D in meshes:
			expect(mesh.transform.is_equal_approx(Transform3D.IDENTITY),part+" baked vertices")
			expect(mesh.mesh.get_surface_count()==1,part+" one surface")
			var colors: PackedColorArray=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var opaque := not colors.is_empty()
			for color in colors:
				if color.a<.999: opaque=false
			expect(opaque,part+" opaque vertex colors")
			if part=="leg":
				expect(is_equal_approx(mesh.get_aabb().position.y,-1.25),"standing hoof reaches support")
				expect(mesh.get_aabb().end.y>=.17,"upper leg overlaps torso above hip")
		asset.free()
	var scene := Node3D.new()
	root.add_child(scene); current_scene=scene
	var wildlife = load("res://tools/animal_pilot/AnimalPilotWildlife.gd").new()
	scene.add_child(wildlife); wildlife.set_process(false)
	var actor = wildlife.add_deer("deer:art",Vector3i(40,21,40),151,"art")
	var meshes: Array[Node] = actor.find_children("*","MeshInstance3D",true,false)
	expect(meshes.size()==9,"five body parts and four independent legs")
	expect(actor.legs.size()==4 and actor.footprint==2,"four legs and two-cell navigation footprint")
	expect(actor.neck.position.is_equal_approx(Vector3(0,1.5,-.3)),"production neck anchor")
	expect((actor.neck.position+actor.head.position).is_equal_approx(Vector3(0,2.65,-.55)),"production head anchor")
	for mesh: MeshInstance3D in meshes:
		var material := mesh.material_override as StandardMaterial3D
		expect(material!=null and material.vertex_color_use_as_albedo and material.roughness==1.0 and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"production opaque vertex-color material")
	# Sample the imported vertices through the real animation, including the full
	# grazing head-bob cycle. AABB checks also cover selection bounds at rest.
	for activity in ["Idle","Wandering","Fleeing","Grazing","Sleeping"]:
		var lowest := INF
		var highest := -INF
		var front := INF
		var back := -INF
		var muzzle_highest := -INF
		for i in 64:
			actor.activity=activity
			actor.hop_progress=float(i)/64.0 if activity in ["Wandering","Fleeing"] else 1.0
			actor.pose_time=float(i)*TAU/64.0/5.0
			actor._pose()
			var box := _local_bounds(actor,meshes)
			lowest=minf(lowest,box.position.y); highest=maxf(highest,box.end.y)
			front=minf(front,box.position.z); back=maxf(back,box.end.z)
			if activity=="Grazing":
				var head_bounds := _local_bounds(actor,actor.head.find_children("*","MeshInstance3D",true,false))
				muzzle_highest=maxf(muzzle_highest,head_bounds.position.y)
		expect(lowest>=-.001,"ground clearance across "+activity+": %.4f"%lowest)
		expect(highest<4.0,"four-block clearance across "+activity)
		if activity in ["Idle","Sleeping"]:
			expect(front>=-1.0 and back<=1.0,"standing footprint across "+activity)
		if activity=="Grazing":
			expect(front>=-2.0 and back<=1.0,"grazing stays in checked forward row")
			expect(muzzle_highest<.15,"grazing muzzle stays within .15 of grass: %.4f"%muzzle_highest)
		if activity=="Sleeping":
			var selection: AABB=wildlife.get_explorer_bounds(actor)
			expect(selection.position.y>=21.0,"rest selection box clears support")
	for failure in failures: push_error(failure)
	print("DEER_PILOT_ART_OK: %d imported-asset and sampled-pose checks"%checks if failures.is_empty() else "DEER_PILOT_ART_FAIL")
	quit(0 if failures.is_empty() else 1)

func _local_bounds(actor: Node3D, meshes: Array[Node]) -> AABB:
	var first := true
	var result := AABB()
	var inverse := actor.global_transform.affine_inverse()
	for mesh: MeshInstance3D in meshes:
		var transform := inverse*mesh.global_transform
		var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := transform*vertex
			if first: result=AABB(point,Vector3.ZERO); first=false
			else: result=result.expand(point)
	return result
