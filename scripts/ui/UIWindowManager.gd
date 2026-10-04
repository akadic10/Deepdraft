class_name UIWindowManager
extends CanvasLayer

## One CanvasLayer hosting every UIWindow (doc 24, Phase U1).
##
## Owns everything that is chrome-and-behaviour rather than content: z-order
## (last-clicked wins), placement (remembered position → default → cascade),
## open/close/toggle bookkeeping, and layout persistence. Content stays with
## the registering system (Scene Decoupling Contract) — controllers build a
## plain Control, register it, and keep their reference to update labels.
##
## Layer plan (doc 24 §3): dock 20, ALL windows here at 22, mouse-ignoring
## HUD callouts 24.
##
## Persistence: `user://ui_layout.json`, this class is the SINGLE owner of that
## file (Registry-Pattern discipline applied to user data — no other script may
## read or write it). Window layout is a player preference, so it lives outside
## the save file and survives every save/load/new game (Alen, 2026-08-20).
##
## New `class_name` — after pulling this change, run Project → Reload Current
## Project once.

## Emitted whenever any window opens or closes. DockUI's pressed-state refresh
## hangs off this one signal — the per-window special cases are gone.
signal window_state_changed(id: String, open: bool)

const LAYOUT_PATH := "user://ui_layout.json"
const LAYOUT_SCHEMA_VERSION := 1

## First-open placement when no remembered or default position exists —
## the classic DockUI cascade, kept.
const CASCADE_START := Vector2(32.0, 130.0)
const CASCADE_STEP := Vector2(28.0, 28.0)
const CASCADE_WRAP := 5

var _windows: Dictionary = {}   # id: String -> UIWindow
var _layout: Dictionary = {}    # id: String -> { "x": float, "y": float, "open": bool }
var _cascade_index: int = 0
var _layout_loaded: bool = false


func _enter_tree() -> void:
	layer = 22


func _ready() -> void:
	_load_layout()
	get_viewport().size_changed.connect(_on_viewport_resized)
	print("UIWindowManager: ready (%d remembered window positions)." % _layout.size())


# ── Registration ──────────────────────────────────────────────────────────────

## Registers a window and returns it (owners keep the reference for title and
## content updates). The window starts hidden; a persistent window whose
## remembered state is open reopens on the next idle frame.
##
## opts:
##   "persistent":  bool     — restorable open state at startup (default false)
##   "default_pos": Vector2  — first-ever position (else cascade)
##   "min_size":    Vector2  — content minimum size
func register_window(id: String, title: String, emoji: String,
		content: Control, opts: Dictionary = {}) -> UIWindow:
	if _windows.has(id):
		push_warning("UIWindowManager: '%s' registered twice — keeping the first." % id)
		return _windows[id] as UIWindow

	var window := UIWindow.new()
	window.window_id = id
	window.persistent = bool(opts.get("persistent", false))
	window.set_window_title(title, emoji)
	window.visible = false
	if opts.has("min_size"):
		window.custom_minimum_size = opts.get("min_size", Vector2.ZERO)
	add_child(window)
	window.set_content(content)
	_windows[id] = window

	window.position = _initial_position_for(id, opts)
	window.focus_requested.connect(_on_focus_requested)
	window.close_pressed.connect(_on_close_pressed)
	window.drag_ended.connect(_on_drag_ended)

	if window.persistent and _remembered_open(id):
		# Deferred: let the owner finish its own _ready before content shows.
		call_deferred("open", id)
	return window


func has_window(id: String) -> bool:
	return _windows.has(id)


## NOT get_window(): that name is Node's native get_window() -> Window, and
## overriding a native method is a warning-treated-as-error in this project.
func get_ui_window(id: String) -> UIWindow:
	return _windows.get(id, null) as UIWindow


# ── Open / close / toggle ─────────────────────────────────────────────────────

func is_open(id: String) -> bool:
	var window := get_ui_window(id)
	return window != null and window.visible


func open(id: String) -> void:
	var window := get_ui_window(id)
	if window == null:
		push_warning("UIWindowManager: open('%s') — no such window registered." % id)
		return
	if window.visible:
		_raise(window)
		return
	window.visible = true
	window.clamp_to_viewport()
	_raise(window)
	_record_state(id)
	window_state_changed.emit(id, true)


func close(id: String) -> void:
	var window := get_ui_window(id)
	if window == null or not window.visible:
		return
	window.visible = false
	_record_state(id)
	window_state_changed.emit(id, false)


func toggle(id: String) -> void:
	if is_open(id):
		close(id)
	else:
		open(id)


# ── Window signal handlers ────────────────────────────────────────────────────

func _on_focus_requested(window: UIWindow) -> void:
	_raise(window)


func _on_close_pressed(window: UIWindow) -> void:
	close(window.window_id)


func _on_drag_ended(window: UIWindow) -> void:
	_record_state(window.window_id)


func _raise(window: UIWindow) -> void:
	move_child(window, get_child_count() - 1)


func _on_viewport_resized() -> void:
	for id: String in _windows:
		var window := _windows[id] as UIWindow
		if window.visible:
			window.clamp_to_viewport()


# ── Placement ─────────────────────────────────────────────────────────────────

func _initial_position_for(id: String, opts: Dictionary) -> Vector2:
	var entry: Dictionary = _layout.get(id, {})
	if entry.has("x") and entry.has("y"):
		return Vector2(float(entry["x"]), float(entry["y"]))
	if opts.has("default_pos"):
		return opts.get("default_pos", CASCADE_START)
	var pos := CASCADE_START + CASCADE_STEP * float(_cascade_index)
	_cascade_index = (_cascade_index + 1) % CASCADE_WRAP
	return pos


func _remembered_open(id: String) -> bool:
	var entry: Dictionary = _layout.get(id, {})
	return bool(entry.get("open", false))


# ── Layout persistence (single owner of user://ui_layout.json) ────────────────

func _record_state(id: String) -> void:
	var window := get_ui_window(id)
	if window == null:
		return
	var entry: Dictionary = _layout.get(id, {})
	entry["x"] = window.position.x
	entry["y"] = window.position.y
	# Only persistent windows restore "open"; storing it for all is harmless
	# and keeps the writer branch-free (the reader filters, doc 24 §2).
	entry["open"] = window.visible
	_layout[id] = entry
	_save_layout()


func _load_layout() -> void:
	_layout_loaded = true
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_warning("UIWindowManager: cannot open %s — using default layout." % LAYOUT_PATH)
		return
	var json := JSON.new()
	var parse_err := json.parse(file.get_as_text())
	file.close()
	if parse_err != OK or not (json.data is Dictionary):
		push_warning("UIWindowManager: %s is corrupt — using default layout." % LAYOUT_PATH)
		return
	var root: Dictionary = json.data
	var windows_variant: Variant = root.get("windows", {})
	if not (windows_variant is Dictionary):
		push_warning("UIWindowManager: %s has no valid windows table — using defaults." % LAYOUT_PATH)
		return
	var windows: Dictionary = windows_variant
	for id_variant: Variant in windows.keys():
		var id := String(id_variant)
		var entry_variant: Variant = windows[id_variant]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var clean: Dictionary = {}
		if entry.has("x") and entry.has("y"):
			clean["x"] = float(entry["x"])
			clean["y"] = float(entry["y"])
		clean["open"] = bool(entry.get("open", false))
		_layout[id] = clean


func _save_layout() -> void:
	if not _layout_loaded:
		return   # never clobber the file before it has been read
	var root: Dictionary = {
		"schema_version": LAYOUT_SCHEMA_VERSION,
		"windows": _layout,
	}
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("UIWindowManager: cannot write %s (error %d)." % [
			LAYOUT_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(root, "  "))
	file.close()
