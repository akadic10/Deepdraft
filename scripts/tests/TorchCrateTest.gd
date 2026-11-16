extends "res://scripts/tests/WorkerCraftingTest.gd"

## Log torches are kept as fruit is, 24 to a crate (owner, 2026-11-15: "The torch in our game takes
## too much space up as a furniture shipping container, can we make the torch behave similar to
## fruit where 24 of them fit in a crate?"):
## - a batch of four lands as one crate, the next batch joins it, a crate takes 24, and another wood
##   keeps a crate of its own, shown in its own colours; a clicked crate says how many it holds;
## - a plan takes one torch out of a loose crate: two plans on one crate each hold their own torch at
##   once and the rest of the crate stays free and counted in Place;
## - a cancelled plan puts its torch back in the crate;
## - a crate takes one stockpile cell, a plan takes one torch out of the stored crate, and a torch
##   taken down joins the stored crate again;
## - a finished goods pallet keeps a crate of torches in one quarter.
const PALLET := "base:furniture:finished_goods_pallet"
const PINE_WOOD := "base:material:pine"
const OAK_WOOD := "base:material:oak"
const BENCH_CELL := Vector3i(44, 20, 41)     # where a bench's torches turn up
const PALLET_ORIGIN := Vector3i(36, 20, 40)
const WALL_CELLS: Array[Vector3i] = [Vector3i(47, 20, 46), Vector3i(49, 20, 46), Vector3i(48, 20, 46)]


func _run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Torch crate test timed out"); quit(1))
	await _setup_crafting_fixture()
	_crates()
	await _two_plans_share_a_crate()
	_cancelled_plan()
	await _stored_crate()
	await _pallet_quarter()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TORCH_CRATE_OK: one crate a batch, 24 to a crate, a crate to a wood, one torch to a plan, shared loose crate, cancelled plan, stored crate, pallet quarter")
	quit(0 if failures.is_empty() else 1)


## Batches fill one crate, as a bench drops them (WorkerCraftOrder: spawn_drop of the recipe's four).
func _crates() -> void:
	var definition: Dictionary = drops.get_item_def(TORCH_ITEM)
	_expect(drops.item_capacity(TORCH_ITEM) == 24 and (definition.get("crate_models", []) as Array).size() == 3
		and "stockpile_furniture" in definition.material_tags, "the torch is furniture kept 24 to a crate")
	drops.spawn_drop(TORCH_ITEM, 4, BENCH_CELL + Vector3i.UP, PINE_WOOD)
	_expect(_torch_crates().size() == 1 and drops.quantity_of(_torch_crates()[0]) == 4, "a batch of four torches is one crate")
	var low: String = _torch_crates()[0].get_meta("visual_path", "")
	drops.spawn_drop(TORCH_ITEM, 26, BENCH_CELL + Vector3i.UP, PINE_WOOD)
	var counts: Array = _torch_crates().map(func(node: Node3D) -> int: return drops.quantity_of(node))
	counts.sort()
	_expect(counts == [6, 24], "later batches join the crate, which takes 24; the rest starts another")
	var full: Node3D = _torch_crates().filter(func(node: Node3D) -> bool: return drops.quantity_of(node) == 24)[0]
	_expect(low.ends_with("torch_low.glb") and String(full.get_meta("visual_path", "")).ends_with("torch_full.glb"), "a crate shows how full it is")
	drops.spawn_drop(TORCH_ITEM, 4, BENCH_CELL + Vector3i.UP, OAK_WOOD)
	var oak: Node3D = _torch_crates().filter(func(node: Node3D) -> bool: return root.get_node("CraftMaterials").of_item(node) == OAK_WOOD)[0]
	_expect(_torch_crates().size() == 3 and drops.quantity_of(oak) == 4, "torches of another wood keep a crate of their own")
	var partial: Node3D = _torch_crates().filter(func(node: Node3D) -> bool: return drops.quantity_of(node) == 6)[0]
	_expect(_colors(oak) != _colors(partial), "and show their own wood")
	_expect(_count(TORCH_ITEM) == 34, "every torch is counted")
	var shown: Dictionary = drops.get_explorer_data(partial)
	_expect(shown.title == "Pine log torch" and shown.badge.get("value") == "6 / 24" and shown.picture == "res://assets/ui/furniture/torch.png",
		"a clicked crate names its torches and says how many it holds: %s, %s" % [shown.title, shown.badge])
	# The plans below work from the one pine crate of six.
	for node: Node3D in [full, oak]:
		drops.take(node)
		node.free()


func _two_plans_share_a_crate() -> void:
	_build_wall()
	var first = _place_torch(WALL_CELLS[0])
	var second = _place_torch(WALL_CELLS[1])
	var mine: Node3D = first.claimed_item()
	var yours: Node3D = second.claimed_item()
	_expect(mine != null and yours != null and mine != yours and drops.quantity_of(mine) == 1 and drops.quantity_of(yours) == 1,
		"two plans on one crate each set a torch of their own aside")
	_expect(int(drops.get_unreserved_counts().get(TORCH_ITEM, 0)) == 4 and _count(TORCH_ITEM) == 6, "the rest of the crate stays free")
	_expect(int(furniture.get_catalog_stock()[TORCH].available) == 4, "Place counts the four torches left")
	for i in range(2000):
		if _installed_torches() == 2: break
		await _tick()
	_expect(_installed_torches() == 2 and _count(TORCH_ITEM) == 4, "both torches are hung, one torch each")
	_expect(_torch_crates().size() == 1 and drops.quantity_of(_torch_crates()[0]) == 4 and worker._carried_entries.is_empty(), "the crate keeps the other four")


func _cancelled_plan() -> void:
	var plan = _place_torch(WALL_CELLS[2])
	_expect(plan.claimed_item() != null and _torch_crates().size() == 2 and int(furniture.get_catalog_stock()[TORCH].available) == 3, "a plan holds one torch out of the crate")
	furniture.cancel_ghost(plan.ghost_id)
	_expect(_torch_crates().size() == 1 and drops.quantity_of(_torch_crates()[0]) == 4 and int(drops.get_unreserved_counts().get(TORCH_ITEM, 0)) == 4,
		"a cancelled plan puts its torch back in the crate")


func _stored_crate() -> void:
	for i in range(2000):
		if zone.stored_count() == 4: break
		zone.update_leases()
		await _tick()
	_expect(zone.cell_stacks.size() == 1 and zone.stored_count() == 4 and _torch_crates().is_empty(), "four torches take one stockpile cell")
	var plan = _place_torch(WALL_CELLS[2])
	_expect(plan.claimed_item() == null and int(furniture.get_catalog_stock()[TORCH].available) == 3, "a plan counts one torch of the stored crate")
	for i in range(2000):
		if _installed_torches() == 3: break
		await _tick()
	_expect(_installed_torches() == 3 and zone.cell_stacks.size() == 1 and zone.stored_count() == 3 and _count(TORCH_ITEM) == 3,
		"the plan takes one torch out of the stored crate")
	# A torch taken down is a loose torch again and joins the stored crate.
	var hung = furniture._installed.values().filter(func(piece) -> bool: return piece.furniture_key == TORCH)[0]
	furniture.dev_remove_installed(hung.installed_id)
	_expect(_installed_torches() == 2 and _count(TORCH_ITEM) == 4 and _torch_crates().size() == 1, "a torch taken down is a loose torch again")
	for i in range(2000):
		if zone.stored_count() == 4: break
		zone.update_leases()
		await _tick()
	_expect(zone.cell_stacks.size() == 1 and zone.stored_count() == 4, "and joins the stored crate")


## The pallet keeps packed furniture one piece to a quarter; a crate of torches is one such piece.
func _pallet_quarter() -> void:
	furniture._install(PALLET, furniture.get_defs()[PALLET], PALLET_ORIGIN, 0, PINE_WOOD)
	var pallet = furniture._installed.values().filter(func(piece) -> bool: return piece.furniture_key == PALLET)[0].storage
	_expect(pallet != null and pallet.accepts_key(TORCH_ITEM) and pallet.priority < zone.priority, "the finished goods pallet takes torches ahead of the ground")
	drops.spawn_drop(TORCH_ITEM, 20, BENCH_CELL + Vector3i.UP, PINE_WOOD)
	for i in range(4000):
		if pallet.stored_count() == 24: break
		zone.update_leases()
		pallet.update_leases()
		await _tick()
	_expect(pallet.stored_count() == 24 and pallet.storage_used() == 1 and zone.stored_count() == 0, "24 torches stand in one quarter of the pallet")
	_expect(pallet.usage_text() == "1 / 4 quarters · 24 goods", "its window counts the crate and its torches: %s" % pallet.usage_text())


## Returns the plan (untyped: a test script cannot name classes that use autoloads).
func _place_torch(cell: Vector3i):
	furniture.activate_for(TORCH, true)
	furniture._yaw = 0
	furniture._hover_cell = cell
	_expect(furniture._placement_valid(cell), "a torch may hang at %s" % cell)
	var before: Array = furniture._ghosts.keys()
	furniture._confirm_ghost()
	furniture.deactivate()
	for id: int in furniture._ghosts:
		if id not in before: return furniture._ghosts[id]
	_expect(false, "a torch plan is placed at %s" % cell)
	return null


func _torch_crates() -> Array:
	return drops._loose.keys().filter(func(node: Node3D) -> bool: return drops.item_key_of(node) == TORCH_ITEM)


func _installed_torches() -> int:
	return furniture._installed.values().filter(func(piece) -> bool: return piece.furniture_key == TORCH).size()


func _colors(node: Node) -> PackedColorArray:
	var result := PackedColorArray()
	if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(node): return result
	if node is MeshInstance3D: result.append_array(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	for child in node.get_children(): result.append_array(_colors(child))
	return result
