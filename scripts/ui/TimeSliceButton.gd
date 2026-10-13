extends "res://scripts/ui/DockIconButton.gd"

## Use the shared dock interaction/tooltip behavior, with an eight-sided art
## aperture. The original atlas is retained; outside painted backdrops never
## appear beyond the copper frame. Rectangular steppers keep their proportions.
var artwork: AtlasTexture


func setup(entry: Dictionary, texture: Texture2D) -> void:
	artwork = texture as AtlasTexture
	super.setup(entry, null)
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	mouse_force_pass_scroll_events = false


func _draw() -> void:
	if artwork != null:
		var cut := Vector2(.14, .14 if size.x < size.y * 1.4 else .18)
		var outline := PackedVector2Array([Vector2(cut.x, 0), Vector2(1-cut.x, 0),
			Vector2(1, cut.y), Vector2(1, 1-cut.y), Vector2(1-cut.x, 1),
			Vector2(cut.x, 1), Vector2(0, 1-cut.y), Vector2(0, cut.y)])
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for p in outline:
			points.append(p * size)
			uvs.append((artwork.region.position + p * artwork.region.size) / artwork.atlas.get_size())
		var tint := Color(.4, .4, .4) if disabled else (Color.WHITE if button_pressed or _hovered else Color(.83, .83, .83))
		draw_colored_polygon(points, tint, uvs, artwork.atlas)
	if not disabled: super._draw()
