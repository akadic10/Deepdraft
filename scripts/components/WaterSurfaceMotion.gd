extends RefCounted

## A small GPU lookup table indexed by water-space keys, so cave pools and
## surface water at the same XZ never share currents. Animation needs no remesh.
## The solver only supplies measured flux; this state is disposable on load.
const WIDTH := 256
const CHECK_INTERVAL := 16
const Flow := preload("res://scripts/components/WaterFlow.gd")
var slots: Dictionary = {}
var velocities: Dictionary = {}
var image := Image.create(WIDTH,256,false,Image.FORMAT_RGBAF)
var texture: ImageTexture
var dirty := true
var gain := 1.3
var maximum_speed := 0.8
# A sample owns its flux and mass at one simulation instant. The solver keeps
# running into a fresh flux dictionary while cosmetic work resumes next frame.
var _flux: Dictionary = {}
var _amounts := PackedFloat64Array()
var _keys: Array = []
var _previous_keys: Array = []
var _head := 0
var _previous_head := 0
var _seconds := 0.0
var _blend := 0.0
var _sample_started := 0
var last_cells := 0
var completed_samples := 0
var last_latency_usec := 0
var last_capture_usec := 0

func reset() -> void:
	_finish_sample()
	velocities.clear()
	image.fill(Color(0,0,0,0))
	dirty = true

func slot(key: Vector3i) -> int:
	if slots.has(key): return slots[key]
	var index := slots.size()+1 # Zero is the stationary default.
	if index >= image.get_width()*image.get_height():
		var expanded := Image.create(WIDTH,image.get_height()*2,false,Image.FORMAT_RGBAF)
		expanded.blit_rect(image,Rect2i(0,0,WIDTH,image.get_height()),Vector2i.ZERO)
		image = expanded
		if texture != null: texture.set_image(image)
	slots[key] = index
	_write(key)
	return index

func velocity(key: Vector3i) -> Vector2:
	var raw: Vector2 = velocities.get(key,Vector2.ZERO)
	var speed := raw.length()
	if speed < 0.0001: return Vector2.ZERO
	# Tiny numerical exchanges fade away; slow, sustained flow stays readable.
	return raw/speed*minf(maximum_speed,sqrt(speed)*gain)*smoothstep(0.0001,0.004,speed)

## Synchronous entry for deterministic fixtures. Live rendering uses begin/advance.
func update(flow: RefCounted, seconds: float) -> void:
	if seconds <= 0: return
	while is_updating(): advance(1000000)
	begin_update(flow,seconds)
	while is_updating(): advance(1000000)

func is_updating() -> bool:
	return _seconds > 0.0

func begin_update(flow: RefCounted, seconds: float) -> bool:
	if seconds <= 0 or is_updating(): return false
	_sample_started = Time.get_ticks_usec()
	_seconds = seconds
	_blend = 1.0-exp(-seconds/0.85)
	# Transfer only disposable telemetry. Never retain a live mutable mass table.
	_flux = flow.surface_flux
	flow.surface_flux = {}
	_keys = _flux.keys()
	_previous_keys = velocities.keys()
	_head = 0
	_previous_head = 0
	if _keys.is_empty() and _previous_keys.is_empty():
		_finish_sample()
	else:
		# Copy only sampled volumes into compact storage. Copying the whole lake
		# dictionary costs several milliseconds even when most water is quiet.
		var mass: Dictionary = flow.mass
		_amounts.resize(_keys.size()+_previous_keys.size())
		for i in _keys.size():
			_amounts[i] = float(mass.get(_keys[i],0))/Flow.UNITS
		for i in _previous_keys.size():
			if not _flux.has(_previous_keys[i]):
				_amounts[_keys.size()+i] = float(mass.get(_previous_keys[i],0))/Flow.UNITS
	last_capture_usec = Time.get_ticks_usec()-_sample_started
	return true

func advance(budget_usec: int) -> void:
	last_cells = 0
	if not is_updating(): return
	var started := Time.get_ticks_usec()
	while is_updating():
		for _i in CHECK_INTERVAL:
			var key: Vector3i
			var amount: float
			if _head < _keys.size():
				key = _keys[_head]
				amount = _amounts[_head]
				_head += 1
			elif _previous_head < _previous_keys.size():
				key = _previous_keys[_previous_head]
				amount = _amounts[_keys.size()+_previous_head]
				_previous_head += 1
				if _flux.has(key): continue # Already sampled with its measured flux.
			else:
				completed_samples += 1
				last_latency_usec = Time.get_ticks_usec()-_sample_started
				_finish_sample()
				break
			var target := Vector2(_flux.get(key,Vector2.ZERO))/_seconds/maxf(0.25,amount)
			var previous := Vector2(velocities.get(key,Vector2.ZERO))
			var value := previous.lerp(target,_blend)
			if amount < 0.0625 or value.length_squared() < 0.00000001:
				velocities.erase(key)
			else:
				velocities[key] = value
			_write(key)
			last_cells += 1
		if Time.get_ticks_usec()-started >= budget_usec: break

func _finish_sample() -> void:
	_seconds = 0.0
	_flux = {}
	_amounts = PackedFloat64Array()
	_keys = []
	_previous_keys = []
	_head = 0
	_previous_head = 0

func get_stats() -> Dictionary:
	return {"pending":_keys.size()-_head+_previous_keys.size()-_previous_head,
		"sampled_cells":last_cells,"completed":completed_samples,
		"latency_ms":last_latency_usec/1000.0,"capture_ms":last_capture_usec/1000.0,
		"age_ms":(Time.get_ticks_usec()-_sample_started)/1000.0 if is_updating() else 0.0}

func _write(key: Vector3i) -> void:
	if not slots.has(key): return
	var index: int = slots[key]
	var current := velocity(key)
	image.set_pixel(index%WIDTH,floori(float(index)/WIDTH),Color(current.x,current.y,0,0))
	dirty = true

func upload() -> ImageTexture:
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	elif dirty:
		texture.update(image)
	dirty = false
	return texture
