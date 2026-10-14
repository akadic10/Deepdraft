shader_type sky;
render_mode disable_fog;

#include "res://scripts/shaders/sky_atmosphere.gdshaderinc"

uniform vec4 sky_top : source_color = vec4(0.025, 0.04, 0.10, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.10, 0.16, 0.27, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.04, 0.065, 0.14, 1.0);
uniform vec2 gradient_curves = vec2(1.8, 1.2);
uniform float night_amount = 1.0;
uniform float star_brightness = 0.65;
uniform float star_scale = 85.0;
uniform float cloud_cover = 0.0;
uniform float cloud_rotation = 0.0;
uniform vec4 cloud_color : source_color = vec4(0.18, 0.23, 0.34, 1.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_visibility = 0.0;
uniform float moon_visibility = 1.0;
uniform float sun_radius = 0.022;
uniform float moon_radius = 0.035;

vec3 hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(cell).x, hash3(cell + vec3(1,0,0)).x, f.x),
                   mix(hash3(cell + vec3(0,1,0)).x, hash3(cell + vec3(1,1,0)).x, f.x), f.y),
               mix(mix(hash3(cell + vec3(0,0,1)).x, hash3(cell + vec3(1,0,1)).x, f.x),
                   mix(hash3(cell + vec3(0,1,1)).x, hash3(cell + vec3(1,1,1)).x, f.x), f.y), f.z);
}

// Three smoothly blended direction-space projections: no longitude seam,
// pole singularity, moving texture or camera-position dependency.
float stars_on_plane(vec2 p, float seed) {
    vec2 uv = p * star_scale;
    vec3 random = hash3(vec3(floor(uv), seed));
    vec2 delta = fract(uv) - (0.2 + random.xy * 0.6);
    float radius = mix(0.035, 0.09, random.y);
    float aa = max(length(fwidth(uv)) * 0.5, 0.012);
    float point = 1.0 - smoothstep(max(radius - aa, 0.0), radius + aa, length(delta));
    // Compensate subpixel stars instead of allowing them to pop when orbiting.
    point *= min(1.0, radius * radius / (aa * aa));
    return point * step(0.982, random.z) * mix(0.3, 1.0, random.x);
}

void sky() {
    vec3 direction = normalize(EYEDIR);
    vec3 atmosphere = diorama_atmosphere(direction, sky_top.rgb, sky_horizon.rgb, sky_bottom.rgb, gradient_curves);
    COLOR = atmosphere;
    // Only the broad atmosphere illuminates the world. Tiny stars and the
    // decorative discs must not sparkle in reflections or brighten interiors.
    if (!AT_CUBEMAP_PASS) {
        vec3 weights = pow(abs(direction), vec3(8.0));
        weights /= max(dot(weights, vec3(1.0)), 0.001);
        float stars = stars_on_plane(direction.yz, 11.0) * weights.x
                    + stars_on_plane(direction.xz, 29.0) * weights.y
                    + stars_on_plane(direction.xy, 47.0) * weights.z;
        COLOR += vec3(0.70, 0.83, 1.0) * stars * star_brightness * night_amount;

        float sun_distance = length(direction - sun_direction);
        float moon_distance = length(direction - moon_direction);
        float aa = max(length(fwidth(direction)), 0.0002);
        float sun_disc = 1.0 - smoothstep(sun_radius - aa, sun_radius + aa, sun_distance);
        COLOR += vec3(1.0, 0.74, 0.40) * sun_visibility *
                 (sun_disc * 1.4 + 0.09 * exp(-sun_distance * 12.0));

        // An ivory crescent with a faint blue earthlit body and a soft halo.
        vec3 east = normalize(cross(moon_direction, vec3(0.001, 1.0, 0.001)));
        vec3 north = normalize(cross(east, moon_direction));
        vec2 moon_uv = vec2(dot(direction, east), dot(direction, north)) / moon_radius;
        float disc = 1.0 - smoothstep(moon_radius - aa, moon_radius + aa, moon_distance);
        float crescent = smoothstep(0.90 - aa / moon_radius, 0.90 + aa / moon_radius,
                                   length(moon_uv - vec2(0.43, 0.12)));
        vec3 moon_surface = mix(atmosphere * 0.7, vec3(0.95, 0.90, 0.72), crescent);
        COLOR = mix(COLOR, moon_surface, disc * moon_visibility);
        COLOR += vec3(0.14, 0.23, 0.43) * 0.06 * exp(-moon_distance * 14.0) * moon_visibility;

        if (cloud_cover > 0.001) {
            float c = cos(cloud_rotation);
            float s = sin(cloud_rotation);
            vec3 p = vec3(c * direction.x - s * direction.z, direction.y, s * direction.x + c * direction.z);
            p *= vec3(4.0, 7.0, 4.0);
            float clouds = noise3(p) * 0.63 + noise3(p * 2.03 + 17.0) * 0.25 + noise3(p * 4.07) * 0.12;
            float threshold = mix(0.95, 0.20, cloud_cover);
            float opacity = smoothstep(threshold, threshold + 0.16, clouds);
            vec3 cloud_shade = cloud_color.rgb * mix(0.72, 1.12, floor(clouds * 6.0) / 6.0);
            COLOR = mix(COLOR, cloud_shade, opacity * 0.96);
        }
    }
}
