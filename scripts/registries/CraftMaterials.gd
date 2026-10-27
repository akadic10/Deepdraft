extends Node

## Sole owner of material identity, appeal tuning and semantic wood palettes.
## Finished goods keep a material ID; recipes and catalog entries remain generic.
const DATA_PATH := "res://data/materials/craft_materials.json"
const JsonData = preload("res://scripts/registries/JsonData.gd")
var definitions: Dictionary = {}
var palettes: Dictionary = {}
var _ingredients: Dictionary = {}
var _meshes: Dictionary = {}


func _ready() -> void:
	var data := JsonData.read_dict(DATA_PATH)
	assert(not data.is_empty(), "Invalid craft material definitions")
	definitions = data.get("materials", {})
	palettes = data.get("source_palettes", {})
	for id: String in definitions:
		for key: String in definitions[id].get("ingredients", []):
			_ingredients[key] = id


func from_ingredient(key: String) -> String:
	return String(_ingredients.get(key, ""))


func of_item(item: Node) -> String:
	return String(item.get_meta("material_id", "")) if is_instance_valid(item) else ""


func valid(id: String) -> bool:
	return id.is_empty() or definitions.has(id)


func material_name(id: String) -> String:
	return String(definitions.get(id, {}).get("name", "Unspecified"))


func product_name(base_name: String, id: String) -> String:
	if not definitions.has(id) or base_name.is_empty(): return base_name
	return "%s %s" % [definitions[id].adjective, base_name.to_lower()]


func appeal(definition: Dictionary, id: String) -> Dictionary:
	var tuning: Dictionary = definition.get("appeal", {})
	var design := float(tuning.get("design", 0.0))
	var material := float(definitions.get(id, {}).get("appeal_bonus", 0.0)) * float(tuning.get("material_factor", 1.0))
	return {"design": design, "material": material, "total": design + material}


## The compact panel's appeal badge (doc 260): the total, with the parts on hover.
func appeal_badge(definition: Dictionary, id: String, packed: bool = false) -> Dictionary:
	var score := appeal(definition, id)
	var number := func(value: float) -> String: return ("%.1f" % value).trim_suffix(".0")
	return {"kind": "appeal", "value": number.call(score.total), "tooltip": "%s %s: %s design + %s material" % [
		"Appeal when installed" if packed else "Appeal", number.call(score.total), number.call(score.design), number.call(score.material)]}


func inspection_rows(definition: Dictionary, id: String, packed: bool = false) -> Array:
	var rows: Array = []
	if not id.is_empty(): rows.append(["Material", material_name(id)])
	if definition.has("appeal"):
		var score := appeal(definition, id)
		rows.append(["Appeal when installed" if packed else "Appeal", "%s  (%s design + %s material)" % [str(score.total), str(score.design), str(score.material)]])
	return rows


func apply_palette(root: Node, definition: Dictionary, id: String) -> void:
	var profile := String(definition.get("material_palette", ""))
	if profile.is_empty() or not palettes.has(profile) or not definitions.has(id): return
	var target: Dictionary = definitions[id].get("colors", {})
	if target.is_empty(): return
	_apply_node(root, profile, id, target)


func _apply_node(node: Node, profile: String, id: String, target: Dictionary, source: Dictionary = {}) -> void:
	if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(node): return
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var original: ArrayMesh = node.mesh
		var cache_key := "%d:%s:%s" % [original.get_instance_id(), profile, id]
		if not _meshes.has(cache_key): _meshes[cache_key] = _recolor(original, source if not source.is_empty() else palettes[profile], target)
		node.mesh = _meshes[cache_key]
	for child in node.get_children(): _apply_node(child, profile, id, target, source)


## The same shared, shade-aware recolour for a palette owned elsewhere (dwarf
## clothing, doc 256): `source` is {"colors": {role: hex}}, `target` {role: hex}.
func apply_colors(root: Node, source: Dictionary, tag: String, target: Dictionary) -> void:
	_apply_node(root, tag, "", target, source)


func _recolor(original: ArrayMesh, profile: Dictionary, target: Dictionary) -> ArrayMesh:
	var replacements: Array = []
	var swatches: Array = []
	for role: String in profile.colors:
		if not target.has(role): continue
		var source := Color(String(profile.colors[role])).srgb_to_linear()
		if int(profile.get("encoding", 1)) == 2: source = source.srgb_to_linear()
		replacements.append([source, Color(String(target[role])).srgb_to_linear()])
		swatches.append([source, Color(String(target[role])).srgb_to_linear()])
		# Godot packs imported colors by truncating to RGBA8. Compare the exact
		# packed swatch too, so pale cut surfaces map without tinting nearby stone.
		var packed := Color(floorf(source.r * 255) / 255, floorf(source.g * 255) / 255, floorf(source.b * 255) / 255)
		replacements.append([packed, Color(String(target[role])).srgb_to_linear()])
	var mesh := ArrayMesh.new()
	for surface in range(original.get_surface_count()):
		var arrays := original.surface_get_arrays(surface)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var shades: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		for index in range(colors.size()):
			if index < shades.size() and shades[index].x < 0.999:
				colors[index] = _shaded(colors[index], shades[index].x, swatches)
				continue
			for pair: Array in replacements:
				var delta: Color = colors[index] - pair[0]
				if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) < 0.0001:
					colors[index] = Color(pair[1], colors[index].a)
					break
		if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(original.surface_get_primitive_type(surface), arrays)
		mesh.surface_set_material(surface, original.surface_get_material(surface))
		mesh.surface_set_name(surface, original.surface_get_name(surface))
	return mesh


## Baked corner occlusion (tools/art_data/voxel_occlusion.json) darkens vertex colors and
## stores each vertex's shade in UV2.x. Wood ramps collide once darkened, so match
## the unshaded swatch at that exact shade and keep the shade on the new wood.
static func _shaded(color: Color, shade: float, swatches: Array) -> Color:
	var result := color
	var best := 1.5 / 255.0   # a true match is at most one 8-bit step away
	for pair: Array in swatches:
		var source: Color = pair[0]
		var error := maxf(absf(color.r - source.r * shade), maxf(absf(color.g - source.g * shade), absf(color.b - source.b * shade)))
		if error < best:
			best = error
			var goal: Color = pair[1]
			result = Color(goal.r * shade, goal.g * shade, goal.b * shade, color.a)
	return result
