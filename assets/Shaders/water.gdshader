shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;

// Pixel-art tile texture (64x16 recommended).
// Linear mipmaps + anisotropic filtering improve distant/horizon quality.
uniform sampler2D WATER_TILE_TEX : source_color, repeat_enable, filter_linear_mipmap_anisotropic;

// Colors mapped from the BW mask texture.
uniform vec4 OCEAN_COL : source_color = vec4(0.04, 0.38, 0.88, 1.0);
uniform vec4 FOAM_COL : source_color = vec4(0.8125, 0.9609, 0.9648, 1.0);
uniform float foam_threshold = 0.5;
uniform bool hard_mask = true;
uniform bool invert_mask = false;

// Surface UV tiling on the mesh plane.
uniform vec2 tile = vec2(5.0, 5.0);
uniform bool use_world_mapping = true;
uniform float world_tiling = 0.2;
// For 64x16 masks use 4.0 (64/16) to avoid horizontal squashing.
uniform float mask_aspect = 4.0;
// Tiny static lift to avoid z-fighting with coplanar terrain.
uniform float surface_lift = 0.01;
// Vertical bobbing: moves between 0.0 and bob_height above base level.
uniform float bob_height = 0.1;
uniform float bob_speed = 1.0;
uniform float bob_phase = 0.0;

// Simple planar motion (no vertical displacement).
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed = 0.18;

varying vec3 world_pos_v;

void vertex() {
    // Keep the mesh flat, but lift it slightly to render on top of the ground plane.
    vec3 local_pos = VERTEX;
    float bob01 = 0.5 + 0.5 * sin(TIME * bob_speed + bob_phase);
    local_pos.y += surface_lift + bob01 * bob_height;
    VERTEX = local_pos;
    world_pos_v = (MODEL_MATRIX * vec4(local_pos, 1.0)).xyz;
}

vec2 pixel_snap_uv(vec2 uv) {
    vec2 tex_size = vec2(textureSize(WATER_TILE_TEX, 0));
    tex_size = max(tex_size, vec2(1.0));
    return floor(uv * tex_size) / tex_size;
}

void fragment() {
    vec2 base_uv = UV * tile;
    if (use_world_mapping) {
        base_uv = world_pos_v.xz * world_tiling * tile;
    }

    base_uv.x /= max(mask_aspect, 0.0001);

    vec2 dir = flow_direction;
    float len_dir = length(dir);
    if (len_dir > 0.0001) {
        dir /= len_dir;
    }

    float t = TIME * flow_speed;
    vec2 final_uv = pixel_snap_uv(base_uv + dir * t);
    vec3 mask_tex = texture(WATER_TILE_TEX, final_uv).rgb;
    float mask = mask_tex.r;
    if (invert_mask) {
        mask = 1.0 - mask;
    }

    float edge = hard_mask ? step(foam_threshold, mask) : mask;

    ALBEDO = mix(OCEAN_COL.rgb, FOAM_COL.rgb, edge);
}
