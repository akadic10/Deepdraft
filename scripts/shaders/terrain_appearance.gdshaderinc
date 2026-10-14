// Terrain-only detail. COLOR alpha carries a profile selected from an allowed
// visible block, never an undiscovered resource. Tags 9..15 are quiet slice caps;
// alpha=1 is imported art/opt-out.
uniform bool terrain_surface = false;
uniform bool terrain_detail_enabled = true;
uniform vec4 terrain_profiles[8]; // cell, broad patch, seam, bevel width
uniform vec4 terrain_shapes[8]; // normal strength, prototype geometry depth
uniform vec3 terrain_detail_range = vec3(55.0,180.0,8.0);

float terrain_hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}

float terrain_patch(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(mix(terrain_hash(cell),terrain_hash(cell+vec3(1,0,0)),f.x),
                   mix(terrain_hash(cell+vec3(0,1,0)),terrain_hash(cell+vec3(1,1,0)),f.x),f.y),
               mix(mix(terrain_hash(cell+vec3(0,0,1)),terrain_hash(cell+vec3(1,0,1)),f.x),
                   mix(terrain_hash(cell+vec3(0,1,1)),terrain_hash(cell+vec3(1,1,1)),f.x),f.y),f.z);
}

void terrain_appearance(vec3 position, vec3 face_normal, float tag_value,
                        float view_distance, mat3 view_basis,
                        inout vec3 albedo, inout vec3 shading_normal) {
    int tag = int(round(tag_value*16.0));
    bool cut = tag > 8 && tag < 16;
    if (cut) tag -= 8;
    if (!terrain_surface || !terrain_detail_enabled || tag <= 0 || tag >= 8) return;
    vec4 profile = terrain_profiles[tag];
    vec3 axis = abs(face_normal);
    vec3 u = axis.x > 0.5 ? vec3(0,0,1) : vec3(1,0,0);
    vec3 v = axis.y > 0.5 ? vec3(0,0,1) : vec3(0,1,0);
    vec2 coord = vec2(dot(position,u),dot(position,v));
    vec2 aa = max(fwidth(coord),vec2(0.001));
    float footprint = max(aa.x,aa.y);
    float detail = (1.0-smoothstep(terrain_detail_range.x,terrain_detail_range.y,view_distance))
                 *(1.0-smoothstep(0.055,0.22,footprint));
    vec3 cell = floor(position-face_normal*0.015);
    if (cut) detail *= 0.12;
    float local = (terrain_hash(cell)-0.5)*2.0;
    float broad = (terrain_patch(position/terrain_detail_range.z)-0.5)*2.0;
    albedo *= 1.0+broad*profile.y+local*profile.x*detail;
    vec2 fraction = fract(coord);
    vec2 edge_distance = min(fraction,vec2(1.0)-fraction);
    // Vary edge width/strength within the material instead of giving every
    // natural block an identical dressed-stone border.
    float character = terrain_hash(cell+vec3(71.0,19.0,43.0));
    float width = profile.w*mix(0.65,1.3,character);
    float edge_weight = mix(0.35,1.0,character);
    vec2 bevel = vec2(1.0)-smoothstep(vec2(0.0),vec2(width)+aa,edge_distance);
    float seam = 1.0-smoothstep(0.0,width*0.32+footprint,min(edge_distance.x,edge_distance.y));
    albedo *= 1.0-seam*profile.z*detail*edge_weight;
    vec2 slope = sign(fraction-vec2(0.5))*bevel*terrain_shapes[tag].x*detail*edge_weight;
    vec3 shaped = normalize(face_normal+u*slope.x+v*slope.y);
    shading_normal = normalize(view_basis*shaped);
}
