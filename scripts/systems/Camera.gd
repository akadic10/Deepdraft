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
var _surface_floor_margin:     float = 8.0   # WALL clearance above surface in rugged terrain (no-collider safety)
var _surface_floor_min_clear:  float = 1.5   # clearance on flat ground (small → full ground-level zoom)
var _surface_floor_ruggedness: float = 8.0   # local height delta (blocks) at which full wall margin applies (21_camera.md, Surface floor)

var _move_speed:  float = 15.0
var _shift_mult:  float = 2.5
var _move_smooth: float = 0.1
var _edge_scroll: bool  = false
var _edge_px:     int   = 10
var _pan_ref_height: float = 135.0   # camera world-Y at default framing; move_speed reads face value here (21_camera.md)

var _rot_speed:   float = 0.5
var _invert_x:    bool  = false
var _invert_y:    bool  = false
var _min_pitch:   float = -85.0
var _max_pitch:   float = -10.0
var _orbit_dead_zone: float = 6.0   # pixels of mouse motion before orbit engages (Stonehearth dead zone)
var _orbit_dynamic_pivot: bool = true  # on orbit engage, re-anchor the pivot to the look point (Stonehearth _get_orbit_target)

var _zoom_speed:  float = 2.0         # legacy / non-proportional fixed step (units per notch)
var _zoom_min:    float = 5.0
var _zoom_max:    float = 100.0
var _zoom_default: float = 30.0
var _zoom_proportional: bool = true   # Stonehearth-style: step scales with current distance
var _zoom_step_fraction: float = 0.18 # proportional notch = this fraction of current distance (21_camera.md)
var _zoom_mode: String = "cursor_target"  # "cursor_target" = zoom toward mouse (Route B) | "spring_fraction" = Route A
var _cursor_min_gap: float = 14.0     # cursor zoom stops this far from the targeted surface point (never punches through)
var _zoom_smooth: float = 0.15

var _keys_forward:  Array[Key] = []
var _keys_backward: Array[Key] = []
var _keys_left:     Array[Key] = []
var _keys_right:    Array[Key] = []
var _btn_rotate:    MouseButton = MOUSE_BUTTON_RIGHT    # Stonehearth: orbit on right-mouse
var _btn_drag:      MouseButton = MOUSE_BUTTON_MIDDLE   # Stonehearth: grab-the-ground pan on middle-mouse

# Cursor overlay (emoji shown while orbit/drag is active, like Stonehearth's cursor swap)
var _cursor_enabled:    bool   = true
var _cursor_orbit:      String = "🔄"
var _cursor_drag:       String = "✋"
var _cursor_size:       int    = 28
var _cursor_hide_os:    bool   = true

# ── Runtime state ─────────────────────────────────────────────────────────────

var _target_pos:   Vector3 = Vector3.ZERO
var _target_zoom:  float   = 30.0
var _pitch:        float   = -45.0   # spring arm X rotation (degrees)
var _orbit_y:      float   = 0.0    # arm Y rotation (degrees)
var _orbiting:     bool    = false   # rotate button held
var _orbit_active: bool    = false   # dead zone exceeded → rotation applied
var _orbit_accum:  float   = 0.0     # accumulated mouse motion since the button went down
var _dragging:     bool    = false   # grab-the-ground pan active
var _drag_grab:    Vector3 = Vector3.ZERO   # world point grabbed under the cursor on drag start
var _cursor_layer: CanvasLayer = null
var _cursor_label: Label       = null
var _cursor_os_hidden: bool    = false
var _zoom_suppressed: bool = false   # an active tool (e.g. mining brush resize) owns the wheel
var _last_slice_y: int     = -9999

## Fires when the AUTO-slice Y changes. Connect to WorldRenderer to drive the
## horizontal layer cut-plane (see 21_camera.md §Horizontal Layer Slicing).
signal slice_y_changed(new_slice_y: int)


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group(SaveManager.OWNER_GROUP)
	_load_settings()
	_ensure_child_nodes()   # create arm / spring / camera if not wired in editor
	_build_cursor_overlay()
	_apply_initial_transform()
	print("Camera: ready (FOV %d°, zoom %.0f–%.0f m)." % [int(_fov), _zoom_min, _zoom_max])


func _process(delta: float) -> void:
	_handle_pan(delta)
	_handle_drag()
	_smooth_transforms(delta)
	_enforce_camera_floor()
	_update_slice()
	_update_cursor_overlay()


## Presses and wheel notches route through _unhandled_input so the GUI and the
## click-tools see them FIRST: scrolling over a dock window no longer zooms the
## world behind it, and an RMB press on a panel no longer arms an orbit. (The
## old _input hook saw every event before Control GUI processing — the defect
## behind the set_zoom_suppressed workaround's siblings.)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_handle_mouse_press(event as InputEventMouseButton)


## Releases and orbit motion stay on the raw _input path deliberately: once a
## world drag is active, the camera must keep receiving events even while the
## pointer crosses a Control (which would consume them before _unhandled_input)
## — otherwise an orbit stalls over any window, and a button released over a
## panel would leave the camera orbiting/panning forever. Both handlers no-op
## unless the corresponding drag is already active, so this path can never
## START an interaction over UI.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_handle_mouse_release(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _orbiting:
		_handle_orbit_motion(event as InputEventMouseMotion)


## Alt-tab mid-orbit means the release event never arrives — end any drag and
## restore the OS cursor so it can't stay hidden outside the game. Same on
## teardown (SaveManager scene reload mid-drag).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_orbiting = false
		_orbit_active = false
		_orbit_accum = 0.0
		_dragging = false
		_set_os_cursor_hidden(false)
	elif what == NOTIFICATION_EXIT_TREE:
		_set_os_cursor_hidden(false)


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
	_surface_floor_margin     = cs.get("surface_floor_margin",     8.0)
	_surface_floor_min_clear  = cs.get("surface_floor_min_clear",  1.5)
	_surface_floor_ruggedness = cs.get("surface_floor_ruggedness", 8.0)

	# movement ─────────────────────────────────────────────────────────────────
	var mv := d.get("movement", {}) as Dictionary
	_move_speed  = mv.get("move_speed",                   15.0)
	_shift_mult  = mv.get("shift_multiplier",              2.5)
	_move_smooth = mv.get("smoothing",                     0.1)
	_edge_scroll = mv.get("edge_scroll_enabled",          false)
	_edge_px     = int(mv.get("edge_scroll_threshold_pixels", 10))
	_pan_ref_height = mv.get("pan_reference_height",     135.0)

	# rotation ─────────────────────────────────────────────────────────────────
	var rot := d.get("rotation", {}) as Dictionary
	_rot_speed  = rot.get("rotation_speed",  0.5)
	_invert_x   = rot.get("invert_x",       false)
	_invert_y   = rot.get("invert_y",       false)
	_min_pitch  = rot.get("min_pitch",     -85.0)
	_max_pitch  = rot.get("max_pitch",     -10.0)
	_orbit_dead_zone = rot.get("dead_zone_pixels", 6.0)
	_orbit_dynamic_pivot = rot.get("dynamic_pivot", true)

	# zoom ─────────────────────────────────────────────────────────────────────
	var zm := d.get("zoom", {}) as Dictionary
	_zoom_speed         = zm.get("zoom_speed",         2.0)
	_zoom_min           = zm.get("min_distance",       5.0)
	_zoom_max           = zm.get("max_distance",     100.0)
	_zoom_default       = zm.get("default_distance",  30.0)
	_zoom_proportional  = zm.get("proportional",      true)
	_zoom_step_fraction = zm.get("zoom_step_fraction", 0.18)
	_zoom_mode          = zm.get("mode",     "cursor_target")
	_cursor_min_gap     = zm.get("cursor_min_gap",     14.0)
	_zoom_smooth        = zm.get("smoothing",          0.15)
	_target_zoom = clampf(_zoom_default, _zoom_min, _zoom_max)

	# input_mappings ───────────────────────────────────────────────────────────
	var im := d.get("input_mappings", {}) as Dictionary
	_keys_forward  = _parse_keys(im.get("move_forward",  []))
	_keys_backward = _parse_keys(im.get("move_backward", []))
	_keys_left     = _parse_keys(im.get("move_left",     []))
	_keys_right    = _parse_keys(im.get("move_right",    []))
	_btn_rotate    = _parse_mouse_button(im.get("rotate_action", "MOUSE_BUTTON_RIGHT"))
	_btn_drag      = _parse_mouse_button(im.get("drag_action",   "MOUSE_BUTTON_MIDDLE"))

	# cursors ────────────────────────────────────────────────────────────────────
	var cur := d.get("cursors", {}) as Dictionary
	_cursor_enabled = cur.get("enabled",              true)
	_cursor_orbit   = cur.get("orbit",                "🔄")
	_cursor_drag    = cur.get("drag",                 "✋")
	_cursor_size    = int(cur.get("size",               28))
	_cursor_hide_os = cur.get("hide_system_cursor",   true)


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
	# Fast by default; Shift is a PRECISION (slow) modifier — shift_multiplier < 1.0.
	var speed   := _move_speed * (_shift_mult if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	# Scale pan speed with camera HEIGHT (Stonehearth: speed = camera.position.y) so
	# motion feels consistent at any framing: high overview sweeps fast, low/zoomed-in
	# nudges finely. Referenced to the default framing height so move_speed reads at
	# face value there. Using world-Y (not spring_length) also makes a shallow pitch —
	# which lowers the camera — pan finer automatically. (21_camera.md)
	if camera_node and _pan_ref_height > 0.0:
		speed *= maxf(camera_node.global_position.y, 1.0) / _pan_ref_height

	# Rotate 2D screen-space direction into world XZ using the current orbit.
	var o := deg_to_rad(_orbit_y)
	var world_dir := Vector3(
		dir.x * cos(o) + dir.y * sin(o),
		0.0,
		dir.x * -sin(o) + dir.y * cos(o)
	)

	_target_pos += world_dir * speed * delta


# ── Grab-the-ground drag pan (Stonehearth _drag) ─────────────────────────────

## On drag-button press: remember the world point under the cursor.
func _start_drag() -> void:
	var hit := _zoom_target_point()
	if hit.get("hit", false):
		_drag_grab = hit["point"]
		_dragging  = true
	else:
		_dragging = false


## Each frame while dragging: shift the rig in XZ so the grabbed world point stays
## locked under the cursor — the ground feels physically grabbed. Tracks 1:1 (snaps
## XZ, killing pan-smoothing lag during the grab); Y still goes through the floor.
func _handle_drag() -> void:
	if not _dragging or camera_node == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera_node.project_ray_origin(mouse)
	var dir := camera_node.project_ray_normal(mouse).normalized()
	if is_zero_approx(dir.y):
		return
	# Cursor ray ∩ horizontal plane through the grabbed point.
	var t := (_drag_grab.y - origin.y) / dir.y
	if t <= 0.0:
		return
	var p_now := origin + dir * t
	var delta := _drag_grab - p_now        # move the world so the grab point returns under the cursor
	delta.y = 0.0
	_target_pos += delta
	global_position.x = _target_pos.x      # track 1:1, no smoothing lag while grabbing
	global_position.z = _target_pos.z


# ── Public API ────────────────────────────────────────────────────────────────

## Let an active tool claim the mouse wheel (e.g. the mining brush resize) so it
## doesn't also zoom the camera. The tool sets this true on activate, false on deactivate.
func set_zoom_suppressed(v: bool) -> void:
	_zoom_suppressed = v


func save_section_key() -> String:
	return "camera"


func save_restore_priority() -> int:
	return 70


func serialize_state() -> Dictionary:
	return {
		"target_position": SaveManager.pack_v3(_target_pos),
		"zoom": _target_zoom,
		"pitch": _pitch,
		"orbit_y": _orbit_y,
	}


func restore_state(state: Dictionary) -> void:
	_target_pos = SaveManager.unpack_v3(state.get("target_position", []))
	global_position = _target_pos
	_target_zoom = clampf(float(state.get("zoom", _zoom_default)), _zoom_min, _zoom_max)
	_pitch = clampf(float(state.get("pitch", _default_rot.x)), _min_pitch, _max_pitch)
	_orbit_y = float(state.get("orbit_y", _default_rot.y))
	if arm_node != null:
		arm_node.rotation_degrees.y = _orbit_y
	if spring_arm != null:
		spring_arm.rotation_degrees.x = _pitch
		spring_arm.spring_length = _target_zoom


# ── Cursor overlay (emoji while orbit/drag is active) ─────────────────────────

## Build a tiny CanvasLayer + Label that renders an emoji at the mouse position.
## (UI lives on a CanvasLayer per Hard Rule 7; the dock proves emoji glyphs render.)
func _build_cursor_overlay() -> void:
	if not _cursor_enabled:
		return
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 128             # above gameplay UI
	add_child(_cursor_layer)

	_cursor_label = Label.new()
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_label.add_theme_font_size_override("font_size", _cursor_size)
	_cursor_label.visible = false
	_cursor_layer.add_child(_cursor_label)


## Show ✋ while grab-dragging and 🔄 while orbiting; hide the OS cursor under it.
func _update_cursor_overlay() -> void:
	if _cursor_label == null:
		return

	var emoji := ""
	if _dragging:
		emoji = _cursor_drag
	elif _orbit_active:
		emoji = _cursor_orbit

	if emoji == "":
		if _cursor_label.visible:
			_cursor_label.visible = false
			_set_os_cursor_hidden(false)
		return

	_cursor_label.text = emoji
	# Centre the glyph on the pointer (emoji box ≈ font size).
	var mp := get_viewport().get_mouse_position()
	_cursor_label.position = mp - Vector2(_cursor_size, _cursor_size) * 0.5
	_cursor_label.visible = true
	_set_os_cursor_hidden(true)


func _set_os_cursor_hidden(hide_it: bool) -> void:
	if not _cursor_hide_os or hide_it == _cursor_os_hidden:
		return
	_cursor_os_hidden = hide_it
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide_it else Input.MOUSE_MODE_VISIBLE


# ── Orbit (RMB drag, dead-zoned), grab-drag pan (MMB) and zoom (wheel) ────────

## Press-side half (called from _unhandled_input — UI-hovered events never
## arrive here, which is the whole point).
func _handle_mouse_press(mbe: InputEventMouseButton) -> void:
	# Orbit: armed while the rotate button (RMB) is held. Rotation only begins
	# once the mouse moves past _orbit_dead_zone, so a click-wobble (e.g. a
	# context click) doesn't spin the view. (Stonehearth dead zone.)
	if mbe.button_index == _btn_rotate:
		_orbiting = true
		_orbit_accum  = 0.0      # reset the dead-zone accumulator on press
		_orbit_active = false

	# Grab-the-ground pan: start on the drag button (MMB) press.
	if mbe.button_index == _btn_drag:
		_start_drag()

	# Scroll wheel: zoom in/out. Dispatches to _apply_zoom → cursor-targeted zoom
	# (zoom toward the point under the mouse, clamped at that surface) or the
	# spring_fraction fallback. Both use a geometric per-notch step. (21_camera.md)
	if (mbe.button_index == MOUSE_BUTTON_WHEEL_UP or mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN) \
			and (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT)):
		return
	# An active tool (e.g. the mining brush) claims the wheel for its own resize.
	# Kept even now that the wheel routes through _unhandled_input: the relative
	# order of _unhandled_input between this rig (runtime-instanced) and the
	# tools is scene-order-fragile, so the explicit claim stays as the guarantee.
	if _zoom_suppressed and (mbe.button_index == MOUSE_BUTTON_WHEEL_UP or mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		return
	if mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(true)
	elif mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(false)


## Release-side half (called from _input so a release over UI still lands).
func _handle_mouse_release(mbe: InputEventMouseButton) -> void:
	if mbe.button_index == _btn_rotate:
		_orbiting = false
		_orbit_accum  = 0.0
		_orbit_active = false    # …so the 🔄 cursor clears the moment RMB is let go
	if mbe.button_index == _btn_drag:
		_dragging = false


func _handle_orbit_motion(mme: InputEventMouseMotion) -> void:
	# Dead zone: accumulate motion until it passes the threshold, then orbit.
	if not _orbit_active:
		_orbit_accum += absf(mme.relative.x) + absf(mme.relative.y)
		if _orbit_accum < _orbit_dead_zone:
			return
		_orbit_active = true
		if _orbit_dynamic_pivot:
			_reanchor_orbit_pivot()   # spin around what you're looking at

	# Horizontal drag → orbit around Y axis (snap — rotation is not smoothed).
	# Negative sign: dragging right rotates clockwise (natural feel).
	var dx := mme.relative.x * _rot_speed * (1.0 if _invert_x else -1.0)
	_orbit_y += dx

	# Vertical drag → pitch up/down, clamped to safe range.
	var dy := mme.relative.y * _rot_speed * (-1.0 if _invert_y else 1.0)
	_pitch  = clampf(_pitch + dy, _min_pitch, _max_pitch)


# ── Zoom (cursor-targeted, with spring-fraction fallback) ─────────────────────

## One wheel notch. Tries cursor-targeted zoom (toward the point under the mouse);
## falls back to the spring_fraction step if disabled or the ray hits nothing.
func _apply_zoom(zoom_in: bool) -> void:
	if _zoom_mode == "cursor_target" and camera_node != null:
		if _zoom_cursor(zoom_in):
			return
	_zoom_spring(zoom_in)


## Route A fallback: shrink/grow spring_length toward the rig pivot by a geometric step.
func _zoom_spring(zoom_in: bool) -> void:
	var step := _zoom_speed
	if _zoom_proportional:
		step = _target_zoom * _zoom_step_fraction
	_target_zoom = clampf(_target_zoom + (-step if zoom_in else step), _zoom_min, _zoom_max)


## Cursor-targeted zoom (21_camera.md, Zoom — keep-rig variant).
##
## Scales the whole rig (pivot target + spring length) toward the surface point P
## under the cursor by a single factor s. Because pivot and camera scale toward P by
## the same s with the view direction held fixed, P stays put on screen — true
## "zoom to cursor" — and the move is clamped to stop _cursor_min_gap short of P, so
## scrolling can never punch through the surface. Returns false (→ spring fallback)
## when the ray finds no target or the geometry is degenerate.
func _zoom_cursor(zoom_in: bool) -> bool:
	var hit := _zoom_target_point()
	if not hit.get("hit", false):
		return false
	var p: Vector3 = hit["point"]

	# View direction is fixed during zoom: unit vector from pivot to camera.
	var u := camera_node.global_position - global_position
	if u.length() < 0.001:
		return false
	u = u.normalized()

	var l0 := _target_zoom
	var c0 := _target_pos + u * l0          # target camera position (orientation unchanged)
	var dist_cp := c0.distance_to(p)
	if dist_cp < 0.001:
		return false

	# Solve for the scale factor s = L1/L0, clamped so spring length stays in range
	# and the camera never comes within _cursor_min_gap of the targeted surface.
	var frac := _zoom_step_fraction
	var s: float
	if zoom_in:
		var s_lo := maxf(_zoom_min / l0, _cursor_min_gap / dist_cp)
		s = clampf(1.0 - frac, minf(s_lo, 1.0), 1.0)
	else:
		var s_hi := maxf(_zoom_max / l0, 1.0)
		s = clampf(1.0 + frac, 1.0, s_hi)

	if is_equal_approx(s, 1.0):
		return true   # fully clamped; notch consumed, no movement

	_target_zoom = clampf(s * l0, _zoom_min, _zoom_max)
	_target_pos  = p + (_target_pos - p) * s
	_target_pos.y = clampf(_target_pos.y, 1.0, _far)   # keep the pivot sane
	return true


## Find the ground point under the cursor by marching the ray against the terrain
## HEIGHT FIELD (WorldGenerator.get_visible_surface_y) — the same source the overview
## renderer uses. This works map-wide regardless of which chunks WorldData has
## streamed; the old WorldData voxel DDA missed un-streamed overview columns and fell
## back to a plane at the pivot height, which left zoom stuck high above the ground.
func _zoom_target_point() -> Dictionary:
	if camera_node == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	return _march_surface(camera_node.project_ray_origin(mouse),
		camera_node.project_ray_normal(mouse).normalized())


## March a ray against the terrain height field; returns {hit, point} where it first
## drops to/below the surface, or {} on a miss (ray points up, or no ground within range).
func _march_surface(origin: Vector3, dir: Vector3) -> Dictionary:
	if not WorldGenerator.has_method("get_visible_surface_y"):
		return {}
	if dir.y >= -0.0001:
		return {}   # not looking downward (the pitch clamp normally prevents this)
	const STEP := 1.0
	const MAX_T := 1200.0
	var t := 0.0
	while t <= MAX_T:
		var pt := origin + dir * t
		var surf := float(WorldGenerator.get_visible_surface_y(int(floor(pt.x)), int(floor(pt.z))))
		if pt.y <= surf:
			return { "hit": true, "point": Vector3(pt.x, surf, pt.z) }
		t += STEP
	return {}


## Dynamic orbit pivot (Stonehearth _get_orbit_target). When orbit engages, move the rig
## pivot to the ground point straight ahead of the camera and recompute spring length so
## the camera does NOT move — then the existing orbit math rotates around what you're
## looking at instead of the old rig origin. Skips (keeps the old pivot) if the look
## point is out of the zoom range, which would otherwise force a visible jump.
func _reanchor_orbit_pivot() -> void:
	if camera_node == null:
		return
	var cam := camera_node.global_position
	var fwd := -camera_node.global_transform.basis.z   # camera forward (look direction)
	var hit := _march_surface(cam, fwd.normalized())
	if not hit.get("hit", false):
		return
	var p: Vector3 = hit["point"]
	# p lies along the forward ray, so the pivot→camera direction is unchanged; setting
	# spring_length = |cam − p| and the rig to p leaves the camera exactly where it is.
	var new_len := cam.distance_to(p)
	if new_len < _zoom_min or new_len > _zoom_max:
		return
	_target_pos     = p
	global_position = p
	_target_zoom    = new_len
	if spring_arm:
		spring_arm.spring_length = new_len   # snap live so there's no lerp jump this frame


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


# ── Camera surface floor (no-collider clip guard) ─────────────────────────────

## Keep the camera at least _surface_floor_margin above the terrain everywhere.
## The terrain has no physics colliders, so the SpringArm cannot push the camera
## out of rock; this is the global guard that stops deep zoom / low pitch from
## clipping below or into the surface. Samples a small neighbourhood (not just the
## camera's own column) so a tall wall the camera is near also lifts it clear.
## Lifts the whole rig (pivot + live position) by the deficit, preserving framing.
func _enforce_camera_floor() -> void:
	if camera_node == null or _surface_floor_margin <= 0.0:
		return
	if not WorldGenerator.has_method("get_visible_surface_y"):
		return

	var cam := camera_node.global_position

	# Sample around the LOOK point (the rig pivot = what you're zooming into), not the
	# camera's own column — so pointing at flat ground lets you get close even when the
	# camera body sits near a shelf edge behind it. Radius 1 (immediate neighbours only)
	# so only a true adjacent wall counts. (get_visible_surface_y is terrain-only, so
	# placed flora/props never inflate the floor.) §8a follow-up.
	var lx := int(floor(_target_pos.x))
	var lz := int(floor(_target_pos.z))

	var max_surf := int(WorldGenerator.get_visible_surface_y(lx, lz))
	var min_surf := max_surf
	for ox in [-1, 0, 1]:
		for oz in [-1, 0, 1]:
			var sy := int(WorldGenerator.get_visible_surface_y(lx + ox, lz + oz))
			if sy > max_surf: max_surf = sy
			if sy < min_surf: min_surf = sy

	# Ruggedness 0..1: how much the surface varies nearby. Flat ground ≈ 0 (→ tiny
	# clearance, so you can zoom to ground level); a wall/notch ≈ 1 (→ full margin to
	# keep the camera clear of the rock). This is the §8a fix.
	var rugged := 0.0
	if _surface_floor_ruggedness > 0.0:
		rugged = clampf(float(max_surf - min_surf) / _surface_floor_ruggedness, 0.0, 1.0)

	var margin := lerpf(_surface_floor_min_clear, _surface_floor_margin, rugged)
	var floor_y := float(max_surf) + margin

	var deficit := floor_y - cam.y
	if deficit > 0.0:
		# Lift the rig (and its target) so the camera clears terrain without changing
		# orbit, pitch, or zoom distance.
		global_position.y += deficit
		_target_pos.y     += deficit


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
