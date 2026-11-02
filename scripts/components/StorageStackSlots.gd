extends RefCounted

## Physical storage slots. One item type per slot; reservations include units.
## Tokens stay paired with cargo even when pickup order changes or a path fails.
var entries: Dictionary = {}
var slots: Array = []
var reservations: Dictionary = {}
var capacity_for: Callable


func room(key: String, slot: Variant, material_id: String = "") -> int:
	var stack: Dictionary = entries.get(slot, {})
	var claim: Dictionary = reservations.get(slot, {})
	if not stack.is_empty() and (String(stack.item) != key or String(stack.get("material_id", "")) != material_id):
		return 0
	if not claim.is_empty() and (String(claim.item) != key or String(claim.get("material_id", "")) != material_id):
		return 0
	return maxi(int(capacity_for.call(key)) - int(stack.get("count", 0)) - int(claim.get("count", 0)), 0)


func has_room(key: String) -> bool:
	for slot in slots:
		if room(key, slot, String(entries.get(slot, reservations.get(slot, {})).get("material_id", ""))) > 0:
			return true
	return false


func has_any_room() -> bool:
	for slot in slots:
		var stack: Dictionary = entries.get(slot, reservations.get(slot, {}))
		if stack.is_empty() or room(String(stack.item), slot, String(stack.get("material_id", ""))) > 0:
			return true
	return false


## Top up a matching crate before claiming another physical slot. Food that spoils (`spoil`
## 0 to 1; -1 for goods that never do) tops up only a crate within `band` of its freshness
## while an empty slot is left, so fresh fruit never joins a rotting crate (doc 42
## "Spoilage"). With no empty slot it tops up the crate closest in freshness rather than
## wait outside.
func reserve(key: String, amount: int, owner: int, near: Vector3i, empty_only: bool = false, material_id: String = "",
		spoil: float = -1.0, band: float = 1.0) -> Variant:
	for pass_name: String in ["like", "empty", "closest"]:
		if pass_name != "empty" and empty_only: continue
		if pass_name == "closest" and spoil < 0.0: continue
		var best: Variant = null
		var best_rank := INF
		for slot in slots:
			if (entries.has(slot) or reservations.has(slot)) != (pass_name != "empty") or room(key, slot, material_id) <= 0:
				continue
			var gap := absf(_slot_spoil(slot) - spoil) if spoil >= 0.0 else 0.0
			if pass_name == "like" and gap > band: continue
			var distance := 0.0
			if slot is Vector3i:
				var delta: Vector3i = slot - near
				distance = float(absi(delta.x) + absi(delta.z))
			# The closest in freshness, then the nearest.
			var rank := gap * 1000000.0 + distance if pass_name == "closest" else distance
			if rank < best_rank:
				best = slot
				best_rank = rank
		if best == null:
			continue
		var count := mini(amount, room(key, best, material_id))
		var claim: Dictionary = reservations.get(best, {"item": key, "count": 0, "material_id": material_id, "spoil": spoil})
		claim.count = int(claim.count) + count
		reservations[best] = claim
		return {"slot": best, "count": count, "owner": owner, "item": key, "material_id": material_id, "active": true}
	return null


## A slot's freshness: its stack's spoil, else what is on its way to it.
func _slot_spoil(slot: Variant) -> float:
	var stack: Dictionary = entries.get(slot, {})
	if not stack.is_empty(): return float(stack.get("spoil", 0.0))
	return maxf(0.0, float(reservations.get(slot, {}).get("spoil", 0.0)))


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
	assert(int(stack.count) == 0 or String(stack.get("material_id", "")) == String(token.get("material_id", "")))
	stack["disallowed"] = false
	# Food joining a stack averages its spoil by count (doc 42 "Spoilage").
	var spoil := ItemDropManager.blend_spoil(float(stack.get("spoil", 0.0)), int(stack.count), float(token.get("spoil", 0.0)), int(token.count))
	if spoil > 0.0: stack["spoil"] = spoil
	else: stack.erase("spoil")
	stack.count = int(stack.count) + int(token.count)
	assert(int(stack.count) <= int(capacity_for.call(key)))
	if token.has("instance_id"): stack["instance_id"] = token.instance_id
	stack["material_id"] = String(token.get("material_id", ""))
	entries[token.slot] = stack
	release(token)
