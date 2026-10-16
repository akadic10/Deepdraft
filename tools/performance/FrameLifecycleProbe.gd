extends Node

## Diagnostic only. Bracket the complete interval between process_frame signals,
## including work after ordinary node callbacks and the benchmark's own work.
var rows: Array = []
var labels: Dictionary = {}
var phase := "setup"
var begin_usec := 0
var process_end_usec := 0
var pre_draw_usec := 0
var post_draw_usec := 0
var physics_start_usec := 0
var physics_usec := 0
var physics_count := 0
var frame_index := 0
var record_all := true
var latest: Dictionary = {}
var previous_pipelines := {}

func pipeline_counts() -> Dictionary:
	return {"canvas":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		"mesh":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surface":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"specialization":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)}

func _ready() -> void:
	process_priority=2000000
	process_physics_priority=2000000
	get_tree().process_frame.connect(_begin)
	get_tree().physics_frame.connect(_physics_begin)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)

func _begin() -> void:
	var now:=Time.get_ticks_usec()
	var pipelines:=pipeline_counts()
	if begin_usec>0:
		var compiled: Dictionary={}
		for key in pipelines: compiled[key]=int(pipelines[key])-int(previous_pipelines.get(key,pipelines[key]))
		latest={"frame":frame_index,"phase":phase,"wall_ms":(now-begin_usec)/1000.0,
			"process_ms":(process_end_usec-begin_usec)/1000.0,
			"after_process_ms":(pre_draw_usec-process_end_usec)/1000.0,
			"draw_ms":(post_draw_usec-pre_draw_usec)/1000.0,
			"after_draw_ms":(now-post_draw_usec)/1000.0,
			"physics_ms":physics_usec/1000.0,"physics_steps":physics_count,
			"setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"pipelines":compiled,
			"labels":labels.duplicate()}
		if record_all: rows.append(latest)
	previous_pipelines=pipelines
	frame_index+=1
	begin_usec=now
	process_end_usec=now
	pre_draw_usec=now
	post_draw_usec=now
	physics_usec=0
	physics_count=0
	labels.clear()

func _process(_delta: float) -> void:
	process_end_usec=Time.get_ticks_usec()

func _physics_begin() -> void:
	physics_start_usec=Time.get_ticks_usec()
	physics_count+=1

func _physics_process(_delta: float) -> void:
	physics_usec+=Time.get_ticks_usec()-physics_start_usec

func _pre_draw() -> void:
	pre_draw_usec=Time.get_ticks_usec()

func _post_draw() -> void:
	post_draw_usec=Time.get_ticks_usec()

func stamp(label: String, started: int) -> void:
	labels[label]=(Time.get_ticks_usec()-started)/1000.0
