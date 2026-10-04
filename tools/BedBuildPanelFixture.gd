extends "res://scripts/ui/DockUI.gd"

# Loaded after autoload initialization by VerifyBed. Exercise real panel construction
# without reading/writing player UI preferences or registering save/load callbacks.
func _ready() -> void:
	_build_styles()
	_build_root()
	_build_action_panel()
