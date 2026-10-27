extends Node

## Versioned manual/autosave coordinator. The deterministic world seed is the
## base; scene owners persist only authoritative player/colony deltas.
## Scheduler tasks, reservations, renderer caches, and derived interior/nav
## data rebuild.
## It also moves between the title screen and the world (doc 23, "The title screen"):
## Continue, New game and Load enter the world, and Quit to main menu leaves it.
## Beside the quick save and the autosave it keeps the player's named saves (Save as…, doc 23),
## one file each in the named folder, written by the same transaction.

const SAVE_DIRECTORY := "user://saves"
const NAMED_DIRECTORY := "user://saves/named"
## A named save's slot id is this and its file's name, without the ending.
const NAMED_PREFIX := "named_"
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
const WORLD_SCENE := "res://scenes/main/debug_world.tscn"
const TITLE_SCENE := "res://scenes/main/title_screen.tscn"
## The title screen's group: from it, the world is entered rather than reloaded.
const TITLE_GROUP := "title_screen"
const FileStore = preload("res://scripts/components/SaveFileStore.gd")
const SnapshotValidator := preload("res://scripts/components/SaveSnapshotValidator.gd")
const SaveName = preload("res://scripts/components/SaveName.gd")

signal save_finished(success: bool)
signal autosave_finished(success: bool)
signal load_finished(success: bool, used_backup: bool)

# At most one transaction owns either slot. Completion is consumed only after
# joining the worker; normal frames never wait for unfinished I/O.
var _save_task := -1
var _save_job: RefCounted
var _saving_autosave := false
## The slot being written ("quick", "auto" or a named save's id), and a named save's name.
var _saving_id := ""
var _saving_name := ""
var _save_started_usec := 0
var last_save_profile: Dictionary = {}
var _capture_profile: Dictionary = {}
var _captured_sections: Array[String] = []
var _dock_ui: Node = null
var _pending_restore: Dictionary = {}
var _loading: bool = false
var _ready_frames: int = 0
var _loading_from_backup: bool = false
## What is loading: its slot id, and its name as the notices give it ("quick save",
## "autosave" or a named save's name in quotes).
var _loading_id := ""
var _loading_label := ""
var _clock_was_paused_before_load: bool = false
var _autosave_elapsed_seconds: float = 0.0
var _startup_checked := false
var _starting_new_game := false
## When this colony was saved to each slot, by slot id (Unix time): the save it was loaded
## from, then each save of it. A new game starts with none, and deleting a slot takes it
## out, so "Last saved" never names a save that is gone.
var _colony_saves: Dictionary = {}
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
var _named_directory: String = NAMED_DIRECTORY

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
	_named_directory = normalized.path_join("named")
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
	_named_directory = NAMED_DIRECTORY
	_autosave_elapsed_seconds = 0.0


## The dock shows save and load messages as toasts. The game menu (doc 23) asks for saves,
## loads and new games.
func register_dock(dock: Node) -> void:
	_dock_ui = dock
	if _starting_new_game:
		_notify("Starting a new game…")
	elif _loading:
		_notify("Loading %s…" % _loading_label)


func generation_seed_for_new_scene(fallback: int) -> int:
	# Resolve startup before generation so only the selected world's seed is built.
	# Ordinary scene reloads never auto-resume again.
	if not _startup_checked:
		_startup_checked = true
		_load_request_msec = Time.get_ticks_msec()
		var latest := _latest_valid_save()
		if not latest.is_empty():
			_prepare_restore(latest.snapshot, latest.id, latest.label, latest.backup)
	if _starting_new_game:
		WorldClock.reset_for_new_game()
		return 0 # WorldGenerator chooses a fresh seed.
	if _loading and not _pending_restore.is_empty():
		return int(_pending_restore.get("world_seed", fallback))
	return fallback


## Read only committed slots, newest first: the quick save, the autosave and the named saves.
## Startup recovery never rewrites a damaged primary; manual Load retains its existing repair
## behavior. At startup, saves that all fail say a new world starts instead; the title's
## Continue says so itself.
func _latest_valid_save(at_startup := true) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for slot: Dictionary in _slot_files():
		for key in ["primary", "backup"]:
			var path := String(slot.paths[key])
			if FileAccess.file_exists(path):
				candidates.append({"path": path, "id": slot.id, "autosave": slot.id == "auto", "rank": slot.rank,
					"backup": key == "backup", "time": _save_timestamp(path),
					"modified": FileAccess.get_modified_time(path)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time != b.time: return a.time > b.time
		if a.backup != b.backup: return not a.backup
		if a.modified != b.modified: return a.modified > b.modified
		return a.rank < b.rank)
	for candidate in candidates:
		var result := _read_snapshot(candidate.path)
		if result.get("ok", false):
			candidate["snapshot"] = result.snapshot
			candidate["label"] = _slot_label(String(candidate.id), result.snapshot)
			return candidate
		push_warning("SaveManager: skipping %s: %s" % [candidate.path, result.get("error", "invalid save")])
	if at_startup and not candidates.is_empty():
		_notify("No valid save could be loaded; starting a new world. Existing saves are unchanged.", true)
	return {}


func _save_timestamp(path: String) -> int:
	# Our JSON writer places this metadata before the large scene payload. Avoid
	# parsing several complete colonies just to order four files.
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var header := file.get_buffer(8192).get_string_from_ascii()
		file.close()
		var pattern := RegEx.create_from_string('"saved_at_utc"\\s*:\\s*"(\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2})"')
		var found := pattern.search(header)
		if found != null:
			return Time.get_unix_time_from_datetime_string(found.get_string(1))
	# Older/noncanonical files remain loadable; validation still happens below.
	return FileAccess.get_modified_time(path)


## When this colony was last saved, as Unix time: its newest save still on disk, 0 when there
## is none.
func colony_saved_unix() -> int:
	var newest := 0
	for stamp: int in _colony_saves.values(): newest = maxi(newest, stamp)
	return newest


## The game menu's Load page (doc 23): the quick save and the autosave, then the named saves
## that exist, newest first. Each with whether it exists, when it was saved, the settlement's
## name and its date in the colony, read from the top of its file (the primary, else its
## backup) without parsing the colony. A named save also gives its name (`named`), its
## world's seed, read from the end of the file, and the room its files take (`bytes`).
func save_slots() -> Array:
	var slots: Array = [_slot_entry("quick", "Quick save", _quick_save_paths()), _slot_entry("auto", "Autosave", _autosave_paths())]
	var named: Array = []
	for stem: String in _named_stems():
		var entry := _slot_entry(NAMED_PREFIX + stem, stem, _named_paths(stem))
		if entry.exists: named.append(entry)
	named.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved_unix > b.saved_unix)
	return slots + named


func _slot_entry(id: String, name: String, paths: Dictionary) -> Dictionary:
	var path := String(paths.primary) if FileAccess.file_exists(String(paths.primary)) else String(paths.backup)
	var entry := {"id": id, "name": name, "named": id.begins_with(NAMED_PREFIX), "exists": FileAccess.file_exists(path)}
	if not entry.exists: return entry
	var file := FileAccess.open(path, FileAccess.READ)
	var header := ""
	var tail := ""
	if file != null:
		header = file.get_buffer(8192).get_string_from_utf8()
		# The world's seed sorts last, after the colony.
		file.seek(maxi(0, file.get_length() - 4096))
		tail = file.get_buffer(4096).get_string_from_utf8()
		file.close()
	entry.saved_unix = _save_timestamp(path)
	# Names keep to letters, digits, spaces, commas, hyphens and apostrophes, so no quote ends
	# one early.
	entry.colony = _header_value(header, '"colony_name"\\s*:\\s*"([^"]*)"')
	entry.season = _header_value(header, '"season"\\s*:\\s*"(\\w+)"')
	entry.day = int(_header_value(header, '"day"\\s*:\\s*(\\d+)'))
	entry.year = int(_header_value(header, '"year"\\s*:\\s*(\\d+)'))
	entry.hour = float(_header_value(header, '"hour"\\s*:\\s*([\\d.]+)'))
	if entry.named:
		var saved_name := _header_value(header, '"save_name"\\s*:\\s*"([^"]*)"')
		if not saved_name.is_empty(): entry.name = saved_name
		entry.seed = int(_header_value(tail, '"world_seed"\\s*:\\s*(\\d+)'))
		entry.bytes = _file_size(String(paths.primary)) + _file_size(String(paths.backup))
	return entry


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	if file == null: return 0
	var size := file.get_length()
	file.close()
	return size


## The first match in a save's header, or "". The clock comes first in every save.
static func _header_value(header: String, pattern: String) -> String:
	var found := RegEx.create_from_string(pattern).search(header)
	return found.get_string(1) if found != null else ""


## The title screen's Continue (doc 23): the newest valid save, chosen as launch chose it
## before the title existed. False, with a notice, when none can be read.
func request_continue() -> bool:
	if is_saving(): return _fail_load("A save is still finishing; try Continue again shortly.")
	if _loading: return _fail_load("A save is already loading.")
	_load_request_msec = Time.get_ticks_msec()
	var latest := _latest_valid_save(false)
	if latest.is_empty(): return _fail_load("No save could be loaded.")
	_prepare_restore(latest.snapshot, latest.id, latest.label, latest.backup)
	return _enter_restore(latest.backup)


## The game menu's Quit to main menu (doc 23): the world's runtime state is cleared as New
## game and Load clear it, and the title screen replaces the world. Nothing is saved here;
## the game menu saves first when the player asks it to.
func request_quit_to_title() -> bool:
	if is_saving() or _loading:
		_notify("A save or load is still finishing; try again shortly.")
		return false
	var title := load(TITLE_SCENE) as PackedScene
	if title == null:
		_notify("Quit failed: the title screen could not be opened.", true)
		return false
	_clear_world_runtime()
	_pending_restore.clear()
	_autosave_elapsed_seconds = 0.0
	_colony_saves.clear()
	return get_tree().change_scene_to_packed(title) == OK


func request_new_game() -> bool:
	if is_saving() or _loading:
		_notify("A save or load is still finishing; try New Game again shortly.")
		return false
	_startup_checked = true
	_starting_new_game = true
	_loading = true
	_pending_restore.clear()
	_autosave_elapsed_seconds = 0.0
	_clock_was_paused_before_load = WorldClock.paused
	WorldClock.set_paused(true)
	_notify("Starting a new game…")
	if not _reload_world_scene():
		_starting_new_game = false
		_loading = false
		WorldClock.set_paused(_clock_was_paused_before_load)
		_notify("New Game failed: the world scene could not be reloaded.", true)
		return false
	return true


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
	return _start_save(_quick_save_paths(), "quick")

func request_autosave() -> bool:
	if _loading or is_saving() or not _world_ready_for_autosave(): return false
	return _start_save(_autosave_paths(), "auto")


## Save as… (doc 23): the colony under the player's name, beside the quick save and the
## autosave. A name already in use, capitals aside, replaces that save; the game menu asks
## first. False, with a notice, when the name breaks the rules or the save cannot start.
func request_save_as(save_name: String) -> bool:
	var name := SaveName.clean(save_name)
	if not SaveName.is_valid(name): return _fail_save(SaveName.RULE)
	if _loading: return _fail_save("A save is currently loading.")
	if is_saving():
		_notify("A save is still finishing.")
		return false
	if not bool(WorldGenerator.get_streaming_stats().get("maps_ready",false)):
		return _fail_save("The world is still generating; try Save again shortly.")
	var stem := _named_stem_for(name)
	return _start_save(_named_paths(stem), NAMED_PREFIX + stem, name)


## The file a name is saved in: the named save that has that name, capitals aside, else a
## new file named after it and made free.
func _named_stem_for(name: String) -> String:
	for slot: Dictionary in save_slots():
		if slot.named and SaveName.key(slot.name) == SaveName.key(name): return String(slot.id).trim_prefix(NAMED_PREFIX)
	var base := SaveName.stem(name)
	var stem := base
	var count := 2
	while FileAccess.file_exists(_named_paths(stem).primary) or FileAccess.file_exists(_named_paths(stem).backup):
		stem = "%s_%d" % [base, count]
		count += 1
	return stem


## Writes the slot `id` ("quick", "auto" or a named save's) at `paths` on the worker.
func _start_save(paths: Dictionary, id: String, save_name := "") -> bool:
	var autosave := id == "auto"
	_save_started_usec=Time.get_ticks_usec()
	_save_job=_file_store()
	_save_job.directory=ProjectSettings.globalize_path(String(paths.primary).get_base_dir())
	_save_job.paths=_absolute_paths(paths)
	_save_job.snapshot=_capture_snapshot()
	# A named save keeps its name beside the clock, where the Load page reads.
	if not save_name.is_empty(): _save_job.snapshot["save_name"]=save_name
	_save_job.sections=_captured_sections
	_captured_sections=[]
	_saving_autosave=autosave
	_saving_id=id
	_saving_name=save_name
	last_save_profile={"capture_ms":(Time.get_ticks_usec()-_save_started_usec)/1000.0,"owners":_capture_profile.duplicate()}
	_save_task=WorkerThreadPool.add_task(_save_job.run,false,"Validated colony save")
	if not autosave: _notify("Saving…")
	return true

func _capture_snapshot() -> Dictionary:
	_capture_profile={}
	_captured_sections=[]
	var state: Dictionary={"schema_version":SAVE_SCHEMA_VERSION,"project":"Deepdraft",
		"saved_at_utc":Time.get_datetime_string_from_system(true,true),"world_seed":WorldGenerator.world_seed,
		"colony_name":_colony_name(),
		"clock":WorldClock.serialize_state().duplicate(true),"weather":WeatherManager.serialize_state().duplicate(true),
		"scene":{"terrain":{"edits":WorldData.serialize_edits()},"exploration":InteriorTracker.serialize_exploration()}}
	for section_owner in get_tree().get_nodes_in_group(OWNER_GROUP):
		if not section_owner.has_method("save_section_key") or not section_owner.has_method("serialize_state"): continue
		var key:=String(section_owner.call("save_section_key"))
		if key.is_empty(): continue
		var started:=Time.get_ticks_usec()
		if section_owner.has_method("capture_save_state"):
			state.scene[key]=section_owner.call("capture_save_state")
			_captured_sections.append(key)
		else:
			state.scene[key]=section_owner.call("serialize_state").duplicate(true)
		_capture_profile[key]=(Time.get_ticks_usec()-started)/1000.0
	return state

func _poll_save() -> void:
	if _save_task<0 or not WorkerThreadPool.is_task_completed(_save_task): return
	var started:=Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(_save_task)
	var error: String=_save_job.result_error
	var autosave:=_saving_autosave
	var saved_id:=_saving_id
	var save_name:=_saving_name
	_saving_id=""
	_saving_name=""
	last_save_profile["worker"]=_save_job.timings.duplicate()
	last_save_profile["elapsed_ms"]=(Time.get_ticks_usec()-_save_started_usec)/1000.0
	last_save_profile["success"]=error.is_empty()
	for warning in _save_job.warnings: push_warning(warning)
	_save_job=null
	_save_task=-1
	last_save_profile["completion_ms"]=(Time.get_ticks_usec()-started)/1000.0
	if error.is_empty():
		_colony_saves[saved_id] = int(Time.get_unix_time_from_system())
		if not save_name.is_empty(): _notify("Saved as \"%s\"." % save_name)
		else: _notify("Autosaved." if autosave else "Game saved.")
		print("SaveManager: validated %s written." % ("autosave" if autosave else ("\"%s\"" % save_name if not save_name.is_empty() else "quick save")))
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


## Synchronous serializer oracle for tests and benchmark tools: SaveWorkerChecks
## compares it with _capture_snapshot + SaveSnapshotPreparation. Not on the
## gameplay save path.
func _build_snapshot() -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"project": "Deepdraft",
		"saved_at_utc": Time.get_datetime_string_from_system(true, true),
		"world_seed": WorldGenerator.world_seed,
		"colony_name": _colony_name(),
		"clock": WorldClock.serialize_state(),
		"weather": WeatherManager.serialize_state(),
		"scene": _collect_scene_state(),
	}


## The settlement's name for the Load list (doc 23). JSON sorts the keys, so it lands beside
## the clock at the top of the file; the flag's own section keeps the name the game restores.
func _colony_name() -> String:
	var settlement := get_tree().get_first_node_in_group("settlement")
	return String(settlement.settlement_name) if settlement != null else ""


func request_load() -> bool:
	return _request_load_slot(_quick_save_paths(), "quick", "quick save")


func request_load_autosave() -> bool:
	return _request_load_slot(_autosave_paths(), "auto", "autosave")


## Loads the slot the Load page lists under `id` (`save_slots()`): "quick", "auto", or a
## named save.
func request_load_save(id: String) -> bool:
	if id == "quick": return request_load()
	if id == "auto": return request_load_autosave()
	var paths := _slot_paths(id)
	if paths.is_empty(): return _fail_load("That save no longer exists.")
	return _request_load_slot(paths, id, "\"%s\"" % _named_name(id))


## Deletes a save the Load page lists, the quick save and the autosave too, its backup with
## it. The player's own saves go to the Recycle Bin; test storage deletes outright, so tests
## never fill the player's bin. A deleted save no longer counts as this colony's last save.
## False, with a notice, when nothing was deleted.
func request_delete_save(id: String) -> bool:
	if is_saving() or _loading:
		_notify("A save or load is still finishing; try again shortly.")
		return false
	var paths := _slot_paths(id)
	if paths.is_empty() or not (FileAccess.file_exists(String(paths.primary)) or FileAccess.file_exists(String(paths.backup))):
		_notify("That save no longer exists.", true)
		return false
	var subject: String = {"quick": "The quick save", "auto": "The autosave"}.get(id, "\"%s\"" % _named_name(id))
	var to_bin := _save_directory_path == SAVE_DIRECTORY
	for key: String in ["primary", "backup", "temp", "backup_stage"]:
		var path := ProjectSettings.globalize_path(String(paths[key]))
		if not FileAccess.file_exists(path): continue
		var error := OS.move_to_trash(path) if to_bin else DirAccess.remove_absolute(path)
		if error != OK:
			_notify("%s could not be deleted (%s)." % [subject, error_string(error)], true)
			return false
	_colony_saves.erase(id)
	_notify("%s is in the Recycle Bin." % subject if to_bin else "%s was deleted." % subject)
	return true


## A slot's files by its `save_slots()` id, or {} for a named save that is gone.
func _slot_paths(id: String) -> Dictionary:
	if id == "quick": return _quick_save_paths()
	if id == "auto": return _autosave_paths()
	var stem := id.trim_prefix(NAMED_PREFIX)
	return _named_paths(stem) if id.begins_with(NAMED_PREFIX) and stem in _named_stems() else {}


## A named save's name, read from the top of its file.
func _named_name(id: String) -> String:
	for slot: Dictionary in save_slots():
		if slot.id == id: return String(slot.name)
	return id.trim_prefix(NAMED_PREFIX)


## Shows the folder the named saves are kept in, as the computer names it (Open folder).
func open_saves_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_named_directory))
	OS.shell_open(ProjectSettings.globalize_path(_named_directory))


func _request_load_slot(paths: Dictionary, id: String, label: String) -> bool:
	if is_saving(): return _fail_load("A save is still finishing; try Load again shortly.")
	if _loading:
		return _fail_load("A save is already loading.")

	_load_request_msec = Time.get_ticks_msec()
	var primary_path := String(paths.get("primary", ""))
	var backup_path := String(paths.get("backup", ""))
	var primary_result := _read_snapshot(primary_path)
	var selected_result: Dictionary = primary_result
	var use_backup := false
	if not bool(primary_result.get("ok", false)):
		var backup_result := _read_snapshot(backup_path)
		if not bool(backup_result.get("ok", false)):
			if bool(primary_result.get("missing", false)) \
					and bool(backup_result.get("missing", false)):
				return _fail_load("No %s exists yet." % label)
			var details: Array[String] = []
			if not bool(primary_result.get("missing", false)):
				details.append("primary %s" % String(primary_result.get("error", "is invalid")))
			if not bool(backup_result.get("missing", false)):
				details.append("backup %s" % String(backup_result.get("error", "is invalid")))
			return _fail_load("Load failed: %s." % "; ".join(details))
		selected_result = backup_result
		use_backup = true
		push_warning("SaveManager: primary %s unavailable (%s); using backup." \
			% [label, String(primary_result.get("error", "missing"))])
		var repair_error := _restore_primary_from_backup(paths)
		if not repair_error.is_empty():
			push_warning("SaveManager: %s backup is valid but primary repair failed: %s" \
				% [label, repair_error])

	_prepare_restore(selected_result.get("snapshot", {}), id, label, use_backup)
	return _enter_restore(use_backup)


## Reloads (or, from the title screen, enters) the world for a prepared restore; a failure
## leaves everything as it was.
func _enter_restore(use_backup: bool) -> bool:
	if not _reload_world_scene():
		_loading = false
		_pending_restore.clear()
		WorldClock.set_paused(_clock_was_paused_before_load)
		_loading_from_backup = false
		_loading_id = ""
		_loading_label = ""
		_notify("Load failed: the world scene could not be reloaded.", true)
		load_finished.emit(false, use_backup)
		return false
	return true


## `id` is the slot it comes from; `label` names the save in the notices: "quick save",
## "autosave" or a named save in quotes.
func _prepare_restore(snapshot: Dictionary, id: String, label: String, use_backup: bool) -> void:
	_startup_checked = true
	_load_validated_msec = Time.get_ticks_msec()
	_pending_restore = snapshot
	_loading = true
	_ready_frames = 0
	_loading_from_backup = use_backup
	_loading_id = id
	_loading_label = label
	_clock_was_paused_before_load = WorldClock.paused
	if use_backup: _notify("Recovering %s from its backup…" % (label if label.begins_with("\"") else "the " + label))
	else: _notify("Loading %s…" % label)
	WorldClock.set_paused(true)


func _reload_world_scene() -> bool:
	_clear_world_runtime()
	var scene_tree := get_tree()
	var scene_changed_callback := Callable(self, "_on_scene_reloaded")
	if not scene_tree.scene_changed.is_connected(scene_changed_callback):
		scene_tree.scene_changed.connect(scene_changed_callback, CONNECT_ONE_SHOT)
	# From the title screen there is no world yet: it is entered rather than reloaded.
	var from_title := scene_tree.current_scene != null and scene_tree.current_scene.is_in_group(TITLE_GROUP)
	var reload_error := scene_tree.change_scene_to_file(WORLD_SCENE) if from_title else scene_tree.reload_current_scene()
	if reload_error != OK:
		if scene_tree.scene_changed.is_connected(scene_changed_callback):
			scene_tree.scene_changed.disconnect(scene_changed_callback)
		return false
	return true


## Everything a world leaves in the autoloads, cleared before another world or the title.
func _clear_world_runtime() -> void:
	TaskManager.reset_runtime_state()
	StockpileManager.reset_runtime_state()
	InteriorTracker.clear_runtime_state()
	RoomManager.clear_runtime_state()
	NavGrid.clear_runtime_state()
	PlacedEntityRegistry.clear_runtime_state()
	EventLog.clear_runtime_state()
	ColonyJournal.clear_runtime_state()
	WorldGenerator.prepare_for_world_reload()
	WorldData.clear_world()


func _on_scene_reloaded() -> void:
	if _loading:
		SkyController.rebind_to_current_scene()
	if _starting_new_game:
		WeatherManager.reset_for_new_game()
		_starting_new_game = false
		_loading = false
		_colony_saves.clear()
		_notify("New game started.")


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
	# Install final terrain without running live water displacement per voxel.
	# Water's owner restores authoritative volumes/queues and rebuilds derived
	# topology once. Other exact edits and coalesced mesh/nav updates remain.
	WorldData.begin_edit_batch()
	WaterManager.begin_terrain_restore()
	var t_terrain := Time.get_ticks_msec()
	WorldData.restore_terrain(scene_state.terrain)
	owner_lines.append("    terrain: %d ms" % (Time.get_ticks_msec() - t_terrain))
	var t_exploration := Time.get_ticks_msec()
	InteriorTracker.restore_exploration(scene_state.exploration)
	owner_lines.append("    exploration: %d ms" % (Time.get_ticks_msec() - t_exploration))
	for state_owner in owners:
		if not state_owner.has_method("save_section_key") or not state_owner.has_method("restore_state"):
			continue
		var key := String(state_owner.call("save_section_key"))
		if scene_state.has(key):
			var t_owner := Time.get_ticks_msec()
			state_owner.call("restore_state", scene_state[key] as Dictionary)
			owner_lines.append("    %s: %d ms" % [key, Time.get_ticks_msec() - t_owner])
	assert(not WaterManager.restoring, "Saved water must finish the terrain restore boundary")
	WorldData.end_edit_batch()

	var t_owners_end := Time.get_ticks_msec()
	StockpileManager.rebuild_totals()
	WorldClock.restore_state(_pending_restore.get("clock", {}) as Dictionary)
	WeatherManager.restore_state(_pending_restore.get("weather", {}) as Dictionary)
	_print_load_performance(t_restore_start, t_owners_end, owner_lines)
	var restored_from_backup := _loading_from_backup
	var label := _loading_label
	var saved_at := String(_pending_restore.get("saved_at_utc", ""))
	# The colony is the save it came from, so that save is its last.
	_colony_saves.clear()
	if not saved_at.is_empty(): _colony_saves[_loading_id] = Time.get_unix_time_from_datetime_string(saved_at)
	_pending_restore.clear()
	_loading = false
	_ready_frames = 0
	_loading_from_backup = false
	_loading_id = ""
	_loading_label = ""
	_autosave_elapsed_seconds = 0.0
	if label == "autosave":
		_notify("Autosave backup recovered and loaded." if restored_from_backup else "Autosave loaded.")
	elif label == "quick save":
		_notify("Backup recovered and loaded." if restored_from_backup else "Game loaded.")
	else:
		_notify("%s recovered from its backup and loaded." % label if restored_from_backup else "%s loaded." % label)
	print("SaveManager: %s%s restored." % ["backup " if restored_from_backup else "", label])
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


func _named_paths(stem: String) -> Dictionary:
	var base := _named_directory.path_join(stem)
	return {"primary": base + ".json", "backup": base + ".backup.json", "temp": base + ".tmp.json",
		"backup_stage": base + ".backup.tmp.json"}


## The named saves by file: every save file in the named folder, its backups and unfinished
## writes aside, so a save copied in from elsewhere is listed too.
func _named_stems() -> Array[String]:
	var stems: Array[String] = []
	var folder := DirAccess.open(_named_directory)
	if folder == null: return stems
	for file: String in folder.get_files():
		if not file.ends_with(".json") or file.ends_with(".tmp.json"): continue
		var stem := file.trim_suffix(".json").trim_suffix(".backup")
		if not stem in stems: stems.append(stem)
	return stems


## Every slot's files, ranked as equal save times rank them: the quick save, the named saves,
## then the autosave.
func _slot_files() -> Array[Dictionary]:
	var slots: Array[Dictionary] = [{"id": "quick", "paths": _quick_save_paths(), "rank": 0},
		{"id": "auto", "paths": _autosave_paths(), "rank": 2}]
	for stem: String in _named_stems():
		slots.append({"id": NAMED_PREFIX + stem, "paths": _named_paths(stem), "rank": 1})
	return slots


## How the notices name a slot: "quick save", "autosave", or a named save's name in quotes.
func _slot_label(id: String, snapshot: Dictionary) -> String:
	if id == "quick": return "quick save"
	if id == "auto": return "autosave"
	return "\"%s\"" % String(snapshot.get("save_name", id.trim_prefix(NAMED_PREFIX)))


func _capture_catalogs() -> Dictionary:
	var blocks := {}
	for key in BlockRegistry.block_keys():
		blocks[String(key)]={"kind":String(BlockRegistry.get_def(key).get("kind","void")),
			"solid":BlockRegistry.is_solid(BlockRegistry.get_id(key))}
	var construction := {}
	for key in BlockRegistry.construction_keys(): construction[key]={"logs":String(BlockRegistry.get_construction_def(key).get("logs",""))}
	var woods := {}
	for wood in BlockRegistry.woods(): woods[wood]=true
	var materials := {"":true}
	for key in CraftMaterials.definitions: materials[key]=true
	var catalogs := ContentRegistry.save_catalogs()
	catalogs.merge({"blocks":blocks,"construction":construction,"woods":woods,"materials":materials,"appeal_words":RoomManager.appeal_word_ids()})
	return catalogs


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

## Synchronous read/recovery helpers. Writes enter _start_save and run the
## transaction on a worker; tests drive SaveFileStore through _file_store().
func _restore_primary_from_backup(paths: Dictionary) -> String:
	return _file_store().restore_primary_from_backup(_absolute_paths(paths))

func _read_snapshot(path: String) -> Dictionary:
	return _file_store().read_snapshot(ProjectSettings.globalize_path(path))


func _fail_save(message: String) -> bool:
	_notify(message, true)
	save_finished.emit(false)
	return false


func _fail_load(message: String) -> bool:
	_notify(message, true)
	load_finished.emit(false, false)
	return false


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
