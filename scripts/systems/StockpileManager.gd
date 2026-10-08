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
var _containers: Dictionary = {}     # source_id -> ContainerStorageComponent (doc 19 Phase 4)
var _totals: Dictionary = {}         # item_key -> stored count (aggregate)
var _max_haulers: int = 2
var _carry_mult_heavy: float = 0.7
var _carry_capacity: int = 4
var _pouch_radius: int = 8

var _drop_manager: Node3D = null
var _drop_manager_connected: bool = false
var _lease_dirty: bool = false
var _lease_accum: float = 0.0
var hauling_revision: int = 0 # invalidates read-only scheduler pickup quotes


func _ready() -> void:
	var hauling: Dictionary = TaskManager.get_config_section("hauling")
	_max_haulers = int(hauling.get("max_haulers_per_zone", _max_haulers))
	_carry_mult_heavy = float(hauling.get("carry_speed_mult_heavy", _carry_mult_heavy))
	_carry_capacity = maxi(1, int(hauling.get("carry_capacity", _carry_capacity)))
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
			_drop_manager.connect("loose_items_changed", _mark_dirty)
			_drop_manager_connected = true
			# Backfill zones registered before the scene node entered the tree.
			for source_id: int in _zones:
				(_zones[source_id] as StockpileZoneComponent).drop_manager = _drop_manager
			for source_id: int in _containers:
				(_containers[source_id] as ContainerStorageComponent).drop_manager = _drop_manager
	if not _lease_dirty:
		return
	_lease_accum += delta
	if _lease_accum < LEASE_REFRESH_S:
		return
	_lease_accum = 0.0
	_lease_dirty = false
	for source_id: int in _zones:
		(_zones[source_id] as StockpileZoneComponent).update_leases()
	for source_id: int in _containers:
		(_containers[source_id] as ContainerStorageComponent).update_leases()


# ── Zone registry (called by StockpileDesignationController) ──────────────────

func register_zone(zone: StockpileZoneComponent) -> void:
	zone.source_id = SOURCE_ID_BASE + zone.zone_id
	zone.max_haulers = _max_haulers
	zone.carry_speed_mult_heavy = _carry_mult_heavy
	zone.carry_capacity = _carry_capacity
	zone.pouch_bundle_radius = _pouch_radius
	zone.drop_manager = _drop_manager
	zone.changed_callback = _on_zone_deposit
	_zones[zone.source_id] = zone
	TaskManager.register_work_source(zone.source_id, zone)
	_mark_dirty()


## Container registered by FurniturePlacementController on install (doc 19
## Phase 4). Source id comes from the caller (TaskManager.allocate_source_id).
func register_container(container: ContainerStorageComponent) -> void:
	container.max_haulers = _max_haulers
	container.carry_speed_mult_heavy = _carry_mult_heavy
	container.carry_capacity = _carry_capacity
	container.pouch_bundle_radius = _pouch_radius
	container.drop_manager = _drop_manager
	container.changed_callback = _on_zone_deposit
	_containers[container.source_id] = container
	TaskManager.register_work_source(container.source_id, container)
	_mark_dirty()


## Container removed (uninstall/DEV): contents are the CALLER's to dump
## (FurniturePlacementController tears down in order); this frees the slots.
func deregister_container(container: ContainerStorageComponent) -> void:
	if not _containers.has(container.source_id):
		return
	TaskManager.cancel_source_tasks(container.source_id)
	container.release_storage_claims()
	_containers.erase(container.source_id)
	TaskManager.unregister_work_source(container.source_id)
	_mark_dirty()


## Zone removed by the player: cancel its leases, free its work-source slot,
## and return its stored items to the world as loose drops (doc 18 §2.4 —
## stacked counts respawn so nothing is lost).
func deregister_zone(zone: StockpileZoneComponent) -> void:
	if not _zones.has(zone.source_id):
		return
	TaskManager.cancel_source_tasks(zone.source_id)
	zone.release_storage_claims()
	_zones.erase(zone.source_id)
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


func get_inventory_totals() -> Dictionary:
	return _totals.duplicate()


## Live storage owners holding a key; callers re-query before every action.
func get_item_locations(item_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone: StockpileZoneComponent in _zones.values():
		var count := 0
		var position := Vector3.ZERO
		for cell: Vector3i in zone.cell_stacks:
			var stack: Dictionary = zone.cell_stacks[cell]
			if String(stack.item) == item_key:
				count += int(stack.count)
				position = Vector3(cell) + Vector3(.5, 1, .5)
		if count > 0:
			result.append({"kind": "stockpile", "owner": zone, "count": count, "position": position})
	for container: ContainerStorageComponent in _containers.values():
		var count := int(container.inventory.get(item_key, 0))
		if count > 0 and is_instance_valid(container.display_parent):
			result.append({"kind": "container", "owner": container, "count": count,
				"position": container.display_parent.global_position, "node": container.display_parent})
	return result


func get_stats() -> Dictionary:
	var cells: int = 0
	var stored: int = 0
	for source_id: int in _zones:
		var zone: StockpileZoneComponent = _zones[source_id]
		cells += zone.cell_count()
		stored += zone.stored_count()
	for source_id: int in _containers:
		stored += (_containers[source_id] as ContainerStorageComponent).stored_count()
	return { "zones": _zones.size(), "cells": cells, "stored": stored, "containers": _containers.size() }


## Scene-reload boundary. Work-source state is transient and TaskManager is
## reset separately; restored zones/containers register themselves afresh.
func reset_runtime_state() -> void:
	if _drop_manager_connected and _drop_manager != null \
			and is_instance_valid(_drop_manager) \
			and _drop_manager.is_connected("drop_spawned", _on_drop_spawned):
		_drop_manager.disconnect("drop_spawned", _on_drop_spawned)
		_drop_manager.disconnect("loose_items_changed", _mark_dirty)
	_zones.clear()
	_containers.clear()
	_totals.clear()
	_drop_manager = null
	_drop_manager_connected = false
	_lease_dirty = false
	_lease_accum = 0.0
	hauling_revision += 1


## Recomputes aggregate counts after all restored storage owners are present.
func rebuild_totals() -> void:
	_totals.clear()
	for source_id: int in _zones:
		var zone: StockpileZoneComponent = _zones[source_id]
		for cell: Vector3i in zone.cell_stacks:
			var stack: Dictionary = zone.cell_stacks[cell]
			var key := String(stack.get("item", ""))
			var count := int(stack.get("count", 0))
			if not key.is_empty() and count > 0:
				_totals[key] = int(_totals.get(key, 0)) + count
	for source_id: int in _containers:
		var container: ContainerStorageComponent = _containers[source_id]
		for key: String in container.inventory:
			var count := int(container.inventory[key])
			if count > 0:
				_totals[key] = int(_totals.get(key, 0)) + count
	_mark_dirty()
	stockpile_changed.emit("", 0)


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
			if int(zone.cell_stacks[cell].count) <= int(zone._outgoing.get(cell, {}).get("count", 0)): continue
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
	if best_zone != null:
		var node := best_zone.withdraw_nearest(item_key, near, dwarf_id)
		if node != null: return node
	# No zone holds it — try containers (doc 19 Phase 4).
	for source_id: int in _containers:
		var container: ContainerStorageComponent = _containers[source_id]
		if int(container.inventory.get(item_key, 0)) > 0:
			var node := container.withdraw_nearest(item_key, near, dwarf_id)
			if node != null: return node
	return null


## Crafting may permit several species. Choose a nearby unclaimed stored unit
## across the allowed keys instead of treating key sorting as a wood preference.
func withdraw_matching_item(keys: Array[String], near: Vector3i, dwarf_id: int) -> Node3D:
	var candidates: Array[Dictionary] = []
	for source: StorageComponent in _zones.values() + _containers.values():
		if source is ContainerStorageComponent and source.suspended: continue
		var entries := source.stored_entries()
		for slot in entries:
			var stack: Dictionary = entries[slot]
			var key := String(stack.item)
			if key not in keys or int(stack.count) <= int(source._outgoing.get(slot,{}).get("count",0)): continue
			var delta := source.slot_cell(slot)-near
			var distance := absi(delta.x)+absi(delta.y)+absi(delta.z)
			candidates.append({"source":source,"slot":slot,"distance":distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
	for candidate in candidates:
		# An unavailable pickup location must not hide other permitted timber.
		var item: Node3D = candidate.source.withdraw_stack(candidate.slot,1,dwarf_id)
		if item != null: return item
	return null


func is_registered(storage: StorageComponent) -> bool:
	return _zones.get(storage.source_id) == storage or _containers.get(storage.source_id) == storage


func storage_rules_changed() -> void:
	_mark_dirty()
	stockpile_changed.emit("", 0)


## Only rejected stored goods may relocate. A claim never changes ownership
## or totals; the source withdraws when the worker physically reaches it.
func relocation_candidates(destination: StorageComponent, near: Vector3i, exclude: Dictionary = {}, limit: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_registered(destination): return result
	for origin: StorageComponent in _zones.values() + _containers.values():
		if origin == destination: continue
		if origin is ContainerStorageComponent and origin.suspended: continue
		for slot in origin.stored_entries():
			if origin._outgoing.has(slot) or exclude.has(origin.relocation_id(slot)): continue
			if exclude.has(origin.slot_cell(slot)): continue
			var stack: Dictionary = origin.stored_entries()[slot]
			var key := String(stack.item)
			if origin.accepts_key(key) or not destination._can_haul_key(key): continue
			var cell := origin.slot_cell(slot)
			var distance := absi(cell.x - near.x) + absi(cell.y - near.y) + absi(cell.z - near.z)
			result.append({"source": origin, "distance": distance,
				"token": {"slot": slot, "item": key, "count": int(stack.count), "active": false}})
			if limit > 0 and result.size() >= limit: return result
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
	return result


func get_outgoing_totals() -> Dictionary:
	var result := {}
	for origin: StorageComponent in _zones.values() + _containers.values():
		for token: Dictionary in origin._outgoing.values():
			result[token.item] = int(result.get(token.item, 0)) + int(token.count)
	return result


## Bounded counterpart to relocation_candidates, used only for worker ranking.
## Source/slot snapshots are transient, contain no claims and never own goods.
func advance_relocation_quote(destination: StorageComponent, near: Vector3i, query: Dictionary, deadline_usec: int, exclude_cells: Dictionary = {}) -> bool:
	if query.is_empty():
		query.merge({"sources": _zones.values() + _containers.values(), "source_index": 0,
			"slots": [], "slot_index": 0, "cell": Vector3i(-1, -1, -1), "distance": 0x7FFFFFFF})
	while int(query.source_index) < query.sources.size():
		if Time.get_ticks_usec() >= deadline_usec: return false
		var origin: StorageComponent = query.sources[query.source_index]
		if origin == destination or not is_registered(origin) or (origin is ContainerStorageComponent and origin.suspended):
			query.source_index += 1
			continue
		if query.slots.is_empty(): query.slots = origin.stored_entries().keys()
		while int(query.slot_index) < query.slots.size():
			if Time.get_ticks_usec() >= deadline_usec: return false
			var slot = query.slots[query.slot_index]
			query.slot_index += 1
			if origin._outgoing.has(slot): continue
			var stack: Dictionary = origin.stored_entries().get(slot, {})
			if stack.is_empty(): continue
			var key := String(stack.item)
			if origin.accepts_key(key) or not destination._can_haul_key(key): continue
			var cell := origin.slot_cell(slot)
			if exclude_cells.has(cell): continue
			var distance := absi(cell.x - near.x) + absi(cell.y - near.y) + absi(cell.z - near.z)
			if distance < int(query.distance):
				query.cell = cell
				query.distance = distance
		query.source_index += 1
		query.slots = []
		query.slot_index = 0
	return true


# ── Wake plumbing ─────────────────────────────────────────────────────────────

func _mark_dirty() -> void:
	_lease_dirty = true
	hauling_revision += 1


func _on_drop_spawned(_item_key: String) -> void:
	_mark_dirty()


func _on_zone_deposit(item_key: String, delta: int) -> void:
	_apply_total(item_key, delta)


func _apply_total(item_key: String, delta: int) -> void:
	if item_key.is_empty() or delta == 0:
		return
	_totals[item_key] = int(_totals.get(item_key, 0)) + delta
	_mark_dirty()
	stockpile_changed.emit(item_key, delta)


func _route(task: Task, dwarf_id: int) -> void:
	if task.source_id < SOURCE_ID_BASE:
		return
	var zone: StockpileZoneComponent = _zones.get(task.source_id)
	if zone != null:
		zone.on_task_gone(task.id, dwarf_id)
	var container: ContainerStorageComponent = _containers.get(task.source_id)
	if container != null:
		container.on_task_gone(task.id, dwarf_id)
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
	var container: ContainerStorageComponent = _containers.get(task.source_id)
	if container != null:
		container.cancel_haul(dwarf_id)
	_mark_dirty()


func _on_task_gone_signal(task: Task) -> void:
	_route(task, task.assigned_to)


func _on_task_failed(task: Task, _reason: String) -> void:
	_route(task, task.assigned_to)
