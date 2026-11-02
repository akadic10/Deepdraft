shader_type spatial;
// Rain and snow (doc 24, "Rain and snow"). Every drop belongs to a world tile:
// where it falls depends only on that tile, the drop's number and its fall
// cycle, so moving the camera never reshuffles drops. WeatherPrecipitation.gd
// picks the tiles in view and keeps these uniforms.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix, world_vertex_coords;


// Where drops land: the top solid block of each column, plus any water on it.
// r = whole blocks; g = 0 on dry ground, else 1 + the water's fraction * 254.
// The image is z wide and x tall, like WorldGenerator.heightmap.
uniform sampler2D landing : filter_nearest, repeat_disable;
// x, y: the world tile index; z: 0 on the fine level, 1 on the coarse one.
uniform vec3 tiles[192];
uniform int tile_count = 0;
// Tile edge, in blocks, of the fine and the coarse level.
uniform vec2 tile_sizes = vec2(32.0, 64.0);
// Drops shown per tile on each level; the fraction fades the last one in.
uniform vec2 drops_shown = vec2(0.0);
uniform float time = 0.0;
uniform float cycle_time = 1.0;
uniform float cycle_count = 4096.0;
// Nothing shows above the slice: the top of the highest visible block row.
uniform float slice_top = 1000.0;
// 0 = rain, 1 = snow.
uniform int style = 0;
uniform vec4 tint : source_color = vec4(0.62, 0.71, 0.78, 0.3);
uniform float column_height = 14.0;
uniform float fall_speed = 17.0;
// Sideways blocks per block of fall, downwind.
uniform float slant = 0.15;
uniform vec2 wind = vec2(-1.0, 0.0);
// Sizes in pixels of a 1080-line screen, so drops look alike at every zoom.
uniform float width_px = 1.4;
uniform float length_px = 18.0;
uniform float size_px = 6.0;
// Longest rain streak, in blocks.
uniform float max_length = 2.5;
uniform float splash_time = 0.18;
uniform float ripple_time = 0.4;
uniform float sway = 0.35;

varying vec4 v_color;
varying vec2 v_shape;
varying float v_ring;

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float next_random(inout uint seed) {
	seed = pcg(seed);
	return float(seed >> 8u) / 16777216.0;
}

// World size of one 1080-line pixel at this distance from the camera. The
// renderer may flip the projection's y axis, so only its size counts.
float reference_pixel(mat4 projection, float dist) {
	bool orthographic = projection[3][3] > 0.5;
	return (orthographic ? 2.0 : 2.0 * dist) / (abs(projection[1][1]) * 1080.0);
}

void vertex() {
	int count = max(tile_count, 1);
	int slot = INSTANCE_ID % count;
	int drop = INSTANCE_ID / count;
	vec3 tile = tiles[slot];
	bool coarse = tile.z > 0.5;
	float size = coarse ? tile_sizes.y : tile_sizes.x;
	float keep = clamp((coarse ? drops_shown.y : drops_shown.x) - float(drop), 0.0, 1.0);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 world = vec3(0.0);
	v_color = vec4(0.0);
	v_shape = UV * 2.0 - 1.0;
	v_ring = 0.0;
	if (slot < tile_count && keep > 0.0) {
		// The tile size, not the level, seeds a drop: when zoom moves a size from
		// the coarse level to the fine one, its drops stay where they were.
		uint seed = pcg(uint(tile.x) * 73856093u ^ uint(tile.y) * 19349663u ^ uint(size) * 83492791u ^ uint(drop) * 2654435761u);
		float cycle = time / cycle_time + next_random(seed);
		// Each fall lands somewhere new; the change happens while the drop is unseen.
		uint fall_seed = pcg(seed ^ uint(mod(floor(cycle), cycle_count)));
		float into = fract(cycle) * cycle_time;
		vec2 xz = (tile.xy + vec2(next_random(fall_seed), next_random(fall_seed))) * size;
		ivec2 column = ivec2(floor(xz));
		ivec2 extent = textureSize(landing, 0);
		if (column.x >= 0 && column.y >= 0 && column.x < extent.y && column.y < extent.x) {
			vec2 cell = texelFetch(landing, ivec2(column.y, column.x), 0).rg;
			float wet = round(cell.g * 255.0);
			bool water = wet > 0.5;
			float ground = round(cell.r * 255.0) + 1.0 + (water ? (wet - 1.0) / 254.0 : 0.0);
			vec3 land = vec3(xz.x, ground, xz.y);
			vec3 drift = vec3(wind.x, 0.0, wind.y) * slant;
			float fall_time = column_height / fall_speed;
			// Nothing shows above the slice. Under a low cut a drop repeats the
			// blocks it can show, so the rain stays as full as without the cut.
			float window = min(column_height, slice_top - ground);
			float remaining = column_height * (1.0 - into / fall_time);
			float height = window < column_height ? mod(remaining, window) : remaining;
			// A drop's first fall under a low cut starts partway down; fade it in.
			float start_fade = smoothstep(0.0, 0.06, into / fall_time);
			// A roof the slice hides still keeps rain out of the room below it.
			if (ground < slice_top && style == 0) {
				if (into < fall_time) {
					vec3 head = land + vec3(0.0, height, 0.0) - drift * height;
					float dist = max(length(eye - head), 0.1);
					float pixel = reference_pixel(PROJECTION_MATRIX, dist);
					float streak = min(clamp(length_px * pixel, fall_speed / 60.0, max_length), 0.6 * window);
					float tail_height = min(height + streak, window);
					if (window >= 0.75 && height < tail_height) {
						vec3 tail = land + vec3(0.0, tail_height, 0.0) - drift * tail_height;
						vec3 across = cross(normalize(tail - head), normalize(eye - head));
						across = length(across) < 0.001 ? INV_VIEW_MATRIX[0].xyz : normalize(across);
						// Never thinner than a real pixel, or small screens lose the streaks.
						float width = max(width_px * pixel, pixel * 1080.0 / VIEWPORT_SIZE.y);
						world = mix(head, tail, UV.y) + across * v_shape.x * 0.5 * width;
						float top_fade = 1.0 - smoothstep(0.7, 1.0, height / window);
						v_color = vec4(tint.rgb, tint.a * keep * top_fade * start_fade * smoothstep(1.5, 4.0, dist));
					}
				} else {
					// A small splash ring on the ground, a wider, longer ripple on water.
					// Far out they would only flicker, so they fade with distance.
					float age = (into - fall_time) / (water ? ripple_time : splash_time);
					if (age < 1.0) {
						float dist = max(length(eye - land), 0.1);
						float radius = max(mix(0.04, water ? 0.42 : 0.14, sqrt(age)), 2.5 * reference_pixel(PROJECTION_MATRIX, dist));
						world = land + vec3(v_shape.x * radius, 0.03, v_shape.y * radius);
						v_ring = 1.0;
						v_color = vec4(tint.rgb, tint.a * keep * (water ? 1.0 : 0.6) * (1.0 - age) * smoothstep(1.5, 4.0, dist) * (1.0 - smoothstep(70.0, 150.0, dist)));
					}
				}
			} else if (ground < slice_top) {
				// Snow: a small square flake that flutters down, rests, then fades.
				height = into < fall_time ? height : 0.0;
				float rest = max(into - fall_time, 0.0) / splash_time;
				float wobble = 6.2831853 * next_random(fall_seed);
				vec3 flutter = vec3(sin(into * 1.3 + wobble), 0.0, cos(into * 1.1 + wobble * 1.7)) * sway * smoothstep(0.0, 2.0, height);
				vec3 centre = land + vec3(0.0, height + 0.06, 0.0) - drift * height + flutter;
				if (rest < 1.0 && centre.y < slice_top && window >= 0.5) {
					float dist = max(length(eye - centre), 0.1);
					float pixel = reference_pixel(PROJECTION_MATRIX, dist);
					float half_size = 0.5 * max(clamp(size_px * pixel, 0.05, 0.6) * (0.7 + 0.6 * next_random(fall_seed)), 1.5 * pixel * 1080.0 / VIEWPORT_SIZE.y);
					float spin = into * (next_random(fall_seed) * 4.0 - 2.0) + wobble;
					vec2 corner = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * v_shape;
					world = centre + (INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y) * half_size;
					float top_fade = 1.0 - smoothstep(0.8, 1.0, height / window);
					v_color = vec4(tint.rgb, tint.a * keep * top_fade * start_fade * (1.0 - rest) * smoothstep(1.5, 4.0, dist));
				}
			}
		}
	}
	// A hidden drop collapses to a point and draws nothing.
	VERTEX = v_color.a > 0.0 ? world : vec3(0.0);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float alpha = v_color.a;
	if (v_ring > 0.5) {
		float r = length(v_shape);
		alpha *= smoothstep(0.55, 0.8, r) * (1.0 - smoothstep(0.85, 1.0, r));
	} else if (style == 0) {
		// Soft across the streak, brightest at the falling head.
		alpha *= (1.0 - 0.4 * v_shape.x * v_shape.x) * mix(1.0, 0.35, UV.y);
	}
	ALBEDO = v_color.rgb;
	ALPHA = alpha;
}
