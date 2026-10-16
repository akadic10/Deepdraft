extends RefCounted

## One stable texture per lighting owner. Materials bind it once; live fog and
## sky changes upload 320 bytes without invalidating every material's uniforms.
## Layout is shared with atmosphere() in underground_lighting.gdshader.
var _image := Image.create(20, 1, false, Image.FORMAT_RGBAF)
var texture: ImageTexture


func _init() -> void:
	_pack({})
	texture = ImageTexture.create_from_image(_image)


func update(values: Dictionary) -> void:
	_pack(values)
	texture.update(_image)


func _pack(values: Dictionary) -> void:
	_image.set_pixel(0, 0, Color(float(values.get("scene_fog_enabled", false)), values.get("fog_density", 0.0), float(values.get("fog_depth_mode", true)), values.get("fog_aerial", 0.0)))
	var depth: Vector3 = values.get("fog_depth", Vector3(0, 170, 1))
	_image.set_pixel(1, 0, Color(depth.x, depth.y, depth.z, values.get("fog_sun_count", 0)))
	var height: Vector2 = values.get("fog_height", Vector2.ZERO)
	_image.set_pixel(2, 0, Color(height.x, height.y, 0, 0))
	# These used to be source_color uniforms. A raw float data sampler does not
	# perform that conversion, so convert exactly once here (including HDR RGB).
	var colors := ["fog_color", "fog_sky_top", "fog_sky_horizon", "fog_ground_bottom", "fog_ground_horizon"]
	for i in range(colors.size()):
		var color: Color = values.get(colors[i], Color(0, 0, 0, 0))
		_image.set_pixel(3 + i, 0, color.srgb_to_linear())
	var curves: Vector2 = values.get("fog_sky_curves", Vector2(4, 30))
	_image.set_pixel(8, 0, Color(curves.x, curves.y, 0, 0))
	var rotation: Basis = values.get("fog_sky_rotation", Basis.IDENTITY)
	_vector(9, rotation.x)
	_vector(10, rotation.y)
	_vector(11, rotation.z)
	var directions: PackedVector3Array = values.get("fog_sun_directions", PackedVector3Array())
	var sunlight: PackedVector3Array = values.get("fog_sun_colors", PackedVector3Array())
	for i in range(4):
		_vector(12 + i, directions[i] if i < directions.size() else Vector3.ZERO)
		# Sun colours already arrive in linear space from the lighting owner.
		_vector(16 + i, sunlight[i] if i < sunlight.size() else Vector3.ZERO)


func _vector(index: int, value: Vector3) -> void:
	_image.set_pixel(index, 0, Color(value.x, value.y, value.z, 0))
