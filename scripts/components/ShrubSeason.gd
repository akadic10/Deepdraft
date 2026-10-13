extends RefCounted

## Pure crop rules. The owner handles leases, rewards and visuals. Regrowth
## integrates planted time in eligible seasons, never real time or load count.
static func cycle() -> String:
	return "%d:%s" % [WorldClock.year, WorldClock.season]


static func available(definition: Dictionary, state: Dictionary) -> bool:
	return not bool(state.get("removed", false)) and not is_young(definition, state) and WorldClock.season in definition.harvest.seasons \
		and regrow_remaining(definition, state) <= 0.000001


static func regrow_progress(definition: Dictionary, state: Dictionary) -> float:
	var started := float(state.get("regrow_started_at", -1.0))
	if started < 0.0: return float(definition.harvest.regrow_days)
	var credit := float(state.get("regrow_credit", 0.0))
	if bool(state.get("packed", false)) or bool(state.get("removed", false)): return credit
	var rates := {"spring":0.0,"summer":0.0,"autumn":0.0,"winter":0.0}
	for season: String in definition.harvest.seasons: rates[season] = 1.0
	return credit + WorldClock.seasonal_days_between(started,WorldClock.elapsed_days(),rates)


static func regrow_remaining(definition: Dictionary, state: Dictionary) -> float:
	return maxf(0.0,float(definition.harvest.regrow_days)-regrow_progress(definition,state))


static func pause_regrowth(definition: Dictionary, state: Dictionary) -> void:
	if float(state.get("regrow_started_at", -1.0)) < 0.0: return
	state.regrow_credit = minf(float(definition.harvest.regrow_days),regrow_progress(definition,state))
	state.regrow_started_at = WorldClock.elapsed_days()


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
		"regrow_started_at": float(raw.get("regrow_started_at", -1.0)),
		"regrow_credit": clampf(float(raw.get("regrow_credit", 0.0)),0.0,float(definition.harvest.regrow_days)),
		"harvest_work_seconds": clampf(float(raw.get("harvest_work_seconds", 0)), 0, float(definition.harvest.work_seconds)),
		"clear_work_seconds": clampf(float(raw.get("clear_work_seconds", 0)), 0, float(definition.clearing.work_seconds)),
		"work_seconds": clampf(float(raw.get("work_seconds", 0)), 0, duration)}
