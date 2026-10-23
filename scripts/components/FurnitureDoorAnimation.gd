extends Node

## Installed-only hinges. Navigation and the room's seal never depend on pose.
var _model: Node3D
var _settings: Dictionary
var _hinges: Array[Node3D] = []
var _angle := 0.0
var _direction := 1.0
var _hold := 0.0
var _until_scan := 0.0

func setup(model: Node3D, settings: Dictionary) -> void:
	_model = model
	_settings = settings
	var half_width := float(settings.width)*.5
	var inset := float(settings.get("hinge_inset",.125))
	for leaf_name: String in ["leaf_left", "leaf_right"]:
		var leaf := model.find_child(leaf_name, true, false) as Node3D
		if leaf == null: continue
		var hinge := Node3D.new()
		hinge.name = leaf_name+"_hinge"
		model.add_child(hinge)
		hinge.position.x = (-half_width+inset) if leaf_name=="leaf_left" else (half_width-inset)
		leaf.reparent(hinge)
		_hinges.append(hinge)

func _process(delta: float) -> void:
	if WorldClock.paused or WorldClock.speed<=0 or SaveManager.is_loading() or not is_instance_valid(_model): return
	if not _model.is_visible_in_tree(): return
	var elapsed := delta*WorldClock.speed
	_until_scan -= elapsed
	_hold = maxf(0.0, _hold-elapsed)
	if _until_scan<=0:
		_until_scan = .1
		_scan()
	var target := deg_to_rad(float(_settings.open_degrees)) if _hold>0 else 0.0
	var seconds := float(_settings.open_seconds if _hold>0 else _settings.close_seconds)
	_angle = move_toward(_angle, target, elapsed*deg_to_rad(float(_settings.open_degrees))/seconds)
	for i in _hinges.size():
		_hinges[i].rotation.y = _angle*_direction*(1.0 if i==0 else -1.0)

func _scan() -> void:
	var closest_z := INF
	var nearby := false
	for actor in TaskManager.get_agents():
		if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion(): continue
		var local: Vector3 = _model.to_local(actor.global_position)
		if absf(local.y)>1.25 or absf(local.x)>float(_settings.width)*.5+.35: continue
		if absf(local.z)>float(_settings.approach_distance): continue
		nearby = true
		if absf(local.z)<absf(closest_z): closest_z = local.z
	if nearby:
		# Choose a side only from the closed pose; passing dwarves cannot flip it.
		if _angle<.001: _direction = 1.0 if closest_z>=0 else -1.0
		_hold = float(_settings.hold_seconds)
