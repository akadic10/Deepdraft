extends RefCounted

## One temporary assignment. Sources retain intent/progress; this owns liveness,
## fencing and receipts only. Never an inventory or a second world-state owner.
var generation := 0
var task_id := -1
var worker_id := -1
var order_key := ""
var step := "assigned"
var detail := ""
var elapsed := 0.0
var step_started := 0.0
var last_progress := 0.0
var best_remaining := INF
var deadline := 30.0
var commits: Dictionary = {}
var last_sample: Dictionary = {}

func observe(sample: Dictionary, now: float, grace: float) -> void:
	var identity := String(sample.get("step", "missing executor")) + ":" + String(sample.get("unit", ""))
	var remaining := float(sample.get("remaining", 0.0))
	if identity != detail:
		step = String(sample.get("step", "missing executor"))
		detail = identity
		step_started = now
		last_progress = now
		best_remaining = remaining
		deadline = maxf(grace, float(sample.get("expected_seconds", grace)) * 2.0 + grace)
	elif remaining < best_remaining - .01:
		best_remaining = remaining
		last_progress = now
	elapsed = now
	last_sample = sample

func stalled(now: float, grace: float) -> bool:
	return now - last_progress > grace or now - step_started > deadline

func describe(now: float) -> Dictionary:
	return {"attempt":generation, "worker":worker_id, "step":step,
		"seconds_without_progress":maxf(0.0, now-last_progress),
		"step_seconds":maxf(0.0, now-step_started), "deadline":deadline,
		"unit":String(last_sample.get("unit", ""))}
