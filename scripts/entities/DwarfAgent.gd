class_name DwarfAgent
extends CharacterBody3D

## One dwarf colonist (doc 41 / 41b). First Dwarf Milestone Phase 1 scope:
## visual assembly, runtime tinting, procedural idle bob, and slice culling.
## State machine, needs, navigation-following, and task execution arrive in
## later phases of doc 16.
##
## VISUAL CONTRACT (doc 41, hard rules):
##   - Four-part silhouette: oversized head, compact torso, DETACHED floating
##     hands and feet. No arms, no legs — ever.
##   - Parts are independent MeshInstance3D-bearing nodes; NEVER merged into a
##     single mesh (equipment attaches as children; animation drives transforms).
##   - All parts attach at identity transforms — the GLBs are authored in a
##     shared coordinate frame with the 0.125 scale baked in (doc 41b / 15).
##   - Visual height ~3.3 blocks; LOGICAL height 3 blocks (1x1x3 footprint) —
##     collision and (future) nav use the logical box, never the visual AABB.

const LOGICAL_HEIGHT := 3.0    # blocks — collision + future nav clearance
const COLLISION_LAYER_DWARF := 4   # layer bit 3. NOT layer 1 (camera spring arm
								   # collides mask 1, terrain only) and NOT
								   # layer 2 (trees) — see doc 13 §7 gotcha.

# ── Identity (set once by setup) ──────────────────────────────────────────────
var dwarf_id: int = -1
var dwarf_name: String = ""
var gender: String = "male"
var appearance: DwarfAppearanceData = null
var traits: Array[String] = []
var profession: String = "base:profession:worker"
var profession_experience: Dictionary = {}

## The claimed task id (id, NOT the Task object — doc 16 §2.2). -1 = idle.
var current_task_id: int = -1

## Task execution phases. MOVING/EXECUTING is the generic v1 executor (walk to
## target, work a fixed timer — synthetic DEV tasks still use it).
## ZONE_MOVING/ZONE_SWINGING is the MINE-lease executor (doc 16 §2.7): pull a
## block from the zone's destination set, reserve it, path to a stand cell,
## swing it down, commit, pull the next.
## HAUL_TO_ITEM/HAUL_TO_ZONE is the HAUL-lease executor (doc 18 §2.3): pull
## the nearest accepted loose item, reserve it + a deposit cell, walk over,
## pick it up, carry it to the stockpile, deposit, pull the next.
enum TaskPhase { NONE, MOVING, EXECUTING, ZONE_MOVING, ZONE_SWINGING, HAUL_TO_ITEM, HAUL_TO_ZONE,
		FETCH_TO_ITEM, FETCH_TO_GHOST, FETCH_WORKING, UNINSTALL_MOVING, UNINSTALL_WORKING }
const GENERIC_WORK_TIME := 1.0   # seconds — generic executor only
var _task_phase: int = TaskPhase.NONE
var _task_target: Vector3i = Vector3i.ZERO
var _exec_timer: float = 0.0

## Zone-lease execution state (doc 16 step 6).
const ZONE_PULL_FAILURE_LIMIT := 3   # §2.7 step 2: 3 path failures -> release lease
## Off-profession speed (doc 31: ×0.7). Every dwarf is a Worker in v1, so the
## miner-profession fast path is a later hook; 1.0 keeps the formula visible.
const MINING_SPEED_MULT := 1.0
var _zone_id: int = -1
var _zone_block: Vector3i = Vector3i(-1, -1, -1)
var _zone_stand_cells: Array[Vector3i] = []
var _stand_index: int = 0
var _swings_left: int = 0
var _swing_time: float = 1.0
var _swing_timer: float = 0.0
var _pull_failures: int = 0
var _pull_exclude: Dictionary = {}   # Vector3i -> true; this-round path blacklist

## HAUL-lease execution state (doc 18 §2.3 + pouch). Mirrors the zone-lease
## shape: 3 failed rounds release the lease with backoff; EVERYTHING carried
## is dropped at the feet on ANY interruption (Hard Rule 12). The pouch (SH
## backpack parity): a pull is a BUNDLE of up to pouch_capacity items visited
## in order, carried as a stack, deposited in one trip.
const HAUL_PULL_FAILURE_LIMIT := 3
const CARRY_OFFSET := Vector3(0.0, 1.8, 0.55)   # chest height, in front (local +Z = facing)
const CARRY_STACK_STEP := 0.95                  # vertical spacing of pouch items
var _haul_source_id: int = -1
var _haul_items: Array[Node3D] = []  # this round's bundle, visit order
var _haul_index: int = 0             # next bundle item to fetch
var _haul_deposit: Vector3i = Vector3i(-1, -1, -1)
var _haul_failures: int = 0
var _haul_exclude: Dictionary = {}   # Node3D -> true; this-round item blacklist
var _carried_entries: Array = []     # [[node: Node3D, item_key: String], ...]
var _carry_speed_mult: float = 1.0

## Furniture pipeline (doc 19 §3.3/§3.4). FETCH_BUILD: reserve item via the
## ghost work source -> walk -> pick up -> walk to the ghost -> build swing.
## UNINSTALL: walk to the piece's stand cell -> teardown swing. Interrupts
## anywhere follow Hard Rule 12 (carried item drops at the feet; an
## uninstall interrupt leaves the piece installed with the flag set).
var _fetch_source_id: int = -1
var _fetch_item: Node3D = null       # reserved (pre-pickup) or carried (post)
var _fetch_picked_up: bool = false
var _fetch_heavy: bool = false
var _uninstall_source_id: int = -1

## Sleep-lite (doc 16 §2.8 / Phase 5 — the FIRST interrupt producer).
## Deliberately minimal: ONE stat draining per real second (doc 41 rate);
## below the threshold the dwarf releases its task through the §2.8 protocol
## and sleeps IN PLACE (no beds yet) for the doc-41 minimum rest, counted in
## in-game hours (clock-speed aware, frozen while paused). The full needs
## system (hunger/thirst/mood/thoughts) is its own later milestone.
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
const SLEEP_DRAIN_PER_S := 0.0007   # doc 41 §Physiological Stats drain rate (retuned)
const SLEEP_THRESHOLD := 0.25       # doc 41: sleep taken autonomously below this
const SLEEP_HOURS := 6.0            # doc 41: minimum rest per 24-hour cycle
var sleep: float = 1.0
var _sleep_drain: float = SLEEP_DRAIN_PER_S   # per-dwarf jittered rate (setup())
var _sleeping: bool = false
var _sleep_hours_left: float = 0.0

## Fired when a walk order finishes (arrived) or fails (no path / cleared).
signal walk_finished(success: bool)

## Movement (step 3b). Path = ordered floor cells from NavGrid; the agent
## stands on cell tops (y = floor_y + 1). Direct position movement — no
## physics sweep (collision_mask 0); obstacle correctness comes from the nav
## grid, not the physics engine.
##
## Walk animation (doc 17 §2 rework, 2026-07-02): the gait cycle is driven by
## DISTANCE TRAVELLED, not time — feet plant in sync with ground covered at
## any speed. With foot swing amplitude = stride_length/2 and the planted
## foot sliding backward (relative to the body) exactly one stride per half
## cycle, the planted foot stays world-fixed — the core fix for foot sliding.
@export var walk_speed: float = 2.2      # blocks/s on the flat (doc 17: 3.0 read too fast)
@export var stride_length: float = 0.7   # blocks covered per step (one foot's half cycle)
@export var walk_lean_deg: float = 2.5   # forward body pitch while walking (0 = off)
const SHORTCUT_INTERVAL := 0.3   # s between string-pulling rescans (cost bound)
var _move_path: Array[Vector3i] = []
var _move_index: int = 0
var _walk_cycle: float = 0.0
var _shortcut_timer: float = 0.0

# ── Part nodes (procedural bob targets) ───────────────────────────────────────
var _head: Node3D
var _body: Node3D
var _hand_l: Node3D
var _hand_r: Node3D
var _foot_l: Node3D
var _foot_r: Node3D
var _bob_phase: float = 0.0


func setup(p_dwarf_id: int, data: Dictionary) -> void:
	dwarf_id = p_dwarf_id
	dwarf_name = String(data.get("name", "Urist"))
	gender = String(data.get("gender", "male"))
	appearance = data.get("appearance") as DwarfAppearanceData
	traits.assign(data.get("traits", []))
	profession = String(data.get("profession", "base:profession:worker"))
	profession_experience = data.get("profession_experience", {})
	name = "Dwarf_%d_%s" % [dwarf_id, dwarf_name]
	_bob_phase = float(dwarf_id) * 1.7   # desynchronise the squad's idle motion
	# Stagger initial tiredness deterministically (birth-index hash, no randf)
	# so a squad spawned together does not collapse asleep in the same instant
	# (at the retuned drain, this 0.35 spread = ~8 real minutes of first-sleep
	# spread), and jitter each dwarf's drain rate ±10% so sleep schedules
	# DECOHERE across days instead of staying phase-locked — identical rates
	# preserve the initial offsets forever, and offsets smaller than a nap
	# still produce a window where the whole colony sleeps at once.
	sleep = 1.0 - fposmod(float(dwarf_id) * 0.191, 0.35)
	_sleep_drain = SLEEP_DRAIN_PER_S * (0.9 + 0.2 * fposmod(float(dwarf_id) * 0.317, 1.0))

	_build_parts()
	_build_collision()
	_build_name_label()
	_build_sleep_indicator()
	_apply_tints()
	walk_finished.connect(_on_walk_finished)


func _process(delta: float) -> void:
	if _sleeping:
		_process_sleeping(delta)
		return
	# Sleep drains in EVERY waking state — idle, walking, working, swinging —
	# so the threshold can interrupt any of them (doc 16 Phase 5 acceptance).
	sleep = maxf(sleep - _sleep_drain * delta, 0.0)
	if sleep <= SLEEP_THRESHOLD:
		_begin_sleep()
		return
	if _task_phase == TaskPhase.EXECUTING:
		_exec_timer -= delta
		if _exec_timer <= 0.0:
			_task_phase = TaskPhase.NONE
			var finished_id := current_task_id
			current_task_id = -1
			if finished_id >= 0:
				TaskManager.complete_dwarf_task(dwarf_id)
	elif _task_phase == TaskPhase.ZONE_SWINGING:
		_process_swinging(delta)
		return   # swing bob owns the part offsets this frame
	elif _task_phase == TaskPhase.FETCH_WORKING:
		_exec_timer -= delta
		if _exec_timer <= 0.0:
			_fetch_complete()
	elif _task_phase == TaskPhase.UNINSTALL_WORKING:
		_exec_timer -= delta
		if _exec_timer <= 0.0:
			_uninstall_complete()
	if _move_path.is_empty():
		_idle_bob()
	else:
		_follow_path(delta)


# ── Task execution (doc 16 step 4 — generic v1 executor) ─────────────────────

## Called by TaskManager on assignment. MINE leases (payload carries zone_id)
## run the zone executor; everything else walks to the target and works the
## generic timer. Failure paths use the release protocol — releasing is
## always cheap and legal (doc 16 §2.8).
func receive_task(task_id: int, target_pos: Vector3i) -> void:
	if _sleeping:
		# Race guard (should not happen — sleepers leave the idle pool): an
		# assignment landing in the frame the dwarf fell asleep bounces straight
		# back to PENDING; releasing is always cheap and legal (§2.8).
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
		return
	current_task_id = task_id
	_task_target = target_pos
	var task := TaskManager.get_task(task_id)
	if task != null and task.type == Task.Type.MINE and task.payload.has("zone_id"):
		_zone_id = int(task.payload["zone_id"])
		_pull_failures = 0
		_pull_exclude.clear()
		_zone_pull_next()
		return
	if task != null and task.type == Task.Type.HAUL and task.payload.has("zone_id"):
		_haul_source_id = int(task.payload["zone_id"])
		_haul_failures = 0
		_haul_exclude.clear()
		_haul_pull_next()
		return
	if task != null and task.type == Task.Type.FETCH_BUILD:
		_fetch_source_id = task.source_id
		_fetch_begin()
		return
	if task != null and task.type == Task.Type.UNINSTALL:
		_uninstall_source_id = task.source_id
		_uninstall_begin()
		return
	# Phase is set AFTER walk_to: a synchronous walk_finished(false) from a
	# failed pathfind must not double-release through _on_walk_finished.
	if walk_to(target_pos):
		_task_phase = TaskPhase.MOVING
	else:
		# Probe said reachable but the full path failed (rare: cap mismatch or
		# terrain changed since). Release; backoff will retry it later.
		_task_phase = TaskPhase.NONE
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)


## Called by TaskManager when the task is cancelled out from under us.
func abort_task() -> void:
	# Defensive unreserve — the controller's cancelled-route also frees it,
	# but cancel ordering clears assigned_to before the signal fires.
	if _zone_id >= 0:
		var source := TaskManager.get_work_source(_zone_id)
		if source != null:
			source.call("release_worker", dwarf_id)
	_finish_zone_state()
	_finish_haul_state()
	_finish_fetch_state()
	_finish_uninstall_state()
	_task_phase = TaskPhase.NONE
	current_task_id = -1
	_exec_timer = 0.0
	stop_walking()


func _on_walk_finished(success: bool) -> void:
	if _task_phase == TaskPhase.ZONE_MOVING:
		_task_phase = TaskPhase.NONE
		if success:
			_begin_swinging()
		else:
			# Path invalidated mid-walk — try the block's remaining stand cells.
			_zone_try_stand()
		return
	if _task_phase == TaskPhase.HAUL_TO_ITEM:
		_task_phase = TaskPhase.NONE
		if success:
			_haul_pickup_current()
		else:
			_haul_skip_current()   # this item unreachable; the bundle continues
		return
	if _task_phase == TaskPhase.HAUL_TO_ZONE:
		_task_phase = TaskPhase.NONE
		if success:
			_haul_deposit_now()
		else:
			# Carrying and the path died — drop everything at the feet
			# (Hard Rule 12); the items re-enter the loose index.
			_drop_carried_at_feet()
			_haul_cancel_pull()
			_haul_count_failure()
		return
	if _task_phase == TaskPhase.FETCH_TO_ITEM:
		_task_phase = TaskPhase.NONE
		if success:
			_fetch_pickup()
		else:
			_fetch_fail_release()
		return
	if _task_phase == TaskPhase.FETCH_TO_GHOST:
		_task_phase = TaskPhase.NONE
		if success:
			_task_phase = TaskPhase.FETCH_WORKING
			_exec_timer = _furniture_time("build_time_s")
		else:
			_fetch_fail_release()
		return
	if _task_phase == TaskPhase.UNINSTALL_MOVING:
		_task_phase = TaskPhase.NONE
		if success:
			_task_phase = TaskPhase.UNINSTALL_WORKING
			_exec_timer = _furniture_time("uninstall_time_s")
		else:
			_finish_uninstall_state()
			current_task_id = -1
			TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)
		return
	if _task_phase != TaskPhase.MOVING:
		return
	if success:
		_task_phase = TaskPhase.EXECUTING
		_exec_timer = GENERIC_WORK_TIME
	else:
		_task_phase = TaskPhase.NONE
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)


# ── Sleep-lite (doc 16 §2.8 / Phase 5) ────────────────────────────────────────

## The interrupt: release whatever we hold through the §2.8 protocol and sleep
## in place. Local task state is torn down FIRST (phase to NONE before
## stop_walking, the abort_task ordering) so the synchronous walk_finished(false)
## cannot re-enter the executors. The zone reservation is freed by the
## controller on task_released; zone-level progress (completed set) is never
## touched; partial swing progress is discarded — the block keeps full
## durability (swings only commit at zero).
func _begin_sleep() -> void:
	_sleeping = true
	_sleep_hours_left = SLEEP_HOURS
	_set_sleep_indicator_visible(true)
	var had_task := current_task_id >= 0
	_finish_zone_state()
	_finish_haul_state()
	_finish_fetch_state()
	_finish_uninstall_state()
	_task_phase = TaskPhase.NONE
	current_task_id = -1
	_exec_timer = 0.0
	stop_walking()
	_reset_part_offsets()
	if had_task:
		# requeue_dwarf = false: we re-enter the idle pool only on waking (§2.8).
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.NEED_INTERRUPT, false)
	else:
		TaskManager.notify_dwarf_unavailable(dwarf_id)


func _process_sleeping(delta: float) -> void:
	# Duration counts in IN-GAME hours: honours clock speed, freezes on pause.
	_sleep_hours_left -= delta * WorldClock.game_hours_per_real_second()
	_sleep_bob()
	if _sleep_hours_left <= 0.0:
		_wake_up()


func _wake_up() -> void:
	_sleeping = false
	sleep = 1.0
	_sleep_hours_left = 0.0
	_set_sleep_indicator_visible(false)
	_reset_part_offsets()
	TaskManager.notify_dwarf_idle(dwarf_id)


func is_sleeping() -> bool:
	return _sleeping


func serialize_state() -> Dictionary:
	var appearance_state: Dictionary = {}
	var carried_items: Array[String] = []
	for entry in _carried_entries:
		if entry is Array and (entry as Array).size() >= 2:
			carried_items.append(String((entry as Array)[1]))
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
		}
	return {
		"id": dwarf_id,
		"name": dwarf_name,
		"gender": gender,
		"appearance": appearance_state,
		"traits": traits.duplicate(),
		"profession": profession,
		"profession_experience": profession_experience.duplicate(true),
		"position": SaveManager.pack_v3(position),
		"rotation_y": rotation.y,
		"sleep": sleep,
		"sleeping": _sleeping,
		"sleep_hours_left": _sleep_hours_left,
		"carried_items": carried_items,
	}


func restore_saved_runtime(state: Dictionary) -> void:
	sleep = clampf(float(state.get("sleep", 1.0)), 0.0, 1.0)
	_sleeping = bool(state.get("sleeping", false))
	_sleep_hours_left = maxf(float(state.get("sleep_hours_left", 0.0)), 0.0)
	_set_sleep_indicator_visible(_sleeping)   # a dwarf saved mid-nap restores with its 💤
	current_task_id = -1
	_task_phase = TaskPhase.NONE
	stop_walking()
	_reset_part_offsets()


## Slow, deep breathing with a drooped head — read as asleep at RTS zoom.
## Transform offsets only (doc 41: no AnimationPlayer).
func _sleep_bob() -> void:
	if _body == null:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0 + _bob_phase
	var breathe := sin(t * 0.9) * 0.030
	_body.position.y = breathe
	if _head != null:
		_head.position.y = breathe * 1.2 - 0.08
		_head.rotation.x = 0.35
	if _hand_l != null:
		_hand_l.position.y = breathe * 0.5
	if _hand_r != null:
		_hand_r.position.y = breathe * 0.5


# ── DEV interruption helpers (doc 16 Phase 5 — Dwarves window buttons) ────────

## Instant deterministic interruption: force-release the current task with
## reason PLAYER and return to the idle pool immediately. Returns false if
## there was nothing to interrupt.
func dev_force_interrupt() -> bool:
	if current_task_id < 0:
		return false
	_finish_zone_state()
	_finish_haul_state()
	_finish_fetch_state()
	_finish_uninstall_state()
	_task_phase = TaskPhase.NONE
	current_task_id = -1
	_exec_timer = 0.0
	stop_walking()
	_reset_part_offsets()
	TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PLAYER)
	return true


## Drops the sleep stat to the threshold so the ORGANIC interrupt path fires on
## the next frame — tests release + sleep + wake + resume without the ~4-minute
## real-time drain. Returns false if the dwarf is already asleep.
func dev_make_tired() -> bool:
	if _sleeping:
		return false
	sleep = SLEEP_THRESHOLD
	return true


# ── Zone-lease executor (doc 16 §2.7 worker loop) ─────────────────────────────

func _zone_source() -> RefCounted:
	if _zone_id < 0:
		return null
	return TaskManager.get_work_source(_zone_id) as RefCounted


## Step 1 of the worker loop: pull the nearest pullable block. Nothing to
## pull -> the lease completes early (other workers finish the zone) or the
## zone is done — either way this dwarf is finished here.
func _zone_pull_next() -> void:
	if current_task_id < 0:
		return   # cancelled out from under us mid-loop
	var source := _zone_source()
	if source == null:
		_finish_zone_state()
		current_task_id = -1
		TaskManager.fail_dwarf_task(dwarf_id, "zone gone")
		return
	var pull: Dictionary = source.call("reserve_next", dwarf_id, current_cell(), _pull_exclude)
	if pull.is_empty():
		_finish_zone_state()
		current_task_id = -1
		TaskManager.complete_dwarf_task(dwarf_id)
		return
	_zone_block = pull["block"]
	_zone_stand_cells = pull["stand_cells"]
	_stand_index = 0
	_zone_try_stand()


## Step 2: path to a stand cell (nearest first). All unpathable -> unreserve,
## blacklist the block, try the next; 3 failed blocks -> release the lease
## with backoff (§2.7 step 2).
func _zone_try_stand() -> void:
	while _stand_index < _zone_stand_cells.size():
		var stand := _zone_stand_cells[_stand_index]
		_stand_index += 1
		if stand == current_cell():
			_begin_swinging()
			return
		if walk_to(stand):
			_task_phase = TaskPhase.ZONE_MOVING
			return
	# No stand cell pathable for this block.
	var source := _zone_source()
	if source != null:
		source.call("unreserve", dwarf_id)
	_pull_exclude[_zone_block] = true
	_pull_failures += 1
	if _pull_failures >= ZONE_PULL_FAILURE_LIMIT:
		_finish_zone_state()
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)
	else:
		_zone_pull_next()


## Step 3: swing timer = (base × hardness / speed) ÷ durability per swing
## (doc 43 block time, doc 16 durability-per-swing). Partial progress is
## DISCARDED on any interruption — the block keeps full durability (§2.8).
func _begin_swinging() -> void:
	var source := _zone_source()
	if source == null:
		_zone_pull_next()   # routes to fail via null source
		return
	var work: Dictionary = source.call("get_block_work", dwarf_id)
	if work.is_empty():
		# Reservation lost or block no longer solid — pull something else.
		source.call("unreserve", dwarf_id)
		_zone_pull_next()
		return
	_swings_left = int(work["swings"])
	_swing_time = float(work["swing_time"]) / MINING_SPEED_MULT
	_swing_timer = _swing_time
	_task_phase = TaskPhase.ZONE_SWINGING
	_face_cell(_zone_block)


func _process_swinging(delta: float) -> void:
	_swing_timer -= delta
	_work_bob()
	if _swing_timer > 0.0:
		return
	_swings_left -= 1
	if _swings_left > 0:
		_swing_timer = _swing_time
		return
	# Step 4: the block falls. commit_mined routes the world mutation through
	# the controller (bedrock re-guard, WorldData void, renderer promotion,
	# drops, X0) and marks zone progress.
	_task_phase = TaskPhase.NONE
	_reset_part_offsets()
	var source := _zone_source()
	var committed := source != null and bool(source.call("commit_mined", dwarf_id))
	_snap_to_floor()
	if current_task_id < 0:
		_finish_zone_state()
		return   # task ended during commit (zone destroyed / cancelled)
	if committed:
		_pull_failures = 0
		_pull_exclude.clear()
	_zone_pull_next()


func _finish_zone_state() -> void:
	_zone_id = -1
	_zone_block = Vector3i(-1, -1, -1)
	_zone_stand_cells = []
	_stand_index = 0
	_swings_left = 0
	_swing_timer = 0.0
	_pull_failures = 0
	_pull_exclude.clear()
	if _task_phase == TaskPhase.ZONE_MOVING or _task_phase == TaskPhase.ZONE_SWINGING:
		_task_phase = TaskPhase.NONE
		_reset_part_offsets()


## After mining the block under your own feet, the floor is gone — settle
## onto the first walkable floor below (visual position only; the nav grid
## already knows the truth via chunk invalidation).
func _snap_to_floor() -> void:
	var cell := current_cell()
	if NavGrid.is_walkable(cell):
		return
	for k in range(1, 5):
		var below := Vector3i(cell.x, cell.y - k, cell.z)
		if NavGrid.is_walkable(below):
			global_position.y = float(below.y + 1)
			return


## Mining swing: hands chop alternately, body leans into the work. Transform
## offsets only (doc 41 — no AnimationPlayer).
func _work_bob() -> void:
	if _swing_time <= 0.0:
		return
	var p := clampf(1.0 - _swing_timer / _swing_time, 0.0, 1.0)
	var arc := sin(p * PI)
	if _hand_r != null:
		_hand_r.position.y = arc * 0.22
		_hand_r.position.z = arc * 0.14
	if _hand_l != null:
		_hand_l.position.y = arc * 0.06
	if _body != null:
		_body.position.y = arc * 0.03
	if _head != null:
		_head.position.y = arc * 0.05
		_head.rotation.x = arc * 0.12


func _face_cell(cell: Vector3i) -> void:
	var flat := Vector2(
		float(cell.x) + 0.5 - global_position.x,
		float(cell.z) + 0.5 - global_position.z)
	if flat.length_squared() > 0.0001:
		# +Z faces forward for dwarf part GLBs (see _follow_path note).
		rotation.y = atan2(flat.x, flat.y)


# ── HAUL-lease executor (doc 18 §2.3 worker loop) ─────────────────────────────

func _haul_source() -> RefCounted:
	if _haul_source_id < 0:
		return null
	return TaskManager.get_work_source(_haul_source_id) as RefCounted


## Step 1: pull a BUNDLE (main + nearby extras, each with a reserved deposit
## cell — the pouch). Nothing to pull -> the lease completes early.
func _haul_pull_next() -> void:
	if current_task_id < 0:
		return   # cancelled out from under us mid-loop
	var source := _haul_source()
	if source == null:
		_finish_haul_state()
		current_task_id = -1
		TaskManager.fail_dwarf_task(dwarf_id, "stockpile zone gone")
		return
	var pull: Dictionary = source.call("reserve_haul", dwarf_id, current_cell(), _haul_exclude)
	if pull.is_empty():
		_finish_haul_state()
		current_task_id = -1
		TaskManager.complete_dwarf_task(dwarf_id)
		return
	_haul_items = pull["items"]
	_haul_index = 0
	_haul_deposit = pull["deposit_target"]
	_carry_speed_mult = float(pull.get("carry_mult", 1.0))
	_haul_walk_current()


## Step 2: walk to the next bundle item; past the end of the bundle, head to
## the zone with whatever is in the pouch.
func _haul_walk_current() -> void:
	if current_task_id < 0:
		return
	if _haul_index >= _haul_items.size():
		# Bundle exhausted. Carrying something -> deliver; nothing at all ->
		# the whole round failed (every item skipped).
		if _carried_entries.is_empty():
			_haul_cancel_pull()
			_haul_count_failure()
		elif walk_to(_haul_deposit):
			_task_phase = TaskPhase.HAUL_TO_ZONE
		else:
			_drop_carried_at_feet()
			_haul_cancel_pull()
			_haul_count_failure()
		return
	var item := _haul_items[_haul_index]
	if item == null or not is_instance_valid(item):
		_haul_skip_current()
		return
	var stand := _item_stand_cell(item)
	if stand == current_cell():
		_haul_pickup_current()
		return
	if walk_to(stand):
		_task_phase = TaskPhase.HAUL_TO_ITEM
	else:
		_haul_skip_current()


## Step 3: pocket the current bundle item — the node joins the carried stack
## at chest height. Then on to the next item (or the zone).
func _haul_pickup_current() -> void:
	var source := _haul_source()
	if source == null:
		_finish_haul_state()
		current_task_id = -1
		TaskManager.fail_dwarf_task(dwarf_id, "stockpile zone gone")
		return
	var node: Node3D = source.call("take_item", dwarf_id, _haul_index)
	if node == null:
		_haul_skip_current()   # item vanished / raced — bundle continues
		return
	var key := String(node.get_meta("item_key", ""))
	_carried_entries.append([node, key])
	add_child(node)
	node.position = CARRY_OFFSET + Vector3(0.0, CARRY_STACK_STEP * float(_carried_entries.size() - 1), 0.0)
	node.rotation = Vector3.ZERO
	_haul_index += 1
	_haul_walk_current()


## An unreachable/vanished bundle item: blacklist it, free its reservations,
## move on. Skips never count as round failures by themselves — only an
## entirely empty-handed round does (_haul_walk_current end branch).
func _haul_skip_current() -> void:
	var source := _haul_source()
	if _haul_index < _haul_items.size():
		var item := _haul_items[_haul_index]
		if item != null and is_instance_valid(item):
			_haul_exclude[item] = true
		if source != null:
			source.call("skip_item", dwarf_id, _haul_index)
	_haul_index += 1
	_haul_walk_current()


## Step 4: multi-deposit — every pouch item lands on its own reserved cell.
func _haul_deposit_now() -> void:
	var source := _haul_source()
	var committed := false
	if source != null and not _carried_entries.is_empty():
		committed = bool(source.call("commit_haul", dwarf_id, _carried_entries))
	if committed:
		_carried_entries = []   # the zone/drop manager owns the nodes now
		_carry_speed_mult = 1.0
		_haul_failures = 0
		_haul_exclude.clear()
		_haul_pull_next()
	else:
		_drop_carried_at_feet()
		_haul_cancel_pull()
		_haul_count_failure()


## Frees this round's remaining reservations (idempotent — the zone's
## task_released route may have freed them already).
func _haul_cancel_pull() -> void:
	var source := _haul_source()
	if source != null:
		source.call("cancel_haul", dwarf_id)
	_haul_items = []
	_haul_index = 0
	_haul_deposit = Vector3i(-1, -1, -1)
	_carry_speed_mult = 1.0


## The FLOOR cell a dwarf stands on to pick up a drop (mirrors
## ItemDropManager.item_floor_cell — drops rest on their floor's top face).
func _item_stand_cell(node: Node3D) -> Vector3i:
	return Vector3i(
		floori(node.position.x),
		int(round(node.position.y)) - 1,
		floori(node.position.z))


func _haul_count_failure() -> void:
	if current_task_id < 0:
		return
	_haul_failures += 1
	if _haul_failures >= HAUL_PULL_FAILURE_LIMIT:
		_finish_haul_state()
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)
	else:
		_haul_pull_next()


## Hard Rule 12: everything carried goes back to the world as loose drops at
## the dwarf's feet — never destroyed, never stuck on the agent.
func _drop_carried_at_feet() -> void:
	if _carried_entries.is_empty():
		return
	var manager := get_tree().get_first_node_in_group("item_drop_manager")
	for entry: Array in _carried_entries:
		var node: Node3D = entry[0]
		if node == null or not is_instance_valid(node):
			continue
		if manager != null and manager.has_method("drop_loose"):
			manager.call("drop_loose", node, current_cell())
		else:
			node.queue_free()   # last resort — should never happen in a live scene
	_carried_entries = []
	_carry_speed_mult = 1.0


## Interrupt/abort teardown (mirrors _finish_zone_state): drop the pouch,
## free reservations, clear the loop state. Always cheap, always legal.
func _finish_haul_state() -> void:
	if _haul_source_id < 0 and _carried_entries.is_empty():
		return
	_drop_carried_at_feet()
	_haul_cancel_pull()
	_haul_source_id = -1
	_haul_failures = 0
	_haul_exclude.clear()
	if _task_phase == TaskPhase.HAUL_TO_ITEM or _task_phase == TaskPhase.HAUL_TO_ZONE:
		_task_phase = TaskPhase.NONE


# ── FETCH_BUILD / UNINSTALL executors (doc 19 §3.3/§3.4) ─────────────────────

func _furniture_time(key: String) -> float:
	var config: Dictionary = TaskManager.get_config_section("furniture")
	return float(config.get(key, 2.0))


func _fetch_source() -> RefCounted:
	if _fetch_source_id < 0:
		return null
	return TaskManager.get_work_source(_fetch_source_id) as RefCounted


func _uninstall_source() -> RefCounted:
	if _uninstall_source_id < 0:
		return null
	return TaskManager.get_work_source(_uninstall_source_id) as RefCounted


## FETCH step 1: claim an item (loose first, else a storage withdraw).
## Nothing available -> the lease completes early and re-posts on the next
## item wake (the haul precedent).
func _fetch_begin() -> void:
	var source := _fetch_source()
	if source == null:
		_finish_fetch_state()
		current_task_id = -1
		TaskManager.fail_dwarf_task(dwarf_id, "furniture ghost gone")
		return
	var pull: Dictionary = source.call("reserve_fetch", dwarf_id, current_cell())
	if pull.is_empty():
		_finish_fetch_state()
		current_task_id = -1
		TaskManager.complete_dwarf_task(dwarf_id)
		return
	_fetch_item = pull["item"]
	_fetch_picked_up = false
	_fetch_heavy = bool(pull.get("heavy", false))
	if _fetch_item == null or not is_instance_valid(_fetch_item):
		_fetch_fail_release()
		return
	var stand := _item_stand_cell(_fetch_item)
	if stand == current_cell():
		_fetch_pickup()
	elif walk_to(stand):
		_task_phase = TaskPhase.FETCH_TO_ITEM
	else:
		_fetch_fail_release()


## FETCH step 2: pocket the item and head for the ghost.
func _fetch_pickup() -> void:
	var source := _fetch_source()
	if source == null or _fetch_item == null or not is_instance_valid(_fetch_item):
		_fetch_fail_release()
		return
	var manager := get_tree().get_first_node_in_group("item_drop_manager")
	if manager == null:
		_fetch_fail_release()
		return
	var key := String(manager.call("take", _fetch_item))
	if key.is_empty():
		_fetch_fail_release()   # vanished / raced
		return
	_fetch_picked_up = true
	source.call("notify_picked_up", dwarf_id)
	if _fetch_heavy:
		var hauling: Dictionary = TaskManager.get_config_section("hauling")
		_carry_speed_mult = float(hauling.get("carry_speed_mult_heavy", 0.7))
	_carried_entries.append([_fetch_item, key])
	add_child(_fetch_item)
	_fetch_item.position = CARRY_OFFSET
	_fetch_item.rotation = Vector3.ZERO
	var target: Vector3i = source.call("nearest_stand_target", current_cell())
	if target.x < 0:
		_fetch_fail_release()   # footprint has no walkable neighbour right now
		return
	if target == current_cell():
		_task_phase = TaskPhase.FETCH_WORKING
		_exec_timer = _furniture_time("build_time_s")
	elif walk_to(target):
		_task_phase = TaskPhase.FETCH_TO_GHOST
	else:
		_fetch_fail_release()


## FETCH step 4: the build swing finished — the carried item BECOMES the
## installed piece (node freed, controller instances the solid form).
func _fetch_complete() -> void:
	_task_phase = TaskPhase.NONE
	var source := _fetch_source()
	if source == null:
		_fetch_fail_release()
		return
	# Consume the carried item: it is the furniture now, not a drop.
	if _fetch_item != null and is_instance_valid(_fetch_item):
		_carried_entries = _carried_entries.filter(
			func(entry: Array) -> bool: return entry[0] != _fetch_item)
		_fetch_item.queue_free()
	_fetch_item = null
	_carry_speed_mult = 1.0
	source.call("complete_build", dwarf_id)
	_fetch_source_id = -1
	_fetch_picked_up = false
	var finished_id := current_task_id
	current_task_id = -1
	if finished_id >= 0:
		TaskManager.complete_dwarf_task(dwarf_id)


## Any fetch failure: Rule 12 teardown + release with backoff.
func _fetch_fail_release() -> void:
	_finish_fetch_state()
	if current_task_id < 0:
		return
	current_task_id = -1
	TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)


## Interrupt/abort teardown: a carried item drops at the feet (it re-enters
## the loose index); a merely-reserved item is unreserved via the source.
func _finish_fetch_state() -> void:
	if _fetch_source_id < 0 and _fetch_item == null:
		return
	var source := _fetch_source()
	if source != null:
		source.call("cancel_fetch", dwarf_id)
	_drop_carried_at_feet()   # covers the picked-up case; no-op otherwise
	_fetch_item = null
	_fetch_picked_up = false
	_fetch_source_id = -1
	_carry_speed_mult = 1.0
	if _task_phase == TaskPhase.FETCH_TO_ITEM or _task_phase == TaskPhase.FETCH_TO_GHOST \
			or _task_phase == TaskPhase.FETCH_WORKING:
		_task_phase = TaskPhase.NONE


## UNINSTALL step 1: walk to the piece's stand cell.
func _uninstall_begin() -> void:
	var source := _uninstall_source()
	if source == null:
		_finish_uninstall_state()
		current_task_id = -1
		TaskManager.fail_dwarf_task(dwarf_id, "installed furniture gone")
		return
	var target: Vector3i = source.call("nearest_stand_target", current_cell())
	if target.x < 0:
		_finish_uninstall_state()
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)
		return
	if target == current_cell():
		_task_phase = TaskPhase.UNINSTALL_WORKING
		_exec_timer = _furniture_time("uninstall_time_s")
	elif walk_to(target):
		_task_phase = TaskPhase.UNINSTALL_MOVING
	else:
		_finish_uninstall_state()
		current_task_id = -1
		TaskManager.release_dwarf_task(dwarf_id, Task.ReleaseReason.PATH_INVALID)


## UNINSTALL step 2: teardown swing finished.
func _uninstall_complete() -> void:
	_task_phase = TaskPhase.NONE
	var source := _uninstall_source()
	_uninstall_source_id = -1
	if source != null:
		source.call("complete_uninstall", dwarf_id)
	var finished_id := current_task_id
	current_task_id = -1
	if finished_id >= 0:
		TaskManager.complete_dwarf_task(dwarf_id)


## Interrupt teardown: the piece stays installed, the 📤 flag stays set —
## the lease returns to PENDING and another dwarf finishes the job.
func _finish_uninstall_state() -> void:
	_uninstall_source_id = -1
	if _task_phase == TaskPhase.UNINSTALL_MOVING or _task_phase == TaskPhase.UNINSTALL_WORKING:
		_task_phase = TaskPhase.NONE


# ── Movement (doc 16 step 3b) ─────────────────────────────────────────────────

## Current FLOOR cell (the block under the feet). Standing height is
## floor_y + 1, so the floor is one below the rounded position.
func current_cell() -> Vector3i:
	return Vector3i(
		floori(global_position.x),
		int(round(global_position.y)) - 1,
		floori(global_position.z))


## Orders a walk to a goal floor cell. Returns true if a path was found and
## the walk began; emits walk_finished(success) when it ends either way.
func walk_to(goal_cell: Vector3i) -> bool:
	var path := NavGrid.find_path(current_cell(), goal_cell)
	if path.is_empty():
		walk_finished.emit(false)
		return false
	_move_path = path
	_move_index = 0
	_walk_cycle = 0.0
	_shortcut_timer = 0.0   # string-pull immediately on the first frame
	return true


func stop_walking() -> void:
	if _move_path.is_empty():
		return
	_clear_path()
	_reset_part_offsets()
	walk_finished.emit(false)


## NOTE: never .clear() _move_path — NavGrid hands out its CACHED array, so
## clearing in place would corrupt the cache. Always swap in a fresh one.
func _clear_path() -> void:
	var fresh: Array[Vector3i] = []
	_move_path = fresh
	_move_index = 0


## String-pulling (the zigzag fix): advance the target waypoint to the FURTHEST
## same-level path cell reachable in a straight walkable line from here, so the
## agent walks at any angle between obstacles instead of tracing 45-degree grid
## stairs. The grid path remains the correctness authority; elevation changes
## stay waypoint-exact (no shortcutting across terrace steps).
const SHORTCUT_LOOKAHEAD := 24   # cells scanned ahead per check (bounds cost)

func _advance_shortcut() -> void:
	var here := current_cell()
	var best := _move_index
	var limit := mini(_move_path.size() - 1, _move_index + SHORTCUT_LOOKAHEAD)
	for j in range(_move_index + 1, limit + 1):
		if _move_path[j].y != here.y:
			break   # elevation change ahead — take those steps exactly
		if NavGrid.line_walkable_flat(here, _move_path[j]):
			best = j
		else:
			break
	_move_index = best


func is_walking() -> bool:
	return not _move_path.is_empty()


func _follow_path(delta: float) -> void:
	_shortcut_timer -= delta
	if _shortcut_timer <= 0.0:
		_advance_shortcut()
		_shortcut_timer = SHORTCUT_INTERVAL
	var cell := _move_path[_move_index]
	var target := Vector3(float(cell.x) + 0.5, float(cell.y + 1), float(cell.z) + 0.5)
	var to_target := target - global_position
	var distance := to_target.length()
	# Heavy carried items slow the walk (doc 18 §2.3 / resources.json contract).
	var step := walk_speed * _carry_speed_mult * delta

	# Face travel direction (XZ only). The dwarf part GLBs are authored with
	# the FACE on the +Z side (generate_dwarf_glb.py FACE_Z), so local +Z —
	# not Godot's usual -Z — must point along travel. Smooth turn, no snap.
	var flat := Vector2(to_target.x, to_target.z)
	if flat.length_squared() > 0.0001:
		var target_yaw := atan2(flat.x, flat.y)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 10.0))

	if distance <= step:
		global_position = target
		_move_index += 1
		if _move_index >= _move_path.size():
			_clear_path()
			_reset_part_offsets()
			walk_finished.emit(true)
		return
	global_position += to_target / distance * step
	_walk_bob(step)


## Distance-driven gait (doc 17 §2). One full cycle = two steps (left + right),
## so the body covers stride_length per HALF cycle. Each foot alternates a
## SWING phase (arcs forward with lift) and a PLANT phase (holds flat while
## sliding backward relative to the body — i.e. world-fixed, faking a real
## footstep). Hands counter-swing at half amplitude; the body bounces once per
## step and leans gently into travel. Transform offsets only (doc 41 contract:
## no AnimationPlayer, no skeleton).
func _walk_bob(moved: float) -> void:
	_walk_cycle = fposmod(_walk_cycle + moved / maxf(stride_length * 2.0, 0.01), 1.0)
	var amp := stride_length * 0.5   # foot swing amplitude; matches ground covered
	# Feet: right foot leads the cycle, left is half a cycle out of phase.
	_pose_foot(_foot_r, _walk_cycle, amp)
	_pose_foot(_foot_l, fposmod(_walk_cycle + 0.5, 1.0), amp)
	# Bounce peaks once per step (twice per cycle), at each foot plant.
	var bounce := absf(sin(_walk_cycle * TAU)) * 0.04
	var lean := deg_to_rad(walk_lean_deg)
	if _body != null:
		_body.position.y = bounce
		_body.rotation.x = lean
	if _head != null:
		_head.position.y = bounce * 1.2
		_head.rotation.x = lean * 0.6
	# Hands counter-swing smoothly at half the foot amplitude (they never plant).
	var hand_swing := sin(_walk_cycle * TAU) * amp * 0.5
	if _hand_l != null:
		_hand_l.position.z = hand_swing
		_hand_l.position.y = bounce
	if _hand_r != null:
		_hand_r.position.z = -hand_swing
		_hand_r.position.y = bounce


## One foot's pose at cycle phase q ∈ [0, 1): first half = SWING (back → front
## along local +Z with a sine lift arc), second half = PLANT (front → back,
## flat on the ground). Local +Z is the dwarf's facing (GLB authoring frame).
func _pose_foot(foot: Node3D, q: float, amp: float) -> void:
	if foot == null:
		return
	if q < 0.5:
		var s := q / 0.5                                   # 0 → 1 across the swing
		foot.position.z = lerpf(-amp, amp, s)
		foot.position.y = sin(s * PI) * 0.10               # lift arc
	else:
		var s := (q - 0.5) / 0.5                           # 0 → 1 across the plant
		foot.position.z = lerpf(amp, -amp, s)              # world-fixed vs moving body
		foot.position.y = 0.0


func _reset_part_offsets() -> void:
	for part in [_body, _head, _hand_l, _hand_r, _foot_l, _foot_r]:
		if part != null:
			part.position = Vector3.ZERO
			part.rotation = Vector3.ZERO


# ── Assembly (doc 41b scene hierarchy) ────────────────────────────────────────

func _build_parts() -> void:
	if appearance == null:
		push_error("DwarfAgent %d: setup without appearance data." % dwarf_id)
		return

	_head = _attach(self, "MeshHead", DwarfAssets.heads.get(appearance.age_tier))
	_body = _attach(self, "MeshBody", DwarfAssets.body)
	_hand_l = _attach(self, "MeshHandL", DwarfAssets.hand)
	_hand_r = _attach(self, "MeshHandR", DwarfAssets.hand, true)
	_foot_l = _attach(self, "MeshFootL", DwarfAssets.foot)
	_foot_r = _attach(self, "MeshFootR", DwarfAssets.foot, true)

	if _head != null:
		_attach(_head, "MeshEyes", DwarfAssets.eyes)
		var hair := DwarfAssets.hair_for(appearance)
		if hair != null:
			_attach(_head, "MeshHair", hair)
		if gender == "male" and appearance.beard_style != "":
			var beard: PackedScene = DwarfAssets.beards.get(appearance.beard_style)
			if beard != null:
				_attach(_head, "MeshBeard", beard)
		var brows := DwarfAssets.brows_for(appearance)
		if brows != null:
			_attach(_head, "MeshBrows", brows)
		# Scar is PORTRAIT-ONLY (doc 41b §Map Mesh vs Portrait) — not added here.


## Instantiates a part GLB under `parent` at identity (shared authoring frame).
## mirror=true flips across X for the right-side hand/foot (doc 41b).
func _attach(parent: Node3D, part_name: String, packed: PackedScene, mirror: bool = false) -> Node3D:
	if packed == null:
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("DwarfAgent: part %s did not instance as Node3D." % part_name)
		return null
	instance.name = part_name
	if mirror:
		instance.scale = Vector3(-1.0, 1.0, 1.0)
	parent.add_child(instance)
	return instance


func _build_collision() -> void:
	# Logical 1x1x3-block box (doc 41 §Visual Mesh Profile) — NOT the 3.3-block
	# visual AABB. Mask 0: nothing physically collides yet (movement is direct
	# until the nav phase decides its sweep model).
	collision_layer = COLLISION_LAYER_DWARF
	collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "LogicalBox"
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, LOGICAL_HEIGHT, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, LOGICAL_HEIGHT * 0.5, 0.0)
	add_child(shape)


func _build_name_label() -> void:
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = dwarf_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.96, 0.86)
	label.position = Vector3(0.0, 4.0, 0.0)
	label.visible = false   # OFF by default (Alen, 2026-06-10) — DEV toggle in the Dwarves window
	add_child(label)


## 💤 sleep indicator (Alen, 2026-08-07 — "the dwarves are just stuck doing
## nothing" turned out to be the whole squad napping; make sleep readable at
## a glance). Same billboard conventions as the name tag, but ALWAYS shown
## while sleeping — independent of the DEV name-tag toggle, because it is
## gameplay information, not debug info. Emoji renders via the same system
## font fallback the dock's emoji buttons already rely on (doc 23).
func _build_sleep_indicator() -> void:
	var label := Label3D.new()
	label.name = "SleepIndicator"
	label.text = "💤"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 44
	label.outline_size = 6
	label.position = Vector3(0.35, 3.7, 0.0)   # beside the drooped head, below the name tag
	label.visible = false
	add_child(label)


func _set_sleep_indicator_visible(show_indicator: bool) -> void:
	var label := get_node_or_null("SleepIndicator")
	if label != null:
		(label as Label3D).visible = show_indicator


func set_name_label_visible(show_label: bool) -> void:
	var label := get_node_or_null("NameLabel")
	if label != null:
		(label as Label3D).visible = show_label


# ── Tinting (doc 41b §Runtime Tinting — neutral palettes x albedo tint) ───────

func _apply_tints() -> void:
	var skin: Color = DwarfAssets.SKIN_TONES.get(appearance.skin_tone, Color.WHITE)
	var hair: Color = DwarfAssets.HAIR_COLORS.get(appearance.hair_color, Color.WHITE)
	var eye: Color = DwarfAssets.EYE_COLORS.get(appearance.eye_color, Color.WHITE)

	# Body and feet are BAKED since the doc-17 regen (clothed tunic torso,
	# leather boots) — tint WHITE to keep the standard material while leaving
	# the baked colours alone. Skin tint applies to head and hands only.
	_tint(_body, Color.WHITE)
	_tint(_hand_l, skin)
	_tint(_hand_r, skin)
	_tint(_foot_l, Color.WHITE)
	_tint(_foot_r, Color.WHITE)
	if _head != null:
		# The head mesh itself is skin; children carry their own tints.
		_tint(_head, skin, false)
		_tint(_head.get_node_or_null("MeshEyes"), eye)
		_tint(_head.get_node_or_null("MeshHair"), hair)
		_tint(_head.get_node_or_null("MeshBeard"), hair)   # beard follows hair colour (doc 41b)
		_tint(_head.get_node_or_null("MeshBrows"), hair)


## Applies a tint material to every MeshInstance3D under `node`. Parts are
## authored near-white with baked vertex-colour shading, so albedo_color
## multiplication = the doc-41b tint shader without a custom shader. Material
## settings mirror the project standard (lit per-pixel, double-sided).
func _tint(node: Node, color: Color, recurse_children: bool = true) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = color
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		# When tinting the head WITHOUT recursing into part children (they get
		# their own colours), still walk non-part nodes (the GLB's inner scene).
		if not recurse_children and child is Node3D \
				and String(child.name).begins_with("Mesh"):
			continue
		_tint(child, color, recurse_children)


# ── Procedural idle bob (doc 41: transform offsets, no AnimationPlayer) ───────

func _idle_bob() -> void:
	if _body == null:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0 + _bob_phase
	var breathe := sin(t * 2.2) * 0.018
	var sway := sin(t * 1.1) * 0.012
	_body.position.y = breathe
	if _head != null:
		_head.position.y = breathe * 1.4
		_head.rotation.y = sway * 0.6
	if _hand_l != null:
		_hand_l.position.y = breathe + sin(t * 2.2 + 0.9) * 0.010
	if _hand_r != null:
		_hand_r.position.y = breathe + sin(t * 2.2 + 2.1) * 0.010
	# Feet stay planted while idle; they animate when walking (nav phase).


# ── Slice culling hook (doc 11 Phase 5 pattern — DwarfDirector drives this) ───

func apply_slice(slice_y: int) -> void:
	visible = int(floor(global_position.y)) <= slice_y
