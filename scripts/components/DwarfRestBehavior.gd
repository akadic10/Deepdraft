extends RefCounted

## Rest owns only transient destinations, bed claims and visual poses. The actor
## keeps the sleep need, task cleanup and a real, supported navigation position.
const DIRECTIONS := [Vector3i.BACK, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.LEFT]
const Privacy = preload("DwarfPrivacy.gd")
var _privacy := Privacy.new()
var agent: DwarfAgent
var config: Dictionary
var state := ""
var pose := "sitting"
var goal := Vector3i(-1,-1,-1)
var cells: Array[Vector3i] = []
var elapsed := 0.0
var blend := 0.0
var _facing := Vector3i.BACK
var _shelter := Vector3i(-1,-1,-1)
var _candidates: Array[Vector3i] = []
var _cursor := 0
var _search_pass := 0
var _tree_handles: Dictionary = {}
var _flora: Node
var _check_timer := 0.0
var _snore_timer := 0.0
var _eyelids: Node3D
var bed_rest: RefCounted

func _init(dwarf: DwarfAgent) -> void:
	agent = dwarf
	config = TaskManager.get_config_section("rest")
	bed_rest = preload("DwarfBedRest.gd").new(agent)
	_build_eyelids()

func cancel() -> void:
	if bed_rest != null: bed_rest.release()
	state = ""
	_privacy.reset()
	goal = Vector3i(-1,-1,-1)
	cells = []
	blend = 0.0
	_eyes(false)
	agent.stop_walking()
	agent._reset_part_offsets()

func begin(restored := false) -> void:
	cancel()
	elapsed = float(agent.dwarf_id % 7) * .43
	_snore_timer = 2.0 + float(posmod(agent.dwarf_id,5)) * .7
	_flora = agent.get_tree().get_first_node_in_group("surface_flora")
	_tree_handles.clear()
	var here := agent.current_cell()
	if not Privacy.allowed(here,agent.dwarf_id,true):
		state = "leaving_room"
		return
	var radius := int(config.get("search_radius",8))
	bed_rest.begin(float(config.get("bed_search_radius",48)))
	_search_pass = 0
	if is_instance_valid(_flora):
		for id: Vector2i in _flora._trees:
			var tree: Dictionary = _flora._trees[id]
			if Vector3(tree.cell-here).length() <= radius+8 and int(tree.occupancy_id) >= 0:
				_tree_handles[int(tree.occupancy_id)] = id
	var restored_spot := restored and _choose(here,true)
	if restored and not restored_spot:
		_search_pass = 1
		restored_spot = _choose(here,true)
	if restored and not restored_spot:
		_search_pass = 2
		restored_spot = _choose(here,false)
	_search_pass = 0
	if restored and bed_rest.restore_here():
		_settle_bed()
		blend = 1.0
		state = "sleeping"
		_apply_pose()
		return
	if restored_spot:
		_settle()
		blend = 1.0
		state = "sleeping"
		_apply_pose()
		return
	_candidates = []
	for x in range(-radius,radius+1):
		for z in range(-radius,radius+1):
			if x*x+z*z <= radius*radius: _candidates.append(here+Vector3i(x,0,z))
	_candidates.sort_custom(func(a: Vector3i,b: Vector3i): return a.distance_squared_to(here) < b.distance_squared_to(here))
	_cursor = 0
	state = "finding_bed" if not bed_rest._options.is_empty() else "searching"

## Bounded local search: a few candidates per frame, no whole-map A* burst.
## Bed routes use normal navigation; ground rest stays on nearby flat ground.
func tick(delta: float) -> bool:
	elapsed += delta
	if state.is_empty(): begin()
	if state=="leaving_room":
		if not _privacy.leave(agent,delta,true): begin()
		return false
	if not Privacy.allowed(agent.current_cell(),agent.dwarf_id,true):
		begin()
		return false
	# Furniture may be removed between frames, including during the wake pose.
	if bed_rest.bed != null and not is_instance_valid(bed_rest.bed.node):
		begin()
		return false
	if state=="finding_bed":
		var result: int = bed_rest.seek()
		if result==1:
			goal = bed_rest.goal
			state = "travelling_bed"
		elif result<0: state = "searching"
		return false
	if state=="travelling_bed":
		if not bed_rest.valid():
			begin()
			return false
		if agent.is_walking(): agent._follow_path(delta)
		if not agent.is_walking():
			if agent.current_cell()==goal: _settle_bed()
			else: begin()
		return false
	if state == "searching":
		for i in range(int(config.get("candidates_per_tick",12))):
			if _cursor >= _candidates.size():
				_search_pass += 1
				_cursor = 0
				if _search_pass >= 3: _fallback()
				break
			var candidate := _candidates[_cursor]
			_cursor += 1
			if not _choose(candidate,_search_pass<2): continue
			if not Privacy.segment(agent.current_cell(),candidate,agent.dwarf_id,true) or not NavGrid.line_walkable_flat_from(agent.global_position,candidate):
				goal = Vector3i(-1,-1,-1)
				cells = []
				continue
			state = "travelling"
			agent.walk_nearby(goal)
			break
		return false
	if state == "travelling":
		if not _valid() or not Privacy.segment(agent.current_cell(),goal,agent.dwarf_id,true) or not NavGrid.line_walkable_flat_from(agent.global_position,goal):
			begin()
			return false
		if agent.is_walking(): agent._follow_path(delta)
		if not agent.is_walking():
			if agent.current_cell() == goal: _settle()
			else: begin()
		return false
	_check_timer -= delta
	if _check_timer <= 0.0 and state != "waking":
		_check_timer = .5
		if agent.current_cell() != goal or (bed_rest.bed != null and not bed_rest.valid()) or (bed_rest.bed == null and not cells.is_empty() and not _valid()):
			begin()
			return false
	var duration := maxf(.1,float(config.get("transition_seconds",1.1)))
	if state == "waking":
		blend = maxf(0.0,blend-delta/duration)
		_apply_pose()
		if blend <= 0.0: agent._wake_up()
		return false
	blend = minf(1.0,blend+delta/duration)
	if blend >= 1.0: state = "sleeping"
	_apply_pose()
	if state == "sleeping":
		_snore_timer -= delta
		if _snore_timer <= 0.0:
			WorkFeedback.play_snore(agent)
			_snore_timer = float(config.get("snore_interval_seconds",7.0)) + float(posmod(agent.dwarf_id,4))*.65
		return true
	return false

func begin_waking() -> void:
	state = "waking"
	_eyes(false)

func _settle() -> void:
	agent.stop_walking()
	agent._reset_part_offsets()
	agent.rotation.y = atan2(_facing.x,_facing.z)
	state = "settling"
	blend = 0.0
	_check_timer = .5

func _settle_bed() -> void:
	goal = bed_rest.goal
	cells = []
	pose = "lying"
	_shelter = Vector3i(-1,-1,-1)
	_settle()
	agent.rotation.y = bed_rest.yaw()

func _choose(cell: Vector3i, sheltered: bool) -> bool:
	if not _clear(cell): return false
	var preferred := "lying" if posmod(agent.dwarf_id,2)==0 else "sitting"
	var alternate := "sitting" if preferred=="lying" else "lying"
	var styles: Array = [preferred,alternate] if _search_pass==2 else [preferred if _search_pass==0 else alternate]
	for style: String in styles:
		for forward: Vector3i in DIRECTIONS:
			var cover := cell-forward*(2 if style=="lying" else 1)
			if sheltered and not _cover(cover): continue
			var footprint := _footprint(cell,forward,style)
			var clear := true
			for tile in footprint:
				if not _clear(tile): clear = false; break
			if not clear or not _unclaimed(footprint): continue
			goal = cell
			pose = style
			_facing = forward
			_shelter = cover if sheltered else Vector3i(-1,-1,-1)
			cells = footprint
			return true
	return false

func _footprint(cell: Vector3i, forward: Vector3i, style: String) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var side := Vector3i(forward.z,0,-forward.x)
	for x in range(-1,2):
		for z in range(-1 if style=="lying" else 0,3 if style=="lying" else 2):
			result.append(cell+side*x+forward*z)
	return result

func _clear(cell: Vector3i) -> bool:
	if not Privacy.allowed(cell,agent.dwarf_id,true) or RoomManager._door_cells.has(cell): return false
	if not NavGrid.is_walkable(cell) or NavGrid.bridge_supports(cell): return false
	for offset: Vector3i in [Vector3i.ZERO,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		if not NavGrid.ladder_at(cell+offset).is_empty(): return false
	for zone in StockpileManager._zones.values():
		if cell in zone.tile_cells: return false
	var furniture := agent.get_tree().get_first_node_in_group("furniture_controller")
	return furniture == null or (not furniture._cell_to_ghost.has(cell) and not furniture._cell_to_installed.has(cell))

func _cover(cell: Vector3i) -> bool:
	if BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y+1,cell.z)) and BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y+2,cell.z)): return true
	if not is_instance_valid(_flora): return false
	for range_entry: Vector3i in PlacedEntityRegistry._columns.get(Vector2i(cell.x,cell.z),[]):
		if not _tree_handles.has(range_entry.z) or cell.y+1 < range_entry.x or cell.y+2 > range_entry.y: continue
		var id: Vector2i = _tree_handles[range_entry.z]
		if not bool(_flora._tree_changes.get(id,{}).get("designated",false)): return true
	return false

func _unclaimed(footprint: Array[Vector3i]) -> bool:
	for other: DwarfAgent in TaskManager._agents.values():
		if other == agent or not is_instance_valid(other): continue
		if other.current_cell() in footprint: return false
		if other._rest_behavior == null or not other.is_sleeping(): continue
		for tile in footprint:
			if tile in other._rest_behavior.cells: return false
	return true

func _valid() -> bool:
	if _shelter.x >= 0 and not _cover(_shelter): return false
	for cell in cells:
		if not _clear(cell): return false
	return true

func _fallback() -> void:
	# Both sheltered poses and clear open ground were checked incrementally.
	# A cramped-space seated fallback never teleports or searches indefinitely.
	goal = agent.current_cell()
	cells = []
	_shelter = Vector3i(-1,-1,-1)
	pose = "sitting"
	_facing = DIRECTIONS[posmod(roundi(agent.rotation.y/(PI*.5)),4)]
	_settle()

func _part(node: Node3D, center: Vector3, target: Vector3, rotation: Vector3, mirror := false) -> void:
	if not is_instance_valid(node): return
	if bed_rest.bed != null: target += bed_rest.offset()
	var weight := smoothstep(0.0,1.0,blend)
	var turn := Quaternion.IDENTITY.slerp(Quaternion.from_euler(rotation),weight)
	var basis := Basis(turn)
	# Transform about each authored part's centre, preserving the right-hand/boot reflection.
	var anchor := center
	if mirror: anchor.x = -anchor.x
	var reflection := Basis.from_scale(Vector3(-1,1,1) if mirror else Vector3.ONE)
	if node==agent._body: reflection=Basis.from_scale(Vector3(agent.proportions.body_width,1,1))
	if node==agent._head: reflection=Basis.from_scale(Vector3(agent.proportions.head_width,1,1))
	node.transform = Transform3D(basis*reflection,anchor.lerp(target,weight)-basis*anchor)

## A lying head rests on its lowest cell, so a back bun or a deep knot lifts it
## slightly instead of sinking into the bed or floor (doc 256). Each dwarf's
## head never changes shape, so the height is measured once.
var _lying_head_rest := -1.0

func _lying_head_height() -> float:
	if _lying_head_rest >= 0.0: return _lying_head_rest
	_lying_head_rest = .96
	if not is_instance_valid(agent._head): return _lying_head_rest
	var turn := Basis(Quaternion.from_euler(Vector3(-PI*.5+.05,0,0)))
	var width := Basis.from_scale(Vector3(agent.proportions.head_width,1,1))
	var lowest := INF
	for mesh: MeshInstance3D in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(agent._head):
		if mesh.mesh == null: continue
		var frame := Transform3D.IDENTITY
		var node: Node = mesh
		while node != agent._head and node is Node3D:
			frame = (node as Node3D).transform * frame
			node = node.get_parent()
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			lowest = minf(lowest,(turn*(width*(frame*vertex)-Vector3(0,2.45,0))).y)
	# Breathing lowers the head by up to .0104 below its rest height.
	if lowest < INF: _lying_head_rest = maxf(.96,.012-lowest)
	return _lying_head_rest

func _apply_pose() -> void:
	var breath := sin(elapsed*TAU/4.6)*.026
	var nod := sin(elapsed*TAU/9.2)*.025
	var compact := cells.is_empty()
	if pose == "lying":
		_part(agent._body,Vector3(0,1.15,0),Vector3(0,.49+breath,.65),Vector3(-PI*.5,0,0))
		_part(agent._head,Vector3(0,2.45,0),Vector3(0,_lying_head_height()+breath*.4,-.55),Vector3(-PI*.5+.05,nod,0))
		_part(agent._hand_l,Vector3(1.0625,1.25,.1875),Vector3(.49,.89+breath,.55),Vector3(-.8,0,-.15))
		_part(agent._hand_r,Vector3(1.0625,1.25,.1875),Vector3(-.49,.89+breath,.55),Vector3(-.8,0,.15),true)
		_part(agent._foot_l,Vector3(.5,.2,.15),Vector3(.46,.385,1.57),Vector3(-.35,0,-.12))
		_part(agent._foot_r,Vector3(.5,.2,.15),Vector3(-.46,.385,1.67),Vector3(-.35,0,.12),true)
	else:
		var forward := .10 if compact else .42
		_part(agent._body,Vector3(0,1.15,0),Vector3(0,.63+breath,forward),Vector3(-.13,0,0))
		_part(agent._head,Vector3(0,2.45,0),Vector3(0,1.83+breath,forward+.10),Vector3(.18+nod,0,.06))
		_part(agent._hand_l,Vector3(1.0625,1.25,.1875),Vector3(.56,.55,forward+.42),Vector3(.12,0,-.18))
		_part(agent._hand_r,Vector3(1.0625,1.25,.1875),Vector3(-.56,.53,forward+.40),Vector3(.12,0,.18),true)
		_part(agent._foot_l,Vector3(.5,.2,.15),Vector3(.50,.22,.55 if compact else 1.12),Vector3(0,-.14,0))
		_part(agent._foot_r,Vector3(.5,.2,.15),Vector3(-.50,.22,.55 if compact else 1.04),Vector3(0,.14,0),true)
	_eyes(blend > .85 and state != "waking")

func _build_eyelids() -> void:
	if not is_instance_valid(agent._head) or agent.appearance == null: return
	_eyelids = DwarfAssets.rest_eyelids.instantiate() as Node3D
	_eyelids.name = "RestEyelids"
	agent._head.add_child(_eyelids)
	var skin: Color = DwarfAssets.SKIN_TONES.get(agent.appearance.skin_tone,Color.WHITE)
	preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(_eyelids,false)
	for lid in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(_eyelids):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo=true
		material.albedo_color=skin
		material.roughness=1.0
		lid.material_override=material
		lid.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes(false)

func _eyes(closed: bool) -> void:
	if is_instance_valid(_eyelids): _eyelids.visible = closed
	if is_instance_valid(agent._head):
		var eyes := agent._head.get_node_or_null("MeshEyes")
		if eyes != null: eyes.visible = not closed

func describe() -> Dictionary:
	var activity := "Sleeping on the ground" if pose=="lying" else "Sleeping seated"
	if bed_rest.bed != null: activity = "Sleeping in a bed"
	if state=="finding_bed": activity = "Finding a bed"
	if state=="leaving_room": activity = "Leaving bedroom to rest"
	if state=="travelling_bed": activity = "Going to bed"
	if state=="searching": activity = "Finding a place to sleep"
	if state=="travelling": activity = "Going to rest"
	if state=="settling": activity = "Settling down"
	if state=="waking": activity = "Waking up"
	var explanation := "Resting beside shelter" if _shelter.x >= 0 else "Resting on the ground"
	if bed_rest.bed != null: explanation = "Resting in %s" % bed_rest.bed.display_name().to_lower()
	return {"activity":activity,"destination":goal,"explanation":explanation}
