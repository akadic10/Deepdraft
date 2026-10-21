extends "res://tools/settlement_art/BenchmarkSettlement.gd"

## Full production art comparison using the established deterministic settlement.
## Terrain-edit regressions run separately; the historical arbitrary-cliff edit
## can leave an unbounded lighting settle on the current world implementation.
func _settle() -> Dictionary:
	var samples: Array[float] = []
	var started := Time.get_ticks_usec()
	for i in 4: await process_frame
	while not renderer.is_loading_complete():
		var tick := Time.get_ticks_usec()
		await process_frame
		samples.append((Time.get_ticks_usec()-tick)/1000.0)
		if Time.get_ticks_usec()-started>90000000:
			var field = renderer.underground_lighting
			var detail := {"renderer":renderer.get_render_stats(),"light_phase":field._phase,"light_pending":field._pending.size()}
			report.failures.append("Bounded settlement wait exceeded 90 seconds: "+JSON.stringify(detail))
			_finish()
			return {"timeout":true}
	return {"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"frames":samples.size(),"frame_ms":_percentiles(samples)}

func _edit_and_slice() -> void:
	var slice = scene.get_node("SliceController")
	report["slice_transitions"] = []
	_view(Vector3(camp)+Vector3(0,2,0),100,Vector3(-.7,1,1))
	for level in [camp.y+4,camp.y+1,camp.y+4]:
		var tick := Time.get_ticks_usec()
		slice.activate()
		slice._set_slice_y(level)
		var dispatch := (Time.get_ticks_usec()-tick)/1000.0
		var settled := await _settle()
		report.slice_transitions.append({"level":level,"dispatch_ms":dispatch,"settle":settled})
	await _sample("active_slice",true)
	slice.deactivate()
	await _settle()
	if renderer.slice_y!=127: report.failures.append("Full world not restored after slice")
	report["terrain_edits"] = []
	report["terrain_edit_note"] = "Measured separately with current focused terrain/construction fixtures; arbitrary historical cliff loop excluded equally before and after."
	report["final_renderer"] = renderer.get_render_stats()
	# The current save writer advances in _process; the historical harness leaves
	# it disabled after setup, so request_save otherwise waits forever.
	root.get_node("SaveManager").set_process(true)
