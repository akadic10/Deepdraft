extends Node3D

## The candle on a Miner's hat (doc 304). It burns while the dwarf is awake and it is dark where
## they stand: underground away from daylight, or in the open at night, with no lit torch or fire
## in sight. It is out in daylight and in a lit room, and it goes out as the dwarf settles down to
## sleep. Presentation only: nothing is saved and no job reads it.
##
## The light is not at the flame. A hat stands in the ceiling's rock of a tunnel three blocks high,
## and a light above the head would be shadowed by the head itself. It hangs before the brow,
## shadowed by rock and built walls only (TerrainLighting.configure_carried_light), drawn back out
## of any block it would enter, and kept under the slice's cut, so it never lights what a
## sliced-away wall hides. A small shadowless glow at the flame lights the cap itself.
const TerrainLighting = preload("res://scripts/components/TerrainLighting.gd")
const FurnitureLighting = preload("res://scripts/components/FurnitureLighting.gd")
## Marks the flame's mesh: it takes no outline (DwarfReadability) and stays out of portraits.
const FLAME := &"hat_flame"
const CHECK_SECONDS := 0.4
const FADE_SECONDS := 0.3
## Rest states in which the dwarf is still on its feet, on the way to a bed or a place to sleep.
const ON_THE_WAY := ["leaving_room", "finding_bed", "travelling_bed", "searching", "travelling"]

var agent: DwarfAgent
var settings: Dictionary
## What the rule says now, and how far the flame has come up (0 out, 1 burning).
var burning := false
var level := 0.0
var _dark := false
var _timer := 0.0
var _phase := 0.0
var _seat := Vector3.ZERO
var _flame: MeshInstance3D
var _flame_foot := Vector3.ZERO
var _flame_material: StandardMaterial3D
var _light: OmniLight3D
var _glow: OmniLight3D


## Hangs the candle on a hat whose model has a `flame` mesh.
static func attach(dwarf: DwarfAgent, hat: Node3D, light_settings: Dictionary) -> void:
	var helper := new()
	helper.name = "HatLight"
	helper.agent = dwarf
	helper.settings = light_settings
	hat.add_child(helper)
	helper.build(hat)


func build(hat: Node3D) -> void:
	_phase = float(agent.dwarf_id) * 1.3   # a squad's candles do not flicker together
	var at: Array = settings.get("position", [0, 2.6, 0.9])
	_seat = Vector3(float(at[0]), float(at[1]), float(at[2]))
	_flame = hat.find_child("flame", true, false) as MeshInstance3D
	if _flame != null:
		_flame.set_meta(FLAME, true)
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A flame gives its own light: unshaded, as the torch's is (FurnitureLighting).
		_flame_material = StandardMaterial3D.new()
		_flame_material.vertex_color_use_as_albedo = true
		_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flame.material_override = _flame_material
		var box := _flame.get_aabb()
		_flame_foot = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		_flame.visible = false
	_light = OmniLight3D.new()
	_light.name = "Candle"
	_light.light_color = Color(String(settings.get("color", "#FFFFFF")))
	_light.omni_range = float(settings.get("range", 6.0))
	_light.omni_attenuation = float(settings.get("attenuation", 1.0))
	TerrainLighting.configure_carried_light(_light)
	_light.position = _seat
	_light.visible = false
	add_child(_light)
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = _light.light_color
	_glow.omni_range = float(settings.get("glow_range", 1.5))
	_glow.shadow_enabled = false
	_glow.position = _flame_foot + Vector3.UP * 0.15
	_glow.visible = false
	add_child(_glow)


func _process(delta: float) -> void:
	if not is_instance_valid(agent) or not agent.is_inside_tree() or not agent.visible: return
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_SECONDS
		look()
	if level == 0.0 and not burning: return
	level = move_toward(level, 1.0 if burning else 0.0, delta / FADE_SECONDS)
	_show()


## Reads the spot and the dwarf and decides whether the candle burns. Run a few times a second.
func look() -> void:
	_dark = reads_dark()
	burning = _dark and stands_awake()


## Awake, or asleep on its feet still: walking to a bed or a place to sleep. The candle goes out
## as the dwarf settles down.
func stands_awake() -> bool:
	if not agent.is_sleeping(): return true
	var rest := agent.get_rest_behavior()
	return rest != null and String(rest.state) in ON_THE_WAY


## Whether it is dark where the dwarf stands: little daylight reaches the spot (the sky that
## reaches it, times how far the day has come), and no lit torch or fire is in sight within reach.
func reads_dark() -> bool:
	var sky := 1.0
	var lighting := get_tree().get_first_node_in_group("underground_lighting")
	if lighting != null: sky = lighting.actor_sky_at(agent.global_position + Vector3.UP * DwarfAgent.LOGICAL_HEIGHT * 0.5)
	var daylight := sky * (1.0 - SkyController.night_amount())
	# Between the two marks the candle stays as it is, so it does not gutter at a tunnel's mouth.
	var mark := float(settings.get("bright_above", 0.45)) if _dark else float(settings.get("dark_below", 0.3))
	if daylight >= mark: return false
	return not _fire_in_sight(agent.global_position + Vector3.UP * 2.5)


func _fire_in_sight(eye: Vector3) -> bool:
	# A candle a fire has put out stays out a little past the fire's reach, for the same reason.
	var reach := float(settings.get("fire_reach", 0.6)) * (1.0 if _dark else 1.15)
	for node: Node in get_tree().get_nodes_in_group(FurnitureLighting.LIGHT_GROUP):
		var fire := node as OmniLight3D
		if fire == null or not fire.visible or not fire.is_inside_tree() or fire.get_world_3d() != get_world_3d(): continue
		var at := fire.global_position
		if eye.distance_to(at) <= fire.omni_range * reach and _clear_line(eye, at): return true
	return false


## Whether no block stands between two points, sampled every quarter block.
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) * 4.0))
	for i in range(1, steps):
		if _solid(from.lerp(to, float(i) / steps)): return false
	return true


func _solid(at: Vector3) -> bool:
	return BlockRegistry.is_solid(WorldData.get_live_block(floori(at.x), floori(at.y), floori(at.z)))


func _show() -> void:
	var lit := level > 0.01
	_light.visible = lit
	_glow.visible = lit
	if _flame != null: _flame.visible = lit
	if not lit: return
	var t := float(Time.get_ticks_msec()) * 0.001 + _phase
	var flicker := 1.0 + 0.06 * sin(t * 9.1) + 0.04 * sin(t * 23.7)
	_light.light_energy = float(settings.get("energy", 2.0)) * level * flicker
	_glow.light_energy = float(settings.get("glow_energy", 1.0)) * level * flicker
	if _flame != null:
		# Above 1 an unshaded flame is all that reaches the glow threshold (doc 64, Lighting).
		var gain := float(SkyController.hearthblock_settings().get("flame_gain", 1.0)) if SkyController.hearthblock_active() else 1.0
		_flame_material.albedo_color = Color(gain, gain, gain)
		var tall := Basis.from_scale(Vector3(1.0, level * (1.0 + 0.12 * sin(t * 11.3)), 1.0))
		_flame.transform = Transform3D(tall, _flame_foot - tall * _flame_foot)
	_place()


## Sets the light before the brow, wherever the head is now.
func _place() -> void:
	var at := global_transform * _seat
	# Under the slice's cut: above it the light would cross rock the slice no longer draws.
	var cut := float(agent.get_slice_y() + 1) - 0.15
	if at.y > cut: at.y = maxf(cut, agent.global_position.y + 0.4)
	# Out of any block it would enter (a dwarf at a wall's face): back toward the head.
	var back := -global_basis.z.normalized() * 0.25
	for _step in 6:
		if not _solid(at): break
		at += back
	_light.global_position = at
