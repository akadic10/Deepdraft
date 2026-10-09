extends SceneTree

## Offline transparent thumbnails from the actual resource models. The
## registry owns JSON reading; generated PNGs are the only assets written.
const OUT := "res://assets/ui/items/"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("SaveManager").set_process(false)
	root.get_node("WorldClock").set_paused(true)
	root.get_node("RoomManager").set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var registry = load("res://scripts/systems/ItemDropManager.gd").new()
	root.add_child(registry)
	var definitions: Dictionary = registry.get_item_defs()
	var count := 0
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	for key: String in definitions:
		if not only.is_empty() and not key in only.split(","): continue
		var definition: Dictionary = definitions[key]
		if "stockpile_furniture" in definition.get("material_tags", []): continue
		if not ResourceLoader.exists(String(definition.get("model", ""))): continue
		var viewport := SubViewport.new()
		viewport.size = Vector2i(216, 180)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		root.add_child(viewport)
		var scene := Node3D.new()
		viewport.add_child(scene)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d9e4da")
		environment.environment.ambient_light_energy = .65
		scene.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-52, -32, 0)
		light.light_color = Color("ffe4bb")
		light.light_energy = 1.2
		scene.add_child(light)
		var model: Node3D = load(String(definition.model)).instantiate()
		scene.add_child(model)
		var bounds := AABB()
		var first := true
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
			var box: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		model.position = -bounds.get_center()
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		scene.add_child(camera)
		camera.position = Vector3(10, 8, 12)
		camera.look_at(Vector3.ZERO)
		var projected := Vector2.ZERO
		for corner in range(8):
			var local: Vector3 = camera.basis.inverse() * (bounds.get_endpoint(corner) - bounds.get_center())
			projected.x = maxf(projected.x, absf(local.x) * 2)
			projected.y = maxf(projected.y, absf(local.y) * 2)
		camera.size = maxf(projected.y, projected.x / 1.2) * 1.18
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var output := OUT + key.replace(":", "_") + ".png"
		count += 1
		var result := viewport.get_texture().get_image().save_png(output)
		if result != OK: push_error("Could not save " + output); quit(1); return
		viewport.queue_free()
	registry.free()
	print("INVENTORY_THUMBNAILS_OK: ", count, " resource models")
	quit()
