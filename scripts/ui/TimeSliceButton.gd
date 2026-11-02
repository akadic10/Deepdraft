extends "res://scripts/ui/DockIconButton.gd"

## Use the shared dock interaction/tooltip behavior. Hearthblock icons (doc 259) use
## the dock's family tile.


func setup(entry: Dictionary, texture: Texture2D) -> void:
	super.setup(entry, texture)
	mouse_force_pass_scroll_events = false


func _draw() -> void:
	if not disabled: super._draw()
