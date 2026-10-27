extends Node

## The dock's live counts (doc 23, "Counts"): what waits on you. Colony counts the dwarves
## with nothing to do, in hay, once one has waited a few game minutes, so a dwarf between
## two jobs never flicks it. Place counts what is ready to place, in moss. A count shows
## only when it isn't zero, and its hover card says what it counts. Colony refreshes every
## second, Place every five.
const Inspection = preload("res://scripts/components/DwarfInspection.gd")
const REFRESH_SECONDS := 1.0
const PLACE_EVERY := 5   # Place's stock is costlier to add up and rarely changes: every 5 s
const IDLE_WAIT_DAYS := 5.0 / (24.0 * 60.0)   # five game minutes: five seconds at 1×

var buttons: Dictionary = {}   # the dock's buttons by target
var furniture: Node = null   # the placement controller, once it registers
var _idle_since: Dictionary = {}   # dwarf → the game day it was first seen idle
var _elapsed := 0.0
var _ticks := 0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS: return
	_elapsed = 0.0
	_ticks += 1
	_refresh_colony()
	if _ticks % PLACE_EVERY == 0: _refresh_place()


func refresh() -> void:
	_refresh_colony()
	_refresh_place()


func _refresh_colony() -> void:
	var idle := idle_dwarves()
	_show("colony", idle, "waiting", "1 dwarf is idle" if idle == 1 else "%d dwarves are idle" % idle)


func _refresh_place() -> void:
	var ready := ready_to_place()
	_show("place", ready, "fine", "1 item is ready to place" if ready == 1 else "%d items are ready to place" % ready)


## Dwarves the roster files under Idle (no work, no need to see to) for at least
## IDLE_WAIT_DAYS of game time; a paused game holds the count.
func idle_dwarves() -> int:
	var director := get_tree().get_first_node_in_group("dwarf_director")
	if director == null: return 0
	var now := WorldClock.elapsed_days()
	var seen := {}
	var count := 0
	for agent: DwarfAgent in director.get_roster():
		if not is_instance_valid(agent) or Inspection.roster_group(agent) != "idle": continue
		seen[agent] = true
		# A load can move the clock back; the wait starts again from there.
		if not _idle_since.has(agent) or float(_idle_since[agent]) > now: _idle_since[agent] = now
		if now - float(_idle_since[agent]) >= IDLE_WAIT_DAYS: count += 1
	for agent: Variant in _idle_since.keys():
		if not seen.has(agent): _idle_since.erase(agent)
	return count


## Everything Place lists as ready to place: furniture, plants and water stones. Designs
## that share an item count it once.
func ready_to_place() -> int:
	if not is_instance_valid(furniture): return 0
	var defs: Dictionary = furniture.get_defs()
	var by_item := {}
	var stock: Dictionary = furniture.get_catalog_stock()
	for key: String in stock:
		var item := String(defs.get(key, {}).get("item_key", key))
		by_item[item] = maxi(int(by_item.get(item, 0)), int(stock[key].get("available", 0)))
	var count := 0
	for item: String in by_item: count += int(by_item[item])
	return count


func _show(target: String, count: int, tone: String, note: String) -> void:
	var button: Control = buttons.get(target)
	if button == null: return
	button.show_count(("99+" if count > 99 else str(count)) if count > 0 else "", tone, note if count > 0 else "")
