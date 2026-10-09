extends RefCounted

## Seeded macro geography. No scene, registry, terrain writes or global RNG.
## WorldGenerator owns profile loading; callers pass that immutable input here.
## Shared by the live generator and the offline seed gallery.
const Validator = preload("res://scripts/components/WorldLayoutValidator.gd")
const CARDINAL: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const FALLBACK_VARIANTS := 32

var _count: int
var _profile: Dictionary


func generate(world_seed: int, profile: Dictionary) -> Dictionary:
	var errors := Validator.profile_errors(profile)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_profile = profile
	_count = int(profile["macro_count"])
	var rejected: Array = []
	for attempt in range(int(profile["max_attempts"])):
		var candidate := _candidate(world_seed, attempt, false)
		var check := Validator.inspect(candidate, profile)
		if check["errors"].is_empty():
			return _accepted(candidate, check, attempt + 1, false, rejected)
		rejected.append(check["errors"])
	# A finite fallback family lets the test exercise EVERY possible fallback,
	# rather than extrapolating a guarantee from randomly sampled fallback seeds.
	# Selection remains seed-derived. Keep validating in case the profile changes.
	var variant := posmod(world_seed, FALLBACK_VARIANTS)
	var fallback := _candidate(variant, 0, true)
	fallback["seed"] = world_seed
	fallback["fallback_variant"] = variant
	var check := Validator.inspect(fallback, profile)
	if not check["errors"].is_empty():
		return {"ok": false, "errors": check["errors"], "rejected": rejected}
	return _accepted(fallback, check, int(profile["max_attempts"]), true, rejected)


func _accepted(layout: Dictionary, check: Dictionary, attempts: int, fallback: bool, rejected: Array) -> Dictionary:
	layout["ok"] = true
	layout["metrics"] = check["metrics"]
	layout["attempts"] = attempts
	layout["used_fallback"] = fallback
	layout["rejected"] = rejected
	return layout


func _stream(world_seed: int, attempt: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed * 1000003) ^ (attempt * 73856093) ^ salt
	return rng


func _candidate(world_seed: int, attempt: int, fallback: bool) -> Dictionary:
	var rng := _stream(world_seed, attempt, 104729)
	var water_rng := _stream(world_seed, attempt, 130363)
	var tarn_rng := _stream(world_seed, attempt, 155921)
	var ranks := PackedInt32Array()
	ranks.resize(_count * _count)
	var sources: Array[Vector3i] = [] # x, z, shelf rank
	var primary: Dictionary = _profile["primary"]
	if fallback:
		var turn := rng.randi_range(0, 3)
		var offset := Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
		for point in [Vector2i(-2, 0), Vector2i(0, 0), Vector2i(2, 1)]:
			for rotation in range(turn):
				point = Vector2i(-point.y, point.x)
			point += Vector2i(16, 16) + offset
			sources.append(Vector3i(point.x, point.y, 9))
	else:
		var margin := int(primary["anchor_margin"])
		var anchor := Vector2(rng.randi_range(margin, _count - margin - 1), rng.randi_range(margin, _count - margin - 1))
		var angle := rng.randf_range(0.0, TAU)
		var length := rng.randi_range(int(primary["ridge_length_min"]), int(primary["ridge_length_max"]))
		var bend := rng.randf_range(-0.7, 0.7)
		var summit_width := 2 if rng.randf() < float(primary["summit_expansion_chance"]) else 1
		for step in range(length):
			var t := float(step) / float(length - 1)
			var along := Vector2(cos(angle), sin(angle)) * (t - 0.5) * float(length)
			var across := Vector2(-sin(angle), cos(angle)) * sin(t * PI) * bend * float(length) * 0.4
			var point := Vector2i((anchor + along + across).round())
			point = point.clamp(Vector2i(4, 4), Vector2i(_count - 5, _count - 5))
			var rank := 9 - int(floor(absf(t - 0.5) * 5.0))
			if step == length / 2: rank = 9
			for dx in range(summit_width if rank == 9 else 1):
				for dz in range(summit_width if rank == 9 else 1):
					sources.append(Vector3i(point.x + dx, point.y + dz, rank))
		var secondary: Dictionary = _profile["secondary"]
		for i in range(rng.randi_range(int(secondary["count_min"]), int(secondary["count_max"]))):
			sources.append(Vector3i(rng.randi_range(2, _count - 3), rng.randi_range(2, _count - 3),
				rng.randi_range(int(secondary["rank_min"]), int(secondary["rank_max"]))))
	_raise_shelves(ranks, sources)
	# Broad, useful mountain ledges are part of the landform, independent of
	# whether the later water stream decides to place a tarn on one.
	for i in range(rng.randi_range(int(primary["shoulders_min"]), int(primary["shoulders_max"]))):
		var choices: Array[int] = []
		for index in range(ranks.size()):
			if ranks[index] == 4: choices.append(index)
		if choices.is_empty(): break
		var center := _point(choices[rng.randi_range(0, choices.size() - 1)])
		var width := rng.randi_range(int(primary["shoulder_size_min"]), int(primary["shoulder_size_max"]))
		var ledge: Array[Vector3i] = []
		for x in range(center.x - width / 2, center.x - width / 2 + width):
			for z in range(center.y - width / 2, center.y - width / 2 + width):
				if _inside(x, z): ledge.append(Vector3i(x, z, 4))
		_raise_shelves(ranks, ledge)
	_promote_lowland_islands(ranks)
	var water_bodies: Array = []
	var lake := _lowland_lake(ranks, water_rng)
	if not lake.is_empty(): water_bodies.append(lake)
	var tarn := _mountain_tarn(ranks, tarn_rng)
	if not tarn.is_empty(): water_bodies.append(tarn)
	var heights := PackedInt32Array()
	var water_index := PackedInt32Array()
	heights.resize(ranks.size())
	water_index.resize(ranks.size())
	water_index.fill(-1)
	for index in range(ranks.size()): heights[index] = int(_profile["shelf_tops"][ranks[index]])
	for body_index in range(water_bodies.size()):
		var body: Dictionary = water_bodies[body_index]
		for index in body["cells"]:
			heights[index] = int(body["floor_y"])
			water_index[index] = body_index
	return {"seed": world_seed, "profile_id": _profile["profile_id"], "algorithm_version": _profile["algorithm_version"],
		"macro_count": _count, "macro_size": _profile["macro_size"], "ranks": ranks, "heights": heights,
		"water_index": water_index, "water_bodies": water_bodies}


func _raise_shelves(ranks: PackedInt32Array, sources: Array[Vector3i]) -> void:
	# Multi-source distance envelope: max(source_rank - Chebyshev distance).
	# Every adjacent plate (including diagonals) differs by at most one rank.
	# No lowering pass can erase a summit. Packed arrays are reference types.
	var buckets: Array = []
	for rank in range(10): buckets.append([])
	for source in sources:
		var index := source.x * _count + source.y
		if source.z > ranks[index]:
			ranks[index] = source.z
			buckets[source.z].append(index)
	for rank in range(9, 1, -1):
		for index: int in buckets[rank]:
			if ranks[index] != rank: continue
			var point := _point(index)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var x := point.x + dx
					var z := point.y + dz
					if not _inside(x, z): continue
					var next := x * _count + z
					if ranks[next] < rank - 1:
						ranks[next] = rank - 1
						buckets[rank - 1].append(next)


func _promote_lowland_islands(ranks: PackedInt32Array) -> void:
	for component in _lowland_components(ranks):
		var touches_edge := false
		for index: int in component:
			var point := _point(index)
			if point.x == 0 or point.y == 0 or point.x == _count - 1 or point.y == _count - 1:
				touches_edge = true
				break
		if not touches_edge:
			for index: int in component: ranks[index] = 1


func _lowland_components(ranks: PackedInt32Array) -> Array:
	var seen := PackedByteArray()
	seen.resize(ranks.size())
	var components: Array = []
	for index in range(ranks.size()):
		if seen[index] or ranks[index] != 0: continue
		var queue: Array[int] = [index]
		seen[index] = 1
		var head := 0
		while head < queue.size():
			var point := _point(queue[head])
			head += 1
			for direction in CARDINAL:
				var next := point + direction
				if not _inside(next.x, next.y): continue
				var neighbor := next.x * _count + next.y
				if not seen[neighbor] and ranks[neighbor] == 0:
					seen[neighbor] = 1
					queue.append(neighbor)
		components.append(queue)
	return components


func _lowland_lake(ranks: PackedInt32Array, rng: RandomNumberGenerator) -> Dictionary:
	var components := _lowland_components(ranks)
	if components.is_empty(): return {}
	var eligible: Array[int] = []
	for component: Array in components:
		if component.size() > eligible.size(): eligible.assign(component)
	var config: Dictionary = _profile["lowland_lake"]
	if eligible.size() < int(config["min_cells"]): return {}
	var coastal := rng.randf() < float(config["coastal_chance"])
	var anchors: Array[int] = []
	for index in eligible:
		var point := _point(index)
		var edge := mini(mini(point.x, point.y), mini(_count - 1 - point.x, _count - 1 - point.y))
		if (coastal and edge == 0) or (not coastal and edge >= 4): anchors.append(index)
	if anchors.is_empty(): anchors = eligible
	var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
	var origin := _point(anchor)
	var target := rng.randi_range(int(config["min_cells"]), int(config["max_cells"]))
	var shape_salt := rng.randi()
	var stretch := rng.randf_range(0.65, 1.5)
	var frontier: Array[int] = [anchor]
	var discovered := {anchor: true}
	var cells: Array[int] = []
	while not frontier.is_empty() and cells.size() < target:
		var best := 0
		var best_score := INF
		for i in range(frontier.size()):
			var point := _point(frontier[i])
			var dx := float(point.x - origin.x) * stretch
			var dz := float(point.y - origin.y) / stretch
			var roughness := float(((frontier[i] * 1664525) ^ shape_salt) & 1023) / 1023.0
			var score := dx * dx + dz * dz + roughness * 4.0
			if score < best_score:
				best = i
				best_score = score
		var index := frontier[best]
		frontier.remove_at(best)
		cells.append(index)
		for direction in CARDINAL:
			var point := _point(index) + direction
			if not _inside(point.x, point.y): continue
			var neighbor := point.x * _count + point.y
			if ranks[neighbor] != 0 or discovered.has(neighbor): continue
			discovered[neighbor] = true
			frontier.append(neighbor)
	cells.sort()
	return {"kind": "lowland_lake", "floor_y": config["floor_y"], "waterline_y": config["waterline_y"], "cells": cells}


func _mountain_tarn(ranks: PackedInt32Array, rng: RandomNumberGenerator) -> Dictionary:
	var config: Dictionary = _profile["mountain_tarn"]
	if rng.randf() >= float(config["chance"]): return {}
	var candidates: Array[int] = []
	for x in range(1, _count - 1):
		for z in range(1, _count - 1):
			if ranks[x * _count + z] != 4: continue
			var valid := true
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if ranks[(x + dx) * _count + z + dz] not in [4, 5]: valid = false
			if valid: candidates.append(x * _count + z)
	if candidates.is_empty(): return {}
	return {"kind": "mountain_tarn", "floor_y": config["floor_y"], "waterline_y": config["waterline_y"],
		"cells": [candidates[rng.randi_range(0, candidates.size() - 1)]]}


func _point(index: int) -> Vector2i:
	return Vector2i(index / _count, index % _count)


func _inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < _count and z < _count
