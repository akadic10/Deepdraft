class_name Task
extends RefCounted

## One unit of colony work-INTENT (doc 16 §2.2 — refines doc 31's schema).
##
## Tasks are first-class entities owned exclusively by the TaskManager autoload.
## A dwarf holds only a task id (int), never the object — lookups go through
## TaskManager, so a cancelled task can be freed safely while a dwarf still
## remembers its id.
##
## SCALING RULE (doc 16 §2.1): task count is O(intents), not O(blocks). A mining
## zone posts at most MAX_WORKERS zone-LEASE tasks; the per-block work never
## exists as a queued Task object. Do not create per-block tasks — ever.
##
## `priority` stores only the STATIC base value (doc 31 priority table). Dynamic
## colony-state bonuses (+20 BREW when ale is low, ...) are computed once per
## scheduler wake, per TYPE — never written into tasks, so colony-state changes
## never trigger re-sorts.

## FETCH_BUILD / UNINSTALL: the furniture pipeline (doc 19 §3.3/§3.4 — a ghost
## posts ONE fetch-and-build lease; a 📤-flagged piece posts ONE uninstall
## lease). First-class types per SH parity (dedicated placement_task_group).
enum Type { MINE, HAUL, FARM, BREW, BUILD, IDLE, PATROL, FETCH_BUILD, UNINSTALL }   # SMELT/FORGE later (doc 44)
enum Status { PENDING, ASSIGNED, IN_PROGRESS, BLOCKED, COMPLETED, FAILED, CANCELLED }

## Release reasons (doc 16 §2.8) — passed through task_released for logging/AI.
enum ReleaseReason { NEED_INTERRUPT, COMBAT, PLAYER, PATH_INVALID, SOURCE_EMPTY }

var id: int = -1                       # unique, assigned by TaskManager
var type: int = Type.IDLE              # Task.Type
var status: int = Status.PENDING       # Task.Status
var priority: int = 1                  # STATIC base priority (1 lowest – 100 highest)
var target_pos: Vector3i = Vector3i.ZERO   # representative position (zone centroid for leases)
var payload: Dictionary = {}           # type data; MINE lease: { "zone_id": int }
var source_id: int = -1                # owning work source (zone id, workshop id), or -1
var assigned_to: int = -1              # dwarf id, or -1
var created_at: int = 0                # Time.get_ticks_msec()
var retry_at: int = 0                  # msec; BLOCKED until then (scheduler skips, never polls)
var blocked_count: int = 0             # consecutive blocked probes -> backoff + task_unreachable


func _init(p_type: int = Type.IDLE, p_priority: int = 1,
		p_target: Vector3i = Vector3i.ZERO, p_payload: Dictionary = {},
		p_source_id: int = -1) -> void:
	type = p_type
	priority = p_priority
	target_pos = p_target
	payload = p_payload
	source_id = p_source_id
	created_at = Time.get_ticks_msec()


## True when the scheduler may consider this task right now.
func is_available(now_msec: int) -> bool:
	return status == Status.PENDING and now_msec >= retry_at


## Human-readable type name (UI / debug overlay / task log).
static func type_name(t: int) -> String:
	match t:
		Type.MINE:   return "MINE"
		Type.HAUL:   return "HAUL"
		Type.FARM:   return "FARM"
		Type.BREW:   return "BREW"
		Type.BUILD:  return "BUILD"
		Type.IDLE:   return "IDLE"
		Type.PATROL: return "PATROL"
		Type.FETCH_BUILD: return "FETCH_BUILD"
		Type.UNINSTALL:  return "UNINSTALL"
	return "UNKNOWN"
