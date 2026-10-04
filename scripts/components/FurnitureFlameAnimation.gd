extends Node

## Cosmetic voxel flipbook, independent of calendar speed/heat. Only installed
## lights create this node. Meshes are shared; each fire owns its emission material.
## Visibility changes suspend the update loop when the slice hides the parent.
static var _clip_cache: Dictionary = {} # resource path -> named Mesh resources

var _owner: Node3D
var _flame: MeshInstance3D
var _light: OmniLight3D
var _material: StandardMaterial3D
var _frames: Array[Mesh] = []
var _durations: Array[float] = []
var _cycle: float = 0.0
var _elapsed: float = 0.0
var _accum: float = 0.0
var _phase: float = 0.0
var _speed: float = 1.0
var _frame_index: int = -1
var _base_energy: float
var _base_emission: float
var _light_variation: float
var _emission_variation: float
var _frequency: float
var _interval: float


func setup(owner_node: Node3D, flame: MeshInstance3D, light: OmniLight3D,
		material: StandardMaterial3D, config: Dictionary) -> bool:
	set_process(false)
	var clip := _load_clip(String(config.get("model", "")))
	var names: Array = config.get("frames", [])
	var durations: Array = config.get("frame_durations", [])
	if names.is_empty() or names.size() != durations.size():
		push_error("FurnitureFlameAnimation: frame names and durations must match.")
		return false
	for i in range(names.size()):
		var mesh := clip.get(String(names[i])) as Mesh
		var duration := float(durations[i])
		if mesh == null or duration <= 0.0:
			push_error("FurnitureFlameAnimation: missing frame or non-positive duration.")
			return false
		_frames.append(mesh)
		_durations.append(duration)
		_cycle += duration
	_owner = owner_node
	_flame = flame
	_light = light
	_material = material
	_base_energy = light.light_energy
	_base_emission = material.emission_energy_multiplier
	_light_variation = clampf(float(config.get("light_variation", 0)), 0.0, 1.0)
	_emission_variation = clampf(float(config.get("emission_variation", 0)), 0.0, 1.0)
	_frequency = maxf(float(config.get("flicker_frequency_hz", 1)), 0.0)
	_interval = 1.0 / maxf(float(config.get("update_hz", 30)), 1.0)
	# A fixed position-derived phase makes neighbors independent and restores
	# predictable starts without RNG or persisted cosmetic animation state.
	var at := owner_node.global_position * 8.0
	var seed_value := hash(Vector3i(roundi(at.x), roundi(at.y), roundi(at.z))) & 0x7FFFFFFF
	_phase = float(seed_value % 4093) / 4093.0
	var speed_variation := clampf(float(config.get("speed_variation", 0)), 0.0, .5)
	_speed = 1.0 + (float((seed_value >> 12) % 4093) / 4093.0 * 2.0 - 1.0) * speed_variation
	_elapsed = _phase * _cycle
	_apply_sample()
	_owner.visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	return true


static func _load_clip(path: String) -> Dictionary:
	if _clip_cache.has(path):
		return _clip_cache[path]
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("FurnitureFlameAnimation: missing clip '%s'." % path)
		return {}
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var model := scene.instantiate()
	var result := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		result[String(mesh.name)] = mesh.mesh
	model.free()
	_clip_cache[path] = result
	return result


func _sync_visibility() -> void:
	set_process(_owner.is_visible_in_tree())


func _process(delta: float) -> void:
	if not is_instance_valid(_owner) or not _owner.is_visible_in_tree():
		return
	_elapsed += delta * _speed
	_accum += delta
	if _accum < _interval:
		return
	_accum = fmod(_accum, _interval)
	_apply_sample()


func _apply_sample() -> void:
	var position_in_cycle := fposmod(_elapsed, _cycle)
	var index := 0
	while index < _durations.size() - 1 and position_in_cycle >= _durations[index]:
		position_in_cycle -= _durations[index]
		index += 1
	if index != _frame_index:
		_frame_index = index
		_flame.mesh = _frames[index]
	# Unequal frequencies avoid a regular brightness pulse; the weighted sum
	# stays within [-1,1], keeping both light and emission variation bounded.
	var t := (_elapsed + _phase * 17.0) * TAU * _frequency
	var wave := .55 * sin(t) + .30 * sin(t * 1.91 + _phase * TAU) + .15 * sin(t * .73)
	_light.light_energy = _base_energy * (1.0 + _light_variation * wave)
	_material.emission_energy_multiplier = _base_emission * (1.0 + _emission_variation * wave)
