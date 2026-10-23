extends RefCounted

## The cargo half of a dwarf's work execution (DwarfWorkExecution extends this
## script): the attempt identity (task id + generation) shared by every work
## family, the HAUL-lease executor (doc 18 §2.3), the FETCH_BUILD/CRAFT
## executor (doc 19 §3.3), and the shared pickup/carry/set-down presentation.
## The cargo itself lives on the body rig (rig.carried_entries); locomotion is
## DwarfMovement's. DwarfWorkExecution adds dispatch, the in-place executors,
## the per-frame tick and supervision samples.

const BodyRig = preload("res://scripts/components/DwarfBodyRig.gd")
const Movement = preload("res://scripts/components/DwarfMovement.gd")
const FellingPose = preload("res://scripts/components/DwarfFellingPose.gd")
const MiningPose = preload("res://scripts/components/DwarfMiningPose.gd")
const ConstructionPose = preload("res://scripts/components/DwarfConstructionPose.gd")
const CarryPose = preload("res://scripts/components/DwarfCarryPose.gd")

var task_id := -1
var generation := 0
var agent: DwarfAgent
var rig: BodyRig
var movement: Movement

## Task execution phase (DwarfAgent.TaskPhase). Every task needs a work source
## with its own executor; there is no generic walk-and-wait fallback.
var task_phase: int = 0
var task_target: Vector3i = Vector3i.ZERO
var exec_timer: float = 0.0

## HAUL-lease execution state (doc 18 §2.3 + pouch). Mirrors the zone-lease
## shape: 3 failed rounds release the lease with backoff; EVERYTHING carried
## is dropped at the feet on ANY interruption (Hard Rule 12). The pouch (SH
## backpack parity): a pull is a BUNDLE whose JSON carry_cost sum fits the
## carry_capacity budget, visited in order and deposited in one trip.
const HAUL_PULL_FAILURE_LIMIT := 3
## Pickup keeps the source reserved until fist contact. After that the normal
## carried-items save/drop contract applies, even while the lift is incomplete.
var _handling_item: Node3D
var _handling_start := Transform3D.IDENTITY
var _handling_world_start := Transform3D.IDENTITY
var _handling_target := Vector3.ZERO
var _handling_yaw_from := 0.0
var _handling_yaw_to := 0.0
var _handling_elapsed := 0.0
var _handling_duration := 0.75
var _handling_lifted := false
var _haul_source_id: int = -1
var _haul_items: Array[Node3D] = []  # this round's bundle, visit order
var _haul_index: int = 0             # next bundle item to fetch
var _handling_fruit_topup := false
var _haul_deposit: Vector3i = Vector3i(-1, -1, -1)
var _haul_failures: int = 0
var _haul_exclude: Dictionary = {}   # Node3D -> true; this-round item blacklist

## Furniture pipeline (doc 19 §3.3). FETCH_BUILD: reserve item via the ghost
## work source -> walk -> pick up -> walk to the ghost -> set down. Interrupts
## anywhere follow Hard Rule 12 (a carried item drops at the feet).
var _fetch_source_id: int = -1
var _fetch_item: Node3D = null       # reserved (pre-pickup) or carried (post)
var _fetch_plan: Dictionary = {}
var _fetch_picked_up: bool = false
var _plant_animation_duration := 0.0 # Remaining work at arrival; interrupted planting restarts the reach.
var _fetch_heavy: bool = false


func _init(p_agent: DwarfAgent = null, p_rig: BodyRig = null, p_movement: Movement = null) -> void:
	agent = p_agent
	rig = p_rig
	movement = p_movement


func bind(task: Task) -> void:
	task_id = task.id
	generation = task.attempt.generation

func complete(worker_id: int) -> void:
	TaskManager.complete_dwarf_task(worker_id,task_id,generation)

func release(worker_id: int, reason: int, available := true) -> void:
	TaskManager.release_dwarf_task(worker_id,reason,available,task_id,generation)

func fail(worker_id: int, reason: String) -> void:
	TaskManager.fail_dwarf_task(worker_id,reason,task_id,generation)

func commit(worker_id: int, unit: String, operation: Callable) -> bool:
	return TaskManager.commit_step(worker_id,task_id,generation,unit,operation)


## The item the dwarf is walking to pick up: the next haul bundle item, else the fetch item.
func target_item() -> Node3D:
	if task_phase in [DwarfAgent.TaskPhase.HAUL_TO_ITEM, DwarfAgent.TaskPhase.HAUL_PICKUP] and _haul_index < _haul_items.size(): return _haul_items[_haul_index]
	return _fetch_item

func get_haul_deposit() -> Vector3i: return _haul_deposit


# ── HAUL-lease executor (doc 18 §2.3 worker loop) ─────────────────────────────

func haul_source() -> RefCounted:
	if _haul_source_id < 0:
		return null
	return TaskManager.get_work_source(_haul_source_id) as RefCounted

## Step 1: pull a BUNDLE (main + nearby extras, each with a reserved deposit
## cell — the pouch). Nothing to pull -> the lease completes early.
func _haul_pull_next() -> void:
	if agent.current_task_id < 0:
		return   # cancelled out from under us mid-loop
	var source := haul_source()
	if source == null:
		_finish_haul_state()
		agent.current_task_id = -1
		fail(agent.dwarf_id, "stockpile zone gone")
		return
	var pull: Dictionary = source.call("reserve_haul", agent.dwarf_id, agent.current_cell(), _haul_exclude)
	if pull.is_empty():
		_finish_haul_state()
		agent.current_task_id = -1
		complete(agent.dwarf_id)
		return
	var task := TaskManager.get_task(agent.current_task_id)
	if source is StorageComponent and task != null:
		source.plan_fruit_haul(agent.dwarf_id,task.payload.get("haul_delivery_path",[]),_haul_exclude,
			task.payload.get("haul_pickup_path",[]))
	_haul_items = pull["items"]
	_haul_index = 0
	_haul_deposit = pull["deposit_target"]
	movement.carry_speed_mult = float(pull.get("carry_mult", 1.0))
	_haul_walk_current()

## Step 2: walk to the next bundle item; past the end of the bundle, head to
## the zone with whatever is in the pouch.
func _haul_walk_current() -> void:
	if agent.current_task_id < 0:
		return
	if _haul_index >= _haul_items.size():
		# Bundle exhausted. Carrying something -> deliver; nothing at all ->
		# the whole round failed (every item skipped).
		if rig.carried_entries.is_empty():
			_haul_cancel_pull()
			_haul_count_failure()
		else:
			var delivery_source := haul_source()
			if delivery_source == null or not _walk_to_handling_stand(delivery_source.call("delivery_stand_cells", _haul_deposit, agent.dwarf_id), DwarfAgent.TaskPhase.HAUL_TO_ZONE):
				drop_carried_at_feet()
				_haul_cancel_pull()
				_haul_count_failure()
			elif task_phase==DwarfAgent.TaskPhase.HAUL_TO_ZONE and delivery_source is StorageComponent:
				# Reconsider matching fruit on the actual delivery path after pickups.
				# This runs at handling boundaries, never as a per-frame item scan.
				if delivery_source.plan_fruit_haul(agent.dwarf_id,movement.move_path,_haul_exclude):
					movement.clear_path()
					_haul_walk_current()
		return
	var item := _haul_items[_haul_index]
	if item == null or not is_instance_valid(item):
		_haul_skip_current()
		return
	var source := haul_source()
	if source is StorageComponent:
		var planned: Array[Vector3i] = source.fruit_pickup_path(agent.dwarf_id,_haul_index)
		if not planned.is_empty() and planned.front()==agent.current_cell() and planned.back() in source.pickup_stand_cells(agent.dwarf_id,_haul_index):
			rig.reset_part_offsets()
			movement.move_path=planned
			movement.move_index=0
			movement.move_validation_index=-1
			movement.ladder_path_revision=NavGrid.ladder_revision
			movement.walk_cycle=0.0
			movement.shortcut_timer=0.0
			task_phase=DwarfAgent.TaskPhase.HAUL_TO_ITEM
			return
	if source == null or not _walk_to_handling_stand(source.call("pickup_stand_cells", agent.dwarf_id, _haul_index), DwarfAgent.TaskPhase.HAUL_TO_ITEM):
		_haul_skip_current()

## Step 3: reach first; the source hands over the cargo at fist contact.
func _haul_pickup_current() -> void:
	if _haul_index >= _haul_items.size() or not is_instance_valid(_haul_items[_haul_index]):
		_haul_skip_current()
		return
	_begin_item_pickup(_haul_items[_haul_index], DwarfAgent.TaskPhase.HAUL_PICKUP)
	var source := haul_source()
	_handling_fruit_topup = source is StorageComponent and source.is_fruit_topup(agent.dwarf_id)

func _haul_take_current() -> bool:
	var source := haul_source()
	if source == null:
		_finish_haul_state()
		agent.current_task_id = -1
		fail(agent.dwarf_id, "stockpile zone gone")
		return false
	var node: Node3D = source.call("take_item", agent.dwarf_id, _haul_index)
	if node == null:
		_clear_item_handling()
		_haul_skip_current()   # item vanished / raced — bundle continues
		return false
	var key := String(node.get_meta("item_key", ""))
	if not rig.carried_entries.any(func(entry: Array): return entry[0]==node):
		rig.carried_entries.append([node, key])
		agent.add_child(node)
		node.transform = _handling_start
	else:
		rig.carry_pose.clear_items() # Contents may have selected a fuller basket model.
	_handling_item = node # A partial produce-crate pickup can return a new node.
	return true

## An unreachable/vanished bundle item: blacklist it, free its reservations,
## move on. Skips never count as round failures by themselves — only an
## entirely empty-handed round does (_haul_walk_current end branch).
func _haul_skip_current() -> void:
	var source := haul_source()
	if _haul_index < _haul_items.size():
		var item := _haul_items[_haul_index]
		if item != null and is_instance_valid(item):
			_haul_exclude[item] = true
			if item.has_meta("relocation_id"):
				_haul_exclude[item.get_meta("relocation_id")] = true
		if source != null:
			source.call("skip_item", agent.dwarf_id, _haul_index)
	_haul_index += 1
	_haul_walk_current()

func _begin_haul_deposit() -> void:
	var source := haul_source()
	if source == null or rig.carried_entries.is_empty():
		_haul_deposit_now()
		return
	_begin_item_lower(source.call("delivery_contact", _haul_deposit), DwarfAgent.TaskPhase.HAUL_DEPOSIT)

## Step 4: multi-deposit — every pouch item lands on its own reserved cell.
func _haul_deposit_now() -> void:
	var source := haul_source()
	var committed := false
	if source != null and not rig.carried_entries.is_empty():
		committed = commit(agent.dwarf_id,"haul",func(): return source.commit_haul(agent.dwarf_id,rig.carried_entries))
	if committed:
		rig.carried_entries = []   # the zone/drop manager owns the nodes now
		rig.carry_pose.clear_items()
		rig.reset_part_offsets()
		movement.carry_speed_mult = 1.0
		# A completed load returns to worker selection. Pulling again here
		# bypasses nearby idle workers (including the dwarf who cut the tree)
		# and prevents higher-priority work from being considered between trips.
		_finish_haul_state()
		agent.current_task_id = -1
		complete(agent.dwarf_id)
	else:
		drop_carried_at_feet()
		_haul_cancel_pull()
		_haul_count_failure()

## Frees this round's remaining reservations (idempotent — the zone's
## task_released route may have freed them already).
func _haul_cancel_pull() -> void:
	var source := haul_source()
	if source != null:
		source.call("cancel_haul", agent.dwarf_id)
	_haul_items = []
	_haul_index = 0
	_haul_deposit = Vector3i(-1, -1, -1)
	movement.carry_speed_mult = 1.0

func _haul_count_failure() -> void:
	if agent.current_task_id < 0:
		return
	_haul_failures += 1
	if _haul_failures >= HAUL_PULL_FAILURE_LIMIT:
		_finish_haul_state()
		agent.current_task_id = -1
		release(agent.dwarf_id, Task.ReleaseReason.PATH_INVALID)
	else:
		_haul_pull_next()


## Hard Rule 12: everything carried goes back to the world as loose drops at
## the dwarf's feet — never destroyed, never stuck on the agent.
func drop_carried_at_feet() -> void:
	_clear_item_handling()
	if rig.carried_entries.is_empty():
		if rig.carry_pose != null:
			rig.carry_pose.clear_items()
		return
	var manager := ItemDropManager.find(agent.get_tree())
	for entry: Array in rig.carried_entries:
		var node: Node3D = entry[0]
		if node == null or not is_instance_valid(node):
			continue
		if manager != null:
			manager.drop_loose(node, agent.current_cell())
		else:
			node.queue_free()   # last resort — should never happen in a live scene
	rig.carried_entries = []
	movement.carry_speed_mult = 1.0
	rig.carry_pose.clear_items()
	rig.carry_pose.reset()


## Interrupt/abort teardown (mirrors _finish_zone_state): drop the pouch,
## free reservations, clear the loop state. Always cheap, always legal.
func _finish_haul_state() -> void:
	if _haul_source_id < 0 and rig.carried_entries.is_empty():
		return
	drop_carried_at_feet()
	_haul_cancel_pull()
	_haul_source_id = -1
	_haul_failures = 0
	_haul_exclude.clear()
	if task_phase in [DwarfAgent.TaskPhase.HAUL_TO_ITEM, DwarfAgent.TaskPhase.HAUL_TO_ZONE, DwarfAgent.TaskPhase.HAUL_PICKUP, DwarfAgent.TaskPhase.HAUL_DEPOSIT]:
		task_phase = DwarfAgent.TaskPhase.NONE


# ── Shared pickup / carry / set-down presentation ─────────────────────────

func _begin_item_pickup(item: Node3D, phase: int) -> void:
	rig.reset_part_offsets()
	_handling_item = item
	_handling_world_start = item.global_transform
	_handling_start = agent.global_transform.affine_inverse() * _handling_world_start
	_handling_yaw_from = agent.rotation.y
	var toward := item.global_position - agent.global_position
	_handling_yaw_to = atan2(toward.x, toward.z)
	_handling_elapsed = 0.0
	_handling_lifted = false
	_handling_duration = maxf(.05, float(TaskManager.get_config_section("hauling").get("pickup_time_s", .75)))
	task_phase = phase
	rig.carry_pose.pickup(0.0, item, _handling_start, rig.carried_entries, false)


## Choose a reachable side, never the cell under the goods. A blocked nearest
## side must not prevent a valid approach from another side. Test paths without
## emitting walk_finished(false) for every rejected candidate.
func _walk_to_handling_stand(candidates: Array[Vector3i], phase: int) -> bool:
	var here := agent.current_cell()
	candidates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector3(a - here).length_squared() < Vector3(b - here).length_squared())
	for stand in candidates:
		if not NavGrid.is_walkable(stand):
			continue
		if stand == here:
			task_phase = phase
			agent.finish_walk(true)
			return true
		if NavGrid.find_path(here, stand).is_empty():
			continue
		task_phase = DwarfAgent.TaskPhase.NONE
		if agent.walk_to(stand): # Uses the path just cached by the reachability check.
			task_phase = phase
			return true
	return false


func _begin_item_lower(contact: Vector3, phase: int) -> void:
	rig.reset_part_offsets()
	_handling_target = contact
	_handling_yaw_from = agent.rotation.y
	var toward := Vector2(contact.x - agent.global_position.x, contact.z - agent.global_position.z)
	_handling_yaw_to = atan2(toward.x, toward.y) if toward.length() > .25 else agent.rotation.y
	_handling_elapsed = 0.0
	_handling_duration = maxf(.05, float(TaskManager.get_config_section("hauling").get("deposit_time_s", .65)))
	task_phase = phase
	rig.carry_pose.lower(0.0, rig.carried_entries, agent.to_local(_handling_target))


func _begin_fetch_deposit() -> void:
	# Construction consumes the packed item only after the set-down. Until
	# then cancellation or a save still sees ordinary carried cargo.
	var source := fetch_source()
	var contact := agent.to_global(Vector3(0, 0, 1.25))
	if source != null and source.has_method("placement_contact"):
		contact = source.placement_contact(agent.global_position)
	_begin_item_lower(contact, DwarfAgent.TaskPhase.FETCH_DEPOSIT)


func _process_item_handling(delta: float) -> void:
	_handling_elapsed = minf(_handling_duration, _handling_elapsed + delta)
	var phase := _handling_elapsed / _handling_duration
	var action := task_phase
	if action in [DwarfAgent.TaskPhase.HAUL_PICKUP, DwarfAgent.TaskPhase.FETCH_PICKUP]:
		if not is_instance_valid(_handling_item):
			_clear_item_handling()
			if action == DwarfAgent.TaskPhase.HAUL_PICKUP:
				_haul_skip_current()
			else:
				_fetch_fail_release()
			return
		# Finish facing the item before contact, keeping its untouched world
		# transform fixed while the worker turns underneath the local pose.
		agent.rotation.y = lerp_angle(_handling_yaw_from, _handling_yaw_to, smoothstep(0.0, .28, phase))
		_handling_start = agent.global_transform.affine_inverse() * _handling_world_start
		if not _handling_lifted and phase >= CarryPose.CONTACT_PHASE:
			var item_floor := agent.item_floor_cell(_handling_item)
			if item_floor.y - agent.current_cell().y == 2 and (not NavGrid.is_walkable(agent.current_cell()) or not StorageComponent.ledge_reach_clear(item_floor, agent.current_cell())):
				_clear_item_handling()
				if action == DwarfAgent.TaskPhase.HAUL_PICKUP:
					_haul_skip_current()
				else:
					_fetch_fail_release()
				return
			var took := _haul_take_current() if action == DwarfAgent.TaskPhase.HAUL_PICKUP else _fetch_take_item()
			if not took:
				return
			_handling_lifted = true
		if _handling_fruit_topup:
			rig.carry_pose.gather_into(phase,_handling_start,rig.carried_entries)
		else:
			rig.carry_pose.pickup(phase, _handling_item, _handling_start, rig.carried_entries, _handling_lifted)
	else:
		agent.rotation.y = lerp_angle(_handling_yaw_from, _handling_yaw_to, smoothstep(0.0, .35, phase))
		rig.carry_pose.lower(phase, rig.carried_entries, agent.to_local(_handling_target))
	if phase < 1.0:
		return
	_clear_item_handling()
	task_phase = DwarfAgent.TaskPhase.NONE
	if action in [DwarfAgent.TaskPhase.HAUL_PICKUP, DwarfAgent.TaskPhase.FETCH_PICKUP]:
		rig.carry_pose.hold(rig.carried_entries)
	match action:
		DwarfAgent.TaskPhase.HAUL_PICKUP:
			_haul_index += 1
			_haul_walk_current()
		DwarfAgent.TaskPhase.FETCH_PICKUP:
			_fetch_travel_to_ghost()
		DwarfAgent.TaskPhase.HAUL_DEPOSIT:
			_haul_deposit_now()
		DwarfAgent.TaskPhase.FETCH_DEPOSIT:
			_fetch_complete()


func _clear_item_handling() -> void:
	_handling_fruit_topup = false
	_handling_item = null
	_handling_elapsed = 0.0
	_handling_lifted = false
	if rig.carry_pose != null:
		rig.carry_pose.reset()


# ── FETCH_BUILD / CRAFT executors (doc 19 §3.3) ───────────────────────────────

func fetch_source() -> RefCounted:
	if _fetch_source_id < 0:
		return null
	return TaskManager.get_work_source(_fetch_source_id) as RefCounted


## FETCH step 1: claim an item (loose first, else a storage withdraw).
## Nothing available -> the lease completes early and re-posts on the next
## item wake (the haul precedent).
func _fetch_begin() -> void:
	var source := fetch_source()
	if source == null:
		_finish_fetch_state()
		agent.current_task_id = -1
		fail(agent.dwarf_id, "furniture ghost gone")
		return
	if source.has_method("needs_trip_plan") and source.needs_trip_plan():
		_fetch_plan.clear()
		task_phase = DwarfAgent.TaskPhase.FETCH_PLANNING
		return
	var pull: Dictionary = source.call("reserve_fetch", agent.dwarf_id, agent.current_cell())
	if pull.is_empty():
		_finish_fetch_state()
		agent.current_task_id = -1
		release(agent.dwarf_id,Task.ReleaseReason.MATERIAL_UNAVAILABLE)
		return
	if bool(pull.get("work_only",false)):
		_fetch_travel_to_ghost()
		return
	_fetch_item = pull["item"]
	_fetch_picked_up = false
	_fetch_heavy = bool(pull.get("heavy", false))
	if _fetch_item == null or not is_instance_valid(_fetch_item):
		_fetch_fail_release()
		return
	var pickup_stands := StorageComponent.ground_access_cells(agent.item_floor_cell(_fetch_item))
	if pull.has("pickup_stand"): pickup_stands = [pull.pickup_stand]
	if not _walk_to_handling_stand(pickup_stands, DwarfAgent.TaskPhase.FETCH_TO_ITEM):
		_fetch_fail_release()


## FETCH step 2: the same reach/lift used for stockpile hauling, including
## furniture withdrawn from a ground stockpile or a storage container.
func _fetch_pickup() -> void:
	if not is_instance_valid(_fetch_item):
		_fetch_fail_release()
		return
	_begin_item_pickup(_fetch_item, DwarfAgent.TaskPhase.FETCH_PICKUP)


func _fetch_take_item() -> bool:
	var source := fetch_source()
	if source == null or _fetch_item == null or not is_instance_valid(_fetch_item):
		_fetch_fail_release()
		return false
	var manager := ItemDropManager.find(agent.get_tree())
	if manager == null:
		_fetch_fail_release()
		return false
	var key := ""
	if source.has_method("take_planting_item"):
		var cargo: Node3D = source.take_planting_item(_fetch_item, agent.dwarf_id)
		if cargo != null:
			_fetch_item = cargo
			key = String(cargo.get_meta("item_key", ""))
	else:
		key = manager.take(_fetch_item)
	if key.is_empty():
		_fetch_fail_release()   # vanished / raced
		return false
	_fetch_picked_up = true
	source.call("notify_picked_up", agent.dwarf_id)
	if _fetch_heavy:
		var hauling: Dictionary = TaskManager.get_config_section("hauling")
		movement.carry_speed_mult = float(hauling.get("carry_speed_mult_heavy", 0.7))
	rig.carried_entries.append([_fetch_item, key])
	agent.add_child(_fetch_item)
	_fetch_item.transform = _handling_start
	_handling_item = _fetch_item # A single cutting may be split from a larger crate.
	return true


func _fetch_travel_to_ghost() -> void:
	var source := fetch_source()
	if source == null:
		_fetch_fail_release()
		return
	var target: Vector3i = source.call("nearest_stand_target", agent.current_cell())
	if source.has_method("delivery_stand"): target = source.delivery_stand(agent.dwarf_id,agent.current_cell())
	if target.x < 0:
		_fetch_fail_release()   # footprint has no walkable neighbour right now
		return
	if target == agent.current_cell():
		_begin_fetch_work()
	elif agent.walk_to(target):
		task_phase = DwarfAgent.TaskPhase.FETCH_TO_GHOST
	else:
		_fetch_fail_release()


## FETCH step 4: the placement/work animation finished — the carried item BECOMES the
## installed piece (node freed, controller instances the solid form).
func _fetch_complete() -> void:
	if not TaskManager.matches_attempt(agent.dwarf_id,task_id,generation): return
	task_phase = DwarfAgent.TaskPhase.NONE
	var source := fetch_source()
	if source == null:
		_fetch_fail_release()
		return
	if source.has_method("commit_staged_build"):
		if not commit(agent.dwarf_id,"build:%s" % source.target,func(): return source.commit_staged_build(agent.dwarf_id)):
			_fetch_fail_release()
			return
		if source.continue_staged_build(agent.dwarf_id):
			task_phase = DwarfAgent.TaskPhase.FETCH_WORKING
			exec_timer = float(source.remaining_work())
			return
		source.cancel_fetch(agent.dwarf_id)
		rig.reset_part_offsets()
		_fetch_source_id = -1
		agent.current_task_id = -1
		complete(agent.dwarf_id)
		return
	if source.has_method("needs_ingredient_delivery") and bool(source.call("needs_ingredient_delivery")):
		var unit := "ingredient:%d" % _fetch_item.get_instance_id() if is_instance_valid(_fetch_item) else "missing ingredient"
		if not commit(agent.dwarf_id,unit,func(): return bool(source.stage_ingredient(agent.dwarf_id))):
			_fetch_fail_release()
			return
		rig.carried_entries = rig.carried_entries.filter(func(entry: Array) -> bool: return entry[0] != _fetch_item)
		_fetch_item = null
		_fetch_picked_up = false
		movement.carry_speed_mult = 1.0
		rig.carry_pose.clear_items()
		rig.reset_part_offsets()
		_fetch_begin()
		return
	# A wall can be mined during the work swing. Release the intact item if
	# the mount lost its support before the deferred terrain check cancelled it.
	if source.has_method("can_build_from") and not source.can_build_from(agent.current_cell()):
		_fetch_fail_release()
		return
	if source.has_method("can_complete_build") and not bool(source.call("can_complete_build")):
		_fetch_fail_release()
		return
	if not preload("res://scripts/components/ItemPermission.gd").allowed(_fetch_item):
		_fetch_fail_release()
		return
	if not commit(agent.dwarf_id,"fetch",_commit_fetch_result.bind(source)):
		_fetch_fail_release()
		return
	_fetch_source_id = -1
	_fetch_picked_up = false
	var finished_id := agent.current_task_id
	agent.current_task_id = -1
	if finished_id >= 0:
		complete(agent.dwarf_id)


func _commit_fetch_result(source: Object) -> bool:
	if not preload("res://scripts/components/WorkSourceAdapter.gd").valid_commit(source,"fetch"): return false
	if not is_instance_valid(_fetch_item): return false
	# Consume the carried item: it is the furniture now, not a drop.
	if _fetch_item != null and is_instance_valid(_fetch_item):
		rig.carried_entries = rig.carried_entries.filter(
			func(entry: Array) -> bool: return entry[0] != _fetch_item)
		if source.has_method("capture_item_properties"): source.capture_item_properties(_fetch_item)
		_fetch_item.queue_free()
	_fetch_item = null
	movement.carry_speed_mult = 1.0
	rig.carry_pose.clear_items()
	rig.reset_part_offsets()
	source.call("complete_build", agent.dwarf_id)
	return true


func _begin_fetch_work() -> void:
	var source := fetch_source()
	if source == null:
		_fetch_fail_release()
		return
	if source.has_method("needs_ingredient_delivery") and bool(source.call("needs_ingredient_delivery")):
		_begin_fetch_deposit()
		return
	if not source.has_method("remaining_work"):
		# Finished furniture only needs one set-down; no invisible build delay
		# before it. Bridge/ladder assembly, crafting and planting own their time.
		_begin_fetch_deposit()
		return
	task_phase = DwarfAgent.TaskPhase.FETCH_WORKING
	exec_timer = float(source.remaining_work())
	if source.has_method("commit_staged_build"):
		rig.reset_part_offsets()
		_construction_work_pose(source)
	if source.has_method("advance_plant"):
		_plant_animation_duration = exec_timer
		rig.reset_part_offsets()
		var toward: Vector3 = source.work_surface() - agent.global_position
		agent.rotation.y = atan2(toward.x, toward.z)
		_plant_pose(source, 0.0)


## The configured planting work IS the reach/lower/release animation, with
## no invisible timer before it and no second deposit afterwards. Cargo stays
## owned by the worker until the final valid-site commit, including saves.
func _plant_pose(source: RefCounted, phase: float) -> void:
	rig.carry_pose.lower(phase, rig.carried_entries, agent.to_local(source.work_surface()))

func _construction_work_pose(source: RefCounted) -> Vector3:
	var face: Vector3i = source.work_facing(agent.current_cell())
	agent.rotation.y = atan2(face.x,face.z)
	var contact := ConstructionPose.contact_point(source.target,agent.global_position,agent.global_basis.z)
	var inward := -ConstructionPose.contact_normal(source.target,contact)
	# Use the near side's horizontal clearance for the entire work session,
	# including low blocks struck on top. Higher targets must not move the feet.
	rig.construction_pose.prepare_stance(agent.to_local(MiningPose.contact_point(source.target,agent.global_position,agent.global_basis.z)))
	rig.construction_pose.apply(float(source.progress)/ConstructionPose.CYCLE_SECONDS,agent.to_local(contact),agent.global_basis.inverse()*inward)
	return contact


func _craft_pose(source: RefCounted) -> Vector3:
	var contact: Vector3 = source.call("work_surface")
	var toward := contact-agent.global_position
	agent.rotation.y = atan2(toward.x,toward.z)
	if is_instance_valid(_fetch_item):
		var bounds: AABB = rig.carry_pose.item_bounds(_fetch_item)
		_fetch_item.global_position = contact-Vector3.UP*bounds.position.y
		_fetch_item.rotation = Vector3.ZERO
		contact += Vector3.UP*bounds.size.y
	if rig.felling_pose != null:
		rig.felling_pose.apply(float(source.get("progress"))/FellingPose.CYCLE_SECONDS,agent.to_local(contact))
	return contact


## Any fetch failure: Rule 12 teardown + release with backoff.
func _fetch_fail_release(reason: int = Task.ReleaseReason.PATH_INVALID) -> void:
	_finish_fetch_state()
	rig.reset_part_offsets()
	if agent.current_task_id < 0:
		return
	agent.current_task_id = -1
	release(agent.dwarf_id, reason)


## Interrupt/abort teardown: a carried item drops at the feet (it re-enters
## the loose index); a merely-reserved item is unreserved via the source.
func _finish_fetch_state() -> void:
	_fetch_plan.clear()
	if _fetch_source_id < 0 and _fetch_item == null:
		return
	var source := fetch_source()
	if source != null:
		source.call("cancel_fetch", agent.dwarf_id)
	drop_carried_at_feet()   # covers the picked-up case; no-op otherwise
	_fetch_item = null
	_fetch_picked_up = false
	_fetch_source_id = -1
	_plant_animation_duration = 0.0
	movement.carry_speed_mult = 1.0
	if task_phase in [DwarfAgent.TaskPhase.FETCH_TO_ITEM, DwarfAgent.TaskPhase.FETCH_TO_GHOST, DwarfAgent.TaskPhase.FETCH_WORKING,DwarfAgent.TaskPhase.FETCH_PLANNING,
			DwarfAgent.TaskPhase.FETCH_PICKUP, DwarfAgent.TaskPhase.FETCH_DEPOSIT]:
		task_phase = DwarfAgent.TaskPhase.NONE
