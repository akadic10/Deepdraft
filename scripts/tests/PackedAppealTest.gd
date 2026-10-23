extends "res://scripts/tests/WorkerCraftingTest.gd"

## Appeal lives only in the furniture definition. A packed piece shows the
## appeal of the furniture it installs as, so every screen agrees.

const GAME_TABLE := "base:furniture:board_game_table"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Packed appeal test timed out"); quit(1))
	await _setup_crafting_fixture()
	var def: Dictionary = furniture.get_defs()[GAME_TABLE]
	var item_key := String(def.item_key)
	_expect(furniture.def_for_item(item_key) == def, "packed item maps to its furniture definition")
	_expect(furniture.def_for_item(PINE).is_empty(), "ordinary goods install as nothing")
	for key: String in drops.get_item_defs():
		_expect(not drops.get_item_def(key).has("appeal"), "%s keeps no copy of furniture appeal" % key)
	drops.spawn_drop(item_key, 1, Vector3i(44,20,44), "base:material:pine")
	var node: Node3D = drops.nearest_loose_of_key(item_key, Vector3i(44,20,44), {}, "", -1, "")
	var expected := "%s  (" % str(_appeal(def).total)
	var rows: Array = drops.get_explorer_data(node).rows
	_expect(rows.any(func(row): return String(row[0]) == "Appeal when installed" and String(row[1]).begins_with(expected)), "packed table shows the furniture's appeal %s" % expected)
	for failure: String in failures: push_error(failure)
	print("PACKED_APPEAL_OK" if failures.is_empty() else "PACKED_APPEAL_FAIL")
	quit(0 if failures.is_empty() else 1)

func _appeal(def: Dictionary) -> Dictionary:
	return root.get_node("CraftMaterials").appeal(def, "base:material:pine")
