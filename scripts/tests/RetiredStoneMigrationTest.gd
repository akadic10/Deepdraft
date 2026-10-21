extends SceneTree

const Migration = preload("res://scripts/components/RetiredFurnitureMigration.gd")
const COPIES := "res://tmp/retired_stones_20261019/player_saves_before/"
var checks := 0
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for id in ["SaveManager", "WorldClock", "TaskManager", "RoomManager"]: root.get_node(id).set_process(false)
	var manager := root.get_node("SaveManager")
	var catalogs: Dictionary = manager._capture_catalogs()
	var retired: Dictionary = catalogs.retired_items
	_expect(retired.size() == 4, "four explicitly retired stone items")
	var drops = load("res://scripts/systems/ItemDropManager.gd").new()
	root.add_child(drops)
	for key: String in retired:
		_expect(not drops.get_item_defs().has(key), "absent from live item and storage catalogue: " + key)
		_test_owners(key, catalogs)
	_expect(not drops.get_item_def("base:resources:stone:rough_stone").is_empty(), "Rough Stone retained")
	drops.free()
	# Opt-in integration uses immutable copies, never the player's live profile.
	if "--verify-player-copies" in OS.get_cmdline_user_args():
		for slot in ["quicksave.json", "quicksave.backup.json", "autosave.json", "autosave.backup.json"]:
			_test_saved_copy(manager, catalogs, slot)
	for failure in failures: push_error(failure)
	print("RETIRED_STONE_PASS " if failures.is_empty() else "RETIRED_STONE_FAIL ", checks, " checks")
	quit(0 if failures.is_empty() else 1)

func _test_owners(gone: String, catalogs: Dictionary) -> void:
	var keep := "base:resources:stone:rough_stone"
	var modded := gone.replace("base:", "mod:")
	var filter := {"tags":["stockpile_stone"], "items":[gone,keep], "excluded_items":[gone,modded]}
	var fixture := {"scene":{
		"items":{"loose":[{"item_key":gone,"count":2},{"item_key":keep,"count":3},{"item_key":modded,"count":1}]},
		"stockpiles":{"zones":[{"stacks":[{"item":gone,"count":4},{"item":keep,"count":5}],"storage_filter":filter.duplicate(true)}]},
		"dwarves":{"roster":[{"id":1,"carried_items":[{"item_key":gone,"count":6},{"item_key":keep,"count":1}]}]},
		"furniture":{
			"installed":[
				{"id":4,"key":"base:furniture:barrel","origin":[12,20,14],"inventory":{keep:7,gone:2},
					"instances":[{"item":keep,"count":3,"instance_id":"retained","disallowed":true},{"item":gone,"count":1}]},
				{"id":5,"key":"base:furniture:log_table","inventory":{gone:2,keep:1},"instances":[{"item":gone,"count":1}],"storage_filter":filter.duplicate(true)}],
			"ghosts":[{"key":"base:furniture:log_chair","move_id":"furniture_move:1"}],
			"moves":{"next_id":2,"records":{"furniture_move:1":{"key":"base:furniture:log_chair","installed_id":-1,"storage_filter":filter.duplicate(true)}}}},
		"water":{"stones":{"wet":{"kind":"wet"},"dry":{"kind":"dry"}}},
		"terrain":{"edits":[{"cell":[1,2,3]}]}}}
	var before := JSON.stringify(fixture)
	var cleaned := Migration.cleaned_copy(fixture,catalogs.retired_furniture,catalogs.retired_items)
	_expect(JSON.stringify(fixture)==before,"copy leaves caller untouched")
	var report := Migration.apply(fixture,catalogs.retired_furniture,catalogs.retired_items)
	_expect(fixture==cleaned,"copy and in-place cleanup agree")
	_expect(report.packed_units==16 and report.spilled_units==7,"exact removal and retained spill counts; no double counting")
	_expect(report.installed==1 and report.ghosts==0 and report.moves==0,"stone retirement does not remove surviving furniture or moves")
	_expect(report.filter_entries==6,"zone, installed and moved storage filters cleaned")
	_expect(fixture.scene.items.loose[0].item_key==keep and fixture.scene.items.loose[1].item_key==modded,"Rough Stone and similarly named mod item survive")
	_expect(fixture.scene.items.loose[2].instance_id=="retained" and fixture.scene.items.loose[2].disallowed,"surviving spill preserves identity and permissions")
	_expect(fixture.scene.stockpiles.zones[0].stacks==[{"item":keep,"count":5}],"stockpile units preserved")
	_expect(fixture.scene.dwarves.roster[0].carried_items==[{"item_key":keep,"count":1}],"carried units preserved")
	_expect(fixture.scene.furniture.installed[0].inventory=={keep:1} and fixture.scene.furniture.installed[0].instances.is_empty(),"stored aggregate and instance references removed")
	var again := Migration.apply(fixture,catalogs.retired_furniture,catalogs.retired_items)
	_expect(again.values().all(func(v): return v==0) and fixture==cleaned,"idempotent cleanup")
	var store = load("res://scripts/components/SaveFileStore.gd").new()
	store.catalogs=catalogs
	var source: Dictionary = JSON.parse_string(before)
	var source_before := JSON.stringify(source)
	_expect(JSON.parse_string(store._encode(source))==JSON.parse_string(JSON.stringify(cleaned)),"actual save encoder applies both retirement policies")
	_expect(JSON.stringify(source)==source_before,"save encoder leaves caller untouched")

func _test_saved_copy(manager: Node, catalogs: Dictionary, slot: String) -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COPIES+slot))
	var read: Dictionary = manager._read_snapshot(COPIES+slot)
	_expect(read.get("ok",false),slot+" validates and loads")
	if not read.get("ok",false): return
	_expect(read.snapshot==original,slot+" current player copy needs no changes")
	# Inject retired goods into a valid copied save and exercise real validation,
	# read migration and transactional write without mutating the original copy.
	var state: Dictionary = read.snapshot.duplicate(true)
	for key: String in catalogs.retired_items:
		state.scene.items.loose.append({"item_key":key,"count":1,"disallowed":false,"position":[270.5,44.0,520.5],"rotation_y":0.0})
		state.scene.dwarves.roster[0].carried_items.append({"item_key":key,"count":1,"disallowed":false})
		state.scene.stockpiles.zones[0].storage_filter.items.append(key)
	manager.configure_storage_for_testing("user://retired_stone_test")
	var store = manager._file_store()
	var input := "user://retired_stone_test/injected.json"
	DirAccess.make_dir_recursive_absolute("user://retired_stone_test")
	FileAccess.open(input,FileAccess.WRITE).store_string(JSON.stringify(state))
	var migrated: Dictionary = store._read_snapshot(input)
	_expect(migrated.ok and migrated.snapshot==original,slot+" read removes only injected retired items/filters")
	var before := JSON.stringify(state)
	var error: String = manager._commit_snapshot(state,manager._quick_save_paths())
	_expect(error.is_empty(),slot+" transactional write: "+error)
	_expect(JSON.stringify(state)==before,slot+" write preserves caller")
	var reread: Dictionary = manager._read_snapshot(manager._quick_save_paths().primary)
	_expect(reread.ok and reread.snapshot==original,slot+" written copy roundtrips all unrelated state")
	state.scene.items.loose.back().count=-1
	_expect(not manager._commit_snapshot(state,manager._quick_save_paths()).is_empty(),"malformed retired content rejected before migration")

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
