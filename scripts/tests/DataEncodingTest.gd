extends SceneTree

## Data text must be clean UTF-8. UTF-8 that was once read as Windows-1252 and
## saved again turns "·" into "Â·" and "→" into "â†’", and players see it.

const SIGNATURES := ["Â", "Ã", "â€", "â†", "â‰", "âˆ"]

func _init() -> void:
	var failures: Array[String] = []
	for path: String in _files("res://data"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			for signature: String in SIGNATURES:
				if lines[index].contains(signature):
					failures.append("%s:%d contains garbled text '%s'" % [path, index + 1, signature])
					break
	for failure: String in failures: push_error(failure)
	print("DATA_ENCODING_OK" if failures.is_empty() else "DATA_ENCODING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _files(folder: String) -> Array[String]:
	var result: Array[String] = []
	for name: String in DirAccess.get_files_at(folder):
		if name.get_extension() == "json": result.append(folder.path_join(name))
	for name: String in DirAccess.get_directories_at(folder):
		result.append_array(_files(folder.path_join(name)))
	return result
