extends RefCounted

## A dwarf's health (doc 41 "Health"), tuned by `health` in task_config.json: whole hit points
## from the dwarf's Toughness, healing a share of the maximum each game hour (more asleep),
## its level (healthy, hurt, badly_hurt) and the word for it, and the Injured thought while
## badly hurt. Nothing in
## the world hurts a dwarf yet; DEV: hurt a dwarf does, and health never drops below
## `minimum`. A save keeps what is left only while the dwarf is hurt.
const HitPoints = preload("res://scripts/components/HitPoints.gd")
const Wording = preload("res://scripts/components/Wording.gd")
var config: Dictionary
var hit_points := HitPoints.new()


func _init() -> void:
	config = TaskManager.get_config_section("health")
	hit_points.minimum = float(config.get("minimum", 1))


## The maximum from the stat `config.stat` names; full, or what `saved` holds (a hurt
## dwarf's save).
func setup(stats: Dictionary, saved := -1.0) -> void:
	var average := int(DwarfAssets.get_stat_data().get("average", 3))
	var step := int(stats.get(String(config.get("stat", "")), average))
	hit_points.maximum = maxf(1.0, float(config.get("base_hit_points", 100)) + (step - average) * float(config.get("per_step", 0)))
	hit_points.current = hit_points.maximum if saved < 0.0 else clampf(saved, minf(hit_points.minimum, hit_points.maximum), hit_points.maximum)


## Heals for `hours` game hours, faster asleep.
func clock_tick(hours: float, asleep: bool) -> void:
	if hours <= 0.0 or hit_points.full(): return
	var rate := float(config.get("heal_asleep_per_hour" if asleep else "heal_awake_per_hour", 0.0))
	hit_points.heal(hit_points.maximum * rate * hours)


## Takes `amount` hit points, never below the minimum; returns what was taken.
func hurt(amount: float) -> float:
	return hit_points.hurt(amount)


## How hurt the dwarf is, by the share left: "healthy", "hurt" or "badly_hurt". Logic and
## colours read this code; word() says it.
func level() -> String:
	if hit_points.share() < float(config.get("badly_hurt_below", 0.5)): return "badly_hurt"
	if hit_points.share() < float(config.get("hurt_below", 0.75)): return "hurt"
	return "healthy"


## The level in words (task_config.json, health.words): Healthy, Hurt or Badly hurt.
func word() -> String:
	return Wording.of(config.get("words", {}), level())


func badly_hurt() -> bool:
	return level() == "badly_hurt"


## The Injured thought's happiness cost while Badly hurt.
func mood_penalty() -> float:
	return float(config.get("injured_mood_penalty", 0.0)) if badly_hurt() else 0.0


## For the readouts: whole points, the maximum, the share left, the level (a code) and its
## word, and whether the dwarf is hurt enough to show it (hurt or badly hurt).
func describe() -> Dictionary:
	var now := level()
	return {"points": hit_points.points(), "maximum": roundi(hit_points.maximum), "share": hit_points.share(),
		"level": now, "word": word(), "hurt": now != "healthy"}


## What a save keeps: the hit points left, or -1 while full (nothing to save).
func saved_points() -> float:
	return -1.0 if hit_points.full() else hit_points.current
