extends Node

## Measure actual scene processing every frame; Performance.TIME_PROCESS is cached.
var start_usec := 0
var last_ms := 0.0

func _ready() -> void:
	process_priority = 1000000
	get_tree().process_frame.connect(_begin)

func _begin() -> void:
	start_usec = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	last_ms = (Time.get_ticks_usec()-start_usec)/1000.0
