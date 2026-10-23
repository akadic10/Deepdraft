extends RefCounted

## Installed furniture owns the bed; this helper owns one sleeper's temporary
## claim and a safe access floor. The actor never teleports into bed occupancy.
var agent: DwarfAgent
var bed: InstalledFurnitureComponent
var goal := Vector3i(-1,-1,-1)
var _controller: Node
var _options: Array[Dictionary] = []
var _index := 0

func _init(dwarf: DwarfAgent) -> void: agent = dwarf

func release() -> void:
	if bed != null and bed.sleep_owner == agent.dwarf_id: bed.sleep_owner = -1
	bed = null
	goal = Vector3i(-1,-1,-1)
	_options.clear()
	_index = 0

func begin(radius: float) -> void:
	release()
	_controller = agent.get_tree().get_first_node_in_group("furniture_controller")
	if not is_instance_valid(_controller): return
	var nearby: Array = []
	for piece: InstalledFurnitureComponent in _controller.get_installed_pieces():
		if not _available(piece): continue
		var owned := piece.assigned_dwarf_id==agent.dwarf_id
		if not owned and piece.node.global_position.distance_to(agent.global_position)>radius: continue
		var room := RoomManager.get_room_at(piece.origin_cell+Vector3i.UP)
		var score := piece.node.global_position.distance_squared_to(agent.global_position)
		# Prefer an actual bedroom, but a free camp bed still beats the ground.
		if room.get("room_type","") not in ["bedroom","personal_bedroom","barracks"]: score += radius*radius
		if owned: score = -1.0 # Always try the assigned bed before spare local beds.
		nearby.append({"bed":piece,"score":score})
	nearby.sort_custom(func(a,b): return float(a.score)<float(b.score))
	for entry: Dictionary in nearby:
		var candidates := access_cells(entry.bed)
		candidates.sort_custom(func(a: Vector3i,b: Vector3i): return a.distance_squared_to(agent.current_cell())<b.distance_squared_to(agent.current_cell()))
		for cell in candidates: _options.append({"bed":entry.bed,"cell":cell})

func _available(piece: InstalledFurnitureComponent) -> bool:
	return piece != null and is_instance_valid(piece.node) and not piece.flagged_uninstall and piece.def.has("sleep_surface") and piece.sleep_owner in [-1,agent.dwarf_id] and piece.assigned_dwarf_id in [-1,agent.dwarf_id]

func in_personal_bedroom() -> bool:
	# The rest controller already validates access/support on its bounded cadence.
	if bed==null or not is_instance_valid(bed.node) or bed.flagged_uninstall or bed.sleep_owner!=agent.dwarf_id or bed.assigned_dwarf_id!=agent.dwarf_id: return false
	var room := RoomManager.get_room_at(bed.origin_cell+Vector3i.UP)
	return room.get("room_type","")=="personal_bedroom" and int(room.get("owner_id",-1))==agent.dwarf_id

static func access_cells(piece: InstalledFurnitureComponent) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var w := int(piece.def.footprint.width)
	var d := int(piece.def.footprint.depth)
	# Beside the mattress, never at the obstructing headboard.
	for x in range(1,w-1):
		for z in [-1,d]:
			var box := preload("FurnitureSeating.gd").rotate_box(piece.def,Vector3(x,0,z),Vector3(x+1,0,z+1),piece.yaw_steps)
			result.append(piece.origin_cell+Vector3i(box.position))
	return result

func _access_clear(piece: InstalledFurnitureComponent, cell: Vector3i) -> bool:
	if not preload("DwarfPrivacy.gd").allowed(cell,agent.dwarf_id,true): return false
	if not NavGrid.is_walkable(cell) or NavGrid.bridge_supports(cell) or not NavGrid.ladder_at(cell).is_empty(): return false
	for tile: Vector3i in piece.cells:
		if not BlockRegistry.is_solid(WorldData.get_live_block(tile.x,tile.y,tile.z)): return false
		for y in range(1,4):
			var air := tile+Vector3i.UP*y
			if BlockRegistry.is_solid(WorldData.get_live_block(air.x,air.y,air.z)) or PlacedEntityRegistry.occupies(air,piece.occupancy_ids): return false
	for other: DwarfAgent in TaskManager.get_agents():
		if other!=agent and is_instance_valid(other) and other.is_sleeping() and other.current_cell()==cell: return false
	return true

func restore_here() -> bool:
	for option in _options:
		if option.cell == agent.current_cell() and _claim(option): return true
	return false

func _claim(option: Dictionary) -> bool:
	var piece: InstalledFurnitureComponent = option.bed
	if not _available(piece) or not _access_clear(piece,option.cell): return false
	bed = piece
	goal = option.cell
	bed.sleep_owner = agent.dwarf_id
	return true

## 0 = more candidates, 1 = physically walking to a claimed bed, -1 = no bed.
func seek() -> int:
	if _index >= _options.size(): return -1
	var option := _options[_index]
	_index += 1
	if not _claim(option): return 0
	if agent.walk_to(goal): return 1
	bed.sleep_owner = -1
	bed = null
	return 0

func valid() -> bool:
	return _available(bed) and is_instance_valid(_controller) and _controller.get_installed(bed.installed_id)==bed and bed.sleep_owner==agent.dwarf_id and _access_clear(bed,goal)

func yaw() -> float:
	return float(bed.yaw_steps+int(bed.def.sleep_surface.facing_steps))*PI*.5

func offset() -> Vector3:
	var settings: Dictionary = bed.def.sleep_surface
	return agent.to_local(bed.node.global_position)+Vector3(0,float(settings.height),float(settings.get("forward_offset",0)))
