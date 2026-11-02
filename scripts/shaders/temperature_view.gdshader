// The Temperature view's floor tint (doc 23 "The Temperature view", doc 24): each floor quad
// carries its base temperature and its shares of the season and of the day and weather in
// INSTANCE_CUSTOM; the two offsets below, set once a game hour and when the weather changes,
// give its temperature now, and the quad takes that word's colour. So the clock moving
// rebuilds nothing. Presentation only; TemperatureViewController owns it.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The season's and the day and weather's offsets from the mean, as open air feels them now.
uniform float season_c = 0.0;
uniform float day_weather_c = 0.0;
// The words' edges (temperature.json): Frozen at or under frozen_at, Cold under cold_below,
// Chilly under comfortable_min, Comfortable to comfortable_max, then Hot.
uniform float frozen_at = 0.0;
uniform float cold_below = 8.0;
uniform float comfortable_min = 16.0;
uniform float comfortable_max = 26.0;
uniform vec4 frozen_colour : source_color = vec4(0.9, 0.96, 1.0, 1.0);
uniform vec4 cold_colour : source_color = vec4(0.29, 0.51, 0.88, 1.0);
uniform vec4 chilly_colour : source_color = vec4(0.27, 0.76, 0.71, 1.0);
uniform vec4 comfortable_colour : source_color = vec4(0.61, 0.81, 0.36, 1.0);
uniform vec4 hot_colour : source_color = vec4(0.91, 0.45, 0.25, 1.0);
uniform float alpha = 0.6;

varying float temperature;

void vertex() {
	temperature = INSTANCE_CUSTOM.r + INSTANCE_CUSTOM.g * season_c + INSTANCE_CUSTOM.b * day_weather_c;
}

void fragment() {
	vec3 colour = hot_colour.rgb;
	if (temperature <= frozen_at) colour = frozen_colour.rgb;
	else if (temperature < cold_below) colour = cold_colour.rgb;
	else if (temperature < comfortable_min) colour = chilly_colour.rgb;
	else if (temperature <= comfortable_max) colour = comfortable_colour.rgb;
	ALBEDO = colour;
	ALPHA = alpha;
}
