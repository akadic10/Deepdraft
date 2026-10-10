extends "res://scripts/tests/WorkerCraftingTest.gd"

const TOOLS := ["stone_hoe", "hunting_spear", "carpentry_kit", "stone_hammer"]
const TOOL_PREFIX := "base:resources:tools:"
const RECIPE_PREFIX := "base:recipe:worker:"

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Starter tools timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/starter_tools_review"))
	var first_id: int = crafting.queue_order(RECIPE_PREFIX+TOOLS[0],1)
	drops.spawn_drop(PINE,1,Vector3i(42,21,42))
	await _frames(2)
	_expect(crafting.status(crafting.get_order(first_id),crafting.stock_snapshot())=="Waiting for Rough Stone", "wood alone cannot fabricate stone tools")
	drops.spawn_drop(STONE,1,Vector3i(44,21,44))
	await _frames(2)
	_expect(crafting.get_order(first_id).lease_id<0, "tool requires installed crude workbench")
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(45,20,42),0)
	var inspection = load("res://scripts/components/DwarfInspection.gd")
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST), "worker carries the first tool ingredient")
	var status: Dictionary = inspection.describe(worker)
	_expect(status.activity=="Carrying Rough Stone" and status.cargo[0].key==STONE,
		"crafting activity names the real carried stone instead of timber")
	_expect(await _phase(worker.TaskPhase.FETCH_DEPOSIT), "worker sets down the stone before collecting wood")
	_expect(inspection.describe(worker).activity=="Setting down Rough Stone", "ingredient delivery is not labeled as crafting the finished tool")
	_expect(await _phase(worker.TaskPhase.FETCH_TO_GHOST), "worker carries the second tool ingredient")
	status = inspection.describe(worker)
	_expect(status.activity=="Carrying Pine Log" and status.cargo[0].key==PINE,
		"crafting activity changes with the actual carried ingredient")
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "worker stages stone and carries wood to bench")
	_expect(inspection.describe(worker).activity=="Crafting stone hoe", "crafting starts after ingredient deliveries")
	var order = crafting.get_order(first_id)
	_expect(order.staged_items.size()==1 and drops.reserved_by(order.staged_items[0],worker.dwarf_id), "staged stone stays physical and reserved")
	_expect(_count(STONE)==1 and _count(PINE)==1, "all materials remain intact during work")
	worker._process(.4)
	var saved_order: Dictionary = JSON.parse_string(JSON.stringify(crafting.serialize_state()))
	var saved_items: Dictionary = drops.serialize_state()
	var carried: Array = worker.serialize_state().carried_items
	_expect(saved_items.loose.filter(func(entry): return entry.item_key==STONE).size()==1, "staged material saved by loose item owner")
	_expect(carried.size()==1 and carried[0].item_key==PINE, "carried ingredient saved once by dwarf")
	var progress: float = order.progress
	crafting.set_paused(first_id,true)
	_expect(_count(STONE)==1 and _count(PINE)==1 and crafting.bench_claims.is_empty(), "pause releases every intact ingredient and bench")
	_expect(crafting.stock_snapshot()[STONE].available==1, "staged stone returns to available inventory")
	# Rebuild physical goods from the two saved owners, as scene load does;
	# runtime staging claims must not be needed to recover either input.
	for node in drops._loose.keys():
		drops.take(node)
		node.free()
	drops.restore_state(saved_items)
	for cargo: Dictionary in carried:
		drops.restore_loose_item(cargo.item_key,worker.global_position,0,int(cargo.count))
	_expect(_count(STONE)==1 and _count(PINE)==1,"serialized staged and carried materials rebuild without duplication")
	crafting.restore_state(saved_order)
	order = crafting.orders[0]
	_expect(is_equal_approx(order.progress,progress), "partial multi-material work survives JSON restore")
	_expect(await _completed(order.id), "restored tool order completes")
	_expect(_count(TOOL_PREFIX+TOOLS[0])==1 and _count(PINE)==0 and _count(STONE)==0, "one log plus one stone makes exactly one hoe")
	# All four recipes, including storage withdrawal and exact resource costs.
	for tool in TOOLS.slice(1):
		drops.spawn_drop(PINE,1,Vector3i(42,21,42))
		zone.cell_stacks[Vector3i(40,20,44)]={"item":STONE,"count":1}
		drops.restore_stored_item(STONE,Vector3i(40,20,44),1)
		stockpiles._totals[STONE] = 1
		var id: int = crafting.queue_order(RECIPE_PREFIX+tool,1)
		_expect(await _completed(id), tool+" completes from loose wood and stored stone")
		_expect(_count(TOOL_PREFIX+tool)==1 and _count(PINE)==0 and _count(STONE)==0, tool+" conserves inputs/output")
	# Stop after the first delivery, before collecting the final log.
	drops.spawn_drop(PINE,1,Vector3i(42,21,42))
	drops.spawn_drop(STONE,1,Vector3i(44,21,44))
	var id: int = crafting.queue_order(RECIPE_PREFIX+TOOLS[0],1)
	for i in range(800):
		await _tick()
		if crafting.get_order(id).staged_items.size()==1: break
	order = crafting.get_order(id)
	_expect(order.staged_items.size()==1, "fixture reaches material delivery between trips")
	crafting.remove_order(id)
	_expect(_count(STONE)==1 and _count(PINE)==1 and worker._carried_entries.is_empty(), "cancel between trips returns both materials")
	# Changing wood after staging returns both inputs, keeping partial work.
	id = crafting.queue_order(RECIPE_PREFIX+TOOLS[0],1)
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "tool order resumes after cancellation")
	worker._process(.3)
	order = crafting.get_order(id)
	progress = order.progress
	crafting.set_allowed_ingredients(id,["base:resources:wood:oak_log"])
	_expect(_count(STONE)==1 and _count(PINE)==1 and order.staged_items.is_empty(), "wood rule change returns staged stone and carried log")
	_expect(order.progress==progress, "wood rule change retains partial work")
	crafting.set_allowed_ingredients(id,[PINE])
	_expect(await _phase(worker.TaskPhase.FETCH_WORKING), "reselecting wood resumes gathering")
	var bench = furniture._installed.values()[0]
	bench.set_uninstall(true)
	crafting._refresh()
	_expect(order.worker_id<0 and _count(STONE)==1 and _count(PINE)==1, "bench removal releases every material")
	bench.set_uninstall(false)
	crafting.remove_order(id)
	# Maintain uses finished tools as spare stock, with no furniture dependency.
	id = crafting.queue_order(RECIPE_PREFIX+TOOLS[3],1,true)
	await _frames(3)
	_expect(crafting.get_order(id).lease_id<0, "maintain tool waits at spare stock target")
	var hammer: Node3D = drops.nearest_loose_of_key(TOOL_PREFIX+TOOLS[3],worker.current_cell())
	drops.take(hammer)
	hammer.free()
	for i in range(800):
		await _tick()
		if _count(TOOL_PREFIX+TOOLS[3])==1 and worker.current_task_id<0: break
	_expect(_count(TOOL_PREFIX+TOOLS[3])==1 and _count(STONE)==0 and _count(PINE)==0, "maintain replenishes one consumed tool with both ingredients")
	crafting.remove_order(id)
	# New goods use ordinary storage hauling.
	for i in range(1600):
		zone.update_leases()
		await _tick()
		if int(crafting.stock_snapshot().get(TOOL_PREFIX+TOOLS[3],{}).get("stored",0))==1: break
	_expect(int(crafting.stock_snapshot().get(TOOL_PREFIX+TOOLS[3],{}).get("stored",0))==1,"tools can be hauled into ordinary storage")
	for role in ["farmer","hunter","blacksmith"]:
		_expect(not root.get_node("DwarfAssets").profession_enabled("base:profession:"+role), "crafted tool does not activate unfinished "+role)
	await _review_tools()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STARTER_TOOLS_OK: four recipes, physical multi-material delivery, conservation, pause/save, cancel, wood rules, bench removal, maintain, storage and UI")
	quit(0 if failures.is_empty() else 1)

func _review_tools() -> void:
	dock.open_crafting()
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		await _frames(6)
		for tool in TOOLS:
			panel.select_recipe(RECIPE_PREFIX+tool)
			await _frames(3)
			_expect(not panel._place.visible, "tools never offer furniture placement")
			_expect(panel._purpose.visible and panel._purpose.text.contains("promot" if tool == "carpentry_kit" else "planned"), "tool card explains its profession's current availability")
			_expect(panel._requirements.text.contains("Rough Stone"), "tool card shows both materials")
			_expect(panel._detail_scroll.get_global_rect().encloses(panel._make.get_global_rect()), "queue tool action fits at "+str(viewport))
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tmp/starter_tools_review/%s_%d.png" % [tool,viewport.x])
	manager.close("craft")
	dock._open_inventory()
	dock._inventory_panel._set_category("tools")
	await _frames(5)
	for tool in TOOLS:
		_expect(dock._inventory_panel._tiles[TOOL_PREFIX+tool].button.is_visible_in_tree(), "inventory Tools category includes "+tool)
	manager.close("inventory")
	var director = load("res://scripts/entities/DwarfDirector.gd").new()
	director.window_manager_path = NodePath("../Windows")
	scene.add_child(director)
	director._agents.append(worker)
	director.open_professions(worker)
	var promotion = director._profession_panel
	for viewport in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size = viewport
		await _frames(6)
		for role in ["farmer","hunter","carpenter","blacksmith"]:
			promotion.select_profession("base:profession:"+role)
			await _frames(3)
			_expect(promotion._requirements.text.contains("1 available") and promotion._requirements.text.contains("crude workbench"),"profession shows owned starter tool and maker")
			_expect(promotion._promote.disabled == (role != "carpenter"),"only Carpenter promotion is enabled with its available starter tool")
			_expect(promotion.window.get_global_rect().end.y <= dock._dock_panel.position.y-8,"tool promotion card clears dock at "+str(viewport))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tmp/starter_tools_review/promotion_%d.png" % viewport.x)
	manager.close("professions")
