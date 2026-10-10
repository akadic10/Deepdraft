extends RefCounted

## A personal appointment, not a colony job another dwarf can claim. The kit
## stays a real item: loose/reserved -> carried at contact -> equipped child.
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const CarryPose = preload("res://scripts/components/DwarfCarryPose.gd")
var agent: DwarfAgent
var pending_role := ""
var message := ""
var equipped: Node3D
var item: Node3D
var stage := ""
var _items: ItemDropManager
var _loose := {}
var _stored := {}
var _excluded := {}
var _quote := {}
var _route := {}
var _elapsed := 0.0
var _lifted := false
var _origin := Transform3D.IDENTITY
var _yaw := 0.0
var _target_yaw := 0.0

func _init(owner: DwarfAgent) -> void:
	agent = owner

func active() -> bool:
	return not pending_role.is_empty()

func tool_key() -> String:
	return String(equipped.get_meta("item_key", "")) if is_instance_valid(equipped) else ""

func items() -> ItemDropManager:
	if not is_instance_valid(_items) and agent.is_inside_tree():
		_items = agent.get_tree().get_first_node_in_group("item_drop_manager") as ItemDropManager
	return _items

func blocked_reason(role: String) -> String:
	var required := DwarfAssets.profession_tool(role)
	if required.is_empty(): return ""
	if agent.is_sleeping(): return "Let this dwarf wake before collecting a tool."
	if agent.needs_ladder_exit() or agent._ladder_exiting: return "Let this dwarf reach solid ground first."
	if items() == null: return "No tools are available."
	if int(Inventory.snapshot(_items, null).get(required, {}).get("available", 0)) < 1:
		return "Craft a spare %s at the crude workbench." % _items.get_item_def(required).get("display_name", "tool")
	return ""

func request(role: String) -> bool:
	message = blocked_reason(role)
	if not message.is_empty(): return false
	agent._release_for_assignment_change()
	cancel("", false)
	if agent._idle_behavior != null: agent._idle_behavior.cancel()
	agent.stop_walking()
	_clear_search()
	_excluded.clear()
	pending_role = role
	stage = "finding"
	message = "Finding a starter tool."
	TaskManager.notify_dwarf_unavailable(agent.dwarf_id)
	return true

func tick(delta: float) -> void:
	if stage == "finding":
		_find_tool()
		return
	if not is_instance_valid(item) or (not _lifted and not _items.reserved_by(item, agent.dwarf_id)):
		cancel("Promotion cancelled: the tool is no longer available.")
		return
	if stage == "walking":
		if agent._move_path.is_empty() or agent._ladder_path_revision != NavGrid.ladder_revision \
				or not NavGrid.is_navigable(agent._move_path[agent._move_index]):
			cancel("Promotion cancelled: the route to the tool changed.")
			return
		agent._follow_path(delta * WorldClock.speed)
	elif stage == "pickup":
		if not _lifted and not agent.current_cell() in StorageComponent.ground_access_cells(_items.item_floor_cell(item)):
			cancel("Promotion cancelled: the tool moved out of reach.")
			return
		_pickup(delta * WorldClock.speed)

func _find_tool() -> void:
	if items() == null:
		cancel("Promotion cancelled: no tools are available.")
		return
	var deadline := Time.get_ticks_usec() + 2000
	var keys: Array[String] = [DwarfAssets.profession_tool(pending_role)]
	if _quote.is_empty():
		if not _items.advance_material_quote(keys, agent.current_cell(), _loose, deadline, _excluded): return
		if not StockpileManager.advance_material_quote(keys, agent.current_cell(), _stored, deadline, _excluded): return
		_quote = _loose.best
		if _quote.is_empty() or (not _stored.best.is_empty() and int(_stored.distance) < int(_loose.distance)):
			_quote = _stored.best
		if _quote.is_empty():
			cancel("Promotion cancelled: no unreserved, reachable starter tool. Craft one or clear a path.")
			return
	var goals := {}
	for cell in StorageComponent.ground_access_cells(_quote.cell):
		if NavGrid.is_walkable(cell): goals[cell] = true
	var result := NavGrid.ProbeResult.UNREACHABLE
	if not goals.is_empty():
		result = NavGrid.advance_reachability(_route, agent.current_cell(), goals.keys()[0], 128, deadline, false, goals)
	if result == NavGrid.ProbeResult.SEARCHING: return
	if result == NavGrid.ProbeResult.UNREACHABLE:
		_excluded[_quote.cell] = true
		_clear_search()
		return
	if _quote.has("source"):
		item = StockpileManager.withdraw_material_quote(_quote, agent.dwarf_id)
	else:
		var candidate: Node3D = _quote.get("node")
		if is_instance_valid(candidate) and _items.item_key_of(candidate) == keys[0] and _items.quantity_of(candidate) == 1 \
				and _items.item_floor_cell(candidate) == _quote.cell and _items.reserve(candidate, agent.dwarf_id):
			item = candidate
	if not is_instance_valid(item):
		_clear_search() # Another appointment/hauler claimed this quote first.
		return
	stage = "walking"
	message = "Collecting %s before promotion." % _items.get_item_def(keys[0]).get("display_name", "starter tool")
	# Reuse the checked route, rather than performing a second unbounded search.
	agent._move_path = _route.path.duplicate()
	agent._move_index = 0
	agent._ladder_path_revision = NavGrid.ladder_revision
	agent._walk_cycle = 0.0
	agent._shortcut_timer = 0.0
	_clear_search()

func walk_finished(success: bool) -> void:
	if stage != "walking": return
	if not success or not is_instance_valid(item) or not agent.current_cell() in StorageComponent.ground_access_cells(_items.item_floor_cell(item)):
		cancel("Promotion cancelled: the route to the tool was interrupted.")
		return
	stage = "pickup"
	_elapsed = 0.0
	_origin = item.global_transform
	_yaw = agent.rotation.y
	var toward := item.global_position - agent.global_position
	_target_yaw = atan2(toward.x, toward.z)
	agent._reset_part_offsets()

func _pickup(delta: float) -> void:
	var duration := maxf(.05, float(TaskManager.get_config_section("hauling").get("pickup_time_s", .75)))
	_elapsed += delta
	var phase := minf(1.0, _elapsed / duration)
	agent.rotation.y = lerp_angle(_yaw, _target_yaw, smoothstep(0.0, .28, phase))
	if not _lifted and phase >= CarryPose.CONTACT_PHASE:
		var key := _items.take(item)
		if key.is_empty():
			cancel("Promotion cancelled: the tool could not be collected.")
			return
		agent.add_child(item)
		agent._carried_entries.append([item, key])
		_lifted = true
	agent._carry_pose.pickup(phase, item, agent.global_transform.affine_inverse() * _origin, agent._carried_entries, _lifted)
	if phase < 1.0: return
	var role := pending_role
	return_tool()
	equipped = item
	equipped.set_meta("equipped", true)
	equipped.hide()
	agent._carried_entries = []
	agent._carry_pose.clear_items()
	item = null
	_lifted = false
	pending_role = ""
	stage = ""
	agent._reset_part_offsets()
	agent._complete_profession_change(role)
	message = "%s is now a %s." % [agent.dwarf_name, DwarfAssets.profession_definition(role).display_name]
	_items.loose_items_changed.emit()
	TaskManager.notify_dwarf_idle(agent.dwarf_id)

func cancel(reason := "Promotion cancelled.", resume := true) -> void:
	if not active(): return
	pending_role = ""
	stage = "" # Clear before stop_walking emits its callback.
	if is_instance_valid(item) and is_instance_valid(items()):
		if _lifted:
			agent._drop_carried_at_feet()
		else:
			_items.unreserve(item, agent.dwarf_id)
	item = null
	_lifted = false
	_clear_search()
	_excluded.clear()
	agent.stop_walking()
	agent._reset_part_offsets()
	message = reason
	if resume and not agent.is_sleeping(): TaskManager.notify_dwarf_idle(agent.dwarf_id)

func return_tool() -> void:
	if not is_instance_valid(equipped): return
	equipped.remove_meta("equipped")
	items().drop_loose(equipped, agent.current_cell())
	equipped = null

func _clear_search() -> void:
	_loose = {}
	_stored = {}
	_quote = {}
	_route = {}

func serialize() -> Dictionary:
	return {"tool": tool_key(), "pending_role": pending_role}

func restore(state: Dictionary) -> void:
	var key := String(state.get("tool", ""))
	if not key.is_empty() and items() != null:
		equipped = _items.spawn_reserved(key, agent.current_cell(), agent.dwarf_id)
		if is_instance_valid(equipped):
			_items.take(equipped)
			agent.add_child(equipped)
			equipped.set_meta("equipped", true)
			equipped.hide()
	pending_role = String(state.get("pending_role", ""))
	if active():
		stage = "finding"
		message = "Finding a starter tool."

func release_reservation() -> void:
	# Scene teardown destroys owned children; never spawn/drop save copies here.
	if is_instance_valid(item) and is_instance_valid(_items) and not _lifted:
		_items.unreserve(item, agent.dwarf_id)
