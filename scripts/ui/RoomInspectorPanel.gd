extends MarginContainer

## The room window (doc 261, phase 5), after Stonehearth's Town Overview: a header with the
## name and a banner, then rows of picture, value and goal.
## - The band names the room ("Birna's bedroom"). The header gives its kind with tags
##   (Sealed, the owner's bonus), who sleeps there, and the appeal banner.
## - Overview: what makes it its kind, each need with its count and goal and a tick when
##   met (a plain room is shown the kind it is nearest, and what is missing); its comfort
##   (heating and temperature, each with its goal); and the furniture in it.
## - Appeal (doc 23 "Room appeal"): the appeal and its word on the scale, then each part with
##   its picture and value, and the share a large room counts.
## - Details: volume, doors, floor level, heating and the season's reach.
## Presentation only: RoomManager owns rooms, their kinds (room_kinds.json), temperature
## and appeal. A selection overlay never represents the room's illumination.
const Portrait = preload("res://scripts/ui/DwarfPortrait.gd")
const Grid = preload("res://scripts/ui/PictureGrid.gd")
const Appeal = preload("res://scripts/components/RoomAppeal.gd")
const HAY := Color("e2c06a")
const MUTED := Color("aeb5ad")
const MOSS := Color("8fbf5a")
const RUST := Color("d3856e")
# Text sizes come from the type scale (doc 23, "Type").
const LARGE := UITheme.TYPE_LARGE
const MEDIUM := UITheme.TYPE_MEDIUM
const SMALL := UITheme.TYPE_SMALL
## Sizes by the screen's height: large from 1300 px tall (the concept's sizes on the
## 7680×2160 screen), small below 650 px. `body` is the page's height: the window keeps it
## from tab to tab, as far as the room above the dock allows, and longer pages scroll.
const SIZES := {
	"large": {"width": 860, "side": 20, "top": 12, "bottom": 10, "kind": LARGE.name, "tag": LARGE.small, "owner_tile": 64, "owner": LARGE.lead,
		"note": LARGE.body, "banner": Vector2i(35, 49), "face": 60, "word": LARGE.lead, "value": LARGE.title, "tab": Vector2(200, 42),
		"tab_font": LARGE.body, "label": LARGE.small, "tile": 44, "name": LARGE.lead, "count": LARGE.lead, "goal": LARGE.body, "name_width": 200,
		"count_width": 210, "row": 52, "furniture": 44, "hint": LARGE.body, "gap": 12, "body": 660, "type": LARGE},
	"medium": {"width": 600, "side": 14, "top": 8, "bottom": 8, "kind": MEDIUM.name, "tag": MEDIUM.small, "owner_tile": 48, "owner": MEDIUM.lead,
		"note": MEDIUM.body, "banner": Vector2i(26, 36), "face": 44, "word": MEDIUM.lead, "value": MEDIUM.title, "tab": Vector2(140, 34),
		"tab_font": MEDIUM.body, "label": MEDIUM.small, "tile": 34, "name": MEDIUM.lead, "count": MEDIUM.lead, "goal": MEDIUM.body, "name_width": 140,
		"count_width": 150, "row": 40, "furniture": 34, "hint": MEDIUM.body, "gap": 8, "body": 420, "type": MEDIUM},
	"small": {"width": 470, "side": 10, "top": 6, "bottom": 6, "kind": SMALL.name, "tag": SMALL.small, "owner_tile": 36, "owner": SMALL.lead,
		"note": SMALL.body, "banner": Vector2i(20, 28), "face": 32, "word": SMALL.lead, "value": SMALL.title, "tab": Vector2(110, 30),
		"tab_font": SMALL.body, "label": SMALL.small, "tile": 28, "name": SMALL.lead, "count": SMALL.lead, "goal": SMALL.body, "name_width": 108,
		"count_width": 118, "row": 34, "furniture": 30, "hint": SMALL.body, "gap": 6, "body": 260, "type": SMALL},
}
## How a missing need reads in "One step from a bedroom: add a light."
const MISSING := {"beds": "a bed", "lights": "a light", "doors": "a door", "owner": "an owner for the bed"}

var window: UIWindow
var dock: Node   # DockUI, when there is one: the window fits above it
var _size: Dictionary = {}
var _room := {}
var _shown := {}   # what each rebuilt part last showed, so live refreshes keep their nodes
var _owner_agent: DwarfAgent
var _portrait: SubViewport
var _portrait_model: Node3D
var _column: VBoxContainer
var _header: HBoxContainer
var _kind: Label
var _tags: HFlowContainer
var _owner_row: HBoxContainer
var _owner_frame: PanelContainer
var _owner_picture: TextureRect
var _owner_line: Label
var _owner_note: Label
var _banner: Control
var _banner_art: TextureRect
var _banner_face: TextureRect
var _banner_word: Label
var _banner_value: Label
var _tabs: Array[Button] = []
var _scroll: ScrollContainer
var _overview: VBoxContainer
var _details: VBoxContainer
var _needs_heading: Label
var _needs: VBoxContainer
var _need_rows := {}   # need id -> its row
var _short: Label
var _comfort_heading: Label
var _comfort := {}   # heating, temperature -> their rows
var _furniture_heading: Label
var _furniture
var _furniture_empty: Label
var _appeal: VBoxContainer
var _appeal_parts: VBoxContainer
var _appeal_rows: Array[Dictionary] = []
var _appeal_empty: Label
var _appeal_total: Dictionary
var _appeal_size: Dictionary
var _appeal_score: Label
var _appeal_scale: AppealScale
var _appeal_note: Label
var _appeal_feel: Label
var _detail_rows := {}
var _detail_note: Label
var _hint: Label
var _headings: Array[Label] = []
var _textures := {}


func _ready() -> void:
	UITheme.apply_surface(self)
	_column = VBoxContainer.new()
	add_child(_column)
	_build_header()
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	_column.add_child(tab_row)
	for caption: String in ["Overview", "Appeal", "Details"]:
		var tab := Button.new()
		tab.text = caption
		tab.focus_mode = Control.FOCUS_ALL
		tab.pressed.connect(_show_tab.bind(_tabs.size()))
		tab_row.add_child(tab)
		_tabs.append(tab)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_column.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_overview = VBoxContainer.new()
	_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_overview)
	var needs := _inset(_overview)
	_needs_heading = _heading(needs, "")
	_needs = VBoxContainer.new()
	needs.add_child(_needs)
	_short = _text(needs, "", MEDIUM.body, HAY)
	var comfort := _inset(_overview)
	_comfort_heading = _heading(comfort, "COMFORT")
	for id: String in ["heating", "temperature"]:
		_comfort[id] = _goal_row(comfort, id)
	_furniture_heading = _heading(_overview, "IN THIS ROOM")
	_furniture = Grid.new()
	_furniture.family = UIRegistry.get_icon_family_color("settlement")
	_furniture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview.add_child(_furniture)
	_furniture_empty = _text(_overview, "Nothing installed yet.", MEDIUM.body, MUTED)
	_build_appeal(pages)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_details)
	for entry: Array in [["volume", "Room volume"], ["doors", "Doors"], ["level", "Average floor level"],
			["heat", "Heating"], ["season", "Seasonal influence"]]:
		_detail_rows[entry[0]] = _detail_row(_details, entry[1])
	_detail_note = _text(_details, "Rock shelters rooms from the weather. A stone hearth warms a room; torches mainly give light. Cold or hot sleep lowers happiness.", MEDIUM.body, MUTED)
	_hint = _text(_column, "Select another room to inspect · Esc to finish", MEDIUM.body, MUTED)
	get_viewport().size_changed.connect(func(): _fit.call_deferred())
	_apply_size(SIZES.medium)
	_show_tab(0)


func _build_header() -> void:
	_header = HBoxContainer.new()
	_column.add_child(_header)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 8)
	_header.add_child(identity)
	_kind = _text(identity, "", MEDIUM.name, UITheme.CARD_TITLE, true)
	_kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tags = HFlowContainer.new()
	_tags.add_theme_constant_override("h_separation", 8)
	_tags.add_theme_constant_override("v_separation", 6)
	identity.add_child(_tags)
	# Who sleeps here: the owner's live portrait on the people tile, or the bed.
	_owner_row = HBoxContainer.new()
	_owner_row.add_theme_constant_override("separation", 12)
	identity.add_child(_owner_row)
	_owner_picture = TextureRect.new()
	_owner_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_owner_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_owner_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_owner_frame = UITheme.framed_picture(_owner_picture)
	_owner_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_owner_row.add_child(_owner_frame)
	var owner_words := VBoxContainer.new()
	owner_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owner_words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owner_words.add_theme_constant_override("separation", 2)
	_owner_row.add_child(owner_words)
	_owner_line = _text(owner_words, "", MEDIUM.lead, UITheme.CARD_TITLE, true)
	_owner_note = _text(owner_words, "", MEDIUM.small, MUTED)
	# The appeal banner, hung at the right like Stonehearth's Town Morale ribbon.
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_PASS
	_banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_header.add_child(_banner)
	_banner_art = TextureRect.new()
	_banner_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_banner_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_art)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	_banner.add_child(stack)
	_banner_face = TextureRect.new()
	_banner_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_banner_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner_face.texture = UIRegistry.get_room_symbol("appeal")
	stack.add_child(_banner_face)
	_banner_word = _text(stack, "", MEDIUM.title, UITheme.CARD_TITLE, true)
	_banner_value = _text(stack, "", MEDIUM.name, UITheme.CARD_TITLE, true)
	for label: Label in [_banner_word, _banner_value]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## The Appeal tab: the appeal with its word on the scale and what a stay leaves, then what
## the room holds, each part with its picture and value, and the sums: what they add up to
## and the share a large room counts.
func _build_appeal(pages: Control) -> void:
	_appeal = VBoxContainer.new()
	_appeal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_appeal)
	_appeal_score = _text(_appeal, "", MEDIUM.title, UITheme.CARD_TITLE, true)
	_appeal_scale = AppealScale.new()
	_appeal_scale.words = RoomManager.appeal_config.get("words", [])
	_appeal_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_appeal.add_child(_appeal_scale)
	_appeal_note = _text(_appeal, "", MEDIUM.body, MUTED)
	_appeal_feel = _text(_appeal, "", MEDIUM.body, HAY)
	var held := _inset(_appeal)
	_heading(held, "WHAT IT HOLDS")
	_appeal_parts = VBoxContainer.new()
	held.add_child(_appeal_parts)
	_appeal_empty = _text(held, "Nothing here adds appeal yet. Furniture does.", MEDIUM.body, MUTED)
	var sums := _inset(_appeal)
	_heading(sums, "ITS APPEAL")
	_appeal_total = _part_row(sums, UIRegistry.get_room_symbol("appeal"))
	_appeal_size = _part_row(sums, UIRegistry.get_room_symbol("walls"))


# ── Showing a room ────────────────────────────────────────────────────────────

func show_room(room: Dictionary) -> void:
	_room = room
	var counts := RoomManager.room_counts(room)
	var kind := RoomManager.nearest_kind(room)
	var own := RoomManager.room_kind(room)
	_kind.text = RoomManager.room_label(room)
	_show_tags(room, own)
	_show_owner(room, own, int(counts.beds))
	var appeal := RoomManager.room_appeal(room)
	_banner_word.text = String(appeal.word.get("word", ""))
	_banner_value.text = Appeal.number(float(appeal.score))
	_banner.tooltip_text = "Appeal %s · %s\nWhat the room holds, for its size. The Appeal tab lists each part." % [
		_banner_value.text, _banner_word.text]
	_show_appeal(room, appeal)
	# What makes it its kind: each need with its count and goal.
	var missing := RoomManager.missing_needs(room, kind)
	_needs_heading.text = String(kind.get("shows", "What makes a room")).to_upper()
	var needs: Dictionary = kind.get("needs", {})
	var ids: Array = needs.keys() + ["walls"]
	if _changed("needs", ids):
		_clear(_needs)
		_need_rows.clear()
		for id: String in ids: _need_rows[id] = _goal_row(_needs, id)
	for id: String in needs:
		var rule: Dictionary = needs[id]
		var count := int(counts.get(id, 0))
		_set_row(_need_rows[id], {"beds": "Bed", "lights": "Light", "doors": "Door"}.get(id, id.capitalize()),
			"%d source%s" % [count, "" if count == 1 else "s"] if id == "lights" else str(count), _needs_words(rule), not id in missing)
	_set_row(_need_rows.walls, "Walls", "Sealed", "", true)   # a room is a sealed space
	_short.visible = own.is_empty() and not missing.is_empty()
	if _short.visible:
		var noun := String(kind.get("shows", "")).trim_prefix("What makes it ")
		var words: Array = missing.map(func(need: String): return MISSING.get(need, need))
		_short.text = ("One step from %s: add %s." % [noun, words[0]]) if words.size() == 1 \
			else "Add %s to make it %s." % [" and ".join(PackedStringArray(words)), noun]
	var pieces := RoomManager.room_furniture(room)
	_show_comfort(room, pieces)
	_show_furniture(pieces)
	# Details.
	_detail_rows.volume.text = "%d blocks" % int(room.get("volume", 0))
	_detail_rows.doors.text = str(int(counts.doors))
	_detail_rows.level.text = "%.1f" % float(room.get("mean_floor_y", 0.0))
	var heat := int(room.get("heat_units", 0))
	_detail_rows.heat.text = "%d units · +%.1f °C" % [heat, float(room.get("heat_bonus_c", 0.0))]
	_detail_rows.season.text = "%d%%" % roundi(float(room.get("seasonal_influence", 0.0)) * 100)
	_fit.call_deferred()


func _show_tags(room: Dictionary, own: Dictionary) -> void:
	var tags: Array = [["Sealed", "fine"]]
	if bool(room.get("is_frozen_vault", false)): tags.append(["Frozen vault", "fine"])
	if bool(own.get("owner", false)):
		var bonus := roundi(float(TaskManager.get_config_section("mood").personal_bedroom.bonus) * 100)
		tags.append(["Owner's bonus +%d" % bonus, "fine"])
	if not _changed("tags", tags): return
	_clear(_tags)
	for tag: Array in tags:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + String(tag[1]), 3))
		var label := Label.new()
		label.text = String(tag[0])
		UITheme.format_label(label, false, int(_size.tag), UITheme.tag_ink(String(tag[1])))
		panel.add_child(label)
		_tags.add_child(panel)


## Who sleeps here: the owner with their portrait, or how the beds are shared.
func _show_owner(room: Dictionary, own: Dictionary, beds: int) -> void:
	var owner_id := int(room.get("owner_id", -1))
	var owner: DwarfAgent = TaskManager.get_agent(owner_id) if owner_id >= 0 else null
	_owner_row.visible = beds > 0
	if not _owner_row.visible:
		_set_owner(null)
		return
	_set_owner(owner if is_instance_valid(owner) else null)
	if is_instance_valid(owner):
		_owner_line.text = "%s sleeps here" % owner.dwarf_name
		_owner_note.text = "Assign another owner from the bed."
	elif beds > 1:
		_owner_line.text = "%d beds, shared" % beds
		_owner_note.text = "Owners keep their own beds; there is no owner's bonus here."
	else:
		_owner_line.text = "No one owns the bed"
		_owner_note.text = "Assign the bed to a dwarf for the owner's bonus."
	_owner_frame.tooltip_text = _owner_line.text


## The owner's live portrait, or the bed's picture when no one owns it.
func _set_owner(agent: DwarfAgent) -> void:
	if agent == _owner_agent and (agent != null or _owner_picture.texture == UIRegistry.get_room_symbol("beds")): return
	_owner_agent = agent
	if is_instance_valid(_portrait_model): _portrait_model.free()
	_portrait_model = null
	if agent == null:
		if _portrait != null: _portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_owner_picture.texture = UIRegistry.get_room_symbol("beds")
		return
	if _portrait == null: _portrait = Portrait.create_viewport(_owner_picture)
	_owner_picture.texture = _portrait.get_texture()
	_portrait_model = Portrait.create_model(_portrait, agent)


## Comfort: the warmth the room's heat sources add and its temperature, each with its goal.
## (Details keeps the heat in units.)
func _show_comfort(room: Dictionary, pieces: Dictionary) -> void:
	var config := RoomManager.temperature_config
	var heat := int(room.get("heat_units", 0))
	var temperature := float(room.get("temp_c", 0.0))
	var comfort := RoomManager.comfort_label(temperature)
	var cosy := comfort == "Comfortable"
	var sources := 0
	for key: String in pieces:
		if not ContentRegistry.furniture_def(key).get("heat_source", {}).is_empty(): sources += int(pieces[key])
	if heat > 0:
		_set_row(_comfort.heating, "Heating", "+%.1f °C" % float(room.get("heat_bonus_c", 0.0)),
			"%d heat source%s" % [sources, "" if sources == 1 else "s"], true)
	else:
		_set_row(_comfort.heating, "Heating", "None", "" if cosy else "Add a hearth", cosy)
	var goal := ""
	if comfort == "Hot": goal = "%d °C or less" % roundi(float(config.comfortable_max_c))
	elif not cosy: goal = "%d °C or more" % roundi(float(config.comfortable_min_c))
	_set_row(_comfort.temperature, "Temperature", "%.1f °C · %s" % [temperature, comfort], goal, cosy)


func _show_furniture(pieces: Dictionary) -> void:
	var keys: Array = pieces.keys()
	keys.sort()
	var items := []
	for key: String in keys:
		var name := String(ContentRegistry.furniture_def(key).get("display_name", key.get_slice(":", 2).capitalize()))
		items.append({"id": key, "picture": _texture("res://assets/ui/furniture/%s.png" % key.get_slice(":", 2)),
			"count": int(pieces[key]), "tooltip": "%s × %d" % [name, int(pieces[key])]})
	_furniture.show_groups([{"id": "furniture", "items": items}])
	_furniture.visible = not items.is_empty()
	_furniture_empty.visible = items.is_empty()


## The Appeal tab from RoomManager.room_appeal: the appeal on the scale and what a sleep, a
## meal or a game here leaves, then each part, what they add up to and the share the room's
## size counts.
func _show_appeal(room: Dictionary, appeal: Dictionary) -> void:
	var parts: Array = appeal.get("parts", [])
	if _changed("appeal", parts.map(func(part: Dictionary): return [part.key, part.name, part.value])):
		_clear(_appeal_parts)
		_appeal_rows.clear()
		for part: Dictionary in parts:
			var key := String(part.key)
			var picture: Texture2D = UIRegistry.get_room_symbol(key) if key in ["loose", "stocked"] \
				else _texture("res://assets/ui/furniture/%s.png" % key.get_slice(":", 2))
			_appeal_rows.append(_part_row(_appeal_parts, picture))
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var count := int(part.count)
		_set_part(_appeal_rows[i], String(part.name), "%d × %s" % [count, Appeal.signed(float(part.value))] if count > 1 else "",
			float(part.value) * count)
	_appeal_empty.visible = parts.is_empty()
	var total := float(appeal.total)
	var share := float(appeal.share)
	var tiles := int(appeal.tiles)
	_set_part(_appeal_total, "What it holds", "", total, false)
	_set_part(_appeal_size, "Room size", ("%d floor tiles · counts %d%%" % [tiles, roundi(share * 100.0)]) if share < 1.0
		else "%d floor tiles · counts in full" % tiles, total * share, false)
	var word: Dictionary = appeal.word
	var score := float(appeal.score)
	_appeal_score.text = "Appeal %s · %s" % [Appeal.number(score), String(word.get("word", ""))]
	_appeal_scale.score = score
	_show_feeling(room, appeal)
	_appeal_scale.queue_redraw()
	var points := roundi(float(word.get("points", 0.0)) * 100.0)
	if points != 0:
		_appeal_note.text = "A sleep, a meal or a game here leaves %s thought: %s%d happiness for a while." % [
			"a good" if points > 0 else "a bad", "+" if points > 0 else "−", absi(points)]
	else:
		var words: Array = RoomManager.appeal_config.get("words", [])
		var next := words.find(word) + 1
		_appeal_note.text = "A %s room leaves no thought. At %s it is %s." % [String(word.get("word", "")).to_lower(),
			Appeal.number(float(word.below)), String(words[next].word)] if word.has("below") and next < words.size() \
			else "A %s room leaves no thought." % String(word.get("word", "")).to_lower()


## How the owner of a personal bedroom feels it, when a taste of theirs they have found
## moves it (doc 41 "Tastes"): marked in hay on the scale, and said under it.
func _show_feeling(room: Dictionary, appeal: Dictionary) -> void:
	var owner: DwarfAgent = TaskManager.get_agent(int(room.get("owner_id", -1))) if int(room.get("owner_id", -1)) >= 0 else null
	var felt: Dictionary = owner.get_tastes().felt(appeal) if is_instance_valid(owner) else {}
	var taste := String(felt.get("taste", ""))
	_appeal_feel.visible = not taste.is_empty()
	_appeal_scale.felt = float(felt.score) if not taste.is_empty() else NAN
	if taste.is_empty(): return
	_appeal_feel.text = "%s %s, so to them it is %s %s." % [owner.dwarf_name, owner.get_tastes().describe(taste),
		String(felt.word.get("word", "")), Appeal.number(float(felt.score))]


## Opens a tab by its name: overview, appeal (from the Appeal view) or details.
func show_tab_named(tab: String) -> void:
	var index := ["overview", "appeal", "details"].find(tab)
	if index >= 0: _show_tab(index)


func _show_tab(index: int) -> void:
	_overview.visible = index == 0
	_appeal.visible = index == 1
	_details.visible = index == 2
	for i in range(_tabs.size()): UITheme.show_tab(_tabs[i], i == index)
	_scroll.scroll_vertical = 0
	_fit.call_deferred()


# ── Size and fit ──────────────────────────────────────────────────────────────

## Take the size for the screen and the room above the dock. The page keeps one height
## from tab to tab, and longer pages scroll.
func _fit() -> void:
	if window == null or not is_visible_in_tree(): return
	var viewport := get_viewport_rect().size
	var chosen: Dictionary = SIZES.large if viewport.y >= 1300.0 else (SIZES.small if viewport.y < 650.0 else SIZES.medium)
	if chosen != _size:
		_apply_size(chosen)
		if not _room.is_empty(): show_room(_room)
	custom_minimum_size.x = minf(float(_size.width) - 8.0, viewport.x - 32.0)   # the frame's sides
	var top := UIWindow.VIEWPORT_MARGIN if viewport.y < 650.0 else 24.0
	var bottom: float = (dock.dock_top() if is_instance_valid(dock) else viewport.y) - 8.0
	_scroll.custom_minimum_size.y = 0.0
	window.reset_size()
	UITheme.lay_out_now(window)
	var chrome := window.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(bottom - top - chrome, 96.0, float(_size.body))
	window.reset_size()
	window.position.y = minf(window.position.y, maxf(top, bottom - window.size.y))
	window.clamp_to_viewport()


func _apply_size(s: Dictionary) -> void:
	_size = s
	_shown.clear()   # rebuild the rows and tags at the new size
	var gap := int(s.gap)
	for side: String in ["left", "right"]: add_theme_constant_override("margin_" + side, int(s.side))
	add_theme_constant_override("margin_top", int(s.top))
	add_theme_constant_override("margin_bottom", int(s.bottom))
	_column.add_theme_constant_override("separation", gap)
	_header.add_theme_constant_override("separation", gap + 6)
	UITheme.format_label(_kind, true, int(s.kind), UITheme.CARD_TITLE, 6)
	_kind.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	_owner_frame.custom_minimum_size = Vector2.ONE * float(s.owner_tile)
	_owner_line.add_theme_font_size_override("font_size", s.owner)
	_owner_note.add_theme_font_size_override("font_size", s.note)
	var cells: Vector2i = s.banner
	_banner.custom_minimum_size = Vector2(cells * UITheme.CARD_CELL)
	_banner_art.texture = UITheme.banner_texture(UIRegistry.get_icon_family_color("settlement"), cells.x, cells.y)
	_banner_art.size = _banner.custom_minimum_size
	(_banner_face.get_parent() as VBoxContainer).offset_top = roundf(float(s.face) * 0.23)
	_banner_face.custom_minimum_size = Vector2.ONE * float(s.face)
	_banner_word.add_theme_font_size_override("font_size", s.word)
	_banner_value.add_theme_font_size_override("font_size", s.value)
	for label: Label in [_banner_word, _banner_value]:
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", UITheme.CARD_TITLE_OUTLINE)
	for tab: Button in _tabs:
		tab.custom_minimum_size = s.tab
		tab.add_theme_font_size_override("font_size", s.tab_font)
	for page: VBoxContainer in [_overview, _appeal, _details]: page.add_theme_constant_override("separation", gap + 4)
	for label: Label in _headings: label.add_theme_font_size_override("font_size", s.label)
	for label: Label in [_short, _furniture_empty, _detail_note, _hint, _appeal_empty, _appeal_note, _appeal_feel]:
		label.add_theme_font_size_override("font_size", int(s.hint))
	for row: Dictionary in _comfort.values(): _size_row(row)
	for row: Dictionary in [_appeal_total, _appeal_size]: _size_part(row)
	UITheme.format_label(_appeal_score, true, int(s.word), UITheme.CARD_TITLE, 4)
	_appeal_scale.font_size = int(s.goal)
	_appeal_scale.custom_minimum_size.y = roundf(float(s.tile) * 0.55) + float(s.goal) + 12.0
	_furniture.set_tile_size(float(s.furniture))
	for label: Label in _detail_rows.values(): label.add_theme_font_size_override("font_size", s.count)


# ── Pieces ────────────────────────────────────────────────────────────────────

## A Town Overview row: the picture, the name, the count and the goal, ticked when met.
func _goal_row(parent: Control, symbol: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = UIRegistry.get_room_symbol(symbol)
	var frame := UITheme.framed_picture(picture)   # on the settlement tile
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)
	var title := _text(row, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	var count := _text(row, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	var goal := _text(row, "", MEDIUM.lead, MUTED)
	for label: Label in [title, count, goal]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.size_flags_horizontal = Control.SIZE_FILL
	count.size_flags_horizontal = Control.SIZE_FILL
	goal.clip_text = true
	goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var mark := PanelContainer.new()
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var glyph := Label.new()
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(glyph)
	var parts := {"row": row, "frame": frame, "title": title, "count": count, "goal": goal, "mark": mark, "glyph": glyph}
	if not _size.is_empty(): _size_row(parts)
	return parts


func _set_row(row: Dictionary, title: String, count: String, goal: String, met: bool) -> void:
	row.title.text = title
	row.count.text = count
	row.count.add_theme_color_override("font_color", UITheme.CARD_TITLE if met else HAY)
	row.goal.text = goal
	row.goal.tooltip_text = goal
	row.row.tooltip_text = "%s · %s%s" % [title, count, "" if goal.is_empty() else " · " + goal]
	var tone := "fine" if met else "waiting"
	row.mark.add_theme_stylebox_override("panel", UITheme.cell_style("tag_" + tone, 3))
	row.glyph.text = "✓" if met else "!"
	UITheme.format_label(row.glyph, true, int(_size.goal), UITheme.tag_ink(tone))


func _size_row(row: Dictionary) -> void:
	var s := _size
	row.row.custom_minimum_size.y = float(s.row)
	row.frame.custom_minimum_size = Vector2.ONE * float(s.tile)
	row.title.add_theme_font_size_override("font_size", s.name)
	row.title.custom_minimum_size.x = float(s.name_width)
	row.count.add_theme_font_size_override("font_size", s.count)
	row.count.custom_minimum_size.x = float(s.count_width)
	row.goal.add_theme_font_size_override("font_size", s.goal)
	row.glyph.add_theme_font_size_override("font_size", s.goal)


## A part of the room's appeal: its picture, its name, a note and what it adds or takes.
func _part_row(parent: Control, picture_texture: Texture2D) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = picture_texture
	var frame := UITheme.framed_picture(picture)   # on the settlement tile
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)
	var title := _text(row, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	var note := _text(row, "", MEDIUM.lead, MUTED)
	var value := _text(row, "", MEDIUM.heading, UITheme.CARD_TITLE, true)
	for label: Label in [title, note, value]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A long name gives way; the note and the value keep their width.
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.size_flags_horizontal = Control.SIZE_SHRINK_END
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var parts := {"row": row, "frame": frame, "title": title, "note": note, "value": value}
	if not _size.is_empty(): _size_part(parts)
	return parts


func _set_part(row: Dictionary, title: String, note: String, value: float, signed := true) -> void:
	row.title.text = title
	row.note.text = note
	row.value.text = Appeal.signed(value) if signed else Appeal.number(value)
	row.value.add_theme_color_override("font_color", MOSS if signed and value > 0.0 else (RUST if value < 0.0 else UITheme.CARD_TITLE))
	row.row.tooltip_text = "%s%s · %s" % [title, "" if note.is_empty() else " · " + note, row.value.text]


func _size_part(row: Dictionary) -> void:
	var s := _size
	row.row.custom_minimum_size.y = float(s.row)
	row.frame.custom_minimum_size = Vector2.ONE * float(s.tile)
	row.title.add_theme_font_size_override("font_size", s.name)
	row.note.add_theme_font_size_override("font_size", s.goal)
	row.value.add_theme_font_size_override("font_size", s.count)
	row.value.custom_minimum_size.x = float(s.count) * 3.5


## How a need reads: "Needs 1", "Needs 2 or more", "Needs 1 to 3".
static func _needs_words(rule: Dictionary) -> String:
	var least := int(rule.get("least", 0))
	if not rule.has("most"): return "Needs %d" % least if least <= 1 else "Needs %d or more" % least
	var most := int(rule.most)
	return "Needs %d" % least if most == least else "Needs %d to %d" % [least, most]


func _detail_row(parent: Control, title: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var caption := _text(row, title, MEDIUM.body, MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _text(row, "", MEDIUM.body, UITheme.CARD_TITLE, true)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	return value


func _inset(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.hearth_panel(true))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _heading(parent: Control, text: String) -> Label:
	var label := _text(parent, text, MEDIUM.small, HAY)
	_headings.append(label)
	return label


func _text(parent: Control, value: String, font_size: int, color := UITheme.CARD_TEXT, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.format_label(label, display, font_size, color)
	parent.add_child(label)
	return label


func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path) if ResourceLoader.exists(path) else load("res://assets/ui/icons/stocks.png")
	return _textures[path]


## Whether a rebuilt part's contents changed since it last showed.
func _changed(key: String, value: Variant) -> bool:
	if _shown.has(key) and _shown[key] == value: return false
	_shown[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return true


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_portrait_model): _portrait_model.free()


## The room's appeal on its word scale (appeal.json): a segment per word in its tint with the
## word under it, a mark at the appeal, and a hay mark where one dwarf feels it. Each segment spans the scores between two turns;
## the open ends span as much as their neighbour.
class AppealScale extends Control:
	var words: Array = []
	var score := 0.0
	var felt := NAN   # how one dwarf feels it, marked in hay; none while NAN
	var font_size := 15

	func _draw() -> void:
		if words.is_empty(): return
		var segment := size.x / words.size()
		var font := UITheme.body_font()
		var bar := maxf(8.0, size.y - float(font_size) - 12.0)
		for i in range(words.size()):
			var tint := Color(String(words[i].get("tint", "#9a978b")))
			draw_rect(Rect2(i * segment + 2.0, 4.0, segment - 4.0, bar - 4.0), tint.darkened(0.1))
			draw_string(font, Vector2(i * segment, bar + 6.0 + font.get_ascent(font_size)), String(words[i].word),
				HORIZONTAL_ALIGNMENT_CENTER, segment, font_size, tint)
		if not is_nan(felt): draw_rect(Rect2(place(felt) - 3.0, 0.0, 6.0, bar + 2.0), Color("e2c06a"))
		var x := place(score)
		draw_rect(Rect2(x - 3.0, 0.0, 6.0, bar + 2.0), UITheme.CARD_TITLE)
		draw_rect(Rect2(x - 3.0, 0.0, 6.0, bar + 2.0), UITheme.CARD_TITLE_OUTLINE, false, 1.0)

	## Where an appeal sits along the scale.
	func place(value: float) -> float:
		var turns: Array[float] = []
		for i in range(words.size() - 1): turns.append(float(words[i].below))
		if turns.is_empty(): return size.x * 0.5
		var span: float = turns[1] - turns[0] if turns.size() > 1 else 8.0
		var segment := size.x / words.size()
		for i in range(words.size()):
			var low: float = turns[i - 1] if i > 0 else turns[0] - span
			var high: float = turns[i] if i < turns.size() else turns[turns.size() - 1] + span
			if value < high or i == words.size() - 1:
				return (i + clampf((value - low) / maxf(0.001, high - low), 0.0, 1.0)) * segment
		return size.x
