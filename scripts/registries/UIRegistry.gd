extends Node

# Registry autoload for data-driven UI layout.
# Owns dock/menu layout, icon family tiles, world order markers, the compact panel's
# action pictures, Place captions/order, Inventory categories, roster filters,
# Colony's page rows, Settings' key list, the title screen and the DEV item stamper.
#
# Pattern mirrors BlockRegistry: this autoload is the SINGLE owner of UI-layout
# JSON I/O. No other script should call FileAccess on these files — query the
# public API below instead (Registry Pattern, see CLAUDE.md).
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
var _storage_groups: Array[Dictionary] = []
var _sky_dial: Dictionary = {}
var _settlement_page: Dictionary = {}
var _time_slice: Dictionary = {}
var _controls: Dictionary = {}
var _title_screen: Dictionary = {}
var _item_stamper: Dictionary = {}
var _tool_bar: Dictionary = {}
var _loading_screen: Dictionary = {}
var _dwarf_indicators: Dictionary = {}
var _need_icons: Dictionary = {}
const DEV_TOOLS_PATH := "res://data/ui/dev_tools.json"
const ICON_FAMILIES_PATH := "res://data/ui/icon_families.json"
var _icon_families: Dictionary = {}
const ORDER_MARKERS_PATH := "res://data/ui/order_markers.json"
var _order_markers: Dictionary = {}
var _order_marker_tile := Color.TRANSPARENT
const COMPACT_PANEL_PATH := "res://data/ui/compact_panel.json"
var _compact_panel: Dictionary = {}
const JsonData = preload("res://scripts/registries/JsonData.gd")
## The development tools switch (data/ui/dev_tools.json), read once at startup.
## Off hides the Development menu, its windows and every "dev" variant action.
var dev_tools_enabled := false

# ── Internal tables ───────────────────────────────────────────────────────────
# Ordered list of validated navigation buttons.
#   Button entries: { id, icon, label, tooltip, action, target }
# Keys with "__" prefix in the JSON are documentation comments and are ignored
# automatically (the loader only reads "items" and "menus").
var _dock_items: Array = []
var _menus: Dictionary = {}
var _room_symbols: Dictionary = {}

const _VALID_ACTIONS := ["open_panel", "toggle_window", "activate_tool", "panel_action", "open_crafting", "game_menu"]


func _ready() -> void:
	_load_dev_tools()
	_load_icon_families()
	_load_order_markers()
	_load_compact_panel()
	_load_dock()
	_load_place_catalog()
	_load_inventory_catalog()
	_load_roster_filters()
	_load_storage_categories()
	_load_sky_dial()
	_load_settlement_page()
	_load_time_slice()
	_load_controls()
	_load_title_screen()
	_load_item_stamper()
	_load_tool_bar()
	_load_loading_screen()
	_load_dwarf_indicators()
	print("UIRegistry: loaded %d dock items." % _dock_items.size())


func _load_dev_tools() -> void:
	var parsed: Variant = JsonData.read(DEV_TOOLS_PATH)
	if not parsed is Dictionary or not parsed.get("enabled") is bool:
		push_error("UIRegistry: %s needs a boolean \"enabled\"; development tools stay off." % DEV_TOOLS_PATH)
		dev_tools_enabled = false
		return
	dev_tools_enabled = parsed.enabled


## Dock buttons and menu entries marked "dev": true exist only with the switch on.
func is_shown(entry: Dictionary) -> bool:
	return dev_tools_enabled or not bool(entry.get("dev", false))


## Object-window actions without the "dev" variant ones while the switch is off.
func shown_actions(actions: Array) -> Array:
	if dev_tools_enabled: return actions
	return actions.filter(func(action: Dictionary) -> bool: return String(action.get("variant", "")) != "dev")


func _load_loading_screen() -> void:
	var parsed: Variant = JsonData.read("res://data/ui/loading_screen.json")
	if parsed == null: return
	if not parsed.get("backgrounds") is Array or parsed.backgrounds.is_empty():
		push_error("UIRegistry: loading screen needs a nonempty backgrounds list")
		return
	for path in parsed.backgrounds:
		if not path is String or path.is_empty():
			push_error("UIRegistry: loading screen background paths must be nonempty strings")
			return
	_loading_screen = parsed


func get_loading_screen() -> Dictionary:
	return _loading_screen


func _load_icon_families() -> void:
	_icon_families.clear()
	var families: Variant = JsonData.read_dict(ICON_FAMILIES_PATH).get("families", {})
	if not families is Dictionary:
		push_error("UIRegistry: icon families must be an object.")
		return
	for family: String in families:
		_icon_families[family] = Color(String(families[family].get("tile", "")))


## Tile colour for a Hearthblock icon family (doc 259); transparent when unknown.
func get_icon_family_color(family: String) -> Color:
	if not _icon_families.has(family):
		push_warning("UIRegistry: unknown icon family '%s'." % family)
		return Color.TRANSPARENT
	return _icon_families[family]


func _load_order_markers() -> void:
	_order_markers.clear()
	var parsed := JsonData.read_dict(ORDER_MARKERS_PATH)
	var markers: Variant = parsed.get("markers", {})
	if not markers is Dictionary:
		push_error("UIRegistry: order markers must be an object.")
		return
	for kind: String in markers:
		_order_markers[kind] = load(String(markers[kind])) as Texture2D
	_order_marker_tile = get_icon_family_color(String(parsed.get("family", "")))


## The picture for a world order marker (doc 259): fell, harvest, clear_stones,
## clear_plants or uproot. Null for an unknown kind.
func get_order_marker(kind: String) -> Texture2D:
	return _order_markers.get(kind)


## The tile colour behind every world order marker.
func get_order_marker_tile() -> Color:
	return _order_marker_tile


func _load_compact_panel() -> void:
	var parsed := JsonData.read_dict(COMPACT_PANEL_PATH)
	_compact_panel = {"family": String(parsed.get("family", "")), "dev_family": String(parsed.get("dev_family", "")),
		"dev_icon": load(String(parsed.get("dev_icon", ""))) as Texture2D, "actions": {}, "badges": {}}
	var actions: Variant = parsed.get("actions", {})
	var badges: Variant = parsed.get("badges", {})
	if not actions is Dictionary or not badges is Dictionary:
		push_error("UIRegistry: compact panel actions and badges must be objects.")
		return
	for id: String in actions:
		_compact_panel.actions[id] = {"icon": load(String(actions[id].get("icon", ""))) as Texture2D,
			"tooltip": String(actions[id].get("tooltip", ""))}
	for kind: String in badges:
		_compact_panel.badges[kind] = load(String(badges[kind])) as Texture2D


## The compact object panel's picture and hover text for a provider action id (doc 260):
## {icon, tooltip}, or empty when the id has no entry.
func get_compact_action(id: String) -> Dictionary:
	return _compact_panel.get("actions", {}).get(id, {})


## The picture in the compact panel's badge for a kind (appeal, quantity); null if unknown.
func get_compact_badge(kind: String) -> Texture2D:
	return _compact_panel.get("badges", {}).get(kind)


## The icon family of the compact panel's action tiles, or of its DEV tiles.
func get_compact_family(dev: bool = false) -> String:
	return String(_compact_panel.get("dev_family" if dev else "family", ""))


## The picture on every DEV action tile.
func get_compact_dev_icon() -> Texture2D:
	return _compact_panel.get("dev_icon")


func _load_dwarf_indicators() -> void:
	var parsed: Variant = JsonData.read("res://data/ui/dwarf_indicators.json")
	if parsed == null: return
	if not parsed.get("icons") is Dictionary:
		push_error("UIRegistry: invalid dwarf indicator definition")
		return
	_dwarf_indicators = parsed
	for kind: String in ["food","rest","mood"]:
		_need_icons[kind] = load(String(parsed.icons[kind])) as Texture2D


func get_dwarf_indicators() -> Dictionary:
	return _dwarf_indicators


func get_need_icon(kind: String) -> Texture2D:
	return _need_icons.get(kind)


# ── Loaders ───────────────────────────────────────────────────────────────────

func _load_dock() -> void:
	_dock_items.clear()
	_menus.clear()
	_room_symbols.clear()

	var parsed: Variant = JsonData.read(DOCK_PATH)
	if parsed == null: return
	var root: Dictionary = parsed
	if root.get("room_symbols", {}) is Dictionary:
		_room_symbols = root.get("room_symbols", {})
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
			"parent": String(menu.get("parent", "")), "items": entries,
			"illustrated": bool(menu.get("illustrated", false)), "dev": bool(menu.get("dev", false)),
			"dock_anchor": String(menu.get("dock_anchor", "")),
			"columns": maxi(1, int(menu.get("columns", entries.size()))),
			"compact_columns": maxi(1, int(menu.get("compact_columns", entries.size())))}


func _is_valid_button(item: Dictionary) -> bool:
	for field in ["id", "label", "action", "target"]:
		if not item.get(field) is String or String(item[field]).is_empty():
			return false
	return item.action in _VALID_ACTIONS


# ── Public API ────────────────────────────────────────────────────────────────

## Returns the navigation buttons in screen order, without hidden DEV entries.
func get_dock_items() -> Array:
	return _dock_items.filter(is_shown)


## Atlas regions retain the approved illustrated art without baking captions or
## selection states into individual buttons. Also accepts ordinary icon files.
func get_dock_icon(entry: Dictionary) -> Texture2D:
	if String(entry.get("icon", "")).is_empty(): return null
	var texture := load(String(entry.get("icon", ""))) as Texture2D
	var region: Array = entry.get("icon_region", [])
	if texture == null or region.size() != 4: return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	atlas.filter_clip = true
	return atlas


## Read-only command-group metadata; behavior remains with DockUI.
func get_menu(target: String) -> Dictionary:
	var menu: Dictionary = _menus.get(target, {})
	if menu.is_empty() or dev_tools_enabled: return menu
	if menu.dev: return {}
	var shown := menu.duplicate()
	shown.items = menu.items.filter(is_shown)
	return shown


func get_room_symbol(id: String) -> Texture2D:
	return get_dock_icon(_room_symbols.get(id, {}))


func get_sky_dial() -> Dictionary:
	return _sky_dial


func get_time_slice() -> Dictionary:
	return _time_slice


func _load_time_slice() -> void:
	_time_slice.clear()
	_time_slice = JsonData.read_dict("res://data/ui/time_slice.json")


## Settings' key list (doc 23 "Keys"): two columns of groups, each entry what the player
## does with its input actions or fixed keys.
func get_controls() -> Dictionary:
	return _controls


func _load_controls() -> void:
	_controls = JsonData.read_dict("res://data/ui/controls.json")
	for column: Array in _controls.get("columns", []):
		for group: Dictionary in column:
			for entry: Dictionary in group.get("entries", []):
				for action: String in entry.get("actions", []):
					if not InputMap.has_action(action):
						push_warning("UIRegistry: the key list names '%s', which is not an input action." % action)


## The title screen (doc 23): its art, the game's name and the line under it.
func get_title_screen() -> Dictionary:
	return _title_screen


func _load_title_screen() -> void:
	_title_screen = JsonData.read_dict("res://data/ui/title_screen.json")


## The DEV item stamper (doc 23): its groups of items, the amounts it jumps to, and how
## many recent items it keeps.
func get_item_stamper() -> Dictionary:
	return _item_stamper


func _load_item_stamper() -> void:
	_item_stamper = JsonData.read_dict("res://data/ui/item_stamper.json")


## The tool bar (doc 23): the keys each tool shows under its name.
func get_tool_bar() -> Dictionary:
	return _tool_bar


func _load_tool_bar() -> void:
	_tool_bar = JsonData.read_dict("res://data/ui/tool_bar.json")


## The dock's entry whose target is a tool (doc 23, "The tool bar"): its name, picture and
## family for the bar. {} when the dock has none: Place, Move and the stamper name themselves.
func get_tool_entry(tool_id: String) -> Dictionary:
	for entry: Dictionary in _dock_items:
		if String(entry.get("target", "")) == tool_id: return entry
	for menu: Dictionary in _menus.values():
		for entry: Dictionary in menu.get("items", []):
			if String(entry.get("target", "")) == tool_id: return entry
	return {}


func _load_sky_dial() -> void:
	_sky_dial.clear()
	_sky_dial = JsonData.read_dict("res://data/ui/sky_dial.json")


## Colony's page (doc 23): each row's picture, and the goals its meter fills toward.
func get_settlement_page() -> Dictionary:
	return _settlement_page


func _load_settlement_page() -> void:
	_settlement_page = JsonData.read_dict("res://data/ui/settlement_page.json")


## Re-reads the UI layout files. Useful for development / hot-tweaking the layout.
func reload() -> void:
	_load_dev_tools()
	_load_icon_families()
	_load_order_markers()
	_load_compact_panel()
	_load_dock()
	_load_place_catalog()
	_load_inventory_catalog()
	_load_roster_filters()
	_load_storage_categories()
	_load_sky_dial()
	_load_settlement_page()
	_load_time_slice()
	_load_controls()
	_load_title_screen()
	_load_item_stamper()


## The storage filter's categories: tag, label, group and picture (doc 261).
func get_storage_categories() -> Array[Dictionary]:
	return _storage_categories


## The storage filter's groups, in order: id and label (doc 261).
func get_storage_groups() -> Array[Dictionary]:
	return _storage_groups


func _load_storage_categories() -> void:
	_storage_categories.clear()
	_storage_groups.clear()
	var parsed: Variant = JsonData.read("res://data/ui/storage_filters.json")
	if parsed == null: return
	if not parsed.get("categories") is Array or not parsed.get("groups") is Array:
		push_error("UIRegistry: malformed storage filter groups or categories")
		return
	var group_ids := {}
	for entry in parsed.groups:
		if entry is Dictionary and entry.get("id") is String and entry.get("label") is String:
			_storage_groups.append(entry)
			group_ids[entry.id] = true
	for entry in parsed.categories:
		if entry is Dictionary and entry.get("tag") is String and entry.get("label") is String \
				and group_ids.has(entry.get("group")) and entry.get("picture") is String:
			_storage_categories.append(entry)
		else:
			push_error("UIRegistry: storage category needs a tag, label, known group and picture: %s" % str(entry))


func get_roster_filters() -> Array[Dictionary]:
	return _roster_filters


func _load_roster_filters() -> void:
	_roster_filters.clear()
	var parsed: Variant = JsonData.read(ROSTER_PATH)
	if parsed == null: return
	if not parsed.get("filters") is Array:
		push_error("UIRegistry: malformed dwarf roster filters")
		return
	for entry in parsed.filters:
		if entry is Dictionary and entry.get("id") in ["all", "working", "resting", "idle"] and entry.get("label") is String:
			_roster_filters.append(entry)


func get_inventory_catalog() -> Dictionary:
	return _inventory_catalog


func _load_inventory_catalog() -> void:
	_inventory_catalog = {"categories": [], "furniture_categories": {}}
	var parsed: Variant = JsonData.read(INVENTORY_PATH)
	if parsed == null: return
	if not parsed.get("categories") is Array:
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
	var parsed: Variant = JsonData.read(PLACE_PATH)
	if parsed == null: return
	if not parsed.get("categories") is Array or not parsed.get("items") is Array:
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
