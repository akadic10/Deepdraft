extends "res://scripts/systems/SaveManager.gd"
## Baseline-only instrumentation; file ordering and validation are unchanged.
var stages: Array = []
func _record(stage: String, started: int, path: String = "") -> void:
	stages.append({"stage":stage,"ms":(Time.get_ticks_usec()-started)/1000.0,"path":path})
func _profile_encode(snapshot: Dictionary) -> String:
	var started:=Time.get_ticks_usec()
	var result:=JSON.stringify(snapshot,"\t")
	_record("encode_json",started)
	return result
func _build_snapshot() -> Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=super._build_snapshot()
	_record("snapshot_total",started)
	return result
func _collect_scene_state() -> Dictionary:
	var result: Dictionary={}
	for owner in get_tree().get_nodes_in_group(OWNER_GROUP):
		if not owner.has_method("save_section_key") or not owner.has_method("serialize_state"): continue
		var key:=String(owner.call("save_section_key"))
		if key.is_empty(): continue
		var started:=Time.get_ticks_usec()
		result[key]=owner.call("serialize_state")
		_record("snapshot/"+key,started)
	return result
func _validate_snapshot(snapshot: Dictionary) -> String:
	var started:=Time.get_ticks_usec()
	var result:=super._validate_snapshot(snapshot)
	_record("validate",started)
	return result
func _write_text_file(path: String, contents: String) -> String:
	var started:=Time.get_ticks_usec()
	var result:=super._write_text_file(path,contents)
	_record("write_bytes",started,path)
	return result

func _commit_snapshot(snapshot: Dictionary, paths: Dictionary) -> String:
	var dir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_save_directory_path))
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

	var write_error := _write_text_file(temp_path, _profile_encode(snapshot))
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


func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "missing": true, "error": "is missing" }
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { "ok": false, "missing": false, "error": "could not be opened" }
	var started := Time.get_ticks_usec()
	var contents := file.get_as_text()
	file.close()
	_record("read_bytes",started,path)
	started=Time.get_ticks_usec()
	var json := JSON.new()
	var parse_error := json.parse(contents)
	_record("parse_json",started,path)
	if parse_error != OK or not (json.data is Dictionary):
		return { "ok": false, "missing": false, "error": "contains invalid JSON" }
	var snapshot: Dictionary = json.data
	var validation_error := _validate_snapshot(snapshot)
	if not validation_error.is_empty():
		return { "ok": false, "missing": false, "error": validation_error }
	return { "ok": true, "missing": false, "error": "", "snapshot": snapshot }

