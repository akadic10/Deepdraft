extends RefCounted

## Mining zones as work sources for MiningDesignationController (doc 258 step
## 8): MINE leases and their task-event routing, the block execution pipeline
## (swing cost, the void write, drops) and the DEV instant mine. The zone
## records stay in the controller; this helper shares its two tables and calls
## back through the controller's public hooks for overlays, the window and the
## area guide.

var controller
var zones: Dictionary          # the controller's zone_id -> zone record
var zone_by_block: Dictionary  # the controller's block -> zone_id
var max_workers: int           # data/terrain/mining_config.json zone.max_workers
var swing_base_time: float     # execution.swing_base_time_s
var _occupancy_dirty_zones: Dictionary = {}
## Cached ItemDropManager scene node (group lookup, lazy).
var _drop_manager_node: ItemDropManager = null


func _init(owner_controller, zone_table: Dictionary, block_table: Dictionary,
		default_max_workers: int, default_swing_base_time: float) -> void:
	controller = owner_controller
	zones = zone_table
	zone_by_block = block_table
	max_workers = default_max_workers
	swing_base_time = default_swing_base_time


static func block_id_at(pos: Vector3i) -> int:
	return WorldData.get_live_block(pos.x,pos.y,pos.z)


## Picking/planning must agree with the concealed slice, even when actual
## generated air exists behind it. Revealed air is removed from plans later.
static func designation_block_id_at(pos: Vector3i) -> int:
	if InteriorTracker.is_known(pos): return WorldData.get_terrain_block(pos.x,pos.y,pos.z)
	var cave_id := WorldGenerator.get_cave_id(pos)
	if cave_id >= 0 and not InteriorTracker.is_cave_discovered(cave_id):
		return WorldGenerator.get_overview_strata_block_id(pos.x, pos.y, pos.z)
	return block_id_at(pos)


# ── Zone work source — leases & execution (doc 16 steps 5/6) ─────────────────

## Posts MINE leases up to min(max_workers, unreserved remaining blocks).
## Leases are INTENT-sized (doc 16 §2.1) — at most max_workers per zone, never
## per-block tasks. Excess leases self-correct: a dwarf that pulls nothing
## completes its lease early.
func top_up_leases(zone_id: int) -> void:
	var zone: Dictionary = zones.get(zone_id, {})
	if zone.is_empty():
		return
	var component: MiningZoneComponent = zone.get("component")
	if component == null:
		return
	var target := mini(max_workers, component.unreserved_remaining())
	while component.lease_ids.size() < target:
		var rep := component.representative_target()
		if rep.y < 0:
			break
		var task_id := TaskManager.add_task(
			Task.Type.MINE, rep, { "zone_id": zone_id }, zone_id)
		component.lease_ids[task_id] = true


## The component behind a task, or null if the task is not a zone lease.
func _component_for(task: Task) -> MiningZoneComponent:
	if task == null or task.type != Task.Type.MINE:
		return null
	var zone: Dictionary = zones.get(task.source_id, {})
	if zone.is_empty():
		return null
	return zone.get("component")


func on_task_released(task: Task, dwarf_id: int, _reason: int) -> void:
	var component := _component_for(task)
	if component != null:
		component.release_worker(dwarf_id)   # reservation freed; completed set untouched (§2.8)


func on_task_completed(task: Task) -> void:
	_on_lease_finished(task)


func on_task_failed(task: Task, _reason: String) -> void:
	_on_lease_finished(task)


func on_task_cancelled(task: Task) -> void:
	_on_lease_finished(task)


func _on_lease_finished(task: Task) -> void:
	var component := _component_for(task)
	if component == null:
		return
	component.lease_ids.erase(task.id)
	if task.assigned_to >= 0:
		component.release_worker(task.assigned_to)
	maybe_destroy_finished_zone(task.source_id)
	if zones.has(task.source_id):
		controller.refresh_zone_window(task.source_id)


## Stuck-zone revival: a terrain change near a zone with NO working dwarves
## refreshes it — destination recomputed, leases re-targeted and re-armed,
## missing leases reposted. This covers BOTH stall shapes:
##   - zero leases (all completed early while unreachable), and
##   - blocked leases whose targets went stale (zone designated while sealed;
##     a later dig exposes its face, but the leases kept probing the interior
##     rock they were aimed at on confirm — caught in-engine 2026-06-10).
## Zones with an assigned worker self-maintain (targets refresh on their own
## mined blocks), so they are skipped. Per-zone 250 ms throttle keeps the
## per-mined-block cost bounded; worldgen streaming is naturally cheap here
## because fresh zones rarely intersect streaming chunks without also being
## worked.
func on_world_chunk_dirtied(cx: int, cy: int, cz: int) -> void:
	if zones.is_empty():
		return
	var chunk := Vector3i(cx, cy, cz)
	var now := Time.get_ticks_msec()
	for zone_id: int in zones.keys():
		var component: MiningZoneComponent = (zones[zone_id] as Dictionary).get("component")
		if component == null or component.is_empty():
			continue
		if not component.intersects_chunk(chunk):
			continue
		if _has_assigned_worker(component):
			continue
		if now - component.last_refresh_msec < 250:
			continue
		component.last_refresh_msec = now
		component.mark_destination_dirty()
		top_up_leases(zone_id)
		refresh_lease_targets(zone_id)


## Furniture moves and felled trunks change stand cells without editing terrain.
## Invalidate immediately, then coalesce all footprint changes before replanning
## against NavGrid's final state. Never throttle away the removal half of a move.
func on_occupancy_changed(box_min: Vector3i, box_size: Vector3i) -> void:
	if not controller.is_inside_tree(): return
	var was_empty := _occupancy_dirty_zones.is_empty()
	for zone_id: int in zones:
		var component: MiningZoneComponent = zones[zone_id].get("component")
		if component == null or component.is_empty() or not component.intersects_occupancy(box_min,box_size): continue
		component.mark_destination_dirty()
		_occupancy_dirty_zones[zone_id] = true
	if was_empty and not _occupancy_dirty_zones.is_empty():
		_refresh_occupancy_zones.call_deferred()


func _refresh_occupancy_zones() -> void:
	var changed := _occupancy_dirty_zones.keys()
	_occupancy_dirty_zones.clear()
	if not controller.is_inside_tree(): return
	for zone_id: int in changed:
		top_up_leases(zone_id)
		refresh_lease_targets(zone_id, "Nearby obstruction changed")


func _has_assigned_worker(component: MiningZoneComponent) -> bool:
	for task_id: int in component.lease_ids.keys():
		var task := TaskManager.get_task(task_id)
		if task != null and task.assigned_to >= 0:
			return true
	return false


## Swing parameters for one block (doc 43: mine_time = base × hardness /
## skill; doc 16 §2.7: durability swings per block). Skill speed is applied by
## the AGENT (its profession multiplier) — this is the block's base cost.
## Reached through the controller's get_zone_block_work.
func get_block_work(block: Vector3i) -> Dictionary:
	var block_id := block_id_at(block)
	if not BlockRegistry.is_solid(block_id):
		# Undiscovered cave air is planned as the strata the slice shows. Work it
		# as that block so the commit breaks into the cave and reveals it; air
		# the player already knows about has nothing left to mine.
		block_id = designation_block_id_at(block)
		if not BlockRegistry.is_solid(block_id):
			return {}
	var key := BlockRegistry.get_key(block_id)
	var def := BlockRegistry.get_def(key)
	var hardness := maxi(int(def.get("hardness", 1)), 1)
	var res := BlockRegistry.get_resource_def(key)
	var durability := maxi(int(res.get("durability", 2)), 1)
	var block_time := swing_base_time * float(hardness)
	return {
		"swings": durability,
		"swing_time": block_time / float(durability),
	}


## Match the struck face's concealment rule: only mined-open neighbours
## expose the real resource. A natural/slice/designation face shows strata.
func play_impact(block: Vector3i, impact_position: Vector3, normal: Vector3) -> void:
	var block_id := block_id_at(block)
	if not BlockRegistry.is_solid(block_id):
		block_id = designation_block_id_at(block)   # concealed cave air strikes like its strata
		if not BlockRegistry.is_solid(block_id):
			return
	var exposed_air := block + Vector3i(normal)
	var cave_id := WorldGenerator.get_cave_id(exposed_air)
	if not WorldData.is_removed_terrain(exposed_air) and not (cave_id >= 0 and InteriorTracker.is_cave_discovered(cave_id)):
		block_id = WorldGenerator.get_overview_strata_block_id(block.x,block.y,block.z)
	WorkFeedback.mining_impact(impact_position,block,block_id,normal)


## THE mining execution pipeline (doc 16 §2.7 step 4) — one block leaves the
## world. Called by MiningZoneComponent.commit_mined (real mining) through the
## controller's execute_zone_block_mined; the DEV instant-mine button runs the
## same world-mutation steps minus dwarf/drops.
## Returns false (and writes nothing) on any guard failure.
func execute_block_mined(zone_id: int, block: Vector3i, dwarf_id: int) -> bool:
	var zone: Dictionary = zones.get(zone_id, {})
	if zone.is_empty():
		return false
	# Hard Rule 1 — re-validated at the moment of the void write, independent
	# of designation-time filters.
	if block.y <= MiningDesignationController.BEDROCK_MAX_Y:
		push_error("MiningDesignationController: bedrock write blocked at %s." % str(block))
		return false

	# Capture identity BEFORE the void write (drops + sanity).
	var pre_id := block_id_at(block)
	if int(BlockRegistry.get_def(BlockRegistry.get_key(pre_id)).get("hardness",1))<0: return false
	var was_solid := BlockRegistry.is_solid(pre_id)

	mine_block_world(block)
	NavGrid.refresh_mined_block(block)
	if was_solid:
		_spawn_block_drops(pre_id, block)
		WorkFeedback.block_mined(block,pre_id)

	# Zone bookkeeping.
	var component: MiningZoneComponent = zone.get("component")
	if component != null:
		component.mark_completed(block, dwarf_id)
	(zone["blocks"] as Array).erase(block)

	if component != null and component.is_empty():
		_cancel_pending_leases(zone_id)
		maybe_destroy_finished_zone(zone_id)
	else:
		controller.refresh_zone_overlay(zone_id)
		top_up_leases(zone_id)
		refresh_lease_targets(zone_id)
	if zones.has(zone_id):
		controller.refresh_zone_window(zone_id)
	return true


## Mining opens new stand cells, so the zone's reachable-representative moves.
## Re-target the zone's still-PENDING leases (≤ max_workers of them) so their
## probes and the chunk-dirtied re-arm aim at live geometry, and clear their
## backoff — the terrain just changed in this very zone.
func refresh_lease_targets(zone_id: int, retry_reason: String = "") -> void:
	var zone: Dictionary = zones.get(zone_id, {})
	var component: MiningZoneComponent = zone.get("component") if not zone.is_empty() else null
	if component == null:
		return
	var rep := component.representative_target()
	if rep.y < 0:
		return
	var orders: Dictionary = {}
	for task_id: int in component.lease_ids.keys():
		var task := TaskManager.get_task(task_id)
		if task == null or task.assigned_to >= 0:
			continue
		task.target_pos = rep
		task.retry_at = 0   # re-arm immediately; the next wake re-probes
		if not retry_reason.is_empty(): orders[task.order_key] = true
	for order_key: String in orders:
		TaskManager.retry_order(order_key, retry_reason)


## World-mutation core shared by real mining and DEV mine: materialise the
## chunk, write void through WorldData (NavGrid + future systems see truth —
## closes the step-3b DEV wart), promote to MINED in the renderer (exposure
## pipeline, SO-2b), feed X0, update controller raycast/grid bookkeeping.
func mine_block_world(block: Vector3i) -> void:
	var blocks: Array[Vector3i] = [block]
	mine_blocks_world(blocks)


## Batched core of the void write. All per-block state lands first, then the
## renderer, InteriorTracker, and grid flags are notified ONCE with the whole
## batch. Save-restore previously routed thousands of blocks through the
## single-block path — one add_mined_blocks call (and thus one coalesced
## cavity-shell rebuild) per block, O(n²) over the save. One batch call keeps
## the load boundary O(n).
func mine_blocks_world(blocks: Array[Vector3i]) -> void:
	if blocks.is_empty():
		return
	for block: Vector3i in blocks:
		ensure_chunk_real(block)
		WorldData.set_block(block.x, block.y, block.z, BlockRegistry.AIR_ID)
		if zone_by_block.has(block):
			zone_by_block.erase(block)
	var renderer: Node = controller.get_renderer()
	if renderer != null and renderer.has_method("add_mined_blocks"):
		renderer.call("add_mined_blocks", blocks)
	InteriorTracker.on_blocks_mined(blocks)
	controller.mark_grid_dirty()


## Materialises an ungenerated chunk from the deterministic generator before
## the first real write. Without this, WorldData's lazy chunk creation would
## hand back an ALL-VOID chunk and silently delete 4,095 innocent blocks.
## Cost: 4,096 generator calls, once per first-touched chunk (~ms scale) —
## acceptable for v1; thread it only if profiling ever disagrees (doc 11
## lesson: one variable at a time).
static func ensure_chunk_real(block: Vector3i) -> void:
	var cx := block.x >> 4
	var cy := block.y >> 4
	var cz := block.z >> 4
	if WorldData.chunk_exists(cx, cy, cz):
		return
	var chunk: Chunk = WorldData.get_chunk(cx, cy, cz)   # creates empty (all void)
	var base_x := cx << 4
	var base_y := cy << 4
	var base_z := cz << 4
	for ly in range(16):
		for lz in range(16):
			for lx in range(16):
				chunk.blocks[Chunk.local_index(lx, ly, lz)] = int(WorldGenerator.get_generated_block_id(
					base_x + lx, base_y + ly, base_z + lz))


## Rolls the block's loot table (block_resources.json) and hands drops to the
## ItemDropManager. randf chance rolls are runtime behaviour, not worldgen —
## Hard Rule 8 (deterministic terrain identity) does not apply to drops.
func _spawn_block_drops(pre_block_id: int, block: Vector3i) -> void:
	var manager := _drop_manager()
	if manager == null:
		return
	var key := BlockRegistry.get_key(pre_block_id)
	var res := BlockRegistry.get_resource_def(key)
	var drops: Array = res.get("drops", [])
	for entry in drops:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var drop: Dictionary = entry
		if randf() > float(drop.get("chance", 1.0)):
			continue
		manager.spawn_drop(
			String(drop.get("item", "")), int(drop.get("count", 1)), block)


func _drop_manager() -> ItemDropManager:
	if _drop_manager_node == null or not is_instance_valid(_drop_manager_node):
		_drop_manager_node = ItemDropManager.find(controller.get_tree())
	return _drop_manager_node


## Cancels a finished zone's still-PENDING leases; assigned leases complete
## naturally (their dwarves pull nothing and finish).
func _cancel_pending_leases(zone_id: int) -> void:
	var zone: Dictionary = zones.get(zone_id, {})
	var component: MiningZoneComponent = zone.get("component") if not zone.is_empty() else null
	if component == null:
		return
	for task_id: int in component.lease_ids.keys().duplicate():
		var task := TaskManager.get_task(task_id)
		if task != null and task.assigned_to < 0:
			TaskManager.cancel_task(task_id)   # cancelled handler erases the lease id


## Destroys a zone once it is mined out AND its last lease has finished.
## (Player removal goes through the controller's _remove_zone instead — that
## path cancels assigned leases too.)
func maybe_destroy_finished_zone(zone_id: int) -> void:
	var zone: Dictionary = zones.get(zone_id, {})
	if zone.is_empty():
		return
	var component: MiningZoneComponent = zone.get("component")
	if component == null or not component.is_empty() or not component.lease_ids.is_empty():
		return
	TaskManager.unregister_work_source(zone_id)
	zones.erase(zone_id)
	controller.refresh_zone_overlay(zone_id)   # frees the overlay of an erased zone
	if controller.get_selected_zone_id() == zone_id:
		controller.close_zone_window()
	print("MiningDesignationController: zone %d mined out — destroyed." % zone_id)


# ── DEV instant mine (testing tool — no drops) ────────────────────────────────

## Executes a zone immediately: its blocks leave the game through the SAME
## world-mutation pipeline as real mining, minus the dwarf and minus drops
## (doc 16 Phase 4: "the same pipeline minus the dwarf"). The renderer's
## visual cuts are deliberately KEPT (in overview mode the cut set is the
## authoritative record of removal — the generated heightmap would resurrect
## the rock otherwise). Chunks are MATERIALISED before the void write, so
## WorldData and NavGrid see truth everywhere (the step-3b DEV wart is
## closed). X0 interior tracking runs here too.
func dev_mine_zone(zone_id: int) -> void:
	if not zones.has(zone_id):
		return
	var zone: Dictionary = zones[zone_id]
	# Pull the work source out from under any dwarves first.
	TaskManager.cancel_source_tasks(zone_id)
	TaskManager.unregister_work_source(zone_id)
	var mined: Array[Vector3i] = []
	for block: Vector3i in zone.get("blocks", []):
		if block.y <= MiningDesignationController.BEDROCK_MAX_Y:
			continue   # Hard Rule 1 — never write bedrock, even in DEV paths
		if int(BlockRegistry.get_def(BlockRegistry.get_key(block_id_at(block))).get("hardness",1))<0: continue
		if zone_by_block.get(block, -1) == zone_id:
			zone_by_block.erase(block)
		mined.append(block)
		ensure_chunk_real(block)
		WorldData.set_block(block.x, block.y, block.z, BlockRegistry.AIR_ID)
	zones.erase(zone_id)
	# NOTE: no visual-cut removal here — the cuts ARE the mined holes.
	# Promote the blocks to MINED in the renderer (doc 11 Phase SO-2b): punches
	# wall side-bands and grows the cavity shell.
	var renderer: Node = controller.get_renderer()
	if renderer != null and renderer.has_method("add_mined_blocks"):
		renderer.call("add_mined_blocks", mined)
	InteriorTracker.on_blocks_mined(mined)
	controller.refresh_zone_overlay(zone_id)   # frees the overlay of an erased zone
	controller.refresh_tool_view()   # mined blocks change effective grid tops
	print("MiningDesignationController: DEV mined zone %d (%d blocks, no drops)." % [
		zone_id, mined.size()])
