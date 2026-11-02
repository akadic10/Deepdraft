extends Node

## Persistent worker order queue over ContentRegistry's recipes. Runtime leases,
## worker/bench reservations and cargo ownership are never serialized here.
signal changed()
## Dock that shows the crafting window for this queue (Scene Decoupling Contract).
@export var dock_ui_path: NodePath
const Order = preload("res://scripts/components/WorkerCraftOrder.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
## An order that could start but finds every bench of its kind claimed. It keeps its
## turn: a busy bench is not a missing one.
const QUEUED := "Queued"
const Batch = preload("res://scripts/components/WorkshopBatch.gd")
const Sources = preload("res://scripts/components/WorkSourceTable.gd")
const CatchLog = preload("res://scripts/components/CatchLog.gd")
## A workshop's claim while a batch hangs on it to finish by itself (doc 292): no order takes it.
const HANGING := -2
var recipes: Dictionary = ContentRegistry.recipes.duplicate(true) # own copies
var sections: Dictionary = ContentRegistry.recipe_sections.duplicate(true)
var orders: Array = []
var bench_claims: Dictionary = {}
var items: ItemDropManager
var furniture: FurniturePlacementController
var max_orders := ContentRegistry.max_craft_orders
var _next_id := 1
var _dirty := false
var _elapsed := 0.0
var _leaving := false
var selection_revision := 0
var _batches := {}   # bench installed id -> true while its batch shows on it
var hanging: Dictionary = {}   # bench installed id -> WorkshopBatch left on it (doc 292)
var _hanging_sources: RefCounted   # WorkSourceTable: the hanging batches' take-down leases

func _ready() -> void:
	add_to_group("crafting_manager")
	add_to_group(SaveManager.OWNER_GROUP)
	_hanging_sources = Sources.new()
	items = ItemDropManager.find(get_tree())
	furniture = get_tree().get_first_node_in_group("furniture_controller")
	# Explicit scene reference injected when a fixture does not use that group.
	if furniture == null:
		for node in get_parent().get_children():
			if node is FurniturePlacementController: furniture = node
	if items != null: items.loose_items_changed.connect(_selection_changed)
	StockpileManager.stockpile_changed.connect(func(_key: String, _count: int): wake())
	if furniture != null: furniture.catalog_changed.connect(_selection_changed)
	TaskManager.task_completed.connect(_task_gone)
	TaskManager.task_cancelled.connect(_task_gone)
	TaskManager.task_failed.connect(func(task: Task, _reason: String): _task_gone(task))
	TaskManager.task_released.connect(_task_released)
	var dock := get_node_or_null(dock_ui_path) if not dock_ui_path.is_empty() else null
	if dock != null: dock.register_crafting_controller(self)
	wake()

func _process(delta: float) -> void:
	_show_batches()
	_elapsed += delta
	if _elapsed < .5: return
	_elapsed = 0.0
	_update_hanging()
	wake() # covers nav changes, uninstall flags and live progress labels

func wake() -> void:
	if _dirty or _leaving: return
	_dirty = true
	_refresh.call_deferred()

func _selection_changed() -> void:
	selection_revision += 1
	wake()

func _refresh() -> void:
	_dirty = false
	if _leaving or items == null or furniture == null: return
	var totals := Inventory.snapshot(items, furniture)
	var in_line := {} # workshop -> orders waiting their turn so far
	var last_lease := -1
	for order in orders.duplicate():
		if order.quantity <= 0:
			remove_order(order.id)
			continue
		if order.worker_id >= 0 and order.bench_id >= 0 and not bench_valid(order.bench_id, order.id):
			TaskManager.invalidate_dwarf_task(order.worker_id)
		if order.worker_id < 0 and order.bench_id >= 0 and not _keeps_goods(order, totals): order.release_goods()
		var reason := waiting_reason(order, totals)
		order.queue_place = 0
		if reason == QUEUED:
			in_line[order.recipe.workshop] = int(in_line.get(order.recipe.workshop, 0)) + 1
			order.queue_place = in_line[order.recipe.workshop]
		# Leases wait in posting order. One that would go before an earlier order is
		# posted again behind it, so the next free bench goes to the top-most order.
		if order.worker_id < 0 and order.lease_id >= 0 and (not reason.is_empty() or order.lease_id < last_lease):
			TaskManager.cancel_task(order.lease_id)
		if order.lease_id < 0 and reason.is_empty():
			order.lease_id = TaskManager.add_task(Task.Type.CRAFT, Vector3i.ZERO, {"order_id":order.id}, order.source_id)
		if order.worker_id < 0 and order.lease_id >= 0: last_lease = order.lease_id
	_show_batches()
	changed.emit()

## A workshop with a `batch_model` shows it only while a Worker works a batch there: the fish
## hang on the drying rack while they dry (doc 289), and an idle rack is bare.
func _show_batches() -> void:
	if furniture == null: return
	var worked := {}
	for order in orders:
		if order.worker_id < 0 or order.bench_id < 0: continue
		var agent := TaskManager.get_agent(order.worker_id)
		if is_instance_valid(agent) and agent.get_task_phase() == DwarfAgent.TaskPhase.FETCH_WORKING: worked[order.bench_id] = true
	for id: int in hanging: worked[id] = true   # and while a batch dries on it (doc 292)
	for id: int in _batches.keys():
		if worked.has(id): continue
		furniture.show_batch(id, false)
		_batches.erase(id)
	for id: int in worked:
		if _batches.has(id): continue
		furniture.show_batch(id, true)
		_batches[id] = true

## A recipe with `dry_hours` leaves its batch on the workshop (doc 292): the order that hung the
## fish is done with them, and the rack takes no other batch until a Ranger takes this one down.
func hang_batch(order) -> void:
	var bench = furniture.get_installed(order.bench_id)
	var batch = Batch.new()
	batch.installed_id = order.bench_id
	batch.origin = bench.origin_cell if bench != null else order.work_cell
	batch.recipe = order.recipe
	batch.input_key = order.timber_key if not order.timber_key.is_empty() else String(order.allowed_ingredients.front())
	batch.input_count = int(order.recipe.ingredient_count)
	batch.material_id = order.output_material_id
	batch.started = WorldClock.elapsed_days()
	_add_hanging(batch)

func _add_hanging(batch) -> void:
	var bench = furniture.get_installed(batch.installed_id)
	batch.workshop_name = String(bench.def.get("display_name", "Workshop")) if bench != null else "Workshop"
	batch.duration = float(batch.recipe.get("collect_seconds", 4.0))
	batch.stands_callback = _bench_stands.bind(batch.installed_id)
	batch.contact_callback = _bench_contact.bind(batch.installed_id)
	batch.complete_callback = _take_down.bind(batch)
	hanging[batch.installed_id] = batch
	bench_claims[batch.installed_id] = HANGING
	_hanging_sources.add(batch, batch)
	batch.ensure_lease()
	wake()

## A dry batch posts its take-down; one whose workshop went drops what hangs on it.
func _update_hanging() -> void:
	for id: int in hanging.keys():
		if not bench_usable(id): _spill(hanging[id])
		else: hanging[id].ensure_lease()

## The batch comes down beside its workshop and the Ranger's log counts the fish. Its source
## retires once the finished lease has gone.
func _take_down(dwarf_id: int, batch) -> bool:
	if batch.collected: return false
	var agent := TaskManager.get_agent(dwarf_id)
	var cell: Vector3i = agent.current_cell() if is_instance_valid(agent) else batch.origin
	items.spawn_drop(String(batch.recipe.output), int(batch.recipe.output_count), cell + Vector3i.UP, batch.material_id)
	if is_instance_valid(agent) and batch.recipe.has("catch_log"): CatchLog.add(agent.catch_log, String(batch.recipe.catch_log), int(batch.recipe.output_count))
	_drop_hanging(batch, false)
	return true

## The workshop went before its batch came down: the batch falls beside where it stood, dry
## or still fresh.
func _spill(batch) -> void:
	var dried: bool = batch.dry()
	var key: String = String(batch.recipe.output) if dried else String(batch.input_key)
	var count: int = int(batch.recipe.output_count) if dried else int(batch.input_count)
	var stands := _bench_stands(batch.installed_id)
	var cell: Vector3i = stands[0] if not stands.is_empty() else batch.origin
	if not key.is_empty() and count > 0: items.spawn_drop(key, count, cell + Vector3i.UP, batch.material_id if dried else "")
	_drop_hanging(batch, true)

func _drop_hanging(batch, cancel_lease: bool) -> void:
	batch.collected = true
	if hanging.get(batch.installed_id) == batch: hanging.erase(batch.installed_id)
	if int(bench_claims.get(batch.installed_id, 0)) == HANGING: bench_claims.erase(batch.installed_id)
	if cancel_lease: _hanging_sources.retire(batch, true)
	else: _hanging_sources.retire.call_deferred(batch, false)
	wake()

## The floor cells beside a workshop, where a dwarf stands to work it.
func _bench_stands(id: int) -> Array:
	var cells: Array = []
	var bench = furniture.get_installed(id)
	if bench == null: return cells
	for cell: Vector3i in bench.cells:
		for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var stand := cell + offset
			if NavGrid.is_walkable(stand) and not stand in bench.cells and not stand in cells: cells.append(stand)
	return cells

## Where hands reach on a workshop from `from`: its working surface toward them, as
## WorkerCraftOrder.work_surface.
func _bench_contact(from: Vector3, id: int) -> Vector3:
	var bench = furniture.get_installed(id)
	if bench == null or not is_instance_valid(bench.node): return from + Vector3(0, 1.2, 0)
	return bench_surface(bench, from)

## A workshop's working surface toward `from`. A long slab (`crafting_surface_inset`: the
## carpenter's and the mason's benches, doc 293) takes the point of its top nearest them, that far
## inside its edges, so the goods lie in front of the worker and never overhang it. Others reach
## `crafting_surface_radius` from the centre: the stump has no front, so the material faces the
## approaching worker whatever the furniture's decorative rotation.
static func bench_surface(bench, from: Vector3) -> Vector3:
	var center: Vector3 = bench.node.global_position
	var height := float(bench.def.get("crafting_surface_height", 1.0))
	if bench.def.has("crafting_surface_inset") and not bench.cells.is_empty():
		var inset := float(bench.def.crafting_surface_inset)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for cell: Vector3i in bench.cells:
			low = Vector2(minf(low.x, cell.x), minf(low.y, cell.z))
			high = Vector2(maxf(high.x, cell.x + 1), maxf(high.y, cell.z + 1))
		return Vector3(clampf(from.x, low.x + inset, high.x - inset), center.y + height, clampf(from.z, low.y + inset, high.y - inset))
	var toward := Vector3(from.x - center.x, 0, from.z - center.z).normalized()
	var reach := float(bench.def.get("crafting_surface_radius", .125))
	return center + Vector3(toward.x * reach, height, toward.z * reach)

## Units a recipe's batches will give once off their workshops: the fish drying on racks.
func batch_output(key: String) -> int:
	var count := 0
	for batch in hanging.values():
		if String(batch.recipe.output) == key: count += int(batch.recipe.output_count)
	return count

## "about 14 hours", "about an hour", "under an hour".
static func hours_text(hours: float) -> String:
	if hours < 1.0: return "under an hour"
	return "about an hour" if ceili(hours) == 1 else "about %d hours" % ceili(hours)

## A batch on its workshop in words (doc 292), {} with none: `text` for the compact line,
## `row` for the window's Drying row and `tone`.
func hanging_status(installed_id: int) -> Dictionary:
	var batch = hanging.get(installed_id)
	if batch == null: return {}
	if batch.dry():
		var output := "%d %s" % [int(batch.recipe.output_count), _plural(String(batch.recipe.output))]
		return {"text": "%s · waiting for a %s" % [output, crafter_name(batch.recipe)], "row": "Dry · %s to take down" % output, "tone": "waiting"}
	var fish := "%d %s" % [batch.input_count, _plural(batch.input_key)]
	return {"text": "Drying %s · %s left" % [fish, hours_text(batch.hours_left())], "row": "%s · %s left" % [fish, hours_text(batch.hours_left())], "tone": "fine"}

## Each batch hanging on a workshop of this section's recipes, in words: the crafting window's
## list under the queue.
func section_hanging(section_id: String) -> Array[String]:
	var lines: Array[String] = []
	var ids := hanging.keys()
	ids.sort()
	for id: int in ids:
		var batch = hanging[id]
		if String(batch.recipe.get("section", "rudimentary")) == section_id: lines.append("%s · %s" % [batch.workshop_name, hanging_status(id).row])
	return lines

func _plural(key: String) -> String:
	var definition: Dictionary = items.get_item_def(key)
	return String(definition.get("plural_name", definition.get("display_name", key))).to_lower()

## An order whose every workshop holds a batch waits for one to come down (doc 292); "" when one
## is free or none holds a batch.
func _hanging_wait(workshop: String) -> String:
	var soonest := INF
	for id: int in furniture.get_installed_ids():
		var bench = furniture.get_installed(id)
		if bench.furniture_key != workshop or not bench_usable(id): continue
		if not hanging.has(id): return ""
		soonest = minf(soonest, hanging[id].hours_left())
	if soonest == INF: return ""
	return "Waiting for a free %s%s" % [bench_name(workshop), "" if soonest <= 0.0 else " · " + hours_text(soonest)]

func queue_order(recipe_id: String, quantity: int, maintain := false, allowed: Variant = null) -> int:
	if not recipes.has(recipe_id) or quantity < 1: return -1
	var keys := allowed_ingredient_keys(recipes[recipe_id], allowed)
	quantity = mini(quantity, 99)
	if maintain:
		for order in orders:
			if order.maintain and String(order.recipe.id) == recipe_id:
				order.quantity = quantity
				set_allowed_ingredients(order.id, keys)
				wake()
				return order.id
	if orders.size() >= max_orders: return -1
	var order = Order.new()
	order.manager = self
	order.recipe = recipes[recipe_id]
	order.id = _next_id
	_next_id += 1
	order.quantity = quantity
	order.maintain = maintain
	order.allowed_ingredients = keys
	order.source_id = TaskManager.allocate_source_id()
	orders.append(order)
	TaskManager.register_work_source(order.source_id, order)
	wake()
	return order.id

func get_order(id: int):
	for order in orders:
		if order.id == id: return order
	return null

func remove_order(id: int) -> void:
	var order = get_order(id)
	if order == null: return
	orders.erase(order)
	if order.lease_id >= 0: TaskManager.cancel_task(order.lease_id)
	if order.worker_id >= 0: order.cancel_fetch(order.worker_id)
	order.release_goods()
	TaskManager.unregister_work_source(order.source_id)
	wake()

func set_paused(id: int, value: bool) -> void:
	var order = get_order(id)
	if order == null: return
	order.paused = value
	if value and order.lease_id >= 0: TaskManager.cancel_task(order.lease_id)
	# A paused order lets its goods and bench go; its progress stays.
	if value: order.release_goods()
	wake()

func set_allowed_ingredients(id: int, selected: Array) -> void:
	var order = get_order(id)
	if order == null: return
	var keys := allowed_ingredient_keys(order.recipe, selected)
	if keys == order.allowed_ingredients: return
	order.allowed_ingredients = keys
	# Applying a stricter rule takes effect even during pickup/work. The normal
	# cancellation path returns the intact logs; progress stays on the order.
	if order.lease_id >= 0 and not order.timber_key.is_empty() and order.timber_key not in keys:
		TaskManager.cancel_task(order.lease_id)
	if not order.timber_key.is_empty() and order.timber_key not in keys: order.release_goods()
	wake()

func move_order(id: int, direction: int) -> void:
	var order = get_order(id)
	if order == null or order.worker_id >= 0: return
	var index := orders.find(order)
	var next := clampi(index+direction,0,orders.size()-1)
	orders.remove_at(index)
	orders.insert(next,order)
	wake() # the refresh re-posts any lease that now jumps an earlier order

func _task_gone(task: Task) -> void:
	if task.type != Task.Type.CRAFT: return
	var order = get_order(int(task.payload.get("order_id",-1)))
	if order == null: return
	if order.lease_id == task.id: order.lease_id = -1
	if order.worker_id >= 0: order.cancel_fetch(order.worker_id)
	wake()

func _task_released(task: Task, dwarf_id: int, _reason: int) -> void:
	if task.type != Task.Type.CRAFT: return
	var order = get_order(int(task.payload.get("order_id",-1)))
	if order != null: order.cancel_fetch(dwarf_id)

func ingredient_keys(recipe: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in items.get_item_defs():
		if String(recipe.ingredient_tag) in items.get_item_def(key).get("material_tags",[]): keys.append(key)
	keys.sort()
	return keys

func allowed_ingredient_keys(recipe: Dictionary, selected: Variant = null) -> Array[String]:
	var candidates: Variant = recipe.get("default_ingredients", []) if selected == null else selected
	var result: Array[String] = []
	if not candidates is Array: return result
	for key in ingredient_keys(recipe):
		if key in candidates: result.append(key)
	return result

## How a recipe names its ingredient goods (doc 289): its `ingredient_words` (dried fish names
## fish), or timber's words for the wooden recipes.
const TIMBER_WORDS := {"noun": "wood", "units": "logs", "same": "All logs must be the same wood.",
	"pick": "Click a wood to allow it.", "carrying": "Gathering / carrying timber"}

static func ingredient_words(recipe: Dictionary) -> Dictionary:
	return recipe.get("ingredient_words", TIMBER_WORDS)

func ingredient_label(key: String) -> String:
	return String(items.get_item_def(key).get("display_name",key)).trim_suffix(" Log").trim_suffix(" Wood")

func ingredient_summary(keys: Array) -> String:
	var labels: Array[String] = []
	for key: String in keys: labels.append(ingredient_label(key))
	return ", ".join(labels)

func ingredient_available(recipe: Dictionary, totals: Dictionary, allowed: Variant = null) -> int:
	var count := 0
	for key in allowed_ingredient_keys(recipe,allowed): count += int(totals.get(key,{}).get("available",0))
	return count

## Each finished item has one wood identity. Only start a batch when one allowed
## species can supply it; don't promise the same remaining logs to two workers.
## The asking order's own logs beside its bench count, and keep their species.
func batch_ingredient_keys(recipe: Dictionary, totals: Dictionary, allowed: Array[String], exclude_order := -1) -> Array[String]:
	var keys: Array[String] = []
	var asking = get_order(exclude_order)
	var own: Dictionary = asking.held_counts().timber if asking != null else {}
	for key in allowed_ingredient_keys(recipe,allowed):
		if not own.is_empty() and not own.has(key): continue
		var available := int(totals.get(key,{}).get("available",0)) + int(own.get(key,0))
		for order in orders:
			if order.id != exclude_order and order.worker_id >= 0 and order.timber_key == key:
				available -= order.pending_timber_count()
		if available >= int(recipe.ingredient_count): keys.append(key)
	return keys

func stock_snapshot() -> Dictionary:
	return Inventory.snapshot(items, furniture)

func reserve_ingredient(recipe: Dictionary, from: Vector3i, dwarf_id: int, allowed: Array[String], order_id := -1) -> Node3D:
	return reserve_material(batch_ingredient_keys(recipe,stock_snapshot(),allowed,order_id), from, dwarf_id)

func reserve_material(keys: Array[String], from: Vector3i, dwarf_id: int) -> Node3D:
	var candidate: Node3D
	var distance := INF
	for key in keys:
		var node := items.nearest_loose_of_key(key, from, {})
		if node != null:
			var delta := items.item_floor_cell(node)-from
			var score := absi(delta.x)+absi(delta.y)+absi(delta.z)
			if score < distance: candidate = node; distance = score
	if candidate != null and items.reserve(candidate, dwarf_id): return candidate
	return StockpileManager.withdraw_matching_item(keys, from, dwarf_id)

func additional_ingredient_keys(recipe: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in recipe.get("additional_ingredients", []): keys.append(String(key))
	return keys

## No reservations while comparing workers. Keep scans bounded by the same
## deadline as navigation; storage and loose materials compete by distance.
## An order holding goods beside its bench stays there, and its next trip is for
## what is missing; with every ingredient there, the Worker lifts the last log.
func advance_worker_quote(order, from: Vector3i, query: Dictionary, deadline: int, excluded: Dictionary) -> bool:
	if query.is_empty():
		query.merge({"material_keys":order.next_ingredient_keys(), "loose":{}, "stored":{}, "final":order.final_quote(from),
			"benches":[order.bench_id] if order.holds_goods() else furniture.get_installed_ids(), "index":0, "goals":{}})
	if not query.final.is_empty():
		query.material = {} if excluded.has(query.final.cell) else query.final
	else:
		var keys: Array[String] = query.material_keys
		if not items.advance_material_quote(keys,from,query.loose,deadline,excluded,-1,"","",false): return false
		if not StockpileManager.advance_material_quote(keys,from,query.stored,deadline,excluded): return false
		var best: Dictionary = query.loose.best
		if best.is_empty() or (not query.stored.best.is_empty() and int(query.stored.distance) < int(query.loose.distance)):
			best = query.stored.best
		query.material = best
	if query.material.is_empty() or String(order.recipe.workshop).is_empty(): return true
	while int(query.index) < query.benches.size():
		if Time.get_ticks_usec() >= deadline: return false
		var id: int = query.benches[query.index]
		query.index += 1
		var bench = furniture.get_installed(id)
		if bench == null or bench.furniture_key != String(order.recipe.workshop) or not bench_valid(id, order.id): continue
		for cell: Vector3i in bench.cells:
			for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
				var stand := cell+offset
				if NavGrid.is_walkable(stand) and not query.goals.has(stand): query.goals[stand] = id
	return true

## The nearest unit of these keys within `radius` blocks of `from`, loose or stored,
## reserved for the Worker; null when none lies that near or the bounded search
## runs out. A trip's later ingredients (doc 44, "Trips").
func reserve_nearby(keys: Array[String], from: Vector3i, dwarf_id: int, radius: int, excluded: Dictionary) -> Node3D:
	var deadline := Time.get_ticks_usec() + int(TaskManager.get_config_section("supervision").get("trip_extra_budget_usec",1000))
	var loose := {}
	var stored := {}
	if not items.advance_material_quote(keys,from,loose,deadline,excluded,-1,"","",false): return null
	if not StockpileManager.advance_material_quote(keys,from,stored,deadline,excluded): return null
	var best: Dictionary = loose.best
	if best.is_empty() or (not stored.best.is_empty() and int(stored.distance) < int(loose.distance)): best = stored.best
	if best.is_empty() or int(best.distance) > radius: return null
	return reserve_material_quote(best,dwarf_id)

## A loose crate, such as a fisher's catch, is reserved whole; only the one unit the
## batch needs leaves it at pickup (WorkerCraftOrder.take_planting_item).
func reserve_material_quote(quote: Dictionary, dwarf_id: int) -> Node3D:
	if quote.has("source"): return StockpileManager.withdraw_material_quote(quote,dwarf_id)
	var node: Node3D = quote.get("node")
	if not is_instance_valid(node) or items.quantity_of(node) < 1: return null
	if items.item_key_of(node) != quote.key or items.item_floor_cell(node) != quote.cell: return null
	return node if items.reserve(node,dwarf_id) else null

## Free for this order: usable, and unclaimed or claimed by the order itself.
func bench_valid(id: int, order_id := -1) -> bool:
	if bench_claims.has(id) and int(bench_claims[id]) != order_id: return false
	return bench_usable(id)

## Installed, kept and standing on solid ground, whoever has claimed it.
func bench_usable(id: int) -> bool:
	var bench = furniture.get_installed(id)
	if bench == null or bench.flagged_uninstall or not is_instance_valid(bench.node): return false
	for cell: Vector3i in bench.cells:
		if not BlockRegistry.is_solid(WorldData.get_live_block(cell.x,cell.y,cell.z)): return false
	return true

## Whether the colony has a bench of this kind to queue for, busy or not.
func has_bench(key: String) -> bool:
	for id: int in furniture.get_installed_ids():
		var bench = furniture.get_installed(id)
		if bench.furniture_key == key and bench_usable(id) and bench.nearest_stand_target(Vector3i.ZERO).x >= 0: return true
	return false

func bench_name(key: String) -> String:
	if furniture == null: return "workbench"
	return String(furniture.get_defs().get(key, {}).get("display_name", "workbench")).to_lower()

func bench_target(key: String, from: Vector3i) -> Dictionary:
	var best := {}
	var distance := INF
	for id: int in furniture.get_installed_ids():
		var bench = furniture.get_installed(id)
		if bench.furniture_key != key or not bench_valid(id): continue
		var stand: Vector3i = bench.nearest_stand_target(from)
		if stand.x < 0: continue
		var delta := Vector3(stand-from).length_squared()
		if delta < distance:
			best = {"id":id, "stand":stand}
			distance = delta
	return best

## Whether an order with no Worker keeps the goods beside its bench (doc 44,
## "Interruption"): they still lie where they were set down, the bench stands,
## and nothing but its turn, a Worker or missing goods holds it up.
func _keeps_goods(order, totals: Dictionary) -> bool:
	if not order.holds_goods() or order.paused or not order.staged_valid() or not bench_usable(order.bench_id): return false
	if order.maintain and available_output(order, totals) >= order.quantity: return false
	return order.timber_key.is_empty() or order.timber_key in order.allowed_ingredients

## Why an order cannot start now, or "". QUEUED when it only waits its turn.
func waiting_reason(order, totals: Dictionary) -> String:
	if order.paused: return "Paused"
	if order.worker_id >= 0: return ""
	var reason := _missing_reason(order, totals)
	if not reason.is_empty(): return reason
	var workshop := String(order.recipe.workshop)
	# Goods beside a bench keep the order at that bench; it waits its turn there.
	if not workshop.is_empty() and order.holds_goods(): return "" if bench_valid(order.bench_id, order.id) else QUEUED
	return QUEUED if not workshop.is_empty() and bench_target(workshop, Vector3i.ZERO).is_empty() else ""

## What an order lacks before it could start: a stock target already met, wood,
## materials or a workbench. A busy workbench is not missing. Goods the order
## already holds beside its bench count toward it.
func _missing_reason(order, totals: Dictionary) -> String:
	if order.maintain and available_output(order, totals) >= order.quantity:
		return "Stock target met"
	var words := ingredient_words(order.recipe)
	if order.allowed_ingredients.is_empty(): return "Choose allowed " + String(words.noun)
	# recipe_waiting_reason asks with a Dictionary, which holds nothing.
	var own_id: int = order.id if order is Object else -1
	if batch_ingredient_keys(order.recipe, totals, order.allowed_ingredients, own_id).is_empty():
		var count := int(order.recipe.ingredient_count)
		var one: bool = order.allowed_ingredients.size() == 1
		if not order.recipe.has("ingredient_words"):   # timber: "Waiting for 2 Pine logs"
			if count > 1: return "Waiting for %d %s logs" % [count, ingredient_label(order.allowed_ingredients[0]) if one else "matching"]
			return "Waiting for " + ingredient_label(order.allowed_ingredients[0]) if one else "Waiting for allowed wood"
		# Others name their goods: "Waiting for 2 perch", "Waiting for 2 matching fish".
		var plural := String(items.get_item_def(order.allowed_ingredients[0]).get("plural_name", words.units)) if one else "matching " + String(words.units)
		return "Waiting for %d %s" % [count, plural]
	var own: Dictionary = order.held_counts().extras if order is Object else {}
	var extra_counts := {}
	for key in additional_ingredient_keys(order.recipe):
		extra_counts[key] = int(extra_counts.get(key,0)) + 1
		if int(totals.get(key,{}).get("available",0)) + int(own.get(key,0)) < extra_counts[key]:
			return "Waiting for " + ingredient_label(key)
	var workshop := String(order.recipe.workshop)
	if not workshop.is_empty() and not has_bench(workshop): return "Needs a " + bench_name(workshop)
	# Each section's orders wait for its own career (doc 292): Dried fish for a Ranger.
	if crafters(order.recipe).is_empty(): return "Needs a " + crafter_name(order.recipe)
	return ""

## The dwarves whose career makes a recipe's section, busy or not.
func crafters(recipe: Dictionary) -> Array[DwarfAgent]:
	var career := DwarfAssets.section_profession(String(recipe.get("section", "rudimentary")))
	var found: Array[DwarfAgent] = []
	for agent: DwarfAgent in TaskManager.get_agents():
		if is_instance_valid(agent) and agent.profession == career: found.append(agent)
	return found

## The career that makes a recipe, by name: "Worker", "Ranger".
func crafter_name(recipe: Dictionary) -> String:
	return String(DwarfAssets.profession_definition(DwarfAssets.section_profession(String(recipe.get("section", "rudimentary")))).get("display_name", "Worker"))

## Why a recipe could not be made with these woods, or "" when it could: the crafting
## window's ready and missing recipes (doc 261). A busy bench only means the order queues.
func recipe_waiting_reason(recipe: Dictionary, allowed: Array[String], totals: Dictionary) -> String:
	return _missing_reason({"maintain": false, "quantity": 1, "allowed_ingredients": allowed, "recipe": recipe}, totals)

## "Next in line", "2nd in line": an order's turn at a busy bench of its kind.
static func turn_label(place: int) -> String:
	if place <= 1: return "Next in line"
	var suffix := "th"
	if place % 100 not in [11, 12, 13] and place % 10 in [1, 2, 3]: suffix = ["st", "nd", "rd"][place % 10 - 1]
	return "%d%s in line" % [place, suffix]

func status(order, totals: Dictionary) -> String:
	var reason := waiting_reason(order, totals)
	if reason == QUEUED:
		var wait := _hanging_wait(String(order.recipe.workshop))
		return wait if not wait.is_empty() else turn_label(order.queue_place)
	if not reason.is_empty(): return reason
	if order.worker_id >= 0:
		var agent = TaskManager.get_agent(order.worker_id)
		if is_instance_valid(agent) and agent.get_task_phase() == agent.TaskPhase.FETCH_WORKING:
			return "Crafting · %d%%" % roundi(100.0*order.progress/float(order.recipe.work_seconds))
		return String(ingredient_words(order.recipe).carrying) if additional_ingredient_keys(order.recipe).is_empty() else "Gathering / carrying materials"
	var task := TaskManager.get_task(order.lease_id)
	return "Waiting for a reachable route" if task != null and task.blocked_count > 0 else "Waiting for a " + crafter_name(order.recipe)

func crafting_count(item_key: String) -> int:
	var count := 0
	var totals := stock_snapshot()
	for order in orders:
		if String(order.recipe.output) != item_key: continue
		var batch := int(order.recipe.output_count)
		if order.maintain:
			var missing := maxi(0,order.quantity-available_output(order, totals))
			count += maxi(ceili(float(missing)/batch)*batch,batch if order.worker_id>=0 else 0)
		else: count += order.quantity * batch
	return count + batch_output(item_key)

func save_section_key() -> String: return "worker_crafting"
func save_restore_priority() -> int: return 70
func serialize_state() -> Dictionary:
	var entries := []
	for order in orders: entries.append(order.serialize())
	var left := []
	for batch in hanging.values(): left.append(batch.serialize())
	return {"orders":entries, "batches":left}

func restore_state(state: Dictionary) -> void:
	for order in orders.duplicate(): remove_order(order.id)
	for batch in hanging.values(): _drop_hanging(batch, true)
	var next_unused := _next_id
	for entry in state.get("orders",[]):
		if not entry is Dictionary: continue
		_next_id = int(entry.get("id",_next_id))
		# An empty or invalid list stays empty; never silently allow more wood.
		var id := queue_order(String(entry.get("recipe","")),int(entry.get("quantity",0)),bool(entry.get("maintain",false)),entry.allowed_ingredients)
		var order = get_order(id)
		next_unused = maxi(next_unused,_next_id)
		order.paused = bool(entry.get("paused",false))
		order.progress = clampf(float(entry.get("progress",0)),0,float(order.recipe.work_seconds))
		order.restore_goods(entry.get("staged",[]),int(entry.get("bench",-1)))
	_next_id = next_unused
	# Batches left on their workshops (doc 292); one whose workshop is gone drops on the next tick.
	for entry in state.get("batches",[]):
		if not entry is Dictionary or not recipes.has(String(entry.get("recipe",""))): continue
		var batch = Batch.new()
		batch.installed_id = int(entry.get("bench",-1))
		batch.origin = SaveManager.unpack_v3i(entry.get("origin",[]))
		batch.recipe = recipes[String(entry.recipe)]
		batch.input_key = String(entry.get("input",""))
		batch.input_count = int(entry.get("inputs",0))
		batch.material_id = String(entry.get("material",""))
		batch.started = float(entry.get("started",0.0))
		_add_hanging(batch)
	wake()

func _exit_tree() -> void:
	_leaving = true
	for order in orders.duplicate(): remove_order(order.id)
	_hanging_sources.retire_all(true)

func available_output(order, totals: Dictionary) -> int:
	var key := String(order.recipe.output)
	var total := int(totals.get(key, {}).get("available", 0))
	# Fish drying on a rack count toward a Keep target already (doc 292).
	if not order.recipe.has("material_group") or not is_instance_valid(furniture): return total + batch_output(key)
	var furniture_key := String(order.recipe.get("furniture", ""))
	var variants: Dictionary = furniture.get_material_stock(furniture_key) if not furniture_key.is_empty() else furniture.spare_materials(key)
	var count := 0
	var seen := {}
	for ingredient: String in order.allowed_ingredients:
		var id := CraftMaterials.from_ingredient(ingredient)
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		count += int(variants.get(id, 0))
	return mini(count, total)
