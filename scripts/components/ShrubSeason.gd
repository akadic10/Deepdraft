extends RefCounted

## Pure crop rules. The owner handles leases, rewards and visuals. A saved cycle
## identifies a harvest, not elapsed frames; reloading cannot refresh berries.
static func cycle() -> String:
	return "%d:%s" % [WorldClock.year, WorldClock.season]


static func available(definition: Dictionary, state: Dictionary) -> bool:
	return not bool(state.get("removed", false)) and not is_young(definition, state) and WorldClock.season in definition.harvest.seasons \
		and String(state.get("harvested_cycle", "")) != cycle()


static func model(definition: Dictionary, state: Dictionary) -> String:
	if is_young(definition, state): return String(definition.young_models[WorldClock.season])
	if not available(definition, state) and definition.picked_models.has(WorldClock.season):
		return String(definition.picked_models[WorldClock.season])
	return String(definition.seasonal_models[WorldClock.season])


static func grown_days(definition: Dictionary, state: Dictionary) -> float:
	if not state.has("planted_at"): return float(definition.growth_days)
	return float(state.get("growth_credit", 0)) + WorldClock.seasonal_days_between(
		float(state.planted_at), WorldClock.elapsed_days(), definition.planting.seasonal_growth)


static func is_young(definition: Dictionary, state: Dictionary) -> bool:
	return state.has("planted_at") and grown_days(definition, state) + .000001 < float(definition.growth_days)


static func restore(raw: Dictionary, definition: Dictionary) -> Dictionary:
	var action := String(raw.get("action", "clear"))
	if action not in ["harvest", "clear", "uproot"]: action = "clear"
	var duration := float(definition.harvest.work_seconds if action == "harvest" else definition.transplant.uproot_seconds if action == "uproot" else definition.clearing.work_seconds)
	return {"action": action, "uproot_work_seconds": clampf(float(raw.get("uproot_work_seconds", 0)), 0, float(definition.transplant.uproot_seconds)), "harvested_cycle": String(raw.get("harvested_cycle", "")),
		"harvest_work_seconds": clampf(float(raw.get("harvest_work_seconds", 0)), 0, float(definition.harvest.work_seconds)),
		"clear_work_seconds": clampf(float(raw.get("clear_work_seconds", 0)), 0, float(definition.clearing.work_seconds)),
		"work_seconds": clampf(float(raw.get("work_seconds", 0)), 0, duration)}
