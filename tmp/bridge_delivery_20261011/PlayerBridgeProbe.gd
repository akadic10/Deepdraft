extends SceneTree

var loaded := false
var succeeded := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Player bridge probe timed out"); quit(1))
	var saves := root.get_node("SaveManager")
	saves.configure_storage_for_testing("user://bridge_probe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bridge_probe"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tmp/bridge_delivery_20261011/player_quicksave.json"), ProjectSettings.globalize_path("user://bridge_probe/quicksave.json"))
	saves.load_finished.connect(func(ok: bool, _backup: bool): loaded = true; succeeded = ok)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	for i in range(12): await process_frame
	if not saves.request_load(): quit(1); return
	while not loaded: await process_frame
	if not succeeded: quit(1); return
	var clock := root.get_node("WorldClock")
	clock.set_paused(true)
	var bridges := get_first_node_in_group("bridges")
	var tasks := root.get_node("TaskManager")
	var nav := root.get_node("NavGrid")
	var stocks := root.get_node("StockpileManager")
	print("PLAYER_BRIDGE routes=",bridges.serialize_state()," kit_stock=",stocks.get_available_total("base:resources:furniture:log_bridge"))
	for route: Dictionary in bridges.routes.values():
		print("PLAYER_BRIDGE geometry=",bridges.describe(route.base,route.yaw,route.id,false)," landings=",bridges.landings(route)," source_stands=",route.source.stands)
		for agent in tasks._agents.values():
			var lengths := []
			for landing: Vector3i in bridges.landings(route): lengths.append(nav.find_path(agent.current_cell(),landing).size())
			print("PLAYER_BRIDGE dwarf=",agent.dwarf_name," cell=",agent.current_cell()," chosen=",route.source.nearest_stand_target(agent.current_cell())," paths=",lengths)
	if "--finish" in OS.get_cmdline_user_args():
		clock.set_paused(false)
		clock.set_speed(2.0)
		while not bridges.routes[1].built: await process_frame
		clock.set_paused(true)
		print("PLAYER_BRIDGE_BUILT material=",bridges.routes[1].material_id," kits=",stocks.get_available_total("base:resources:furniture:log_bridge")," crossing=",nav.find_path(Vector3i(497,43,276),Vector3i(503,43,276)).size())
	quit(0)
