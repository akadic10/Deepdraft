extends Node

## Versioned manual/autosave coordinator. The deterministic world seed is the
## base; scene owners persist only authoritative player/colony deltas.
## Scheduler tasks, reservations, renderer caches, and derived interior/nav
## data rebuild.

const SAVE_DIRECTORY := "user://saves"
const SAVE_PATH := "user://saves/quicksave.json"
const BACKUP_SAVE_PATH := "user://saves/quicksave.backup.json"
const TEMP_SAVE_PATH := "user://saves/quicksave.tmp.json"
const BACKUP_STAGE_PATH := "user://saves/quicksave.backup.tmp.json"
const AUTOSAVE_PATH := "user://saves/autosave.json"
const AUTOSAVE_BACKUP_PATH := "user://saves/autosave.backup.json"
const AUTOSAVE_TEMP_PATH := "user://saves/autosave.tmp.json"
const AUTOSAVE_BACKUP_STAGE_PATH := "user://saves/autosave.backup.tmp.json"
const AUTOSAVE_INTERVAL_SECONDS := 300.0
const SAVE_SCHEMA_VERSION := 2
const OWNER_GROUP := "save_state_owner"
const FileStore = preload("res://scripts/components/SaveFileStore.gd")
const SnapshotValidator := preload("res://scripts/components/SaveSnapshotValidator.gd")

signal save_finished(success: bool)
signal autosave_finished(success: bool)
signal load_finished(success: bool, used_backup: bool)

# At most one transaction owns either slot. Completion is consumed only after
# joining the worker; normal frames never wait for unfinished I/O.
var _save_task := -1
var _save_job: RefCounted
var _saving_autosave := false
var _save_started_usec := 0
var last_save_profile: Dictionary = {}
var _capture_profile: Dictionary = {}
var _captured_sections: Array[String] = []
var _dock_ui: Node = null
var _pending_restore: Dictionary = {}
var _loading: bool = false
var _ready_frames: int = 0
var _loading_from_backup: bool = false
var _loading_autosave: bool = false
var _clock_was_paused_before_load: bool = false
var _autosave_elapsed_seconds: float = 0.0
# ── LoadPerformance stamps ────────────────────────────────────────────────────
# Times the load pipeline: request → read/validate → scene reload + regen wait
# → per-owner restore. Printed by _print_load_performance at restore end. The
# post-restore overview tile rebuild is timed separately by SliceTiming.
var _load_request_msec: int = 0
var _load_validated_msec: int = 0

var _save_directory_path: String = SAVE_DIRECTORY
var _save_path: String = SAVE_PATH
var _backup_save_path: String = BACKUP_SAVE_PATH
var _temp_save_path: String = TEMP_SAVE_PATH
var _backup_stage_path: String = BACKUP_STAGE_PATH
var _autosave_path: String = AUTOSAVE_PATH
var _autosave_backup_path: String = AUTOSAVE_BACKUP_PATH
var _autosave_temp_path: String = AUTOSAVE_TEMP_PATH
var _autosave_backup_stage_path: String = AUTOSAVE_BACKUP_STAGE_PATH

## Save request return values mean accepted; *_finished signals mean committed.
func is_saving() -> bool:
	return _save_task >= 0

func is_loading() -> bool:
	return _loading


## Isolates automated tests from the player's real quick-save files. This is
## intentionally unavailable in release builds.
func configure_storage_for_testing(directory: String) -> bool:
	if is_saving() or _loading: return false
	if not OS.is_debug_build():
		push_error("SaveManager: test storage can only be configured in a debug build.")
		return false
	var normalized := directory.trim_suffix("/")
	if not normalized.begins_with("user://") or normalized == "user://":
		push_error("SaveManager: test storage must be a dedicated user:// subdirectory.")
		return false
	_save_directory_path = normalized
	_save_path = normalized.path_join("quicksave.json")
	_backup_save_path = normalized.path_join("quicksave.backup.json")
	_temp_save_path = normalized.path_join("quicksave.tmp.json")
	_backup_stage_path = normalized.path_join("quicksave.backup.tmp.json")
	_autosave_path = normalized.path_join("autosave.json")
	_autosave_backup_path = normalized.path_join("autosave.backup.json")
	_autosave_temp_path = normalized.path_join("autosave.tmp.json")
	_autosave_backup_stage_path = normalized.path_join("autosave.backup.tmp.json")
	_autosave_elapsed_seconds = 0.0
	return true


func reset_storage_after_testing() -> void:
	if is_saving() or _loading: return
	_save_directory_path = SAVE_DIRECTORY
	_save_path = SAVE_PATH
	_backup_save_path = BACKUP_SAVE_PATH
	_temp_save_path = TEMP_SAVE_PATH
	_backup_stage_path = BACKUP_STAGE_PATH
	_autosave_path = AUTOSAVE_PATH
	_autosave_backup_path = AUTOSAVE_BACKUP_PATH
	_autosave_temp_path = AUTOSAVE_TEMP_PATH
	_autosave_backup_stage_path = AUTOSAVE_BACKUP_STAGE_PATH
	_autosave_elapsed_seconds = 0.0


func register_dock(dock: Node) -> void:
	_dock_ui = dock
	if not dock.is_connected("save_game_requested", request_save):
		dock.connect("save_game_requested", request_save)
	if not dock.is_connected("load_game_requested", request_load):
		dock.connect("load_game_requested", request_load)
	if not dock.is_connected("load_autosave_requested", request_load_autosave):
		dock.connect("load_autosave_requested", request_load_autosave)
	if _loading:
		_notify("Loading autosave…" if _loading_autosave else "Loading quick save…")


func generation_seed_for_new_scene(fallback: int) -> int:
	if _loading and not _pending_restore.is_empty():
		return int(_pending_restore.get("world_seed", fallback))
	return fallback


## Slice height stored in the pending restore snapshot, or `fallback` when no
## load is in flight. WorldRenderer polls this right before queueing the first
## overview tiles, so a load builds every tile cut at the restored plane the
## FIRST time — previously the startup tiles built at the default plane (127)
## and the slice restore (priority 80) re-queued and re-built them.
## SliceController's own restore then applies the same value and its setter
## no-ops the requeue (old_y == v).
func pending_slice_for_new_scene(fallback: int) -> int:
	if not _loading or _pending_restore.is_empty():
		return fallback
	var scene_state: Dictionary = _pending_restore.get("scene", {})
	var slice_state: Dictionary = scene_state.get("slice", {})
	return int(slice_state.get("slice_y", fallback))


func request_save() -> bool:
	if _loading: return _fail_save("A save is currently loading.")
	if is_saving():
		_notify("A save is still finishing.")
		return false
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready",false)):
		return _fail_save("The world is still generating; try Save again shortly.")
	return _start_save(false)

func request_autosave() -> bool:
	if _loading or is_saving() or not _world_ready_for_autosave(): return false
	return _start_save(true)

func _start_save(autosave: bool) -> bool:
	_save_started_usec=Time.get_ticks_usec()
	_save_job=_file_store()
	_save_job.paths=_absolute_paths(_autosave_paths() if autosave else _quick_save_paths())
	_save_job.snapshot=_capture_snapshot()
	_save_job.sections=_captured_sections
	_captured_sections=[]
	_saving_autosave=autosave
	last_save_profile={"capture_ms":(Time.get_ticks_usec()-_save_started_usec)/1000.0,"owners":_capture_profile.duplicate()}
	_save_task=WorkerThreadPool.add_task(_save_job.run,false,"Validated colony save")
	if not autosave: _notify("Saving…")
	return true

func _capture_snapshot() -> Dictionary:
	_capture_profile={}
	_captured_sections=[]
	var state: Dictionary={"schema_version":SAVE_SCHEMA_VERSION,"project":"Deepdraft",
		"saved_at_utc":Time.get_datetime_string_from_system(true,true),"world_seed":WorldGenerator.world_seed,
		"clock":WorldClock.serialize_state().duplicate(true),"weather":WeatherManager.serialize_state().duplicate(true),
		"scene":{"terrain":{"edits":WorldData.serialize_edits()},"exploration":InteriorTracker.serialize_exploration()}}
	for owner in get_tree().get_nodes_in_group(OWNER_GROUP):
		if not owner.has_method("save_section_key") or not owner.has_method("serialize_state"): continue
		var key:=String(owner.call("save_section_key"))
		if key.is_empty(): continue
		var started:=Time.get_ticks_usec()
		if owner.has_method("capture_save_state"):
			state.scene[key]=owner.call("capture_save_state")
			_captured_sections.append(key)
		else:
			state.scene[key]=owner.call("serialize_state").duplicate(true)
		_capture_profile[key]=(Time.get_ticks_usec()-started)/1000.0
	return state

func _poll_save() -> void:
	if _save_task<0 or not WorkerThreadPool.is_task_completed(_save_task): return
	var started:=Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(_save_task)
	var error: String=_save_job.result_error
	var autosave:=_saving_autosave
	last_save_profile["worker"]=_save_job.timings.duplicate()
	last_save_profile["elapsed_ms"]=(Time.get_ticks_usec()-_save_started_usec)/1000.0
	last_save_profile["success"]=error.is_empty()
	for warning in _save_job.warnings: push_warning(warning)
	_save_job=null
	_save_task=-1
	last_save_profile["completion_ms"]=(Time.get_ticks_usec()-started)/1000.0
	if error.is_empty():
		_notify("Autosaved." if autosave else "Game saved.")
		print("SaveManager: validated %s written." % ("autosave" if autosave else "quick save"))
	else:
		_notify(("Autosave failed: " if autosave else "Save failed: ")+error,true)
	if autosave: autosave_finished.emit(error.is_empty())
	else: save_finished.emit(error.is_empty())

func _exit_tree() -> void:
	# Closing after an accepted save must not abandon a file replacement.
	if _save_task>=0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task=-1
		if not _save_job.result_error.is_empty(): push_warning("SaveManager: closing save failed: "+_save_job.result_error)
		_save_job=null


func _build_snapshot() -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"project": "Deepdraft",
		"saved_at_utc": Time.get_datetime_string_from_system(true, true),
		"world_seed": WorldGenerator.world_seed,
		"clock": WorldClock.serialize_state(),
		"weather": WeatherManager.serialize_state(),
		"scene": _collect_scene_state(),
	}


func request_load() -> bool:
	return _request_load_slot(_quick_save_paths(), false)


func request_load_autosave() -> bool:
	return _request_load_slot(_autosave_paths(), true)


func _request_load_slot(paths: Dictionary, is_autosave: bool) -> bool:
	if is_saving(): return _fail_load("A save is still finishing; try Load again shortly.")
	if _loading:
		return _fail_load("A save is already loading.")

	_load_request_msec = Time.get_ticks_msec()
	var primary_path := String(paths.get("primary", ""))
	var backup_path := String(paths.get("backup", ""))
	var slot_name := "autosave" if is_autosave else "quick save"
	var primary_result := _read_snapshot(primary_path)
	var selected_result: Dictionary = primary_result
	var use_backup := false
	if not bool(primary_result.get("ok", false)):
		var backup_result := _read_snapshot(backup_path)
		if not bool(backup_result.get("ok", false)):
			if bool(primary_result.get("missing", false)) \
					and bool(backup_result.get("missing", false)):
				return _fail_load("No autosave exists yet." if is_autosave else "No quick save exists yet.")
			var details: Array[String] = []
			if not bool(primary_result.get("missing", false)):
				details.append("primary %s" % String(primary_result.get("error", "is invalid")))
			if not bool(backup_result.get("missing", false)):
				details.append("backup %s" % String(backup_result.get("error", "is invalid")))
			return _fail_load("Load failed: %s." % "; ".join(details))
		selected_result = backup_result
		use_backup = true
		push_warning("SaveManager: primary %s unavailable (%s); using backup." \
			% [slot_name, String(primary_result.get("error", "missing"))])
		var repair_error := _restore_primary_from_backup(paths)
		if not repair_error.is_empty():
			push_warning("SaveManager: %s backup is valid but primary repair failed: %s" \
				% [slot_name, repair_error])

	var snapshot: Dictionary = selected_result.get("snapshot", {})
	_load_validated_msec = Time.get_ticks_msec()
	_pending_restore = preload("res://scripts/components/TerrainSaveMigration.gd").upgrade(snapshot)
	_loading = true
	_ready_frames = 0
	_loading_from_backup = use_backup
	_loading_autosave = is_autosave
	_clock_was_paused_before_load = WorldClock.paused
	if is_autosave:
		_notify("Recovering autosave backup…" if use_backup else "Loading autosave…")
	else:
		_notify("Recovering backup save…" if use_backup else "Loading quick save…")
	WorldClock.set_paused(true)
	TaskManager.reset_runtime_state()
	StockpileManager.reset_runtime_state()
	InteriorTracker.clear_runtime_state()
	RoomManager.clear_runtime_state()
	NavGrid.clear_runtime_state()
	PlacedEntityRegistry.clear_runtime_state()
	WorldGenerator.prepare_for_world_reload()
	WorldData.clear_world()
	var scene_tree := get_tree()
	var scene_changed_callback := Callable(self, "_on_scene_reloaded")
	if not scene_tree.scene_changed.is_connected(scene_changed_callback):
		scene_tree.scene_changed.connect(scene_changed_callback, CONNECT_ONE_SHOT)
	var reload_error := scene_tree.reload_current_scene()
	if reload_error != OK:
		if scene_tree.scene_changed.is_connected(scene_changed_callback):
			scene_tree.scene_changed.disconnect(scene_changed_callback)
		_loading = false
		_pending_restore.clear()
		WorldClock.set_paused(_clock_was_paused_before_load)
		var failed_from_backup := _loading_from_backup
		_loading_from_backup = false
		_loading_autosave = false
		_notify("Load failed: the world scene could not be reloaded.", true)
		load_finished.emit(false, failed_from_backup)
		return false
	return true


func _on_scene_reloaded() -> void:
	if _loading:
		SkyController.rebind_to_current_scene()


func _process(delta: float) -> void:
	_poll_save()
	if not _loading:
		_tick_autosave(delta)
		return
	if _pending_restore.is_empty():
		return
	var stats := WorldGenerator.get_streaming_stats()
	if not bool(stats.get("maps_ready", false)) or WorldGenerator.is_generating():
		_ready_frames = 0
		return
	# Two quiet frames let scene owners and seed-derived flora finish their
	# ready/deferred hookups before player state is reapplied.
	_ready_frames += 1
	if _ready_frames < 2:
		return
	_restore_pending_snapshot()


func _tick_autosave(delta: float) -> void:
	if is_saving() or not _world_ready_for_autosave():
		return
	_autosave_elapsed_seconds += delta
	if _autosave_elapsed_seconds < AUTOSAVE_INTERVAL_SECONDS:
		return
	# Reset after the attempt so a disk error reports at most once per interval.
	_autosave_elapsed_seconds = 0.0
	request_autosave()


func _world_ready_for_autosave() -> bool:
	var stats := WorldGenerator.get_streaming_stats()
	return bool(stats.get("maps_ready", false)) and not WorldGenerator.is_generating()


func _collect_scene_state() -> Dictionary:
	var result: Dictionary = {"terrain":{"edits":WorldData.serialize_edits()},"exploration":InteriorTracker.serialize_exploration()}
	for state_owner in get_tree().get_nodes_in_group(OWNER_GROUP):
		if not state_owner.has_method("save_section_key") or not state_owner.has_method("serialize_state"):
			continue
		var key := String(state_owner.call("save_section_key"))
		if key.is_empty():
			continue
		result[key] = state_owner.call("serialize_state")
	return result


func _restore_pending_snapshot() -> void:
	var t_restore_start := Time.get_ticks_msec()
	var owner_lines: Array[String] = []
	var scene_state: Dictionary = _pending_restore.get("scene", {})
	var owners: Array = get_tree().get_nodes_in_group(OWNER_GROUP)
	owners.sort_custom(func(a: Node, b: Node) -> bool:
		var ap := int(a.call("save_restore_priority")) if a.has_method("save_restore_priority") else 100
		var bp := int(b.call("save_restore_priority")) if b.has_method("save_restore_priority") else 100
		return ap < bp)
	# Large settlements restore tens of thousands of mined/constructed blocks
	# synchronously. Queue one mesh/nav invalidation per chunk, not per voxel,
	# while preserving exact edits for water, interiors and other live owners.
	WorldData.begin_edit_batch()
	WorldData.restore_terrain(scene_state.terrain)
	InteriorTracker.restore_exploration(scene_state.exploration)
	for state_owner in owners:
		if not state_owner.has_method("save_section_key") or not state_owner.has_method("restore_state"):
			continue
		var key := String(state_owner.call("save_section_key"))
		if scene_state.has(key):
			var t_owner := Time.get_ticks_msec()
			state_owner.call("restore_state", scene_state[key] as Dictionary)
			owner_lines.append("    %s: %d ms" % [key, Time.get_ticks_msec() - t_owner])
	WorldData.end_edit_batch()

	var t_owners_end := Time.get_ticks_msec()
	StockpileManager.rebuild_totals()
	WorldClock.restore_state(_pending_restore.get("clock", {}) as Dictionary)
	WeatherManager.restore_state(_pending_restore.get("weather", {}) as Dictionary)
	_print_load_performance(t_restore_start, t_owners_end, owner_lines)
	var restored_from_backup := _loading_from_backup
	var restored_autosave := _loading_autosave
	_pending_restore.clear()
	_loading = false
	_ready_frames = 0
	_loading_from_backup = false
	_loading_autosave = false
	_autosave_elapsed_seconds = 0.0
	if restored_autosave:
		_notify("Autosave backup recovered and loaded." if restored_from_backup else "Autosave loaded.")
	else:
		_notify("Backup recovered and loaded." if restored_from_backup else "Game loaded.")
	var slot_name := "autosave" if restored_autosave else "quick save"
	print("SaveManager: %s%s restored." % ["backup " if restored_from_backup else "", slot_name])
	load_finished.emit(true, restored_from_backup)


## Where did load time go? request→validate is disk + JSON parse; validate→
## restore-start is the scene reload plus the FULL deterministic regen (map
## precompute dominates — the same ~10 s StartupPerformance reports on a cold
## boot) plus the two quiet frames; then each owner's restore_state is timed
## individually so growth in one section (e.g. mined_blocks) shows up by name.
## The overview tile rebuild the restored slice triggers AFTER this point is
## reported by SliceTiming when its queue drains.
func _print_load_performance(t_restore_start: int, t_owners_end: int, owner_lines: Array[String]) -> void:
	var t_end := Time.get_ticks_msec()
	print("LoadPerformance:")
	print("  total_request_to_restored: %.3f s" % (float(t_end - _load_request_msec) / 1000.0))
	print("  read_validate: %d ms" % (_load_validated_msec - _load_request_msec))
	print("  reload_regen_wait: %.3f s (map precompute + quiet frames — see StartupPerformance)" \
		% (float(t_restore_start - _load_validated_msec) / 1000.0))
	print("  restore_owners: %d ms" % (t_owners_end - t_restore_start))
	for line in owner_lines:
		print(line)
	print("  totals_clock_weather: %d ms" % (t_end - t_owners_end))
	print("  note: post-restore overview tile rebuild reported by SliceTiming.")


func _quick_save_paths() -> Dictionary:
	return {
		"primary": _save_path,
		"backup": _backup_save_path,
		"temp": _temp_save_path,
		"backup_stage": _backup_stage_path,
	}


func _autosave_paths() -> Dictionary:
	return {
		"primary": _autosave_path,
		"backup": _autosave_backup_path,
		"temp": _autosave_temp_path,
		"backup_stage": _autosave_backup_stage_path,
	}


func _capture_catalogs() -> Dictionary:
	var blocks := {}
	for key in BlockRegistry._key_to_id:
		blocks[String(key)]={"kind":String(BlockRegistry.get_def(key).get("kind","void")),
			"solid":BlockRegistry.is_solid(BlockRegistry.get_id(key))}
	var construction := {}
	for key in BlockRegistry._construction_defs:
		if not BlockRegistry.get_construction_def(key).is_empty(): construction[key]=true
	var materials := {"":true}
	for key in CraftMaterials.definitions: materials[key]=true
	return {"blocks":blocks,"construction":construction,"materials":materials}


func _file_store() -> RefCounted:
	var store:=FileStore.new()
	store.directory=ProjectSettings.globalize_path(_save_directory_path)
	store.schema_version=SAVE_SCHEMA_VERSION
	store.catalogs=_capture_catalogs()
	return store

func _absolute_paths(paths: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in paths: result[key]=ProjectSettings.globalize_path(paths[key])
	return result

## Synchronous helpers for reads/recovery and transaction fault fixtures only.
## Gameplay writes enter _start_save and run the same transaction on a worker.
func _commit_snapshot(snapshot: Dictionary, paths: Dictionary) -> String:
	if is_saving(): return "a save is still finishing."
	var store:=_file_store()
	var result: String=store._commit_snapshot(snapshot,_absolute_paths(paths))
	for warning in store.warnings: push_warning(warning)
	return result

func _restore_primary_from_backup(paths: Dictionary) -> String:
	return _file_store()._restore_primary_from_backup(_absolute_paths(paths))

func _read_snapshot(path: String) -> Dictionary:
	return _file_store()._read_snapshot(ProjectSettings.globalize_path(path))

func _write_text_file(path: String, contents: String) -> String:
	return _file_store()._write_text_file(ProjectSettings.globalize_path(path),contents)

func _remove_if_exists(path: String) -> String:
	return _file_store()._remove_if_exists(ProjectSettings.globalize_path(path))


func _fail_save(message: String) -> bool:
	_notify(message, true)
	save_finished.emit(false)
	return false


func _fail_load(message: String) -> bool:
	_notify(message, true)
	load_finished.emit(false, false)
	return false


func _validate_snapshot(snapshot: Dictionary) -> String:
	return _file_store()._validate_snapshot(snapshot)


func _notify(message: String, is_error: bool = false) -> void:
	if _dock_ui != null and is_instance_valid(_dock_ui) \
			and _dock_ui.has_method("show_persistence_status"):
		_dock_ui.call("show_persistence_status", message, is_error)
	elif is_error:
		push_warning("SaveManager: %s" % message)
	else:
		print("SaveManager: %s" % message)


func pack_v3i(value: Vector3i) -> Array:
	return [value.x, value.y, value.z]


func unpack_v3i(value: Variant) -> Vector3i:
	if not (value is Array) or (value as Array).size() < 3:
		return Vector3i.ZERO
	var a := value as Array
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


func pack_v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func unpack_v3(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() < 3:
		return Vector3.ZERO
	var a := value as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
