extends "res://scripts/tests/HaulingAnimationTest.gd"

var construction: Node3D
var original: Node3D
var old_work: RefCounted
var new_work: RefCounted
var old_scripts: Array[GDScript] = []
var comparisons := 0
var before_usec := 0
var after_usec := 0

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Construction obstacle timeout"); quit(1))
	await _setup_fixture()
	construction=load("res://scripts/systems/ConstructionController.gd").new()
	scene.add_child(construction)
	construction.set_process(false)
	for name in ["ConstructionController","ConstructionWork"]:
		var script:=GDScript.new()
		script.source_code=FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/colony_scaling_20261014/"+name+".before.txt")
		# Godot 4.7 rejects the original untyped ternary literal when carrying.
		# Normalize that declaration only, keeping the original scanning algorithm.
		if name=="ConstructionWork":
			script.source_code=script.source_code.replace('var candidates: Array[Vector3i] = [target] if not _carried_by.is_empty() else cells','var candidates: Array[Vector3i] = []\n\tif not _carried_by.is_empty(): candidates.append(target)\n\telse: candidates = cells')
		_expect(script.reload()==OK,"frozen "+name+" compiles")
		old_scripts.append(script)
	original=old_scripts[0].new()
	scene.add_child(original)
	original.set_process(false)
	old_work=old_scripts[1].new()
	new_work=load("res://scripts/components/ConstructionWork.gd").new()
	old_work.controller=original
	new_work.controller=construction
	var cells: Array[Vector3i]=[]
	for x in range(48,56):
		for z in range(48,54): cells.append(Vector3i(x,21,z))
	for work in [old_work,new_work]:
		work.setup(1,"stone",construction.definition,Vector3i(48,20,48),0)
		work.cells=cells.duplicate()
		work.drop_manager=drops
	for i in 640:
		drops.restore_loose_item(STONE,Vector3(65+i%32,21,50+i/32)+Vector3(.5,0,.5))
	_compare("many distant loose items")
	drops.restore_loose_item(STONE,Vector3(50.5,21,50.5))
	var item: Node3D=drops._loose.keys().back()
	drops.restore_loose_item(STONE,Vector3(50.6,21,50.4))
	var second: Node3D=drops._loose.keys().back()
	drops.reserve(item,worker.dwarf_id)
	_compare("reserved and colocated items still obstruct")
	drops.take(item)
	worker.add_child(item)
	_compare("one item picked up; another remains")
	drops.take(second)
	worker.add_child(second)
	_compare("both items carried")
	drops.drop_loose(item,Vector3i(52,20,50))
	drops.place_stored(second,Vector3i(54,20,50))
	_compare("release and stored transition")
	worker.position=Vector3(49.999,21,49.5)
	_compare("fractional dwarf overlap")
	worker.position=Vector3(40.5,21,39.5)
	_compare("moving worker immediately clears candidate")
	var handle: int=root.get_node("PlacedEntityRegistry").register_box(Vector3i(51,21,50),Vector3i(1,3,1))
	_compare("placed occupancy")
	root.get_node("PlacedEntityRegistry").unregister(handle)
	world.set_block(53,21,50,blocks.get_id("base:terrain:rock:rock01"))
	_compare("new solid terrain")
	world.set_block(53,21,50,blocks.AIR_ID)
	_compare("mined terrain")
	for work in [old_work,new_work]:
		work.target=Vector3i(48,21,48)
		work._carried_by[worker.dwarf_id]=true
	_compare("carrying restricts to chosen work unit")
	for work in [old_work,new_work]: work._carried_by.clear()
	# Alternating order controls shared navigation-cache warmup. No simulation
	# runs between paired calls; every stand and target map must be identical.
	for trial in 24: _compare("timing %d" % trial,trial%2==0,true)
	var result: Dictionary={"failures":failures,"comparisons":comparisons,
		"timed_calls_per_version":24,"old_usec":before_usec,"new_usec":after_usec}
	DirAccess.make_dir_recursive_absolute("res://tmp/colony_scaling_20261014")
	FileAccess.open("res://tmp/colony_scaling_20261014/obstacle_reuse.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	for failure: String in failures: push_error(failure)
	print("CONSTRUCTION_OBSTACLE_REUSE_PASS " if failures.is_empty() else "CONSTRUCTION_OBSTACLE_REUSE_FAIL ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _compare(label: String, old_first := true, timed := false) -> void:
	var results: Dictionary={}
	for work in ([old_work,new_work] if old_first else [new_work,old_work]):
		var started:=Time.get_ticks_usec()
		var stands: Array=work.work_stands(worker.current_cell())
		var duration:=Time.get_ticks_usec()-started
		results[work]=[stands,work._stand_targets.duplicate()]
		if timed:
			if work==old_work: before_usec+=duration
			else: after_usec+=duration
	_expect(results[old_work]==results[new_work],label+": exact work stands and target mapping")
	var snapshot: Dictionary=construction.obstacle_snapshot()
	for cell: Vector3i in new_work.cells:
		_expect(construction.build_reason(cell,false,true,"stone",snapshot)==original.build_reason(cell,false),label+": exact rejection reason")
	comparisons+=1
