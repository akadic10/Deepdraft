extends SceneTree

const Migration = preload("res://scripts/components/RetiredFurnitureMigration.gd")
const RECOVERY := "res://tmp/retired_furniture_20261018/player_saves_before/"
const CANDIDATES := "res://tmp/retired_furniture_20261018/player_saves_cleaned/"
var failures: Array[String] = []
var checks := 0
var reports := {}

func _init() -> void: _run.call_deferred()

func _run() -> void:
	for id in ["SaveManager", "WorldClock", "TaskManager", "RoomManager"]: root.get_node(id).set_process(false)
	var manager := root.get_node("SaveManager")
	var retired: Dictionary = manager._capture_catalogs().retired_furniture
	_expect(retired.size() == 15, "15 explicitly retired identities")
	var controller = load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var defs: Dictionary = controller.get_defs()
	var catalog: Dictionary = root.get_node("UIRegistry").get_place_catalog()
	for key in retired:
		_expect(not defs.has(key), key + " absent from live definitions")
		_expect(catalog.items.filter(func(row): return row.key == key).is_empty(), key + " absent from Place")
	for key in ["base:furniture:settlement_flag", "base:water:wet_stone", "base:water:dry_stone", "base:furniture:log_table", "base:furniture:log_chair", "base:furniture:board_game_table"]:
		_expect(defs.has(key), key + " retained")
	controller.free()
	_test_all_owners(retired)
	# Optional explicit integration pass: use the immutable recovery copies, never
	# discover or write the player's real profile from a regression test.
	if "--prepare-player-copies" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(CANDIDATES)
		for slot in ["quicksave.json", "quicksave.backup.json", "autosave.json", "autosave.backup.json"]:
			_test_copy(manager, retired, slot)
		FileAccess.open(CANDIDATES+"report.json", FileAccess.WRITE).store_string(JSON.stringify(reports,"  "))
	for failure in failures: push_error(failure)
	print("RETIRED_FURNITURE_PASS " if failures.is_empty() else "RETIRED_FURNITURE_FAIL ", checks, " checks ", JSON.stringify(reports))
	quit(0 if failures.is_empty() else 1)

func _test_all_owners(retired: Dictionary) -> void:
	var gone := "base:resources:furniture:barrel"
	var wood := "base:resources:wood:oak"
	var keep := "base:resources:furniture:log_chair"
	var filter := {"tags":["stockpile_wood"], "items":[gone,wood], "excluded_items":[gone,keep]}
	var fixture := {"scene":{
		"items":{"loose":[{"item_key":gone,"count":2},{"item_key":wood,"count":3}]},
		"stockpiles":{"zones":[{"stacks":[{"item":gone,"count":4},{"item":wood,"count":5}],"storage_filter":filter.duplicate(true)}]},
		"dwarves":{"roster":[{"id":1,"carried_items":[{"item_key":gone,"count":6},{"item_key":keep,"count":1}]}]},
		"furniture":{
			"installed":[
				{"id":4,"key":"base:furniture:barrel","origin":[12,20,14], "inventory":{wood:7,gone:2},
					"instances":[{"item":wood,"count":3,"material_id":"base:material:oak","instance_id":"special","disallowed":true},{"item":gone,"count":1,"disallowed":false}]},
				{"id":5,"key":"base:furniture:log_table","inventory":{gone:2,wood:1},"instances":[{"item":gone,"count":1}],"storage_filter":filter.duplicate(true)},
				{"id":6,"key":"base:furniture:settlement_flag"},
				{"id":7,"key":"mod:furniture:barrel"}],
			"ghosts":[{"key":"base:furniture:barrel","move_id":"furniture_move:1"},{"key":"base:furniture:barrel"},{"key":"base:furniture:log_chair","move_id":"furniture_move:2"}],
			"moves":{"next_id":3,"records":{
				"furniture_move:1":{"key":"base:furniture:barrel","installed_id":4,"storage_filter":filter.duplicate(true)},
				"furniture_move:2":{"key":"base:furniture:log_chair","installed_id":-1,"storage_filter":filter.duplicate(true)}}}},
		"water":{"stones":{"wet":{"kind":"wet"},"dry":{"kind":"dry"}}},
		"terrain":{"edits":[{"cell":[1,2,3]}]}}}
	var before := JSON.stringify(fixture)
	var cleaned := Migration.cleaned_copy(fixture,retired)
	_expect(JSON.stringify(fixture)==before,"cleaned copy leaves caller snapshot unchanged")
	var report := Migration.apply(fixture,retired)
	_expect(fixture==cleaned,"copy and in-place migrations agree")
	_expect(report.installed==1 and report.ghosts==2 and report.moves==1,"installed, ghost and move cleanup")
	_expect(report.packed_units==16,"loose, stockpile, carried and inventory units counted exactly once")
	_expect(report.spilled_units==7,"all seven wood units preserved without double counting instances")
	_expect(report.filter_entries==6,"retired filter keys removed from retained owners")
	_expect(fixture.scene.furniture.installed.size()==3,"ordinary table, flag and unknown/modded key survive")
	_expect(fixture.scene.furniture.moves.next_id==3,"identity counter retained")
	_expect(fixture.scene.furniture.moves.records.has("furniture_move:2"),"unrelated move survives")
	_expect(fixture.scene.items.loose.size()==3,"original goods and two spilled stacks")
	var drop: Dictionary=fixture.scene.items.loose[1]
	_expect(drop.count==3 and drop.disallowed and drop.instance_id=="special" and drop.material_id=="base:material:oak","spilled instance keeps permission, identity and material")
	_expect(drop.position==[12.5,21.0,14.5],"spilled goods rest at removed container's floor")
	_expect(fixture.scene.items.loose[2].count==4,"remaining aggregate inventory is spilled once")
	_expect(fixture.scene.water==cleaned.scene.water and fixture.scene.terrain==cleaned.scene.terrain,"water and terrain untouched")
	var again := Migration.apply(fixture,retired)
	_expect(fixture==cleaned and again.values().all(func(v): return v==0),"migration is idempotent")

func _test_copy(manager: Node, retired: Dictionary, slot: String) -> void:
	var path := RECOVERY+slot
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var read: Dictionary = manager._read_snapshot(path)
	_expect(read.get("ok",false),slot+" validates before and after migration")
	if not read.get("ok",false): return
	var cleaned: Dictionary = read.snapshot
	reports[slot]=read.retirement
	for key in original:
		if key!="scene": _expect(original[key]==cleaned[key],slot+" unchanged "+key)
	for section in original.scene:
		if section not in ["furniture","items","stockpiles","dwarves"]:
			_expect(original.scene[section]==cleaned.scene[section],slot+" unchanged "+section)
	# These player slots have no carried retired furniture, so full dwarf state
	# (not merely the roster count) must be byte-for-byte equivalent as data.
	_expect(original.scene.dwarves==cleaned.scene.dwarves,slot+" entire dwarf state preserved")
	_expect(original.scene.items==cleaned.scene.items,slot+" unrelated loose items preserved")
	_expect(cleaned.scene.furniture.installed.all(func(row): return not retired.has(row.key)),slot+" no retired installed furniture")
	_expect(cleaned.scene.furniture.installed.any(func(row): return row.key=="base:furniture:settlement_flag"),slot+" installed settlement flag preserved")
	var stable := cleaned.duplicate(true)
	_expect(Migration.apply(stable,retired).values().all(func(v): return v==0) and stable==cleaned,slot+" no duplicate second cleanup")
	_expect(manager._write_text_file(CANDIDATES+slot,JSON.stringify(cleaned,"\t")).is_empty(),slot+" candidate saved")
	_expect(manager._read_snapshot(CANDIDATES+slot).get("ok",false),slot+" candidate re-read valid")
	if slot=="quicksave.json":
		_expect(read.retirement.installed==15 and read.retirement.packed_units==14,"current quicksave expected removals")
		_test_transaction(manager,original,cleaned)
		_test_identity_contents(manager,retired,cleaned)

func _test_identity_contents(manager: Node, retired: Dictionary, source: Dictionary) -> void:
	var state := source.duplicate(true)
	var empty_filter := {"tags":[],"items":[],"excluded_items":[]}
	var shelf := "base:furniture:storage_shelf"
	var barrel := "base:furniture:barrel"
	var wood := "base:resources:wood:oak_log"
	# Exercise both kinds of in-flight Move and a packed water stone inside a
	# removed container. All of these must satisfy the real identity validator.
	state.scene.water.stones.wet.placed=false
	state.scene.water.stones.wet.packing=false
	state.scene.furniture.installed.append({"id":9001,"key":shelf,"origin":[50,20,50],"yaw":0,"layout_version":2,"flagged_uninstall":true,
		"inventory":{"base:resources:water:wet_stone":1,wood:3},
		"instances":[{"item":"base:resources:water:wet_stone","count":1,"instance_id":"wet","disallowed":true},
			{"item":wood,"count":1,"material_id":"base:material:oak","disallowed":true}]})
	state.scene.furniture.moves={"next_id":3,"records":{
		"furniture_move:1":{"key":shelf,"installed_id":9001,"assigned_dwarf_id":-1,"storage_filter":empty_filter.duplicate(true)},
		"furniture_move:2":{"key":barrel,"installed_id":-1,"assigned_dwarf_id":-1,"storage_filter":empty_filter.duplicate(true)}}}
	for i in [1,2]:
		state.scene.furniture.ghosts.append({"id":9100+i,"key":shelf if i==1 else barrel,"origin":[55+i,20,50],"yaw":1,"layout_version":2,"move_id":"furniture_move:%d"%i})
	state.scene.items.loose.append({"item_key":"base:resources:furniture:barrel","count":1,"position":[56.5,21.0,50.5],"rotation_y":0.0,"disallowed":false,"instance_id":"furniture_move:2"})
	_expect(manager._validate_snapshot(state).is_empty(),"legacy Move/container/stone fixture is valid before cleanup")
	var water_before: Dictionary=state.scene.water.duplicate(true)
	var report := Migration.apply(state,retired)
	_expect(manager._validate_snapshot(state).is_empty(),"spilled identities and removed Moves validate after cleanup")
	_expect(report.installed==1 and report.moves==2 and report.ghosts==2 and report.packed_units==1 and report.spilled_units==4,"both Move phases removed and ordinary contents conserved")
	_expect(state.scene.water==water_before,"container cleanup never rewrites water identity")
	var stones: Array=state.scene.items.loose.filter(func(row): return row.get("instance_id","")=="wet")
	_expect(stones.size()==1 and stones[0].disallowed,"packed wet stone survives exactly once with permission")

func _test_transaction(manager: Node, original: Dictionary, expected: Dictionary) -> void:
	manager.configure_storage_for_testing("user://retirement_transaction_test")
	var before := JSON.stringify(original)
	var paths: Dictionary=manager._quick_save_paths()
	_expect(manager._commit_snapshot(original,paths).is_empty(),"real file transaction accepts and cleans legacy save")
	_expect(JSON.stringify(original)==before,"commit never mutates caller snapshot")
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.primary))
	_expect(raw==expected,"committed bytes contain cleaned snapshot")
	var corrupt := original.duplicate(true)
	corrupt.scene.erase("items")
	_expect(not manager._commit_snapshot(corrupt,paths).is_empty(),"malformed save rejected before migration")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(paths.primary))==expected,"failed transaction preserves valid primary")

func _expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
