extends "res://scripts/tests/WorkerCraftingTest.gd"

var water
var water_stones
class TestLighting extends RefCounted:
	func make_material(base: Material) -> Material: return base
class TestTerrain extends Node3D:
	var underground_lighting = TestLighting.new()
	var slice_y := 127
	func is_revealed_air(_cell: Vector3i) -> bool: return true

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Water stone lifecycle timed out"); quit(1))
	await _setup_crafting_fixture()
	water = root.get_node("WaterManager")
	water.set_process(false)
	var generator = root.get_node("WorldGenerator")
	generator.waterline_map.resize(1024*1024)
	generator.waterline_map.fill(-1)
	generator.water_profile = generator.load_water_profile()
	water._config = generator.water_profile
	water.flow = load("res://scripts/components/WaterFlow.gd").new()
	water.flow.spans_at = func(col: Vector2i): return [Vector2i(21,128)] if col.x>=0 and col.x<128 and col.y>=0 and col.y<128 else []
	water.flow.conductance = 0 # Isolate each real stone's effect from lateral exchange.
	water.moisture = load("res://scripts/components/SoilMoisture.gd").new()
	water._water_id = blocks.get_id("base:terrain:water:source")
	water.initialized = true
	water.stones = {"wet":{"kind":"wet","cell":Vector3i(44,21,40),"intake":Vector3i(44,21,41),"level":22.0,"placed":true,"disallowed":true,"packing":false,"work":0.0},
		"dry":{"kind":"dry","cell":Vector3i(46,21,40),"intake":Vector3i(46,21,40),"level":22.0,"placed":true,"disallowed":true,"packing":false,"work":0.0}}
	var terrain := TestTerrain.new()
	scene.add_child(terrain)
	water_stones = load("res://scripts/components/WaterStones.gd").new()
	water_stones.terrain = terrain
	scene.add_child(water_stones)
	water_stones._process(0)
	water.flow.seed_column(Vector3i(46,21,40),3.0)
	water.step(.1)
	_expect(water.flow.added>0 and water.flow.drained>0, "disallowed natural stones still function")
	_expect(not water_stones.request_pack("wet"), "natural stones refuse packing by default")
	water_stones.set_disallowed("wet",false)
	await _frames(3)
	_expect(drops._loose.is_empty() and not water.stones.wet.packing, "allow alone does not auto-haul placed stone")
	furniture.begin_water_stone_move("wet")
	furniture._hover_cell = Vector3i(54,20,40)
	furniture._confirm_ghost()
	_expect(water.stones.wet.packing and furniture._ghosts.size()==1, "move requests actual packing and a single destination")
	_expect(await _phase(worker.TaskPhase.UNINSTALL_WORKING), "dwarf reaches stone and works")
	worker._process(.3)
	_expect(water.stones.wet.work>0 and water.stones.wet.placed, "packing work persists while source remains active")
	# Forbid while actively packing: progress survives, source and item count unchanged.
	water_stones.set_disallowed("wet",true)
	_expect(furniture._ghosts.is_empty() and not water.stones.wet.packing and water.stones.wet.placed, "disallow cancels move and pack without deleting stone")
	water_stones.set_disallowed("wet",false)
	furniture.begin_water_stone_move("wet")
	furniture._hover_cell = Vector3i(54,20,40)
	furniture._confirm_ghost()
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST), "real worker packs and carries same stone")
	_expect(not water.stones.wet.placed and worker._fetch_item.get_meta("instance_id")=="wet", "carried stone retains identity and deactivates")
	var before: float = water.flow.added
	water.step(.1)
	_expect(water.flow.added==before, "no phantom spring at original location while carried")
	var cargo: Array = worker.serialize_state().carried_items
	_expect(cargo.size()==1 and cargo[0].instance_id=="wet", "in-transit save owns stone exactly once")
	for i in 500:
		if water.stones.wet.placed: break
		await _tick()
	_expect(water.stones.wet.placed and water.stones.wet.cell==Vector3i(54,21,40), "worker completes relocation to chosen cell")
	_expect(worker._carried_entries.is_empty() and drops._loose.is_empty(), "placement consumes packed form exactly once")
	water.step(.1)
	_expect(water.flow.volume(Vector3i(54,21,40))>0, "relocated source feeds new cell")
	# Future scenario boundary creates extra inactive items with unique IDs.
	var extra_wet: String = water.grant_stone("wet",Vector3i(60,21,40))
	var extra_dry: String = water.grant_stone("dry",Vector3i(62,21,40))
	_expect(extra_wet!=extra_dry and water.stones.size()==4, "additional pair has independent identities")
	var item: Node3D = null
	for node in drops._loose:
		_expect(not drops.Permission.allowed(node), "new scenario stones default disallowed")
		if node.get_meta("instance_id")==extra_wet: item=node
	drops.set_disallowed(item,false)
	furniture.begin_water_stone_move(extra_wet)
	furniture._hover_cell = Vector3i(65,20,40)
	furniture._confirm_ghost()
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST), "extra stone uses same physical placement pipeline")
	drops.set_disallowed(worker._fetch_item,true)
	_expect(furniture._ghosts.is_empty() and worker._carried_entries.is_empty() and not water.stones[extra_wet].placed, "disallow in transit safely drops extra stone and cancels plan")
	drops.set_disallowed(item,false)
	furniture.begin_water_stone_move(extra_wet)
	furniture._hover_cell = Vector3i(65,20,40)
	furniture._confirm_ghost()
	for i in 600:
		if water.stones[extra_wet].placed: break
		await _tick()
	water.step(.1)
	_expect(water.stones[extra_wet].placed and water.flow.volume(Vector3i(65,21,40))>0 and water.stones.wet.placed, "multiple placed wet stones function independently")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(water.serialize_state()))
	water.restore_state(saved)
	water_stones._process(0)
	_expect(water.stones.size()==4 and water.next_stone_id==3 and water.stones.wet.cell==Vector3i(54,21,40), "stone identities and locations survive JSON restore")
	if "--capture" in OS.get_cmdline_user_args(): await _review_ui()
	if failures.is_empty(): print("WATER_STONE_LIFECYCLE_OK: real pack/move work, cancellation, relocated effects, inactive cargo, multiple pairs and JSON state")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _review_ui() -> void:
	explorer = load("res://scripts/ui/ObjectExplorerController.gd").new()
	explorer.window_manager_path = NodePath("../Windows")
	scene.add_child(explorer)
	camera.position = Vector3(62,30,53)
	camera.look_at(Vector3(54.5,21.5,40.5))
	water_stones.set_disallowed("wet",true)
	for size in [Vector2i(960,540),Vector2i(2560,1440)]:
		root.size=size
		water_stones._process(0)
		_expect(explorer.select_object(water_stones,"wet"),"placed stone can be inspected")
		await _frames(8)
		_expect(explorer._window.get_global_rect().end.y<=size.y,"stone controls fit viewport")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/stone_disallowed_%dx%d.png" % [size.x,size.y])
		explorer._perform_action("permission")
		await _frames(5)
		_expect(not water.stones.wet.disallowed,"native inspector Allow updates placed stone")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/water_review/stone_allowed_%dx%d.png" % [size.x,size.y])
		water_stones.set_disallowed("wet",true)
	# Packed stones in Place share their inventory artwork and permission gate.
	var dry: Node3D = null
	for node in drops._loose:
		if drops.item_key_of(node)=="base:resources:water:dry_stone": dry=node
	_expect(dry!=null and furniture.get_catalog_stock()["base:water:dry_stone"].available==0,"forbidden packed stone hidden from available stock")
	drops.set_disallowed(dry,false)
	manager.close(explorer.WINDOW_ID)
	root.size=Vector2i(960,540)
	await _frames(6)
	dock._open_place_catalog()
	var catalog = dock._place_catalog
	catalog.category="water"
	catalog.refresh()
	catalog._select("base:water:dry_stone")
	await _frames(8)
	_expect(catalog._tiles["base:water:dry_stone"].image.texture!=null and not catalog._place.disabled,"allowed packed stone has thumbnail and enabled Place")
	_expect(catalog.window.get_global_rect().end.y<=540,"Water catalog fits compact screen")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/water_review/water_place_960x540.png")
	furniture.deactivate()
