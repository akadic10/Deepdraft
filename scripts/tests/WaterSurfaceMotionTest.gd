extends SceneTree

const Flow := preload("res://scripts/components/WaterFlow.gd")
const Motion := preload("res://scripts/components/WaterSurfaceMotion.gd")
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.get_node("WorldClock").paused = true
	for direction: Vector2i in Flow.DIRECTIONS:
		var side := Vector2i(-direction.y,direction.x)
		var cells: Array[Vector2i] = []
		for i in 6: cells.append(Vector2i(24,24)+direction*i)
		for i in range(1,6): cells.append(cells[5]+side*i)
		var geometry: Dictionary = {}
		for p in cells: geometry[p] = [Vector2i(4,20)]
		var tracked := Flow.new()
		var control := Flow.new()
		for flow in [tracked,control]:
			flow.spans_at = func(p: Vector2i): return geometry.get(p,[])
			for p in cells: flow.seed_column(Vector3i(p.x,4,p.y),1)
		tracked.track_surface_motion = true
		var motion := Motion.new()
		var inlet := Vector3i(cells[0].x,4,cells[0].y)
		var outlet := Vector3i(cells[-1].x,4,cells[-1].y)
		for i in 200:
			for flow in [tracked,control]:
				flow.add_at(inlet,0.03,8)
				flow.remove_at(outlet,0.03,4,true)
				flow.step(0.1,100)
			motion.update(tracked,0.1)
		check(tracked.serialize()==control.serialize(),"motion telemetry changed solver state")
		var before_bend := Vector3i(cells[3].x,4,cells[3].y)
		var after_bend := Vector3i(cells[8].x,4,cells[8].y)
		check(motion.velocity(before_bend).normalized().dot(Vector2(direction))>0.95,"upstream current direction %s" % direction)
		check(motion.velocity(after_bend).normalized().dot(Vector2(side))>0.95,"current failed to turn %s" % direction)
		# Remove supply and drainage: a sealed reach must settle and become quiet.
		for i in 500:
			tracked.step(0.1,100)
			motion.update(tracked,0.1)
		check(motion.velocity(before_bend).length()<0.005,"sealed pool keeps scrolling")
		var state := tracked.serialize()
		var slot := motion.slot(before_bend)
		check(slot!=motion.slot(before_bend+Vector3i.UP*10),"stacked pools share motion")
		motion.update(tracked,0)
		check(tracked.serialize()==state,"paused motion mutated water")
		motion.upload()
	# Reach equalization must report its implicit transfers, including reverse.
	var reach := Flow.new()
	reach.track_surface_motion = true
	reach.spans_at = func(p: Vector2i): return [Vector2i(4,20)] if p.y==0 and p.x>=0 and p.x<=4 else []
	for x in 5: reach.seed_column(Vector3i(x,4,0),1 if x<4 else 3)
	reach._level_wet_reach(Vector3i(0,4,0),Vector2i.RIGHT)
	check(Vector2(reach.surface_flux[Vector3i(2,4,0)]).x<0,"equalization lost reverse current")
	check(is_equal_approx(reach.total_volume(),7.0),"equalization changed volume")
	# Sampling and rendering state never enter JSON or alter future evolution.
	var copy := Flow.new()
	copy.spans_at = reach.spans_at
	for x in 5: copy.seed_column(Vector3i(x,4,0),1 if x<4 else 3)
	copy.restore(JSON.parse_string(JSON.stringify(reach.serialize(),"",false,true)))
	for i in 20:
		reach.step(0.1,100)
		copy.step(0.1,100)
	check(reach.serialize()==copy.serialize(),"save/load motion affected future volume")
	print("WaterSurfaceMotionTest: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
