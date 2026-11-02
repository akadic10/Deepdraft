extends SceneTree

## Terrain dressing reads on every material (doc 63, "World and effect boundaries"). Coal is
## the darkest block: its faces keep enough colour for light to show, and its profile draws
## a lighter edge and seam, because darkening a near-black face shows nothing.

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	var blocks := root.get_node("BlockRegistry")
	var coal: int = blocks.get_id(&"base:terrain:ore:coal")
	var face: Color = blocks.get_terrain_color(coal, "summer")
	var luminance := 0.2126 * face.r + 0.7152 * face.g + 0.0722 * face.b
	_expect(luminance > 0.025, "coal keeps enough colour for light to show its faces (linear luminance %.4f)" % luminance)
	var profile: Dictionary = blocks.get_appearance_profile(coal)
	var dressing: Dictionary = profile.get("dressing", {})
	_expect(float(dressing.get("edge", 0.0)) < 0.0 and float(dressing.get("seam", 0.0)) < 0.0,
		"coal's edge and seam lighten")
	var tag := int(round(face.a * 16.0))
	_expect(tag == int(profile.get("id", -1)), "coal's vertices carry its own profile")
	var iron: int = blocks.get_id(&"base:terrain:ore:iron")
	_expect(int(blocks.get_appearance_profile(iron).get("id", -1)) != tag, "the other ores keep the mineral profile")
	var material := ShaderMaterial.new()
	blocks.configure_terrain_material(material)
	var uniforms: Array = material.get_shader_parameter("terrain_dressing")
	var lit: Vector4 = uniforms[tag] if tag >= 0 and tag < uniforms.size() else Vector4.ZERO
	_expect(lit.x < 0.0 and lit.y < 0.0, "the terrain shader receives coal's lit edge")
	for failure: String in failures: push_error(failure)
	print("TERRAIN_ART_OK" if failures.is_empty() else "TERRAIN_ART_FAIL")
	quit(0 if failures.is_empty() else 1)
