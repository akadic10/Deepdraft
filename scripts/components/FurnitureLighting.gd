extends RefCounted

const LOOK_GROUP := &"hearthblock_furniture_lights"

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
	# A finite fire source softens the bowl's shadow; older definitions keep
	# the engine's point-source default unless they opt in.
	light.light_size = maxf(0.0, float(light_def.get("size", 0.0)))
	light.omni_range = float(light_def.get("range", 5.0))
	light.omni_attenuation = float(light_def.get("attenuation", 1.0))
	light.shadow_enabled = bool(light_def.get("shadows", true))
	var pos: Array = light_def.get("position", [0, 0, 0])
	light.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	# Hearthblock lighting may warm the colour and brighten the flame; keep the
	# definition's values so switching the look off restores them exactly.
	light.set_meta("base_color", light.light_color)
	var warm: Dictionary = SkyController.hearthblock_settings().get("light_colors", {})
	var key := String(def.get("furniture_key", ""))
	if warm.has(key): light.set_meta("hearthblock_color", Color(String(warm[key])))
	light.add_to_group(LOOK_GROUP)
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
		# A flame supplies its own light; its far side should not turn dark
		# when the bracket, logs or terrain occlude the associated point light.
		if bool(light_def.get("unshaded_flame", true)):
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = float(light_def.get("emission_energy", 1.0))
		mesh.material_override = material
		light.set_meta("flame_material", material)
		var animation_def: Dictionary = light_def.get("flame_animation", {})
		if not animation_def.is_empty():
			var animation := preload("FurnitureFlameAnimation.gd").new()
			animation.name = "FlameAnimation"
			node.add_child(animation)
			if not animation.setup(node, mesh, light, material, animation_def):
				animation.queue_free() # retain the static glow if a custom clip is invalid
	preload("VoxelShadowSetup.gd").set_casting(node, bool(light_def.get("body_shadows", false)))
	_apply_light_look(light)


## Re-apply the current look to every installed furniture light.
static func apply_look(tree: SceneTree) -> void:
	for light: Node in tree.get_nodes_in_group(LOOK_GROUP):
		if light is OmniLight3D: _apply_light_look(light)


static func _apply_light_look(light: OmniLight3D) -> void:
	var active: bool = SkyController.hearthblock_active()
	light.light_color = light.get_meta("hearthblock_color") if active and light.has_meta("hearthblock_color") else light.get_meta("base_color")
	var flame: Variant = light.get_meta("flame_material", null)
	if flame is StandardMaterial3D:
		# Unshaded flames output albedo directly; a gain above 1 lifts only the
		# fire past the glow threshold, leaving lit walls and faces unbloomed.
		var gain := float(SkyController.hearthblock_settings().get("flame_gain", 1.0)) if active else 1.0
		flame.albedo_color = Color(gain, gain, gain)
