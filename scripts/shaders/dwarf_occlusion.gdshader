shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// Depth reconstruction follows Godot's reverse-Z spatial shader contract:
// https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 silhouette_color : source_color = vec4(0.71, 0.67, 0.56, 0.18);
uniform float max_cover_depth = 2.5;
uniform vec3 cover_lower[40];
uniform vec3 cover_upper[40];
uniform int cover_count = 0;

void fragment() {
	if (cover_count == 0) { discard; }
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_distance = -surface.z / surface.w;
	float cover = -VERTEX.z - scene_distance;
	// Visible fragments stay untouched; deep rock does not reveal distant dwarves.
	if (cover < 0.06 || cover > max_cover_depth) { discard; }
	vec3 world_surface = (INV_VIEW_MATRIX * vec4(surface.xyz / surface.w, 1.0)).xyz;
	bool terrain_cover = false;
	for (int i = 0; i < cover_count; i++) {
		if (all(greaterThanEqual(world_surface, cover_lower[i] - vec3(0.025))) &&
			all(lessThanEqual(world_surface, cover_upper[i] + vec3(0.025)))) {
			terrain_cover = true;
			break;
		}
	}
	if (!terrain_cover) { discard; }
	float fade = 1.0 - smoothstep(max_cover_depth * 0.65, max_cover_depth, cover);
	ALBEDO = silhouette_color.rgb;
	ALPHA = silhouette_color.a * fade;
}
