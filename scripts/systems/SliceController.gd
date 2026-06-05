class_name SliceController
extends Node

## The Slice tool (doc 11 Phase 2) — manual control of WorldRenderer.slice_y.
##
## After the Phase SO consolidation the renderer's sliced overview IS the slice
## view at every depth, so this controller has NO mode management: every path
## here simply writes `WorldRenderer.slice_y` and the renderer's setter does the
## localized invalidation. "Off" is slice_y = 127 — one code path (ref doc 10
## rule S1), so toggling off is just a plane move, never a special state.
##
## Responsibilities (ref doc 10 rules in parentheses):
##   - Stepping: cell ±4 and single ±1, snapped to cell tops (S2; Deepdraft cell
##     height = 4, NOT Stonehearth's 5).
##   - Clamps: slice_y in [4, 127]. Y4 keeps one mineable layer visible above
##     bedrock — the Bedrock Protocol stays inviolate. 127 = slice off.
##   - Seeding: first activation seeds from the camera's surface column (S3),
##     once per session (no save system yet — S4 persistence deferred).
##   - Hotkeys (H1): slice_toggle (\), slice_cell_up (]), slice_cell_down ([),
##     slice_single_up (Ctrl+]), slice_single_down (Ctrl+[) — registered in
##     project.godot [input] (ownership note: AGENT.md, approved 2026-06-05).
##   - Palette window (H2): cell/single steppers + live Y readout, in the Clock
##     window's visual language.
##   - Mutual exclusion (S7): the future X-Ray tool calls deactivate_if_active();
##     exclusion is enforced at the tool layer, never in the renderer.
##
## Scene wiring: @export paths (Scene Decoupling Contract). DockUI's `slice`
## dock entry routes its toggle here via register on _ready.

# ── Scene references (wire in Inspector) ─────────────────────────────────────

@export var renderer_path: NodePath
@export var camera_path: NodePath
@export var dock_ui_path: NodePath

# ── Constants ─────────────────────────────────────────────────────────────────

## Mining cell height. MUST match data/terrain/mining_config.json →
## dig_tool.y_cell_size (owned/loaded by MiningDesignationController — kept as a
## named constant here rather than a second raw reader of that file).
const CELL_HEIGHT: int = 4

## Floor clamp: Y4 = first mineable layer above the Y0–3 bedrock slab.
const MIN_SLICE_Y: int = 4

## Ceiling clamp = slice off (world top; identical output to the unsliced view).
const MAX_SLICE_Y: int = 127

# ── Signals ───────────────────────────────────────────────────────────────────

## Fired whenever the slice plane moves (active or not). UI readouts connect here.
signal slice_changed(new_slice_y: int)

## Fired when the tool turns on/off. DockUI uses it to refresh button state.
signal slice_active_changed(active: bool)

# ── State ─────────────────────────────────────────────────────────────────────

var _renderer: Node = null
var _camera_rig: Node3D = null
var _dock_ui: Node = null

var _active: bool = false
var _seeded: bool = false          # S3: seed exactly once per session
var _last_slice_y: int = MAX_SLICE_Y   # restored on re-activation

var _palette_layer: CanvasLayer
var _palette_panel: PanelContainer
var _readout_label: Label


func _ready() -> void:
	_renderer = get_node_or_null(renderer_path)
	_camera_rig = get_node_or_null(camera_path) as Node3D
	_dock_ui = get_node_or_null(dock_ui_path)
	_build_palette()

	if _renderer == null:
		push_warning("SliceController: renderer_path is not wired — slice tool inert.")
	if _dock_ui != null and _dock_ui.has_method("register_slice_controller"):
		_dock_ui.call("register_slice_controller", self)


func _unhandled_input(event: InputEvent) -> void:
	# exact_match = true so plain ] / [ (cell) never double-fire with Ctrl+] /
	# Ctrl+[ (single), and vice versa.
	if event.is_action_pressed(&"slice_toggle", false, true):
		toggle_active()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	if event.is_action_pressed(&"slice_cell_up", false, true):
		step_cell_up()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"slice_cell_down", false, true):
		step_cell_down()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"slice_single_up", false, true):
		step_single_up()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"slice_single_down", false, true):
		step_single_down()
		get_viewport().set_input_as_handled()


# ── Public API ────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _active


func get_slice_y() -> int:
	if _renderer == null:
		return MAX_SLICE_Y
	return int(_renderer.get("slice_y"))


func toggle_active() -> void:
	if _active:
		deactivate()
	else:
		activate()


## Turns the slice view on. First activation seeds the plane from the camera's
## surface column (S3); later activations restore the last manual height.
func activate() -> void:
	if _active or _renderer == null:
		return
	_active = true

	if not _seeded:
		var seed_y := _seed_from_camera()
		if seed_y >= 0:
			_seeded = true
			_last_slice_y = seed_y
		# Maps not ready yet (seed_y < 0): keep _seeded false so the next
		# activation retries; fall through with the previous value (127 = no
		# visible cut, harmless).

	_set_slice_y(_last_slice_y)
	_palette_layer.visible = true
	slice_active_changed.emit(true)


## Turns the slice view off: the plane returns to the world top (S1 — "off" is
## just a plane move; visibility-level cost, no special rebuild path).
func deactivate() -> void:
	if not _active:
		return
	_active = false
	_last_slice_y = get_slice_y()
	_set_slice_y(MAX_SLICE_Y)
	_palette_layer.visible = false
	slice_active_changed.emit(false)


## Mutual exclusion hook (S7): the future X-Ray tool calls this before
## activating itself. Exclusion lives at the tool layer, not the renderer.
func deactivate_if_active() -> void:
	deactivate()


# ── Stepping (S2 — cell = 4; cell tops are n*4 - 1: Y7, Y11, … Y127) ──────────

func step_cell_up() -> void:
	var y := get_slice_y()
	_set_slice_y(y - ((y + 1) % CELL_HEIGHT) + CELL_HEIGHT)


func step_cell_down() -> void:
	var y := get_slice_y()
	var delta := (y + 1) % CELL_HEIGHT
	if delta == 0:
		delta = CELL_HEIGHT
	_set_slice_y(y - delta)


func step_single_up() -> void:
	_set_slice_y(get_slice_y() + 1)


func step_single_down() -> void:
	_set_slice_y(get_slice_y() - 1)


# ── Internals ─────────────────────────────────────────────────────────────────

func _set_slice_y(value: int) -> void:
	if _renderer == null:
		return
	var clamped := clampi(value, MIN_SLICE_Y, MAX_SLICE_Y)
	if clamped != get_slice_y():
		_renderer.set("slice_y", clamped)   # setter runs the localized invalidation
	_update_readout()
	slice_changed.emit(clamped)


## S3 seeding: cell top of the camera's surface column — the same math as
## Stonehearth's embark seed (quantize to the cell, minus the ceiling):
##   cell_top(y) = floor(y / 4) * 4 + 3
## Returns -1 while the generator maps are not ready.
func _seed_from_camera() -> int:
	if _camera_rig == null or not WorldGenerator.has_method("get_visible_surface_y"):
		return -1
	var wx := clampi(floori(_camera_rig.global_position.x), 0, WorldGenerator.WORLD_SIZE_X - 1)
	var wz := clampi(floori(_camera_rig.global_position.z), 0, WorldGenerator.WORLD_SIZE_Z - 1)
	var surface_y := int(WorldGenerator.get_visible_surface_y(wx, wz))
	if surface_y < 0:
		return -1
	@warning_ignore("integer_division")
	var cell_top := (surface_y / CELL_HEIGHT) * CELL_HEIGHT + CELL_HEIGHT - 1
	return clampi(cell_top, MIN_SLICE_Y, MAX_SLICE_Y)


# ── Palette window (H2 — Clock-window visual language) ───────────────────────

func _build_palette() -> void:
	_palette_layer = CanvasLayer.new()
	_palette_layer.name = "SlicePalette"
	_palette_layer.layer = 22
	_palette_layer.visible = false
	add_child(_palette_layer)

	_palette_panel = PanelContainer.new()
	_palette_panel.name = "Panel"
	_palette_panel.position = Vector2(18.0, 130.0)
	_palette_panel.custom_minimum_size = Vector2(150.0, 0.0)
	_palette_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.070, 0.075, 0.94), Color(1, 1, 1, 0.12), 8))
	_palette_layer.add_child(_palette_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_palette_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "Slice"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(30.0, 26.0)
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Turn slice off"
	close.pressed.connect(deactivate)
	header.add_child(close)

	column.add_child(_make_step_button("▲▲  Cell up", "Raise the slice one 4-block cell  ( ] )", step_cell_up))
	column.add_child(_make_step_button("▲  Block up", "Raise the slice one block  (Ctrl+])", step_single_up))

	_readout_label = Label.new()
	_readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout_label.add_theme_font_size_override("font_size", 17)
	column.add_child(_readout_label)

	column.add_child(_make_step_button("▼  Block down", "Lower the slice one block  (Ctrl+[)", step_single_down))
	column.add_child(_make_step_button("▼▼  Cell down", "Lower the slice one 4-block cell  ( [ )", step_cell_down))

	_update_readout()


func _make_step_button(text: String, tooltip: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(126.0, 30.0)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal",  _style(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 1, 6))
	button.add_theme_stylebox_override("hover",   _style(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.22), 1, 6))
	button.add_theme_stylebox_override("pressed", _style(Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.28), 1, 6))
	button.pressed.connect(on_press)
	return button


func _update_readout() -> void:
	if _readout_label == null:
		return
	var y := get_slice_y()
	_readout_label.text = "Y = %d" % y if y < MAX_SLICE_Y else "Off"


func _style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	return _style(bg, border, 1, radius)
