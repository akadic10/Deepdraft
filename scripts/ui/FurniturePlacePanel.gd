class_name FurniturePlacePanel
extends MarginContainer

## The Place window (doc 262), in the crafting window's shape:
## - every category open at once as a group of the picture grid: each design on the
##   settlement tile with how many are ready (dimmed when none), its name on hover;
## - the chosen design on the pine board: its picture, facts and appeal, its description and
##   note, its wood as pictures with counts, and how many are ready, on their way and being
##   crafted;
## - Place under the board, with what it takes to have one when none is ready. The tool
##   bar runs the placing, with its keys, Undo and Done (doc 23, "The tool bar").
## A click on a picture starts placing it. Sizes follow the screen's height, and the window
## fits above the dock. Presentation only: inventory, reservations, validity and delivery
## stay with FurniturePlacementController; movable chrome belongs to UIWindowManager.
signal place_requested(furniture_key: String)

const Grid = preload("res://scripts/ui/PictureGrid.gd")
const Inventory = preload("res://scripts/components/ColonyInventory.gd")
const INK := UITheme.CATALOG_INK
const INK_SOFT := UITheme.CATALOG_MUTED
const ANY := "any"   # the wood tile that leaves the choice of wood to the dwarves
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height: large from 1300 px tall, small below 650 px. `columns` is
## the columns' least height; they grow until every design's board shows whole, as far as
## the room above the dock allows.
const SIZES := {
	"large": {"tile": 110, "gap": 14, "per_row": 6, "card": 680, "picture": 300, "title": LARGE.name, "body": LARGE.body,
		"label": LARGE.small, "heading": LARGE.heading, "wood": 80, "wood_gap": 16, "value": LARGE.name, "word": LARGE.body, "action": 72, "verb": LARGE.heading, "columns": 960, "type": LARGE},
	"medium": {"tile": 72, "gap": 10, "per_row": 5, "card": 440, "picture": 150, "title": MEDIUM.name, "body": MEDIUM.body,
		"label": MEDIUM.small, "heading": MEDIUM.heading, "wood": 52, "wood_gap": 20, "value": MEDIUM.name, "word": MEDIUM.body, "action": 52, "verb": MEDIUM.heading, "columns": 560, "type": MEDIUM},
	"small": {"tile": 52, "gap": 8, "per_row": 5, "card": 330, "picture": 90, "title": SMALL.name, "body": SMALL.body,
		"label": SMALL.small, "heading": SMALL.heading, "wood": 42, "wood_gap": 8, "value": SMALL.name, "word": SMALL.body, "action": 40, "verb": SMALL.heading, "columns": 300, "type": SMALL},
}
## The words beside the board's three numbers: in full, then on small screens.
const WORDS := {"Available": ["ready to place", "ready"], "Reserved": ["on their way", "on the way"],
	"Crafting": ["being crafted", "crafting"]}

var controller: FurniturePlacementController
var window: UIWindow
var selected_key := ""
var show_all := false
var _entries: Array = []
var _stock := {}
## Keep browsing targets fixed until the player reopens the catalog. A temporarily carried
## or claimed item never removes a tile, and designs that arrive while the window is open
## wait in a New group at the end, so nothing moves under the pointer.
var _browse_keys: Array[String] = []
var _arrivals: Array[String] = []
var _browsing := false   # the window's first refresh has listed what was in stock
var _shown: Array[String] = []
var _textures := {}
var _size: Dictionary = SIZES.medium
var _dock_top := 600.0
var _layout_pending := false
var _shown_facts := PackedStringArray()
var _columns: HBoxContainer
var _intro: Label
var _all_toggle: Button
var _left: PanelContainer
var _scroll: ScrollContainer
var _grid
var _empty: VBoxContainer
var _empty_title: Label
var _empty_text: Label
var _side: VBoxContainer
var _none: PanelContainer
var _none_text: Label
var _card_scroll: ScrollContainer
var _card: PanelContainer
var _name: Label
var _picture: TextureRect
var _facts: VBoxContainer
var _appeal: PanelContainer
var _appeal_label: Label
var _description: Label
var _note: Label
var _wood_heading: Label
var _material
var _values := {}
var _words := {}
var _actions: HBoxContainer
var _place: Button
var _hint: Label


func _ready() -> void:
	UITheme.apply_surface(self)
	for side: String in ["left", "right", "top"]: add_theme_constant_override("margin_" + side, 12)
	add_theme_constant_override("margin_bottom", 10)
	_entries = UIRegistry.get_place_catalog().get("items", [])
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	add_child(_columns)
	_columns.add_child(_build_designs())
	_columns.add_child(_build_side())


func _build_designs() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	_intro = _text("Click a picture to place it · hover for its name", MEDIUM.body, UITheme.HEARTH_MUTED)
	_intro.autowrap_mode = TextServer.AUTOWRAP_OFF
	_intro.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_intro)
	_all_toggle = UITheme.make_button("Show all designs", "Also list the designs with none ready to place", Vector2(0, 32))
	_all_toggle.toggle_mode = true
	_all_toggle.focus_mode = Control.FOCUS_ALL
	_all_toggle.toggled.connect(func(value: bool): show_all = value; refresh(); _reveal_selected())
	top.add_child(_all_toggle)
	_left = PanelContainer.new()
	_left.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_left)
	_scroll = _scroll_box()
	# Reserve the scrollbar's gutter before the list overflows: adding a design must not move
	# the tiles sideways.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_left.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	_scroll.add_child(list)
	_grid = Grid.new()
	_grid.family = UIRegistry.get_icon_family_color("settlement")
	_grid.heading_display = true
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.item_pressed.connect(_select)
	list.add_child(_grid)
	_empty = VBoxContainer.new()
	_empty.add_theme_constant_override("separation", 8)
	list.add_child(_empty)
	_empty_title = Label.new()
	_empty_title.text = "Nothing ready to place"
	UITheme.format_label(_empty_title, true, MEDIUM.heading, UITheme.TAG_TONES.waiting[0])
	_empty.add_child(_empty_title)
	_empty_text = _text("Finished furniture, uprooted plants, cuttings and packed water stones appear here when available.", MEDIUM.body, UITheme.HEARTH_MUTED)
	_empty.add_child(_empty_text)
	var browse := UITheme.make_button("Browse all designs", "", Vector2(0, 32))
	browse.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	browse.pressed.connect(func(): _all_toggle.button_pressed = true)
	_empty.add_child(browse)
	return column


func _build_side() -> Control:
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	_none = PanelContainer.new()
	_none.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_none.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_none)
	_none_text = _text("Choose a picture to see it here.", MEDIUM.body, INK_SOFT)
	_none_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_none_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_none.add_child(_none_text)
	_card_scroll = _scroll_box()
	_side.add_child(_card_scroll)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.catalog_paper_style())
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_card.add_child(content)
	_name = _text("", MEDIUM.title, INK)
	_name.add_theme_font_override("font", UITheme.display_font())
	content.add_child(_name)
	var showcase := HBoxContainer.new()
	showcase.add_theme_constant_override("separation", 12)
	content.add_child(showcase)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.add_child(_picture)
	_facts = VBoxContainer.new()
	_facts.add_theme_constant_override("separation", 8)
	_facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	showcase.add_child(_facts)
	_appeal = _chip(load("res://assets/ui/icons/appeal.png"))
	_appeal.tooltip_text = "Appeal once installed"
	_facts.add_child(_appeal)
	_description = _text("", MEDIUM.lead, INK)
	content.add_child(_description)
	_note = _text("", MEDIUM.body, INK_SOFT)
	content.add_child(_note)
	# Any room the board has to spare goes here, so the wood and the counts sit at its foot.
	var spare := Control.new()
	spare.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spare)
	_wood_heading = _text("", MEDIUM.small, INK_SOFT)
	content.add_child(_wood_heading)
	_material = Grid.new()
	_material.family = UIRegistry.get_icon_family_color("settlement")
	_material.board = true
	_material.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material.item_pressed.connect(_choose_material)
	content.add_child(_material)
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 12)
	content.add_child(counts)
	for state: String in WORDS:
		var stat := HBoxContainer.new()
		stat.add_theme_constant_override("separation", 8)
		stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		counts.add_child(stat)
		var value := Label.new()
		value.text = "—"
		UITheme.format_label(value, true, MEDIUM.name, INK)
		stat.add_child(value)
		var word := Label.new()
		UITheme.format_label(word, false, MEDIUM.body, INK_SOFT)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stat.add_child(word)
		_values[state] = value
		_words[state] = word
	_values.Crafting.get_parent().tooltip_text = "Items requested in the Worker crafting queue."
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_side.add_child(_actions)
	_place = Button.new()
	_place.text = "Place item"
	UITheme.apply_catalog_primary(_place)
	_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place.size_flags_stretch_ratio = 2.0
	# Its words change with the stock ("Placing · 2 available"); they must not widen the window.
	_place.clip_text = true
	_place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place.pressed.connect(func(): if not selected_key.is_empty(): place_requested.emit(selected_key))
	_actions.add_child(_place)
	# One line, so a longer hint never makes the window taller; hover shows it whole.
	_hint = Label.new()
	UITheme.format_label(_hint, false, MEDIUM.body, UITheme.HEARTH_MUTED)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_side.add_child(_hint)
	return _side


func bind_controller(value: FurniturePlacementController) -> void:
	controller = value
	controller.catalog_changed.connect(refresh)
	controller.tool_active_changed.connect(func(_active: bool): refresh())
	if window != null: window.resized.connect(_clamp_above_dock)
	refresh()


## Whether Place lists this design, shown or not.
func has_design(key: String) -> bool:
	return controller != null and controller.get_defs().has(key) and _entries.any(func(entry: Dictionary): return entry.key == key)


## A shown design's picture tile, or null.
func tile(key: String) -> Button:
	return _grid.get_tile(key)


## The designs shown now, in their order on screen.
func shown_designs() -> Array[String]:
	return _shown.duplicate()


## The chosen design's facts as their chips read, joined by " · ".
func facts_text() -> String:
	return " · ".join(_shown_facts)


func _select(key: String) -> void:
	selected_key = key
	# A tile is the placement action. Use current stock, since a hauler may reserve the last
	# item before the deferred catalog refresh reaches us.
	var available := int(controller.get_catalog_stock().get(key, {}).get("available", 0))
	if available > 0:
		# Re-clicking the active design should keep the player's rotation.
		if controller.active_furniture_key() != key: place_requested.emit(key)
	else:
		controller.deactivate()
	refresh()
	_reveal_selected()


func _choose_material(id: String) -> void:
	if selected_key.is_empty(): return
	controller.material_choices[selected_key] = "" if id == ANY else id
	controller.deactivate()
	refresh()


func set_all_toggle(pressed: bool) -> void:
	_all_toggle.set_pressed_no_signal(pressed)


func begin_browsing() -> void:
	_browse_keys.clear()
	_arrivals.clear()
	_browsing = false
	_scroll.scroll_vertical = 0
	refresh()
	_fit.call_deferred()


func refresh() -> void:
	if controller == null or _grid == null: return
	if window != null and not window.visible: return
	_stock = controller.get_catalog_stock()
	var defs := controller.get_defs()
	for entry: Dictionary in _entries:
		var key := String(entry.key)
		if not defs.has(key) or key in _browse_keys: continue
		if int(_stock[key].available) > 0 or int(_stock[key].reserved) > 0:
			_browse_keys.append(key)
			if _browsing: _arrivals.append(key)
	_browsing = true
	var groups := _groups(defs)
	_shown.clear()
	for group: Dictionary in groups:
		for item: Dictionary in group.items: _shown.append(String(item.id))
	var previous := selected_key
	if not selected_key in _shown:
		selected_key = ""
		for key: String in _shown:
			if selected_key.is_empty() or int(_stock[key].available) > 0:
				selected_key = key
				if int(_stock[key].available) > 0: break
	for group: Dictionary in groups:
		for item: Dictionary in group.items: item.selected = item.id == selected_key
	_grid.show_groups(groups)
	_grid.visible = not _shown.is_empty()
	_empty.visible = _shown.is_empty()
	UITheme.show_tab(_all_toggle, show_all)
	_all_toggle.text = ("✓ " if show_all else "") + "Show all designs"
	if previous != selected_key and controller.is_active():
		controller.deactivate()   # a design that is no longer shown must not keep placing
	var chosen := not selected_key.is_empty()
	_card_scroll.visible = chosen
	_none.visible = not chosen
	if not chosen:
		for value: Label in _values.values(): value.text = "—"
		_place.disabled = true
		_hint.text = ""
		return
	_show_card(selected_key)


## Every category with its designs. While only owned stock shows, designs that arrived after
## the window opened wait in a New group at the end.
func _groups(defs: Dictionary) -> Array:
	var groups: Array = []
	for category: Dictionary in UIRegistry.get_place_catalog().get("categories", []):
		var items: Array = []
		for entry: Dictionary in _entries:
			var key := String(entry.key)
			if entry.category != category.id or not defs.has(key): continue
			if show_all or (key in _browse_keys and not key in _arrivals): items.append(_design(key, defs[key]))
		if not items.is_empty(): groups.append({"id": String(category.id), "title": String(category.label), "items": items})
	if not show_all and not _arrivals.is_empty():
		var arrived: Array = []
		for key: String in _arrivals: arrived.append(_design(key, defs[key]))
		groups.append({"id": "new", "title": "New", "items": arrived})
	return groups


func _design(key: String, definition: Dictionary) -> Dictionary:
	var ready := int(_stock[key].available)
	var coming := int(_stock[key].reserved)
	return {"id": key, "picture": _design_picture(key, definition), "count": ready if ready > 0 else -1, "dim": ready <= 0,
		"tooltip": "%s\n%d ready to place · %d on %s way" % [definition.display_name, ready, coming, "its" if coming == 1 else "their"]}


## The chosen design on the board. Also measures each design's board for the window's
## height, so it only shows.
func _show_card(key: String) -> void:
	var definition: Dictionary = controller.get_defs()[key]
	var stock: Dictionary = _stock[key].duplicate()
	stock.available = controller.placement_available(key)
	var chosen := String(controller.material_choices.get(key, ""))
	var placing := controller.active_furniture_key() == key
	_name.text = String(definition.display_name)
	_picture.texture = _design_picture(key, definition)
	_description.text = String(definition.get("description", ""))
	# Small screens keep the board for what placing needs: the note, the wood and the counts.
	_description.visible = not _description.text.is_empty() and _size != SIZES.small
	var footprint: Dictionary = definition.get("footprint", {})
	var spec := "%d × %d" % [int(footprint.get("width", 1)), int(footprint.get("depth", 1))]
	if definition.has("placement_label"): spec = String(definition.placement_label)
	if definition.has("seating"):
		var seating: Dictionary = definition.seating
		var seats := int(seating.get("max_chairs", seating.get("slots", []).size()))
		spec += " · %d separate log stools" % seats if definition.has("recreation") else " · %d chair%s" % [seats, "" if seats == 1 else "s"]
	elif key == "base:furniture:log_chair": spec += " · Snaps to tables"
	elif String(definition.placement) == "wall": spec += " · Wall mounted"
	var note := String(definition.get("placement_note", ""))
	var action := "Placing · %d available" % stock.available if placing else "Place item" if stock.available > 0 else "None available"
	# While placing, the tool bar has the keys; the window keeps what to do before.
	var hint := "" if placing else "Click an available item to start placing."
	if bool(definition.get("plant", false)):
		spec = "3 × 3 planting area · Open sky"
		if bool(definition.get("from_cutting", false)):
			var plant := SurfaceDetailRegistry.get_definition(String(definition.plant_definition))
			note = "Uses 1 cutting. Matures after %.1f growth days; growth pauses in winter." % float(plant.growth_days)
			action = "Plant cutting" if stock.available > 0 else "No cuttings available"
		else:
			note = "Replant this whole plant. Its shape and seasonal state are preserved." if stock.available > 0 else "Uproot a plant of this type to place it here."
			action = "Replant" if stock.available > 0 else "No uprooted plants"
	if definition.has("recreation") and not definition.has("placement_note"):
		note = "Add log stools on the opposite guides. Play alone with one stool, or together with two for more happiness."
	if definition.has("water_stone"):
		note = "Inactive in storage. A dwarf must place it to start the water effect." if stock.available > 0 else "Allow and pack a water stone to make it available here."
	if String(definition.placement) == "ladder":
		spec = "%d blocks per section" % int(definition.ladder.section_height)
		note = "Aim at a cliff face. The preview shows the full height and section cost before you place it."
		action = "Place ladder" if stock.available > 0 else "Craft ladder sections first"
		hint = "" if placing else "Craft sections at a crude workbench."
	if String(definition.placement) == "bridge":
		spec = "2 blocks wide · Gaps up to %d blocks" % int(definition.bridge.max_span)
		note = "One kit per crossing. Both two-block landings must be level and the same height."
		action = "Place bridge" if stock.available > 0 else "Craft a bridge kit first"
		hint = "" if placing else "Craft a kit at a crude workbench, then choose a narrow crossing."
	_show_facts(spec.split(" · "))
	_appeal_label.text = _appeal_text(definition, chosen)
	_appeal.visible = not _appeal_label.text.is_empty()
	_note.text = note
	_note.visible = not note.is_empty()
	_show_woods(key, definition, chosen)
	_values.Available.text = str(stock.available)
	_values.Reserved.text = str(stock.reserved)
	var crafting := get_tree().get_first_node_in_group("crafting_manager")
	_values.Crafting.text = str(crafting.crafting_count(String(definition.item_key))) if crafting != null else "0"
	var short := 1 if _size == SIZES.small else 0
	for state: String in WORDS: _words[state].text = WORDS[state][short]
	if short == 0 and int(stock.reserved) == 1: _words.Reserved.text = "on its way"
	_place.disabled = stock.available <= 0
	_place.text = action
	_hint.text = hint
	_hint.tooltip_text = hint


## The facts as stone chips beside the picture, the appeal chip last.
func _show_facts(facts: PackedStringArray) -> void:
	if facts == _shown_facts: return
	_shown_facts = facts
	for child: Node in _facts.get_children():
		if child == _appeal: continue
		_facts.remove_child(child)
		child.queue_free()
	for text: String in facts:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.cell_style("chip", 3))
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var label := Label.new()
		label.text = text
		UITheme.format_label(label, false, int(_size.body), UITheme.KEYCAP_INK)
		chip.add_child(label)
		_facts.add_child(chip)
	_facts.move_child(_appeal, -1)


## The appeal it adds once installed: for the chosen wood, or the range across its woods.
func _appeal_text(definition: Dictionary, chosen: String) -> String:
	if not definition.has("appeal"): return ""
	var ids: Array = [chosen]
	if chosen.is_empty() and definition.has("material_group"):
		ids = CraftMaterials.definitions.keys().filter(func(id: String): return CraftMaterials.definitions[id].group == definition.material_group)
	var scores: Array[float] = []
	for id: String in ids: scores.append(float(CraftMaterials.appeal(definition, id).total))
	var number := func(value: float) -> String: return ("%.1f" % value).trim_suffix(".0")
	if is_equal_approx(scores.min(), scores.max()): return number.call(scores.min())
	return "%s–%s" % [number.call(scores.min()), number.call(scores.max())]


## The material to place, as pictures with counts: Any first, then each of the design's group.
## Their names sit under them, except on small screens, where hovering names them.
func _show_woods(key: String, definition: Dictionary, chosen: String) -> void:
	var named := _size != SIZES.small
	var group := String(definition.get("material_group", ""))
	_wood_heading.visible = not group.is_empty()
	_material.visible = not group.is_empty()
	if group.is_empty(): return
	_wood_heading.text = "%s · click one to place only that %s" % [group.to_upper(), group]
	var counts := controller.get_material_stock(key)
	var items: Array = [{"id": ANY, "text": "Any", "caption": "Any " + group if named else "", "selected": chosen.is_empty(),
		"tooltip": "Any %s\nDwarves bring whichever piece is nearest." % group}]
	for id: String in CraftMaterials.definitions:
		var material: Dictionary = CraftMaterials.definitions[id]
		if String(material.group) != group: continue
		var count := int(counts.get(id, 0))
		var name := CraftMaterials.material_name(id)
		var ingredients: Array = material.get("ingredients", [])
		var picture: Texture2D = _picture_at(Inventory.thumbnail_path(String(ingredients[0]))) if not ingredients.is_empty() else null
		items.append({"id": id, "picture": picture, "text": "" if picture != null else name, "count": count if count > 0 else -1,
			"dim": count <= 0, "selected": chosen == id, "caption": name if named else "",
			"tooltip": "%s · %d ready\nPlace only %s pieces." % [name, count, name.to_lower()]})
	_material.show_groups([{"id": "materials", "items": items}])


func _design_picture(key: String, definition: Dictionary) -> Texture2D:
	var path := "res://assets/ui/furniture/%s.png" % key.get_slice(":", 2)
	if not ResourceLoader.exists(path): path = Inventory.thumbnail_path(String(definition.item_key))
	return _picture_at(path)


func _picture_at(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


func _reveal_selected() -> void:
	_reveal.call_deferred()


## Look the tile up when the scroll moves: a refresh in between may rebuild the grid.
func _reveal() -> void:
	var picture: Control = _grid.get_tile(selected_key)
	if picture != null and picture.is_visible_in_tree(): _scroll.ensure_control_visible(picture)


# ── Size and fit ──────────────────────────────────────────────────────────────

func fit_above_dock(dock_top: float) -> void:
	_dock_top = dock_top
	_fit.call_deferred()


func _fit() -> void:
	if window == null or not is_inside_tree() or controller == null: return
	var viewport := get_viewport_rect().size
	_size = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	_apply_size()
	refresh()
	# The columns are as tall as the tallest board needs, as far as the room the window's
	# frame leaves above the dock allows; the designs scroll, and so does a board that
	# cannot show whole.
	_columns.custom_minimum_size.y = 0
	var chrome := window.get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	var room := maxf(200.0, _dock_top - 12.0 - chrome)
	_columns.custom_minimum_size.y = minf(room, maxf(float(_size.columns), _tallest_side()))
	window.reset_size()
	window.clamp_to_viewport()
	_clamp_above_dock.call_deferred()
	_settle_layout()
	_reveal_selected()


## The side's height when every design's board shows whole at this size: the tallest board,
## with the actions and the hint under it. Measured on the live board, so wrapped text counts
## as it will show.
func _tallest_side() -> float:
	if not is_visible_in_tree() or _stock.is_empty(): return 0.0
	_card_scroll.visible = true
	_none.visible = false
	window.reset_size()
	UITheme.lay_out_now(window)   # every column takes its width for this size
	_card.size.x = _card_scroll.size.x   # a board that fits has no scrollbar beside it
	var tallest := 0.0
	for entry: Dictionary in _entries:
		if not controller.get_defs().has(entry.key): continue
		_show_card(String(entry.key))
		UITheme.lay_out_now(_card)
		tallest = maxf(tallest, _card.get_combined_minimum_size().y)
	refresh()
	var separation := float(_side.get_theme_constant("separation"))
	return ceilf(tallest + _actions.get_combined_minimum_size().y + _hint.get_combined_minimum_size().y + separation * 2.0)


func _apply_size() -> void:
	var s := _size
	_grid.gap = float(s.gap)
	_grid.heading_size = int(s.heading)
	_grid.set_tile_size(float(s.tile))
	_left.custom_minimum_size.x = float(s.per_row) * (float(s.tile) + float(s.gap)) + 40.0   # the inset and its scrollbar
	_side.custom_minimum_size.x = float(s.card)
	_intro.visible = s != SIZES.small   # small screens: the hover card says it
	_intro.add_theme_font_size_override("font_size", int(s.body))
	_all_toggle.custom_minimum_size.y = maxf(30.0, float(s.action) * 0.6)
	_all_toggle.add_theme_font_size_override("font_size", int(s.label))
	_empty_title.add_theme_font_size_override("font_size", s.heading)
	_empty_text.add_theme_font_size_override("font_size", s.body)
	_none_text.add_theme_font_size_override("font_size", s.body)
	_picture.custom_minimum_size = Vector2(float(s.picture), float(s.picture) * 0.82)
	_name.add_theme_font_size_override("font_size", s.title)
	_description.add_theme_font_size_override("font_size", s.body)
	_note.add_theme_font_size_override("font_size", int(s.body))
	_appeal_label.add_theme_font_size_override("font_size", int(s.type.lead))
	_shown_facts = PackedStringArray()   # the chips are rebuilt at this size
	_wood_heading.add_theme_font_size_override("font_size", s.label)
	_material.caption_size = int(s.label)
	_material.gap = float(s.wood_gap)   # room for each wood's name under its tile
	_material.set_tile_size(float(s.wood))
	for value: Label in _values.values(): value.add_theme_font_size_override("font_size", s.value)
	for word: Label in _words.values(): word.add_theme_font_size_override("font_size", s.word)
	_place.custom_minimum_size.y = float(s.action)
	_place.add_theme_font_size_override("font_size", s.verb)
	_hint.add_theme_font_size_override("font_size", int(s.label))


func _settle_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	# Wrapped text needs its final width before measuring.
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

## A stone chip with a picture and a value: the appeal badge.
func _chip(icon: Texture2D) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.cell_style("chip", 3))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var picture := TextureRect.new()
	picture.texture = icon
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(24, 24)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	_appeal_label = Label.new()
	UITheme.format_label(_appeal_label, true, MEDIUM.lead, UITheme.KEYCAP_INK)
	row.add_child(_appeal_label)
	return chip


func _scroll_box() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UITheme.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
