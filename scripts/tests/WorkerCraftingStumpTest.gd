extends "res://scripts/tests/WorkerCraftingTest.gd"

const STUMP_OUT := "res://tmp/worker_crafting_review/stump"
const STUMP_CELL := Vector3i(45,20,42)
const SIDES := [Vector3i(0,0,-1),Vector3i(1,0,0),Vector3i(0,0,1),Vector3i(-1,0,0)]
const SIDE_NAMES := ["North","East","South","West"]

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Stump crafting test timed out"); quit(1))
	await _setup_crafting_fixture()
	dock.hide()
	root.get_node("WorkFeedback").set_muted(true)
	root.get_node("SkyController").set_process(false)
	root.size = Vector2i(640,480)
	camera.size = 6.7
	var center := Vector3(STUMP_CELL)+Vector3(.5,2,.5)
	camera.position = center+Vector3(8,7,10)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var caption := Label.new()
	caption.position = Vector2(18,16)
	caption.add_theme_font_size_override("font_size",20)
	layer.add_child(caption)
	var review := Image.create(1280,960,false,Image.FORMAT_RGBA8)
	var definition: Dictionary = furniture.get_defs()[BENCH]
	for yaw in range(4):
		# Existing saved benches use the same identity/origin. Loading now
		# releases the old second tile instead of adding occupied terrain.
		furniture.restore_state({"installed":[{"id":1,"key":BENCH,
			"origin":[45,20,42],"yaw":yaw,"layout_version":1}]})
		var bench = furniture._installed[1]
		var model_bounds: AABB = furniture._visual_bounds(definition,STUMP_CELL,yaw)
		_expect(model_bounds.size.x<=1.001 and model_bounds.size.z<=1.001 and model_bounds.size.y<=1.001,"imported stump fits its collision at every rotation")
		_expect(bench.cells==[STUMP_CELL],"restored stump occupies one tile at yaw %d" % yaw)
		_expect(not root.get_node("NavGrid").is_walkable(STUMP_CELL),"stump blocks its own tile")
		for direction: Vector3i in SIDES:
			_expect(root.get_node("NavGrid").is_walkable(STUMP_CELL+direction),"all four neighboring tiles remain open")
		for side in range(4):
			var direction: Vector3i = SIDES[side]
			worker.position = Vector3(STUMP_CELL+direction*3)+Vector3(.5,1,.5)
			drops.spawn_drop(PINE,1,STUMP_CELL+direction*2+Vector3i.UP)
			var id: int = crafting.queue_order(TORCH_RECIPE,1)
			_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"Worker reaches stump from %s at yaw %d" % [SIDE_NAMES[side],yaw])
			var order = crafting.get_order(id)
			_expect(order.work_cell==STUMP_CELL+direction,"crafting uses approached side independently of stump rotation")
			worker._process(.63)
			var surface: Vector3 = order.work_surface()
			var toward: Vector3 = surface-worker.global_position
			toward.y = 0
			_expect(worker.global_basis.z.dot(toward.normalized())>.999,"Worker faces the stump")
			var bounds: AABB = worker._carry_pose.item_bounds(worker._fetch_item)
			_expect(is_equal_approx(worker._fetch_item.global_position.y+bounds.position.y,
				bench.node.global_position.y+float(definition.crafting_surface_height)),"log rests on cut top")
			var contact: Vector3 = worker._fetch_item.global_position+Vector3.UP*bounds.end.y
			var cutting_edge: Vector3 = worker._felling_pose.axe.to_global(worker.FellingPose.CUTTING_EDGE)
			_expect(cutting_edge.distance_to(contact)<.001,"axe contacts material from each direction")
			if yaw==0 and "--capture" in OS.get_cmdline_user_args():
				caption.text = SIDE_NAMES[side]+" approach"
				await _frames(3)
				await RenderingServer.frame_post_draw
				var frame := root.get_texture().get_image()
				frame.convert(Image.FORMAT_RGBA8)
				review.blit_rect(frame,Rect2i(0,0,640,480),Vector2i((side%2)*640,(side/2)*480))
			_expect(await _completed(id),"torch batch completes from %s at yaw %d" % [SIDE_NAMES[side],yaw])
		if yaw<3:
			furniture.dev_remove_installed(bench.installed_id)
			await _frames(2)
	_expect(_count(TORCH_ITEM)==64,"sixteen directional batches consume sixteen logs and produce 64 torches")
	# Start on the opposite side from the ingredient. Reconsider the stand
	# after pickup rather than walking around to the old assignment position.
	worker.position = Vector3(STUMP_CELL+Vector3i(0,0,-3))+Vector3(.5,1,.5)
	drops.spawn_drop(PINE,1,STUMP_CELL+Vector3i(0,1,3))
	var id: int = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"opposite-side pickup reaches stump")
	_expect(crafting.get_order(id).work_cell==STUMP_CELL+Vector3i(0,0,1),"post-pickup position selects the near side")
	crafting.remove_order(id)
	# A wall on three sides still leaves a usable workshop at its open edge.
	for item in drops._loose.keys():
		if drops.item_key_of(item)==PINE: drops.take(item); item.free()
	for direction: Vector3i in [SIDES[0],SIDES[2],SIDES[3]]:
		for y in range(1,4): world.set_block(STUMP_CELL.x+direction.x,20+y,STUMP_CELL.z+direction.z,blocks.get_id("base:terrain:rock:rock01"))
	await _frames(3)
	worker.position = Vector3(STUMP_CELL+Vector3i(3,0,0))+Vector3(.5,1,.5)
	drops.spawn_drop(PINE,1,STUMP_CELL+Vector3i(2,1,0))
	id = crafting.queue_order(TORCH_RECIPE,1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING),"stump remains usable with three blocked sides")
	_expect(crafting.get_order(id).work_cell==STUMP_CELL+Vector3i(1,0,0),"only clear side is used")
	crafting.remove_order(id)
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(STUMP_OUT)
		review.save_png(STUMP_OUT+"/four_sides.png")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CRAFTING_STUMP_OK: saved footprint, four approaches at four rotations, material/axe alignment, 16 completed batches, post-pickup side selection and blocked sides")
	quit(0 if failures.is_empty() else 1)
