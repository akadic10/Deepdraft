extends RefCounted

## Ghost visuals for FurniturePlacementController (doc 258 step 8): the cursor
## ghost (validity-tinted, rebuilt for ladder heights), the
## why-invalid hint, the project's ghost and solid materials and model
## instancing. Tool state is read through the controller's placement_state(). The hint is
## text the tool bar shows (doc 23, "The tool bar").

const WallMount = preload("res://scripts/components/WallFurnitureMount.gd")
const GridFence = preload("res://scripts/components/GridFence.gd")
const Rules = preload("res://scripts/components/FurniturePlacementRules.gd")

var controller
var preview: Node3D = null             # cursor ghost (one per activation)
var material: StandardMaterial3D = null
var hint_text := ""
var _ladder_height := -1


func _init(owner_controller) -> void:
	controller = owner_controller


## A fresh cursor ghost for one furniture def, hidden until positioned.
func create(furniture_key: String) -> void:
	material = make_ghost_material()
	preview = instance_model(furniture_key, material, controller.get_defs().get(furniture_key, {}))
	if preview != null:
		controller.add_child(preview)
		preview.visible = false


func clear() -> void:
	_ladder_height = -1
	if preview != null:
		preview.queue_free()
		preview = null
	hint_text = ""


func place(origin: Vector3i) -> void:
	if preview == null:
		return
	var state: Dictionary = controller.placement_state()
	var key: String = state.key
	var yaw: int = state.yaw
	var def: Dictionary = controller.get_defs().get(key, {})
	var ladders: Node3D = controller.get_ladders()
	if key == ladders.KEY:
		var spec: Dictionary = ladders.describe(origin, yaw)
		var height := maxi(ladders.section_height(), int(spec.height))
		if height != _ladder_height:
			preview.queue_free()
			preview = ladders.make_visual(height, 0, material)
			controller.add_child(preview)
			_ladder_height = height
	preview.visible = origin.x >= 0 and Rules.piece_visible(def, origin, yaw, controller.get_slice_y())
	preview.position = Rules.world_pos(def, origin, yaw)
	preview.rotation = Vector3(0.0, float(yaw) * PI * 0.5, 0.0)
	var tint: Color = FurniturePlacementController.TINT_VALID if state.valid else FurniturePlacementController.TINT_INVALID
	material.albedo_color = Color(tint.r, tint.g, tint.b, FurniturePlacementController.GHOST_ALPHA)
	update_hint(origin)


## Why-invalid hint (the mining-ruler lesson: never make the player guess).
## Shown only for the wall requirement — plain cell blockage is self-evident.
func update_hint(_origin: Vector3i) -> void:
	var state: Dictionary = controller.placement_state()
	var key: String = state.key
	var yaw: int = state.yaw
	var valid: bool = state.valid
	var invalid_reason: String = state.reason
	var defs: Dictionary = controller.get_defs()
	var ladders: Node3D = controller.get_ladders()
	var wall := WallMount.is_wall(defs.get(key, {}))
	var hints := {"stone_access":"Needs a reachable dry place for a dwarf to stand", "plant_soil":"Needs suitable soil and a level 3 × 3 patch",
		"fence_support":"Needs solid ground under every tile",
		"fence_clearance":"Clear the tile for the post or gate",
		"fence_access":"Leave a walkable tile beside the fence",
		"plant_clearance":"Clear nearby plants, stones or structures first",
		"plant_spacing":"Needs its own 3 × 3 area — move farther from plants or queued orders",
		"plant_sky":"This plant needs open sky", "wall_support":"The bracket needs solid wall behind it",
		"wall_clearance":"Leave clear space for the whole light, including its flame",
		"overlap":"Another piece occupies this space", "access":"Needs a clear work position within %d blocks below the mount" % int(TaskManager.get_config_section("furniture").wall_reach_up_blocks),
		"slice":"Raise the slice to show this furniture",
		"seat_clearance":"Leave room for a seated dwarf’s head",
		"seat_access":"Leave an open tile beside or behind the chair",
		"seat_capacity":"Table chair limit reached — cancel or remove a chair to choose another side",
		"cell":"This position is occupied or has no clear floor"}
	hint_text = String(hints.get(invalid_reason, "Point at a wall, or aim beside it and press R" if wall else ""))
	if GridFence.applies(defs.get(key,{})) and valid:
		hint_text = "Click a tile to place a post · Rails connect neighboring posts · Esc finishes" if GridFence.is_post(defs[key]) else "Point at the gate's opening tile · R rotates · Click to place · Esc finishes"
	if wall and valid:
		hint_text = "Mount level %d · Alt + wheel: height · R: floor-aim facing · Click to place" % WallMount.mount_cell(defs[key],state.cell).y
	elif wall:
		hint_text += " · Alt + wheel: height"
	if valid and not controller.get_seating().snap.is_empty():
		hint_text = "Table seat — chair faces inward. Click to place; Esc to finish."
	if valid and bool(defs.get(key, {}).get("plant", false)):
		hint_text = "Click to choose this plant’s new home · R rotates · Esc cancels" if not String(state.moving_shrub).is_empty() else "Click to plant here · reserves a 3 × 3 area · R rotates · Esc finishes"
	var tree := ContentRegistry.tree_species(String(defs.get(key, {}).get("tree_species", "")))
	if not tree.is_empty(): # A seed's sizes are its grown tree's (doc 284).
		var trunk := "%d × %d" % [int(tree.placement.footprint.ancient), int(tree.placement.footprint.ancient)]
		var area := "%d × %d" % [int(tree.planting.area), int(tree.planting.area)]
		hint_text = "Click to plant here · keeps other trees out of its %s area · Esc finishes" % area if valid else String({
			"plant_soil": "Plant it in grass, dirt or soil",
			"tree_ground": "Needs level ground for the grown %s trunk" % trunk,
			"tree_sky": "The grown tree needs open sky over its %s trunk" % trunk,
			"plant_clearance": "Clear plants, stones, furniture and stockpiles from its %s trunk ground" % trunk,
			"tree_spacing": "Needs its own %s area: fell nearby trees or plant farther away" % area}.get(invalid_reason, hint_text))
	if bool(defs.get(key, {}).get("show_placement_area", false)):
		var fp: Dictionary = defs[key].footprint
		var area := "%d × %d" % [int(fp.width), int(fp.depth)]
		if valid:
			hint_text = "Click to place · reserves a %s area · R rotates · Esc finishes" % area
			if defs[key].has("placement_label"):
				hint_text = "%s · Click to place · R rotates · Esc finishes" % String(defs[key].placement_label)
				if bool(defs[key].get("room_heater", false)):
					hint_text += "\nFace the opening into an enclosed room"
		elif invalid_reason == "cell":
			hint_text = "Needs a clear, level %s area" % area
	if key == ladders.KEY:
		var spec: Dictionary = ladders.describe(_origin, yaw)
		hint_text = "%d-block ladder · %d ladder sections · Click to build · R rotates" % [spec.height, ladders.sections(spec.height)] if valid else invalid_reason


static func make_ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, FurniturePlacementController.GHOST_ALPHA)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	return mat


## Project-standard solid material (doc 61 — lit per-pixel, double-sided).
static func make_solid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


## The placed-form model for one def; `def` is the resolved definition.
static func instance_model(furniture_key: String, override: Material, def: Dictionary) -> Node3D:
	var path := String(def.get("model", ""))
	if bool(def.get("plant", false)):
		path = SurfaceDetailRegistry.place_model(def, WorldClock.season)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("FurniturePlacementController: missing model '%s' for %s." % [path, furniture_key])
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	apply_material(node, override)
	var is_preview := override is BaseMaterial3D and (override as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	preload("res://scripts/components/VoxelShadowSetup.gd").set_casting(node, not is_preview)
	var plant := bool(def.get("plant", false))
	var ghost_area := bool(def.get("show_placement_area", false)) and override is BaseMaterial3D \
		and (override as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if plant or ghost_area:
		var outline := MeshInstance3D.new()
		outline.name = "PlantingArea" if plant else "PlacementArea"
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, override)
		var fp: Dictionary = def.get("footprint", {})
		var half_w := 1.5 if plant else float(fp.get("width", 1)) * .5
		var half_d := 1.5 if plant else float(fp.get("depth", 1)) * .5
		var rects: Array[Rect2] = [Rect2(-half_w, -half_d, half_w * 2, half_d * 2)]
		var tree := ContentRegistry.tree_species(String(def.get("tree_species", "")))
		if not tree.is_empty(): # A seed outlines its grown tree's area and the trunk inside it (doc 284).
			var half := int(tree.planting.area) * .5
			var trunk := int(tree.placement.footprint.ancient)
			var low := -floori((trunk - 1) / 2.0) - .5
			rects = [Rect2(-half, -half, half * 2, half * 2), Rect2(low, low, trunk, trunk)]
		for rect: Rect2 in rects:
			var corners := [Vector3(rect.position.x,.04,rect.position.y), Vector3(rect.end.x,.04,rect.position.y),
				Vector3(rect.end.x,.04,rect.end.y), Vector3(rect.position.x,.04,rect.end.y)]
			for i in range(4):
				mesh.surface_add_vertex(corners[i])
				mesh.surface_add_vertex(corners[(i+1)%4])
		mesh.surface_end()
		outline.mesh = mesh
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(outline)
	return node


static func apply_material(node: Node, mat: Material) -> void:
	if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(node): return
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		apply_material(child, mat)
