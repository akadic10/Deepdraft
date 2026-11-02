extends RefCounted

## Nightly fires (doc 279). A campfire or hearth holds no wood of its own. At dusk
## each cold one posts a job to bring a log and light it; it burns until dawn, and
## then its log is gone. Light, heat and crackle follow the lit state; stools face
## a fire lit or cold. The burning log is saved on the installed piece; the jobs are not, and
## are posted again from the clock after a load. Owned by FurniturePlacementController.
## A fire in a sealed room is lit only while the room is below Comfortable without it
## (owner, 2026-10-29): a warm room keeps its log and does not overheat. Room changes
## re-check, so a second hearth stands down once the first has warmed the room.
## Bedtime fires (owner, 2026-10-30): a tired dwarf whose bed is in a cold room lights
## that room's fire before bed, by day too, through this same job. By day a fire then
## burns while someone sleeps in its room, going out at dawn or when the last one wakes.

const FireSource = preload("res://scripts/components/FireLightingComponent.gd")
const Lighting = preload("res://scripts/components/FurnitureLighting.gd")
const LOG_NODE := "FireLog"

var controller: Node
var work := preload("res://scripts/components/WorkSourceTable.gd").new() # installed id -> light job
var night := false
var dirty := true            # a load resyncs every fire against the clock
var leases_dirty := false    # a job ended without lighting: post it again
var restoring := false       # the owner is rebuilding saved pieces; their log comes from the save
var woke := false            # a dwarf woke: by day, fires nobody sleeps by go out
var _reloaded := false       # saved pieces came back: the next re-check reads the restored clock
var _fuel_keys: Dictionary = {} # fuel tag -> item keys
var _bedtime: Dictionary = {}   # installed id -> the tired dwarf lighting it before bed


func _init(owner: Node) -> void:
	controller = owner
	night = WorldClock.is_night()
	work.on_gone = func(_id: Variant, _task: Task) -> void: leases_dirty = true


static func burning(piece: InstalledFurnitureComponent) -> bool:
	return not piece.def.has("nightly_fire") or not piece.fire_log.is_empty()


## Every frame: follow dusk and dawn, and repost jobs after supply or task changes.
## Lit fires go out only at dawn or when a sleeper wakes, never on a room or load
## re-check, which may come before a loaded save's rooms are rebuilt. A load restores
## the clock after the furniture, so its first re-check is no dawn either.
func tick() -> void:
	var now := WorldClock.is_night()
	if now != night or dirty or woke:
		var put_out := not _reloaded and not now and (night or woke)
		night = now
		dirty = false
		woke = false
		_reloaded = false
		_sync(put_out)
	if leases_dirty:
		leases_dirty = false
		update_leases()


func update_leases() -> void:
	var drops: Variant = controller.get_drop_manager()
	for key: Variant in work.keys():
		var source: FireSource = work.get_source(key)
		if is_instance_valid(drops): source.drop_manager = drops
		source.update_lease()


## A new piece starts cold, and at night posts its job at once if its room needs it, so a
## save taken straight away already holds it. A restored piece waits for its saved log.
func installed(piece: InstalledFurnitureComponent) -> void:
	if not piece.def.has("nightly_fire"): return
	_show(piece, false)
	if restoring:
		dirty = true
		_reloaded = true
	elif WorldClock.is_night() and not piece.flagged_uninstall and needed(piece): _post(piece)


## Rooms were rebuilt or their temperatures moved: each cold fire checks its need again.
func rooms_changed() -> void:
	dirty = true


## Whether a fire should burn tonight: always outside a sealed room (the campfire's
## gathering light), and in a sealed room only while it is below Comfortable without
## this fire's own heat (what the room keeps of it past its doors). Fires are tended
## (owner, 2026-10-30): a cold one beside a fire already holding the room at the tended
## cap would add nothing, so it stays unlit.
func needed(piece: InstalledFurnitureComponent) -> bool:
	var cells: Array[Vector3i] = controller.room_cells(piece)
	if cells.is_empty(): return true
	var air := cells[0] + Vector3i.UP
	var room: Dictionary = RoomManager.get_room_at(air)
	if room.is_empty(): return true
	var units := int(piece.def.get("heat_source", {}).get("heat_units", 0))
	var without := float(room.temp_c)
	if not piece.fire_log.is_empty(): without -= RoomManager.heat_kept(air, units)
	elif RoomManager.heat_kept(air, units, false) < 0.05: return false
	return without < float(RoomManager.temperature_config.comfortable_min_c)


## The cold fire a dwarf going to sleep in `bed` lights first: one in the bed's sealed
## room that the room needs (owner, 2026-10-30). Null when there is none.
func bedroom_fire(bed: InstalledFurnitureComponent) -> InstalledFurnitureComponent:
	var room := RoomManager.get_room_id_at(bed.origin_cell + Vector3i.UP)
	if room < 0: return null
	for piece: InstalledFurnitureComponent in controller.get_installed_pieces():
		if piece.def.has("nightly_fire") and not piece.flagged_uninstall and piece.fire_log.is_empty() \
				and _room_of(piece) == room and needed(piece): return piece
	return null


## The fire's light job for the tired dwarf to take, posted now even by day. -1 when
## another worker already has it or there is no log: the dwarf then just goes to bed.
func bedtime_job(piece: InstalledFurnitureComponent, dwarf_id: int) -> int:
	var posted := not work.has(piece.installed_id)
	if posted: _post(piece)
	var source: FireSource = work.get_source(piece.installed_id)
	var task: Task = TaskManager.get_task(source.lease_id())
	if task != null and (task.status == Task.Status.PENDING or task.assigned_to == dwarf_id):
		_bedtime[piece.installed_id] = dwarf_id
		return task.id
	if posted and not night: work.retire(piece.installed_id, true)
	return -1


## The tired dwarf is done with the job, lit or not. By day nobody else takes it up.
func end_bedtime(piece: InstalledFurnitureComponent) -> void:
	_bedtime.erase(piece.installed_id)
	if not night and work.has(piece.installed_id): work.retire(piece.installed_id, true)


## A dwarf woke up: by day, a fire whose room has nobody left asleep goes out.
func dwarf_woke() -> void:
	woke = true


## Teardown: the burning log is lost with the fire.
func removed(piece: InstalledFurnitureComponent) -> void:
	if not piece.def.has("nightly_fire"): return
	_bedtime.erase(piece.installed_id)
	if work.has(piece.installed_id): work.retire(piece.installed_id, true)
	if not piece.fire_log.is_empty():
		piece.fire_log = ""
		RoomManager.set_fire_lit(controller.room_cells(piece), piece.def, false)


func restore(piece: InstalledFurnitureComponent, log_key: String, material_id: String) -> void:
	if piece.def.has("nightly_fire") and not log_key.is_empty(): light(piece, log_key, material_id)


func light(piece: InstalledFurnitureComponent, log_key: String, material_id: String) -> void:
	if work.has(piece.installed_id): work.retire(piece.installed_id, true)
	_bedtime.erase(piece.installed_id)
	if not piece.fire_log.is_empty(): return
	piece.fire_log = log_key
	piece.fire_log_material = material_id
	_show(piece, true)
	RoomManager.set_fire_lit(controller.room_cells(piece), piece.def, true)


func extinguish(piece: InstalledFurnitureComponent) -> void:
	if piece.fire_log.is_empty(): return
	piece.fire_log = ""
	piece.fire_log_material = ""
	_show(piece, false)
	RoomManager.set_fire_lit(controller.room_cells(piece), piece.def, false)


## The compact panel's line and the window's Fire row for one nightly fire.
func status(piece: InstalledFurnitureComponent) -> Dictionary:
	if not piece.fire_log.is_empty():
		var drops: Variant = controller.get_drop_manager()
		var log_name := String(drops.get_item_def(piece.fire_log).get("display_name", "")) if is_instance_valid(drops) else ""
		return {"text": "Burning until dawn" if night else "Burning while a dwarf sleeps here", "tone": "fine", "log": log_name}
	if not piece.flagged_uninstall and not needed(piece):
		var room: Dictionary = RoomManager.get_room_at(controller.room_cells(piece)[0] + Vector3i.UP)
		var warm := float(room.temp_c) >= float(RoomManager.temperature_config.comfortable_min_c)
		return {"text": "Unlit · the room is warm enough" if warm else "Unlit · another fire already heats the room", "tone": "fine"}
	var source: FireSource = work.get_source(piece.installed_id)
	var task: Task = TaskManager.get_task(source.lease_id()) if source != null else null
	if task != null and task.assigned_to >= 0:
		return {"text": "A worker is bringing a log", "tone": "fine"}
	if not night or piece.flagged_uninstall:
		return {"text": "Cold · lit at dusk or at bedtime" if _room_of(piece) >= 0 else "Cold · lit at dusk", "tone": "waiting"}
	if source != null and source.item_available():
		return {"text": "Waiting for a worker to light it", "tone": "waiting"}
	return {"text": "No log to light it", "tone": "blocked"}


## By day only a bedtime job stays posted. `put_out` (dawn, or a sleeper woke) puts out
## each lit fire with nobody asleep in its room.
func _sync(put_out: bool) -> void:
	for piece: InstalledFurnitureComponent in controller.get_installed_pieces():
		if not piece.def.has("nightly_fire"): continue
		if not night:
			if work.has(piece.installed_id) and not _bedtime.has(piece.installed_id): work.retire(piece.installed_id, true)
			if put_out and not piece.fire_log.is_empty() and not _slept_in(piece): extinguish(piece)
		elif piece.fire_log.is_empty() and not piece.flagged_uninstall:
			# A worker already on the way drops the log intact (Hard Rule 12).
			if not needed(piece):
				if work.has(piece.installed_id): work.retire(piece.installed_id, true)
			elif not work.has(piece.installed_id): _post(piece)


func _post(piece: InstalledFurnitureComponent) -> void:
	var fire: Dictionary = piece.def.nightly_fire
	var source := FireSource.new()
	source.setup(piece.installed_id, piece.furniture_key, piece.def, piece.origin_cell, piece.yaw_steps)
	source.ghost_id = -1 # identity is the installed fire's, not a placement's
	source.installed_id = piece.installed_id
	source.front_stands = String(fire.get("light_from", "")) == "front"
	source.fuel_keys = _keys_for(String(fire.get("fuel_tag", "timber")))
	if not source.fuel_keys.is_empty(): source.item_key = source.fuel_keys[0] # not the packed fire's own item
	source.log_contact = _log_transform(piece).origin
	var drops: Variant = controller.get_drop_manager()
	if is_instance_valid(drops): source.drop_manager = drops
	source.light_callback = func(lit: FireSource) -> void:
		var fire_piece: InstalledFurnitureComponent = controller.get_installed(lit.installed_id)
		# The worker's own completion resolves the lease, so the job is retired as it stands.
		work.retire(lit.installed_id, false)
		if fire_piece != null: light(fire_piece, lit.delivered_key, lit.material_id)
	source.can_light_callback = func(lit: FireSource) -> bool:
		var fire_piece: InstalledFurnitureComponent = controller.get_installed(lit.installed_id)
		return (night or _bedtime.has(lit.installed_id)) and fire_piece != null and fire_piece.fire_log.is_empty() \
			and not fire_piece.flagged_uninstall and needed(fire_piece)
	work.add(piece.installed_id, source)
	source.update_lease()


## The sealed room a fire stands in, or -1.
func _room_of(piece: InstalledFurnitureComponent) -> int:
	var cells: Array[Vector3i] = controller.room_cells(piece)
	return RoomManager.get_room_id_at(cells[0] + Vector3i.UP) if not cells.is_empty() else -1


## Someone asleep, or tired enough to sleep, in the fire's room keeps it burning by day.
func _slept_in(piece: InstalledFurnitureComponent) -> bool:
	var room := _room_of(piece)
	if room < 0: return false
	for agent: DwarfAgent in TaskManager.get_agents():
		if (agent.is_sleeping() or agent.sleep <= DwarfAgent.SLEEP_THRESHOLD) \
				and RoomManager.get_room_id_at(agent.current_cell() + Vector3i.UP) == room: return true
	return false


## Light, flame and the burning log together; the log is the delivered good's own model.
func _show(piece: InstalledFurnitureComponent, lit: bool) -> void:
	if not is_instance_valid(piece.node): return
	Lighting.set_lit(piece.node, piece.def, lit)
	var old := piece.node.get_node_or_null(LOG_NODE)
	if old != null:
		piece.node.remove_child(old)
		old.queue_free()
	var drops: Variant = controller.get_drop_manager()
	if not lit or not is_instance_valid(drops): return
	var log_node: Node3D = drops.create_item_visual(piece.fire_log, 1, "", piece.fire_log_material)
	if log_node == null: return
	log_node.name = LOG_NODE
	piece.node.add_child(log_node)
	log_node.global_transform = _log_transform(piece)


func _log_transform(piece: InstalledFurnitureComponent) -> Transform3D:
	var fire: Dictionary = piece.def.nightly_fire
	var at: Array = fire.get("log_position", [0, 0, 0])
	var local := Transform3D(Basis(Vector3.UP, deg_to_rad(float(fire.get("log_yaw_degrees", 0.0)))).scaled(Vector3.ONE * float(fire.get("log_scale", 1.0))),
		Vector3(float(at[0]), float(at[1]), float(at[2])))
	if is_instance_valid(piece.node): return piece.node.global_transform * local
	var root := Transform3D(Basis(Vector3.UP, float(piece.yaw_steps) * PI * 0.5),
		preload("res://scripts/components/FurniturePlacementRules.gd").world_pos(piece.def, piece.origin_cell, piece.yaw_steps))
	return root * local


func _keys_for(tag: String) -> Array[String]:
	if not _fuel_keys.has(tag):
		var keys: Array[String] = []
		for key: String in ContentRegistry.items:
			if tag in ContentRegistry.items[key].get("material_tags", []): keys.append(key)
		keys.sort()
		_fuel_keys[tag] = keys
	return _fuel_keys[tag]
