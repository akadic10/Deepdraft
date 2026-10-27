extends PanelContainer

## A world marker over an ordered tree, plant or stone (doc 259): the order's
## Hearthblock icon on a small tile, the same picture as the tool that marked it. The
## owning system projects it above the object; it is never a pick target.
const SIDE := 36.0

## The order shown: fell, harvest, clear_stones, clear_plants or uproot.
var kind := ""
var _icon: TextureRect


func setup(marker_kind: String, picture: Texture2D, tile: Color) -> void:
	kind = marker_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * SIDE
	add_theme_stylebox_override("panel", UITheme.icon_tile_style(tile, "normal"))
	_icon = TextureRect.new()
	_icon.texture = picture
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)


func get_picture() -> Texture2D:
	return _icon.texture
