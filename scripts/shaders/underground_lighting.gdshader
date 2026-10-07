shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform bool vertex_color = true;
uniform float readability_floor = 0.008;
uniform bool scene_fog_enabled = false;
uniform float fog_density = 0.0;
uniform bool fog_depth_mode = true;
uniform vec3 fog_depth = vec3(0.0,170.0,1.0);
uniform vec2 fog_height = vec2(0.0);
uniform vec4 fog_color : source_color = vec4(0.0);
uniform float fog_aerial = 0.0;
uniform vec4 fog_sky_top : source_color = vec4(0.0);
uniform vec4 fog_sky_horizon : source_color = vec4(0.0);
uniform vec4 fog_ground_bottom : source_color = vec4(0.0);
uniform vec4 fog_ground_horizon : source_color = vec4(0.0);
uniform vec2 fog_sky_curves = vec2(4.0,30.0);
uniform mat3 fog_sky_rotation = mat3(1.0);
uniform int fog_sun_count = 0;
uniform vec3 fog_sun_directions[4];
uniform vec3 fog_sun_colors[4];
uniform sampler2D sky_table : filter_nearest, repeat_disable;
uniform sampler2DArray sky_page_0 : filter_nearest, repeat_disable;
uniform sampler2DArray sky_page_1 : filter_nearest, repeat_disable;
uniform sampler2DArray sky_page_2 : filter_nearest, repeat_disable;
uniform sampler2DArray sky_page_3 : filter_nearest, repeat_disable;
varying vec3 world_position;
varying vec3 world_normal;
varying float sky_access;

vec2 cell_light(ivec3 cell) {
    if (any(lessThan(cell,ivec3(0))) || any(greaterThanEqual(cell,ivec3(1024,128,1024)))) return vec2(1.0,0.0);
    ivec3 tile = cell / 32;
    int index = int(texelFetch(sky_table,ivec2(tile.x,tile.z*4+tile.y),0).r)-1;
    if (index < 0) return vec2(1.0,0.0);
    ivec3 local_cell = cell % 32;
    ivec3 texel = ivec3(local_cell.x,local_cell.y*32+local_cell.z,index%1024);
    int page = index/1024;
    if (page == 0) return texelFetch(sky_page_0,texel,0).rg;
    if (page == 1) return texelFetch(sky_page_1,texel,0).rg;
    if (page == 2) return texelFetch(sky_page_2,texel,0).rg;
    return texelFetch(sky_page_3,texel,0).rg;
}

float exposure(vec3 position) {
    vec2 centre = cell_light(ivec3(floor(position)));
    if (centre.g < 0.5 || centre.r == 0.0) return centre.r;
    // Interpolate air only. Solid rock must not leak its cut-plate daylight
    // into a tunnel, and adjacent floors must remain independent.
    vec3 coord = position-vec3(0.5);
    ivec3 base = ivec3(floor(coord));
    vec3 f = fract(coord);
    float sum = 0.0;
    float weights = 0.0;
    for (int x=0;x<2;x++) for (int y=0;y<2;y++) for (int z=0;z<2;z++) {
        vec2 value = cell_light(base+ivec3(x,y,z));
        vec3 w = mix(vec3(1.0)-f,f,vec3(float(x),float(y),float(z)));
        float weight = w.x*w.y*w.z*value.g;
        sum += value.r*weight;
        weights += weight;
    }
    return weights > 0.0001 ? sum/weights : centre.r;
}

vec4 atmosphere(vec3 view_position, vec3 world_view_direction) {
    if (!scene_fog_enabled || sky_access <= 0.0) return vec4(0.0);
    float distance_to_camera = length(view_position);
    float amount;
    if (fog_depth_mode) {
        float depth = smoothstep(fog_depth.x,max(fog_depth.x+0.001,fog_depth.y),distance_to_camera);
        amount = pow(depth,fog_depth.z)*fog_density;
    } else {
        amount = 1.0-exp(-distance_to_camera*fog_density);
    }
    if (abs(fog_height.y) >= 0.0001) {
        amount = max(amount,1.0-exp(min(0.0,(world_position.y-fog_height.x)*fog_height.y)));
    }
    vec3 direction = fog_sky_rotation * world_view_direction;
    float elevation = clamp(direction.y,-1.0,1.0);
    vec3 sky = mix(fog_sky_top.rgb,fog_sky_horizon.rgb,clamp(pow(1.0-elevation,fog_sky_curves.x),0.0,1.0));
    vec3 ground = mix(fog_ground_bottom.rgb,fog_ground_horizon.rgb,clamp(pow(1.0+elevation,fog_sky_curves.y),0.0,1.0));
    vec3 color = mix(fog_color.rgb,mix(ground,sky,step(0.0,elevation)),fog_aerial);
    for (int i=0;i<fog_sun_count;i++) {
        color += fog_sun_colors[i]*pow(max(dot(world_view_direction,fog_sun_directions[i]),0.0),8.0);
    }
    return vec4(color,clamp(amount,0.0,1.0)*sky_access);
}

void vertex() {
    world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
}

void fragment() {
    sky_access = exposure(world_position+world_normal*0.04);
    ALBEDO = tint.rgb*(vertex_color ? COLOR.rgb : vec3(1.0));
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    AO = sky_access;
    AO_LIGHT_AFFECT = 0.0;
    EMISSION = ALBEDO*readability_floor*(1.0-sky_access)*(0.7+0.3*max(world_normal.y,0.0));
    // Automatic scene fog ignores roofs and doors. Keep its distance/height
    // falloff outside, but never introduce sky-coloured haze into sealed air.
    FOG = atmosphere(VERTEX,normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz));
}

void light() {
    // Godot's rough diffuse (Burley) response; directional lights obey sky
    // access while installed omni lights keep their usual range and shadows.
    float ndl = max(dot(NORMAL,LIGHT),0.0);
    float ndv = max(dot(NORMAL,VIEW),0.0);
    vec3 halfway = normalize(LIGHT+VIEW);
    float ldh = max(dot(LIGHT,halfway),0.0);
    float fd90 = 0.5+2.0*ldh*ldh;
    float fdv = 1.0+(fd90-1.0)*pow(1.0-ndv,5.0);
    float fdl = 1.0+(fd90-1.0)*pow(1.0-ndl,5.0);
    float access = LIGHT_IS_DIRECTIONAL ? sky_access : 1.0;
    DIFFUSE_LIGHT += LIGHT_COLOR*ATTENUATION*ndl*fdv*fdl*access/PI;
}
