extends "res://scripts/tests/StorageFilterTest.gd"

func _capture_storage(file: String) -> void:
	var panel = storage._storage_panel
	print(file, " ", {"tab":panel._shown_tab, "contents_min":panel._contents.get_combined_minimum_size(), "scroll_min":panel._scroll.custom_minimum_size, "scroll_size":panel._scroll.size, "window_min":panel.window.get_combined_minimum_size(), "window_size":panel.window.size, "panel_min":panel.get_combined_minimum_size()})
	await super._capture_storage(file)
