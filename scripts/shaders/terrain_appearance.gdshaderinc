// Terrain-only detail. COLOR alpha carries a profile selected from an allowed
// visible block, never an undiscovered resource. Tags 9..15 are quiet slice caps;
// alpha=1 is imported art/opt-out.
uniform bool terrain_surface = false;
uniform bool terrain_detail_enabled = true;
uniform vec4 terrain_profiles[8]; // cell, broad patch, seam, bevel width
uniform vec4 terrain_shapes[8]; // normal strength, prototype geometry depth
uniform vec3 terrain_detail_range = vec3(55.0,180.0,8.0);
// Hearthblock dressing (doc 256) on the models' 1:16 grid: one-cell edge shade, fine
// seam shade, two-cell fleck strength, mark chance (+ stepped crack, - worn patch).
uniform vec4 terrain_dressing[8];
// Hearthblock lighting darkens cut slice caps toward warm rock; white keeps them unchanged.
uniform vec3 slice_cap_tint : source_color = vec3(1.0);

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
    if (terrain_surface && cut) albedo *= slice_cap_tint;
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
    vec4 dressing = terrain_dressing[tag];
    if (dressing != vec4(0.0)) {
        // Whole cells only, fading before a cell shrinks under a pixel.
        float cells = detail*(1.0-smoothstep(0.02,0.07,footprint));
        vec2 c = floor(fraction*16.0);
        float ring = step(min(min(c.x,c.y),min(15.0-c.x,15.0-c.y)),0.5);
        albedo *= 1.0-ring*dressing.x*cells;
        float line = 1.0-smoothstep(0.0,0.02+footprint,min(edge_distance.x,edge_distance.y));
        albedo *= 1.0-line*dressing.y*detail;
        for (int i = 0; i < 3; i++) {   // three quiet two-cell flecks
            vec3 key = cell+vec3(float(i)*17.0,61.0,float(i)*7.0);
            vec2 d = c-(floor(vec2(terrain_hash(key),terrain_hash(key+vec3(5.0,3.0,11.0)))*13.0)+1.0);
            if (d.x >= 0.0 && d.x < 2.0 && d.y >= 0.0 && d.y < 2.0)
                albedo *= 1.0+(terrain_hash(key+vec3(9.0,1.0,2.0)) > 0.5 ? dressing.z : -1.4*dressing.z)*cells;
        }
        if (terrain_hash(cell+vec3(29.0,13.0,5.0)) < abs(dressing.w)) {
            if (dressing.w > 0.0) {   // a stepped one-cell crack running in from one edge
                float x = 3.0+floor(terrain_hash(cell+vec3(3.0,9.0,1.0))*9.0);
                float reach = 7.0+floor(terrain_hash(cell+vec3(4.0,2.0,8.0))*9.0);
                for (int row = 0; row < 16; row++) {
                    if (float(row) == c.y) {
                        if (c.x == x && c.y < reach) albedo *= 1.0-0.24*cells;
                        break;
                    }
                    float turn = terrain_hash(cell+vec3(float(row),17.0,23.0));
                    x = clamp(x+(turn > 0.72 ? 1.0 : (turn < 0.28 ? -1.0 : 0.0)),1.0,14.0);
                }
            } else {   // a worn patch: paler and flatter
                vec2 d = c-(floor(vec2(terrain_hash(cell+vec3(7.0,5.0,3.0)),terrain_hash(cell+vec3(2.0,8.0,6.0)))*8.0)+2.0);
                vec2 size = vec2(3.0)+floor(vec2(terrain_hash(cell+vec3(1.0,4.0,9.0)),terrain_hash(cell+vec3(8.0,3.0,2.0)))*4.0);
                if (d.x >= 0.0 && d.y >= 0.0 && d.x < size.x && d.y < size.y)
                    albedo = mix(albedo,vec3(dot(albedo,vec3(0.3333))),0.3*cells)*(1.0+0.06*cells);
            }
        }
    }
    vec2 slope = sign(fraction-vec2(0.5))*bevel*terrain_shapes[tag].x*detail*edge_weight;
    vec3 shaped = normalize(face_normal+u*slope.x+v*slope.y);
    shading_normal = normalize(view_basis*shaped);
}
