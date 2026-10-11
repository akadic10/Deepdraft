extends RefCounted

## A small GPU lookup table indexed by water-space keys, so cave pools and
## surface water at the same XZ never share currents. Animation needs no remesh.
## The solver only supplies measured flux; this state is disposable on load.
const WIDTH := 256
var slots: Dictionary = {}
var velocities: Dictionary = {}
var image := Image.create(WIDTH,256,false,Image.FORMAT_RGBAF)
var texture: ImageTexture
var dirty := true
var gain := 1.3
var maximum_speed := 0.8

func reset() -> void:
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

func update(flow: RefCounted, seconds: float) -> void:
	if seconds <= 0: return
	var keys := velocities.duplicate()
	keys.merge(flow.surface_flux)
	var blend := 1.0-exp(-seconds/0.85)
	for key: Vector3i in keys:
		var target := Vector2(flow.surface_flux.get(key,Vector2.ZERO))/seconds/maxf(0.25,flow.volume(key))
		var value := Vector2(velocities.get(key,Vector2.ZERO)).lerp(target,blend)
		if flow.volume(key)<0.0625 or value.length_squared()<0.00000001:
			velocities.erase(key)
		else:
			velocities[key] = value
		_write(key)
	flow.surface_flux.clear()

func _write(key: Vector3i) -> void:
	if not slots.has(key): return
	var index: int = slots[key]
	var current := velocity(key)
	image.set_pixel(index%WIDTH,index/WIDTH,Color(current.x,current.y,0,0))
	dirty = true

func upload() -> ImageTexture:
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	elif dirty:
		texture.update(image)
	dirty = false
	return texture
