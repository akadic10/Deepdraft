extends RefCounted

## Installed visuals only: caller supplies the definition from the furniture owner.
## Keeping the flame a named mesh avoids making the iron and wood glow too.
static func attach(node: Node3D, def: Dictionary) -> void:
	var light_def: Dictionary = def.get("light_source", {})
	if light_def.is_empty():
		return
	var light := OmniLight3D.new()
	light.name = "FurnitureLight"
	light.light_color = Color(String(light_def.get("color", "#FFFFFF")))
	light.light_energy = float(light_def.get("energy", 1.0))
	light.omni_range = float(light_def.get("range", 5.0))
	light.omni_attenuation = float(light_def.get("attenuation", 1.0))
	light.shadow_enabled = bool(light_def.get("shadows", true))
	var pos: Array = light_def.get("position", [0, 0, 0])
	light.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	node.add_child(light)
	var mesh_name := String(light_def.get("emissive_mesh", ""))
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		# Small lamp brackets suppress their own point-light shadow fan. A broad
		# hearth can retain masonry shadows; the fire itself never casts shadows.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (
			String(mesh.name) != mesh_name and bool(light_def.get("body_shadows", false))
		) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mesh.name) != mesh_name:
			continue
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		if bool(light_def.get("unshaded_flame", false)):
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = float(light_def.get("emission_energy", 1.0))
		mesh.material_override = material
		var animation_def: Dictionary = light_def.get("flame_animation", {})
		if not animation_def.is_empty():
			var animation := preload("FurnitureFlameAnimation.gd").new()
			animation.name = "FlameAnimation"
			node.add_child(animation)
			if not animation.setup(node, mesh, light, material, animation_def):
				animation.queue_free() # retain the static glow if a custom clip is invalid
