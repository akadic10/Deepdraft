extends Node

# Registry autoload for data-driven UI layout.
# Currently owns the floating bottom dock definition (data/ui/dock.json).
#
# Pattern mirrors BlockRegistry: this autoload is the SINGLE owner of UI-layout
# JSON I/O. No other script should call FileAccess on these files — query the
# public API below instead (Registry Pattern, see AGENT.md).
#
# Scope: dock LAYOUT only (order, emoji, label, action binding). Action *logic*
# lives in GDScript (the dock node's dispatch map), never in the data file
# (JSON = what things are, GDScript = what things do).

# ── File paths ────────────────────────────────────────────────────────────────
const DOCK_PATH := "res://data/ui/dock.json"

# ── Internal tables ───────────────────────────────────────────────────────────
# Ordered list of validated dock entries.
#   Separator entries: { "type": "separator" }
#   Button entries:    { id, emoji, label, tooltip, action, target }
# Keys with "__" prefix in the JSON are documentation comments and are ignored
# automatically (the loader only reads the top-level "items" array).
var _dock_items: Array = []

const _VALID_ACTIONS := ["open_panel", "toggle_window"]


func _ready() -> void:
	_load_dock()
	print("UIRegistry: loaded %d dock items." % _dock_items.size())


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_dock() -> void:
	_dock_items.clear()

	var file := FileAccess.open(DOCK_PATH, FileAccess.READ)
	if file == null:
		push_error("UIRegistry: cannot open %s (error %d)" % [DOCK_PATH, FileAccess.get_open_error()])
		return

	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("UIRegistry: JSON parse error in %s — %s" % [DOCK_PATH, json.get_error_message()])
		return

	var root: Dictionary = json.data
	var items: Array     = root.get("items", [])

	for entry in items:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = entry

		# Separators pass through untouched.
		if item.get("type", "") == "separator":
			_dock_items.append({ "type": "separator" })
			continue

		# Button entries must carry all required fields and a known action.
		if not _is_valid_button(item):
			push_warning("UIRegistry: skipping malformed dock item: %s" % str(item))
			continue

		_dock_items.append(item)


func _is_valid_button(item: Dictionary) -> bool:
	if not (item.has("id") and item.has("emoji") and item.has("label")):
		return false
	if not item.has("action") or not (item["action"] in _VALID_ACTIONS):
		return false
	if not item.has("target"):
		return false
	return true


# ── Public API ────────────────────────────────────────────────────────────────

## Returns the ordered list of dock entries (buttons + separators) in screen order.
## The returned array is the live internal list — treat it as read-only.
func get_dock_items() -> Array:
	return _dock_items


## Re-reads dock.json from disk. Useful for development / hot-tweaking the layout.
func reload() -> void:
	_load_dock()
