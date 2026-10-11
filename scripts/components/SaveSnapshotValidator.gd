extends RefCounted

## Pure structural validation, shared by every SaveManager read/commit path.
## Keep this contract in step with scene-owner serializers. Empty collections
## are valid (including an unsettled world); missing sections are data loss.
## Dictionary fields are required unless prefixed with ?. A single-element
## array describes its entries; * describes values in a keyed dictionary.
## Additional fields are allowed; required fields must still match their types.

const FILTER := {"tags": [TYPE_STRING], "items": [TYPE_STRING], "excluded_items": [TYPE_STRING]}
const CARGO := {"item_key": "key", "count": "positive_int", "disallowed": TYPE_BOOL, "?instance_id": TYPE_STRING}
const STACK := {"item": "key", "count": "positive_int", "disallowed": TYPE_BOOL, "?instance_id": TYPE_STRING}
const ANIMAL := {
	"id": "key", "cell": "cell", "home": "cell", "target": "cell", "position": "vector",
	"yaw": TYPE_FLOAT, "hunger": TYPE_FLOAT, "fatigue": TYPE_FLOAT, "activity": "key",
	"timer": TYPE_FLOAT, "calm_left": TYPE_FLOAT, "hop_progress": TYPE_FLOAT,
	"hop_seconds": TYPE_FLOAT, "rest_offset": TYPE_FLOAT, "pose_time": TYPE_FLOAT,
	"rng_state": "rng", "?arrival": TYPE_DICTIONARY, "?herd_id": TYPE_STRING,
	"?hunt_target_id": TYPE_STRING, "?hunt_left": TYPE_FLOAT,
	"?retry_hours": TYPE_FLOAT, "?satisfied_hours": TYPE_FLOAT,
}
const DUCK := {"flock_id":TYPE_STRING,"sex":"key","mode":"key","step_from":"vector",
	"flight":["vector"],"flight_index":"positive_int","launch_left":TYPE_FLOAT,"flight_left":TYPE_FLOAT,
	"quack_left":TYPE_FLOAT,"shore_left":TYPE_FLOAT}
const EVENT_PLAN := {"id": "key", "due": TYPE_FLOAT, "count": "positive_int", "roll": TYPE_FLOAT, "seed": "rng"}
const ACTIVE_EVENT := {
	"id": "key", "due": TYPE_FLOAT, "count": "positive_int", "roll": TYPE_FLOAT, "seed": "rng",
	"attempt": TYPE_INT, "issued": TYPE_INT, "wait": TYPE_FLOAT, "route": ["cell"], "edge": TYPE_STRING,
	"?member_routes": [["cell"]],
}
const SCENE := {
	"water": {"layout_version":TYPE_INT,"flow":{"cells":[{"cell":"cell","units":TYPE_INT}],"active":["cell"],
		"displaced":[{"cell":"cell","units":TYPE_INT}],"added_units":TYPE_INT,"drained_units":TYPE_INT,"extracted_units":TYPE_INT},
		"source_enabled":TYPE_BOOL,"outlet_enabled":TYPE_BOOL,"elapsed_usec":TYPE_INT,"accumulator_usec":TYPE_INT,
		"next_stone_id":"positive_int", "stones":{"*":{"kind":"key","cell":"cell","intake":"cell","level":TYPE_FLOAT,
			"placed":TYPE_BOOL,"disallowed":TYPE_BOOL,"packing":TYPE_BOOL,"work":TYPE_FLOAT}},
		"terrain":[{"cell":"cell","block":"key"}],"test_dam":[{"cell":"cell","block":"key"}],
		"moisture":[{"cell":"cell","value":TYPE_INT,"target":TYPE_INT,"since":TYPE_INT}]},
	"mining": {"mined_blocks": ["cell"], "zones": [{"id": TYPE_INT, "blocks": ["cell"]}]},
	"flora": {"trees": [{
		"origin": "cell", "species": "key", "stage": "key", "work_seconds": TYPE_FLOAT,
		"action": TYPE_STRING, "fell_work_seconds": TYPE_FLOAT, "harvest_work_seconds": TYPE_FLOAT,
		"harvest_work_cycle": TYPE_STRING, "harvested_cycle": TYPE_STRING,
		"felled": TYPE_BOOL, "designated": TYPE_BOOL,
	}]},
	"surface_details": {
		"changes": [{"id": "key", "removed": TYPE_BOOL, "designated": TYPE_BOOL,
			"work_seconds": TYPE_FLOAT, "reason": TYPE_STRING, "?origin": "cell", "?yaw": TYPE_INT,
			"?packed": TYPE_BOOL, "?planted_at": TYPE_FLOAT, "?growth_credit": TYPE_FLOAT,
			"?action": TYPE_STRING, "?harvested_cycle": TYPE_STRING, "?harvest_work_cycle": TYPE_STRING,
			"?clear_work_seconds": TYPE_FLOAT, "?harvest_work_seconds": TYPE_FLOAT,
			"?uproot_work_seconds": TYPE_FLOAT}],
		"planted": [{"id": "key", "definition": "key", "origin": "cell", "yaw": TYPE_INT}],
		"next_plant_id": TYPE_INT,
	},
	"settlement_flag": {"placed": TYPE_BOOL, "cell": "cell"},
	"stockpiles": {"zones": [{"id": TYPE_INT, "cells": ["cell"], "filter_tags": [TYPE_STRING],
		"storage_filter": FILTER,
		"stacks": [{"cell": "cell", "item": "key", "count": "positive_int", "disallowed": TYPE_BOOL, "?instance_id": TYPE_STRING}]}]},
	"furniture": {
		"ghosts": [{"id": TYPE_INT, "key": "key", "origin": "cell", "yaw": TYPE_INT,
			"layout_version": TYPE_INT, "?plant_work": TYPE_FLOAT, "?plant_id": TYPE_STRING, "?stone_id": TYPE_STRING}],
		"installed": [{"id": TYPE_INT, "key": "key", "origin": "cell", "yaw": TYPE_INT,
			"layout_version": TYPE_INT, "flagged_uninstall": TYPE_BOOL,
			"?inventory": {"*": "positive_int"}, "?instances": [STACK], "?storage_filter": FILTER}],
	},
	"ladders": {"routes": [{"id": TYPE_INT, "key": "key", "base": "cell", "yaw": TYPE_INT,
		"height": TYPE_INT, "built": TYPE_INT, "mode": TYPE_STRING, "progress": TYPE_FLOAT}], "next_id": TYPE_INT},
	"items": {"loose": [{"item_key": "key", "position": "vector", "rotation_y": TYPE_FLOAT,
		"count": "positive_int", "disallowed": TYPE_BOOL, "?instance_id": TYPE_STRING}]},
	"dwarves": {"birth_index": TYPE_INT, "settlement_anchor": "cell", "roster": [{
		"id": TYPE_INT, "name": TYPE_STRING, "gender": TYPE_STRING, "appearance": {"*": TYPE_STRING},
		"traits": [TYPE_STRING], "profession": "key", "profession_experience": {"*": TYPE_INT},
		"work_permissions": {"*": TYPE_BOOL}, "position": "vector", "rotation_y": TYPE_FLOAT,
		"sleep": TYPE_FLOAT, "sleeping": TYPE_BOOL, "sleep_hours_left": TYPE_FLOAT,
		"carried_items": [CARGO], "equipment": {"*": TYPE_STRING},
	}]},
	"wildlife": {"initialized": TYPE_BOOL, "rabbits": [ANIMAL], "deer_initialized": TYPE_BOOL,
		"deer": [ANIMAL], "wolf_initialized": TYPE_BOOL, "wolves": [ANIMAL], "duck_initialized":TYPE_BOOL,"ducks":["duck"]},
	"world_events": {"initialized": TYPE_BOOL, "serial": TYPE_INT, "rng": "rng",
		"schedules": {"*": {"next": EVENT_PLAN, "active": "active_event"}},
		"pressure": {"*": {"x": TYPE_FLOAT, "z": TYPE_FLOAT, "level": TYPE_FLOAT, "day": TYPE_FLOAT}},
		"history": [{"id": "key", "result": TYPE_STRING, "count": TYPE_INT, "day": TYPE_FLOAT}]},
	"worker_crafting": {"orders": [{"recipe": "key", "quantity": "positive_int", "maintain": TYPE_BOOL,
		"paused": TYPE_BOOL, "progress": TYPE_FLOAT, "allowed_ingredients": [TYPE_STRING]}]},
	"camera": {"target_position": "vector", "zoom": TYPE_FLOAT, "pitch": TYPE_FLOAT, "orbit_y": TYPE_FLOAT},
	"slice": {"active": TYPE_BOOL, "seeded": TYPE_BOOL, "slice_y": TYPE_INT, "last_slice_y": TYPE_INT},
}
const SNAPSHOT := {
	"schema_version": TYPE_INT, "project": TYPE_STRING, "saved_at_utc": "key", "world_seed": TYPE_INT,
	"clock": {"day": "positive_int", "season": "key", "year": "positive_int",
		"hour": TYPE_FLOAT, "speed": TYPE_FLOAT, "paused": TYPE_BOOL},
	"weather": {"current_id": "key", "rng_state": "rng"}, "scene": SCENE,
}


static func validate(snapshot: Dictionary, schema_version: int) -> String:
	# Check metadata before comparing/casting it. JSON decodes numbers as floats,
	# so whole finite numbers are accepted where serializers supply integers.
	var error := _validate(snapshot, SNAPSHOT, "save")
	if not error.is_empty(): return error
	if snapshot.project != "Deepdraft": return "this file belongs to a different project."
	if snapshot.schema_version < 1: return "the save schema is missing."
	if snapshot.schema_version > schema_version: return "this save was made by a newer game version."
	if snapshot.world_seed == 0: return "the world seed is missing."
	if snapshot.scene.water.layout_version != preload("res://scripts/components/RiverLayout.gd").VERSION:
		return "this development save uses an outdated river layout; start a new world."
	if snapshot.clock.hour < 0 or snapshot.clock.speed < 0: return "the saved clock has negative time or speed."
	for list_name: String in ["cells","displaced"]:
		var seen: Dictionary = {}
		for entry: Dictionary in snapshot.scene.water.flow[list_name]:
			var p: Array = entry.cell
			if entry.units < 0 or entry.units > 124000000 or p[0] < 0 or p[0] >= 1024 or p[1] < 4 or p[1] > 128 or p[2] < 0 or p[2] >= 1024:
				return "save.scene.water has an invalid volume or location."
			if list_name=="cells" and (p[1]>=128 or entry.units>(128-p[1])*1000000): return "save.scene.water exceeds the column's capacity."
			if list_name == "cells" and seen.has(str(p)): return "save.scene.water has duplicate cells."
			seen[str(p)] = true
	for field: String in ["elapsed_usec","accumulator_usec"]:
		if snapshot.scene.water[field] < 0: return "save.scene.water has negative time."
	var moist_cells: Dictionary = {}
	for entry: Dictionary in snapshot.scene.water.moisture:
		if entry.value<0 or entry.value>1000000 or entry.target<0 or entry.target>1000000 or entry.since<0 or entry.since>snapshot.scene.water.elapsed_usec:
			return "save.scene.water has invalid soil moisture."
		var p: Array = entry.cell
		if p[0]<0 or p[0]>=1024 or p[1]<4 or p[1]>=128 or p[2]<0 or p[2]>=1024 or moist_cells.has(str(p)): return "save.scene.water has an invalid soil location."
		moist_cells[str(p)] = true
	for field: String in ["added_units","drained_units","extracted_units"]:
		if snapshot.scene.water.flow[field] < 0: return "save.scene.water has negative accounting."
	var queued: Dictionary = {}
	for p: Array in snapshot.scene.water.flow.active:
		if p[0]<0 or p[0]>=1024 or p[1]<4 or p[1]>=128 or p[2]<0 or p[2]>=1024 or queued.has(str(p)): return "save.scene.water has an invalid active cell."
		queued[str(p)] = true
	for list_name: String in ["terrain","test_dam"]:
		var seen: Dictionary = {}
		for entry: Dictionary in snapshot.scene.water[list_name]:
			var p: Array = entry.cell
			if p[0]<0 or p[0]>=1024 or p[1]<4 or p[1]>=128 or p[2]<0 or p[2]>=1024 or seen.has(str(p)): return "save.scene.water has an invalid terrain edit."
			seen[str(p)] = true
	for section: String in snapshot.scene:
		if not snapshot.scene[section] is Dictionary: return "save.scene.%s must be a dictionary." % section
	return _validate_stones(snapshot.scene)


static func _validate_stones(scene: Dictionary) -> String:
	if not scene.water.stones.has("wet") or not scene.water.stones.has("dry"):
		return "save.scene.water is missing a natural stone identity."
	var owners := {}
	for id: String in scene.water.stones:
		var stone: Dictionary = scene.water.stones[id]
		if id.is_empty() or stone.kind not in ["wet", "dry"] or stone.level<4 or stone.level>128 or stone.work<0:
			return "save.scene.water has an invalid stone."
		if id.begins_with("water_stone:") and int(id.get_slice(":",1))>=scene.water.next_stone_id:
			return "save.scene.water has an invalid stone serial."
		for location: Array in [stone.cell, stone.intake]:
			if location[0]<0 or location[0]>=1024 or location[1]<4 or location[1]>=128 or location[2]<0 or location[2]>=1024:
				return "save.scene.water has an invalid stone location."
		if stone.packing and (not stone.placed or stone.disallowed): return "save.scene.water has an invalid packing order."
		owners[id] = 1 if stone.placed else 0
	var goods: Array = scene.items.loose.duplicate()
	for zone: Dictionary in scene.stockpiles.zones: goods.append_array(zone.stacks)
	for piece: Dictionary in scene.furniture.installed: goods.append_array(piece.get("instances",[]))
	for dwarf: Dictionary in scene.dwarves.roster: goods.append_array(dwarf.carried_items)
	for item: Dictionary in goods:
		var key := String(item.get("item_key", item.get("item", "")))
		if key not in ["base:resources:water:wet_stone", "base:resources:water:dry_stone"]: continue
		var id := String(item.get("instance_id", ""))
		if not owners.has(id) or item.count!=1 or key!="base:resources:water:"+scene.water.stones[id].kind+"_stone":
			return "save.scene has a water stone without a matching identity."
		owners[id] += 1
	for count: int in owners.values():
		if count!=1: return "save.scene has a missing or duplicated water stone."
	var moves := {}
	for ghost: Dictionary in scene.furniture.ghosts:
		var id := String(ghost.get("stone_id", ""))
		if id.is_empty(): continue
		if not owners.has(id) or moves.has(id) or ghost.key!="base:water:"+scene.water.stones[id].kind+"_stone": return "save.scene has an invalid water stone move."
		moves[id] = true
	return ""


static func _validate(value: Variant, rule: Variant, path: String) -> String:
	if rule is Dictionary:
		if not value is Dictionary: return path + " must be a dictionary."
		if rule.has("*"):
			for key: Variant in value:
				if not key is String: return path + " must have string keys."
				var error := _validate(value[key], rule["*"], path + "." + key)
				if not error.is_empty(): return error
		else:
			for field: String in rule:
				var key := field.trim_prefix("?")
				if not value.has(key):
					if field.begins_with("?"): continue
					return path + "." + key + " is missing."
				var error := _validate(value[key], rule[field], path + "." + key)
				if not error.is_empty(): return error
		return ""
	if rule is Array:
		if not value is Array: return path + " must be an array."
		for index in value.size():
			var error := _validate(value[index], rule[0], "%s[%d]" % [path, index])
			if not error.is_empty(): return error
		return ""
	if rule is int:
		if rule == TYPE_INT:
			if _is_integer(value): return ""
		elif rule == TYPE_FLOAT:
			if (value is int or value is float) and is_finite(float(value)): return ""
		elif typeof(value) == rule:
			return ""
		return "%s must be %s." % [path, type_string(rule)]
	match rule:
		"duck":
			for schema: Dictionary in [ANIMAL,DUCK]:
				var error := _validate(value,schema,path)
				if not error.is_empty(): return error
			if value.sex not in ["male","female"] or value.mode not in ["land","water","air"]: return path+" has an invalid duck state."
			if not value.flight.is_empty() and (value.flight.size()<2 or value.flight_index>=value.flight.size() or value.mode!="air"): return path+" has an invalid flight."
			if value.hop_seconds<=0 or value.hop_progress<0 or value.hop_progress>1: return path+" has invalid movement progress."
			for point: Array in [value.position,value.step_from]+value.flight:
				if point[0]<0 or point[0]>=1024 or point[1]<4 or point[1]>=158 or point[2]<0 or point[2]>=1024: return path+" has an invalid movement location."
			for field: String in ["launch_left","flight_left","shore_left"]:
				if value[field]<0: return path+" has a negative timer."
			return ""
		"key":
			if value is String and not value.is_empty(): return ""
			return path + " must be a non-empty string."
		"positive_int":
			if _is_integer(value) and value > 0: return ""
			return path + " must be a positive integer."
		"rng":
			# Canonical signed decimal text also rejects overflow before restore.
			if value is String and value.is_valid_int() and str(int(value)) == value: return ""
			return path + " must be a 64-bit integer stored as decimal text."
		"cell", "vector":
			if not value is Array or value.size() != 3: return path + " must have three coordinates."
			for index in 3:
				var error := _validate(value[index], TYPE_INT if rule == "cell" else TYPE_FLOAT,
					"%s[%d]" % [path, index])
				if not error.is_empty(): return error
			return ""
		"active_event":
			if value is Dictionary and value.is_empty(): return ""
			var error := _validate(value, ACTIVE_EVENT, path)
			if not error.is_empty(): return error
			if value.id.begins_with("duck_arrival:") and not value.route.is_empty():
				if not value.has("member_routes") or value.member_routes.size()!=value.count or value.issued<0 or value.issued>=value.count: return path+" has invalid duck arrival members."
				for route: Array in value.member_routes:
					if route.size()!=2: return path+" has an invalid duck arrival route."
			return ""
	return path + " has an unknown validation rule."


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value)
		and value >= -9223372036854775808.0 and value < 9223372036854775808.0)
