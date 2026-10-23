extends "res://scripts/tests/WorkerCraftingTest.gd"

## DEV Instant Build skips the dwarf, not the item: it uses up one matching
## packed item (loose or stored) and installs the piece in that item's material.

const CHAIR := "base:furniture:log_chair"
const CHAIR_ITEM := "base:resources:furniture:log_chair"
const BIRCH := "base:material:birch"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("DEV instant build test timed out"); quit(1))
	await _setup_crafting_fixture()
	worker.hide()
	worker.set_process(false)
	# Loose item.
	drops.spawn_drop(CHAIR_ITEM, 1, Vector3i(44,20,44), BIRCH)
	_build_plan(Vector3i(48,20,44))
	_expect(_count(CHAIR_ITEM) == 0, "instant build uses up the loose chair")
	# Stored item.
	var cell := Vector3i(40,20,44)
	zone.cell_stacks[cell] = {"item":CHAIR_ITEM,"count":1,"material_id":BIRCH}
	drops.restore_stored_item(CHAIR_ITEM,cell,1,"",false,BIRCH)
	stockpiles.rebuild_totals()
	_build_plan(Vector3i(48,20,40))
	_expect(_count(CHAIR_ITEM) == 0, "instant build withdraws and uses up the stored chair")
	for failure: String in failures: push_error(failure)
	print("DEV_INSTANT_BUILD_OK" if failures.is_empty() else "DEV_INSTANT_BUILD_FAIL")
	quit(0 if failures.is_empty() else 1)

func _build_plan(origin: Vector3i) -> void:
	var before: int = furniture._installed.size()
	var plan_id: int = furniture._next_ghost_id
	furniture.activate_for(CHAIR, true)
	furniture._hover_cell = origin
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(furniture._ghosts.has(plan_id), "chair plan placed at %s" % origin)
	furniture.dev_instant_build(plan_id)
	_expect(furniture._installed.size() == before + 1, "instant build installs the chair at %s" % origin)
	var installed = furniture._installed.values().back()
	_expect(installed.material_id == BIRCH, "installed chair keeps the item's material (got '%s')" % installed.material_id)
