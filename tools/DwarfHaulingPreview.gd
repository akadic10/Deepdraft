extends "res://scripts/tests/HaulingAnimationTest.gd"

## Capture the real assigned hauling job, rather than an isolated pose loop.
## Run with a rendering device (no --headless), optionally -- --log or --bundle.
func _run() -> void:
	await _setup_fixture()
	var view := "crate"
	if "--log" in OS.get_cmdline_user_args():
		view = "log"
		await _new_trip(LOG, 1)
	if "--bundle" in OS.get_cmdline_user_args():
		view = "bundle"
		await _new_trip(STONE, 1)
		for i in range(3): drops.restore_loose_item(STONE, Vector3(40.5,21,40.65))
	root.size = Vector2i(900, 750)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.12, .16, .19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = .8
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(7, .2, 9)
	ground.mesh = box
	ground.position = Vector3(40.5, 20.9, 42.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.3, .35, .35)
	ground.material_override = material
	scene.add_child(ground)
	for cell in zone.tile_cells:
		var marker := MeshInstance3D.new()
		var tile := BoxMesh.new()
		tile.size = Vector3(.94,.012,.94)
		marker.mesh = tile
		var tint := StandardMaterial3D.new()
		tint.albedo_color = Color(.39,.48,.35)
		marker.material_override = tint
		marker.position = Vector3(cell.x+.5,21.008,cell.z+.5)
		scene.add_child(marker)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.1
	var center := Vector3(40.5,22.3,42)
	camera.position = center + Vector3(6,5,9)
	camera.look_at(center)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var title := Label.new()
	title.position = Vector2(24,20)
	title.add_theme_font_size_override("font_size", 25)
	title.text = "DWARF HAULING / " + view.to_upper()
	layer.add_child(title)
	var caption := Label.new()
	caption.position = Vector2(24,700)
	caption.add_theme_font_size_override("font_size", 20)
	layer.add_child(caption)
	for i in range(6): await process_frame
	root.get_node("SkyController").set_process(false)
	env.ambient_light_energy = .8
	sun.light_energy = 1.4
	var directory := "res://tmp/hauling_animation_review/" + view
	DirAccess.make_dir_recursive_absolute(directory)
	var labels := {
		worker.TaskPhase.HAUL_PICKUP: "Reach · grip · lift",
		worker.TaskPhase.HAUL_TO_ITEM: "Collect the next item",
		worker.TaskPhase.HAUL_TO_ZONE: "Carry with both fists",
		worker.TaskPhase.HAUL_DEPOSIT: "Lower · release",
		worker.TaskPhase.NONE: "Stored"
	}
	var finished := 0
	for i in range(240):
		zone.update_leases()
		tasks._run_scheduler()
		worker._process(1.0/24.0)
		caption.text = labels.get(worker._task_phase, "Hauling")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/frame_%03d.png" % i)
		if zone.stored_count() > 0:
			finished += 1
			if finished >= 12: break
	print("DWARF_HAULING_PREVIEW_OK: ", view, "; actual scheduler, pickup, walk and storage commit")
	quit()
