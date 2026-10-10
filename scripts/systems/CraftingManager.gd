extends Node

## Scene-owned recipe registry and persistent order queue. Runtime leases,
## worker/bench reservations and cargo ownership are never serialized here.
signal changed()
const Order = preload("res://scripts/components/WorkerCraftOrder.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const DATA := "res://data/workshops/worker_crafting.json"
var recipes: Dictionary = {}
var sections: Dictionary = {}
var orders: Array = []
var bench_claims: Dictionary = {}
var items: ItemDropManager
var furniture: FurniturePlacementController
var max_orders := 64
var _next_id := 1
var _dirty := false
var _elapsed := 0.0
var _leaving := false
var selection_revision := 0

func _ready() -> void:
	add_to_group("crafting_manager")
	add_to_group(SaveManager.OWNER_GROUP)
	_load_definitions()
	items = get_tree().get_first_node_in_group("item_drop_manager")
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
	var dock := get_tree().get_first_node_in_group("command_dock")
	if dock != null: dock.register_crafting_controller(self)
	wake()

func _load_definitions() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not raw is Dictionary: return
	max_orders = int(raw.get("max_orders",64))
	for section: Dictionary in raw.get("sections",[]):
		sections[String(section.id)] = section
	for recipe: Dictionary in raw.get("recipes",[]):
		# One selectable timber unit, plus optional fixed single-unit materials.
		if int(recipe.get("ingredient_count",0)) != 1 or float(recipe.get("work_seconds",0)) <= 0:
			push_error("Unsupported Worker recipe: " + str(recipe.get("id")))
			continue
		recipes[String(recipe.id)] = recipe

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .5: return
	_elapsed = 0.0
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
	for order in orders.duplicate():
		if order.quantity <= 0:
			remove_order(order.id)
			continue
		if order.worker_id >= 0 and order.bench_id >= 0 and not bench_valid(order.bench_id, order.id):
			TaskManager.invalidate_dwarf_task(order.worker_id)
		var reason := waiting_reason(order, totals)
		if order.worker_id < 0 and not reason.is_empty() and order.lease_id >= 0:
			TaskManager.cancel_task(order.lease_id)
		if order.lease_id < 0 and reason.is_empty():
			order.lease_id = TaskManager.add_task(Task.Type.CRAFT, Vector3i.ZERO, {"order_id":order.id}, order.source_id)
	changed.emit()

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
	TaskManager.unregister_work_source(order.source_id)
	wake()

func set_paused(id: int, value: bool) -> void:
	var order = get_order(id)
	if order == null: return
	order.paused = value
	if value and order.lease_id >= 0: TaskManager.cancel_task(order.lease_id)
	wake()

func set_allowed_ingredients(id: int, selected: Array) -> void:
	var order = get_order(id)
	if order == null: return
	var keys := allowed_ingredient_keys(order.recipe, selected)
	if keys == order.allowed_ingredients: return
	order.allowed_ingredients = keys
	# Applying a stricter rule takes effect even during pickup/work. The normal
	# cancellation path returns the intact log; progress stays on the order.
	if order.lease_id >= 0 and is_instance_valid(order.item) \
			and items.item_key_of(order.item) not in keys \
			and items.item_key_of(order.item) not in additional_ingredient_keys(order.recipe):
		TaskManager.cancel_task(order.lease_id)
	wake()

func move_order(id: int, direction: int) -> void:
	var order = get_order(id)
	if order == null or order.worker_id >= 0: return
	var index := orders.find(order)
	var next := clampi(index+direction,0,orders.size()-1)
	orders.remove_at(index)
	orders.insert(next,order)
	# Re-post unassigned leases in the visible queue order.
	for other in orders:
		if other.worker_id < 0 and other.lease_id >= 0: TaskManager.cancel_task(other.lease_id)
	wake()

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

func stock_snapshot() -> Dictionary:
	return Inventory.snapshot(items, furniture)

func reserve_ingredient(recipe: Dictionary, from: Vector3i, dwarf_id: int, allowed: Array[String]) -> Node3D:
	return reserve_material(allowed_ingredient_keys(recipe,allowed), from, dwarf_id)

func reserve_material(keys: Array[String], from: Vector3i, dwarf_id: int) -> Node3D:
	var candidate: Node3D
	var distance := INF
	for key in keys:
		var node := items.nearest_loose_of_key(key, from, {})
		if node != null and items.quantity_of(node) == 1:
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
func advance_worker_quote(order, from: Vector3i, query: Dictionary, deadline: int, excluded: Dictionary) -> bool:
	if query.is_empty(): query.merge({"loose":{}, "stored":{}, "benches":furniture._installed.keys(), "index":0, "goals":{}})
	var keys: Array[String] = additional_ingredient_keys(order.recipe)
	if keys.is_empty(): keys = order.allowed_ingredients
	else: keys = [keys[0]]
	if not items.advance_material_quote(keys,from,query.loose,deadline,excluded): return false
	if not StockpileManager.advance_material_quote(keys,from,query.stored,deadline,excluded): return false
	var best: Dictionary = query.loose.best
	if best.is_empty() or (not query.stored.best.is_empty() and int(query.stored.distance) < int(query.loose.distance)):
		best = query.stored.best
	query.material = best
	if best.is_empty() or String(order.recipe.workshop).is_empty(): return true
	while int(query.index) < query.benches.size():
		if Time.get_ticks_usec() >= deadline: return false
		var id: int = query.benches[query.index]
		query.index += 1
		var bench = furniture._installed.get(id)
		if bench == null or bench.furniture_key != String(order.recipe.workshop) or not bench_valid(id): continue
		for cell: Vector3i in bench.cells:
			for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
				var stand := cell+offset
				if NavGrid.is_walkable(stand) and not query.goals.has(stand): query.goals[stand] = id
	return true

func reserve_material_quote(quote: Dictionary, dwarf_id: int) -> Node3D:
	if quote.has("source"): return StockpileManager.withdraw_material_quote(quote,dwarf_id)
	var node: Node3D = quote.get("node")
	if not is_instance_valid(node) or items.quantity_of(node) != 1: return null
	if items.item_key_of(node) != quote.key or items.item_floor_cell(node) != quote.cell: return null
	return node if items.reserve(node,dwarf_id) else null

func bench_valid(id: int, owner := -1) -> bool:
	var bench = furniture._installed.get(id)
	if bench == null or bench.flagged_uninstall or not is_instance_valid(bench.node): return false
	if bench_claims.has(id) and int(bench_claims[id]) != owner: return false
	for cell: Vector3i in bench.cells:
		if not BlockRegistry.is_solid(NavGrid._block_id(cell.x,cell.y,cell.z)): return false
	return true

func bench_target(key: String, from: Vector3i) -> Dictionary:
	var best := {}
	var distance := INF
	for id: int in furniture._installed:
		var bench = furniture._installed[id]
		if bench.furniture_key != key or not bench_valid(id): continue
		var stand: Vector3i = bench.nearest_stand_target(from)
		if stand.x < 0: continue
		var delta := Vector3(stand-from).length_squared()
		if delta < distance:
			best = {"id":id, "stand":stand}
			distance = delta
	return best

func waiting_reason(order, totals: Dictionary) -> String:
	if order.paused: return "Paused"
	if order.worker_id >= 0: return ""
	if order.maintain and int(totals.get(String(order.recipe.output),{}).get("available",0)) >= order.quantity:
		return "Stock target met"
	if order.allowed_ingredients.is_empty(): return "Choose allowed wood"
	if ingredient_available(order.recipe, totals, order.allowed_ingredients) < 1:
		return "Waiting for " + ingredient_label(order.allowed_ingredients[0]) if order.allowed_ingredients.size()==1 else "Waiting for allowed wood"
	var extra_counts := {}
	for key in additional_ingredient_keys(order.recipe):
		extra_counts[key] = int(extra_counts.get(key,0)) + 1
		if int(totals.get(key,{}).get("available",0)) < extra_counts[key]:
			return "Waiting for " + ingredient_label(key)
	if not String(order.recipe.workshop).is_empty() and bench_target(String(order.recipe.workshop),Vector3i.ZERO).is_empty():
		return "Waiting for a free workbench"
	return ""

func status(order, totals: Dictionary) -> String:
	var reason := waiting_reason(order, totals)
	if not reason.is_empty(): return reason
	if order.worker_id >= 0:
		var agent = TaskManager._agents.get(order.worker_id)
		if is_instance_valid(agent) and agent._task_phase == agent.TaskPhase.FETCH_WORKING:
			return "Crafting · %d%%" % roundi(100.0*order.progress/float(order.recipe.work_seconds))
		return "Gathering / carrying timber" if additional_ingredient_keys(order.recipe).is_empty() else "Gathering / carrying materials"
	var task := TaskManager.get_task(order.lease_id)
	return "Waiting for a reachable route" if task != null and task.blocked_count > 0 else "Waiting for a Worker"

func crafting_count(item_key: String) -> int:
	var count := 0
	var totals := stock_snapshot()
	for order in orders:
		if String(order.recipe.output) != item_key: continue
		var batch := int(order.recipe.output_count)
		if order.maintain:
			var missing := maxi(0,order.quantity-int(totals.get(item_key,{}).get("available",0)))
			count += maxi(ceili(float(missing)/batch)*batch,batch if order.worker_id>=0 else 0)
		else: count += order.quantity * batch
	return count

func save_section_key() -> String: return "worker_crafting"
func save_restore_priority() -> int: return 70
func serialize_state() -> Dictionary:
	var entries := []
	for order in orders: entries.append(order.serialize())
	return {"orders":entries}

func restore_state(state: Dictionary) -> void:
	for order in orders.duplicate(): remove_order(order.id)
	for entry in state.get("orders",[]):
		if not entry is Dictionary: continue
		# Missing field in a pre-filter save adopts the conservative recipe default.
		# An explicit empty/invalid list stays empty; never silently allow more wood.
		var id := queue_order(String(entry.get("recipe","")),int(entry.get("quantity",0)),bool(entry.get("maintain",false)),entry.get("allowed_ingredients"))
		var order = get_order(id)
		if order == null: continue
		order.paused = bool(entry.get("paused",false))
		order.progress = clampf(float(entry.get("progress",0)),0,float(order.recipe.work_seconds))
	wake()

func _exit_tree() -> void:
	_leaving = true
	for order in orders.duplicate(): remove_order(order.id)
