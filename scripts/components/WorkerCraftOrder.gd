extends RefCounted

## One player order, one batch lease. Ingredients stay physical until the final
## set-down commits output. Interruption releases the bench and returns cargo.
var manager: Node
var recipe: Dictionary
var id := 0
var quantity := 1
var maintain := false
var paused := false
var allowed_ingredients: Array[String] = []
var progress := 0.0
var source_id := -1
var lease_id := -1
var worker_id := -1
var bench_id := -1
var work_cell := Vector3i(-1,-1,-1)
var item: Node3D
var picked_up := false

func nearest_stand_target(from: Vector3i) -> Vector3i:
	if worker_id >= 0:
		# Pickup can bring the worker around to another side. Use the closest
		# open edge of the claimed bench from their actual carrying position.
		if bench_id >= 0:
			var bench = manager.furniture._installed.get(bench_id)
			if bench == null or not manager.bench_valid(bench_id,id): return Vector3i(-1,-1,-1)
			work_cell = bench.nearest_stand_target(from)
		elif picked_up and String(recipe.workshop).is_empty():
			# A bootstrap recipe has no fixed workshop. Work where the timber
			# was collected, not where the worker happened to accept the job.
			work_cell = from if NavGrid.is_walkable(from) else Vector3i(-1,-1,-1)
		return work_cell
	if String(recipe.workshop).is_empty(): return from
	return manager.bench_target(String(recipe.workshop), from).get("stand", Vector3i(-1,-1,-1))

func display_name() -> String:
	if bench_id >= 0:
		var bench = manager.furniture._installed.get(bench_id)
		if bench != null: return bench.display_name()
	return "Crafting spot"

func reserve_fetch(dwarf_id: int, from: Vector3i) -> Dictionary:
	if worker_id >= 0: return {}
	# Recheck at assignment: another delivery may have met a maintain target
	# since the last queue wake, or another Worker may have claimed the timber.
	if not manager.waiting_reason(self, manager.stock_snapshot()).is_empty(): return {}
	work_cell = from
	if not String(recipe.workshop).is_empty():
		var bench: Dictionary = manager.bench_target(String(recipe.workshop), from)
		if bench.is_empty(): return {}
		bench_id = int(bench.id)
		work_cell = bench.stand
		manager.bench_claims[bench_id] = id
	worker_id = dwarf_id
	item = manager.reserve_ingredient(recipe, from, dwarf_id, allowed_ingredients)
	if item == null:
		cancel_fetch(dwarf_id)
		return {}
	picked_up = false
	manager.wake()
	return {"item":item, "heavy":true}

func notify_picked_up(_dwarf_id: int) -> void:
	picked_up = true
	manager.wake()

func cancel_fetch(dwarf_id: int) -> void:
	if worker_id != dwarf_id: return
	if is_instance_valid(item) and not picked_up:
		manager.items.unreserve(item, dwarf_id)
	if manager.bench_claims.get(bench_id, -1) == id: manager.bench_claims.erase(bench_id)
	worker_id = -1
	bench_id = -1
	item = null
	picked_up = false
	manager.wake()

func can_complete_build() -> bool:
	if worker_id < 0 or not picked_up or not is_instance_valid(item): return false
	if manager.items.quantity_of(item) != 1: return false
	if manager.items.item_key_of(item) not in allowed_ingredients: return false
	if not NavGrid.is_walkable(work_cell): return false
	return String(recipe.workshop).is_empty() or manager.bench_valid(bench_id, id)

func remaining_work() -> float:
	return maxf(0.0, float(recipe.work_seconds)-progress)

func advance_craft(delta: float) -> float:
	progress = minf(float(recipe.work_seconds), progress + delta)
	return remaining_work()

func work_surface() -> Vector3:
	var agent: Node3D = TaskManager._agents.get(worker_id)
	if bench_id >= 0:
		var bench = manager.furniture._installed.get(bench_id)
		if bench != null:
			var center: Vector3 = bench.node.global_position
			# The stump has no front: the material and axe face the approaching
			# worker, independently of the furniture's decorative rotation.
			var toward := (agent.global_position-center) if agent != null else Vector3.FORWARD
			toward.y = 0
			toward = toward.normalized()
			return center + Vector3(toward.x*.125, float(bench.def.get("crafting_surface_height",1.0)), toward.z*.125)
	return agent.to_global(Vector3(0,0,1.35)) if agent != null else Vector3(work_cell)+Vector3(.5,1,.5)

func complete_build(dwarf_id: int) -> void:
	# Called synchronously after the fetch executor consumes exactly one log.
	manager.items.spawn_drop(String(recipe.output), int(recipe.output_count), work_cell+Vector3i.UP)
	if not maintain: quantity -= 1
	progress = 0.0
	cancel_fetch(dwarf_id)

func serialize() -> Dictionary:
	return {"recipe":String(recipe.id), "quantity":quantity,
		"maintain":maintain, "paused":paused, "progress":progress,
		"allowed_ingredients":allowed_ingredients.duplicate()}
