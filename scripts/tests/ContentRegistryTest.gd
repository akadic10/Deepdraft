extends SceneTree

## ContentRegistry loads before SaveManager and is the only source of
## furniture, item, recipe and tree definitions for the scene systems.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	var content: Node = root.get_node("ContentRegistry")
	var names: Array = root.get_children().map(func(node: Node) -> String: return String(node.name))
	_expect(names.find("SurfaceDetailRegistry") < names.find("ContentRegistry")
		and names.find("ContentRegistry") < names.find("SaveManager"), "autoload order: plants, content, saves")
	_expect(content.has_furniture("base:furniture:log_chair") and not content.has_furniture("base:furniture:retired"), "furniture lookup")
	_expect(content.furniture_def("base:furniture:log_chair").item_key == "base:resources:furniture:log_chair", "furniture definition fields")
	_expect(content.has_furniture("base:flora:blueberry_bush"), "plant place entries merge into furniture")
	_expect(content.has_item("base:resources:furniture:log_chair") and content.item_def("base:resources:retired").is_empty(), "item lookup")
	_expect(content.has_recipe("base:recipe:worker:log_chair") and content.recipe("base:recipe:retired").is_empty(), "recipe lookup")
	_expect(content.trees.keys() == ["base:flora:pine_tree", "base:flora:oak_tree", "base:flora:apple_tree", "base:flora:juniper_tree"],
		"tree species keep the seeded pick order")
	_expect(content.has_tree_species("base:flora:oak_tree") and content.tree_species("base:flora:oak_tree").stages.has("mature"), "tree lookup")
	# The main scene is built before any autoload's _ready, and scene systems copy
	# these tables in member initializers, so the registries must load on construction.
	var fresh_plants: Node = load("res://scripts/registries/SurfaceDetailRegistry.gd").new()
	_expect(fresh_plants.definitions.size() == root.get_node("SurfaceDetailRegistry").definitions.size(), "plant registry loads before _ready")
	fresh_plants.free()
	var fresh: Node = load("res://scripts/registries/ContentRegistry.gd").new()
	_expect(fresh.furniture.size() == content.furniture.size() and fresh.items.size() == content.items.size()
		and fresh.recipes.size() == content.recipes.size() and fresh.trees.size() == content.trees.size(), "content registry loads before _ready")
	fresh.free()
	var catalogs: Dictionary = root.get_node("SaveManager")._capture_catalogs()
	for key: String in ["furniture", "items", "recipes", "trees", "plants", "max_craft_orders", "blocks", "materials"]:
		_expect(catalogs.has(key), "save catalogs include " + key)
	# Scene systems read the registry instead of loading JSON themselves.
	var furniture = load("res://scripts/systems/FurniturePlacementController.gd").new()
	_expect(furniture.get_defs().size() == content.furniture.size(), "furniture controller uses the registry")
	furniture.free()
	var items = load("res://scripts/systems/ItemDropManager.gd").new()
	_expect(items.get_item_def("base:resources:furniture:log_chair") == content.item_def("base:resources:furniture:log_chair"), "item manager uses the registry")
	items.free()
	var crafting = load("res://scripts/systems/CraftingManager.gd").new()
	_expect(crafting.recipes.size() == content.recipes.size() and crafting.max_orders == content.max_craft_orders, "crafting uses the registry")
	crafting.free()
	var flora = load("res://scripts/systems/SurfaceFloraSpawner.gd").new()
	_expect(flora._load_all_flora() and flora._species.size() == content.trees.size(), "flora spawner uses the registry")
	flora.free()
	for failure: String in failures: push_error(failure)
	print("CONTENT_REGISTRY_OK" if failures.is_empty() else "CONTENT_REGISTRY_FAIL")
	quit(0 if failures.is_empty() else 1)
