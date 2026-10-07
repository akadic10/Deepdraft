extends "res://scripts/tests/DwarfInspectorTest.gd"

func _capture_inspector() -> void:
	await super._capture_inspector()
	worker.traits.assign(["base:trait:light_sleeper", "base:trait:born_miner", "base:trait:cheerful"])
	for resolution in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		explorer._refresh_selected()
		explorer._dwarf_panel._show_tab(1)
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/trait_review/details_%d.png" % resolution.x)
	worker.traits.clear()
	explorer._refresh_selected()
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/trait_review/no_traits.png")
