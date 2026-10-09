extends Node

## Sole loader for surface-detail definitions. Runtime owners keep only stable
## string definition/instance keys in saves; no block IDs or visual nodes.
const DATA_PATH := "res://data/entities/surface_details.json"
var definitions: Dictionary = {}


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("SurfaceDetailRegistry: invalid definitions")
		return
	for key: String in parsed:
		var definition: Dictionary = parsed[key]
		if definition.get("models", []).is_empty() or int(definition.get("footprint", 0)) < 1:
			push_error("SurfaceDetailRegistry: invalid detail " + key)
			continue
		definitions[key] = definition
	for species: String in ["blueberry", "elderberry", "wild_strawberry"]:
		_load_shrub(species)


func _load_shrub(species: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/entities/flora/%s_bush.json" % species))
	var key := "base:flora:%s_bush" % species
	if not parsed is Dictionary or not parsed.has(key):
		push_error("SurfaceDetailRegistry: invalid shrub " + species)
		return
	var plant: Dictionary = parsed[key]
	var definition: Dictionary = plant.wild.duplicate(true)
	var mature: Dictionary = plant.stages.fruiting
	definition["kind"] = "shrub"
	definition["category"] = species
	definition["blocking"] = false
	definition["footprint"] = 1
	definition["height"] = int(mature.clearance_height)
	definition["seasonal_models"] = mature.models
	definition["picked_models"] = mature.picked_models
	definition["young_models"] = plant.stages.shrub.models
	definition["growth_days"] = float(plant.stages.shrub.growth_duration_days)
	definition["models"] = [mature.models.summer] # One persistent shape; seeded yaw.
	for entry: Dictionary in mature.harvest.yields:
		if entry.item != plant.harvest_resource: continue
		definition["harvest"] = entry.duplicate(true)
		definition.harvest["work_seconds"] = float(mature.harvest.work_seconds)
		definition.harvest["seasons"] = entry.season_only if entry.season_only is Array else [entry.season_only]
	definitions[key] = definition


func get_definition(key: String) -> Dictionary:
	return definitions.get(key, {})


## Adapter for the shared Place catalog/ghost/carry pipeline. Plant identity
## and planted state continue to belong to SurfaceDetailManager.
func get_place_definitions() -> Dictionary:
	var result := {}
	for key: String in definitions:
		var plant: Dictionary = definitions[key]
		if not plant.has("transplant"): continue
		if plant.get("kind") == "flower":
			for variant in range(plant.transplant.variants.size()):
				var entry: Dictionary = plant.transplant.variants[variant]
				result[entry.catalog_key] = {"plant": true, "plant_definition": key, "plant_variant": variant,
					"furniture_key": entry.catalog_key, "display_name": entry.display_name, "item_key": entry.item,
					"placement": "floor", "model": plant.seasonal_models.summer[variant],
					"footprint": {"width": 1, "depth": 1, "height": plant.height},
					"collision_regions": [], "planting_seconds": plant.transplant.plant_seconds}
			continue
		result[key] = {"plant": true, "plant_definition": key, "furniture_key": key, "display_name": plant.display_name,
			"item_key": plant.transplant.item, "placement": "floor",
			"model": plant.seasonal_models.summer,
			"footprint": {"width": 1, "depth": 1, "height": plant.height},
			"collision_regions": [], "planting_seconds": plant.transplant.plant_seconds}
		var cutting_key := String(plant.planting.catalog_key)
		var cutting: Dictionary = result[key].duplicate(true)
		cutting.merge({"from_cutting": true, "furniture_key": cutting_key,
			"display_name": plant.display_name + " cutting", "item_key": plant.planting.item,
			"model": plant.young_models.summer, "planting_seconds": plant.planting.work_seconds}, true)
		result[cutting_key] = cutting
	return result


func place_model(definition: Dictionary, season: String) -> String:
	var plant := get_definition(String(definition.plant_definition))
	if bool(definition.get("from_cutting", false)): return String(plant.young_models[season])
	var models: Variant = plant.seasonal_models[season]
	return String(models[int(definition.get("plant_variant", 0))] if models is Array else models)


func place_key(key: String, variant: int) -> String:
	var plant := get_definition(key)
	return String(plant.transplant.variants[variant].catalog_key) if plant.get("kind") == "flower" else key


func packed_item(key: String, variant: int) -> String:
	var plant := get_definition(key)
	return String(plant.transplant.variants[variant].item) if plant.get("kind") == "flower" else String(plant.transplant.item)
