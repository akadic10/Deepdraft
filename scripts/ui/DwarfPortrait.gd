extends RefCounted

## Shared static portrait of an existing dwarf. No actor scripts, tasks or
## animations are instantiated; each viewport renders only when requested.
static func create_viewport(texture: TextureRect, resolution := Vector2i(192, 224)) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = resolution
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	texture.add_child(viewport)
	texture.texture = viewport.get_texture()
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("eee5d1")
	settings.ambient_light_energy = .7
	environment.environment = settings
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_color = Color("ffe6c2")
	light.light_energy = 1.2
	viewport.add_child(light)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(4.5, 3.5, 9)
	camera.look_at(Vector3(0, 2.2, 0))
	return viewport


static func create_model(viewport: SubViewport, agent: DwarfAgent) -> Node3D:
	var model := Node3D.new()
	viewport.add_child(model)
	for part: Node3D in [agent._body, agent._head]:
		if part == null: continue
		var copy := part.duplicate(0) as Node3D
		copy.transform = Transform3D.IDENTITY
		copy.scale.x = agent.proportions.body_width if part==agent._body else agent.proportions.head_width
		for silhouette: Node in copy.find_children("OccludedSilhouette","MeshInstance3D",true,false): silhouette.free()
		# Portraits use their own studio lighting, even when the selected dwarf
		# stands underground. Keep the original tint without the world light field.
		for mesh: MeshInstance3D in copy.find_children("*","MeshInstance3D",true,false):
			var material := mesh.material_override
			if material != null and material.has_meta("underground_source_material"):
				mesh.material_override = material.get_meta("underground_source_material")
		model.add_child(copy)
	# The world actor deliberately omits scars; add the saved appearance overlay
	# only to the portrait's independent model, using the existing asset owner.
	if agent.appearance != null and agent.appearance.scar != "none":
		var registry := agent.get_node("/root/DwarfAssets")
		var packed: PackedScene = registry.scars.get(agent.appearance.scar)
		if packed != null:
			var scar := packed.instantiate() as Node3D
			scar.name = "MeshScar"
			model.add_child(scar)
			scar.scale.x = agent.proportions.head_width
			for mesh: MeshInstance3D in scar.find_children("*","MeshInstance3D",true,false):
				var material := StandardMaterial3D.new()
				material.vertex_color_use_as_albedo = true
				material.roughness = 1.0
				mesh.material_override = material
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return model
