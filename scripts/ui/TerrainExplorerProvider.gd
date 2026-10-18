extends Node

## Player-facing terrain facts. The renderer owns reveal/cut provenance, WorldData
## owns live blocks, and BlockRegistry owns names. No independent discovery state.
@export var renderer_path: NodePath
const Picking = preload("res://scripts/components/ObjectPicking.gd")
var renderer: Node

func _ready() -> void:
	if renderer == null: renderer = get_node_or_null(renderer_path)

func developer_inspection_active() -> bool:
	return is_instance_valid(renderer) and renderer.is_block_inspector_active()

func terrain_hit(start: Vector3, direction: Vector3, slice_y: int, distance: float) -> Dictionary:
	if not is_instance_valid(renderer): return {}
	return Picking.terrain_hit(start,direction,slice_y,distance,_visible_block,_visible_face)

func _visible_face(cell: Vector3i, normal: Vector3i) -> bool:
	if is_instance_valid(renderer.underground_view): return renderer.underground_view.is_terrain_face_visible(cell,normal)
	return renderer.is_block_visible(cell)

func _visible_block(cell: Vector3i) -> int:
	if WorldData.has_terrain_override(cell): return WorldData.get_live_block(cell.x,cell.y,cell.z)
	if renderer._visual_cut_blocks.has(cell): return BlockRegistry.AIR_ID
	var block := WorldData.get_live_block(cell.x,cell.y,cell.z)
	# Undiscovered cave air is concealed by the same rock shell as the renderer.
	if block == BlockRegistry.AIR_ID and WorldGenerator.get_cave_id(cell)>=0:
		return WorldGenerator.get_overview_strata_block_id(cell.x,cell.y,cell.z)
	return block

func get_explorer_data(hit: Dictionary) -> Dictionary:
	if not is_instance_valid(renderer) or hit.is_empty(): return {}
	var cell := Vector3i(hit.x,hit.y,hit.z)
	var normal: Vector3i = hit.normal
	if cell.y > renderer.slice_y or normal == Vector3i.ZERO: return {}
	var block := _visible_block(cell)
	if not BlockRegistry.is_solid(block): return {}
	var air := cell+normal
	if air.y<=renderer.slice_y and BlockRegistry.is_solid(_visible_block(air)): return {}
	var known: bool = InteriorTracker.is_known(cell)
	var cut_face: bool = normal==Vector3i.UP and cell.y==renderer.slice_y and BlockRegistry.is_solid(WorldData.get_live_block(air.x,air.y,air.z))
	var revealed: bool = renderer.is_revealed_air(air)
	if normal==Vector3i.UP and not cut_face:
		# Overview floors stay concealed if any removed cell above is only a plan.
		var top := mini(WorldGenerator.get_surface_y(cell.x,cell.z),renderer.slice_y)
		var crossed_plan := false
		for y in range(cell.y+1,top+1):
			var above := Vector3i(cell.x,y,cell.z)
			if renderer._visual_cut_blocks.has(above) and not renderer.is_revealed_air(above): crossed_plan = true
		revealed = not crossed_plan and (revealed or cell.y==WorldGenerator.get_surface_y(cell.x,cell.z))
	if not known and (cut_face or not revealed):
		block = WorldGenerator.get_overview_strata_block_id(cell.x,cell.y,cell.z)
	var def := BlockRegistry.get_def(BlockRegistry.get_key(block))
	var info: Dictionary = def.get("inspection",{})
	if info.is_empty(): return {}
	var title: String = info.name
	var face := "Floor" if normal==Vector3i.UP else ("Ceiling" if normal==Vector3i.DOWN else "Wall")
	return {"title":title,"kind":"Terrain","rows":[["Type",info.category],["Surface","Slice surface" if cut_face else face],
		["Level",str(cell.y)]],
		"details":"Excavate to reveal the material inside this slice." if cut_face and not known else info.description}

func get_explorer_bounds(hit: Dictionary) -> AABB:
	return AABB(Vector3(hit.x,hit.y,hit.z),Vector3.ONE)
