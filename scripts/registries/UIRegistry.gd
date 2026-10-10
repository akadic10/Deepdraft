extends Node

# Registry autoload for data-driven UI layout.
# Owns dock/menu layout, Place captions/order, Inventory categories and roster filters.
#
# Pattern mirrors BlockRegistry: this autoload is the SINGLE owner of UI-layout
# JSON I/O. No other script should call FileAccess on these files — query the
# public API below instead (Registry Pattern, see AGENT.md).
#
# Scope: dock and menu LAYOUT only (order, icon, label, action binding). Action *logic*
# lives in GDScript (the dock node's dispatch map), never in the data file
# (JSON = what things are, GDScript = what things do).

# ── File paths ────────────────────────────────────────────────────────────────
const DOCK_PATH := "res://data/ui/dock.json"
const PLACE_PATH := "res://data/ui/place_catalog.json"
var _place_catalog: Dictionary = {}
const INVENTORY_PATH := "res://data/ui/inventory_catalog.json"
var _inventory_catalog: Dictionary = {}
const ROSTER_PATH := "res://data/ui/dwarf_roster.json"
var _roster_filters: Array[Dictionary] = []
var _storage_categories: Array[Dictionary] = []

# ── Internal tables ───────────────────────────────────────────────────────────
# Ordered list of validated navigation buttons.
#   Button entries: { id, icon, label, tooltip, action, target }
# Keys with "__" prefix in the JSON are documentation comments and are ignored
# automatically (the loader only reads "items" and "menus").
var _dock_items: Array = []
var _menus: Dictionary = {}

const _VALID_ACTIONS := ["open_panel", "toggle_window", "activate_tool", "panel_action", "open_crafting"]


func _ready() -> void:
	_load_dock()
	_load_place_catalog()
	_load_inventory_catalog()
	_load_roster_filters()
	_load_storage_categories()
	print("UIRegistry: loaded %d dock items." % _dock_items.size())


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_dock() -> void:
	_dock_items.clear()
	_menus.clear()

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

	if not json.data is Dictionary:
		push_error("UIRegistry: dock layout must be a JSON object.")
		return
	var root: Dictionary = json.data
	if not root.get("items", []) is Array or not root.get("menus", {}) is Dictionary:
		push_error("UIRegistry: dock items must be an array and menus an object.")
		return
	var items: Array = root.get("items", [])

	for entry in items:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = entry

		# Button entries must carry all required fields and a known action.
		if not _is_valid_button(item):
			push_warning("UIRegistry: skipping malformed dock item: %s" % str(item))
			continue

		_dock_items.append(item)

	for key: String in root.get("menus", {}):
		if not root.menus[key] is Dictionary:
			push_warning("UIRegistry: skipping malformed menu: %s." % key)
			continue
		var menu: Dictionary = root.menus[key]
		if not menu.get("items", []) is Array:
			push_warning("UIRegistry: skipping malformed menu items: %s." % key)
			continue
		var entries: Array = []
		for entry in menu.get("items", []):
			if entry is Dictionary and _is_valid_button(entry):
				entries.append(entry)
			else:
				push_warning("UIRegistry: skipping malformed command in %s." % key)
		_menus[key] = {"title": String(menu.get("title", key.capitalize())),
			"parent": String(menu.get("parent", "")), "items": entries}


func _is_valid_button(item: Dictionary) -> bool:
	for field in ["id", "label", "action", "target"]:
		if not item.get(field) is String or String(item[field]).is_empty():
			return false
	return item.action in _VALID_ACTIONS


# ── Public API ────────────────────────────────────────────────────────────────

## Returns the ordered list of navigation buttons in screen order.
## The returned array is the live internal list — treat it as read-only.
func get_dock_items() -> Array:
	return _dock_items


## Read-only command-group metadata; behavior remains with DockUI.
func get_menu(target: String) -> Dictionary:
	return _menus.get(target, {})


## Re-reads the UI layout files. Useful for development / hot-tweaking the layout.
func reload() -> void:
	_load_dock()
	_load_place_catalog()
	_load_inventory_catalog()
	_load_roster_filters()
	_load_storage_categories()


func get_storage_categories() -> Array[Dictionary]:
	return _storage_categories


func _load_storage_categories() -> void:
	_storage_categories.clear()
	var file := FileAccess.open("res://data/ui/storage_filters.json", FileAccess.READ)
	if file == null:
		push_error("UIRegistry: missing storage filter categories")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("categories") is Array:
		push_error("UIRegistry: malformed storage filter categories")
		return
	for entry in parsed.categories:
		if entry is Dictionary and entry.get("tag") is String and entry.get("label") is String:
			_storage_categories.append(entry)


func get_roster_filters() -> Array[Dictionary]:
	return _roster_filters


func _load_roster_filters() -> void:
	_roster_filters.clear()
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if file == null:
		push_error("UIRegistry: missing dwarf roster filters")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("filters") is Array:
		push_error("UIRegistry: malformed dwarf roster filters")
		return
	for entry in parsed.filters:
		if entry is Dictionary and entry.get("id") in ["all", "working", "resting", "idle"] and entry.get("label") is String:
			_roster_filters.append(entry)


func get_inventory_catalog() -> Dictionary:
	return _inventory_catalog


func _load_inventory_catalog() -> void:
	_inventory_catalog = {"categories": [], "furniture_categories": {}}
	var file := FileAccess.open(INVENTORY_PATH, FileAccess.READ)
	if file == null:
		push_error("UIRegistry: missing Inventory catalog")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("categories") is Array:
		push_error("UIRegistry: malformed Inventory catalog")
		return
	for entry in parsed.categories:
		if entry is Dictionary and entry.get("id") is String and entry.get("label") is String:
			_inventory_catalog.categories.append(entry)
	if parsed.get("furniture_categories") is Dictionary:
		_inventory_catalog.furniture_categories = parsed.furniture_categories


func get_place_catalog() -> Dictionary:
	return _place_catalog


func _load_place_catalog() -> void:
	_place_catalog = {"categories": [], "items": []}
	var file := FileAccess.open(PLACE_PATH, FileAccess.READ)
	if file == null:
		push_error("UIRegistry: missing Place catalog")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("categories") is Array or not parsed.get("items") is Array:
		push_error("UIRegistry: malformed Place catalog")
		return
	var categories: Array[String] = []
	for entry in parsed.categories:
		if entry is Dictionary and entry.get("id") is String and entry.get("label") is String:
			categories.append(entry.id)
			_place_catalog.categories.append(entry)
	var keys: Array[String] = []
	for entry in parsed.items:
		if entry is Dictionary and entry.get("key") is String and entry.get("label") is String \
				and entry.get("category") in categories and not entry.key in keys:
			keys.append(entry.key)
			_place_catalog.items.append(entry)
