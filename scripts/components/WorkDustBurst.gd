extends Node3D

## Bounded cosmetic cubes, one draw call. No collision, loot or world RNG.
var age := 0.0
var lifetime := .72
var floor_y := 0
var _floor_offset := .06
var _mesh: MultiMeshInstance3D
var _particles: Array[Dictionary] = []


func setup(settings: Dictionary, size: float, seed_value: int, base_floor: int, direction := Vector3.ZERO) -> void:
	floor_y = base_floor
	_floor_offset = float(settings.get("floor_offset",.06))
	lifetime = float(settings["lifetime"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_mesh = MultiMeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	multi.mesh = cube
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = material
	var dust_count := int(settings["dust_count"])
	multi.instance_count = dust_count + int(settings["chip_count"])
	_mesh.multimesh = multi
	add_child(_mesh)
	for i in range(multi.instance_count):
		var dust := i < dust_count
		var angle := rng.randf_range(0,TAU)
		var radial := Vector3(cos(angle),0,sin(angle))
		var width := rng.randf_range(.55,.95) if dust else rng.randf_range(.09,.18)
		var colors: Array = settings["dust_colors" if dust else "chip_colors"]
		var color := Color(colors[rng.randi_range(0,colors.size()-1)])
		color.a = .65 if dust else 1.0
		var start := radial * rng.randf_range(.15,1.1) * float(settings.get("spread",1.0))
		start += Vector3.UP * rng.randf_range(.15,1.45) * float(settings.get("height",1.0))
		var velocity := radial * rng.randf_range(1.2,3.6) + Vector3.UP * rng.randf_range(.5,2.4)
		if not direction.is_zero_approx():
			start = direction*.04
			velocity = radial*.45 + direction*rng.randf_range(1.4,2.6) + Vector3.UP*rng.randf_range(.3,1.2)
		_particles.append({
			"start": start * size,
			"velocity": velocity * size,
			"size": Vector3(width,width if dust else width*.65,width if dust else width*1.7) * size,
			"rotation": Vector3(rng.randf(),rng.randf(),rng.randf()) * TAU,
			"spin": Vector3(rng.randf(),rng.randf(),rng.randf()) * (1.2 if dust else 7.0),
			"gravity": .7 if dust else 7.0,
			"color": color,
		})
	advance(0)


func advance(delta: float) -> bool:
	age += delta
	var fraction := clampf(age/lifetime,0,1)
	for i in range(_particles.size()):
		var p := _particles[i]
		var offset: Vector3 = p.start + p.velocity*age - Vector3.UP * float(p.gravity)*age*age*.5
		offset.y = maxf(offset.y,_floor_offset)
		var shrink := maxf(.001,pow(1.0-fraction,.65))
		var basis := Basis.from_euler(p.rotation + p.spin*age).scaled(p.size*shrink)
		_mesh.multimesh.set_instance_transform(i,Transform3D(basis,offset))
		var color: Color = p.color
		color.a *= 1.0-fraction
		_mesh.multimesh.set_instance_color(i,color)
	return age >= lifetime
