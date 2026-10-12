extends "res://scripts/tests/WorkerCraftingTest.gd"

const STOOL := "base:furniture:log_chair"
const STOOL_ITEM := "base:resources:furniture:log_chair"
const STOOL_RECIPE := "base:recipe:worker:log_chair"
var materials

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Craft material test timed out"); quit(1))
	await _setup_crafting_fixture()
	materials = root.get_node("CraftMaterials")
	furniture._install(BENCH, furniture.get_defs()[BENCH], Vector3i(45,20,42), 0)
	var ids: Array[String] = []
	for wood in ["pine", "oak", "juniper", "applewood"]:
		var id: String = "base:material:" + wood
		ids.append(id)
		var raw: String = materials.definitions[id].ingredients[0]
		drops.spawn_drop(raw, 1, Vector3i(42,21,40))
		var order_id: int = crafting.queue_order(STOOL_RECIPE, 1, false, [raw])
		_expect(await _completed(order_id), "actual worker crafts " + wood)
		var item: Node3D = drops.nearest_loose_of_key(STOOL_ITEM, worker.current_cell(), {}, "", -1, id)
		_expect(item != null and materials.of_item(item) == id, "consumed log sets finished material " + wood)
		if item != null:
			_expect(drops.get_explorer_data(item).title.begins_with(materials.material_name(id)), "packed inspector names material")
	var snapshot: Dictionary = inventory_script.snapshot(drops, furniture)
	_expect(snapshot[STOOL_ITEM].total == 4 and snapshot[STOOL_ITEM].materials.size() == 4, "one inventory row exposes four variants")
	var loose_save: Dictionary = JSON.parse_string(JSON.stringify(drops.serialize_state()))
	var validator = load("res://scripts/components/SaveSnapshotValidator.gd")
	_expect(validator._validate(loose_save, validator.SCENE.items, "items").is_empty(), "material cargo validates")
	loose_save.loose[0].material_id = "base:material:made_up"
	_expect(not validator._validate(loose_save, validator.SCENE.items, "items").is_empty(), "unknown material is rejected")
	# Exercise real multi-item hauling: four wood identities must occupy four slots.
	zone.carry_capacity = 4
	for trip in range(4):
		if zone.stored_count() == 4: break
		var haul: Dictionary = zone.reserve_haul(888, Vector3i(43,20,40), {})
		_expect(not haul.is_empty(), "mixed-material haul reserved %d" % trip)
		if haul.is_empty(): break
		var cargo: Array = []
		for index in range(haul.items.size()):
			var item: Node3D = zone.take_item(888, index)
			if item != null:
				scene.add_child(item)
				cargo.append([item, STOOL_ITEM])
		_expect(zone.commit_haul(888, cargo), "mixed-material haul commits")
	var stored_ids: Array = []
	for stack: Dictionary in zone.cell_stacks.values(): stored_ids.append(stack.get("material_id", ""))
	_expect(stored_ids.size() == 4 and ids.all(func(id): return id in stored_ids), "ground storage preserves every wood")
	# Withdraw into a closed container; no display node is available to hide metadata loss.
	var container = load("res://scripts/components/ContainerStorageComponent.gd").new()
	var cells: Array[Vector3i] = [Vector3i(47,20,44)]
	container.setup_container({"storage":{"capacity":8}}, cells)
	stockpiles.register_container(container)
	for id: String in ids:
		var item: Node3D = stockpiles.withdraw_item(STOOL_ITEM, cells[0], 889, "", id)
		_expect(item != null and materials.of_item(item) == id, "filtered withdrawal " + id)
		if item == null: continue
		var token: Dictionary = container._reserve_deposit(STOOL_ITEM, cells[0], 889, 1, id)
		drops.take(item)
		container._commit_one(token, STOOL_ITEM)
		container._place_visual(item, token)
		container.changed_callback.call(STOOL_ITEM, 1)
	var saved_stacks: Array = JSON.parse_string(JSON.stringify(container.stored_entries().values()))
	container.restore_inventory({STOOL_ITEM:4}, drops, saved_stacks)
	_expect(container.stored_entries().values().all(func(stack): return stack.material_id in ids), "container save keeps wood without visuals")
	# Place Oak with all four available. Claim and install must honor the dropdown.
	furniture.material_choices[STOOL] = "base:material:oak"
	furniture.activate_for(STOOL, true)
	furniture._hover_cell = Vector3i(52,20,40)
	furniture._confirm_ghost()
	furniture.deactivate()
	var ghost = furniture._ghosts.values()[0]
	_expect(ghost.required_material_id == "base:material:oak", "placement records selected wood")
	_expect(furniture.serialize_state().ghosts[0].required_material_id == "base:material:oak", "pending material selection saves")
	_expect(await _phase(worker.TaskPhase.FETCH_DEPOSIT), "selected oak reaches installation site")
	var carried: Array = worker.serialize_state().carried_items
	_expect(carried.size() == 1 and carried[0].material_id == "base:material:oak", "save during delivery preserves material")
	_expect(await _installed(STOOL), "worker installs selected oak from container")
	var piece = furniture._installed.values().filter(func(value): return value.furniture_key == STOOL)[0]
	_expect(piece.material_id == "base:material:oak" and piece.display_name() == "Oak log stool", "installed item retains material and name")
	_expect(float(materials.appeal(piece.def, piece.material_id).total) == 2, "stool appeal is design plus oak bonus")
	var saved_furniture: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	_expect(saved_furniture.installed.any(func(entry): return entry.key == STOOL and entry.material_id == "base:material:oak"), "installed material saves")
	furniture._teardown_installed(piece.installed_id, true)
	await _frames(2)
	_expect(drops.nearest_loose_of_key(STOOL_ITEM, Vector3i.ZERO, {}, "", -1, "base:material:oak") != null, "uninstall refunds exact material")
	var maintain: int = crafting.queue_order(STOOL_RECIPE, 2, true, [PINE])
	var order = crafting.get_order(maintain)
	_expect(crafting.available_output(order, inventory_script.snapshot(drops, furniture)) == 1, "oak, juniper and applewood do not satisfy pine maintain target")
	crafting.remove_order(maintain)
	_test_palettes()
	_test_stack_split()
	var copper: Dictionary = materials.appeal({"appeal":{"design":3,"material_factor":1}}, "base:material:copper")
	var gold: Dictionary = materials.appeal({"appeal":{"design":3,"material_factor":1}}, "base:material:gold")
	_expect(copper.total == 7 and gold.total == 28, "future metal design supports independently tuned copper and gold appeal")
	if "--capture" in OS.get_cmdline_user_args():
		for viewport in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(960,540)]:
			manager.close("place")
			root.size = viewport
			await _frames(5)
			dock._place_catalog.selected_key = STOOL
			dock._open_place_catalog()
			dock._place_catalog.refresh()
			await _frames(8)
			var cabinet: Rect2 = dock._place_window.get_global_rect()
			_expect(cabinet.encloses(dock._place_catalog._material.get_global_rect()) and cabinet.encloses(dock._place_catalog._place.get_global_rect()), "material choice and Place fit " + str(viewport))
			_expect(cabinet.end.y <= dock._dock_panel.position.y - 8, "material cabinet clears dock " + str(viewport))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/material_furniture_20261011/place_%d.png" % viewport.x)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CRAFT_MATERIAL_OK: four real crafts, hauling, containers, filtered installation, refund, persistence, maintain, palettes, appeal")
	quit(0 if failures.is_empty() else 1)

func _test_palettes() -> void:
	for key in [STOOL, "base:furniture:bench", "base:furniture:door", "base:furniture:wooden_torch", "base:furniture:campfire"]:
		var definition: Dictionary = furniture.get_defs()[key]
		var original: Node3D = load(String(definition.model)).instantiate()
		var pine: Node3D = load(String(definition.model)).instantiate()
		var apple: Node3D = load(String(definition.model)).instantiate()
		var pine_again: Node3D = load(String(definition.model)).instantiate()
		var original_colors := _colors(original)
		materials.apply_palette(pine, definition, "base:material:pine")
		materials.apply_palette(apple, definition, "base:material:applewood")
		materials.apply_palette(pine_again, definition, "base:material:pine")
		_expect(_colors(original) == original_colors, "shared original mesh untouched " + key)
		_expect(_colors(pine) != _colors(apple), "distinct wood palette " + key)
		_expect(_colors(pine) == _colors(pine_again), "shared cached palette consistent " + key)
		var base_meshes := original.find_children("*", "MeshInstance3D", true, false)
		var pine_meshes := pine.find_children("*", "MeshInstance3D", true, false)
		for index in range(base_meshes.size()):
			if String(base_meshes[index].name).to_lower().contains("flame"):
				_expect(_colors(base_meshes[index]) == _colors(pine_meshes[index]), "flame colors untouched")
		original.free(); pine.free(); apple.free(); pine_again.free()

func _colors(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		for surface in range(node.mesh.get_surface_count()): result.append(node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR])
	for child in node.get_children(): result.append_array(_colors(child))
	return result

func _test_stack_split() -> void:
	var slots = load("res://scripts/components/StorageStackSlots.gd").new()
	slots.slots = [0,1]
	slots.capacity_for = func(_key): return 24
	var pine: Dictionary = slots.reserve("test", 4, 1, Vector3i.ZERO, false, "base:material:pine")
	slots.commit(pine, "test")
	var oak: Dictionary = slots.reserve("test", 3, 2, Vector3i.ZERO, false, "base:material:oak")
	_expect(oak.slot != pine.slot, "different materials never merge in one stack")
	slots.commit(oak, "test")
	var refill: Dictionary = slots.reserve("test", 2, 3, Vector3i.ZERO, false, "base:material:pine")
	_expect(refill.slot == pine.slot, "same material tops up its own stack")
	slots.release(refill)
