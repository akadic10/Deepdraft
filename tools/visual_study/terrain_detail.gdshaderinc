// Study-only surface treatment, inserted into a copy of the shipped shader.
// UV2.x is an explicit material tag supplied from real BlockRegistry IDs.
// Tag 3 is authored linear stone geometry, including concealed uniform caps.
// Tags 4/5 are authored earth/turf. Both retain the same safe air-cell sampling.
// ChunkMesher's registry palette enters this shader as unconverted vertex
// colors. Test a linearized palette; authored GLB palettes remain untouched.
if (study_terrain && UV2.x < 2.5 && UV2.y < 0.5) ALBEDO = pow(max(ALBEDO,vec3(0.0)),vec3(2.2));
if (study_terrain && UV2.x < 2.5 && UV2.y < 0.5) {
    vec3 p = world_position;
    vec3 n = abs(world_normal);
    vec2 face = n.y > 0.5 ? p.xz : (n.x > 0.5 ? p.zy : p.xy);
    float footprint = max(length(dFdx(face)), length(dFdy(face)));
    float detail = 1.0 - smoothstep(0.035, 0.12, footprint);
    if (UV2.x > 0.5 && UV2.x < 1.5) {
        ALBEDO *= 0.68;
        vec2 cell = floor(face);
        float stone = fract(sin(dot(cell, vec2(127.1,311.7))) * 43758.5453);
        vec2 local = fract(face);
        vec2 edge = min(local, 1.0-local);
        float rim = min(edge.x, edge.y);
        float seam = 1.0 - smoothstep(0.012,0.044,rim);
        // Fine square chisel facets; lighting still comes from live lights.
        float facet = fract(sin(dot(floor(face*8.0),vec2(41.7,89.1))) * 17131.31);
        float variation = mix(0.9,1.07,stone) * mix(0.96,1.04,facet);
        ALBEDO *= mix(1.0, variation * (1.0-seam*0.16), detail);
        vec2 slope = vec2(step(local.x,0.06)-step(0.94,local.x), step(local.y,0.06)-step(0.94,local.y));
        vec3 bevel = n.y > 0.5 ? vec3(slope.x,0.0,slope.y) : (n.x > 0.5 ? vec3(0.0,slope.y,slope.x) : vec3(slope.x,slope.y,0.0));
        NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bevel,0.0)).xyz * 0.13 * detail);
    } else if (UV2.x > 1.5) {
        ALBEDO = vec3(0.045,0.075,0.027);
        float patch = 0.5 + 0.5*sin(face.x*1.07+sin(face.y*0.7))*sin(face.y*0.91);
        ALBEDO *= mix(0.92,1.03,patch);
    }
}
if (study_terrain && UV2.x > 3.5) {
    vec3 n = abs(world_normal);
    vec2 face = n.y > 0.7 ? world_position.xz : (n.x > 0.7 ? world_position.zy : world_position.xy);
    float footprint = max(length(dFdx(face)),length(dFdy(face)));
    float detail = 1.0-smoothstep(0.035,0.10,footprint);
    float grain = water_hash(floor(face*8.0));
    // Restrained fine clods and grass flecks; the block shape does the work.
    float variation = UV2.x < 4.5 ? mix(0.92,1.07,grain) : mix(0.96,1.04,grain);
    ALBEDO *= mix(1.0,variation,detail);
}
if (water_surface) {
    float shore = pow(abs(UV.x-0.5)*2.0,4.0);
    float ripple = sin(world_position.z*5.0-water_time*1.7+sin(world_position.x*3.5))*0.5+0.5;
    ALBEDO = mix(vec3(0.025,0.095,0.12),vec3(0.085,0.22,0.22),shore*0.7+ripple*0.18);
    float streak = pow(max(0.0,sin(world_position.x*14.0+sin(world_position.z*2.3-water_time))),16.0);
    if (UV2.y > 0.5 && UV2.y < 1.5) {
        float vertical = sin(world_position.y*11.0+water_time*5.0+world_position.x*3.0)*0.5+0.5;
        ALBEDO = mix(vec3(0.045,0.14,0.19),vec3(0.45,0.63,0.62),streak*0.55+vertical*0.12);
    } else {
        float fleck = water_glints(world_position.xz,vec2(0.0,0.4),water_time,0.7);
        float foam = UV2.y>1.5 ? (0.15+fleck*0.75)*(1.0-abs(UV.y-.5)*1.5) : shore*fleck*.7+streak*ripple*.07;
        ALBEDO = mix(ALBEDO,vec3(0.55,0.7,0.64),clamp(foam,0.0,0.8));
    }
}
