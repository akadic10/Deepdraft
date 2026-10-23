extends RefCounted

## Shared JSON file reader for registries and systems (doc 258 step 6). No
## class_name: owners preload it as `const JsonData = preload(...)`.
##
## Every failure is reported with push_error naming the file and the reason:
## a missing or unreadable file, a parse error (with its line), or a top-level
## value of the wrong JSON type. The caller then gets an empty fallback and keeps
## its own defaults. A file that is legitimately absent passes optional = true;
## its absence stays quiet, but if it exists and is broken it is still reported.


## Parsed top-level value, or null after reporting the problem. expected_type is
## a Variant.Type (TYPE_DICTIONARY, TYPE_ARRAY) or TYPE_NIL to accept any value.
static func read(path: String, expected_type: int = TYPE_DICTIONARY, optional := false) -> Variant:
	var outcome := inspect(path, expected_type)
	var reason := String(outcome.error)
	if reason.is_empty(): return outcome.data
	if not (optional and bool(outcome.missing)): push_error(reason)
	return null


## A top-level JSON object, or {} after reporting the problem.
static func read_dict(path: String, optional := false) -> Dictionary:
	var data: Variant = read(path, TYPE_DICTIONARY, optional)
	return data if data is Dictionary else {}


## A top-level JSON array, or [] after reporting the problem.
static func read_array(path: String, optional := false) -> Array:
	var data: Variant = read(path, TYPE_ARRAY, optional)
	return data if data is Array else []


## The checks without reporting: {"data", "error", "missing"}. error is "" on success.
static func inspect(path: String, expected_type: int = TYPE_DICTIONARY) -> Dictionary:
	var outcome := {"data": null, "error": "", "missing": false}
	if not FileAccess.file_exists(path):
		outcome.missing = true
		outcome.error = "JSON data: missing file %s" % path
		return outcome
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		outcome.error = "JSON data: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		return outcome
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		outcome.error = "JSON data: parse error in %s at line %d: %s" % [path, json.get_error_line() + 1, json.get_error_message()] # 0-based in Godot
		return outcome
	if expected_type != TYPE_NIL and typeof(json.data) != expected_type:
		outcome.error = "JSON data: %s must hold a %s at the top level, not a %s" % [path,
			_json_type_name(expected_type), _json_type_name(typeof(json.data))]
		return outcome
	outcome.data = json.data
	return outcome


static func _json_type_name(type: int) -> String:
	match type:
		TYPE_DICTIONARY: return "JSON object"
		TYPE_ARRAY: return "JSON array"
		TYPE_STRING: return "JSON string"
		TYPE_FLOAT, TYPE_INT: return "JSON number"
		TYPE_BOOL: return "JSON boolean"
		TYPE_NIL: return "JSON null"
	return type_string(type)
