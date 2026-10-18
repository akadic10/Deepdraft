extends "res://scripts/tests/HaulingAnimationTest.gd"

## Slice visibility must follow ordinary stairs, without a slice-control click
## or loss of support. Otherwise upstairs workers do downstairs work invisibly.
func _run() -> void:
	create_timer(70).timeout.connect(func(): push_error("Dwarf slice movement timed out"); quit(1))
	await _setup_fixture()
	worker._food.value=1.0
	worker.sleep=1.0
	var rock: int=blocks.get_id("base:terrain:rock:rock01")
	for x in range(44,48):
		for y in range(21,22+x-44): world.set_block(x,y,40,rock)
	worker.position=Vector3(47.5,25,40.5)
	worker.apply_slice(23)
	_expect(not worker.visible,"upper landing starts hidden by the unchanged slice")
	var mismatches:=await _walk_and_check(Vector3i(43,20,40))
	_expect(mismatches==0,"descending dwarf appears as soon as its feet enter the visible slice")
	_expect(worker.current_cell()==Vector3i(43,20,40) and worker.visible,"downstairs work position is visible without changing slice")
	worker.apply_slice(23) # Independently start the ascent from a visible dwarf.
	mismatches=await _walk_and_check(Vector3i(47,24,40))
	_expect(mismatches==0,"ascending dwarf hides as soon as its feet leave the visible slice")
	_expect(worker.current_cell()==Vector3i(47,24,40) and not worker.visible,"upper landing stays concealed")
	# Restore/DEV position changes also refresh while simulation is paused.
	clock_node.set_paused(true)
	worker.position=Vector3(43.5,21,40.5)
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(worker.visible,"paused position restoration refreshes slice visibility")
	worker.apply_slice(127)
	worker.position=Vector3(47.5,25,40.5)
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(worker.visible,"whole-world view remains visible after movement")
	for failure in failures: push_error(failure)
	print("DWARF_SLICE_MOVEMENT_OK" if failures.is_empty() else "DWARF_SLICE_MOVEMENT_FAIL")
	quit(0 if failures.is_empty() else 1)

func _walk_and_check(destination: Vector3i) -> int:
	_expect(worker.walk_to(destination),"real navigation finds the staircase")
	var wrong:=0
	for i in 240:
		if not worker.is_walking(): break
		worker._process(.05)
		await process_frame
		await RenderingServer.frame_post_draw
		if worker.visible != (floori(worker.global_position.y)<=23): wrong+=1
	print("SLICE_VISIBILITY_MISMATCHES ",wrong," destination=",destination)
	return wrong
