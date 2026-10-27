extends RefCounted

## A still portrait of a world object for the compact panel (doc 260): copies of its
## visible meshes, framed whole in their own world and rendered once, like the dwarf
## portrait. Only meshes are copied, never scripts, colliders or markers, so a portrait
## can never act on the world. Trees show their current season and animals their pose.
const Shadow = preload("res://scripts/components/VoxelShadowSetup.gd")


static func create_viewport(texture: TextureRect, resolution := Vector2i(176, 176)) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	texture.add_child(viewport)
	UITheme.follow_ui_scale(viewport, resolution)   # sharp at any UI scale
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9e4da")
	settings.ambient_light_energy = .65
	environment.environment = settings
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -32, 0)
	light.light_color = Color("ffe4bb")
	light.light_energy = 1.2
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.name = "PortraitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	return viewport


## Show `subject` in the portrait and return the copied model (free it to clear).
static func create_model(viewport: SubViewport, subject: Node3D) -> Node3D:
	var model := Node3D.new()
	viewport.add_child(model)
	var to_local := subject.global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in Shadow.visual_meshes(subject):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or String(mesh.name).contains("Silhouette"): continue
		var copy := MeshInstance3D.new()
		copy.mesh = mesh.mesh
		# Underground tints swap a mesh's material; the portrait keeps its own light.
		var material := mesh.material_override
		if material != null and material.has_meta("underground_source_material"): material = material.get_meta("underground_source_material")
		copy.material_override = material
		for surface in range(mesh.get_surface_override_material_count()):
			copy.set_surface_override_material(surface, mesh.get_surface_override_material(surface))
		copy.transform = to_local * mesh.global_transform
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(copy)
		var box: AABB = copy.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	model.position = -bounds.get_center()
	var camera := viewport.get_node("PortraitCamera") as Camera3D
	camera.position = Vector3(10, 8, 12)
	camera.look_at(Vector3.ZERO)
	var projected := Vector2.ZERO
	for corner in range(8):
		var offset: Vector3 = camera.basis.inverse() * (bounds.get_endpoint(corner) - bounds.get_center())
		projected.x = maxf(projected.x, absf(offset.x) * 2.0)
		projected.y = maxf(projected.y, absf(offset.y) * 2.0)
	camera.size = maxf(maxf(projected.x, projected.y) * 1.08, 0.5)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return model
