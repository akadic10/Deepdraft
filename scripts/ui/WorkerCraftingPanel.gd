extends MarginContainer

## The crafting window (doc 261, phase 2), built around the item and its ingredients:
## - the profession on top, with the Crafters row to switch between professions;
## - the recipes as one grouped picture grid: ready, missing something (dimmed with a hay
##   "!"), and the chosen one ringed in hay;
## - the chosen recipe on the pine board: its picture and badges, its ingredients as
##   pictures (click a wood to allow it), its description and flavour line, and what it
##   needs as tags;
## - two order choices, Make now or Keep in stock, and one Queue button;
## - the queue, each order with its picture and its status as a tag, always in view.
## Below 1200 px across, or on short screens, the queue folds into an Orders tab, and the
## sizes follow the screen's height. CraftingManager owns all the work.
signal place_requested(furniture_key: String)

const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const Grid = preload("res://scripts/ui/PictureGrid.gd")
const ICONS := "res://assets/ui/icons/"
const INK := UITheme.CATALOG_INK
const INK_SOFT := UITheme.CATALOG_MUTED
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height: large from 1300 px tall, small below 650 px. `columns` is
## the columns' least height: they grow until every recipe's board shows whole, as far as
## the room above the dock allows.
const SIZES := {
	"large": {"tile": 76, "per_row": 6, "card": 600, "picture": 200, "queue": 368, "head": LARGE.title,
		"sub": LARGE.body, "title": LARGE.title, "body": LARGE.body, "label": LARGE.small, "wood": 68, "crafter": 52, "section": 64,
		"action": 100, "columns": 800, "row": 64, "verb": LARGE.heading, "type": LARGE},
	"medium": {"tile": 60, "per_row": 5, "card": 440, "picture": 140, "queue": 300, "head": MEDIUM.title,
		"sub": MEDIUM.body, "title": MEDIUM.title, "body": MEDIUM.body, "label": MEDIUM.small, "wood": 52, "crafter": 44, "section": 52,
		"action": 64, "columns": 560, "row": 52, "verb": MEDIUM.heading, "type": MEDIUM},
	"small": {"tile": 44, "per_row": 6, "card": 360, "picture": 84, "queue": 300, "head": SMALL.title,
		"sub": SMALL.body, "title": SMALL.title, "body": SMALL.body, "label": SMALL.small, "wood": 40, "crafter": 34, "section": 40,
		"action": 44, "columns": 330, "row": 44, "verb": SMALL.heading, "type": SMALL},
}
const FOLD_WIDTH := 1200.0   # narrower screens fold the queue into the Orders tab

var controller: Node
var window: UIWindow
var selected := ""
var section_id := "rudimentary"
var maintain := false   # Keep in stock rather than Make now
var make_count := 1
var keep_count := 1
var _size: Dictionary = SIZES.medium
var _folded := false
var _show_orders := false
var _has_matches := true
var _dock_top := 600.0
var _layout_pending := false
var _last_recipe := {}
var _draft_ingredients := {}
var _textures := {}
var _rows := {}
var _crafter_tiles := {}
var _shown_tags := []
var _section_tile: PanelContainer
var _section_icon: TextureRect
var _heading: Label
var _subtitle: Label
var _crafters: HBoxContainer
var _columns: HBoxContainer
var _left: PanelContainer
var _left_box: VBoxContainer
var _search: LineEdit
var _recipe_scroll: ScrollContainer
var _recipes
var _no_results: Label
var _planned: Label
var _middle: VBoxContainer
var _card_scroll: ScrollContainer
var _card: PanelContainer
var _title: Label
var _showcase: HBoxContainer
var _picture: TextureRect
var _chips := {}
var _ingredients_heading: Label
var _ingredients: VBoxContainer
var _woods
var _requirements: Label
var _description: Label
var _flavour: Label
var _tags: HFlowContainer
var _orders_box: HBoxContainer
var _make_row := {}
var _keep_row := {}
var _queue_button: Button
var _place_row: HBoxContainer
var _place: Button
var _stock: Label
var _right: PanelContainer
var _right_box: VBoxContainer
var _queue_heading: Label
var _queue_scroll: ScrollContainer
var _queue_list: VBoxContainer
var _empty: Label
var _tabs: HBoxContainer
var _recipes_tab: Button
var _orders_tab: Button


func _ready() -> void:
	UITheme.apply_surface(self)
	for side: String in ["left", "right", "top"]: add_theme_constant_override("margin_" + side, 12)
	add_theme_constant_override("margin_bottom", 8)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	body.add_child(_build_header())
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 12)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_columns)
	_columns.add_child(_build_recipes())
	_columns.add_child(_build_middle())
	_columns.add_child(_build_queue())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	body.add_child(_tabs)
	_recipes_tab = UITheme.make_button("Recipes", "Browse this profession's recipes", Vector2(150, 34))
	_orders_tab = UITheme.make_button("Orders (0)", "This profession's crafting orders", Vector2(150, 34))
	for tab: Button in [_recipes_tab, _orders_tab]:
		tab.focus_mode = Control.FOCUS_ALL
		_tabs.add_child(tab)
	_recipes_tab.pressed.connect(_select_tab.bind(false))
	_orders_tab.pressed.connect(_select_tab.bind(true))
	_set_folded(false)
	visibility_changed.connect(refresh)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_section_icon = _texture_rect()
	_section_tile = UITheme.framed_picture(_section_icon)
	_section_tile.add_theme_stylebox_override("panel", UITheme.icon_tile_style(_family("people")))
	header.add_child(_section_tile)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 2)
	header.add_child(identity)
	_heading = Label.new()
	UITheme.format_label(_heading, true, MEDIUM.title, UITheme.CARD_TITLE, 5)
	_heading.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	identity.add_child(_heading)
	_subtitle = _text("", MEDIUM.body, UITheme.HEARTH_MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(_subtitle)
	_crafters = HBoxContainer.new()
	_crafters.add_theme_constant_override("separation", 6)
	_crafters.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_crafters)
	return header


func _build_recipes() -> Control:
	_left = PanelContainer.new()
	_left.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 10)
	_left.add_child(_left_box)
	_search = LineEdit.new()
	_search.placeholder_text = "Search recipes or categories…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String):
		_recipe_scroll.scroll_vertical = 0
		refresh())
	_left_box.add_child(_search)
	_recipe_scroll = _scroll()
	_left_box.add_child(_recipe_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	_recipe_scroll.add_child(list)
	_recipes = Grid.new()
	_recipes.family = _family("settlement")
	_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipes.item_pressed.connect(select_recipe)
	list.add_child(_recipes)
	_no_results = _text("No matching recipes.\nTry a name such as campfire or a category such as Access.", MEDIUM.body, UITheme.HEARTH_MUTED)
	list.add_child(_no_results)
	_planned = _text("", MEDIUM.body)
	list.add_child(_planned)
	return _left


func _build_middle() -> Control:
	_middle = VBoxContainer.new()
	_middle.add_theme_constant_override("separation", 10)
	_card_scroll = _scroll()
	_middle.add_child(_card_scroll)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_card.add_child(content)
	_title = _text("", MEDIUM.title, INK)
	_title.add_theme_font_override("font", UITheme.display_font())
	content.add_child(_title)
	_showcase = HBoxContainer.new()
	_showcase.add_theme_constant_override("separation", 12)
	content.add_child(_showcase)
	_picture = _texture_rect()
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_showcase.add_child(_picture)
	var chips := VBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_showcase.add_child(chips)
	for key: String in ["time", "makes", "appeal"]:
		_chips[key] = _chip(chips, {"time": "clock.png", "makes": "stocks.png", "appeal": "appeal.png"}[key])
	_ingredients_heading = _text("", MEDIUM.small, INK_SOFT)
	content.add_child(_ingredients_heading)
	_ingredients = VBoxContainer.new()
	_ingredients.add_theme_constant_override("separation", 8)
	content.add_child(_ingredients)
	_woods = Grid.new()
	_woods.family = _family("settlement")
	_woods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_woods.item_pressed.connect(_toggle_draft_wood)
	_ingredients.add_child(_woods)
	_requirements = _text("", MEDIUM.body, INK_SOFT)
	_ingredients.add_child(_requirements)
	_description = _text("", MEDIUM.lead, INK)
	content.add_child(_description)
	_flavour = _text("", MEDIUM.body, INK_SOFT)
	content.add_child(_flavour)
	_tags = HFlowContainer.new()
	_tags.add_theme_constant_override("h_separation", 10)
	_tags.add_theme_constant_override("v_separation", 6)
	content.add_child(_tags)
	# Make or Keep beside the Queue button.
	_orders_box = HBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 14)
	_middle.add_child(_orders_box)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 6)
	choices.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_orders_box.add_child(choices)
	_make_row = _order_choice(choices, "Make", "now", false)
	_keep_row = _order_choice(choices, "Keep", "in stock", true)
	_queue_button = Button.new()
	_queue_button.text = "Queue"
	_queue_button.icon = load(ICONS + "craft.png")
	_queue_button.expand_icon = true
	UITheme.apply_catalog_primary(_queue_button)
	_queue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_button.pressed.connect(_queue_selected)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders_box.add_child(actions)
	actions.add_child(_queue_button)
	_place_row = HBoxContainer.new()
	_place_row.add_theme_constant_override("separation", 10)
	actions.add_child(_place_row)
	_place = UITheme.make_button("Place finished item", "Open placement for this recipe's finished goods", Vector2(0, 32))
	_place.focus_mode = Control.FOCUS_ALL
	_place.pressed.connect(func(): place_requested.emit(String(controller.recipes[selected].furniture)))
	_place_row.add_child(_place)
	# Goods that are not placed say how many the stores hold instead. One line: wrapped
	# text beside the Place button would measure tall before the window has its width.
	_stock = _text("", MEDIUM.body, UITheme.HEARTH_MUTED)
	_stock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_place_row.add_child(_stock)
	return _middle


func _build_queue() -> Control:
	_right = PanelContainer.new()
	_right.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_right_box = VBoxContainer.new()
	_right_box.add_theme_constant_override("separation", 10)
	_right.add_child(_right_box)
	_queue_heading = _text("", MEDIUM.small, UITheme.TAG_TONES.waiting[0])
	_queue_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_right_box.add_child(_queue_heading)
	_queue_scroll = _scroll()
	_right_box.add_child(_queue_scroll)
	_queue_list = VBoxContainer.new()
	_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_list.add_theme_constant_override("separation", 10)
	_queue_scroll.add_child(_queue_list)
	_empty = _text("No orders yet.\nChoose a recipe, then queue it.", MEDIUM.body, UITheme.HEARTH_MUTED)
	_queue_list.add_child(_empty)
	return _right


func bind_controller(value: Node) -> void:
	controller = value
	controller.changed.connect(refresh)
	if window != null: window.resized.connect(_clamp_above_dock)
	# The Crafters row: one tile per profession, lit when it can craft today.
	for entry: Dictionary in UIRegistry.get_menu("craft").get("items", []):
		var key := String(entry.get("target", ""))
		if not controller.sections.has(key): continue
		var tile := Button.new()
		tile.name = "Crafter" + key.to_pascal_case()
		tile.icon = load(String(entry.icon))
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.focus_mode = Control.FOCUS_ALL
		tile.tooltip_text = "%s\n%s" % [entry.get("label", key), entry.get("tooltip", "")]
		tile.pressed.connect(select_section.bind(key))
		_crafters.add_child(tile)
		_crafter_tiles[key] = tile
	select_section("rudimentary")


func select_section(key: String) -> void:
	if controller == null or not controller.sections.has(key): return
	if not selected.is_empty(): _last_recipe[section_id] = selected
	section_id = key
	_search.text = ""
	_show_orders = false
	selected = ""
	if not bool(controller.sections[key].get("planned", false)):
		for recipe: Dictionary in controller.recipes.values():
			if String(recipe.get("section", "rudimentary")) == key:
				selected = String(_last_recipe.get(key, recipe.id))
				break
		if not selected.is_empty(): _draft(selected)
	_card_scroll.scroll_vertical = 0
	refresh()
	_fit.call_deferred()
	_reveal_selected()


func select_recipe(key: String) -> void:
	if controller == null or not controller.recipes.has(key): return
	var recipe_section := String(controller.recipes[key].get("section", "rudimentary"))
	if section_id != recipe_section: select_section(recipe_section)
	if not _matches_search(controller.recipes[key]): _search.text = ""
	selected = key
	_last_recipe[section_id] = key
	_show_orders = false
	_card_scroll.scroll_vertical = 0
	_draft(key)
	refresh()
	_reveal_selected()


func _reveal_selected() -> void:
	_reveal.call_deferred()


## Look the tile up when the scroll moves: a refresh in between may rebuild the grid.
func _reveal() -> void:
	var tile: Control = _recipes.get_tile(selected)
	if tile != null and _recipe_scroll.is_ancestor_of(tile): _recipe_scroll.ensure_control_visible(tile)


func _select_tab(orders: bool) -> void:
	_show_orders = orders
	refresh()


## The woods a recipe's next order may use: its default until the player changes them.
func _draft(key: String) -> Array:
	if not _draft_ingredients.has(key):
		_draft_ingredients[key] = controller.allowed_ingredient_keys(controller.recipes[key])
	return _draft_ingredients[key]


func _matches_search(recipe: Dictionary) -> bool:
	var query := _search.text.strip_edges().to_lower()
	return query.is_empty() or (String(recipe.name) + " " + String(recipe.get("category", ""))).to_lower().contains(query)


func _queue_selected() -> void:
	if selected.is_empty() or (not _has_matches and not _show_orders): return
	var allowed: Array = _draft(selected)
	if allowed.is_empty(): return
	controller.queue_order(selected, keep_count if maintain else make_count, maintain, allowed)
	refresh()


func _choose_order(keep: bool) -> void:
	maintain = keep
	refresh()


func _change_count(keep: bool, step: int) -> void:
	maintain = keep
	if keep: keep_count = clampi(keep_count + step, 1, 99)
	else: make_count = clampi(make_count + step, 1, 99)
	refresh()


func _toggle_draft_wood(key: String) -> void:
	if key.begins_with("extra:") or selected.is_empty(): return
	var keys: Array = _draft(selected).duplicate()
	if key in keys: keys.erase(key)
	else: keys.append(key)
	_draft_ingredients[selected] = controller.allowed_ingredient_keys(controller.recipes[selected], keys)
	refresh()


func refresh() -> void:
	if controller == null or not controller.sections.has(section_id) or not is_visible_in_tree(): return
	var totals := Inventory.snapshot(controller.items, controller.furniture)
	var section: Dictionary = controller.sections[section_id]
	var planned := bool(section.get("planned", false))
	if window != null: window.set_window_title("Crafting")
	_show_header(section, planned)
	_show_recipes(planned, totals)
	var showing_orders := _folded and _show_orders and not planned
	_search.visible = not planned and not showing_orders
	_recipe_scroll.visible = not showing_orders
	_queue_heading.visible = not _folded or showing_orders
	_queue_scroll.visible = not _folded or showing_orders
	_tabs.visible = _folded and not planned
	UITheme.show_tab(_recipes_tab, not showing_orders)
	UITheme.show_tab(_orders_tab, showing_orders)
	_refresh_orders(totals)
	var has_recipe := not planned and not selected.is_empty() and (_has_matches or showing_orders)
	for control: Control in [_showcase, _ingredients_heading, _ingredients, _flavour, _tags]: control.visible = has_recipe
	_orders_box.visible = has_recipe
	_place_row.visible = has_recipe
	if planned:
		_show_planned(section)
	elif not has_recipe:
		_title.text = "No matching recipes"
		_description.text = "Change or clear your search to browse this profession's recipes."
	else:
		_show_recipe(controller.recipes[selected], totals)


func _show_header(section: Dictionary, planned: bool) -> void:
	var rudimentary := section_id == "rudimentary"
	_heading.text = "%s · Worker" % section.name if rudimentary else ("%s · %s" % [section.name, section.get("status_label", "Planned")] if planned else String(section.name))
	_subtitle.text = "Every Worker can craft. No promotion needed." if rudimentary else String(section.get("description", ""))
	_subtitle.tooltip_text = String(section.get("hint", ""))
	if _crafter_tiles.has(section_id): _section_icon.texture = (_crafter_tiles[section_id] as Button).icon
	var people := _family("people")
	for key: String in _crafter_tiles:
		var tile: Button = _crafter_tiles[key]
		var lit := not bool(controller.sections[key].get("planned", false))
		var state := "selected" if key == section_id else ("normal" if lit else "planned")
		tile.add_theme_stylebox_override("normal", UITheme.icon_tile_style(people, state))
		tile.add_theme_stylebox_override("pressed", UITheme.icon_tile_style(people, state))
		var hover := "selected_hover" if key == section_id else ("hover" if lit else "planned")
		tile.add_theme_stylebox_override("hover", UITheme.icon_tile_style(people, hover))
		tile.add_theme_stylebox_override("hover_pressed", UITheme.icon_tile_style(people, hover))
		for look: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			tile.add_theme_color_override(look, Color.WHITE if lit else Color(0.5, 0.5, 0.5))


## The recipes, grouped by category: ready, or missing something (dimmed with a hay "!").
func _show_recipes(planned: bool, totals: Dictionary) -> void:
	var matches: Array[String] = []
	if not planned:
		for recipe: Dictionary in controller.recipes.values():
			if String(recipe.get("section", "rudimentary")) == section_id and _matches_search(recipe): matches.append(String(recipe.id))
	_has_matches = not matches.is_empty()
	if _has_matches and selected not in matches:
		selected = matches.front()
		_card_scroll.scroll_vertical = 0
		_draft(selected)
	var groups: Array = []
	var by_category := {}
	for id: String in matches:
		var recipe: Dictionary = controller.recipes[id]
		var category := String(recipe.get("category", "Recipes"))
		if not by_category.has(category):
			by_category[category] = {"id": category, "title": category, "items": []}
			groups.append(by_category[category])
		var reason: String = controller.recipe_waiting_reason(recipe, _typed(_draft(id)), totals)
		by_category[category].items.append({"id": id, "picture": _recipe_picture(recipe), "mark": "" if reason.is_empty() else "missing",
			"dim": not reason.is_empty(), "selected": id == selected,
			"tooltip": "%s\n%s" % [recipe.name, "Ready to make" if reason.is_empty() else reason]})
	_recipes.show_groups(groups)
	_recipes.visible = not planned
	_no_results.visible = not planned and not _has_matches
	_planned.visible = planned


func _show_planned(section: Dictionary) -> void:
	_planned.text = "PLANNED\n\n" + "\n\n".join(section.get("preview", []))
	_title.text = "%s · %s" % [section.name, section.get("status_label", "Planned")]
	_description.text = "%s\n\n%s" % [section.get("description", ""), section.get("requirements", "")]
	_description.text = _description.text.strip_edges()


func _show_recipe(recipe: Dictionary, totals: Dictionary) -> void:
	var allowed: Array = _draft(selected)
	_title.text = String(recipe.name)
	_picture.texture = _recipe_picture(recipe)
	_chips.time.label.text = "%d s" % roundi(float(recipe.work_seconds))
	_chips.makes.label.text = "Makes %d" % int(recipe.output_count)
	var appeal := _appeal(recipe, allowed)
	_chips.appeal.panel.visible = not appeal.is_empty()
	_chips.appeal.label.text = appeal
	# Ingredients: every wood the recipe takes, allowed or not, then its fixed materials.
	var extra_counts := {}
	for key: String in controller.additional_ingredient_keys(recipe): extra_counts[key] = int(extra_counts.get(key, 0)) + 1
	var heading := "INGREDIENTS · %d timber" % int(recipe.ingredient_count)
	var woods: Array = []
	for key: String in controller.ingredient_keys(recipe):
		var available := int(totals.get(key, {}).get("available", 0))
		woods.append({"id": key, "picture": _item_picture(key), "count": available, "mark": "on" if key in allowed else "off",
			"dim": key not in allowed, "tooltip": "%s · %d available\n%s" % [controller.ingredient_label(key), available,
			"Allowed. Click to stop using it." if key in allowed else "Not used. Click to allow it."]})
	var extras: Array = []
	for key: String in extra_counts:
		var available := int(totals.get(key, {}).get("available", 0))
		heading += " · %d %s" % [int(extra_counts[key]), controller.ingredient_label(key)]
		extras.append({"id": "extra:" + key, "picture": _item_picture(key), "count": available,
			"mark": "on" if available >= int(extra_counts[key]) else "missing",
			"tooltip": "%d %s · %d available" % [int(extra_counts[key]), controller.ingredient_label(key), available]})
	_ingredients_heading.text = heading
	var groups: Array = [{"id": "woods", "items": woods}]
	if not extras.is_empty(): groups.append({"id": "extras", "items": extras})
	_woods.show_groups(groups)
	var lines: Array[String] = ["%d timber · %d allowed logs available" % [int(recipe.ingredient_count), controller.ingredient_available(recipe, totals, allowed)]]
	if int(recipe.ingredient_count) > 1: lines.append("All logs must be the same wood.")
	for key: String in extra_counts:
		lines.append("%d %s · %d available" % [int(extra_counts[key]), controller.ingredient_label(key), int(totals.get(key, {}).get("available", 0))])
	lines.append("Click a wood to allow it.")
	_requirements.text = "\n".join(lines)
	_description.text = String(recipe.description)
	# Small screens take the short purpose, where a recipe has one.
	var purpose := String(recipe.get("purpose_short", recipe.get("purpose", "")) if _size == SIZES.small else recipe.get("purpose", ""))
	if not purpose.is_empty(): _description.text += "\n\n" + purpose
	_flavour.text = "\"%s\"" % recipe.flavour if recipe.has("flavour") else ""
	_flavour.visible = recipe.has("flavour")
	# What it needs, as tags: the workshop and who can make it.
	var tags: Array = []
	var workshop := String(recipe.workshop)
	if workshop.is_empty(): tags.append(["✓ No workshop needed", "fine"])
	else:
		var bench := String(controller.furniture.get_defs().get(workshop, {}).get("display_name", "workbench")).to_lower() if controller.furniture != null else "workbench"
		tags.append(["✓ A free " + bench, "fine"] if not controller.bench_target(workshop, Vector3i.ZERO).is_empty() else ["Needs a free " + bench, "waiting"])
	tags.append(["✓ Any Worker", "fine"])
	_show_tags(tags)
	_show_order_choices(recipe)
	var stock := int(totals.get(String(recipe.output), {}).get("available", 0))
	var placeable := not String(recipe.get("furniture", "")).is_empty()
	_place.text = "Place · %d ready" % stock
	_place.visible = placeable
	_place.disabled = stock < 1
	_stock.text = "%d in colony stores" % stock
	_stock.visible = not placeable


func _show_order_choices(recipe: Dictionary) -> void:
	for entry: Array in [[_make_row, false, make_count], [_keep_row, true, keep_count]]:
		var row: Dictionary = entry[0]
		var chosen: bool = maintain == entry[1]
		row.mark.text = "◆" if chosen else "◇"
		row.tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_waiting" if chosen else "tag_fine", 2))
		row.mark.add_theme_color_override("font_color", UITheme.tag_ink("waiting" if chosen else "fine"))
		for look: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			row.choose.add_theme_color_override(look, UITheme.CARD_TITLE if chosen else UITheme.HEARTH_MUTED)
		row.count.text = str(entry[2])
	var output_count := make_count * int(recipe.output_count)
	var output_name := String(recipe.name).to_lower() if output_count == 1 else String(recipe.get("output_plural", recipe.name))
	_queue_button.tooltip_text = ("Queue %d %s. The order waits if materials or a workbench are missing." % [output_count, output_name]) if not maintain \
		else "Keep %d in stock: Workers make more from the allowed wood, in batches of %d, whenever stock falls short. Installed and reserved items do not count." % [keep_count, int(recipe.output_count)]
	_queue_button.disabled = _draft(selected).is_empty() or controller.orders.size() >= controller.max_orders


func _show_tags(entries: Array) -> void:
	if entries == _shown_tags: return
	_shown_tags = entries.duplicate(true)
	for child: Node in _tags.get_children():
		_tags.remove_child(child)
		child.queue_free()
	for entry: Array in entries: _tags.add_child(_tag(String(entry[0]), String(entry[1]), MEDIUM.body))


func _appeal(recipe: Dictionary, allowed: Array) -> String:
	var output_def: Dictionary = controller.furniture.def_for_item(String(recipe.output)) if controller.furniture != null else {}
	if not output_def.has("appeal") or allowed.is_empty(): return ""
	var scores: Array[float] = []
	for key: String in allowed: scores.append(float(CraftMaterials.appeal(output_def, CraftMaterials.from_ingredient(key)).total))
	return str(scores.min()) if scores.min() == scores.max() else "%s–%s" % [str(scores.min()), str(scores.max())]


func _refresh_orders(totals: Dictionary) -> void:
	var ids: Array[int] = []
	for order in controller.orders:
		if String(order.recipe.get("section", "rudimentary")) == section_id: ids.append(order.id)
	for id: int in _rows.keys():
		if id not in ids:
			_rows[id].root.queue_free()
			_queue_list.remove_child(_rows[id].root)
			_rows.erase(id)
	for order in controller.orders:
		if order.id not in ids: continue
		if not _rows.has(order.id): _add_order(order.id)
		var row: Dictionary = _rows[order.id]
		_queue_list.move_child(row.root, ids.find(order.id) + 1)
		var units := int(order.quantity) * int(order.recipe.output_count)
		row.title.text = ("%s = %d" % [order.recipe.name, order.quantity]) if order.maintain else ("%s ×%d" % [order.recipe.name, units])
		row.title.tooltip_text = ("Keep %d spare" % order.quantity) if order.maintain else ("%d batch%s · %d remaining" % [order.quantity, "" if order.quantity == 1 else "es", units])
		row.picture.texture = _recipe_picture(order.recipe)
		var status: String = controller.status(order, totals)
		var tone := "blocked" if order.paused else ("waiting" if status.begins_with("Waiting") or status.begins_with("Choose") else "fine")
		row.status.text = status
		row.status.add_theme_color_override("font_color", UITheme.tag_ink(tone))
		row.tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 2))
		_update_wood_menu(row.wood, order.allowed_ingredients, totals)
		row.pause.text = "Resume" if order.paused else "Pause"
		row.up.disabled = ids.front() == order.id or order.worker_id >= 0
		row.down.disabled = ids.back() == order.id or order.worker_id >= 0
	_empty.visible = ids.is_empty()
	_queue_heading.text = "QUEUE · %d order%s" % [ids.size(), "" if ids.size() == 1 else "s"]
	_orders_tab.text = "Orders (%d)" % ids.size()


func _add_order(id: int) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.cell_style("raised", 3))
	_queue_list.add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var picture := _texture_rect()
	picture.custom_minimum_size = Vector2.ONE * (float(_size.row) - 8.0)
	var tile := UITheme.framed_picture(picture)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(tile)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	line.add_child(column)
	var title := Label.new()
	UITheme.format_label(title, true, MEDIUM.lead, UITheme.CARD_TITLE)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(title)
	var tag := PanelContainer.new()
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(tag)
	var status := Label.new()
	UITheme.format_label(status, false, MEDIUM.small, UITheme.tag_ink("fine"))
	tag.add_child(status)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	column.add_child(controls)
	var wood := _make_wood_menu(id)
	wood.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(wood)
	var pause := UITheme.make_button("Pause", "Pause without losing completed work", Vector2(58, 28))
	pause.add_theme_font_size_override("font_size", MEDIUM.small)
	pause.pressed.connect(func():
		var order = controller.get_order(id)
		if order != null: controller.set_paused(id, not order.paused))
	controls.add_child(pause)
	var up := UITheme.make_button("▴", "Move earlier", Vector2(28, 28))
	up.pressed.connect(func(): controller.move_order(id, -1))
	controls.add_child(up)
	var down := UITheme.make_button("▾", "Move later", Vector2(28, 28))
	down.pressed.connect(func(): controller.move_order(id, 1))
	controls.add_child(down)
	var cancel := UITheme.make_button("✕", "Cancel order and return its materials", Vector2(28, 28))
	cancel.pressed.connect(func(): controller.remove_order(id))
	controls.add_child(cancel)
	_rows[id] = {"root": panel, "picture": picture, "title": title, "tag": tag, "status": status, "wood": wood,
		"pause": pause, "up": up, "down": down, "cancel": cancel}


## A queued order's woods: a checklist on the order itself.
func _make_wood_menu(order_id: int) -> MenuButton:
	var button := MenuButton.new()
	button.flat = false
	button.clip_text = true
	button.custom_minimum_size = Vector2(56, 28)
	button.add_theme_font_size_override("font_size", MEDIUM.small)
	button.theme = UITheme.shared_theme().duplicate()
	button.theme.set_stylebox("panel", "PopupMenu", UITheme.cell_style("card", 3))
	button.theme.set_stylebox("hover", "PopupMenu", UITheme.button_hover_style())
	button.theme.set_color("font_color", "PopupMenu", UITheme.HEARTH_TEXT)
	button.theme.set_color("font_hover_color", "PopupMenu", UITheme.HEARTH_TEXT)
	var popup := button.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.about_to_popup.connect(func(): _open_wood_menu(button, order_id))
	popup.id_pressed.connect(func(index: int): _toggle_wood(button, index, order_id))
	return button


func _open_wood_menu(button: MenuButton, order_id: int) -> void:
	var order = controller.get_order(order_id)
	if order == null: return
	var popup := button.get_popup()
	popup.clear()
	# The recipe's default first; this is a checklist, not a preference order.
	var keys: Array = controller.allowed_ingredient_keys(order.recipe)
	for key in controller.ingredient_keys(order.recipe):
		if key not in keys: keys.append(key)
	for key: String in keys:
		popup.add_check_item(controller.ingredient_label(key))
		popup.set_item_metadata(popup.item_count - 1, key)
	_update_wood_menu(button, order.allowed_ingredients, controller.stock_snapshot())


func _toggle_wood(button: MenuButton, index: int, order_id: int) -> void:
	var order = controller.get_order(order_id)
	if order == null: return
	var keys: Array = order.allowed_ingredients.duplicate()
	var key := String(button.get_popup().get_item_metadata(index))
	if key in keys: keys.erase(key)
	else: keys.append(key)
	controller.set_allowed_ingredients(order_id, keys)
	refresh()


func _update_wood_menu(button: MenuButton, keys: Array, totals: Dictionary) -> void:
	var names: String = controller.ingredient_summary(keys)
	var caption := "Choose…" if keys.is_empty() else names
	if keys.size() > 2: caption = "%s + %d" % [controller.ingredient_label(keys[0]), keys.size() - 1]
	button.text = caption + " ▾"
	button.tooltip_text = "Allowed wood: %s. Other wood is never substituted." % ("none" if keys.is_empty() else names)
	var popup := button.get_popup()
	for index in range(popup.item_count):
		var key := String(popup.get_item_metadata(index))
		popup.set_item_checked(index, key in keys)
		popup.set_item_text(index, "%s · %d available" % [controller.ingredient_label(key), int(totals.get(key, {}).get("available", 0))])


# ── Size and fit ──────────────────────────────────────────────────────────────

func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree(): return
	var viewport := get_viewport_rect().size
	_size = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	_set_folded(viewport.x < FOLD_WIDTH or _size == SIZES.small)
	_apply_size()
	refresh()
	# The columns are as tall as the tallest board needs, as far as the room the window's
	# frame, header and tabs leave above the dock allows. No wrapped text sits outside a
	# scroll, so the chrome's measure holds before the first layout.
	_columns.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	var room := maxf(200.0, _dock_top - 12.0 - chrome)
	_columns.custom_minimum_size.y = minf(room, maxf(float(_size.columns), _tallest_board()))
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock.call_deferred()
	_settle_layout()
	_reveal_selected()   # the tiles may have changed size


## The middle column's height when every recipe's board shows whole: the tallest board at
## this size and full width, with its order row (furniture's Place button stands taller
## than goods' stock line). Measured on the live board, so wrapped text and picture rows
## count as they will show.
func _tallest_board() -> float:
	if not is_visible_in_tree() or controller.recipes.is_empty(): return 0.0
	window.reset_size()
	UITheme.lay_out_now(window)   # every column takes its width for this size
	_card.size.x = _card_scroll.size.x   # a board that fits has no scrollbar beside it
	for control: Control in [_showcase, _ingredients_heading, _ingredients, _tags, _orders_box, _place_row]: control.visible = true
	var keep := selected
	var totals := Inventory.snapshot(controller.items, controller.furniture)
	var tallest := 0.0
	for key: String in controller.recipes:
		selected = key
		_show_recipe(controller.recipes[key], totals)
		UITheme.lay_out_now(_card)
		tallest = maxf(tallest, _card.get_combined_minimum_size().y + _orders_box.get_combined_minimum_size().y)
	selected = keep
	refresh()
	return ceilf(tallest + float(_middle.get_theme_constant("separation")))


func _set_folded(folded: bool) -> void:
	_folded = folded
	var box := _left_box if folded else _right_box
	for node: Control in [_queue_heading, _queue_scroll]:
		if node.get_parent() != box: node.reparent(box, false)
	_right.visible = not folded
	if not folded: _show_orders = false


func _apply_size() -> void:
	var s := _size
	_section_tile.custom_minimum_size = Vector2.ONE * float(s.section)
	_heading.add_theme_font_size_override("font_size", s.head)
	_subtitle.add_theme_font_size_override("font_size", s.sub)
	for tile: Button in _crafter_tiles.values():
		tile.custom_minimum_size = Vector2.ONE * float(s.crafter)
		tile.add_theme_constant_override("icon_max_width", int(s.crafter) - 14)
	_left.custom_minimum_size.x = float(s.per_row) * (float(s.tile) + 10.0) + 40.0   # the inset and its scrollbar
	_recipes.set_tile_size(float(s.tile))
	_middle.custom_minimum_size.x = float(s.card)
	_picture.custom_minimum_size = Vector2(float(s.picture), float(s.picture) * 0.9)
	_title.add_theme_font_size_override("font_size", s.title)
	for label: Label in [_description, _requirements, _no_results, _planned, _empty]: label.add_theme_font_size_override("font_size", s.body)
	_flavour.add_theme_font_size_override("font_size", int(s.body))
	_ingredients_heading.add_theme_font_size_override("font_size", s.label)
	_queue_heading.add_theme_font_size_override("font_size", s.label)
	_woods.set_tile_size(float(s.wood))
	_right.custom_minimum_size.x = float(s.queue)
	_queue_button.custom_minimum_size = Vector2(0, float(s.action))
	_queue_button.add_theme_font_size_override("font_size", s.type.title)
	_queue_button.add_theme_constant_override("icon_max_width", int(float(s.action) * 0.6))
	for row: Dictionary in [_make_row, _keep_row]:
		row.choose.add_theme_font_size_override("font_size", s.verb)
		row.count.add_theme_font_size_override("font_size", s.verb)
		row.tail.add_theme_font_size_override("font_size", int(s.body))
		row.tail.visible = s != SIZES.small   # small screens: the verb says enough
	for row: Dictionary in _rows.values(): row.picture.custom_minimum_size = Vector2.ONE * (float(s.row) - 8.0)


func _settle_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_pending = false
	if not is_instance_valid(window): return
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock()


func _clamp_above_dock() -> void:
	if window == null: return
	window.position.y = minf(window.position.y, maxf(4, _dock_top - 8 - window.size.y))


# ── Pieces ────────────────────────────────────────────────────────────────────

## One order choice: its mark, its verb (click to choose it), ‹ count › and a tail.
func _order_choice(parent: Control, verb: String, tail: String, keep: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var tag := PanelContainer.new()
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var mark := Label.new()
	UITheme.format_label(mark, true, MEDIUM.small, UITheme.tag_ink("fine"))
	tag.add_child(mark)
	var choose := Button.new()
	choose.flat = true
	choose.text = verb
	choose.focus_mode = Control.FOCUS_ALL
	choose.add_theme_font_override("font", UITheme.display_font())
	choose.tooltip_text = "Keep this many spare in stock. Workers make more whenever stock falls short." if keep else "Make this many now."
	choose.pressed.connect(_choose_order.bind(keep))
	row.add_child(choose)
	var less := _keycap("‹", "Fewer")
	less.pressed.connect(_change_count.bind(keep, -1))
	row.add_child(less)
	var count := Label.new()
	UITheme.format_label(count, true, MEDIUM.heading, UITheme.TAG_TONES.waiting[0])
	count.custom_minimum_size.x = 28
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	var more := _keycap("›", "More")
	more.pressed.connect(_change_count.bind(keep, 1))
	row.add_child(more)
	var after := _text(tail, MEDIUM.body, UITheme.HEARTH_MUTED)
	after.autowrap_mode = TextServer.AUTOWRAP_OFF
	after.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(after)
	return {"row": row, "tag": tag, "mark": mark, "choose": choose, "less": less, "count": count, "more": more, "tail": after}


func _keycap(glyph: String, tip: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(28, 30)
	button.add_theme_font_override("font", UITheme.display_font())
	button.add_theme_font_size_override("font_size", MEDIUM.body)
	for look: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(look, UITheme.KEYCAP_INK)
	button.add_theme_stylebox_override("normal", UITheme.cell_style("keycap", 2))
	for look: String in ["hover", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(look, UITheme.cell_style("keycap_hover", 2))
	return button


func _chip(parent: Control, icon: String) -> Dictionary:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.cell_style("chip", 3))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	var picture := _texture_rect()
	picture.texture = load(ICONS + icon)
	picture.custom_minimum_size = Vector2(24, 24)
	row.add_child(picture)
	var label := Label.new()
	UITheme.format_label(label, true, MEDIUM.lead, UITheme.KEYCAP_INK)
	row.add_child(label)
	return {"panel": chip, "label": label}


func _tag(text: String, tone: String, font_size: int) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 3))
	var label := Label.new()
	label.text = text
	UITheme.format_label(label, false, font_size, UITheme.tag_ink(tone))
	tag.add_child(label)
	return tag


func _recipe_picture(recipe: Dictionary) -> Texture2D:
	var id := String(recipe.id)
	if not _textures.has(id):
		var furniture_key := String(recipe.get("furniture", ""))
		var path := Inventory.thumbnail_path(String(recipe.output)) if furniture_key.is_empty() else "res://assets/ui/furniture/%s.png" % furniture_key.get_slice(":", 2)
		_textures[id] = load(path) if ResourceLoader.exists(path) else load(ICONS + "craft.png")
	return _textures[id]


func _item_picture(key: String) -> Texture2D:
	if not _textures.has(key):
		var path := Inventory.thumbnail_path(key)
		_textures[key] = load(path) if ResourceLoader.exists(path) else load(ICONS + "stocks.png")
	return _textures[key]


func _family(name: String) -> Color:
	return UIRegistry.get_icon_family_color(name)


## CraftingManager takes typed wood lists.
static func _typed(keys: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(keys)
	return typed


func _scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _texture_rect() -> TextureRect:
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _text(value: String, font_size: int, color: Color = UITheme.CARD_TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UITheme.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
