extends SceneTree

## Large restore bursts retain every exact edit but schedule mesh/navigation
## invalidation once per affected chunk, without filling the deferred-call queue.
var failures: Array[String] = []
var dirtied: Dictionary = {}
var notifications := 0
var edits := 0
var deferred_notifications := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world = root.get_node("WorldData")
	root.get_node("WorldClock").set_paused(true)
	root.get_node("TaskManager").set_process(false)
	var rock: int = root.get_node("BlockRegistry").get_id("base:terrain:rock:rock01")
	for x in range(32,34):
		for y in range(1,5):
			for z in range(32,34): world.get_chunk(x,y,z)
	world.chunk_dirtied.connect(_chunk_dirty)
	world.chunk_dirtied.connect(_deferred_chunk,CONNECT_DEFERRED)
	world.block_changed.connect(func(_cell: Vector3i,_old: int,_new: int): edits += 1)
	world.begin_edit_batch()
	world.begin_edit_batch()
	for x in range(512,544):
		for y in range(16,80):
			for z in range(512,544): world.set_block(x,y,z,rock)
	_expect(edits==65536,"all 65,536 exact block changes are delivered")
	_expect(notifications==0 and deferred_notifications==0,"no chunk callbacks escape an open batch")
	_expect(world.get_terrain_block(543,79,543)==rock,"world truth is available before notification flush")
	_expect(world.get_chunk(33,4,33).is_dirty,"chunk dirtiness is marked immediately")
	world.end_edit_batch()
	_expect(notifications==0,"nested end does not flush the outer batch")
	world.set_block(512,16,512,rock)
	_expect(edits==65536,"unchanged writes do not invent exact edits")
	world.end_edit_batch()
	_expect(notifications==16 and dirtied.size()==16,"large burst emits exactly one update for each of 16 chunks")
	_expect(deferred_notifications==0,"deferred consumers retain their normal delivery boundary")
	await process_frame
	await process_frame
	_expect(deferred_notifications==16,"deferred consumers receive every coalesced update")
	world.set_block(512,16,512,0)
	_expect(notifications==17 and edits==65537,"ordinary gameplay changes still notify immediately")
	world.begin_edit_batch()
	world.set_block(512,16,513,0)
	world.clear_world()
	_expect(world._edit_batch_depth==0 and world._batched_dirty_chunks.is_empty(),"world reset retires pending batch state")
	for failure in failures: push_error(failure)
	print("TERRAIN_EDIT_BATCH_OK" if failures.is_empty() else "TERRAIN_EDIT_BATCH_FAIL")
	quit(0 if failures.is_empty() else 1)

func _chunk_dirty(x: int,y: int,z: int) -> void:
	notifications += 1
	dirtied[Vector3i(x,y,z)] = true

func _deferred_chunk(_x: int,_y: int,_z: int) -> void:
	deferred_notifications += 1

func _expect(condition: bool,message: String) -> void:
	if not condition: failures.append(message)
