extends "res://scripts/tests/DwarfPilotArtTest.gd"

var Navigation

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Proportion integration timeout"); quit(1))
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager","SkyController","WeatherManager"]:
		root.get_node(id).set_process(false)
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	Navigation=load("res://scripts/components/AnimalNavigation.gd")
	var factory=load("res://scripts/entities/DwarfFactory.gd").new()
	var appearance := DwarfAppearanceData.new()
	appearance.hair_style="short_back"; appearance.beard_style="forked"; appearance.scar="cheek_slash"
	var actor: Node3D=factory.spawn({"name":"Proportions","gender":"male","appearance":appearance},165)
	scene.add_child(actor); actor.set_process(false); actor.get_node("Readability").set_process(false)
	actor._reset_part_offsets()
	var standing := _bounds(actor)
	expect(absf(standing.size.x-2.16)<.001 and absf(standing.size.y-3.32)<.001,"approved Balanced width and original height")
	expect(actor.get_node("LogicalBox").shape.size==Vector3(1,3,1),"dwarf gameplay clearance stays fixed")
	for phase in [.0,.2,.55,.93]:
		actor._reset_part_offsets(); actor._walk_cycle=phase; actor._walk_bob(0)
		expect(absf(actor._hand_l.position.x+.22)<.001 and absf(actor._foot_l.position.x+.06)<.001,"gait retains approved relaxed stance")
		for rig in [actor._mining_pose,actor._felling_pose]:
			actor._reset_part_offsets(); rig.apply(phase,Vector3(0,1.2,1.4))
			_expect_widths(actor)
			var before: Dictionary=actor.serialize_state()
			actor.restore_saved_runtime(before)
			actor._reset_part_offsets()
			_expect_widths(actor)
		for pose in ["lying","sitting"]:
			actor._reset_part_offsets()
			actor._rest_behavior.pose=pose; actor._rest_behavior.blend=phase
			actor._rest_behavior._apply_pose()
			_expect_widths(actor)
	actor._rest_behavior.cancel(); actor._reset_part_offsets()
	expect(_bounds(actor).size.is_equal_approx(standing.size),"work/rest/save cycles return to approved standing shape")
	var texture := TextureRect.new(); scene.add_child(texture)
	var portrait=load("res://scripts/ui/DwarfPortrait.gd")
	var model: Node3D=portrait.create_model(portrait.create_viewport(texture),actor)
	expect(is_equal_approx(model.get_node("MeshHead").scale.x,.93) and is_equal_approx(model.get_node("MeshBody").scale.x,.8),"portrait retains world proportions")
	expect(is_equal_approx(model.get_node("MeshScar").scale.x,.93),"portrait scar follows narrower head")
	var wildlife=load("res://scripts/systems/WildlifeManager.gd").new(); scene.add_child(wildlife); wildlife.set_process(false)
	var wolf: Node3D=wildlife.add_wolf("wolf:proportions",Vector3i(40,21,40),165)
	wolf.activity="Idle"; wolf.hop_progress=1; wolf._pose()
	var box := _bounds(wolf)
	expect(box.size.distance_to(Vector3(1.287,2.392,3.41065))<.002,"approved Large wolf dimensions")
	expect(wolf.footprint==4 and int(wolf.definition.navigation.clearance)==3,"wolf navigation matches enlarged form")
	for activity in ["Idle","Wandering","Hunting","Eating","Sleeping"]:
		for phase in [.0,.2,.55,.93]:
			wolf.activity=activity; wolf.pose_time=phase*5
			wolf.hop_progress=phase if activity in ["Wandering","Hunting"] else 1.0
			wolf._pose()
			for yaw in 8:
				wolf.rotation.y=yaw*TAU/8
				var occupied := _bounds(wolf, true)
				expect(occupied.position.x>=-2 and occupied.end.x<=2 and occupied.position.z>=-2 and occupied.end.z<=2 and occupied.end.y<3,"posed wolf fits clearance through every facing")
	_navigation_checks(wolf)
	for error in failures: push_error(error)
	print("PROPORTION_INTEGRATION_OK: %d checks"%checks if failures.is_empty() else "PROPORTION_INTEGRATION_FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect_widths(actor: Node3D) -> void:
	expect(absf(actor._body.basis.get_scale().x-.8)<.001 and absf(actor._head.basis.get_scale().x-.93)<.001,"poses and resets retain authored proportion factors")

func _bounds(actor: Node3D, with_yaw := false) -> AABB:
	var bounds := AABB(); var first := true
	var frame := Transform3D(Basis.IDENTITY,actor.global_position) if with_yaw else actor.global_transform
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.name=="OccludedSilhouette": continue
		var part: AABB=frame.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=part if first else bounds.merge(part); first=false
	return bounds

func _navigation_checks(wolf: Node3D) -> void:
	var world := root.get_node("WorldData")
	var grass: int=root.get_node("BlockRegistry").get_id("base:terrain:surface:grass_01")
	for x in range(38,54):
		for z in range(38,48):
			for y in range(20,26): world.set_block(x,y,z,grass if y==20 else 0)
	var from := Vector3i(40,21,40); var flat := from+Vector3i(2,0,0)
	expect(Navigation.can_hop(from,flat,3,4),"large footprint retains two-cell flat stride")
	wolf.cell=from; wolf._hop(flat)
	expect(is_equal_approx(wolf.hop_seconds,.95),"ordinary flat speed unchanged")
	world.set_block(45,23,43,grass)
	expect(not Navigation.can_hop(from,flat,3,4),"far upper corner blocks enlarged sweep")
	world.set_block(45,23,43,0); world.set_block(45,20,43,0)
	expect(not Navigation.can_hop(from,flat,3,4),"far support corner cannot cross a pit")
	world.set_block(45,20,43,grass); world.set_block(40,23,40,grass)
	expect(not Navigation.standable(from,3,4),"two-high tunnel rejects enlarged wolf")
	world.set_block(40,23,40,0)
	for x in range(44,48):
		for z in range(40,44): world.set_block(x,21,z,grass)
	var terrace := from+Vector3i(4,1,0)
	expect(Navigation.can_hop(from,terrace,3,4) and Navigation.can_hop(terrace,from,3,4),"large wolf can step up and down with full support")
	wolf._hop(terrace)
	expect(is_equal_approx(wolf.hop_seconds,1.9),"long terrace stride preserves horizontal speed")
	wolf.hop_progress=.16
	expect(is_equal_approx(wolf._hop_position().x,42) and wolf._hop_position().y>21,"step rises before crossing terrain edge")
	world.set_block(40,24,40,grass)
	expect(not Navigation.can_hop(from,terrace,3,4),"step checks raised overhead sweep")
	world.set_block(40,24,40,0)
	expect(not Navigation.can_hop(from,from+Vector3i(2,0,2),3,4),"no diagonal shortcut")
