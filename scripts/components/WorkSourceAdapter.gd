extends RefCounted

## Shared source contract around the existing authoritative owners. Identity is
## based on saved source coordinates/IDs, never on an Object instance ID.
static func locator(source: Object, fallback: int) -> String:
	if not is_instance_valid(source): return "synthetic:%d" % fallback
	var fields := {}
	for property: Dictionary in source.get_property_list(): fields[String(property.name)] = true
	var parts: Array[String] = [source.get_script().resource_path]
	# Prefer saved IDs. A ladder's current work origin moves up each section,
	# but all sections still belong to the same player order.
	for key: String in ["zone_id","ghost_id","installed_id","id"]:
		if fields.has(key) and int(source.get(key))>0:
			return "|".join(parts)+"|%s=%s"%[key,str(source.get(key))]
	for key: String in ["origin", "origin_cell", "main_cell", "cell", "cells", "task_type"]:
		if fields.has(key): parts.append("%s=%s" % [key, str(source.get(key))])
	if parts.size() == 1: parts.append("source=%d" % fallback)
	return "|".join(parts)

static func label(source: Object) -> String:
	if not is_instance_valid(source): return "Development work"
	if source.has_method("display_name"): return String(source.display_name())
	return source.get_script().resource_path.get_file().get_basename()

static func waiting_reason(source: Object) -> String:
	if not is_instance_valid(source): return "Source removed"
	if source is StorageComponent:
		return "Waiting for accepted goods needing storage" if source._has_any_room() else "Storage is full"
	if source is FurnitureGhostComponent and not source.item_available(): return "Waiting for matching supplies"
	if source.has_method("work_waiting_reason"): return String(source.work_waiting_reason())
	return "Waiting for eligible worker or work"

static func valid_commit(source: Object, family: String) -> bool:
	if not is_instance_valid(source): return false
	if family == "fetch" and source.has_method("can_complete_build"): return bool(source.can_complete_build())
	return true

static func claimed_workers(source: Object) -> Array:
	if source is StorageComponent: return source._pulls.keys()
	if source is FurnitureGhostComponent: return source._fetches.keys()
	if source is MiningZoneComponent: return source.reserved.values()
	if source.get_script().resource_path.ends_with("TreeFellingComponent.gd"):
		return [source.reserved_by] if source.reserved_by>=0 else []
	if source.get_script().resource_path.ends_with("WorkerCraftOrder.gd"):
		return [source.worker_id] if source.worker_id>=0 else []
	return []
