extends "res://scripts/tests/WorkerCraftingTest.gd"

## The crafting window (doc 261, phase 2) at three screen sizes: the recipes as a grouped
## picture grid with ready and missing states, the chosen recipe on the pine board with
## its ingredients as pictures and its flavour line, Make or Keep with one Queue button,
## the queue beside them or folded into Orders, the Crafters row and the planned crafts.
## Where the screen has the room, every recipe's board shows whole, without scrolling.
const PREFIX := "base:recipe:worker:"
const CAPTURES := "res://tmp/crafting_browser_20261011/"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Crafting browser timed out"); quit(1))
	await _setup_crafting_fixture()
	clock_node.set_paused(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	for viewport in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(960,540)]:
		root.size = viewport
		dock.open_crafting(PREFIX+"campfire")
		await _frames(10)
		var folded: bool = viewport.x < 1200 or viewport.y < 650
		_expect(panel._folded==folded and panel._right.visible!=folded and panel._tabs.visible==folded,"the queue folds into an Orders tab only on small screens: "+str(viewport))
		_expect(panel._recipe_scroll.is_visible_in_tree() and panel._queue_scroll.is_visible_in_tree()!=folded,"recipes show, with the queue beside them unless folded")
		var categories := _categories()
		_expect(categories.size()==7 and categories.has("Rooms") and categories.has("Recreation"),"seven recipe categories include room furnishings and recreation")
		for key: String in crafting.recipes:
			var tile: Button = panel._recipes.get_tile(key)
			_expect(tile!=null and tile.icon!=null and tile.text.is_empty(),"illustrated recipe tile: "+key)
		var campfire: Button = panel._recipes.get_tile(PREFIX+"campfire")
		_expect(campfire.has_node("Selected") and panel._picture.texture==campfire.icon and panel._title.text=="Campfire","the chosen recipe is ringed and shown on the board")
		_expect(campfire.has_node("Mark") and panel._recipes.get_tile(PREFIX+"crude_workbench").has_node("Mark"),"with no timber in the colony every recipe is missing something")
		_expect(panel._chips.time.label.text=="10 s" and panel._chips.makes.label.text=="Makes 1","badges give the work time and the yield")
		_expect(panel._flavour.text=="\"Stones in a ring, logs in the middle, stories all around.\"","the recipe's flavour line shows")
		_expect(panel._ingredients_heading.text=="INGREDIENTS · 1 timber · 1 Rough Stone" and panel._woods.get_tile(PINE)!=null
			and panel._woods.get_tile("extra:base:resources:stone:rough_stone")!=null,"ingredients are pictures: the woods, then the stone")
		_expect(_tag_texts().has("Needs a free crude workbench") and _tag_texts().has("✓ Any Worker"),"tags say what the recipe needs")
		campfire.grab_focus()
		panel.refresh()
		await _frames(3)
		_expect(panel._recipes.get_tile(PREFIX+"campfire").has_focus(),"stock updates preserve keyboard recipe focus")
		var window_rect: Rect2 = dock._craft_window.get_global_rect()
		_expect(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(window_rect) and window_rect.end.y<=dock._dock_panel.position.y-8,"crafting fits the screen above the dock: %s (window %s)" % [viewport,window_rect])
		for action: Control in [panel._queue_button,panel._make_row.more,panel._keep_row.choose]:
			_expect(action.is_visible_in_tree() and window_rect.encloses(action.get_global_rect()),"order controls stay in view: %s (%s)" % [viewport,action.get_global_rect()])
		await _capture_browser("recipes_%d" % viewport.x)
		if viewport.y >= 1080: await _expect_boards_fit(viewport)
		dock.open_crafting(PREFIX+"hearth")
		await _frames(4)
		_expect(panel._requirements.text.contains("4 Rough Stone") and panel._requirements.text.count("Rough Stone")==1,"hearth groups repeated stone ingredients into one count")
		await _capture_browser("hearth_%d" % viewport.x)
		panel.select_recipe(PREFIX+"stone_hoe")
		await _frames(2)
		var hoe: Dictionary = crafting.recipes[PREFIX+"stone_hoe"]
		_expect(panel._description.text.ends_with(String(hoe.purpose_short if viewport.y < 650 else hoe.purpose)),"small screens take the recipe's short purpose")
		# Use real text input so focusing search cannot leak game hotkeys.
		_click(panel._search.get_global_rect().get_center())
		for letter in "ACCESS":
			var event := InputEventKey.new()
			event.unicode = letter.unicode_at(0)
			event.pressed = true
			Input.parse_input_event(event)
		await _frames(5)
		_expect(panel._search.text=="ACCESS" and _visible_recipes().size()==4,"case-insensitive category search finds ladder, bridge, fence and gate")
		_expect(_categories()==["Access"],"search hides empty categories")
		_click(panel._recipes.get_tile(PREFIX+"log_bridge").get_global_rect().get_center())
		await _frames(4)
		_expect(panel.selected==PREFIX+"log_bridge" and panel._title.text=="Log bridge kit","clicking a search result selects its board")
		_click(panel._make_row.more.get_global_rect().get_center())
		await _frames(2)
		_click(panel._queue_button.get_global_rect().get_center())
		await _frames(4)
		_expect(panel.make_count==2 and crafting.orders.size()==1 and crafting.orders[0].quantity==2,"filtered recipe queues requested batches")
		_expect(panel._orders_tab.text=="Orders (1)" and panel._queue_heading.text=="QUEUE · 1 order" and panel._recipe_scroll.is_visible_in_tree(),"the queue count updates without leaving the recipes")
		panel._search.text = "no matching recipe"
		panel._search.text_changed.emit(panel._search.text)
		await _frames(4)
		panel._queue_selected()
		_expect(panel._no_results.visible and not panel._queue_button.is_visible_in_tree() and crafting.orders.size()==1,"empty search cannot queue a hidden stale recipe")
		if folded:
			_click(panel._orders_tab.get_global_rect().get_center())
			await _frames(4)
			_expect(panel._queue_scroll.is_visible_in_tree() and not panel._recipe_scroll.is_visible_in_tree(),"Orders tab reveals the queue even when search is empty")
			_expect(panel._title.text=="Log bridge kit" and panel._queue_button.is_visible_in_tree(),"recipe search does not blank the board behind the Orders tab")
		var id: int = crafting.orders[0].id
		var row: Dictionary = panel._rows[id]
		_expect(row.title.text=="Log bridge kit ×2" and row.status.text.begins_with("Waiting"),"an order row names the item, how many and its status")
		_click(row.pause.get_global_rect().get_center())
		await _frames(4)
		_expect(crafting.get_order(id).paused and row.pause.text=="Resume" and row.tag.get_theme_stylebox("panel")==UITheme.cell_style("tag_blocked", 2),"pausing an order shows it on a rust tag")
		if folded:
			_click(panel._recipes_tab.get_global_rect().get_center())
			await _frames(3)
		panel._search.text = ""
		panel._search.text_changed.emit("")
		panel.select_recipe(TORCH_RECIPE)
		_click(panel._keep_row.choose.get_global_rect().get_center())
		for i in range(4): _click(panel._keep_row.more.get_global_rect().get_center())
		await _frames(4)
		_click(panel._queue_button.get_global_rect().get_center())
		await _frames(3)
		_expect(panel.maintain and crafting.orders.size()==2 and crafting.orders[1].maintain and crafting.orders[1].quantity==5,"Keep in stock preserves its units")
		_expect(panel._keep_row.mark.text=="◆" and panel._make_row.mark.text=="◇","the chosen order kind is marked")
		if folded:
			_click(panel._orders_tab.get_global_rect().get_center())
			await _frames(5)
		panel._queue_scroll.ensure_control_visible(panel._rows[crafting.orders[1].id].root)
		await _frames(4)
		var scroll_before: int = panel._queue_scroll.scroll_vertical
		panel.refresh()
		await _frames(4)
		_expect(panel._queue_scroll.scroll_vertical==scroll_before,"live stock updates preserve queue scroll position")
		_click(panel._rows[crafting.orders[1].id].up.get_global_rect().get_center())
		await _frames(3)
		_expect(crafting.orders[0].maintain,"order priority can be changed from the queue")
		var stable_row: Control = panel._rows[id].root
		panel.refresh()
		await _frames(3)
		_expect(panel._rows[id].root==stable_row and panel._show_orders==folded,"stock refresh keeps order rows and the current tab stable")
		panel._queue_scroll.scroll_vertical = 0
		await _frames(4)
		await _capture_browser("orders_%d" % viewport.x)
		var order_id: int = crafting.orders[0].id
		_click(panel._rows[order_id].cancel.get_global_rect().get_center())
		await _frames(3)
		_expect(crafting.get_order(order_id)==null and panel._orders_tab.text=="Orders (1)","cancel removes only its order and updates the count")
		crafting.remove_order(id)
		panel.maintain = false
		panel.make_count = 1
		panel.keep_count = 1
		_click(panel._crafter_tiles.carpenter.get_global_rect().get_center())
		await _frames(6)
		_expect(panel.section_id=="carpenter" and not panel._tabs.visible and not panel._queue_button.is_visible_in_tree() and panel._planned.visible,"planned professions remain preview-only")
		_click(panel._crafter_tiles.rudimentary.get_global_rect().get_center())
		await _frames(6)
		_expect(panel.selected==TORCH_RECIPE and _visible_recipes().size()==crafting.recipes.size(),"returning restores selection and clears search")
	# The large size, as on the 7680×2160 screen: the campfire needs a second row of
	# ingredients and still shows whole.
	root.size = Vector2i(2560,1440)
	dock.open_crafting(PREFIX+"campfire")
	await _frames(10)
	_expect(panel._size==panel.SIZES.large,"1440 px tall takes the large size")
	await _expect_boards_fit(root.size)
	# A recipe turns ready when its materials are in the colony: the bench needs only timber.
	drops.spawn_drop(PINE,3,Vector3i(50,21,41))
	panel.refresh()
	await _frames(3)
	_expect(not panel._recipes.get_tile(BENCH_RECIPE).has_node("Mark") and panel._recipes.get_tile(TORCH_RECIPE).has_node("Mark"),"timber readies the bench, while the torch still waits for a workbench")
	for failure in failures: push_error(failure)
	print("CRAFTING_BROWSER_OK: picture grid, board, ingredients, Make/Keep, queue, Crafters row and three screen sizes" if failures.is_empty() else "CRAFTING_BROWSER_FAIL")
	quit(0 if failures.is_empty() else 1)

## Every recipe's board shows whole, with no scrollbar, and gives its description once.
func _expect_boards_fit(viewport: Vector2i) -> void:
	for key: String in crafting.recipes:
		panel.select_recipe(key)
		await _frames(2)
		var room: float = panel._card_scroll.size.y
		_expect(not panel._card_scroll.get_v_scroll_bar().visible and panel._card.size.y<=room+0.5,"%s: the %s board shows whole (needs %d px, has %d)" % [viewport,key,int(panel._card.get_combined_minimum_size().y),int(room)])
		_expect(panel._description.text.count(String(crafting.recipes[key].description))==1,"the board gives its description once: "+key)

func _visible_recipes() -> Array[String]:
	var ids: Array[String] = []
	for key: String in crafting.recipes:
		var tile: Button = panel._recipes.get_tile(key)
		if tile!=null and tile.is_visible_in_tree(): ids.append(key)
	return ids

func _categories() -> Array[String]:
	var found: Array[String] = []
	for key: String in _visible_recipes():
		var category := String(crafting.recipes[key].get("category","Recipes"))
		if category not in found: found.append(category)
	return found

func _tag_texts() -> Array[String]:
	var texts: Array[String] = []
	for tag: Node in panel._tags.get_children(): texts.append((tag.get_child(0) as Label).text)
	return texts

func _capture_browser(capture_name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(CAPTURES+capture_name+".png")
