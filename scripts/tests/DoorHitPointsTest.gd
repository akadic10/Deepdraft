extends "res://scripts/tests/WorkerCraftingTest.gd"

## Door and gate hit points (doc 62): the design's number times the wood's toughness,
## the way appeal is design plus material. An installed door's compact panel says "Intact ·
## 180 hit points" and its rows give the sum; the Place card shows the chosen wood's hit points
## or the range across the woods. Nothing damages a door yet.

const DOOR := "base:furniture:door"
const GATE := "base:furniture:log_gate"


func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("DoorHitPoints timeout"); quit(1))
	await _setup_crafting_fixture()
	var materials: Node = root.get_node("CraftMaterials")
	var defs: Dictionary = furniture.get_defs()
	_sums(materials, defs)
	await _panel(defs)
	_place_card(defs)
	for failure: String in failures: push_error(failure)
	print("DOOR_HIT_POINTS_OK: sums, panel and Place card" if failures.is_empty() else "DOOR_HIT_POINTS_FAIL")
	quit(0 if failures.is_empty() else 1)


## 150 for each log door, 100 for the gate, times the material's toughness.
func _sums(materials: Node, defs: Dictionary) -> void:
	var points := {}
	for id: String in ["base:material:pine", "base:material:applewood", "base:material:juniper", "base:material:oak", "base:material:iron"]:
		points[id.get_slice(":", 2)] = materials.hit_points(defs[DOOR], id)
	_expect(points == {"pine": 150, "applewood": 150, "juniper": 165, "oak": 180, "iron": 750}, "the design's 150 times the material's toughness: %s" % points)
	for key: String in ["base:furniture:log_door_3", "base:furniture:log_door_4"]:
		_expect(materials.hit_points(defs[key], "base:material:pine") == 150, "%s has 150 hit points in pine" % key)
	_expect(materials.hit_points(defs[GATE], "base:material:pine") == 100, "the log gate has 100 in pine")
	_expect(materials.hit_points(defs[BENCH], "base:material:oak") == 0, "a piece without hit points has none")


## An installed oak door: intact with 180 hit points, and the sum among its rows.
func _panel(defs: Dictionary) -> void:
	furniture._install(DOOR, defs[DOOR], Vector3i(50, 20, 50), 0, "base:material:oak")
	var door = furniture._installed[furniture._next_installed_id - 1]
	await _frames(2)
	var data: Dictionary = furniture.get_explorer_data("installed:%d" % door.installed_id)
	_expect(String(data.get("status", {}).get("text", "")) == "Intact · 180 hit points", "the oak door's panel says it is intact: %s" % data.get("status", {}))
	_expect((data.get("rows", []) as Array).any(func(row: Array) -> bool: return row[0] == "Hit points" and String(row[1]).begins_with("180")), "its rows give the sum")


## The Place card: the chosen wood's hit points, the range across the woods, or nothing.
func _place_card(defs: Dictionary) -> void:
	var card = load("res://scripts/ui/FurniturePlacePanel.gd").new()
	_expect(card._hit_points_text(defs[DOOR], "") == "150–180", "the Place card gives the range across the woods")
	_expect(card._hit_points_text(defs[DOOR], "base:material:oak") == "180", "or the chosen wood's")
	_expect(card._hit_points_text(defs[BENCH], "").is_empty(), "and nothing for a piece without hit points")
	card.free()
