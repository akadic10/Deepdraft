extends RefCounted

## Physical storage slots. One item type per slot; reservations include units.
## Tokens stay paired with cargo even when pickup order changes or a path fails.
var entries: Dictionary = {}
var slots: Array = []
var reservations: Dictionary = {}
var capacity_for: Callable


func room(key: String, slot: Variant) -> int:
	var stack: Dictionary = entries.get(slot, {})
	var claim: Dictionary = reservations.get(slot, {})
	if not stack.is_empty() and String(stack.item) != key:
		return 0
	if not claim.is_empty() and String(claim.item) != key:
		return 0
	return maxi(int(capacity_for.call(key)) - int(stack.get("count", 0)) - int(claim.get("count", 0)), 0)


func has_room(key: String) -> bool:
	for slot in slots:
		if room(key, slot) > 0:
			return true
	return false


func has_any_room() -> bool:
	for slot in slots:
		var stack: Dictionary = entries.get(slot, reservations.get(slot, {}))
		if stack.is_empty() or room(String(stack.item), slot) > 0:
			return true
	return false


func reserve(key: String, amount: int, owner: int, near: Vector3i) -> Variant:
	# Top up a matching crate before claiming another physical slot.
	for partial in [true, false]:
		var best: Variant = null
		var best_distance := INF
		for slot in slots:
			if (entries.has(slot) or reservations.has(slot)) != partial or room(key, slot) <= 0:
				continue
			var distance := 0.0
			if slot is Vector3i:
				var delta: Vector3i = slot - near
				distance = float(absi(delta.x) + absi(delta.z))
			if distance < best_distance:
				best = slot
				best_distance = distance
		if best == null:
			continue
		var count := mini(amount, room(key, best))
		var claim: Dictionary = reservations.get(best, {"item": key, "count": 0})
		claim.count = int(claim.count) + count
		reservations[best] = claim
		return {"slot": best, "count": count, "owner": owner, "item": key, "active": true}
	return null


func release(token: Dictionary) -> void:
	if not bool(token.get("active", false)):
		return
	token.active = false
	var claim: Dictionary = reservations.get(token.slot, {})
	if claim.is_empty() or String(claim.item) != String(token.item):
		return
	claim.count = int(claim.count) - int(token.count)
	if int(claim.count) <= 0:
		reservations.erase(token.slot)


func commit(token: Dictionary, key: String) -> void:
	assert(bool(token.active) and key == String(token.item))
	var stack: Dictionary = entries.get(token.slot, {"item": key, "count": 0})
	stack.count = int(stack.count) + int(token.count)
	assert(int(stack.count) <= int(capacity_for.call(key)))
	if token.has("instance_id"): stack["instance_id"] = token.instance_id
	entries[token.slot] = stack
	release(token)
