class_name SingleBlockViewer
extends Node3D

## Renders a solid box of voxels using the real ChunkMesher path so you can
## validate exactly what blocks look like in-game (same face culling, same
## vertex-colour material as WorldRenderer).
##
## fill_size controls the region:
##   (1, 1, 1)    → a single block (all six faces visible).
##   (16, 16, 16) → a full chunk-sized cube of one block type.
##
## How it works:
##   - A throwaway Chunk is filled with `block_key` over fill_size, anchored so
##     the region stays inside the 16³ chunk.
##   - ChunkMesher.build_mesh() produces the exact mesh the game would draw.
##     Interior faces are culled; only the outer shell renders.
##
## Camera and light are spawned in code to keep the scene minimal and
## scene-agnostic (see AGENT.md § Script-to-Scene Contract).
##
## ORBIT CONTROLS:
##   Left-drag (or middle-drag) ... orbit around the region
##   Mouse wheel ................... zoom in / out
##   R ............................. reset view

## Block to display. Change in the Inspector to validate any other block key
## from data/terrain/terrain_blocks.json.
@export var block_key: StringName = &"base:terrain:surface:dirt_01"

## Size of the solid box to draw, in blocks. Clamped to the 16³ chunk.
## (1,1,1) = single block. (16,16,16) = full chunk cube.
@export var fill_size: Vector3i = Vector3i(16, 16, 16)

## Match WorldRenderer's current material (SHADING_MODE_UNSHADED). With unshaded
## the cube is a single flat colour with no edge shading — exactly what the game
## renders today. Turn OFF to use per-pixel shading + the spawned sun so the cube
## reads as a 3D shape.
@export var unshaded: bool = true

# ── Orbit tuning ──────────────────────────────────────────────────────────────
@export var orbit_speed: float = 0.01    # radians per pixel dragged
@export var zoom_speed:   float = 1.0     # metres per wheel notch
@export var min_zoom:     float = 1.5
@export var max_zoom:     float = 120.0

const CHUNK_SIZE: int = 16

# ── Runtime camera state ──────────────────────────────────────────────────────
var _pivot:  Node3D
var _camera: Camera3D

var _yaw:      float = 0.785   # ~ 45°
var _pitch:    float = 0.5     # camera raised above the region, looking down
var _distance: float = 6.0

var _dragging: bool = false

# Defaults captured for the reset key.
const DEF_YAW   := 0.785
const DEF_PITCH := 0.5

var _def_distance: float = 6.0


func _ready() -> void:
	var id: int = BlockRegistry.get_id(block_key)
	if id < 0:
		push_error("SingleBlockViewer: unknown block key '%s'." % block_key)
		return

	# Clamp the requested region to a single chunk (1..16 per axis).
	var size := Vector3i(
		clampi(fill_size.x, 1, CHUNK_SIZE),
		clampi(fill_size.y, 1, CHUNK_SIZE),
		clampi(fill_size.z, 1, CHUNK_SIZE))

	# Anchor the region inside the chunk. Centre it when it doesn't fill an axis
	# so every outer face has an in-chunk void neighbour and renders cleanly.
	var origin := Vector3i(
		(CHUNK_SIZE - size.x) / 2,
		(CHUNK_SIZE - size.y) / 2,
		(CHUNK_SIZE - size.z) / 2)

	# Fill the box.
	var chunk := Chunk.new()
	for ly in range(origin.y, origin.y + size.y):
		for lx in range(origin.x, origin.x + size.x):
			for lz in range(origin.z, origin.z + size.z):
				chunk.blocks[Chunk.local_index(lx, ly, lz)] = id

	# Real mesh build path.
	var mesh := ChunkMesher.build_mesh(chunk, 0, 0, 0)
	if mesh == null:
		push_error("SingleBlockViewer: ChunkMesher returned null (no visible faces).")
		return

	var mi := MeshInstance3D.new()
	mi.name              = "BlockRegion"
	mi.mesh              = mesh
	mi.material_override = _make_material()
	add_child(mi)

	# Centre of the filled region, in world/block space.
	var center := Vector3(origin) + Vector3(size) * 0.5

	# Frame the whole region: pull back proportional to its largest dimension.
	var span := float(maxi(size.x, maxi(size.y, size.z)))
	_def_distance = span * 2.2 + 2.0
	_distance     = _def_distance
	max_zoom      = maxf(max_zoom, _def_distance * 1.5)

	_spawn_camera_rig(center)
	_spawn_light()

	print("SingleBlockViewer: rendered %d×%d×%d of '%s' (id %d, colour %s) at %s. " % [
		size.x, size.y, size.z, block_key, id, BlockRegistry.get_color(id), str(center)]
		+ "Left-drag to orbit, wheel to zoom, R to reset.")


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = clampf(_distance - zoom_speed, min_zoom, max_zoom)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = clampf(_distance + zoom_speed, min_zoom, max_zoom)
					_update_camera()

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw   -= mm.relative.x * orbit_speed
		_pitch  = clampf(_pitch + mm.relative.y * orbit_speed, -1.4, 1.4)
		_update_camera()

	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_R:
			_yaw = DEF_YAW
			_pitch = DEF_PITCH
			_distance = _def_distance
			_update_camera()


# ── Camera rig ────────────────────────────────────────────────────────────────

func _spawn_camera_rig(target: Vector3) -> void:
	_pivot = Node3D.new()
	_pivot.name     = "CameraPivot"
	_pivot.position = target
	add_child(_pivot)

	_camera = Camera3D.new()
	_camera.name    = "ViewerCamera"
	_camera.fov     = 45.0
	_camera.far     = 2000.0
	_camera.current = true
	_pivot.add_child(_camera)

	_update_camera()


## Positions the camera on a sphere around the pivot from yaw/pitch/distance,
## then aims it back at the region. Runs only after the camera is in the tree.
func _update_camera() -> void:
	if _camera == null:
		return
	# Spherical → cartesian, relative to the pivot (region centre).
	# Raising _pitch lifts the camera (positive Y); dragging changes yaw/pitch.
	var offset := Vector3(
		_distance * cos(_pitch) * sin(_yaw),
		_distance * sin(_pitch),
		_distance * cos(_pitch) * cos(_yaw))
	_camera.position = offset
	_camera.look_at(_pivot.global_position, Vector3.UP)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic  = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded \
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


func _spawn_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name             = "Sun"
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.shadow_enabled   = true
	add_child(sun)
