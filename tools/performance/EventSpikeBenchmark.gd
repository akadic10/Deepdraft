extends "res://tools/performance/ColonyScalingBenchmark.gd"

var lifecycle: Node

func _prepare_workload() -> void:
	await super._prepare_workload()
	lifecycle=load("res://tools/performance/FrameLifecycleProbe.gd").new()
	scene.add_child(lifecycle)
	root.get_node("WorkFeedback").burst_started.connect(func(_position: Vector3, stage: String):
		lifecycle.labels[stage]=int(lifecycle.labels.get(stage,0))+1)
	if "--no-feedback" in OS.get_cmdline_user_args():
		root.get_node("WorkFeedback").config.audio.minimum_gain=1000

func _sample(mode: String) -> void:
	lifecycle.phase=mode
	await super._sample(mode)
	FileAccess.open(output+"lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify(lifecycle.rows))

func _drive_camera(pan: bool, elapsed: float) -> void:
	var started:=Time.get_ticks_usec()
	super._drive_camera(pan,elapsed)
	lifecycle.stamp("drive_camera",started)

func _record_activity() -> void:
	var started:=Time.get_ticks_usec()
	super._record_activity()
	lifecycle.stamp("record_activity",started)
