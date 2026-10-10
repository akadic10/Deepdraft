extends "res://scripts/tests/WorkerCraftingTest.gd"

const CAMP := "base:furniture:campfire"
const CAMP_ITEM := "base:resources:furniture:campfire"
const OUT := "res://tmp/campfire_area_review/"

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Campfire area test timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(OUT)
	var def: Dictionary = furniture.get_defs()[CAMP]
	var origin := Vector3i(48,20,44)
	var center := Vector3(49.5,21,45.5)
	var nav = root.get_node("NavGrid")
	camera.size = 8
	camera.position = center + Vector3(8,10,10)
	camera.look_at(center)
	worker.hide()
	for yaw in range(4):
		furniture.activate_for(CAMP)
		furniture._yaw = yaw
		# Exercise screen-space aiming, not just a manually assigned origin.
		furniture._update_hover(true,camera.unproject_position(center))
		_expect(furniture._hover_valid and furniture._hover_cell==origin,"cursor selects the center tile in rotation "+str(yaw))
		_expect(furniture._preview.position.is_equal_approx(center),"fire preview stays centered on the cursor")
		var outline: MeshInstance3D = furniture._preview.get_node_or_null("PlacementArea")
		_expect(outline!=null and outline.get_aabb().size.is_equal_approx(Vector3(3,0,3)),"preview outlines its full three-by-three area")
		var bounds: AABB = furniture._visual_bounds(def,origin,yaw)
		# The handmade stone ring is asymmetric by one art voxel (0.125 blocks).
		_expect(bounds.size.x>=1.75 and bounds.size.x<=2.001 and bounds.size.z>=1.75 and bounds.size.z<=2.001,"fire art keeps its original roughly two-block width")
		_expect(absf(bounds.get_center().x-center.x)<=.125 and absf(bounds.get_center().z-center.z)<=.125,"stone ring is centered inside the area within its irregular stone outline")
		if yaw==0 and "--capture" in OS.get_cmdline_user_args(): await _capture_area("preview")
		var plan_id: int = furniture._next_ghost_id
		furniture._confirm_ghost()
		furniture.deactivate()
		var ghost = furniture._ghosts[plan_id]
		_expect(ghost.footprint_cells().size()==9 and ghost.node.get_node_or_null("PlacementArea")!=null,"queued fire displays and reserves all nine cells")
		for cell in ghost.footprint_cells():
			_expect(furniture.blocks_zone_cell(cell) and nav.is_walkable(cell),"queued area excludes placement but does not block walking")
		_expect(not furniture._floor_placement_reason(def,origin+Vector3i(2,0,2),yaw).is_empty(),"overlapping diagonal camp area is rejected")
		_expect(furniture._floor_placement_reason(def,origin+Vector3i(3,0,0),yaw).is_empty(),"touching camp areas are allowed")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		furniture.cancel_ghost(plan_id)
		_expect(not furniture.blocks_zone_cell(origin+Vector3i(2,0,2)),"cancellation frees the outermost area cell")
		furniture.restore_state(saved)
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"new queued area survives save/load")
		furniture.dev_instant_build(plan_id)
		var fire = furniture._installed.values()[0]
		_expect(fire.cells.size()==9 and fire.node.position.is_equal_approx(center),"installed fire matches preview and plan")
		_expect(fire.node.get_node_or_null("PlacementArea")==null,"placement outline disappears after installation")
		_expect(fire.node.get_node_or_null("FlameAnimation")!=null and fire.node.get_node_or_null("FurnitureLight")!=null,"centered fire retains flame animation and light")
		for cell in fire.cells:
			_expect(not nav.is_walkable(cell),"dwarves cannot cross the centered stone ring")
		for offset in [Vector3i(-1,0,1),Vector3i(3,0,1),Vector3i(1,0,-1),Vector3i(1,0,3)]:
			_expect(nav.is_walkable(origin+offset),"walkable approach remains outside each side")
		saved = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
		_clear_camp()
		furniture.restore_state(saved)
		_expect(JSON.parse_string(JSON.stringify(furniture.serialize_state()))==saved,"installed area and rotation survive save/load")
		if yaw==0 and "--capture" in OS.get_cmdline_user_args():
			var stool := "base:furniture:log_chair"
			for entry in [[Vector3i(49,20,42),0],[Vector3i(49,20,48),2],[Vector3i(46,20,45),1],[Vector3i(52,20,45),3]]:
				_expect(furniture._floor_placement_reason(furniture.get_defs()[stool],entry[0],entry[1]).is_empty(),"stools align with each side of the center tile")
				furniture._install(stool,furniture.get_defs()[stool],entry[0],entry[1])
			camera.size = 10
			await _capture_area("installed_with_stools")
			camera.size = 8
		_clear_camp()
	# Development saves use the current definition, regardless of old layout tags.
	var entry := {"id":77,"key":CAMP,"origin":[48,20,44],"yaw":1,"layout_version":1}
	furniture.restore_state({"installed":[entry]})
	var restored = furniture._installed[77]
	_expect(restored.cells.size()==9 and restored.node.position.is_equal_approx(center),"loaded fire adopts current area directly without rebuilding")
	_expect(_count(CAMP_ITEM)==0,"loading an installed fire creates no extra packed item")
	_clear_camp()
	furniture.restore_state({"ghosts":[entry]})
	_expect(furniture._ghosts[77].footprint_cells().size()==9,"loaded pending plan adopts current area")
	furniture.dev_instant_build(77)
	_expect(furniture._installed.values()[0].cells.size()==9,"loaded pending fire finishes in current layout")
	var installed_id: int = furniture._installed.keys()[0]
	furniture.dev_remove_installed(installed_id)
	_expect(_count(CAMP_ITEM)==1,"uninstall returns exactly one packed campfire")
	furniture.activate_for(CAMP,true)
	furniture._update_hover(true,camera.unproject_position(center))
	_expect(furniture._hover_valid,"returned packed campfire can be placed")
	furniture._confirm_ghost()
	furniture.deactivate()
	_expect(await _installed(CAMP),"worker installs returned fire through normal fetching and building")
	_expect(furniture._installed.values()[0].cells.size()==9 and _count(CAMP_ITEM)==0,"installation uses current area and consumes the item")
	for failure in failures: push_error(failure)
	print("CAMPFIRE_AREA_OK: cursor centering, unchanged art, outline, four rotations, reservations, navigation and current-definition save/load" if failures.is_empty() else "CAMPFIRE_AREA_FAIL")
	quit(0 if failures.is_empty() else 1)

func _clear_camp() -> void:
	for id in furniture._ghosts.keys(): furniture.cancel_ghost(id)
	for id in furniture._installed.keys(): furniture.dev_remove_installed(id)
	for node in drops._loose.keys(): drops.take(node); node.free()

func _capture_area(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
