shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/shaders/terrain_appearance.gdshaderinc"
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    terrain_appearance(world_position, world_normal, COLOR.a, length(VERTEX), mat3(VIEW_MATRIX), ALBEDO, NORMAL);
}
