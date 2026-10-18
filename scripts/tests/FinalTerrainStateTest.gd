extends SceneTree

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var migration = load("res://scripts/components/TerrainSaveMigration.gd")
	var old := {"schema_version":1,"scene":{
		"mining":{"mined_blocks":[[8,8,8],[9,8,8],[10,8,8]],"zones":[]},
		"water":{"terrain":[{"cell":[8,8,8],"block":"base:terrain:rock:rock01"}]},
		"construction":{"built":[{"cell":[8,8,8],"block":"base:construction:floor:plank"},
			{"cell":[9,8,8],"block":"base:construction:floor:stone"}],"orders":[],"next_id":1}}}
	var upgraded: Dictionary = migration.upgrade(old.duplicate(true))
	_expect(old.schema_version==1 and old.scene.construction.has("built"),"source snapshot remains available for backup")
	_expect(upgraded.schema_version==2 and upgraded.scene.terrain.edits.size()==3,"overlapping legacy records become one final voxel each")
	var final := {}
	for entry: Dictionary in upgraded.scene.terrain.edits: final[str(entry.cell)] = entry.block
	_expect(final[str([8,8,8])]=="base:construction:floor:plank","last old owner determines final plank tile")
	_expect(final[str([9,8,8])]=="base:construction:floor:stone","stone flooring retains its identity")
	_expect(final[str([10,8,8])]=="base:terrain:void","unfilled excavation retains air")
	_expect(upgraded.scene.exploration.legacy_mined==old.scene.mining.mined_blocks,"legacy knowledge is kept separately")
	_expect(not upgraded.scene.construction.has("built") and not upgraded.scene.water.has("terrain") and not upgraded.scene.mining.has("mined_blocks"),"old terrain authorities removed")
	_expect(migration.upgrade(upgraded)==upgraded,"current format needs no conversion")
	# Use real generator identity for pruning, including later dirt/grass writers.
	var generator = root.get_node("WorldGenerator")
	root.get_node("WorldClock").set_paused(true)
	root.get_node("SaveManager").set_process(false)
	root.get_node("TaskManager").set_process(false)
	change_scene_to_file("res://scenes/main/debug_world.tscn")
	while current_scene==null or not generator._maps_ready or generator.is_generating(): await process_frame
	var world = root.get_node("WorldData")
	var blocks = root.get_node("BlockRegistry")
	var cell := Vector3i(512,30,512)
	var original: int = generator.get_generated_block_id(cell.x,cell.y,cell.z)
	var baseline: int = world.terrain_overrides().size()
	for key in ["base:terrain:void","base:terrain:soil:dark","base:terrain:surface:grass_01","base:construction:floor:plank","base:construction:floor:stone"]:
		var id: int = blocks.get_id(key)
		world.set_block(cell.x,cell.y,cell.z,id)
		_expect(world.get_terrain_block(cell.x,cell.y,cell.z)==id,"final terrain follows the latest write: "+key)
		_expect(world.terrain_overrides().size()<=baseline+1,"repeated changes never append voxel history")
	world.set_block(cell.x,cell.y,cell.z,original)
	_expect(not world.has_terrain_override(cell),"returning to generated identity removes the override")
	_expect(root.get_node("InteriorTracker").is_known(cell),"restoring original terrain retains exploration")
	var renderer = current_scene.get_node("Renderer")
	renderer._flush_terrain_changes()
	_expect(not renderer._visual_cut_blocks.has(cell),"restored natural terrain has no stale excavation hole")
	for failure in failures: push_error(failure)
	print("FINAL_TERRAIN_STATE_OK" if failures.is_empty() else "FINAL_TERRAIN_STATE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
