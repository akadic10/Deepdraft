extends "res://scripts/tests/WorkerCraftingTest.gd"

## Type (doc 23, "Type"): every role's face is a font shipped
## with the game, with the symbol font behind it; no Windows font is left; the type scale
## and every window's size table; the Sky Dial's clock keeps one width as its minutes change;
## and every character in the UI's words is in a shipped face.
## godot --headless --path . --script res://scripts/tests/TypeTest.gd
const SCALE := {"display": [42, 34, 28], "name": [34, 28, 24], "title": [28, 23, 20], "heading": [23, 19, 16],
	"lead": [19, 16, 14], "body": [17, 14, 12], "small": [14, 12, 10]}
const WINDOWS := ["ColonyInventoryPanel", "DwarfInspectorPanel", "DwarfRosterPanel", "EventsPanel", "FoundingCard",
	"FurniturePlacePanel", "GameMenu", "ItemStamperPanel", "RoomInspectorPanel", "SettingsPanel", "SettlementPanel",
	"StorageInspectorPanel", "TitleScreen", "ToastStack", "ToolBar", "WorkerCraftingPanel"]
var _quoted := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Type test timed out"); quit(1))
	await _setup_crafting_fixture()
	_check_faces()
	_check_scale()
	await _check_clock()
	_check_characters()
	for failure in failures: push_error(failure)
	print("TYPE_OK: shipped faces, no Windows fonts, the scale and the windows' tables, a steady clock, every character drawn" if failures.is_empty() else "TYPE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_faces() -> void:
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	for role: String in UITheme.FACES:
		var face := UITheme.font(role) as FontVariation
		var spec: Array = UITheme.FACES[role]
		_expect(face != null and face.base_font.resource_path == spec[0] and String(spec[0]).begins_with("res://assets/ui/fonts/")
			and int(face.variation_opentype[wght]) == int(spec[1]), "%s: the shipped font at weight %d" % [role, spec[1]])
		_expect(face.fallbacks.size() == 1 and face.fallbacks[0].resource_path == UITheme.SYMBOL_FONT, "%s: the symbol font behind it" % role)
	_expect(UITheme.display_font() == UITheme.font("names") and UITheme.body_font() == UITheme.font("rows")
		and UITheme.hearth_title_font() == UITheme.font("hud"), "names, rows and the HUD's titles use their roles")
	# The symbol font never makes a line taller (tools/fit_font_metrics.py).
	for role: String in ["text", "names"]:
		var plain := FontVariation.new()
		plain.base_font = (UITheme.font(role) as FontVariation).base_font
		_expect(is_equal_approx(UITheme.font(role).get_height(100), plain.get_height(100)), "%s: lines keep their own height" % role)
	var themes: Array = [UITheme.shared_theme()]
	themes.append_array(UITheme._family_themes.values())
	_expect(themes.all(func(theme: Theme) -> bool: return theme.default_font == UITheme.font("text")), "every theme's text is the shipped face")
	_expect(ThemeDB.fallback_font == UITheme.font("text"), "what draws without a theme falls back to the shipped face")
	var windows_fonts: Array = []
	for node: Node in root.find_children("*", "Control", true, false):
		for key: String in ["font", "normal_font", "bold_font"]:
			if (node as Control).has_theme_font_override(key) and (node as Control).get_theme_font(key) is SystemFont:
				windows_fonts.append(node.name)
	_expect(windows_fonts.is_empty(), "no control names a Windows font: %s" % [windows_fonts])


func _check_scale() -> void:
	var tiers := [UITheme.TYPE_LARGE, UITheme.TYPE_MEDIUM, UITheme.TYPE_SMALL]
	for step: String in SCALE:
		_expect(tiers.all(func(tier: Dictionary) -> bool: return tier.size() == SCALE.size())
			and int(tiers[0][step]) == SCALE[step][0] and int(tiers[1][step]) == SCALE[step][1] and int(tiers[2][step]) == SCALE[step][2],
			"%s is %s by tier" % [step, SCALE[step]])
	for tier: Dictionary in tiers:
		var sizes: Array = SCALE.keys().map(func(step: String) -> int: return int(tier[step]))
		var falling := true
		for i in range(1, sizes.size()): falling = falling and sizes[i] < sizes[i - 1]
		_expect(falling, "the steps fall from display to small: %s" % [sizes])
	var wanted := {"large": [UITheme.TYPE_LARGE], "medium": [UITheme.TYPE_MEDIUM], "small": [UITheme.TYPE_SMALL],
		"short": [UITheme.TYPE_MEDIUM, UITheme.TYPE_SMALL]}
	for window: String in WINDOWS:
		var tables: Dictionary = load("res://scripts/ui/%s.gd" % window).get_script_constant_map().SIZES
		for tier: String in tables:
			_expect(tables[tier].has("type") and tables[tier].type in wanted[tier], "%s: its %s sizes carry the %s scale" % [window, tier, tier])


func _check_clock() -> void:
	var dial = dock._sky_dial
	var label: Label = dial._time_label
	_expect(label.get_theme_font("font") == UITheme.font("figures"), "the clock uses figures of one width")
	var widths: Array = []
	for hour: float in [8.55, 11.19, 18.8, 20.0]:
		clock_node.restore_state({"year": 1, "season": "summer", "day": 1, "hour": hour, "speed": 1, "paused": true})
		dial.refresh()
		await process_frame
		widths.append(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x)
	_expect(widths.all(func(width: float) -> bool: return is_equal_approx(width, widths[0])), "the clock keeps one width: %s" % [widths])


## Every character beyond ASCII in the scripts' strings and the data's words, comments and
## notes left out, is in the text face or the symbol font behind it.
func _check_characters() -> void:
	var face := UITheme.font("text")
	var missing := {}
	for path: String in _files("res://scripts", ".gd") + _files("res://data", ".json"):
		if path.begins_with("res://scripts/tests/"): continue
		var words: Array = []
		var text := FileAccess.get_file_as_string(path)
		if path.ends_with(".json"):
			_words(JSON.parse_string(text), words)
		else:
			for line: String in text.split("\n"):
				if line.strip_edges().begins_with("#"): continue
				for found: RegExMatch in _quoted.search_all(line): words.append(found.get_string(1))
		for word: String in words:
			for i in range(word.length()):
				var code := word.unicode_at(i)
				if code > 127 and not face.has_char(code): missing[String.chr(code)] = path
	_expect(missing.is_empty(), "every character in the UI's words is drawn by a shipped face: %s" % [missing])


func _words(value: Variant, into: Array) -> void:
	if value is String: into.append(value)
	elif value is Array:
		for item: Variant in value: _words(item, into)
	elif value is Dictionary:
		for key: Variant in value:
			if not String(key).begins_with("__") and String(key) != "_comment": _words(value[key], into)


func _files(folder: String, suffix: String) -> Array:
	var found: Array = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(suffix): found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(_files(folder.path_join(sub), suffix))
	return found
