class_name DwarfAgent
extends CharacterBody3D

## One dwarf colonist (doc 41 / 41b): identity, needs, task dispatch and
## interruption. The work lives in components:
##   - DwarfBodyRig: part assembly, tinting, work/carry rigs, idle bob, cargo.
##   - DwarfMovement: path following, ladder climbing, walk cycle, floor support.
##   - DwarfWorkExecution (+ its base DwarfCarryWork): the job executors.
##   - DwarfFoodBehavior, DwarfRestBehavior, DwarfIdleBehavior, DwarfEquipment…
##
## VISUAL CONTRACT (doc 41, hard rules — see DwarfBodyRig): four detached parts,
## never merged; visual height ~3.3 blocks; LOGICAL height 3 blocks (1x1x3
## footprint) — collision and nav use the logical box, never the visual AABB.

const LOGICAL_HEIGHT := 3.0    # blocks — collision + future nav clearance
const IdleBehavior = preload("res://scripts/components/DwarfIdleBehavior.gd")
const RestBehavior = preload("res://scripts/components/DwarfRestBehavior.gd")
const Equipment = preload("res://scripts/components/DwarfEquipment.gd")
const BodyRig = preload("res://scripts/components/DwarfBodyRig.gd")
const Movement = preload("res://scripts/components/DwarfMovement.gd")
const WorkExecution = preload("res://scripts/components/DwarfWorkExecution.gd")
const COLLISION_LAYER_DWARF := 4   # layer bit 3. NOT layer 1 (camera spring arm
								   # collides mask 1, terrain only) and NOT
								   # layer 2 (trees) — see doc 42 Collision Rule.

# ── Identity (set once by setup) ──────────────────────────────────────────────
var dwarf_id: int = -1
var dwarf_name: String = ""
var gender: String = "male"
var appearance: DwarfAppearanceData = null
var proportions: Dictionary = {}
var traits: Array[String] = []
var profession: String = "base:profession:worker"
var profession_experience: Dictionary = {}
var work_permissions: Dictionary = {}

## The claimed task id (id, NOT the Task object — doc 16 §2.2). -1 = idle.
var current_task_id: int = -1
## Body, movement and job execution (built in _init so they exist before setup).
var _rig: BodyRig
var _movement: Movement
var _work_execution: WorkExecution

## Task execution phases. Every task needs a work source with its own executor;
## there is no generic walk-and-wait fallback.
## ZONE_MOVING/ZONE_SWINGING is the MINE-lease executor (doc 16 §2.7): pull a
## block from the zone's destination set, reserve it, path to a stand cell,
## swing it down, commit, pull the next.
## HAUL_TO_ITEM/HAUL_TO_ZONE is the HAUL-lease executor (doc 18 §2.3): pull
## the nearest accepted loose item, reserve it + a deposit cell, walk over,
## pick it up, carry it to the stockpile, deposit, pull the next.
enum TaskPhase { NONE, ZONE_MOVING, ZONE_SWINGING, HAUL_TO_ITEM, HAUL_TO_ZONE,
		FETCH_TO_ITEM, FETCH_TO_GHOST, FETCH_WORKING, UNINSTALL_MOVING, UNINSTALL_WORKING,
		FELL_FINDING, FELL_MOVING, FELL_WORKING,
		HAUL_PICKUP, HAUL_DEPOSIT, FETCH_PICKUP, FETCH_DEPOSIT, FETCH_PLANNING }
## Executor state forwarded for the other components and tests.
var _task_phase: int:
	get: return _work_execution.task_phase
	set(value): _work_execution.task_phase = value
@warning_ignore("unused_private_class_variable") # read by components and tests
var _exec_timer: float:
	get: return _work_execution.exec_timer
	set(value): _work_execution.exec_timer = value
## The cargo in the hands, [[node: Node3D, item_key: String], ...] (DwarfBodyRig).
var _carried_entries: Array:
	get: return _rig.carried_entries
	set(value): _rig.carried_entries = value
## Work and carry rigs, built by DwarfBodyRig in setup().
var _carry_pose: RefCounted
var _felling_pose: RefCounted
var _mining_pose: RefCounted
var _construction_pose: RefCounted

## Sleep-lite (doc 16 §2.8 / Phase 5 — the FIRST interrupt producer).
## Deliberately minimal: ONE stat draining per simulation second (doc 41 rate);
## below the threshold the dwarf releases its task through the §2.8 protocol
## and seeks an assigned/free bed or nearby ground shelter for the minimum rest,
## counted in game hours. DwarfMood supplies the personal-bedroom thought; the
## broader hunger/thirst/health needs remain a later milestone.
## RETUNED 2026-08-07 (Alen playtest: "the dwarves are just stuck doing
## nothing" — the whole squad was asleep). The original 0.003/s drain (doc
## 41's old table value) emptied full→threshold in ~250 real s ≈ 4 game
## hours: dwarves spent 60% of their lives asleep, and since the initial
## stagger only spreads first-sleep by ~2 min while a nap lasts 6, the
## entire colony full-stopped for minutes at a time in every session.
## 0.0007/s gives ~17.9 game hours awake per 6-hour nap — the 24-hour cycle
## doc 41 §Biological Limits actually specifies (doc 41 table updated in
## sync). Per-dwarf drain jitter (±10%, deterministic — set in setup())
## makes the squad's schedules decohere over time instead of staying
## phase-locked off the spawn stagger.
const SLEEP_DRAIN_PER_S := 0.0007   # per simulation second; doc 41 drain rate
const SLEEP_THRESHOLD := 0.25       # doc 41: sleep taken autonomously below this
const SLEEP_HOURS := 6.0            # doc 41: minimum rest per 24-hour cycle
var sleep: float = 1.0
var _sleep_drain: float = SLEEP_DRAIN_PER_S   # per-dwarf jittered rate (setup())
var _sleeping: bool = false
var _sleep_hours_left: float = 0.0
var _mood: RefCounted
var _recreation: RefCounted
var _food: RefCounted
var _tastes: RefCounted

## Fired when a walk order finishes (arrived) or fails (no path / cleared).
signal walk_finished(success: bool)

## Movement (step 3b) runs in DwarfMovement. Walk speed and stride stay here
## as tunable exports; the path state is forwarded for the other components.
@export var walk_speed: float = 3.4      # defaults overridden by TaskManager movement tuning
@export var stride_length: float = 1.05  # blocks per step; longer stride keeps a natural cadence
@export var walk_lean_deg: float = 2.5   # forward body pitch while walking (0 = off)
# Used only by the components, which the unused-variable check cannot see.
@warning_ignore_start("unused_private_class_variable")
var _move_path: Array[Vector3i]:
	get: return _movement.move_path
	set(value): _movement.move_path = value
var _move_index: int:
	get: return _movement.move_index
	set(value): _movement.move_index = value
var _walk_cycle: float:
	get: return _movement.walk_cycle
	set(value): _movement.walk_cycle = value
var _shortcut_timer: float:
	get: return _movement.shortcut_timer
	set(value): _movement.shortcut_timer = value
var _ladder_path_revision: int:
	get: return _movement.ladder_path_revision
	set(value): _movement.ladder_path_revision = value
var _move_validation_index: int:
	get: return _movement.move_validation_index
	set(value): _movement.move_validation_index = value
@warning_ignore_restore("unused_private_class_variable")

# ── Part nodes (built by DwarfBodyRig; procedural pose targets) ───────────────
var _head: Node3D
var _body: Node3D
var _hand_l: Node3D
var _hand_r: Node3D
var _foot_l: Node3D
var _foot_r: Node3D
var _bob_phase: float = 0.0
var _idle_behavior: RefCounted
var _rest_behavior: RefCounted
var _equipment: RefCounted


func _init() -> void:
	_rig = BodyRig.new(self)
	_movement = Movement.new(self, _rig)
	_work_execution = WorkExecution.new(self, _rig, _movement)


func setup(p_dwarf_id: int, data: Dictionary) -> void:
	dwarf_id = p_dwarf_id
	dwarf_name = String(data.get("name", "Urist"))
	gender = String(data.get("gender", "male"))
	appearance = data.get("appearance") as DwarfAppearanceData
	proportions = DwarfAssets.get_proportions()
	traits.assign(data.get("traits", []))
	profession = String(data.get("profession", "base:profession:worker"))
	profession_experience = data.get("profession_experience", {})
	work_permissions = data.get("work_permissions", {}).duplicate(true)
	name = "Dwarf_%d_%s" % [dwarf_id, dwarf_name]
	_bob_phase = float(dwarf_id) * 1.7   # desynchronise the squad's idle motion
	# Stagger initial tiredness deterministically (birth-index hash, no randf)
	# so a squad spawned together does not collapse asleep in the same instant
	# (at the retuned drain, this 0.35 spread = ~8 minutes at x1 of first-sleep
	# spread), and jitter each dwarf's drain rate ±10% so sleep schedules
	# DECOHERE across days instead of staying phase-locked — identical rates
	# preserve the initial offsets forever, and offsets smaller than a nap
	# still produce a window where the whole colony sleeps at once.
	sleep = 1.0 - fposmod(float(dwarf_id) * 0.191, 0.35)
	_sleep_drain = SLEEP_DRAIN_PER_S * (0.9 + 0.2 * fposmod(float(dwarf_id) * 0.317, 1.0))

	_rig.build()
	_head = _rig.head
	_body = _rig.body
	_hand_l = _rig.hand_l
	_hand_r = _rig.hand_r
	_foot_l = _rig.foot_l
	_foot_r = _rig.foot_r
	_felling_pose = _rig.felling_pose
	_construction_pose = _rig.construction_pose
	_mining_pose = _rig.mining_pose
	_carry_pose = _rig.carry_pose
	_reset_part_offsets()
	walk_finished.connect(_on_walk_finished)
	_idle_behavior = IdleBehavior.new(self)
	_equipment = Equipment.new(self)
	_rest_behavior = RestBehavior.new(self)
	_mood = preload("res://scripts/components/DwarfMood.gd").new()
	_food = preload("res://scripts/components/DwarfFoodBehavior.gd").new(self)
	_mood.food = _food
	_tastes = preload("res://scripts/components/DwarfTastes.gd").new()
	_tastes.setup(data.get("tastes", {}), data.get("found_tastes", []))
	_mood.tastes = _tastes
	preload("res://scripts/components/DwarfReadability.gd").attach(self)
	var movement := TaskManager.get_config_section("movement")
	walk_speed = float(movement.get("walk_speed",walk_speed))
	stride_length = float(movement.get("stride_length",stride_length))
	_movement.foot_lift = float(movement.get("foot_lift",_movement.foot_lift))


func _process(delta: float) -> void:
	if WorldClock.paused or WorldClock.speed <= 0.0: return
	_mood.tick(delta * WorldClock.game_hours_per_real_second())
	_food.clock_tick(delta * WorldClock.game_hours_per_real_second())
	if _settle_missing_support(): return
	if needs_bridge_exit():
		_process_bridge_exit(delta * WorldClock.speed)
		return
	if _ladder_exiting or (current_task_id < 0 and _movement.move_path.is_empty() and needs_ladder_exit()):
		_process_ladder_exit(delta * WorldClock.speed)
		return
	if _sleeping:
		_process_sleeping(delta)
		return
	if _task_phase in [TaskPhase.FELL_FINDING, TaskPhase.FELL_MOVING, TaskPhase.FELL_WORKING,
			TaskPhase.ZONE_MOVING, TaskPhase.ZONE_SWINGING,
			TaskPhase.HAUL_TO_ITEM, TaskPhase.HAUL_TO_ZONE, TaskPhase.HAUL_PICKUP, TaskPhase.HAUL_DEPOSIT,
			TaskPhase.FETCH_TO_ITEM, TaskPhase.FETCH_TO_GHOST, TaskPhase.FETCH_WORKING,
			TaskPhase.FETCH_PICKUP, TaskPhase.FETCH_DEPOSIT] \
			and (WorldClock.paused or WorldClock.speed <= 0.0):
		return
	# Sleep drains in EVERY waking state — idle, walking, working, swinging —
	# so the threshold can interrupt any of them (doc 16 Phase 5 acceptance).
	# Match the game-speed scaling used by sleep recovery and the calendar.
	sleep = maxf(sleep - _sleep_drain * delta * WorldClock.speed, 0.0)
	if _food.active():
		_food.tick(delta * WorldClock.speed)
		return
	if _food.famished() and _food.begin_if_needed(): return
	if sleep <= SLEEP_THRESHOLD:
		_begin_sleep()
		return
	if promotion_pending():
		_equipment.tick(delta)
		return
	if _food.begin_if_needed(): return
	if is_recreating():
		_recreation.tick_actor(self,delta * WorldClock.speed)
		return
	if current_task_id < 0 and _task_phase == TaskPhase.NONE and _idle_behavior != null:
		if _idle_behavior.tick(delta * WorldClock.speed): return
	if _work_execution.tick(delta * WorldClock.speed): return
	if _movement.move_path.is_empty():
		_idle_bob()
	else:
		_movement.follow_path(delta * WorldClock.speed)
	if not _rig.climbing and not _carried_entries.is_empty() and _task_phase not in [TaskPhase.HAUL_PICKUP, TaskPhase.FETCH_PICKUP,
			TaskPhase.HAUL_DEPOSIT, TaskPhase.FETCH_DEPOSIT]:
		_carry_pose.hold(_carried_entries, _body.position.y if is_instance_valid(_body) else 0.0)


# ── Task dispatch (doc 16 step 4) ─────────────────────────────────────────────

## Called by TaskManager on assignment. DwarfWorkExecution.start runs the task
## family's executor; a task with no executor fails permanently instead of
## cycling through PENDING. Failure paths use the release protocol — releasing
## is always cheap and legal (doc 16 §2.8).
func receive_task(task_id: int, target_pos: Vector3i, carried_item: Node3D = null) -> void:
	var assignment := TaskManager.get_task(task_id)
	if assignment == null or assignment.attempt == null: return
	_work_execution.bind(assignment)
	if _sleeping or promotion_pending() or is_eating() or is_recreating():
		# Race guard (should not happen — sleepers leave the idle pool): an
		# assignment landing in the frame the dwarf fell asleep bounces straight
		# back to PENDING; releasing is always cheap and legal (§2.8).
		_work_execution.release(dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
		return
	if _idle_behavior != null: _idle_behavior.cancel()
	_reset_part_offsets()
	current_task_id = task_id
	_work_execution.start(task_id, TaskManager.get_task(task_id), target_pos, carried_item)


## Detach ownership, not the node: a confirmed placement retains this exact
## cargo while normal haul cancellation safely drops any remaining bundle.
func detach_placement_cargo(item: Node3D) -> bool:
	for index in range(_carried_entries.size()):
		if _carried_entries[index][0] == item:
			_carried_entries.remove_at(index)
			return true
	return false


## Explicit career changes preserve experience and use normal task release.
func change_profession(key: String) -> bool:
	if not DwarfAssets.profession_enabled(key): return false
	if is_eating(): _food.cancel()
	if key == profession:
		if not promotion_pending(): return false
		_equipment.cancel()
		return true
	if not DwarfAssets.profession_tool(key).is_empty(): return _equipment.request(key)
	_equipment.cancel("", false)
	_release_for_assignment_change()
	_equipment.return_tool()
	_complete_profession_change(key)
	_equipment.message = "%s is now a %s." % [dwarf_name, DwarfAssets.profession_definition(key).display_name]
	if not _sleeping: TaskManager.notify_dwarf_idle(dwarf_id)
	return true


func promotion_pending() -> bool:
	return _equipment != null and _equipment.active()


func is_eating() -> bool:
	return _food != null and _food.active()


func dev_make_hungry() -> bool:
	if _food == null or is_sleeping() or is_eating() or promotion_pending(): return false
	_food.value = float(_food.config.hungry_threshold)
	_food.retry_hours = 0.0
	return true


func _complete_profession_change(key: String) -> void:
	var promoted := key != profession and key != "base:profession:worker"
	profession = key
	if not profession_experience.has(key): profession_experience[key] = 0
	TaskManager.work_policy_changed()
	if not promoted: return
	WorkFeedback.play_promotion(global_position)
	# A promotion is colony news in the event log (doc 23), with the profession's icon.
	var definition := DwarfAssets.profession_definition(key)
	var options := {"dwarves": [dwarf_id]}
	if definition.has("icon"): options.picture = String(definition.icon)
	EventLog.post("colony", "%s is now a %s." % [dwarf_name, String(definition.get("display_name", "specialist"))], options)


func set_work_permission(key: String, allowed: bool) -> void:
	var known := false
	for entry: Dictionary in DwarfAssets.work_permissions():
		if entry.id == key: known = true
	if not known: return
	work_permissions[key] = allowed
	var task := TaskManager.get_task(current_task_id)
	if task != null and not allows_task(task.type): _release_for_assignment_change()
	TaskManager.work_policy_changed()


func allows_task(type: int) -> bool:
	if work_permissions.is_empty(): return true
	return bool(work_permissions.get(DwarfAssets.work_category(Task.type_name(type)), true))


func _release_for_assignment_change() -> void:
	if is_recreating(): _recreation.cancel()
	if current_task_id < 0: return
	abort_task()
	_work_execution.release(dwarf_id, Task.ReleaseReason.PLAYER, not _sleeping)


## Called by TaskManager when the task is cancelled out from under us.
func abort_task() -> void:
	if is_recreating(): _recreation.cancel(dwarf_id)
	if is_eating(): _food.cancel("Meal interrupted; food is preserved.", false)
	if promotion_pending(): _equipment.cancel()
	if _idle_behavior != null: _idle_behavior.cancel()
	_work_execution.abort()
	current_task_id = -1
	stop_walking()


func _on_walk_finished(success: bool) -> void:
	if is_recreating():
		_recreation.walk_finished(self,success)
		return
	if is_eating():
		_food.walk_finished(success)
		return
	if promotion_pending():
		_equipment.walk_finished(success)
		return
	if current_task_id < 0 and _idle_behavior != null and _idle_behavior.owns_walk():
		_idle_behavior.walk_finished(success)
		return
	_work_execution.walk_finished(success)


## Executors already standing at their goal finish the walk through the same
## dispatch as a completed path.
func finish_walk(success: bool) -> void:
	_on_walk_finished(success)


# ── Sleep-lite (doc 16 §2.8 / Phase 5) ────────────────────────────────────────

## The interrupt: release whatever we hold through the §2.8 protocol and sleep
## beside nearby shelter. Local task state is torn down FIRST (phase to NONE before
## stop_walking, the abort_task ordering) so the synchronous walk_finished(false)
## cannot re-enter the executors. The zone reservation is freed by the
## controller on task_released; zone-level progress (completed set) is never
## touched; partial swing progress is discarded — the block keeps full
## durability (swings only commit at zero).
func _begin_sleep() -> void:
	if is_recreating(): _recreation.cancel(dwarf_id)
	if is_eating(): _food.cancel("Meal interrupted for rest.", false)
	if promotion_pending(): _equipment.cancel("Promotion cancelled for sleep. The tool is available again.", false)
	if _idle_behavior != null: _idle_behavior.cancel()
	if not NavGrid.is_walkable(current_cell()) and not NavGrid.ladder_at(current_cell()).is_empty():
		# Needs may interrupt a job immediately, but sleep begins on a real floor.
		force_interrupt()
		_ladder_sleep_pending = true
		_ladder_exiting = true
		TaskManager.notify_dwarf_unavailable(dwarf_id)
		return
	_sleeping = true
	_sleep_hours_left = SLEEP_HOURS
	_mood.begin_sleep()
	var had_task := current_task_id >= 0
	_work_execution.clear_task_state()
	current_task_id = -1
	stop_walking()
	_reset_part_offsets()
	if had_task:
		# requeue_dwarf = false: we re-enter the idle pool only on waking (§2.8).
		_work_execution.release(dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
	else:
		TaskManager.notify_dwarf_unavailable(dwarf_id)
	_rest_behavior.begin()


func _process_sleeping(delta: float) -> void:
	# Duration counts in IN-GAME hours: honours clock speed, freezes on pause.
	if _rest_behavior.tick(delta * WorldClock.speed):
		var hours := minf(_sleep_hours_left,delta * WorldClock.game_hours_per_real_second())
		var sleep_cell := current_cell()+Vector3i.UP
		if _rest_behavior.bed_rest.bed!=null: sleep_cell = _rest_behavior.bed_rest.bed.origin_cell+Vector3i.UP
		_mood.record_sleep(hours,_rest_behavior.bed_rest.in_personal_bedroom(),RoomManager.temperature_at(sleep_cell))
		_sleep_hours_left -= hours
		if _sleep_hours_left <= 0.0:
			# A night in the bed finds the dwarf's taste for it before the room's thought.
			meet_pieces([_rest_behavior.bed_rest.bed])
			_mood.finish_sleep(RoomManager.appeal_at(sleep_cell))
			_rest_behavior.begin_waking()


func _wake_up() -> void:
	_sleeping = false
	sleep = 1.0
	_sleep_hours_left = 0.0
	if _rest_behavior != null: _rest_behavior.cancel()
	_reset_part_offsets()
	TaskManager.notify_dwarf_idle(dwarf_id)


func is_sleeping() -> bool:
	return _sleeping


func is_recreating() -> bool:
	return _recreation != null


func is_resting() -> bool:
	return _sleeping and _rest_behavior != null and _rest_behavior.state == "sleeping"


# ── Read-only views for UI and other systems (the agent's own components use the fields) ──
func get_task_phase() -> int: return _work_execution.task_phase
func get_mood() -> RefCounted: return _mood
func get_food() -> RefCounted: return _food
func get_tastes() -> RefCounted: return _tastes


## The dwarf uses these pieces (the bed after a night, a seat and table after a meal or a
## game): tastes found for the first time go to the journal (doc 41 "Tastes").
func meet_pieces(pieces: Array) -> void:
	for news: Dictionary in _tastes.meet(pieces):
		ColonyJournal.note_taste(self, String(news.id), String(news.kind))
func get_recreation() -> RefCounted: return _recreation
func get_rest_behavior() -> RefCounted: return _rest_behavior
func get_idle_behavior() -> RefCounted: return _idle_behavior
func get_equipment() -> RefCounted: return _equipment
func get_head() -> Node3D: return _head
func get_body() -> Node3D: return _body
func get_slice_y() -> int: return _slice_y
func get_carried_entries() -> Array: return _rig.carried_entries
func get_move_path() -> Array[Vector3i]: return _movement.move_path
func get_sleep_hours_left() -> float: return _sleep_hours_left
func get_haul_deposit() -> Vector3i: return _work_execution.get_haul_deposit()
func get_zone_block() -> Vector3i: return _work_execution.get_zone_block()
func is_climbing() -> bool: return _rig.climbing
func is_ladder_exiting() -> bool: return _ladder_exiting
## The item the dwarf is walking to pick up: the next haul bundle item, else the fetch item.
func target_item() -> Node3D: return _work_execution.target_item()
## Current step, unit and expected time for TaskManager supervision.
func work_sample() -> Dictionary: return _work_execution.sample()
func haul_source() -> RefCounted: return _work_execution.haul_source()
func fetch_source() -> RefCounted: return _work_execution.fetch_source()
func uninstall_source() -> RefCounted: return _work_execution.uninstall_source()


func serialize_state() -> Dictionary:
	var appearance_state: Dictionary = {}
	var carried_items: Array = []
	for entry in _rig.carried_entries:
		if entry is Array and (entry as Array).size() >= 2:
			var cargo: Node3D = (entry as Array)[0]
			carried_items.append({"item_key": String((entry as Array)[1]),
				"count": int(cargo.get_meta("quantity", 1)) if is_instance_valid(cargo) else 1})
			carried_items.back()["disallowed"] = not preload("res://scripts/components/ItemPermission.gd").allowed(cargo)
			if is_instance_valid(cargo) and cargo.has_meta("instance_id"):
				carried_items.back()["instance_id"] = cargo.get_meta("instance_id")
			carried_items.back()["material_id"] = CraftMaterials.of_item(cargo)
	if appearance != null:
		appearance_state = {
			"gender": appearance.gender,
			"age_tier": appearance.age_tier,
			"skin_tone": appearance.skin_tone,
			"eye_color": appearance.eye_color,
			"hair_color": appearance.hair_color,
			"hair_style": appearance.hair_style,
			"eyebrow_style": appearance.eyebrow_style,
			"beard_style": appearance.beard_style,
			"scar": appearance.scar,
			"clothing": appearance.clothing,
		}
	return {
		"id": dwarf_id,
		"name": dwarf_name,
		"gender": gender,
		"appearance": appearance_state,
		"traits": traits.duplicate(),
		"tastes": _tastes.tastes.duplicate(),
		"found_tastes": _tastes.found.keys(),
		"profession": profession,
		"profession_experience": profession_experience.duplicate(true),
		"work_permissions": work_permissions.duplicate(true),
		"position": SaveManager.pack_v3(position),
		"rotation_y": rotation.y,
		"sleep": sleep,
		"sleeping": _sleeping,
		"sleep_hours_left": _sleep_hours_left,
		"mood": _mood.serialize(),
		"food": _food.serialize(),
		"carried_items": carried_items,
		"equipment": _equipment.serialize() if _equipment != null else {},
	}

func restore_saved_runtime(state: Dictionary) -> void:
	if is_recreating(): _recreation.cancel(dwarf_id)
	if is_eating(): _food.cancel("", false)
	if _idle_behavior != null: _idle_behavior.cancel()
	if _rest_behavior != null: _rest_behavior.cancel()
	sleep = clampf(float(state.sleep), 0.0, 1.0)
	_sleeping = bool(state.sleeping)
	_sleep_hours_left = maxf(float(state.sleep_hours_left), 0.0)
	_mood.restore(state.mood)
	_food.restore(state.food)
	current_task_id = -1
	_task_phase = TaskPhase.NONE
	stop_walking()
	_reset_part_offsets()
	_equipment.restore(state.get("equipment", {}))
	if _sleeping: _rest_behavior.begin(true)

# ── Interruption ──────────────────────────────────────────────────────────────

## Instant deterministic interruption: cancel recreation, a meal or a pending
## promotion, or force-release the current task with reason PLAYER and return
## to the idle pool immediately. Returns false if there was nothing to interrupt.
func force_interrupt() -> bool:
	if is_recreating():
		_recreation.cancel()
		return true
	if is_eating():
		_food.cancel()
		return true
	if promotion_pending():
		_equipment.cancel()
		return true
	if current_task_id < 0:
		return false
	_work_execution.clear_task_state()
	current_task_id = -1
	stop_walking()
	_reset_part_offsets()
	_work_execution.release(dwarf_id, Task.ReleaseReason.PLAYER)
	return true

# ── DEV helpers (Dwarves window buttons) ──────────────────────────────────────

## Drops the sleep stat to the threshold so the ORGANIC interrupt path fires on
## the next frame — tests release + sleep + wake + resume without the ~4-minute
## real-time drain. Returns false if the dwarf is already asleep.
func dev_make_tired() -> bool:
	if _sleeping:
		return false
	sleep = SLEEP_THRESHOLD
	return true

# ── Physical support ──────────────────────────────────────────────────────────

## Every state needs physical support, including idle/sleeping dwarves and old
## saved positions. Terrain edits can remove support or raise it into our feet.
## Recover before doing work or asking navigation for a path.
func _settle_missing_support() -> bool:
	if not _movement.lift_from_raised_floor() and not _movement.snap_to_floor(): return false
	# Move first so interruption drops cargo at the actual landing. Normal
	# cleanup releases source/seat/tool claims and reports a failed walk once.
	abort_task()
	if _sleeping and _rest_behavior != null: _rest_behavior.begin()
	_work_execution.release(dwarf_id,Task.ReleaseReason.PATH_INVALID,not _sleeping)
	return true


## The item's floor cell, distinct from the adjacent worker's stand cell.
func item_floor_cell(node: Node3D) -> Vector3i:
	return Vector3i(
		floori(node.position.x),
		int(round(node.position.y)) - 1,
		floori(node.position.z))


## Hard Rule 12 cargo drop (DwarfCarryWork), for the meal and promotion components.
func _drop_carried_at_feet() -> void:
	_work_execution.drop_carried_at_feet()


# ── Movement (doc 16 step 3b; path following lives in DwarfMovement) ──────────

## Current FLOOR cell (the block under the feet). Standing height is
## floor_y + 1, so the floor is one below the rounded position.
func current_cell() -> Vector3i:
	return Vector3i(
		floori(global_position.x),
		int(round(global_position.y)) - 1,
		floori(global_position.z))


var _ladder_exiting := false
var _bridge_exiting := false
var _ladder_sleep_pending := false


func needs_bridge_exit() -> bool:
	return _bridge_exiting or not NavGrid.closing_bridge_at(current_cell()).is_empty()

func _process_bridge_exit(delta: float) -> void:
	var route := NavGrid.closing_bridge_at(current_cell())
	if not _bridge_exiting:
		abort_task() # Cargo is dropped intact on the still-supported deck.
		_work_execution.release(dwarf_id, Task.ReleaseReason.PATH_INVALID, false)
		if _sleeping: _wake_up()
		if _idle_behavior != null: _idle_behavior.cancel()
		_movement.clear_path()
		_bridge_exiting = true
	TaskManager.notify_dwarf_unavailable(dwarf_id)
	if route.is_empty():
		# Finish reaching the landing centre before retiring the escape path.
		if not _movement.move_path.is_empty(): _movement.follow_path(delta); return
		_bridge_exiting = false
		TaskManager.notify_dwarf_idle(dwarf_id)
		return
	if _movement.move_path.is_empty():
		var exits: Array = route.exits.duplicate()
		exits.sort_custom(func(a: Vector3i,b: Vector3i): return current_cell().distance_squared_to(a) < current_cell().distance_squared_to(b))
		for cell: Vector3i in exits:
			if NavGrid.is_walkable(cell) and walk_to(cell): break
	if not _movement.move_path.is_empty(): _movement.follow_path(delta)

func needs_ladder_exit() -> bool:
	return _ladder_exiting or (not NavGrid.ladder_at(current_cell()).is_empty() and not NavGrid.is_walkable(current_cell()))

func _process_ladder_exit(delta: float) -> void:
	TaskManager.notify_dwarf_unavailable(dwarf_id)
	if _movement.ladder_fall_target.x >= 0:
		var target := Vector3(_movement.ladder_fall_target) + Vector3(.5, 1, .5)
		global_position = global_position.move_toward(target, walk_speed * delta)
		if global_position.is_equal_approx(target):
			_movement.ladder_fall_target = Vector3i(-1,-1,-1)
			_movement.clear_path()
		return
	if not _ladder_exiting or _movement.move_path.is_empty():
		var route := NavGrid.ladder_at(current_cell())
		if route.is_empty() or NavGrid.is_walkable(current_cell()):
			_ladder_exiting = false
			if _ladder_sleep_pending:
				_ladder_sleep_pending = false
				_begin_sleep()
			else: TaskManager.notify_dwarf_idle(dwarf_id)
			return
		_ladder_exiting = true
		# If mining removed the foot support, continue down to the next real floor.
		var base: Vector3i = route.base
		if not NavGrid.is_walkable(base):
			base = NavGrid.walkable_floor_at(base.x, base.z, base.y, base.y - 1)
			if base.x >= 0:
				# Support destruction settles the actor down its clear column;
				# it does not create traversable rungs beneath the installed route.
				_movement.ladder_fall_target = base
				_movement.clear_path()
				return
		if not walk_to(base): return
	_movement.follow_path(delta)


## Orders a walk to a goal floor cell. Returns true if a path was found and
## the walk began; emits walk_finished(success) when it ends either way.
func walk_to(goal_cell: Vector3i) -> bool:
	if is_recreating(): _recreation.cancel()
	if is_eating(): _food.cancel("Meal interrupted by movement.")
	if promotion_pending(): _equipment.cancel("Promotion cancelled by movement.")
	if _idle_behavior != null and _idle_behavior.active(): _idle_behavior.cancel()
	return _movement.walk_to(goal_cell)


## Leisure uses only short, fully checked flat segments. No global A* search
## or ladder route is needed, and normal work can replace this path immediately.
func walk_nearby(goal_cell: Vector3i) -> void:
	if is_recreating(): _recreation.cancel()
	if is_eating(): _food.cancel("Meal interrupted by movement.")
	if promotion_pending(): _equipment.cancel("Promotion cancelled by movement.")
	_movement.walk_nearby(goal_cell)


func stop_walking() -> void:
	_movement.stop_walking()


func is_walking() -> bool:
	return _movement.is_walking()


# Thin forwarders for the other dwarf components (DwarfMovement / DwarfBodyRig).
func _clear_path() -> void: _movement.clear_path()
func _follow_path(delta: float) -> void: _movement.follow_path(delta)
func _reset_part_offsets() -> void: _rig.reset_part_offsets()
func _idle_bob() -> void: _rig.idle_bob(_bob_phase)


func set_name_label_visible(show_label: bool) -> void:
	var label := get_node_or_null("NameLabel")
	if label != null:
		(label as Label3D).visible = show_label


func _exit_tree() -> void:
	if is_recreating(): _recreation.cancel(dwarf_id)
	if _food != null: _food.release_reservation()
	if _rest_behavior != null: _rest_behavior.cancel()
	if _idle_behavior != null: _idle_behavior.cancel()
	if _equipment != null: _equipment.release_reservation()


# ── Slice culling: director selects the cut; movement refreshes visibility ───

var _slice_y := SliceController.MAX_SLICE_Y

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		set_notify_transform(true)
	elif what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		# Stair/ladder travel can cross the slice without changing the slice
		# control. Refresh before rendering, including restored/paused moves.
		_update_slice_visibility()

func apply_slice(slice_y: int) -> void:
	_slice_y = slice_y
	_update_slice_visibility()

func _update_slice_visibility() -> void:
	var within_slice := floori(global_position.y) <= _slice_y
	if visible != within_slice: visible = within_slice
