extends SceneTree

## Compare budgeted samples to the original equations, including edits in flight.
const Motion := preload("res://scripts/components/WaterSurfaceMotion.gd")
const Flow := preload("res://scripts/components/WaterFlow.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func reference(previous: Dictionary, mass: Dictionary, flux: Dictionary, seconds: float) -> Dictionary:
	var result := previous.duplicate()
	var keys := previous.duplicate()
	keys.merge(flux)
	for key: Vector3i in keys:
		var amount := float(mass.get(key,0))/Flow.UNITS
		var target := Vector2(flux.get(key,Vector2.ZERO))/seconds/maxf(0.25,amount)
		var value := Vector2(previous.get(key,Vector2.ZERO)).lerp(target,1.0-exp(-seconds/0.85))
		if amount < 0.0625 or value.length_squared() < 0.00000001: result.erase(key)
		else: result[key] = value
	return result

func settle(motion: RefCounted) -> int:
	var calls := 0
	while motion.is_updating() and calls < 20000:
		motion.advance(1)
		calls += 1
	check(not motion.is_updating(),"Motion sample failed to drain")
	return calls

func pixels_match(motion: RefCounted) -> bool:
	for key: Vector3i in motion.slots:
		var index: int = motion.slots[key]
		var velocity: Vector2 = motion.velocity(key)
		if motion.image.get_pixel(index%Motion.WIDTH,index/Motion.WIDTH) != Color(velocity.x,velocity.y,0,0): return false
	return true

func _run() -> void:
	for node in root.get_children(): node.set_process(false)
	var flow := Flow.new()
	var motion := Motion.new()
	for i in 8192:
		var key := Vector3i(i%128,4+i%2*10,i/128)
		flow.mass[key] = 1000000+i*7
		flow.surface_flux[key] = Vector2(sin(i*0.17),cos(i*0.23))*0.05
		motion.slot(key)
	var expected := reference({},flow.mass,flow.surface_flux,0.2)
	var mass_before := flow.mass.duplicate()
	var state := flow.serialize()
	check(motion.begin_update(flow,0.2),"Initial sample was rejected")
	check(flow.surface_flux.is_empty(),"Consumed flux was retained by the solver")
	motion.advance(1)
	check(motion.is_updating() and motion.last_cells<=Motion.CHECK_INTERVAL,"Tiny budget did not yield after a bounded batch")
	check(not motion.begin_update(flow,0.2),"A pending sample was replaced")
	# Edits and later transfers must not change the already captured sample.
	var changed := Vector3i(127,14,63)
	flow.mass[changed] = 0
	flow.surface_flux[changed] = Vector2(-0.4,0.2)
	check(settle(motion)>1,"Large sample completed without incremental work")
	check(motion.velocities==expected,"Budgeted sample differs from original equations or read live mass")
	check(flow.surface_flux.get(changed)==Vector2(-0.4,0.2),"Later flux was lost")
	check(pixels_match(motion),"Texture pixels disagree with sampled velocities")
	flow.mass[changed] = 1000000+8191*7
	check(flow.mass==mass_before and flow.serialize()==state,"Cosmetic sampling changed persistent water state")
	# Follow with overlapping keys, a newly visible stacked pool and drained water.
	var upper := Vector3i(127,24,63)
	flow.mass[upper] = 900000
	flow.surface_flux[upper] = Vector2(0.2,-0.1)
	flow.mass[changed] = 0
	expected = reference(expected,flow.mass,flow.surface_flux,0.3)
	motion.begin_update(flow,0.3)
	motion.slot(upper)
	settle(motion)
	check(motion.velocities==expected,"Second sample lost decay, drain or new flux")
	check(motion.velocity(changed)==Vector2.ZERO,"Drained water retained a current")
	check(motion.slot(upper)!=motion.slot(changed),"Stacked pools shared a slot")
	check(pixels_match(motion),"A slot added during sampling has stale pixels")
	# Repeated samples include both active flux and exponentially decaying currents.
	for tick in 40:
		flow.surface_flux[upper] = Vector2(sin(tick),cos(tick))*0.03
		expected = reference(expected,flow.mass,flow.surface_flux,0.2)
		motion.begin_update(flow,0.2)
		settle(motion)
		check(motion.velocities==expected and pixels_match(motion),"Reference mismatch at sample %d" % tick)
	check(motion.velocities==expected and pixels_match(motion),"Repeated budgeted samples drifted from the reference")
	motion.upload()
	var flux_before := flow.surface_flux.duplicate()
	var velocity_before := motion.velocities.duplicate()
	check(not motion.begin_update(flow,0),"Paused time started a sample")
	motion.update(flow,0)
	check(flow.surface_flux==flux_before and motion.velocities==velocity_before,"Paused update consumed telemetry")
	flow.surface_flux[upper] = Vector2.ONE
	motion.begin_update(flow,0.2)
	motion.advance(1)
	var stable_slot: int = motion.slot(upper)
	motion.reset()
	check(not motion.is_updating() and motion.velocities.is_empty(),"Reset retained a pending sample")
	check(motion.slot(upper)==stable_slot and pixels_match(motion),"Reset broke mesh slot identity or retained motion")
	# Force table growth while a sample is pending, including an existing texture.
	var growing := Motion.new()
	growing.image = Image.create(Motion.WIDTH,1,false,Image.FORMAT_RGBAF)
	growing.upload()
	for i in 250: growing.slot(Vector3i(i,4,0))
	flow.surface_flux = {Vector3i(0,4,0):Vector2.ONE}
	growing.begin_update(flow,0.2)
	for i in range(250,300): growing.slot(Vector3i(i,4,0))
	settle(growing)
	growing.upload()
	check(growing.image.get_height()==2 and pixels_match(growing),"Growing the texture during sampling lost pixels")
	check(growing.texture.get_height()==2,"Expanded texture was not uploaded")
	print("WaterMotionSchedulingTest: ","PASS" if failures.is_empty() else str(failures)," checks=",checks)
	quit(0 if failures.is_empty() else 1)
