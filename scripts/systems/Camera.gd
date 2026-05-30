class_name Camera
extends Node3D

## Camera controller — attach to the CameraRig root Node3D.
##
## All tuning values load from data/camera/camera_settings.json at startup.
## Edit that file to adjust feel without touching GDScript.
##
## Required scene hierarchy (wire @export vars in Inspector):
##
##   CameraRig   (Node3D, this script)    ← pans in XZ plane
##     └─ CameraArm   (Node3D)           ← @export arm_node   — Y-axis orbit
##          └─ SpringArm3D               ← @export spring_arm — zoom + collision
##               └─ Camera3D            ← @export camera_node — viewport
##
## The SpringArm3D collision_mask is forced to Layer 1 (terrain) on _ready().
## Do not collide with dwarves or items (see 32_navigation_3d.md).

const SETTINGS_PATH  := "res://data/camera/camera_settings.json"
const BLOCK_SIZE: int = 1          # 1 voxel = 1 m  (12_world_grid.md)
const SLICE_AUTO_OFFSET: int = 2   # camera sees this many layers below its Y

# ── Scene references (wire in Inspector — never use get_node paths) ───────────

@export var arm_node:    Node3D
@export var spring_arm:  SpringArm3D
@export var camera_node: Camera3D

# ── Settings (populated by _load_settings) ────────────────────────────────────

var _fov:         float = 45.0
var _near:        float = 0.1
var _far:         float = 1000.0
var _default_pos: Vector3 = Vector3(0.0, 25.0, 25.0)
var _default_rot: Vector3 = Vector3(-45.0, 0.0, 0.0)   # degrees

var _move_speed:  float = 15.0
var _shift_mult:  float = 2.5
var _move_smooth: float = 0.1
var _edge_scroll: bool  = false
var _edge_px:     int   = 10

var _rot_speed:   float = 0.5
var _invert_x:    bool  = false
var _invert_y:    bool  = false
var _min_pitch:   float = -85.0
var _max_pitch:   float = -10.0

var _zoom_speed:  float = 2.0
var _zoom_min:    float = 5.0
var _zoom_max:    float = 100.0
var _zoom_default: float = 30.0
var _zoom_proportional: bool = true   # Stonehearth-style: step scales with distance
var _zoom_smooth: float = 0.15

var _keys_forward:  Array[Key] = []
var _keys_backward: Array[Key] = []
var _keys_left:     Array[Key] = []
var _keys_right:    Array[Key] = []
var _btn_rotate:    MouseButton = MOUSE_BUTTON_MIDDLE

# ── Runtime state ─────────────────────────────────────────────────────────────

var _target_pos:   Vector3 = Vector3.ZERO
var _target_zoom:  float   = 30.0
var _pitch:        float   = -45.0   # spring arm X rotation (degrees)
var _orbit_y:      float   = 0.0    # arm Y rotation (degrees)
var _orbiting:     bool    = false
var _last_slice_y: int     = -9999

## Fires when the AUTO-slice Y changes. Connect to WorldRenderer to drive the
## horizontal layer cut-plane (see 21_camera.md §Horizontal Layer Slicing).
signal slice_y_changed(new_slice_y: int)


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_settings()
	_ensure_child_nodes()   # create arm / spring / camera if not wired in editor
	_apply_initial_transform()
	print("Camera: ready (FOV %d°, zoom %.0f–%.0f m)." % [int(_fov), _zoom_min, _zoom_max])


func _process(delta: float) -> void:
	_handle_pan(delta)
	_smooth_transforms(delta)
	_update_slice()


func _input(event: InputEvent) -> void:
	_handle_orbit_and_zoom(event)


# ── Child-node bootstrap ─────────────────────────────────────────────────────

## Creates CameraArm → SpringArm3D → Camera3D if the @export vars were not
## wired in the editor (e.g. when WorldRenderer instantiates this rig at runtime).
func _ensure_child_nodes() -> void:
	if arm_node == null:
		arm_node = Node3D.new()
		arm_node.name = "CameraArm"
		add_child(arm_node)

	if spring_arm == null:
		spring_arm = SpringArm3D.new()
		spring_arm.name = "SpringArm3D"
		arm_node.add_child(spring_arm)

	if camera_node == null:
		camera_node = Camera3D.new()
		camera_node.name = "Camera3D"
		spring_arm.add_child(camera_node)
		camera_node.make_current()   # replace whatever camera was active


# ── Settings loader ───────────────────────────────────────────────────────────

func _load_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_warning("Camera: cannot open %s — using defaults." % SETTINGS_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Camera: JSON parse error in %s." % SETTINGS_PATH)
		file.close()
		return
	file.close()

	var d: Dictionary = json.data

	# camera_settings ──────────────────────────────────────────────────────────
	var cs := d.get("camera_settings", {}) as Dictionary
	_fov         = cs.get("fov",        45.0)
	_near        = cs.get("near_clip",   0.1)
	_far         = cs.get("far_clip", 1000.0)
	var dp       = cs.get("default_position", {})
	_default_pos = Vector3(dp.get("x", 0.0), dp.get("y", 25.0), dp.get("z", 25.0))
	var dr       = cs.get("default_rotation", {})
	_default_rot = Vector3(dr.get("x", -45.0), dr.get("y", 0.0), dr.get("z", 0.0))

	# movement ─────────────────────────────────────────────────────────────────
	var mv := d.get("movement", {}) as Dictionary
	_move_speed  = mv.get("move_speed",                   15.0)
	_shift_mult  = mv.get("shift_multiplier",              2.5)
	_move_smooth = mv.get("smoothing",                     0.1)
	_edge_scroll = mv.get("edge_scroll_enabled",          false)
	_edge_px     = int(mv.get("edge_scroll_threshold_pixels", 10))

	# rotation ─────────────────────────────────────────────────────────────────
	var rot := d.get("rotation", {}) as Dictionary
	_rot_speed  = rot.get("rotation_speed",  0.5)
	_invert_x   = rot.get("invert_x",       false)
	_invert_y   = rot.get("invert_y",       false)
	_min_pitch  = rot.get("min_pitch",     -85.0)
	_max_pitch  = rot.get("max_pitch",     -10.0)

	# zoom ─────────────────────────────────────────────────────────────────────
	var zm := d.get("zoom", {}) as Dictionary
	_zoom_speed        = zm.get("zoom_speed",        2.0)
	_zoom_min          = zm.get("min_distance",      5.0)
	_zoom_max          = zm.get("max_distance",    100.0)
	_zoom_default      = zm.get("default_distance",  30.0)
	_zoom_proportional = zm.get("proportional",     true)
	_zoom_smooth       = zm.get("smoothing",         0.15)
	_target_zoom = clampf(_zoom_default, _zoom_min, _zoom_max)

	# input_mappings ───────────────────────────────────────────────────────────
	var im := d.get("input_mappings", {}) as Dictionary
	_keys_forward  = _parse_keys(im.get("move_forward",  []))
	_keys_backward = _parse_keys(im.get("move_backward", []))
	_keys_left     = _parse_keys(im.get("move_left",     []))
	_keys_right    = _parse_keys(im.get("move_right",    []))
	_btn_rotate    = _parse_mouse_button(im.get("rotate_action", "MOUSE_BUTTON_MIDDLE"))


# ── Initial transform ─────────────────────────────────────────────────────────

func _apply_initial_transform() -> void:
	global_position = _default_pos
	_target_pos     = _default_pos
	_pitch          = _default_rot.x
	_orbit_y        = _default_rot.y

	if arm_node:
		arm_node.rotation_degrees = Vector3(0.0, _orbit_y, 0.0)

	if spring_arm:
		spring_arm.rotation_degrees.x = _pitch
		spring_arm.spring_length      = _target_zoom
		spring_arm.collision_mask     = 1   # Layer 1: terrain only

	if camera_node:
		camera_node.fov  = _fov
		camera_node.near = _near
		camera_node.far  = _far


# ── Pan (WASD / arrows / edge scroll) ────────────────────────────────────────

func _handle_pan(delta: float) -> void:
	var dir := Vector2.ZERO

	if _any_key(_keys_forward):  dir.y -= 1.0
	if _any_key(_keys_backward): dir.y += 1.0
	if _any_key(_keys_left):     dir.x -= 1.0
	if _any_key(_keys_right):    dir.x += 1.0

	if _edge_scroll and dir == Vector2.ZERO:
		dir = _edge_scroll_dir()

	if dir == Vector2.ZERO:
		return

	dir         = dir.normalized()
	var speed   := _move_speed * (_shift_mult if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	# Scale pan speed with zoom so motion feels consistent at any distance
	# (Stonehearth CAMERA_SPEED_SCALE_FACTOR behaviour). Referenced to the
	# default zoom: at default distance, move_speed reads at face value;
	# zoomed in it's slower and finer, zoomed out it's faster.
	if spring_arm:
		speed *= spring_arm.spring_length / _zoom_default

	# Rotate 2D screen-space direction into world XZ using the current orbit.
	var o := deg_to_rad(_orbit_y)
	var world_dir := Vector3(
		dir.x * cos(o) + dir.y * sin(o),
		0.0,
		dir.x * -sin(o) + dir.y * cos(o)
	)

	_target_pos += world_dir * speed * delta


# ── Orbit (middle-mouse drag) and zoom (scroll wheel) ────────────────────────

func _handle_orbit_and_zoom(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton

		# Toggle orbit mode on middle-mouse press/release.
		if mbe.button_index == _btn_rotate:
			_orbiting = mbe.pressed

		# Scroll wheel: zoom in/out.
		# Proportional step (Stonehearth feel): the closer you are, the finer the
		# step; far out, each notch covers more ground. Scales by target/min.
		if mbe.pressed:
			var step := _zoom_speed
			if _zoom_proportional:
				step = _zoom_speed * (_target_zoom / _zoom_min)
			if mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom - step, _zoom_min, _zoom_max)
			elif mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom + step, _zoom_min, _zoom_max)

	elif event is InputEventMouseMotion and _orbiting:
		var mme := event as InputEventMouseMotion

		# Horizontal drag → orbit around Y axis.
		# Negative sign: dragging right rotates clockwise (natural feel).
		var dx := mme.relative.x * _rot_speed * (1.0 if _invert_x else -1.0)
		_orbit_y += dx

		# Vertical drag → pitch up/down, clamped to safe range.
		var dy := mme.relative.y * _rot_speed * (-1.0 if _invert_y else 1.0)
		_pitch  = clampf(_pitch + dy, _min_pitch, _max_pitch)


# ── Smooth transforms (exponential decay, frame-rate independent) ─────────────

func _smooth_transforms(delta: float) -> void:
	# Converts per-frame lerp fraction to a frame-rate-independent rate.
	# Formula: 1 - exp(-rate * delta), where rate ≈ -ln(1 - smooth) * 60.
	var pan_t  := 1.0 - exp(-_move_smooth  * 60.0 * delta)
	var zoom_t := 1.0 - exp(-_zoom_smooth  * 60.0 * delta)

	global_position = global_position.lerp(_target_pos, pan_t)

	if arm_node:
		arm_node.rotation_degrees.y = _orbit_y

	if spring_arm:
		spring_arm.rotation_degrees.x = _pitch
		spring_arm.spring_length       = lerpf(spring_arm.spring_length, _target_zoom, zoom_t)


# ── Horizontal layer slice (AUTO mode) ───────────────────────────────────────

func _update_slice() -> void:
	if camera_node == null:
		return
	# AUTO formula from 21_camera.md:
	#   slice_y = floor(camera_world_y / BLOCK_SIZE) + SLICE_AUTO_OFFSET
	var new_y := int(floor(camera_node.global_position.y / BLOCK_SIZE)) + SLICE_AUTO_OFFSET
	if new_y != _last_slice_y:
		_last_slice_y = new_y
		slice_y_changed.emit(new_y)


# ── Edge scroll ───────────────────────────────────────────────────────────────

func _edge_scroll_dir() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var size  := Vector2(vp.get_visible_rect().size)
	var mouse := vp.get_mouse_position()
	var t     := float(_edge_px)
	var dir   := Vector2.ZERO
	if mouse.x < t:            dir.x -= 1.0
	if mouse.x > size.x - t:  dir.x += 1.0
	if mouse.y < t:            dir.y -= 1.0
	if mouse.y > size.y - t:  dir.y += 1.0
	return dir


# ── Helpers ───────────────────────────────────────────────────────────────────

func _any_key(keys: Array[Key]) -> bool:
	for k: Key in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _parse_keys(raw) -> Array[Key]:
	var result: Array[Key] = []
	if raw is Array:
		for item in raw:
			var k := _str_to_key(str(item))
			if k != KEY_NONE:
				result.append(k)
	elif raw is String:
		var k := _str_to_key(raw as String)
		if k != KEY_NONE:
			result.append(k)
	return result


func _str_to_key(s: String) -> Key:
	match s:
		"KEY_W":     return KEY_W
		"KEY_S":     return KEY_S
		"KEY_A":     return KEY_A
		"KEY_D":     return KEY_D
		"KEY_UP":    return KEY_UP
		"KEY_DOWN":  return KEY_DOWN
		"KEY_LEFT":  return KEY_LEFT
		"KEY_RIGHT": return KEY_RIGHT
	return KEY_NONE


func _parse_mouse_button(s: String) -> MouseButton:
	match s:
		"MOUSE_BUTTON_MIDDLE":     return MOUSE_BUTTON_MIDDLE
		"MOUSE_BUTTON_WHEEL_UP":   return MOUSE_BUTTON_WHEEL_UP
		"MOUSE_BUTTON_WHEEL_DOWN": return MOUSE_BUTTON_WHEEL_DOWN
		"MOUSE_BUTTON_LEFT":       return MOUSE_BUTTON_LEFT
		"MOUSE_BUTTON_RIGHT":      return MOUSE_BUTTON_RIGHT
	return MOUSE_BUTTON_MIDDLE
