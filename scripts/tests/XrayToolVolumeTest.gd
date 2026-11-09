extends SceneTree

## X-ray behind a click tool (doc 24; the project review, 2026-11-09). With X-ray on and a tool
## active, X-ray stands aside and the normal view shows. A dwarf mining then changes the
## interiors, but the normal view's water and damp ground must not hear that the visible volume
## changed: each such change hid and re-meshed all of them, so both blinked while dwarves mined.
## While X-ray inspects, the same change still marks the volume, and leaving the tool marks it once.
## godot --headless --path . --script res://scripts/tests/XrayToolVolumeTest.gd

## Stands in for WorldRenderer: counts what X-ray tells it.
class Renderer extends Node3D:
	var marks := 0
	var slice_y := 40
	var underground_view: Node
	func mark_visible_volume_dirty() -> void: marks += 1

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _run() -> void:
	for id: String in ["SaveManager", "TaskManager", "RoomManager", "WaterManager"]: root.get_node(id).set_process(false)
	var xray = load("res://scripts/systems/XrayController.gd").new()
	root.add_child(xray)
	xray.set_process(false)
	await process_frame
	var renderer := Renderer.new()
	root.add_child(renderer)
	xray.renderer = renderer
	xray.mode = "full"
	var interiors := root.get_node("InteriorTracker")
	xray.working = true   # a click tool is on: X-ray stands aside
	interiors.revision += 1   # a dwarf mined
	xray._refresh_interiors()
	_expect(renderer.marks == 0, "behind a tool, a mined interior leaves the normal view's water and damp ground alone: %d marks" % renderer.marks)
	xray.working = false   # the tool is put away: X-ray inspects again
	interiors.revision += 1
	xray._refresh_interiors()
	_expect(renderer.marks == 1, "while X-ray inspects, a mined interior marks the volume: %d marks" % renderer.marks)
	for failure: String in failures: push_error(failure)
	print("XRAY_TOOL_VOLUME_OK" if failures.is_empty() else "XRAY_TOOL_VOLUME_FAIL")
	quit(0 if failures.is_empty() else 1)
