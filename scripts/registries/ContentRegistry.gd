extends Node

## Sole loader for the static content saves name: furniture pieces (with
## SurfaceDetailRegistry's plant place entries and the tree seed plans merged in), items, worker
## recipes, tree species and field crops. It exists before any scene so startup resume can
## reject saves naming content the game no longer defines. Scene systems read
## definitions here and keep their own runtime state. Never mutate the returned
## dictionaries.
const FURNITURE_DIR := "res://data/furniture/"
const ITEMS_PATH := "res://data/items/items.json"
const RECIPES_PATH := "res://data/recipes/recipes.json"
const CROPS_PATH := "res://data/flora/field_crops.json"
const JsonData = preload("res://scripts/registries/JsonData.gd")

var furniture: Dictionary = {}       # furniture_key -> placeable definition
var items: Dictionary = {}           # item key -> definition
var recipes: Dictionary = {}         # recipe id -> worker recipe
var recipe_sections: Dictionary = {} # section id -> crafting menu section
var max_craft_orders := 64
var trees: Dictionary = {}           # species key -> definition with placement and stages
var crops: Dictionary = {}           # crop key -> a field vegetable's definition (doc 309), in file order


## Loads at construction, not _ready: the main scene is built (member
## initializers that copy these tables included) before any autoload's _ready
## runs. SurfaceDetailRegistry is the earlier autoload, so it is loaded already.
func _init() -> void:
	_load_furniture()
	_load_items()
	_load_recipes()
	_load_trees()
	_load_tree_plantings()
	_load_crops()


func furniture_def(key: String) -> Dictionary: return furniture.get(key, {})
func has_furniture(key: String) -> bool: return furniture.has(key)
func item_def(key: String) -> Dictionary: return items.get(key, {})
func has_item(key: String) -> bool: return items.has(key)
func recipe(id: String) -> Dictionary: return recipes.get(id, {})
## The recipe that makes a good, or {}: who makes a career's tool, and where (doc 306).
func recipe_for(item_key: String) -> Dictionary:
	for entry: Dictionary in recipes.values():
		if String(entry.get("output", "")) == item_key: return entry
	return {}
## The recipes made at a workshop (their `workshop`), in the crafting pages' order. A piece is a
## workshop when it has any: its window opens crafting at the first, and the careers of them all
## craft there (FurnitureWindow, doc 44 "Its window's action").
func recipes_at(workshop_key: String) -> Array:
	return recipes.values().filter(func(entry: Dictionary) -> bool: return String(entry.get("workshop", "")) == workshop_key)
func has_recipe(id: String) -> bool: return recipes.has(id)
func tree_species(key: String) -> Dictionary: return trees.get(key, {})
func has_tree_species(key: String) -> bool: return trees.has(key)
func crop(key: String) -> Dictionary: return crops.get(key, {})
func has_crop(key: String) -> bool: return crops.has(key)


## Key sets for SaveSnapshotValidator. Built fresh so a save worker owns them.
func save_catalogs() -> Dictionary:
	var tree_stages := {}
	for key: String in trees: tree_stages[key] = trees[key].stages.duplicate()
	var plants := {}
	for key: String in SurfaceDetailRegistry.definitions: plants[key] = true
	return {"furniture": furniture.duplicate(), "items": items.duplicate(),
		"recipes": recipes.duplicate(), "max_craft_orders": max_craft_orders,
		"trees": tree_stages, "plants": plants, "crops": crops.duplicate()}


## A top-level JSON object, or null after JsonData reports why not.
func _read(path: String) -> Variant:
	return JsonData.read(path)


## Placeable definitions need a key, a placement and the item they pack into.
func _load_furniture() -> void:
	for file_name in DirAccess.get_files_at(FURNITURE_DIR):
		if not file_name.ends_with(".json"): continue
		var def: Variant = _read(FURNITURE_DIR + file_name)
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


## A species with a "planting" block joins Place → Plants (doc 284): one seed makes
## a sapling. The plan names its species; SurfaceFloraSpawner owns the planted tree.
func _load_tree_plantings() -> void:
	for key: String in trees:
		var planting: Dictionary = trees[key].get("planting", {})
		if planting.is_empty(): continue
		var item_name := String(items.get(String(planting.item), {}).get("display_name", key))
		var sapling: Dictionary = trees[key].stages.sapling
		furniture[String(planting.catalog_key)] = {"plant": true, "tree_species": key,
			"furniture_key": planting.catalog_key, "display_name": item_name.left(1) + item_name.substr(1).to_lower(),
			"item_key": planting.item, "placement": "floor", "model": sapling.models.summer,
			"footprint": {"width": 1, "depth": 1, "height": int(sapling.clearance_height)},
			"collision_regions": [], "planting_seconds": float(planting.work_seconds)}


## The field vegetables (doc 309): each needs the good it gives, a season to be sown in, its days
## and its three stages' models. FarmingSystem holds the fields that grow them.
func _load_crops() -> void:
	var raw: Variant = _read(CROPS_PATH)
	if not raw is Dictionary: return
	for key: String in raw:
		if key.begins_with("__") or not raw[key] is Dictionary: continue
		var def: Dictionary = raw[key]
		var models: Dictionary = def.get("models", {})
		if not items.has(String(def.get("item", ""))) or (def.get("sow_seasons", []) as Array).is_empty() \
				or float(def.get("grow_days", 0)) <= 0 or int(def.get("tile_yield", 0)) < 1 or int(def.get("plan_seasons", 0)) < 1 \
				or not (models.has("sprout") and models.has("growing") and models.has("ripe")) \
				or (float(def.get("regrow_days", 0)) > 0 and not models.has("picked")):
			push_error("ContentRegistry: incomplete field crop " + key)
			continue
		crops[key] = def
