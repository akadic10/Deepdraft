extends SceneTree

## The shared JSON reader (scripts/registries/JsonData.gd) reports a missing file,
## a parse error and a wrong top-level shape with push_error naming the file and
## the reason, stays quiet for a missing optional file, and returns valid data
## unchanged. The expected error lines are listed in tools/test_suite.json.

const JsonData = preload("res://scripts/registries/JsonData.gd")
const DIR := "user://json_data_test"

class ErrorCapture extends Logger:
	var lines: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		lines.append(code + " " + rationale)
		mutex.unlock()
	func take() -> Array[String]:
		mutex.lock()
		var result := lines.duplicate()
		lines.clear()
		mutex.unlock()
		return result

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _write(name: String, text: String) -> String:
	var path := DIR.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path

func _reported(capture: ErrorCapture, needles: Array[String]) -> bool:
	var lines := capture.take()
	if lines.size() != 1: return false
	for needle: String in needles:
		if not lines[0].contains(needle): return false
	return true

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	var valid := _write("valid.json", '{"name": "pine", "count": 3, "tags": ["a", "b"]}')
	var listed := _write("list.json", '[1, 2, 3]')
	var broken := _write("broken.json", '{"name": "pine",\n "count": }')
	var missing := DIR.path_join("missing.json")

	var data := JsonData.read_dict(valid)
	_expect(data == JSON.parse_string(FileAccess.get_file_as_string(valid)), "valid object matches JSON.parse_string")
	_expect(JsonData.read_array(listed) == [1.0, 2.0, 3.0], "valid array reads as an array")
	_expect(capture.take().is_empty(), "valid files report nothing")

	_expect(JsonData.read_dict(missing).is_empty(), "missing file falls back to {}")
	_expect(_reported(capture, ["missing file", missing]), "missing file reported once with its path")
	_expect(JsonData.read_dict(broken).is_empty(), "malformed file falls back to {}")
	_expect(_reported(capture, ["parse error", broken, "line 2"]), "parse error reported with path and line")
	_expect(JsonData.read_dict(listed).is_empty(), "wrong top-level shape falls back to {}")
	_expect(_reported(capture, [listed, "JSON object", "JSON array"]), "wrong shape reported with expected and found types")
	_expect(JsonData.read(missing, TYPE_DICTIONARY, true) == null, "missing optional file returns null")
	_expect(capture.take().is_empty(), "missing optional file stays quiet")
	_expect(JsonData.read(broken, TYPE_DICTIONARY, true) == null and _reported(capture, ["parse error", broken]),
		"a present but broken optional file is still reported")
	var outcome := JsonData.inspect(missing)
	_expect(bool(outcome.missing) and String(outcome.error).contains(missing), "inspect explains without reporting")
	_expect(capture.take().is_empty(), "inspect does not push errors")

	OS.remove_logger(capture)
	for name: String in ["valid.json", "list.json", "broken.json"]: DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)
	for failure: String in failures: push_error(failure)
	print("JSON_DATA_OK" if failures.is_empty() else "JSON_DATA_FAIL")
	quit(0 if failures.is_empty() else 1)
