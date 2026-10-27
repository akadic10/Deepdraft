// The Appeal view's dim (doc 23 "The Appeal view"): a full-screen pass, first of the
// see-through ones, that greys and darkens the rendered world so the room tints and the
// glowing pieces drawn after it stand out. Presentation only; AppealViewController owns it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// How much of the world's own colour stays (0 grey, 1 unchanged), and how bright it stays.
uniform float keep_colour = 0.35;
uniform float brightness = 0.6;

void vertex() {
	// The quad covers the screen whatever the camera.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 world = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float grey = dot(world, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(grey), world, keep_colour) * brightness;
}
