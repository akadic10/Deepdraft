extends "res://scripts/tests/WorkerCraftingTest.gd"

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
		_expect(panel._browser.is_visible_in_tree() and not panel._orders_view.is_visible_in_tree(),"recipe browsing hides the order list")
		_expect(panel._category_groups.size()==6 and panel._category_groups.has("Rooms"),"six recipe categories include log doors in Rooms")
		for key: String in panel._buttons:
			var button: Button = panel._buttons[key]
			_expect(button.icon!=null and button.text.is_empty() and button.size.x<=56,"compact illustrated recipe: "+key)
		_expect(panel._portrait.texture==panel._buttons[PREFIX+"campfire"].icon,"selected recipe has its own illustration")
		panel._buttons[PREFIX+"campfire"].grab_focus()
		panel.refresh()
		await _frames(3)
		_expect(panel._buttons[PREFIX+"campfire"].has_focus(),"stock updates preserve keyboard recipe focus")
		var window_rect: Rect2 = dock._craft_window.get_global_rect()
		_expect(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(window_rect) and window_rect.end.y<=dock._dock_panel.position.y-8,"craft cabinet fits viewport above dock: "+str(viewport))
		for action: Control in [panel._make,panel._place,panel._wood,panel._controls]:
			_expect(panel._detail_scroll.get_global_rect().encloses(action.get_global_rect()),"craft controls stay visible: "+str(viewport))
		await _capture_browser("recipes_%d" % viewport.x)
		dock.open_crafting(PREFIX+"hearth")
		await _frames(4)
		_expect(panel._requirements.text.contains("4 Rough Stone") and panel._requirements.text.count("Rough Stone")==1,"hearth groups repeated stone ingredients into one count")
		await _capture_browser("hearth_%d" % viewport.x)
		# Use real text input so focusing search cannot leak game hotkeys.
		_click(panel._search.get_global_rect().get_center())
		for letter in "ACCESS":
			var event := InputEventKey.new()
			event.unicode = letter.unicode_at(0)
			event.pressed = true
			Input.parse_input_event(event)
		await _frames(5)
		_expect(panel._search.text=="ACCESS" and _visible_recipes().size()==2,"case-insensitive category search finds ladder and bridge")
		_expect(panel._category_groups.Access.visible and not panel._category_groups.Lighting.visible,"search hides empty categories")
		_click(panel._buttons[PREFIX+"log_bridge"].get_global_rect().get_center())
		await _frames(4)
		_expect(panel.selected==PREFIX+"log_bridge" and panel._title.text=="Log bridge kit","clicking a search result selects its detail")
		panel._quantity.get_line_edit().text = "2"
		_click(panel._make.get_global_rect().get_center())
		await _frames(4)
		_expect(crafting.orders.size()==1 and crafting.orders[0].quantity==2,"filtered recipe queues requested batches")
		_expect(panel._orders_tab.text=="Orders (1)" and panel._browser.is_visible_in_tree(),"queue badge updates without switching away from browsing")
		panel._search.text = "no matching recipe"
		panel._search.text_changed.emit(panel._search.text)
		await _frames(4)
		panel._queue_selected()
		_expect(panel._no_results.visible and not panel._make.visible and crafting.orders.size()==1,"empty search cannot queue a hidden stale recipe")
		_click(panel._orders_tab.get_global_rect().get_center())
		await _frames(4)
		_expect(panel._orders_view.is_visible_in_tree() and not panel._browser.is_visible_in_tree(),"Orders tab reveals queue even when search is empty")
		_expect(panel._title.text=="Log bridge kit" and panel._make.visible,"recipe search does not blank the Orders detail card")
		var id: int = crafting.orders[0].id
		var row: Dictionary = panel._rows[id]
		_click(row.pause.get_global_rect().get_center())
		await _frames(4)
		_expect(crafting.get_order(id).paused and row.pause.text=="Resume","actual order pause control still works")
		_click(panel._recipes_tab.get_global_rect().get_center())
		await _frames(3)
		panel._search.text = ""
		panel._search.text_changed.emit("")
		panel.select_recipe(TORCH_RECIPE)
		panel._mode.select(1)
		panel._quantity.value = 5
		panel.refresh()
		await _frames(4)
		_click(panel._make.get_global_rect().get_center())
		await _frames(3)
		_expect(crafting.orders.size()==2 and crafting.orders[1].maintain and crafting.orders[1].quantity==5,"stock target preserves its units")
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
		_expect(crafting.orders[0].maintain,"order priority can be changed from Orders tab")
		var stable_row: Control = panel._rows[id].root
		panel.refresh()
		await _frames(3)
		_expect(panel._rows[id].root==stable_row and panel._show_orders,"stock refresh keeps order rows and current tab stable")
		panel._queue_scroll.scroll_vertical = 0
		await _frames(4)
		await _capture_browser("orders_%d" % viewport.x)
		var order_id: int = crafting.orders[0].id
		var controls: HBoxContainer = panel._rows[order_id].pause.get_parent()
		_click(controls.get_child(3).get_global_rect().get_center())
		await _frames(3)
		_expect(crafting.get_order(order_id)==null and panel._orders_tab.text=="Orders (1)","cancel removes only its order and updates badge")
		crafting.remove_order(id)
		panel._mode.select(0)
		panel._quantity.value = 1
		panel.select_section("carpenter")
		await _frames(6)
		_expect(not panel._tabs.visible and not panel._make.visible and panel._planned_list.visible,"planned professions remain preview-only")
		panel.select_section("rudimentary")
		await _frames(6)
		_expect(panel.selected==TORCH_RECIPE and _visible_recipes().size()==crafting.recipes.size(),"returning restores selection and clears search")
	for failure in failures: push_error(failure)
	print("CRAFTING_BROWSER_OK: categories, search, details, batch/maintain, order controls and three viewport sizes" if failures.is_empty() else "CRAFTING_BROWSER_FAIL")
	quit(0 if failures.is_empty() else 1)

func _visible_recipes() -> Array[String]:
	var ids: Array[String] = []
	for key: String in panel._buttons:
		if panel._buttons[key].is_visible_in_tree(): ids.append(key)
	return ids

func _capture_browser(capture_name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(CAPTURES+capture_name+".png")
