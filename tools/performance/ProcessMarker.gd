extends Node

## Sibling brackets preserve the order and priorities of existing callbacks.
## Intervals include same-priority descendants; nested intervals are not additive.
var label := ""
var before := true
var measurements: Dictionary
var starts: Dictionary

func _process(_delta: float) -> void:
	if before:
		starts[label] = Time.get_ticks_usec()
	else:
		measurements[label] = (Time.get_ticks_usec() - int(starts.get(label,Time.get_ticks_usec())))/1000.0
