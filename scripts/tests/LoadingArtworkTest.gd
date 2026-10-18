extends SceneTree

var failures: Array[String] = []
const OUT := "res://tmp/loading_variants_20261017/"

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	var art = load("res://scripts/ui/LoadingArtwork.gd").new()
	art.definition = root.get_node("UIRegistry").get_loading_screen()
	canvas.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.progress = .62
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for path in art.definition.backgrounds:
		art.artwork = load(String(path)) as Texture2D
		_expect(art.artwork!=null,"configured background loads: "+String(path))
		if art.artwork==null: continue
		var previous := Rect2()
		for width in [1280,1680,2560]:
			root.size = Vector2i(width,720)
			art.queue_redraw()
			for frame in range(4): await process_frame
			var crop: Rect2 = art.source_rect(Vector2(width,720))
			_expect(is_equal_approx(crop.size.x/crop.size.y,float(width)/720.0),"art is never stretched")
			_expect(is_equal_approx(crop.get_center().x,art.artwork.get_width()*.5),"art stays centered")
			if previous.size!=Vector2.ZERO:
				_expect(is_equal_approx(previous.position.y,crop.position.y) and is_equal_approx(previous.size.y,crop.size.y),"wide screens preserve exactly the same vertical composition")
				_expect(crop.encloses(previous),"wide screens reveal extra scenery on both sides")
			previous = crop
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+String(path).get_file().get_basename()+"_%dx720.png"%width)
	for fraction in [0.0,1.0]:
		art.progress = fraction
		art.complete = fraction==1.0
		art.queue_redraw()
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"beer_%d.png"%int(fraction*100))
	for failure in failures: push_error(failure)
	print("LOADING_ARTWORK_OK" if failures.is_empty() else "LOADING_ARTWORK_FAIL")
	quit(0 if failures.is_empty() else 1)
