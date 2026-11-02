extends RefCounted

## One player order, one batch lease. Ingredients stay physical until the final
## set-down commits output. A trip carries as many of the next ingredients as the
## carrying limit allows when they lie near the first (doc 44, "Trips"). Goods set
## down beside the bench belong to the order, not the Worker: an interrupted Worker
## leaves them there, the bench goes to the next order in turn, and when this order's
## turn comes again a Worker fetches only what is missing at that bench (doc 44,
## "Interruption").
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
var bench_id := -1 # Claimed while a Worker crafts; with goods staged and no Worker, where they lie.
var queue_place := 0 # Turn at a busy bench, counted at the manager's last refresh.
var work_cell := Vector3i(-1,-1,-1)
var item: Node3D
var picked_up := false
var output_material_id := ""
var timber_key := "" # First timber locks the species for the whole batch.
var staged_items: Array[Node3D] = [] # Real loose goods beside the bench, claimed by the order.
var staged_cells: Array[Vector3i] = []
var carried: Array[Node3D] = [] # Picked up on this trip, in the order the batch needs them.
var _preferred_fetch: Dictionary = {}
var _delivery_stand := Vector3i(-1,-1,-1)
var _skipped: Dictionary = {} # Cells of extra ingredients this Worker could not reach.

func scheduling_signature() -> Array:
	return [manager.selection_revision, StockpileManager.hauling_revision,
		allowed_ingredients.duplicate(), paused, manager.bench_claims.duplicate()]

## Owner of the order's claim on its staged goods in ItemDropManager's reservation
## table: positive and far outside the dwarf-id range, like
## FurnitureGhostComponent.claim_owner_id (source ids are unique across sources).
func claim_owner_id() -> int:
	return 1_000_000_000 + source_id

## Goods lie beside the order's bench, claimed by the order.
func holds_goods() -> bool:
	return not staged_items.is_empty()

func advance_worker_quote(from: Vector3i, query: Dictionary, deadline: int, excluded: Dictionary) -> bool:
	return manager.advance_worker_quote(self,from,query,deadline,excluded)

func prefer_fetch_plan(plan: Dictionary) -> void:
	_preferred_fetch = plan

func nearest_stand_target(from: Vector3i) -> Vector3i:
	if worker_id >= 0:
		if _delivery_stand.x >= 0:
			work_cell = _delivery_stand
			return work_cell
		# Pickup can bring the worker around to another side. Use the closest
		# open edge of the claimed bench from their actual carrying position.
		if bench_id >= 0:
			var bench = manager.furniture.get_installed(bench_id)
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
		var bench = manager.furniture.get_installed(bench_id)
		if bench != null: return bench.display_name()
	return "Crafting spot"

func reserve_fetch(dwarf_id: int, from: Vector3i) -> Dictionary:
	if worker_id >= 0:
		if worker_id != dwarf_id or is_instance_valid(item) or not staged_valid(): return {}
		return _reserve_next(from)
	# Recheck at assignment: another delivery may have met a maintain target
	# since the last queue wake, or another Worker may have claimed the timber.
	if not manager.waiting_reason(self, manager.stock_snapshot()).is_empty(): return {}
	if not staged_valid(): return {} # the manager's refresh lets moved goods go
	if not _preferred_fetch.is_empty():
		var plan := _preferred_fetch
		_preferred_fetch = {}
		if int(plan.dwarf_id) != dwarf_id or plan.from != from: return {}
		# Goods beside a bench keep the order at that bench.
		if holds_goods() and int(plan.bench_id) != bench_id: return {}
		if int(plan.bench_id) >= 0 and not manager.bench_valid(int(plan.bench_id),id): return {}
		if _all_staged():
			if plan.material.get("node") == staged_items.back(): item = _lift_last_staged(dwarf_id)
		elif String(plan.material.key) in next_ingredient_keys(): item = manager.reserve_material_quote(plan.material,dwarf_id)
		if item == null: return {}
		if timber_key.is_empty() and staged_items.size() >= manager.additional_ingredient_keys(recipe).size():
			timber_key = manager.items.item_key_of(item)
		worker_id = dwarf_id
		bench_id = int(plan.bench_id)
		if bench_id >= 0: manager.bench_claims[bench_id] = id
		work_cell = plan.delivery_stand
		_delivery_stand = work_cell
		picked_up = false
		manager.wake()
		return {"item":item, "pickup_stand":plan.pickup_stand,
			"heavy":String(manager.items.get_item_def(plan.material.key).get("weight_class","light"))=="heavy"}
	if holds_goods():
		if not manager.bench_valid(bench_id,id): return {}
		work_cell = manager.furniture.get_installed(bench_id).nearest_stand_target(from)
		manager.bench_claims[bench_id] = id
	else:
		work_cell = from
		if not String(recipe.workshop).is_empty():
			var bench: Dictionary = manager.bench_target(String(recipe.workshop), from)
			if bench.is_empty(): return {}
			bench_id = int(bench.id)
			work_cell = bench.stand
			manager.bench_claims[bench_id] = id
	worker_id = dwarf_id
	return _reserve_next(from)

func _reserve_next(from: Vector3i) -> Dictionary:
	if _all_staged():
		item = _lift_last_staged(worker_id)
		if item == null:
			cancel_fetch(worker_id)
			return {}
		picked_up = false
		manager.wake()
		return {"item":item, "heavy":String(manager.items.get_item_def(manager.items.item_key_of(item)).get("weight_class","light")) == "heavy"}
	if not _preferred_fetch.is_empty():
		var plan := _preferred_fetch
		_preferred_fetch = {}
		if plan.from!=from or int(plan.dwarf_id)!=worker_id or not String(plan.material.key) in next_ingredient_keys(): return {}
		if bench_id>=0 and not manager.bench_valid(bench_id,id): return {}
		item = manager.reserve_material_quote(plan.material,worker_id)
		if item==null: return {}
		if staged_items.size()>=manager.additional_ingredient_keys(recipe).size() and timber_key.is_empty(): timber_key = manager.items.item_key_of(item)
		_delivery_stand = plan.delivery_stand
		work_cell = _delivery_stand
		picked_up = false
		return {"item":item,"pickup_stand":plan.pickup_stand,"heavy":String(manager.items.get_item_def(plan.material.key).get("weight_class","light"))=="heavy"}
	var extras: Array[String] = manager.additional_ingredient_keys(recipe)
	if staged_items.size() < extras.size():
		var keys: Array[String] = [extras[staged_items.size()]]
		item = manager.reserve_material(keys, from, worker_id)
	else:
		if timber_key.is_empty():
			item = manager.reserve_ingredient(recipe, from, worker_id, allowed_ingredients, id)
			if item != null: timber_key = manager.items.item_key_of(item)
		else:
			var keys: Array[String] = [timber_key]
			item = manager.reserve_material(keys, from, worker_id)
	if item == null:
		cancel_fetch(worker_id)
		return {}
	picked_up = false
	manager.wake()
	return {"item":item, "heavy":String(manager.items.get_item_def(manager.items.item_key_of(item)).get("weight_class","light")) == "heavy"}

## Every unit the batch takes: its fixed ingredients, then its logs.
func _total() -> int:
	return manager.additional_ingredient_keys(recipe).size() + int(recipe.ingredient_count)

## Every ingredient lies beside the bench, an interrupted Worker's last log
## included: the next Worker lifts that log to work instead of fetching another.
func _all_staged() -> bool:
	return staged_items.size() >= _total()

## The last staged log, as a read-only quote for comparing Workers; {} unless
## every ingredient is staged.
func final_quote(from: Vector3i) -> Dictionary:
	if not _all_staged() or not staged_valid(): return {}
	var node: Node3D = staged_items.back()
	var cell: Vector3i = manager.items.item_floor_cell(node)
	var delta := cell-from
	return {"node":node, "key":manager.items.item_key_of(node), "cell":cell, "distance":absi(delta.x)+absi(delta.y)+absi(delta.z)}

## The order's claim on the last staged log passes to the Worker who lifts it.
func _lift_last_staged(dwarf_id: int) -> Node3D:
	var node: Node3D = staged_items.back()
	manager.items.unreserve(node, claim_owner_id())
	if not manager.items.reserve(node, dwarf_id):
		manager.items.reserve(node, claim_owner_id())
		return null
	staged_items.pop_back()
	staged_cells.pop_back()
	return node

func needs_trip_plan() -> bool:
	return worker_id>=0 and not is_instance_valid(item) and _preferred_fetch.is_empty() and not _all_staged()

func next_ingredient_keys() -> Array[String]:
	var extras: Array[String] = manager.additional_ingredient_keys(recipe)
	if staged_items.size()<extras.size(): return [extras[staged_items.size()]]
	if not timber_key.is_empty(): return [timber_key]
	return manager.batch_ingredient_keys(recipe,manager.stock_snapshot(),allowed_ingredients,id)

## Something carried must be set down before work: the batch is not all here yet,
## or the trip brought more than the one log worked in hand.
func needs_ingredient_delivery() -> bool:
	return staged_items.size() < _total() - 1 or carried.size() > 1

func pending_timber_count() -> int:
	var logs := maxi(0,_gathered().size()-manager.additional_ingredient_keys(recipe).size())
	return maxi(0,int(recipe.ingredient_count)-logs)

## Staged, carried and reserved ingredients, in the order the batch needs them.
func _gathered() -> Array[Node3D]:
	var goods: Array[Node3D] = []
	goods.append_array(staged_items)
	goods.append_array(carried)
	if is_instance_valid(item) and item not in goods: goods.append(item)
	return goods

## The keys that can fill the batch's unit at this index.
func _keys_at(index: int) -> Array[String]:
	var extras: Array[String] = manager.additional_ingredient_keys(recipe)
	if index < extras.size(): return [extras[index]]
	if not timber_key.is_empty(): return [timber_key]
	return manager.batch_ingredient_keys(recipe,manager.stock_snapshot(),allowed_ingredients,id)

## After a pickup, the next ingredient the batch needs when it lies near and fits
## the carrying limit (doc 44, "Trips"); {} when the trip heads for the bench.
func reserve_trip_extra(dwarf_id: int, from: Vector3i) -> Dictionary:
	if dwarf_id != worker_id or not picked_up or carried.is_empty(): return {}
	var index := staged_items.size() + carried.size()
	if index >= _total(): return {}
	var hauling: Dictionary = TaskManager.get_config_section("hauling")
	var keys: Array[String] = []
	for key: String in _keys_at(index):
		if _load_with(key) <= int(hauling.get("carry_capacity",4)): keys.append(key)
	if keys.is_empty(): return {}
	var next: Node3D = manager.reserve_nearby(keys,from,dwarf_id,int(hauling.get("pouch_bundle_radius",8)),_skipped)
	if next == null: return {}
	item = next
	picked_up = false
	_settle_timber()
	manager.wake()
	return {"item":next, "heavy":String(manager.items.get_item_def(manager.items.item_key_of(next)).get("weight_class","light"))=="heavy"}

## An extra the Worker could not reach or lift stays where it is; the trip goes
## on to the bench. Returns the last ingredient carried, or null with none.
func drop_trip_extra(dwarf_id: int) -> Node3D:
	if dwarf_id != worker_id or carried.is_empty(): return null
	if is_instance_valid(item) and not picked_up:
		_skipped[manager.items.item_floor_cell(item)] = true
		manager.items.unreserve(item, dwarf_id)
	item = carried.back()
	picked_up = true
	_settle_timber()
	return item

## The log in the Worker's hands to be worked, once everything else is set down.
func held_item() -> Node3D:
	return item if picked_up and is_instance_valid(item) else null

func _carry_cost(key: String) -> int:
	return maxi(1,int(manager.items.get_item_def(key).get("carry_cost",1)))

## The load of the goods carried with one more `key`. Goods that travel in crates share
## one crate's load a kind, as a hauler carries a crate of fish; a log or a stone is
## its own load.
func _load_with(key: String) -> int:
	var units := {key: 1}
	for node: Node3D in carried:
		var carried_key: String = manager.items.item_key_of(node)
		units[carried_key] = int(units.get(carried_key,0)) + 1
	var load := 0
	for each: String in units:
		load += ceili(float(units[each])/manager.items.item_capacity(each))*_carry_cost(each)
	return load

## Staged goods by key, split into the fixed ingredients and the timber, so the
## order's own goods count toward what it still needs.
func held_counts() -> Dictionary:
	var counts := {"extras":{}, "timber":{}}
	var extras: int = manager.additional_ingredient_keys(recipe).size()
	for index in range(staged_items.size()):
		if not is_instance_valid(staged_items[index]): continue
		var group: Dictionary = counts.extras if index < extras else counts.timber
		var key: String = manager.items.item_key_of(staged_items[index])
		group[key] = int(group.get(key,0)) + 1
	return counts

## Sets the trip's goods down beside the bench. When they complete the batch, its
## last log stays in hand to be worked (held_item).
func stage_ingredient(dwarf_id: int) -> bool:
	if dwarf_id != worker_id or not picked_up or carried.is_empty(): return false
	if not staged_valid() or not NavGrid.is_walkable(work_cell): return false
	if not String(recipe.workshop).is_empty() and not manager.bench_valid(bench_id,id): return false
	if not needs_ingredient_delivery(): return false
	var extras: Array[String] = manager.additional_ingredient_keys(recipe)
	var keep: Node3D = carried.back() if staged_items.size() + carried.size() >= _total() else null
	var put_down: Array[Node3D] = carried.filter(func(node: Node3D) -> bool: return node != keep)
	for index in range(put_down.size()):
		var at := staged_items.size() + index
		var expected: String = extras[at] if at < extras.size() else timber_key
		if not is_instance_valid(put_down[index]) or manager.items.item_key_of(put_down[index]) != expected or manager.items.quantity_of(put_down[index]) != 1: return false
	for node: Node3D in put_down:
		# Rejoin the ordinary loose-item owner before the next trip. This keeps
		# saving, inventory and support-loss handling on their existing paths.
		manager.items.drop_loose(node, work_cell)
		if not manager.items.reserve(node, claim_owner_id()): return false
		carried.erase(node)
		staged_items.append(node)
		staged_cells.append(manager.items.item_floor_cell(node))
	_delivery_stand = Vector3i(-1,-1,-1)
	item = keep
	picked_up = keep != null
	manager.wake()
	return true

func staged_valid() -> bool:
	for index in range(staged_items.size()):
		var staged := staged_items[index]
		if not is_instance_valid(staged) or not manager.items.reserved_by(staged,claim_owner_id()): return false
		if manager.items.item_floor_cell(staged) != staged_cells[index]: return false
	return true

## A crate of fish may hold several. Only one unit leaves it at pickup, as a cutting
## leaves its crate (ShrubPlantingComponent); a single log is taken whole.
func take_planting_item(node: Node3D, dwarf_id: int) -> Node3D:
	if manager.items.quantity_of(node) <= 1:
		return node if not manager.items.take(node).is_empty() else null
	var cargo: Node3D = manager.items.take_quantity(node, 1, dwarf_id)
	if cargo != null and node == item: item = cargo
	return cargo

func notify_picked_up(_dwarf_id: int) -> void:
	picked_up = true
	if is_instance_valid(item) and item not in carried: carried.append(item)
	manager.wake()

## The Worker stops: sleep, a meal, a broken route or a finished batch. The bench
## goes to the next order in turn. Staged goods stay claimed by the order, and so
## does the ingredient in the Worker's hands once it lands beside the bench
## (keep_dropped). Only release_goods lets them go.
func cancel_fetch(dwarf_id: int) -> void:
	if worker_id != dwarf_id: return
	var carrying := not carried.is_empty()
	var reserved: Node3D = item if is_instance_valid(item) and not picked_up else null
	if reserved != null: manager.items.unreserve(reserved, dwarf_id)
	worker_id = -1
	item = null
	picked_up = false
	carried.clear()
	_preferred_fetch.clear()
	_delivery_stand = Vector3i(-1,-1,-1)
	_skipped.clear()
	_settle_timber()
	# A log lifted from the staged goods but not yet picked up goes back to the order.
	if reserved != null and not paused and _beside_bench(manager.items.item_floor_cell(reserved)): _claim(reserved)
	_release_claim()
	# The carried ingredients drop at the Worker's feet just after; keep_dropped
	# decides, and the manager's refresh frees the bench if none stays.
	if not holds_goods() and not carrying: _free_bench()
	manager.wake()

## An ingredient an interrupted Worker carried stays with the order when it lands
## beside the order's bench, as when they were setting goods down or working.
func keep_dropped(node: Node3D) -> void:
	if worker_id >= 0 or not is_instance_valid(node): return
	if not paused and _beside_bench(manager.items.item_floor_cell(node)): _claim(node)
	manager.wake()

## Lets every staged good go as ordinary loose goods, which hauling stores, and
## frees the bench: the order paused or cancelled, its bench gone, its wood
## excluded or its stock target met.
func release_goods() -> void:
	for staged: Node3D in staged_items:
		if is_instance_valid(staged): manager.items.unreserve(staged, claim_owner_id())
	staged_items.clear()
	staged_cells.clear()
	if worker_id < 0: _free_bench()
	manager.wake()

## A load claims the goods kept beside the bench again, in staging order. The
## first one no longer there ends the list; the rest stay ordinary goods.
func restore_goods(goods: Array, saved_bench: int) -> void:
	if goods.is_empty() or paused or String(recipe.workshop).is_empty(): return
	var bench = manager.furniture.get_installed(saved_bench)
	if bench == null or bench.furniture_key != String(recipe.workshop) or not manager.bench_usable(saved_bench): return
	bench_id = saved_bench
	for entry in goods:
		if not entry is Dictionary: break
		var cell: Vector3i = SaveManager.unpack_v3i(entry.get("cell",[]))
		var node: Node3D = manager.items.nearest_loose_of_key(String(entry.get("item","")),cell)
		if node == null: break
		var at: Vector3i = manager.items.item_floor_cell(node)
		# Cargo lands up to a quarter block from its carrier, so the next cell counts too.
		if at.y != cell.y or absi(at.x-cell.x) > 1 or absi(at.z-cell.z) > 1 or not _beside_bench(at) or not _claim(node): break
	if not holds_goods(): _free_bench()

## Claims a loose good as the next staged ingredient if it is the one the batch needs.
func _claim(node: Node3D) -> bool:
	var extras: Array[String] = manager.additional_ingredient_keys(recipe)
	if _all_staged() or manager.items.quantity_of(node) != 1: return false
	var key: String = manager.items.item_key_of(node)
	if staged_items.size() < extras.size():
		if key != extras[staged_items.size()]: return false
	elif key not in allowed_ingredients or (not timber_key.is_empty() and key != timber_key): return false
	if not manager.items.reserve(node, claim_owner_id()): return false
	staged_items.append(node)
	staged_cells.append(manager.items.item_floor_cell(node))
	_settle_timber()
	return true

## A floor cell beside the order's standing bench: where goods are set down and worked.
func _beside_bench(cell: Vector3i) -> bool:
	if bench_id < 0 or not manager.bench_usable(bench_id): return false
	var bench = manager.furniture.get_installed(bench_id)
	if cell in bench.cells: return false
	for footprint: Vector3i in bench.cells:
		for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if footprint+offset == cell: return true
	return false

## The batch's first log gathered keeps its species; with none the next log chooses it.
func _settle_timber() -> void:
	var extras: int = manager.additional_ingredient_keys(recipe).size()
	var goods := _gathered()
	timber_key = manager.items.item_key_of(goods[extras]) if goods.size() > extras and is_instance_valid(goods[extras]) else ""

func _release_claim() -> void:
	if manager.bench_claims.get(bench_id, -1) == id: manager.bench_claims.erase(bench_id)

func _free_bench() -> void:
	_release_claim()
	bench_id = -1
	timber_key = ""

func can_complete_build() -> bool:
	if worker_id < 0 or not picked_up or not is_instance_valid(item): return false
	if needs_ingredient_delivery() or not staged_valid(): return false
	if manager.items.quantity_of(item) != 1: return false
	if manager.items.item_key_of(item) not in allowed_ingredients: return false
	if manager.items.item_key_of(item) != timber_key: return false
	if not NavGrid.is_walkable(work_cell): return false
	return String(recipe.workshop).is_empty() or manager.bench_valid(bench_id, id)

func remaining_work() -> float:
	return maxf(0.0, float(recipe.work_seconds)-progress)

func advance_craft(delta: float) -> float:
	progress = minf(float(recipe.work_seconds), progress + delta)
	return remaining_work()

## How a Worker works at its bench (the bench's `crafting_motion`): "hew" with the axe at the
## workbench, "hands" hanging fish at the drying rack (doc 289).
func work_motion() -> String:
	var bench = manager.furniture.get_installed(bench_id) if bench_id >= 0 else null
	return String(bench.def.get("crafting_motion", "hew")) if bench != null else "hew"

func work_surface() -> Vector3:
	var agent: Node3D = TaskManager.get_agent(worker_id)
	if bench_id >= 0:
		var bench = manager.furniture.get_installed(bench_id)
		if bench != null:
			var from: Vector3 = agent.global_position if agent != null else bench.node.global_position+Vector3.FORWARD
			return manager.bench_surface(bench,from)
	return agent.to_global(Vector3(0,0,1.35)) if agent != null else Vector3(work_cell)+Vector3(.5,1,.5)

func capture_item_properties(cargo: Node3D) -> void:
	output_material_id = ""
	if not recipe.has("material_group"): return
	output_material_id = CraftMaterials.of_item(cargo)
	if output_material_id.is_empty(): output_material_id = CraftMaterials.from_ingredient(manager.items.item_key_of(cargo))

func complete_build(dwarf_id: int) -> void:
	# Called synchronously after the executor validates the whole batch and
	# consumes the final carried log. Staged materials commit exactly once.
	for staged: Node3D in staged_items:
		manager.items.take(staged)
		staged.queue_free()
	staged_items.clear()
	staged_cells.clear()
	# Fish hung on the rack dry there (doc 292): the batch stays on its workshop, which gives
	# the dried fish, and the Ranger's log counts them, when a Ranger takes them down.
	if recipe.has("dry_hours"): manager.hang_batch(self)
	else: manager.items.spawn_drop(String(recipe.output), int(recipe.output_count), work_cell+Vector3i.UP, output_material_id)
	# A crafting career earns one experience a batch (doc 293: the Carpenter and the Stonemason).
	var agent = TaskManager.get_agent(dwarf_id)
	if is_instance_valid(agent) and DwarfAssets.earns_by(agent.profession, "CRAFT"):
		agent.profession_experience[agent.profession] = maxi(0, int(agent.profession_experience.get(agent.profession, 0))) + 1
	if not maintain: quantity -= 1
	progress = 0.0
	item = null # consumed with the batch
	carried.clear()
	cancel_fetch(dwarf_id)

func serialize() -> Dictionary:
	var data := {"id":id,"recipe":String(recipe.id), "quantity":quantity,
		"maintain":maintain, "paused":paused, "progress":progress,
		"allowed_ingredients":allowed_ingredients.duplicate()}
	# Goods beside the bench, in staging order, then the Worker's ingredients if
	# they hold them there: they land at their feet on load (DwarfDirector).
	var goods: Array = []
	for index in range(staged_items.size()):
		if is_instance_valid(staged_items[index]):
			goods.append({"item":manager.items.item_key_of(staged_items[index]), "cell":SaveManager.pack_v3i(staged_cells[index])})
	var agent = TaskManager.get_agent(worker_id) if worker_id >= 0 else null
	if is_instance_valid(agent) and _beside_bench(agent.current_cell()):
		for node: Node3D in carried:
			if is_instance_valid(node): goods.append({"item":manager.items.item_key_of(node), "cell":SaveManager.pack_v3i(agent.current_cell())})
	if not goods.is_empty() and bench_id >= 0:
		data["bench"] = bench_id
		data["staged"] = goods
	return data

func work_waiting_reason() -> String:
	return manager.waiting_reason(self,manager.stock_snapshot())
