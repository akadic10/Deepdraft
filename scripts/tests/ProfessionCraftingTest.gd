extends "res://scripts/tests/WorkerCraftingTest.gd"

const CAMP := "base:furniture:campfire"
const LOG_CHAIR := "base:furniture:log_chair"
const RECIPE := "base:recipe:worker:"
const ITEM := "base:resources:furniture:"
const OUT := "res://tmp/profession_crafting_review/"

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Profession crafting timed out"); quit(1))
	await _setup_crafting_fixture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# A valid furniture definition alone is not enough: the player-facing Place
	# catalog must expose every furniture item that Workers can actually craft.
	for recipe: Dictionary in crafting.recipes.values():
		var key := String(recipe.get("furniture",""))
		if not key.is_empty():
			_expect(dock._place_catalog._tiles.has(key),"craftable furniture appears in Place catalog: "+key)
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	# Camp goods require the real bench and consume physical material deliveries.
	var id: int = crafting.queue_order(RECIPE+"campfire",1)
	drops.spawn_drop(PINE,2,Vector3i(42,21,42))
	await _frames(2)
	_expect(crafting.status(crafting.get_order(id),crafting.stock_snapshot())=="Waiting for Rough Stone","campfire cannot be made from wood alone")
	drops.spawn_drop(STONE,1,Vector3i(44,21,44))
	await _frames(2)
	_expect(crafting.get_order(id).lease_id<0,"campfire waits for crude workbench")
	furniture._install(BENCH,furniture.get_defs()[BENCH],Vector3i(45,20,42),0)
	_expect(await _completed(id),"campfire completes through normal material hauling and crafting")
	_expect(_count(ITEM+"campfire")==1 and _count(PINE)==1 and _count(STONE)==0,"campfire costs exactly one log and one stone")
	id = crafting.queue_order(RECIPE+"log_chair",1)
	_expect(await _completed(id),"log chair completes through Worker crafting")
	_expect(_count(ITEM+"log_chair")==1 and _count(PINE)==0,"log chair costs exactly one log")
	# Exercise Craft -> Place as well as the regular Place catalog. Neither path
	# should silently lose a newly craftable design because its UI entry is absent.
	dock.open_crafting(RECIPE+"campfire")
	await _frames(8)
	_click(panel._place.get_global_rect().get_center())
	await _frames(6)
	_expect(manager.is_open("place") and furniture.active_furniture_key()==CAMP and dock._place_catalog.selected_key==CAMP,"Craft Place finished item opens the campfire preview and detail")
	furniture.deactivate()
	manager.close("place")
	for entry in [[CAMP,Vector3i(48,20,46)],[LOG_CHAIR,Vector3i(48,20,42)]]:
		clock_node.set_paused(true)
		dock._place_catalog.show_all = false
		dock._place_catalog._all_toggle.set_pressed_no_signal(false)
		dock._place_catalog.category = "all"
		_click(dock._button_by_target.place.get_global_rect().get_center())
		await _frames(8)
		var catalog = dock._place_catalog
		_expect(catalog._tiles[entry[0]].button.is_visible_in_tree() and catalog._tiles[entry[0]].count.text=="1","finished "+entry[0]+" appears in normal Place while paused")
		var category_key := "lighting" if entry[0]==CAMP else "dining"
		_click(catalog._tabs[category_key].get_global_rect().get_center())
		await _frames(6)
		_expect(catalog._tiles[entry[0]].button.is_visible_in_tree(),"new furniture appears in its Place category")
		_click(catalog._tiles[entry[0]].button.get_global_rect().get_center())
		await _frames(4)
		_expect(furniture.active_furniture_key()==entry[0] and not catalog._place.disabled,"clicking the actual catalog tile enables placement")
		if "--capture" in OS.get_cmdline_user_args(): await _capture_camp("place_"+String(entry[0]).get_slice(":",2))
		furniture._yaw = 0
		furniture._hover_cell = entry[1]
		_expect(furniture._placement_valid(entry[1]),"camp furniture accepts clear supported ground")
		furniture._confirm_ghost()
		furniture.deactivate()
		manager.close("place")
		clock_node.set_paused(false)
		_expect(await _installed(entry[0]),"worker installs crafted "+entry[0])
	_expect(_count(ITEM+"campfire")==0 and _count(ITEM+"log_chair")==0,"installation consumes packed goods exactly once")
	var fire = _piece(CAMP)
	var animation = fire.node.get_node_or_null("FlameAnimation")
	_expect(animation!=null and animation._frames.size()==8,"installed campfire has eight animated flame frames")
	_expect(fire.node.get_node_or_null("FurnitureLight")!=null,"campfire has local warm light")
	if animation!=null:
		var old_frame: int = animation._frame_index
		animation._process(.15)
		_expect(animation._frame_index!=old_frame,"campfire flame changes shape")
	var seating = load("res://scripts/components/FurnitureSeating.gd")
	_expect(seating.is_chair(furniture.get_defs()[LOG_CHAIR]),"log chair participates in existing seating rules")
	worker._idle_behavior.cancel()
	worker.position = Vector3(46.5,21,41.5)
	worker._idle_behavior.config = tasks.get_config_section("idle").duplicate(true)
	worker._idle_behavior.config.start_delay_min_s = .1
	worker._idle_behavior.config.start_delay_max_s = .1
	worker._idle_behavior.config.seat_chance = 1.0
	for i in range(180):
		worker._process(.1)
		if worker._idle_behavior.state=="sitting": break
		await process_frame
	worker._process(1)
	_expect(worker._idle_behavior.state=="sitting" and _piece(LOG_CHAIR).idle_seat_owner==worker.dwarf_id,"idle worker reaches and occupies crafted log chair")
	if "--capture" in OS.get_cmdline_user_args():
		camera.size = 12
		camera.position = Vector3(58,30,56)
		camera.look_at(Vector3(49,22,45))
		await _capture_camp("camp_seating")
	worker._idle_behavior.cancel()
	# Installed identities reconstruct through the normal furniture save owner.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(furniture.serialize_state()))
	for installed_id in furniture._installed.keys(): furniture.dev_remove_installed(installed_id)
	# Development removal refunds packed goods; loading an installed-only save
	# must start without those temporary refunds.
	for node in drops._loose.keys():
		if drops.item_key_of(node) in [BENCH_ITEM,ITEM+"campfire",ITEM+"log_chair"]:
			drops.take(node)
			node.free()
	furniture.restore_state(saved)
	await _frames(3)
	_expect(_piece(CAMP)!=null and _piece(LOG_CHAIR)!=null,"camp furniture survives JSON restore")
	_expect(_count(ITEM+"campfire")==0 and _count(ITEM+"log_chair")==0,"restoring installed furniture does not duplicate packed goods")
	_expect(_piece(CAMP).node.get_node_or_null("FlameAnimation")!=null and _piece(LOG_CHAIR).idle_seat_owner<0,"restored light runs and transient chair claim is clear")
	await _review_menu()
	for failure in failures: push_error(failure)
	print("PROFESSION_CRAFTING_OK: professions, previews, camp recipes, physical costs, placement, fire animation, seating, save/load and compact menu" if failures.is_empty() else "PROFESSION_CRAFTING_FAIL")
	quit(0 if failures.is_empty() else 1)

func _piece(key: String):
	for piece in furniture._installed.values():
		if piece.furniture_key==key: return piece
	return null

func _review_menu() -> void:
	dock.open_crafting(RECIPE+"campfire")
	for viewport in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		await _frames(8)
		_click(dock._button_by_target.craft.get_global_rect().get_center())
		await _frames(8)
		_expect(dock.is_action_menu_open() and dock._active_panel_target=="craft" and not manager.is_open("craft"),"Craft opens the profession submenu before any recipe window")
		_expect(dock._button_by_target.craft.button_pressed,"Craft remains highlighted while choosing a profession")
		_expect(dock._panel_body.get_child_count()==crafting.sections.size(),"every profession has its own submenu button")
		var menu_rect: Rect2 = dock._panel_container.get_global_rect()
		_expect(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(menu_rect) and menu_rect.end.y<=dock._dock_panel.position.y-8,"profession submenu fits above the dock")
		_expect(dock._panel_body.columns==(10 if viewport.x==1280 else 5),"desktop profession row wraps into balanced compact rows")
		for button in dock._panel_body.get_children():
			_expect(not button.disabled and button.icon!=null and dock._panel_scroll.get_global_rect().encloses(button.get_global_rect()),"profession button is visible and clickable: "+button.name)
		if "--capture" in OS.get_cmdline_user_args(): await _capture_camp("crafters_%d" % viewport.x)
		_click(dock._panel_body.get_node("CrafterRudimentary").get_global_rect().get_center())
		await _frames(8)
		_expect(manager.is_open("craft") and not dock.is_action_menu_open() and panel.section_id=="rudimentary","Rudimentary button opens its recipe menu")
		for recipe in ["campfire","log_chair","stone_hoe","wooden_torch"]:
			panel.select_recipe(RECIPE+recipe)
			await _frames(4)
			var rect: Rect2 = dock._craft_window.get_global_rect()
			_expect(rect.end.x<=viewport.x and rect.end.y<=dock._dock_panel.position.y-8,"craft menu fits above dock at "+str(viewport))
			_expect(panel._detail_scroll.get_global_rect().encloses(panel._make.get_global_rect()),"queue action stays visible for "+recipe+str(viewport))
			if panel._place.visible:
				_expect(panel._detail_scroll.get_global_rect().encloses(panel._place.get_global_rect()),"place action stays visible for "+recipe+str(viewport))
		panel._quantity.get_line_edit().text = "2"
		_click(panel._make.get_global_rect().get_center())
		await _frames(3)
		_expect(crafting.orders.size()==1 and crafting.orders[0].quantity==2,"existing recipe still queues from menu")
		var order_id: int = crafting.orders[0].id
		for key: String in crafting.sections:
			if key=="rudimentary": continue
			await _choose_crafter(key)
			_expect(dock._craft_window.get_global_rect().end.y<=dock._dock_panel.position.y-8,"preview fits above dock for "+key+str(viewport))
			panel._queue_selected()
			_expect(panel.selected.is_empty() and not panel._make.visible and not panel._place.visible,"preview cannot queue or place fictitious "+key+" goods")
			_expect(crafting.orders.size()==1 and not panel._rows.has(order_id),"Worker order is retained without appearing in "+key+" orders")
		await _choose_crafter("carpenter")
		await _frames(3)
		if "--capture" in OS.get_cmdline_user_args(): await _capture_camp("carpenter_%d" % viewport.x)
		await _choose_crafter("rudimentary")
		_expect(panel.selected==RECIPE+"wooden_torch","returning remembers previous real recipe")
		_expect(panel._rows.has(order_id),"returning to Rudimentary restores its real order controls")
		await _choose_crafter("miner")
		dock.open_crafting(RECIPE+"campfire")
		await _frames(3)
		_expect(panel.section_id=="rudimentary" and panel.selected==RECIPE+"campfire","recipe deep link returns from preview to usable section")
		if "--capture" in OS.get_cmdline_user_args(): await _capture_camp("rudimentary_%d" % viewport.x)
		crafting.remove_order(order_id)
		# Both the submenu and recipe view support ordinary Escape/toggle dismissal.
		_click(panel._crafters.get_global_rect().get_center())
		await _frames(5)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		await _frames(3)
		_expect(not dock.is_action_menu_open() and not dock._button_by_target.craft.button_pressed,"Escape closes the profession submenu and its highlight")
		dock.open_crafting(RECIPE+"campfire")
		await _frames(4)

func _choose_crafter(key: String) -> void:
	_click(panel._crafters.get_global_rect().get_center())
	await _frames(5)
	_expect(dock.is_action_menu_open() and not manager.is_open("craft"),"Crafters back button returns to the profession submenu")
	var button: Button = dock._panel_body.get_node("Crafter"+key.to_pascal_case())
	_click(button.get_global_rect().get_center())
	await _frames(6)
	_expect(manager.is_open("craft") and panel.section_id==key and not dock.is_action_menu_open(),"profession button opens the correct menu: "+key)

func _capture_camp(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
