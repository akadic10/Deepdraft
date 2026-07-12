extends Node

## Colony storage coordinator (doc 18 §2.2 / Phase 3). Autoload, registered
## after InteriorTracker (needs TaskManager for work-source registration and
## config). Owns the zone registry and the aggregate view; the designation
## controller owns designation/overlay/window, ItemDropManager owns the item
## nodes and resources.json.
##
## LEASE WAKE SOURCES (event-driven, doc 16 §2.5 discipline — never a frame
## scan): drop spawned (new loose item), zone registered, HAUL task left the
## system (completed/released/cancelled/failed). Wakes are throttled to one
## lease-posting pass per LEASE_REFRESH_S (the mining stalled-zone throttle
## pattern) and iterate zones only — zones themselves cap the work.
##
## SOURCE-ID NAMESPACE: TaskManager work-source keys are shared with mining
## zones (both count from 1), so stockpile sources live at SOURCE_ID_BASE +
## zone_id. Recorded tech debt: a TaskManager-owned source-id allocator is
## the clean fix when a third work-source system appears (doc 18 build log).

signal stockpile_changed(item_key: String, delta: int)

const SOURCE_ID_BASE := 1_000_000
const LEASE_REFRESH_S := 0.25

var _zones: Dictionary = {}          # source_id -> StockpileZoneComponent
var _totals: Dictionary = {}         # item_key -> stored count (aggregate)
var _max_haulers: int = 2
var _carry_mult_heavy: float = 0.7
var _pouch_capacity: int = 4
var _pouch_radius: int = 8

var _drop_manager: Node3D = null
var _drop_manager_connected: bool = false
var _lease_dirty: bool = false
var _lease_accum: float = 0.0


func _ready() -> void:
	var hauling: Dictionary = TaskManager.get_config_section("hauling")
	_max_haulers = int(hauling.get("max_haulers_per_zone", _max_haulers))
	_carry_mult_heavy = float(hauling.get("carry_speed_mult_heavy", _carry_mult_heavy))
	_pouch_capacity = int(hauling.get("pouch_capacity", _pouch_capacity))
	_pouch_radius = int(hauling.get("pouch_bundle_radius", _pouch_radius))
	TaskManager.task_completed.connect(_on_task_completed)
	TaskManager.task_released.connect(_on_task_released)
	TaskManager.task_cancelled.connect(_on_task_gone_signal)
	TaskManager.task_failed.connect(_on_task_failed)
	print("StockpileManager: ready (max haulers/zone %d, heavy carry ×%.2f)." % [
		_max_haulers, _carry_mult_heavy])


func _process(delta: float) -> void:
	# Lazy drop-manager hookup: the scene node may enter the tree after this
	# autoload's _ready. Connect once, then this branch never runs again.
	if not _drop_manager_connected:
		_drop_manager = get_tree().get_first_node_in_group("item_drop_manager") as Node3D
		if _drop_manager != null:
			_drop_manager.connect("drop_spawned", _on_drop_spawned)
			_drop_manager_connected = true
			# Backfill zones registered before the scene node entered the tree.
			for source_id: int in _zones:
				(_zones[source_id] as StockpileZoneComponent).drop_manager = _drop_manager
	if not _lease_dirty:
		return
	_lease_accum += delta
	if _lease_accum < LEASE_REFRESH_S:
		return
	_lease_accum = 0.0
	_lease_dirty = false
	for source_id: int in _zones:
		(_zones[source_id] as StockpileZoneComponent).update_leases()


# ── Zone registry (called by StockpileDesignationController) ──────────────────

func register_zone(zone: StockpileZoneComponent) -> void:
	zone.source_id = SOURCE_ID_BASE + zone.zone_id
	zone.max_haulers = _max_haulers
	zone.carry_speed_mult_heavy = _carry_mult_heavy
	zone.pouch_capacity = _pouch_capacity
	zone.pouch_bundle_radius = _pouch_radius
	zone.drop_manager = _drop_manager
	zone.changed_callback = _on_zone_deposit
	_zones[zone.source_id] = zone
	TaskManager.register_work_source(zone.source_id, zone)
	_mark_dirty()


## Zone removed by the player: cancel its leases, free its work-source slot,
## and return its stored items to the world as loose drops (doc 18 §2.4 —
## stacked counts respawn so nothing is lost).
func deregister_zone(zone: StockpileZoneComponent) -> void:
	if not _zones.has(zone.source_id):
		return
	_zones.erase(zone.source_id)
	TaskManager.cancel_source_tasks(zone.source_id)
	TaskManager.unregister_work_source(zone.source_id)
	for cell: Vector3i in zone.cell_stacks:
		var stack: Dictionary = zone.cell_stacks[cell]
		_apply_total(String(stack.get("item", "")), -int(stack.get("count", 0)))
	if _drop_manager != null and is_instance_valid(_drop_manager):
		_drop_manager.call("release_stored_cells", zone.cell_stacks)
	_mark_dirty()


# ── Aggregates (doc 23 API surface — status-bar counters consume this later) ──

func get_total(item_key: String) -> int:
	return int(_totals.get(item_key, 0))


func get_stats() -> Dictionary:
	var cells: int = 0
	var stored: int = 0
	for source_id: int in _zones:
		var zone: StockpileZoneComponent = _zones[source_id]
		cells += zone.cell_count()
		stored += zone.stored_count()
	return { "zones": _zones.size(), "cells": cells, "stored": stored }


## Fetch withdraw (doc 19 §3.3): pull one stored unit of `item_key` out of
## the zone nearest `near`, reserved for `dwarf_id`. Null if no zone holds
## the item. Containers join this lookup in Phase 4 via the same surface.
func withdraw_item(item_key: String, near: Vector3i, dwarf_id: int) -> Node3D:
	var best_zone: StockpileZoneComponent = null
	var best_dist: int = 0x7FFFFFFF
	for source_id: int in _zones:
		var zone: StockpileZoneComponent = _zones[source_id]
		var has_it := false
		for cell: Vector3i in zone.cell_stacks:
			if String((zone.cell_stacks[cell] as Dictionary).get("item", "")) == item_key:
				has_it = true
				break
		if not has_it:
			continue
		var target := zone.nearest_stand_target(near)
		var d := target - near
		var dist := absi(d.x) + absi(d.y) + absi(d.z)
		if dist < best_dist:
			best_zone = zone
			best_dist = dist
	if best_zone == null:
		return null
	return best_zone.withdraw_nearest(item_key, near, dwarf_id)


# ── Wake plumbing ─────────────────────────────────────────────────────────────

func _mark_dirty() -> void:
	_lease_dirty = true


func _on_drop_spawned(_item_key: String) -> void:
	_mark_dirty()


func _on_zone_deposit(item_key: String, delta: int) -> void:
	_apply_total(item_key, delta)


func _apply_total(item_key: String, delta: int) -> void:
	if item_key.is_empty() or delta == 0:
		return
	_totals[item_key] = int(_totals.get(item_key, 0)) + delta
	stockpile_changed.emit(item_key, delta)


func _route(task: Task, dwarf_id: int) -> void:
	if task.source_id < SOURCE_ID_BASE:
		return
	var zone: StockpileZoneComponent = _zones.get(task.source_id)
	if zone != null:
		zone.on_task_gone(task.id, dwarf_id)
	_mark_dirty()


func _on_task_completed(task: Task) -> void:
	# Clean completion: the dwarf already resolved its pull; free the lease id
	# only (dwarf_id -1 skips the reservation cleanup).
	_route(task, -1)


func _on_task_released(task: Task, dwarf_id: int, _reason: int) -> void:
	# A released lease returns to PENDING — it still counts against
	# max_haulers, so only the dwarf's reservations are freed here.
	if task.source_id < SOURCE_ID_BASE:
		return
	var zone: StockpileZoneComponent = _zones.get(task.source_id)
	if zone != null:
		zone.cancel_haul(dwarf_id)
	_mark_dirty()


func _on_task_gone_signal(task: Task) -> void:
	_route(task, task.assigned_to)


func _on_task_failed(task: Task, _reason: String) -> void:
	_route(task, task.assigned_to)
