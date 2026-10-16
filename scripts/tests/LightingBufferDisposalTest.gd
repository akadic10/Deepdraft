extends "res://scripts/tests/HaulingAnimationTest.gd"

var old_script: GDScript
var current_script: GDScript
var old_field: Node
var new_field: Node
var comparisons := 0
var timing := {}

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Lighting disposal timeout"); quit(1))
	await _setup_fixture()
	current_script=load("res://scripts/components/UndergroundLighting.gd")
	old_script=GDScript.new()
	old_script.source_code=FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/lighting_20261015/UndergroundLighting.gd.before.txt")
	_expect(old_script.reload()==OK,"frozen lighting compiles")
	old_field=old_script.new()
	new_field=current_script.new()
	for field in [old_field,new_field]:
		scene.add_child(field)
		field.set_process(false)
	var stone: int=blocks.get_id("base:terrain:rock:rock01")
	# Covered hall with an open entrance on the west.
	for x in range(44,57):
		for z in range(44,51):
			for y in range(21,27):
				var wall: bool=x==56 or z in [44,50] or y==26
				world.set_block(x,y,z,stone if wall else blocks.AIR_ID)
	await _compare("covered hall")
	for z in range(45,50):
		for y in range(21,26): world.set_block(44,y,z,stone)
	await _compare("sealed entrance")
	world.set_block(44,22,47,blocks.AIR_ID)
	await _compare("reopened entrance")
	world.set_block(50,26,47,blocks.AIR_ID)
	await _compare("skylight")
	world.set_block(50,26,47,stone)
	for field in [old_field,new_field]: field._process(.016)
	world.set_block(50,26,47,blocks.AIR_ID)
	await _compare("edit during calculation")
	var doors: Array[Vector3i]=[Vector3i(44,20,47)]
	root.get_node("RoomManager").on_furniture_changed("fixture",doors,{"furniture_category":"door"},true)
	await _compare("door boundary installed")
	root.get_node("RoomManager").on_furniture_changed("fixture",doors,{"furniture_category":"door"},false)
	await _compare("door boundary removed")
	await _pending_disposal()
	await _large_disposal()
	old_field.free()
	new_field.free()
	var result := {"failures":failures,"comparisons":comparisons,"timing":timing}
	DirAccess.make_dir_recursive_absolute("res://tmp/lighting_20261015")
	FileAccess.open("res://tmp/lighting_20261015/disposal.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	for failure: String in failures: push_error(failure)
	print("LIGHTING_BUFFER_DISPOSAL_PASS " if failures.is_empty() else "LIGHTING_BUFFER_DISPOSAL_FAIL ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _compare(label: String) -> void:
	for i in 6000:
		old_field._process(.016)
		new_field._process(.016)
		if not old_field.is_updating() and not new_field.is_updating(): break
		await process_frame
	_expect(not old_field.is_updating() and not new_field.is_updating(),label+": both solvers finish")
	_expect(old_field._samples==new_field._samples,label+": exact published sky samples")
	_expect(old_field._slots==new_field._slots,label+": exact tile mapping")
	_expect(old_field._table.get_data()==new_field._table.get_data(),label+": exact GPU lookup image")
	for page in 4:
		_expect(old_field._images[page].size()==new_field._images[page].size(),label+": equal layer counts")
		for layer in mini(old_field._images[page].size(),new_field._images[page].size()):
			_expect(old_field._images[page][layer].get_data()==new_field._images[page][layer].get_data(),label+": exact texture bytes")
	comparisons+=1

func _pending_disposal() -> void:
	# Deterministically hold the sole cleanup slot; edits must coalesce without
	# another task or a main-thread wait, and published lighting stays readable.
	while new_field._cleanup_task>=0:
		new_field._process(.016)
		await process_frame
	var semaphore := Semaphore.new()
	new_field._cleanup_task=WorkerThreadPool.add_task(func(): semaphore.wait())
	var task: int=new_field._cleanup_task
	var published: Dictionary=new_field._samples.duplicate()
	world.set_block(50,26,47,blocks.get_id("base:terrain:rock:rock01"))
	for i in 3: new_field._process(.016)
	_expect(new_field._cleanup_task==task and new_field._phase=="idle" and not new_field._pending.is_empty(),"busy cleanup retains pending edits without starting another job")
	_expect(new_field._samples==published,"busy cleanup does not erase published lighting")
	semaphore.post()
	await _compare("pending edits after disposal")

func _fill_buffers(field: Node, count: int) -> void:
	for i in count:
		var cell:=Vector3i(i%1024,(i/1024)%128,i/(1024*128))
		field._air[cell]=true
		field._visited[cell]=1
		field._queue.append(cell)
		field._light[cell]=1
		field._light_queue.append(cell)
		field._affected.append(cell)

func _large_disposal() -> void:
	var old: Node=old_script.new()
	var latest: Node=current_script.new()
	for field in [old,latest]:
		scene.add_child(field)
		field.set_process(false)
		field._pending.clear()
		_fill_buffers(field,250000)
	var before:=Time.get_ticks_usec()
	old._step()
	var original_usec:=Time.get_ticks_usec()-before
	# These aliases are inspected only after joining the task, never concurrently.
	var retired_air: Dictionary=latest._air
	var retired_queue: Array=latest._queue
	before=Time.get_ticks_usec()
	latest._step()
	var transfer_usec:=Time.get_ticks_usec()-before
	_expect(latest._cleanup_task>=0 and latest._air.is_empty() and latest._queue.is_empty(),"large job transfers buffers and starts with fresh state")
	var teardown_start:=Time.get_ticks_usec()
	latest.free() # exit joins disposal while its script/scene is still valid
	var teardown_usec:=Time.get_ticks_usec()-teardown_start
	_expect(retired_air.is_empty() and retired_queue.is_empty(),"teardown joins worker and clears retired data")
	old.free()
	timing={"entries_per_container":250000,"original_clear_usec":original_usec,"main_thread_transfer_usec":transfer_usec,"teardown_join_usec":teardown_usec}
