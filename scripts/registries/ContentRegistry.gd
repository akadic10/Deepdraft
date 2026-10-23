extends Node

## Sole loader for the static content saves name: furniture pieces (with
## SurfaceDetailRegistry's plant place entries merged in), items, worker
## recipes and tree species. It exists before any scene so startup resume can
## reject saves naming content the game no longer defines. Scene systems read
## definitions here and keep their own runtime state. Never mutate the returned
## dictionaries.
const FURNITURE_DIR := "res://data/furniture"
const ITEMS_PATH := "res://data/entities/items/resources.json"
const RECIPES_PATH := "res://data/workshops/worker_crafting.json"
const JsonData = preload("res://scripts/registries/JsonData.gd")

var furniture: Dictionary = {}       # furniture_key -> placeable definition
var items: Dictionary = {}           # item key -> definition
var recipes: Dictionary = {}         # recipe id -> worker recipe
var recipe_sections: Dictionary = {} # section id -> crafting menu section
var max_craft_orders := 64
var trees: Dictionary = {}           # species key -> definition with placement and stages


## Loads at construction, not _ready: the main scene is built (member
## initializers that copy these tables included) before any autoload's _ready
## runs. SurfaceDetailRegistry is the earlier autoload, so it is loaded already.
func _init() -> void:
	_load_furniture()
	_load_items()
	_load_recipes()
	_load_trees()


func furniture_def(key: String) -> Dictionary: return furniture.get(key, {})
func has_furniture(key: String) -> bool: return furniture.has(key)
func item_def(key: String) -> Dictionary: return items.get(key, {})
func has_item(key: String) -> bool: return items.has(key)
func recipe(id: String) -> Dictionary: return recipes.get(id, {})
func has_recipe(id: String) -> bool: return recipes.has(id)
func tree_species(key: String) -> Dictionary: return trees.get(key, {})
func has_tree_species(key: String) -> bool: return trees.has(key)


## Key sets for SaveSnapshotValidator. Built fresh so a save worker owns them.
func save_catalogs() -> Dictionary:
	var tree_stages := {}
	for key: String in trees: tree_stages[key] = trees[key].stages.duplicate()
	var plants := {}
	for key: String in SurfaceDetailRegistry.definitions: plants[key] = true
	return {"furniture": furniture.duplicate(), "items": items.duplicate(),
		"recipes": recipes.duplicate(), "max_craft_orders": max_craft_orders,
		"trees": tree_stages, "plants": plants}


## A top-level JSON object, or null after JsonData reports why not.
func _read(path: String) -> Variant:
	return JsonData.read(path)


## Placeable definitions need a key, a placement and the item they pack into.
func _load_furniture() -> void:
	for file_name in DirAccess.get_files_at(FURNITURE_DIR):
		if not file_name.ends_with(".json"): continue
		var def: Variant = _read("%s/%s" % [FURNITURE_DIR, file_name])
		if not def is Dictionary: continue
		var key := String(def.get("furniture_key", ""))
		if key.is_empty() or not def.has("placement") or not def.has("item_key"):
			push_error("ContentRegistry: incomplete furniture " + file_name)
			continue
		furniture[key] = def
	furniture.merge(SurfaceDetailRegistry.get_place_definitions())


func _load_items() -> void:
	var root: Variant = _read(ITEMS_PATH)
	if not root is Dictionary: return
	for key: String in root:
		if not key.begins_with("__") and root[key] is Dictionary: items[key] = root[key]


func _load_recipes() -> void:
	var raw: Variant = _read(RECIPES_PATH)
	if not raw is Dictionary: return
	max_craft_orders = int(raw.get("max_orders", 64))
	for section: Dictionary in raw.get("sections", []):
		recipe_sections[String(section.id)] = section
	for entry: Dictionary in raw.get("recipes", []):
		# A batch of matching timber, plus optional fixed single-unit materials.
		if int(entry.get("ingredient_count", 0)) < 1 or float(entry.get("work_seconds", 0)) <= 0:
			push_error("ContentRegistry: unsupported worker recipe " + str(entry.get("id")))
			continue
		recipes[String(entry.id)] = entry


## Each flora "*_tree.json" holds one "base:flora:*_tree" species. Keeps
## species with both a placement niche and growth stages, ordered by
## placement.pick_order: the seeded species pick order (Hard Rule 8), so a new
## species takes the next free number.
func _load_trees() -> void:
	var found: Array = []
	for path: String in SurfaceDetailRegistry.flora_files("_tree.json"):
		var parsed: Variant = _read(path)
		if not parsed is Dictionary: continue
		for key: String in parsed:
			if not key.begins_with("base:flora:"): continue
			var def: Dictionary = parsed[key]
			if def.get("placement", {}).is_empty() or def.get("stages", {}).is_empty():
				push_error("ContentRegistry: tree species without placement or stages " + key)
				continue
			found.append([int(def.placement.get("pick_order", -1)), key, def])
			break
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in found: trees[entry[1]] = entry[2]
