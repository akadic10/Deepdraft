extends RefCounted

## Private transaction owned by SaveManager. A worker exclusively owns every
## mutable field until its task has completed and the main thread joins it.
const Validator = preload("res://scripts/components/SaveSnapshotValidator.gd")
const Preparation = preload("res://scripts/components/SaveSnapshotPreparation.gd")
var directory := ""
var paths: Dictionary = {}
var catalogs: Dictionary = {}
var schema_version := 1
var snapshot: Dictionary = {}
var sections: Array[String] = []
var result_error := ""
var warnings: Array[String] = []
var timings: Dictionary = {}

func run() -> void:
	var started:=Time.get_ticks_usec()
	Preparation.finish(snapshot,sections)
	_record("prepare",started)
	started=Time.get_ticks_usec()
	result_error=_commit_snapshot(snapshot,paths)
	_record("transaction",started)
	# Destroy large private trees here, not on the gameplay frame that joins us.
	started=Time.get_ticks_usec()
	snapshot.clear()
	catalogs.clear()
	sections.clear()
	_record("cleanup",started)

func _record(stage: String, started: int) -> void:
	timings[stage]=float(timings.get(stage,0))+(Time.get_ticks_usec()-started)/1000.0

func _encode(state: Dictionary) -> String:
	var started:=Time.get_ticks_usec()
	var result:=JSON.stringify(state,"\t")
	_record("encode_json",started)
	return result

func _validate_snapshot(state: Dictionary) -> String:
	var error:=Validator.validate_captured(state,schema_version,catalogs)
	if not error.is_empty(): return error
	for section: String in ["terrain","test_dam"]:
		for entry: Dictionary in state.scene.water.get(section,[]):
			if not catalogs.blocks.has(entry.block): return "save.scene.water contains an unknown terrain block."
			if section=="terrain" and not catalogs.blocks[entry.block].solid: return "save.scene.water contains a non-solid terrain edit."
	return ""

func _commit_snapshot(snapshot: Dictionary, paths: Dictionary) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(
		directory)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return "could not create the saves folder (%s)." % error_string(dir_error)

	var temp_path := String(paths.get("temp", ""))
	var backup_stage_path := String(paths.get("backup_stage", ""))
	var cleanup_error := _remove_if_exists(temp_path)
	if not cleanup_error.is_empty():
		return cleanup_error
	cleanup_error = _remove_if_exists(backup_stage_path)
	if not cleanup_error.is_empty():
		return cleanup_error

	var write_error := _write_text_file(temp_path, _encode(snapshot))
	if not write_error.is_empty():
		return write_error
	var temp_result := _read_snapshot(temp_path)
	if not bool(temp_result.get("ok", false)):
		_remove_if_exists(temp_path)
		return "temporary save validation failed: %s" % String(temp_result.get("error", "invalid file"))

	var rotation_error := _rotate_primary_to_backup_if_valid(paths)
	if not rotation_error.is_empty():
		_remove_if_exists(temp_path)
		return rotation_error

	var replace_error := _replace_primary_with_temp(paths)
	if not replace_error.is_empty():
		_remove_if_exists(temp_path)
		return replace_error
	return ""


func _rotate_primary_to_backup_if_valid(paths: Dictionary) -> String:
	var primary_path := String(paths.get("primary", ""))
	var backup_path := String(paths.get("backup", ""))
	var backup_stage_path := String(paths.get("backup_stage", ""))
	var primary_result := _read_snapshot(primary_path)
	if not bool(primary_result.get("ok", false)):
		if not bool(primary_result.get("missing", false)):
			warnings.append("SaveManager: existing primary is invalid and will not replace the backup (%s)." \
				% String(primary_result.get("error", "invalid file")))
		return ""

	var copy_error := DirAccess.copy_absolute(
		primary_path,
		backup_stage_path)
	if copy_error != OK:
		return "could not stage the previous save as a backup (%s)." % error_string(copy_error)
	var staged_result := _read_snapshot(backup_stage_path)
	if not bool(staged_result.get("ok", false)):
		_remove_if_exists(backup_stage_path)
		return "staged backup validation failed: %s" % String(staged_result.get("error", "invalid file"))

	var remove_error := _remove_if_exists(backup_path)
	if not remove_error.is_empty():
		_remove_if_exists(backup_stage_path)
		return remove_error
	var rename_error := DirAccess.rename_absolute(
		backup_stage_path,
		backup_path)
	if rename_error != OK:
		_remove_if_exists(backup_stage_path)
		return "could not install the validated backup (%s)." % error_string(rename_error)
	return ""


func _replace_primary_with_temp(paths: Dictionary) -> String:
	var primary_path := String(paths.get("primary", ""))
	var temp_path := String(paths.get("temp", ""))
	var remove_error := _remove_if_exists(primary_path)
	if not remove_error.is_empty():
		return remove_error
	var rename_error := DirAccess.rename_absolute(
		temp_path,
		primary_path)
	if rename_error != OK:
		var recovery_error := _restore_primary_from_backup(paths)
		if recovery_error.is_empty():
			return "could not install the new save; the previous backup was restored (%s)." \
				% error_string(rename_error)
		return "could not install the new save (%s); recovery also failed: %s" \
			% [error_string(rename_error), recovery_error]

	var installed_result := _read_snapshot(primary_path)
	if not bool(installed_result.get("ok", false)):
		var validation_error := String(installed_result.get("error", "invalid file"))
		var recovery_error := _restore_primary_from_backup(paths)
		if recovery_error.is_empty():
			return "installed save failed validation; the previous backup was restored (%s)." \
				% validation_error
		return "installed save failed validation (%s); recovery also failed: %s" \
			% [validation_error, recovery_error]
	return ""


func _restore_primary_from_backup(paths: Dictionary) -> String:
	var primary_path := String(paths.get("primary", ""))
	var backup_path := String(paths.get("backup", ""))
	var backup_result := _read_snapshot(backup_path)
	if not bool(backup_result.get("ok", false)):
		return "no valid backup is available (%s)." % String(backup_result.get("error", "missing"))
	var remove_error := _remove_if_exists(primary_path)
	if not remove_error.is_empty():
		return remove_error
	var copy_error := DirAccess.copy_absolute(
		backup_path,
		primary_path)
	if copy_error != OK:
		return "could not copy the backup into the primary slot (%s)." % error_string(copy_error)
	var restored_result := _read_snapshot(primary_path)
	if not bool(restored_result.get("ok", false)):
		return "recovered primary failed validation: %s" \
			% String(restored_result.get("error", "invalid file"))
	return ""


func _write_text_file(path: String, contents: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not open %s for writing." % path
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "write failed for %s (%s)." % [path, error_string(write_error)]
	return ""


func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "missing": true, "error": "is missing" }
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { "ok": false, "missing": false, "error": "could not be opened" }
	var started:=Time.get_ticks_usec()
	var contents := file.get_as_text()
	file.close()
	_record("read_bytes",started)
	started=Time.get_ticks_usec()
	var json := JSON.new()
	var parse_error := json.parse(contents)
	_record("parse_json",started)
	if parse_error != OK or not (json.data is Dictionary):
		return { "ok": false, "missing": false, "error": "contains invalid JSON" }
	var snapshot: Dictionary = json.data
	started=Time.get_ticks_usec()
	var validation_error := _validate_snapshot(snapshot)
	_record("validate",started)
	if not validation_error.is_empty():
		return { "ok": false, "missing": false, "error": validation_error }
	return { "ok": true, "missing": false, "error": "", "snapshot": snapshot }


func _remove_if_exists(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var remove_error := DirAccess.remove_absolute(path)
	if remove_error != OK:
		return "could not remove %s (%s)." % [path, error_string(remove_error)]
	return ""

