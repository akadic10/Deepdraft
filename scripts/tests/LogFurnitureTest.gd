extends "res://scripts/tests/WorkerCraftingTest.gd"

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Log furniture timeout"); quit(1))
	await _setup_crafting_fixture()
	var rooms = root.get_node("RoomManager")
	var nav = root.get_node("NavGrid")
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45,20,42), 0)
	drops.spawn_drop(PINE,4,Vector3i(42,21,42))
	for name in ["door", "log_door_3", "log_door_4", "bench"]:
		worker.stop_walking()
		worker.position = Vector3(42.5,21,40.5)
		var key: String = "base:furniture:"+name
		var recipe: String = "base:recipe:worker:"+name
		var item: String = "base:resources:furniture:"+name
		_expect(dock._place_catalog._tiles.has(key), "Place exposes "+name)
		_expect(await _completed(crafting.queue_order(recipe,1)), "Worker crafts "+name)
		_expect(_count(item)==1, "exactly one packed "+name)
		var origin := Vector3i(52,20,42) if name=="bench" else Vector3i(58+(["door","log_door_3","log_door_4"].find(name))*12,20,46)
		var def: Dictionary = furniture.get_defs()[key]
		if name!="bench": _room(origin, int(def.footprint.width))
		await _frames(2)
		furniture.activate_for(key,true)
		_expect(is_instance_valid(furniture._visuals.preview), "placement loads a model preview: " + name)
		furniture._yaw = 0
		furniture._hover_cell = origin
		_expect(furniture._placement_valid(origin), "fits prepared opening: "+name)
		furniture._confirm_ghost()
		furniture.deactivate()
		_expect(await _installed(key), "Worker delivers and installs "+name)
		_expect(_count(item)==0, "installation consumes one crate: "+name)
		var piece = furniture._installed.values().filter(func(p): return p.furniture_key==key)[0]
		if name=="bench": continue
		var width := int(def.footprint.width)
		var animation = piece.node.get_node("DoorAnimation")
		animation.set_process(false)
		_expect(animation._hinges.size()==(2 if width==4 else 1), "correct leaf count: "+name)
		worker.position = piece.node.to_global(Vector3(0,0,10))
		animation._process(2)
		worker.position = piece.node.to_global(Vector3(0,0,2))
		animation._process(.4)
		_expect(is_equal_approx(animation._angle,PI*.5), "opens on approach: "+name)
		var direction: float = animation._direction
		clock_node.paused = true
		worker.position += Vector3(0,0,8)
		animation._process(3)
		_expect(is_equal_approx(animation._angle,PI*.5), "pause freezes hinge: "+name)
		clock_node.paused = false
		animation._process(2)
		_expect(is_zero_approx(animation._angle), "closes after departure: "+name)
		worker.position = piece.node.to_global(Vector3(0,0,-2))
		animation._process(.4)
		_expect(animation._direction==-direction, "opens away from either side: "+name)
		if width==4:
			_expect(is_equal_approx(animation._hinges[0].rotation.y,-animation._hinges[1].rotation.y), "double leaves swing apart")
		rooms._rebuild_all_rooms()
		var fill: Dictionary = rooms.get_room_at(origin+Vector3i(0,1,2))
		_expect(not fill.is_empty() and fill.door_cells.size()==1, "open door seals one room: "+name)
		for cell in piece.cells:
			_expect(nav.is_walkable(cell), "door footprint stays traversable: "+name)
		worker.position = Vector3(origin)+Vector3(.5,1,-2.5)
		var goal := origin+Vector3i(0,0,3)
		_expect(worker.walk_to(goal), "route crosses doorway: "+name)
		for i in 400:
			worker._process(.04)
			animation._process(.04)
			if not worker.is_walking(): break
			await process_frame
		_expect(worker.current_cell()==goal, "dwarf walks through: "+name)
		# Serialize/restore through the real owner, including rotated geometry.
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		var entry: Dictionary = saved.installed.filter(func(p): return p.key==key)[0]
		furniture._teardown_installed(piece.installed_id,false)
		await _frames(2)
		rooms._rebuild_all_rooms()
		_expect(rooms.get_room_at(origin+Vector3i(0,1,2)).is_empty(), "uninstall unseals opening: "+name)
		furniture.restore_state({"installed":[entry],"ghosts":[]})
		var restored = furniture._installed[int(entry.id)]
		_expect(restored.node.get_node("DoorAnimation")._hinges.size()==(2 if width==4 else 1), "restore recreates hinges: "+name)
		rooms._rebuild_all_rooms()
		_expect(not rooms.get_room_at(origin+Vector3i(0,1,2)).is_empty(), "restore reseals room: "+name)
		for yaw in range(4):
			var rotated := Vector3i(105,20,40+yaw*8)
			furniture._install(key,def,rotated,yaw)
			var rotated_piece = furniture._installed[furniture._next_installed_id-1]
			var hinge = rotated_piece.node.get_node("DoorAnimation")
			hinge.set_process(false)
			worker.position = rotated_piece.node.to_global(Vector3(0,0,2))
			hinge._process(.4)
			_expect(rotated_piece.cells.size()==width and hinge._angle>1.5, "rotated doorway works: %s/%d" % [name,yaw])
			furniture._teardown_installed(rotated_piece.installed_id,false)
	_expect(_count(PINE)==0, "four crafts consume four logs")
	for failure in failures: push_error(failure)
	print("LogFurnitureTest: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _room(origin: Vector3i, width: int) -> void:
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(origin.x-2,origin.x+width+2):
		for z in range(origin.z,origin.z+7):
			for y in range(21,26):
				if z==origin.z and x>=origin.x and x<origin.x+width and y<25: continue
				if x==origin.x-2 or x==origin.x+width+1 or z==origin.z or z==origin.z+6 or y==25:
					world.set_block(x,y,z,stone)
