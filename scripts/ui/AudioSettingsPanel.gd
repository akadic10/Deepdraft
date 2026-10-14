extends VBoxContainer

var sliders: Dictionary = {}
var values: Dictionary = {}
var mute_buttons: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(350, 0)
	add_theme_constant_override("separation", 12)
	UITheme.apply_surface(self)
	for channel: String in ["ambience", "effects"]:
		var title := Label.new()
		title.text = channel.capitalize()
		UITheme.apply_title(title)
		add_child(title)
		var description := Label.new()
		description.text = "Weather, woodland, shoreline and cave sounds" if channel == "ambience" else "Work, wildlife, water, fires and notifications"
		description.add_theme_font_size_override("font_size", 13)
		description.add_theme_color_override("font_color", UITheme.HEARTH_MUTED)
		add_child(description)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var slider := HSlider.new()
		slider.name = channel.capitalize() + "Volume"
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(160, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = channel.capitalize() + " volume"
		slider.value_changed.connect(func(value: float): AmbientAudio.set_volume(channel, value / 100.0))
		row.add_child(slider)
		sliders[channel] = slider
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 40
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		values[channel] = value_label
		var mute := UITheme.make_button("Mute", "Mute " + channel, Vector2(62, 32))
		mute.toggle_mode = true
		mute.toggled.connect(func(enabled: bool): AmbientAudio.set_muted(channel, enabled))
		row.add_child(mute)
		mute_buttons[channel] = mute
	var note := Label.new()
	note.text = "Ambience softens while paused.\nYour audio preferences apply to every settlement."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", UITheme.HEARTH_MUTED)
	add_child(note)
	var reset := UITheme.make_button("Restore defaults", "Restore the original audio mix", Vector2(140, 32))
	reset.pressed.connect(func():
		AmbientAudio.set_volume("ambience", float(AmbientAudio.config.default_volume))
		AmbientAudio.set_volume("effects", float(AmbientAudio.config.default_effects_volume))
		AmbientAudio.set_muted("ambience", false)
		AmbientAudio.set_muted("effects", false))
	add_child(reset)
	AmbientAudio.preferences_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for channel: String in sliders:
		sliders[channel].set_value_no_signal(AmbientAudio.volume(channel) * 100)
		values[channel].text = "%d%%" % roundi(AmbientAudio.volume(channel) * 100)
		mute_buttons[channel].set_pressed_no_signal(AmbientAudio.muted(channel))
