extends "res://scripts/tests/HaulingAnimationTest.gd"

const APPLE := "base:resources:flora:apple"
const BERRY := "base:resources:flora:juniper_berry"
var expected_units := 0
var topups := 0

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Fruit hauling timed out"); quit(1))
	await _setup_fixture()
	if "--capture" in OS.get_cmdline_user_args(): _capture_setup()
	await _fresh(6)
	# Retries/direct pulls may not have the scheduler's optional route proof.
	var uncached: Dictionary=zone.reserve_haul(998,worker.current_cell(),{})
	_expect(not uncached.is_empty() and zone.fruit_pickup_path(998,0).is_empty(),"uncached fruit pickup falls back to normal pathfinding")
	zone.cancel_haul(998)
	_add(APPLE,7,Vector3i(42,20,49))
	_add(APPLE,9,Vector3i(40,20,57))
	_expect(await _delivered(22),"three matching fruit baskets arrive in one trip")
	_expect(zone.cell_stacks.size()==1 and _loose_units()==0,"all 22 apples end in one stored basket")
	_expect(topups==2,"two physical gathering contacts fill the existing basket")
	_expect(drops._reserved.is_empty() and zone.reserved_cells.is_empty(),"completion releases all claims")

	# Reserve only what fits; a second worker cannot steal a claimed source.
	await _fresh(20)
	var extra := _add(APPLE,10,Vector3i(40,20,45))
	_expect(await _phase(worker.TaskPhase.HAUL_PICKUP),"capacity case reaches pickup")
	var competing: Dictionary=zone.reserve_haul(902,Vector3i(40,20,45),{})
	_expect(competing.is_empty(),"planned top-up has an exclusive source claim")
	zone.cancel_haul(902)
	_expect(await _delivered(24),"one full basket delivers 24 apples")
	_expect(drops.quantity_of(extra)==6 and _loose_units()==6,"partial pickup leaves the six excess apples")
	_expect(zone.reserved_cells.is_empty() and drops._reserved.is_empty(),"partial pickup releases its remainder")

	# A partially occupied storage crate and an empty slot share one carried load.
	await _fresh(6)
	zone.cell_stacks[Vector3i(40,20,72)]={"item":APPLE,"count":20,"material_id":""}
	drops.restore_stored_item(APPLE,Vector3i(40,20,72),20)
	expected_units+=20
	_add(APPLE,8,Vector3i(40,20,47))
	_expect(await _delivered(34),"one carried basket fills partial and empty destination slots")
	_expect(zone.cell_stacks.size()==2 and _loose_units()==0,"split deposit preserves both physical storage baskets")

	# A full source with the same fruit must not conceal incompatible/forbidden goods.
	await _fresh(5)
	_add(BERRY,6,Vector3i(40,20,44))
	var forbidden := _add(APPLE,7,Vector3i(40,20,48))
	drops.set_disallowed(forbidden,true)
	_add(APPLE,4,Vector3i(40,20,54))
	_expect(await _delivered(9),"matching allowed fruit is gathered past other fruit and forbidden baskets")
	_expect(_loose_units()==13 and not drops.Permission.allowed(forbidden),"different and forbidden fruit remain untouched")

	# Fruit outside the corridor is not an invitation to take a long detour.
	await _fresh(5)
	var distant := _add(APPLE,7,Vector3i(55,20,50))
	_expect(await _delivered(5),"delivery skips fruit beyond the detour limit")
	_expect(drops.quantity_of(distant)==7,"distant fruit is not reserved or moved")
	await _fresh(5)
	var enclosed := _add(APPLE,7,Vector3i(43,20,49))
	var stone: int=blocks.get_id("base:terrain:rock:rock01")
	for x in range(42,45):
		for z in range(48,51):
			if x==43 and z==49: continue
			for y in range(21,27): world.set_block(x,y,z,stone)
	_expect(await _phase(worker.TaskPhase.HAUL_PICKUP),"blocked case starts the reachable main pickup")
	_expect(not drops._reserved.has(enclosed),"blocked side basket is never claimed by the optional route planner")
	_expect(await _delivered(5),"blocked extra does not prevent the original delivery")
	for x in range(42,45):
		for z in range(48,51):
			if x==43 and z==49: continue
			for y in range(21,27): world.set_block(x,y,z,blocks.AIR_ID)

	# Cancellation at each side of the merge contact keeps every unit exactly once.
	for after_contact in [false,true]:
		await _fresh(6)
		_add(APPLE,7,Vector3i(40,20,49))
		_expect(await _topup_contact(after_contact),"reaches top-up contact boundary")
		var before := _total()
		var saved_items: Dictionary=JSON.parse_string(JSON.stringify(drops.serialize_state()))
		var saved_worker: Dictionary=JSON.parse_string(JSON.stringify(worker.serialize_state()))
		var save_total := 0
		for item in saved_items.loose: save_total+=int(item.count)
		for item in saved_worker.carried_items: save_total+=int(item.count)
		_expect(save_total==13 and saved_worker.carried_items.size()==1,"save sees one carried basket and exact remaining source quantities")
		tasks.cancel_task(worker.current_task_id)
		_expect(_total()==before and _loose_units()==13 and worker._carried_entries.is_empty(),"interruption drops one basket and preserves every apple")
		_expect(drops._reserved.is_empty() and zone.reserved_cells.is_empty(),"interruption releases all quantity reservations")

	await _fresh(6)
	_add(APPLE,7,Vector3i(40,20,49))
	_expect(await _topup_contact(true),"merged load exists before filter change")
	zone.set_item_accepted(APPLE,false)
	_expect(_loose_units()==13 and worker.current_task_id<0 and zone.reserved_cells.is_empty(),"filter change safely cancels merged cargo")

	# Other permissions changing must not treat a consumed source as invalid cargo.
	await _fresh(6)
	_add(APPLE,7,Vector3i(40,20,49))
	var unrelated := _add(BERRY,2,Vector3i(80,20,80))
	_expect(await _topup_contact(true),"merged load exists before unrelated permission edit")
	drops.set_disallowed(unrelated,true)
	_expect(worker.current_task_id>=0,"unrelated permission edit leaves merged fruit delivery active")
	_expect(await _delivered(13),"merged fruit completes after unrelated permission edit")

	# The optional planner can always abandon optimization when its budget expires.
	var planner=load("res://scripts/components/FruitHaulPlanner.gd")
	var route: Array[Vector3i]=[Vector3i(40,20,40),Vector3i(40,20,41)]
	_expect(planner.candidate(drops,APPLE,"",route,{},8,Time.get_ticks_usec()-1,{}).is_empty(),"expired planning budget returns immediately")
	for failure in failures: push_error(failure)
	print("FRUIT_HAULING_OK" if failures.is_empty() else "FRUIT_HAULING_FAIL: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)

func _fresh(amount: int) -> void:
	await _new_trip(APPLE,amount)
	stockpiles.deregister_zone(zone)
	zone=load("res://scripts/components/StockpileZoneComponent.gd").new()
	var cells: Array[Vector3i]=[Vector3i(40,20,72),Vector3i(41,20,72),Vector3i(42,20,72),Vector3i(43,20,72)]
	zone.setup(991,cells)
	stockpiles.register_zone(zone)
	worker._food.value=1.0
	expected_units=amount
	topups=0

func _add(key: String, amount: int, cell: Vector3i) -> Node3D:
	drops.restore_loose_item(key,Vector3(cell)+Vector3(.5,1,.5),0,amount)
	expected_units+=amount
	return drops._loose.keys()[-1]

func _tick() -> void:
	zone.update_leases()
	tasks._run_scheduler()
	var was_topup: bool=worker._work_execution._handling_fruit_topup
	var was_lifted: bool=worker._work_execution._handling_lifted
	worker._process(.05)
	if was_topup and not was_lifted and worker._work_execution._handling_lifted: topups+=1
	_expect(_total()==expected_units,"goods conserved through every pickup/contact/delivery frame")
	_expect(worker._carried_entries.size()<=1,"fruit load stays one physical basket")
	if "--capture" in OS.get_cmdline_user_args() and expected_units==22 and worker._work_execution._handling_fruit_topup:
		var label := "after_contact" if worker._work_execution._handling_lifted else "before_contact"
		if not captured.has(label):
			captured[label]=true
			camera.position=worker.position+Vector3(-8,6,10)
			camera.look_at(worker.position+Vector3(0,1.2,.5))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/fruit_hauling_fix_20261019/"+label+".png")
	await process_frame

func _total() -> int:
	return _snapshot_units()+zone.stored_count()

func _phase(value: int) -> bool:
	for i in 1800:
		if worker._task_phase==value: return true
		await _tick()
	return false

func _delivered(count: int) -> bool:
	for i in 2400:
		if zone.stored_count()>=count: return zone.stored_count()==count
		await _tick()
	return false

func _topup_contact(after: bool) -> bool:
	for i in 1800:
		if worker._work_execution._handling_fruit_topup and bool(worker._work_execution._handling_lifted)==after: return true
		await _tick()
	return false

var captured := {}

func _capture_setup() -> void:
	root.size=Vector2i(1280,800)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=9
	scene.add_child(camera)
	camera.current=true
	var floor_node:=MeshInstance3D.new()
	var mesh:=PlaneMesh.new()
	mesh.size=Vector2(128,128)
	floor_node.mesh=mesh
	floor_node.position=Vector3(64,21,64)
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("79916b")
	floor_node.material_override=material
	scene.add_child(floor_node)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-25,0)
	light.shadow_enabled=true
	scene.add_child(light)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("809196")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.6
	scene.add_child(env)
