extends "res://scripts/tests/HaulingSelectionTest.gd"

var comparisons := 0
var timings := {}
var delivery_checked := false

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Preparation reuse timeout"); quit(1))
	await _setup_fixture()
	await _quotes()
	await _delivery_preparation()
	_expect(delivery_checked,"delivery checks reach their final assertion")
	_expect(tasks.lifecycle_errors().is_empty(), "preparation creates no orphan claims")
	var result := {"failures": failures, "comparisons": comparisons, "timings": timings}
	DirAccess.make_dir_recursive_absolute("res://tmp/jobs30_20261014")
	FileAccess.open("res://tmp/jobs30_20261014/preparation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	for failure: String in failures: push_error(failure)
	print("JOB_PREPARATION_REUSE_PASS " if failures.is_empty() else "JOB_PREPARATION_REUSE_FAIL ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

# Frozen pre-change selection algorithm, deliberately independent of snapshots.
func _original(from: Vector3i, exclude: Dictionary) -> Node3D:
	var best: Node3D = null
	var distance := 0x7FFFFFFF
	for node in drops._loose:
		if not is_instance_valid(node) or bool(node.get_meta("disallowed",false)) or drops._reserved.has(node): continue
		if not zone._can_haul_key(String(drops._loose[node])): continue
		var cell: Vector3i = drops.item_floor_cell(node)
		if exclude.has(cell): continue
		var delta := cell-from
		var next := absi(delta.x)+absi(delta.y)+absi(delta.z)
		if next < distance:
			best = node
			distance = next
	return best

func _compare(snapshot: Dictionary, from: Vector3i, excluded := {}) -> void:
	var query := {}
	_expect(drops.advance_nearest_haul_query(from,zone._can_haul_key,query,snapshot,Time.get_ticks_usec()+100000,excluded), "quote completes")
	_expect(query.best == _original(from,excluded), "exact pickup identity, distance and tie order")
	comparisons += 1

func _quotes() -> void:
	await _fresh(LOG,1)
	zone.set_all_accepted(false)
	zone.set_item_accepted(LOG,true)
	for i in 640:
		drops.restore_loose_item(LOG if i%2==0 else STONE, Vector3(50+i%32,21,50+i/32)+Vector3(.5,0,.5))
	var snapshot := {}
	for i in 30:
		_compare(snapshot,Vector3i(35+i,20,38+i%9))
	_compare(snapshot,Vector3i(40,20,39),{Vector3i(40,20,40):true})
	var nearest: Node3D = _original(Vector3i(40,20,39),{})
	drops.reserve(nearest,999)
	_compare(snapshot,Vector3i(40,20,39))
	drops.unreserve(nearest)
	nearest.set_meta("disallowed",true)
	drops.loose_items_changed.emit()
	_compare(snapshot,Vector3i(40,20,39))
	nearest.set_meta("disallowed",false)
	drops.take(nearest)
	nearest.free()
	_compare(snapshot,Vector3i(40,20,39))
	zone.set_item_accepted(LOG,false)
	zone.set_item_accepted(STONE,true)
	_compare(snapshot,Vector3i(40,20,39))
	var stored: Node3D = _original(Vector3i(50,20,50),{})
	drops.place_stored(stored,Vector3i(60,20,44))
	_compare(snapshot,Vector3i(50,20,50))
	drops.drop_loose(stored,Vector3i(41,20,39))
	_compare(snapshot,Vector3i(40,20,39))
	# A suspended source quote must restart when inventory/filter state changes.
	var pending := {}
	_expect(not zone.advance_haul_quote(worker.current_cell(),pending,Time.get_ticks_usec()-1), "expired deadline yields without claims")
	zone.set_item_accepted(LOG,true)
	zone.set_item_accepted(STONE,false)
	drops.restore_loose_item(LOG,Vector3(39.5,21,39.5))
	_expect(zone.advance_haul_quote(worker.current_cell(),pending,Time.get_ticks_usec()+100000), "changed inventory resumes safely")
	_expect(pending.cell==Vector3i(39,20,39), "resume sees newly available nearer goods")
	for cell: Vector3i in zone.tile_cells: zone.cell_stacks[cell]={"item":LOG,"count":1000}
	stockpiles.storage_rules_changed()
	_expect(zone.advance_haul_quote(worker.current_cell(),pending,Time.get_ticks_usec()+100000) and pending.cell.x<0,"full storage invalidates completed quote")
	zone.cell_stacks.clear()
	stockpiles.storage_rules_changed()
	# Count expensive source-filter calls, not a machine-dependent speed target.
	var counts := {"calls":0}
	var accept := func(key: String) -> bool:
		counts.calls += 1
		return zone._can_haul_key(key)
	snapshot = {}
	var old_usec := 0
	var new_usec := 0
	for i in 30:
		var from := Vector3i(35+i,20,38+i%9)
		var start := Time.get_ticks_usec()
		_original(from,{})
		old_usec += Time.get_ticks_usec()-start
		start = Time.get_ticks_usec()
		var query := {}
		_expect(drops.advance_nearest_haul_query(from,accept,query,snapshot,Time.get_ticks_usec()+100000),"shared comparison finishes")
		new_usec += Time.get_ticks_usec()-start
	_expect(counts.calls==2,"30 workers evaluate each of two item keys only once")
	_expect(drops._reserved.is_empty() and zone.reserved_cells.is_empty(),"all comparison work remains read-only")
	timings={"workers":30,"items":drops._loose.size(),"original_usec":old_usec,"shared_usec":new_usec,"filter_calls":counts.calls}

func _delivery_preparation() -> void:
	await _fresh(STONE,1)
	stockpiles.reset_runtime_state()
	# Load after autoload initialization, like production work sources.
	var Planner = load("res://scripts/components/FurnitureFetchPlanner.gd")
	var slow := GDScript.new()
	slow.source_code = "extends FurnitureGhostComponent\nvar stand_calls := 0\nvar legal: Array[Vector3i] = [Vector3i(55,20,40)]\nfunc work_stands(_from: Vector3i) -> Array[Vector3i]:\n\tstand_calls += 1\n\tOS.delay_usec(1500)\n\treturn legal.duplicate()\n"
	_expect(slow.reload()==OK,"slow preparation fixture compiles")
	var source = slow.new()
	source.item_key=STONE
	source.drop_manager=drops
	var original := GDScript.new()
	original.source_code=FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/jobs30_20261014/FurnitureFetchPlanner.gd.before.txt")
	_expect(original.reload()==OK,"original planner compiles")
	var stalled := {}
	for i in 30: original.advance(source,worker,stalled,1,Time.get_ticks_usec()+1000)
	_expect(stalled.get("stage")=="delivery" and source._preferred_fetch.is_empty(),"original planner reproduces preparation starvation")
	source.stand_calls=0
	var context := {}
	var result := -1
	for i in 150:
		result=Planner.advance(source,worker,context,1,Time.get_ticks_usec()+1000)
		if result==root.get_node("NavGrid").ProbeResult.REACHABLE: break
	_expect(result==root.get_node("NavGrid").ProbeResult.REACHABLE,"route progresses even when stand preparation exceeds the entire slice")
	_expect(source.stand_calls==2,"stands prepared once and refreshed once at handoff")
	_expect(drops._reserved.is_empty(),"planning does not claim supplies")
	context.clear()
	source._preferred_fetch.clear()
	for i in 150:
		Planner.advance(source,worker,context,1,Time.get_ticks_usec()+1000)
		if context.has("delivery_goals"): break
	_expect(context.has("delivery_goals"),"second plan reaches prepared delivery state")
	source.legal.assign([Vector3i(57,20,40)]) # Actor obstruction need not change nav revision.
	for i in 200:
		result=Planner.advance(source,worker,context,1,Time.get_ticks_usec()+1000)
		if result==root.get_node("NavGrid").ProbeResult.REACHABLE: break
	_expect(result==root.get_node("NavGrid").ProbeResult.REACHABLE and source._preferred_fetch.delivery_stand==Vector3i(57,20,40),"late eligibility change rejects old endpoint and finds a current one")
	delivery_checked=true
