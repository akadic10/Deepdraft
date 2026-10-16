extends RefCounted

## Diagnostic-only accumulator used by InstrumentRendering.py wrappers.
## Main-thread methods only. Nested method totals must not be added together.
static var values: Dictionary = {}

static func count(label: String, amount: int) -> void:
	values[label] = int(values.get(label, 0)) + amount

static func record(label: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	values[label] = float(values.get(label, 0.0)) + elapsed / 1000.0
	var count_key := label + "/calls"
	values[count_key] = int(values.get(count_key, 0)) + 1

static func take() -> Dictionary:
	var result := values
	values = {}
	return result
