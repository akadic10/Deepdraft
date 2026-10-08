extends MarginContainer

## Recipes, live stock and stable order rows. CraftingManager owns all work.
signal place_requested(furniture_key: String)
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
var controller: Node
var window: UIWindow
var selected := ""
var _recipes: VBoxContainer
var _buttons := {}
var _rows := {}
var _queue: VBoxContainer
var _queue_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _title: Label
var _description: Label
var _requirements: Label
var _stock: Label
var _wood: MenuButton
var _draft_ingredients := {}
var _mode: OptionButton
var _quantity: SpinBox
var _make: Button
var _place: Button
var _empty: Label
var _queue_title: Label
var _hint: Label
var _detail: VBoxContainer
var _dock_top := 600.0

func _ready() -> void:
	UITheme.apply_surface(self)
	for side in ["left","right","top","bottom"]: add_theme_constant_override("margin_"+side,10)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	add_child(body)
	body.add_child(_label("Every Worker can craft. No promotion needed.",13))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	body.add_child(columns)
	_recipes = VBoxContainer.new()
	_recipes.custom_minimum_size.x = 148
	columns.add_child(_recipes)
	_recipes.add_child(_label("RECIPES",12))
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.custom_minimum_size.x = 260
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.mouse_force_pass_scroll_events = false
	columns.add_child(_detail_scroll)
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.add_theme_stylebox_override("panel",UITheme.catalog_paper_style(true))
	_detail_scroll.add_child(paper)
	var detail := VBoxContainer.new()
	_detail = detail
	detail.add_theme_constant_override("separation",10)
	paper.add_child(detail)
	_title = _label("",21,true,true)
	detail.add_child(_title)
	_description = _label("",13,false,true)
	detail.add_child(_description)
	_requirements = _label("",13,false,true)
	detail.add_child(_requirements)
	_wood = _make_wood_menu()
	detail.add_child(_wood)
	_stock = _label("",13,false,true)
	detail.add_child(_stock)
	var controls := HBoxContainer.new()
	detail.add_child(controls)
	_mode = OptionButton.new()
	_mode.add_item("Make batches")
	_mode.add_item("Keep in stock")
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode.item_selected.connect(func(_index: int): refresh())
	controls.add_child(_mode)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 99
	_quantity.value = 1
	_quantity.custom_minimum_size.x = 72
	_quantity.get_line_edit().add_theme_stylebox_override("normal",UITheme.style(UITheme.HEARTH_CARD,UITheme.HEARTH_EDGE,1,3))
	_quantity.value_changed.connect(func(_value: float): refresh())
	controls.add_child(_quantity)
	_make = Button.new()
	UITheme.apply_catalog_primary(_make)
	_make.pressed.connect(_queue_selected)
	detail.add_child(_make)
	_place = UITheme.make_button("Place finished item", "Open placement for this recipe's finished goods",Vector2(0,30))
	_place.pressed.connect(func(): place_requested.emit(String(controller.recipes[selected].furniture)))
	detail.add_child(_place)
	var queue_column := VBoxContainer.new()
	queue_column.custom_minimum_size.x = 236
	columns.add_child(queue_column)
	_queue_title = _label("ORDERS",12)
	queue_column.add_child(_queue_title)
	_queue_scroll = ScrollContainer.new()
	_queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_queue_scroll.mouse_force_pass_scroll_events = false
	_queue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_column.add_child(_queue_scroll)
	_queue = VBoxContainer.new()
	_queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue.add_theme_constant_override("separation",8)
	_queue_scroll.add_child(_queue)
	_empty = _label("No orders yet.\n\nStart with a crude workbench, then place it from colony stores.",13)
	_empty.custom_minimum_size.x = 212
	_queue.add_child(_empty)
	_hint = _label("Finished goods go to colony stores. Place torches on tunnel walls.",12)
	body.add_child(_hint)
	visibility_changed.connect(refresh)

func bind_controller(value: Node) -> void:
	controller = value
	controller.changed.connect(refresh)
	for recipe: Dictionary in controller.recipes.values():
		var button := Button.new()
		button.custom_minimum_size = Vector2(148,110)
		button.toggle_mode = true
		button.add_theme_stylebox_override("normal",UITheme.catalog_item_style())
		button.add_theme_stylebox_override("hover",UITheme.catalog_item_style(true))
		button.add_theme_stylebox_override("pressed",UITheme.catalog_item_style(true))
		button.text = String(recipe.name)
		button.add_theme_font_size_override("font_size",13)
		var path := "res://assets/ui/furniture/%s.png" % String(recipe.furniture).get_slice(":",2)
		if ResourceLoader.exists(path): button.icon = load(path)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",104)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.pressed.connect(select_recipe.bind(String(recipe.id)))
		_recipes.add_child(button)
		_buttons[String(recipe.id)] = button
	if not controller.recipes.is_empty(): select_recipe(controller.recipes.keys()[0])

func select_recipe(key: String) -> void:
	if controller == null or not controller.recipes.has(key): return
	selected = key
	if not _draft_ingredients.has(key):
		_draft_ingredients[key] = controller.allowed_ingredient_keys(controller.recipes[key])
	refresh()

func _queue_selected() -> void:
	if selected.is_empty(): return
	_quantity.apply()
	if _draft_ingredients[selected].is_empty(): return
	controller.queue_order(selected,int(_quantity.value),_mode.selected == 1,_draft_ingredients[selected])
	refresh()

func refresh() -> void:
	if controller == null or selected.is_empty() or not is_visible_in_tree(): return
	var recipe: Dictionary = controller.recipes[selected]
	var totals := Inventory.snapshot(controller.items,controller.furniture)
	for key: String in _buttons: _buttons[key].set_pressed_no_signal(key == selected)
	_title.text = String(recipe.name)
	_description.text = String(recipe.description)
	var bench := "No workbench needed" if String(recipe.workshop).is_empty() else "Requires a placed crude workbench"
	var allowed: Array = _draft_ingredients[selected]
	_requirements.text = "1 timber · %d allowed logs available\nMakes %d · %.0f seconds\n%s" % [controller.ingredient_available(recipe,totals,allowed),int(recipe.output_count),float(recipe.work_seconds),bench]
	_update_wood_menu(_wood,allowed,totals,true)
	var ready := int(totals.get(String(recipe.output),{}).get("available",0))
	_stock.text = "%d ready to place" % ready
	var amount := int(_quantity.value)
	var output_count := amount*int(recipe.output_count)
	var output_name := String(recipe.name).to_lower() if output_count==1 else String(recipe.get("output_plural",recipe.name))
	_make.text = "Queue %d %s" % [output_count,output_name] if _mode.selected==0 else "Keep %d in stock" % amount
	_make.disabled = allowed.is_empty() or controller.orders.size() >= controller.max_orders
	_make.tooltip_text = "The order waits if timber or a workbench is missing." if _mode.selected==0 else "Replenish spare items in batches of %d. Installed and reserved items do not count." % int(recipe.output_count)
	_place.disabled = ready < 1
	_refresh_orders(totals)

func _refresh_orders(totals: Dictionary) -> void:
	var ids: Array[int] = []
	for order in controller.orders: ids.append(order.id)
	for id: int in _rows.keys():
		if id not in ids:
			_rows[id].root.queue_free()
			_queue.remove_child(_rows[id].root)
			_rows.erase(id)
	for order in controller.orders:
		if not _rows.has(order.id): _add_order(order.id)
		var row: Dictionary = _rows[order.id]
		_queue.move_child(row.root,ids.find(order.id)+1)
		row.title.text = String(order.recipe.name)
		row.quantity.text = "Keep %d spare" % order.quantity if order.maintain else "%d batch%s · %d remaining" % [order.quantity,"" if order.quantity==1 else "es",order.quantity*int(order.recipe.output_count)]
		row.status.text = controller.status(order,totals)
		_update_wood_menu(row.wood,order.allowed_ingredients,totals)
		row.pause.text = "Resume" if order.paused else "Pause"
		row.up.disabled = ids.front()==order.id or order.worker_id>=0
		row.down.disabled = ids.back()==order.id or order.worker_id>=0
	_empty.visible = ids.is_empty()
	_queue_title.text = "ORDERS (%d)" % ids.size()

func _add_order(id: int) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(8))
	_queue.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := _label("",16,true)
	box.add_child(title)
	var quantity := _label("",12)
	box.add_child(quantity)
	var status := _label("",12)
	box.add_child(status)
	var wood := _make_wood_menu(id)
	box.add_child(wood)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	var pause := UITheme.make_button("Pause","Pause without losing completed work",Vector2(60,26))
	pause.add_theme_font_size_override("font_size",12)
	pause.pressed.connect(func():
		var order = controller.get_order(id)
		if order != null: controller.set_paused(id,not order.paused))
	controls.add_child(pause)
	var up := UITheme.make_button("↑","Move earlier",Vector2(26,26))
	up.pressed.connect(func(): controller.move_order(id,-1))
	controls.add_child(up)
	var down := UITheme.make_button("↓","Move later",Vector2(26,26))
	down.pressed.connect(func(): controller.move_order(id,1))
	controls.add_child(down)
	var cancel := UITheme.make_button("×","Cancel order and return its timber",Vector2(26,26))
	cancel.pressed.connect(func(): controller.remove_order(id))
	controls.add_child(cancel)
	_rows[id] = {"root":panel,"title":title,"quantity":quantity,"status":status,"wood":wood,"pause":pause,"up":up,"down":down}

func _make_wood_menu(order_id := -1) -> MenuButton:
	var button := MenuButton.new()
	button.flat = false
	button.clip_text = true
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size",12)
	button.theme = UITheme.shared_theme().duplicate()
	button.theme.set_stylebox("panel","PopupMenu",UITheme.hearth_panel(8))
	button.theme.set_stylebox("hover","PopupMenu",UITheme.button_hover_style())
	button.theme.set_color("font_color","PopupMenu",UITheme.HEARTH_TEXT)
	button.theme.set_color("font_hover_color","PopupMenu",UITheme.HEARTH_TEXT)
	var popup := button.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.about_to_popup.connect(func(): _open_wood_menu(button,order_id))
	popup.id_pressed.connect(func(index: int): _toggle_wood(button,index,order_id))
	return button

func _open_wood_menu(button: MenuButton, order_id: int) -> void:
	var order = controller.get_order(order_id) if order_id>=0 else null
	if order_id>=0 and order==null: return
	var recipe: Dictionary = order.recipe if order!=null else controller.recipes[selected]
	var allowed: Array = order.allowed_ingredients if order!=null else _draft_ingredients[selected]
	var popup := button.get_popup()
	popup.clear()
	# Put the recipe default first; this is a checklist, not a preference order.
	var keys: Array = controller.allowed_ingredient_keys(recipe)
	for key in controller.ingredient_keys(recipe):
		if key not in keys: keys.append(key)
	for key: String in keys:
		popup.add_check_item(controller.ingredient_label(key))
		popup.set_item_metadata(popup.item_count-1,key)
	_update_wood_menu(button,allowed,controller.stock_snapshot(),order_id<0)

func _toggle_wood(button: MenuButton, index: int, order_id: int) -> void:
	var order = controller.get_order(order_id) if order_id>=0 else null
	if order_id>=0 and order==null: return
	var keys: Array = (order.allowed_ingredients if order!=null else _draft_ingredients[selected]).duplicate()
	var key := String(button.get_popup().get_item_metadata(index))
	if key in keys: keys.erase(key)
	else: keys.append(key)
	if order!=null: controller.set_allowed_ingredients(order_id,keys)
	else: _draft_ingredients[selected] = controller.allowed_ingredient_keys(controller.recipes[selected],keys)
	refresh()

func _update_wood_menu(button: MenuButton, keys: Array, totals: Dictionary, draft := false) -> void:
	var names: String = controller.ingredient_summary(keys)
	var caption := "Choose…" if keys.is_empty() else names
	if keys.size()>2: caption = "%s + %d" % [controller.ingredient_label(keys[0]),keys.size()-1]
	button.text = ("Allowed wood: " if draft else "Wood: ") + caption + " ▾"
	button.tooltip_text = "Allowed wood: %s. Other wood is never substituted." % ("none" if keys.is_empty() else names)
	var popup := button.get_popup()
	for index in range(popup.item_count):
		var key := String(popup.get_item_metadata(index))
		popup.set_item_checked(index,key in keys)
		popup.set_item_text(index,"%s · %d available" % [controller.ingredient_label(key),int(totals.get(key,{}).get("available",0))])

func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()

func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	var compact := viewport.y < 650
	_hint.visible = not compact
	_description.visible = not compact
	_detail.add_theme_constant_override("separation",6 if compact else 10)
	_title.add_theme_font_size_override("font_size",18 if compact else 21)
	custom_minimum_size.x = minf(790,viewport.x-48)
	_detail_scroll.custom_minimum_size.y = clampf(_dock_top-150,260,440)
	window.reset_size()
	window.clamp_to_viewport()

func _label(value: String, size: int, heading := false, paper := false) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	if heading: UITheme.apply_title(label,size)
	if paper: label.add_theme_color_override("font_color",UITheme.CATALOG_INK)
	return label
