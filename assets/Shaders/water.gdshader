shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;

// Pixel-art tile texture (64x16 recommended).
// Nearest keeps the voronoi mask crisp and avoids chaotic mipmap artifacts at the horizon.
uniform sampler2D WATER_TILE_TEX : source_color, repeat_enable, filter_nearest;

// Colors mapped from the BW mask texture.
uniform vec4 OCEAN_COL : source_color = vec4(0.04, 0.38, 0.88, 1.0);
uniform vec4 FOAM_COL : source_color = vec4(0.8125, 0.9609, 0.9648, 1.0);
uniform vec4 DARK_FOAM_COL : source_color = vec4(0.02, 0.16, 0.34, 1.0);
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
uniform vec2 flow_secondary_direction = vec2(0.0, 1.0);
uniform float flow_secondary_speed = 0.11;
uniform float flow_secondary_strength = 0.35;
// Smooth flow controls.
uniform bool pixel_flow = true;
uniform float pixel_art_scale = 4.0;
uniform float flow_mix = 0.1;
uniform float flow_wobble_texels = 0.45;
uniform float flow_wobble_frequency = 1.6;
uniform float flow_wobble_speed = 0.8;
uniform float mask_softness = 0.0;
uniform float dark_foam_width = 0.12;
uniform float dark_foam_strength = 0.8;
uniform vec2 dark_foam_offset = vec2(0.0, -0.08);
uniform vec4 HORIZON_COL_NEAR : source_color = vec4(0.00, 0.50, 0.72, 1.0);
uniform vec4 HORIZON_COL_MID : source_color = vec4(0.00, 0.66, 0.86, 1.0);
uniform vec4 HORIZON_COL_FAR : source_color = vec4(0.42, 0.88, 0.96, 1.0);
uniform float horizon_start = 18.0;
uniform float horizon_range = 20.0;
uniform float band_thickness = 0.16;
uniform float horizon_mid_point = 0.5;
uniform float horizon_cut_scale = 0.7;
uniform float horizon_cut_fill = 0.52;
uniform float horizon_cut_softness = 0.08;
uniform float horizon_cut_strength = 1.0;
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
    float scale = max(pixel_art_scale, 1.0);
    vec2 lowres_size = max(floor(tex_size / scale), vec2(1.0));
    return floor(uv * lowres_size) / lowres_size;
}

float sample_flow_mask(vec2 base_uv, vec2 dir, vec2 dir2, float t, float t2, vec2 wobble_uv) {
    vec2 flow_uv_a = base_uv + dir * t + dir2 * (t2 * flow_secondary_strength) + wobble_uv;
    vec2 flow_uv_b = base_uv - dir2 * (t2 * 0.85) + dir * (t * 0.35) - wobble_uv * 0.7;

    vec2 uv_a = pixel_flow ? pixel_snap_uv(flow_uv_a) : flow_uv_a;
    vec2 uv_b = pixel_flow ? pixel_snap_uv(flow_uv_b) : flow_uv_b;

    float mask_a = texture(WATER_TILE_TEX, uv_a).r;
    float mask_b = texture(WATER_TILE_TEX, uv_b).r;
    float mix_amt = clamp(flow_mix, 0.0, 1.0);
    return max(mask_a, mix(mask_a, mask_b, mix_amt));
}

float sample_dark_flow_mask(vec2 base_uv, vec2 dir, vec2 dir2, float t, float t2, vec2 wobble_uv) {
    vec2 dark_flow_uv_a = base_uv + dir * t + dir2 * (t2 * flow_secondary_strength) + wobble_uv;
    vec2 dark_flow_uv_b = base_uv - dir2 * (t2 * 0.85) + dir * (t * 0.35) - wobble_uv * 0.7;

    vec2 dark_uv_a = pixel_flow ? pixel_snap_uv(dark_flow_uv_a) : dark_flow_uv_a;
    vec2 dark_uv_b = pixel_flow ? pixel_snap_uv(dark_flow_uv_b) : dark_flow_uv_b;

    float dark_mask_a = texture(WATER_TILE_TEX, dark_uv_a).r;
    float dark_mask_b = texture(WATER_TILE_TEX, dark_uv_b).r;
    return max(dark_mask_a, dark_mask_b);
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec3 view_pos = (VIEW_MATRIX * vec4(world_pos_v, 1.0)).xyz;
    float horizon_dist = max(-view_pos.z, 0.0);
    float horizon_mix = clamp((horizon_dist - horizon_start) / max(horizon_range, 0.0001), 0.0, 1.0);

    vec2 base_uv = UV * tile;
    if (use_world_mapping) {
        base_uv = world_pos_v.xz * world_tiling * tile;
    }

    base_uv.x /= max(mask_aspect, 0.0001);
    vec2 tex_size = max(vec2(textureSize(WATER_TILE_TEX, 0)), vec2(1.0));
    float scale = max(pixel_art_scale, 1.0);
    vec2 lowres_size = max(floor(tex_size / scale), vec2(1.0));
    base_uv = floor(base_uv * lowres_size) / lowres_size;

    vec2 wobble_source_uv = base_uv;

    vec2 dir = flow_direction;
    float len_dir = length(dir);
    if (len_dir > 0.0001) {
        dir /= len_dir;
    }

    vec2 dir2 = flow_secondary_direction;
    float len_dir2 = length(dir2);
    if (len_dir2 > 0.0001) {
        dir2 /= len_dir2;
    }

    float t = TIME * flow_speed;
    float t2 = TIME * flow_secondary_speed;
    float wobble_t = TIME * flow_wobble_speed;

    float wobble_x = sin((wobble_source_uv.y * flow_wobble_frequency + wobble_t) * 6.2831853);
    float wobble_y = cos((wobble_source_uv.x * (flow_wobble_frequency * 0.85) + wobble_t * 1.13) * 6.2831853);
    vec2 wobble_uv = vec2(wobble_x, wobble_y) * (flow_wobble_texels / tex_size);

    float mask = sample_flow_mask(base_uv, dir, dir2, t, t2, wobble_uv);
    if (invert_mask) {
        mask = 1.0 - mask;
    }

    float soft = max(mask_softness, 0.0001);
    float edge_soft = smoothstep(foam_threshold - soft, foam_threshold + soft, mask);
    float edge = hard_mask ? step(foam_threshold, mask) : edge_soft;

    float dark_foam_threshold = foam_threshold - dark_foam_width;
    vec2 dark_foam_uv = base_uv + dark_foam_offset;
    float dark_mask = sample_dark_flow_mask(dark_foam_uv, dir, dir2, t, t2, wobble_uv);
    float dark_foam_mask = hard_mask
        ? step(dark_foam_threshold, dark_mask)
        : smoothstep(dark_foam_threshold - soft, dark_foam_threshold + soft, dark_mask);
    dark_foam_mask = clamp(dark_foam_mask - edge, 0.0, 1.0) * dark_foam_strength;

    // Randomize horizon foam in 2D world space to avoid visible vertical line patterns.
    float cut_scale = max(horizon_cut_scale, 0.0001);
    vec2 cut_coord = world_pos_v.xz * cut_scale;
    vec2 warp = vec2(
        hash21(floor(cut_coord * 0.6) + vec2(12.37, 41.91)),
        hash21(floor(cut_coord * 0.6) + vec2(73.11, 8.53))
    );
    cut_coord += (warp - 0.5) * 0.8;

    vec2 cut_cell = floor(cut_coord);
    vec2 cut_local = fract(cut_coord);
    float segment_fill = clamp(horizon_cut_fill, 0.05, 0.95);
    float seg_soft = max(horizon_cut_softness, 0.001);

    float keep = step(1.0 - segment_fill, hash21(cut_cell + vec2(19.7, 7.9)));
    float local_noise = hash21(cut_cell + vec2(3.1, 9.2));
    float radius = mix(0.2, 0.75, local_noise);
    float blob = 1.0 - smoothstep(radius - seg_soft, radius + seg_soft, length(cut_local - vec2(0.5)));

    float horizon_segment_mask = mix(1.0, keep * blob, clamp(horizon_mix * horizon_cut_strength, 0.0, 1.0));
    edge *= horizon_segment_mask;

    // Keep MID color exactly around the center horizon color band.
    float mid_point = clamp(horizon_mid_point, 0.0, 1.0);
    float band_width = max(band_thickness, 0.0001);
    float dist_to_mid = abs(horizon_mix - mid_point);
    float band_b = 1.0 - smoothstep(0.0, band_width, dist_to_mid);
    float side = smoothstep(mid_point - 0.001, mid_point + 0.001, horizon_mix);
    float remaining = 1.0 - band_b;
    float band_a = remaining * (1.0 - side);
    float band_c = remaining * side;

    // Remove dark foam in the MID horizon color band.
    dark_foam_mask *= (1.0 - band_b);

    vec3 horizon_col = HORIZON_COL_NEAR.rgb * band_a;
    horizon_col += HORIZON_COL_MID.rgb * band_b;
    horizon_col += HORIZON_COL_FAR.rgb * band_c;

    vec3 water_col = mix(OCEAN_COL.rgb, horizon_col, horizon_mix);
    water_col = mix(water_col, DARK_FOAM_COL.rgb, dark_foam_mask * (1.0 - horizon_mix));

    ALBEDO = mix(water_col, FOAM_COL.rgb, edge);
}
