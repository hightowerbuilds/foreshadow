struct Uniforms {
    time: f32,
    width: f32,
    height: f32,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) vid: u32) -> @builtin(position) vec4<f32> {
    let x = f32((vid << 1u) & 2u);
    let y = f32(vid & 2u);
    return vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
}

// --------- noise helpers ---------

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let x = hash21(p);
    let y = hash21(p + vec2<f32>(1.234, 5.678));
    return vec2<f32>(x, y);
}

fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let s = f * f * (vec2<f32>(3.0) - 2.0 * f);
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

fn fbm(p_in: vec2<f32>) -> f32 {
    var total = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var p = p_in;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        total = total + amp * value_noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return total;
}

// --------- Worley/Voronoi for crown placement ---------

struct Worley {
    f1: f32,           // distance to nearest seed
    f2: f32,           // distance to second nearest seed (cell edge feel)
    cell_id: vec2<f32>,
    seed_pos: vec2<f32>,
};

fn worley(p: vec2<f32>) -> Worley {
    let i = floor(p);
    let f = fract(p);
    var min1 = 9.0;
    var min2 = 9.0;
    var best_cell = vec2<f32>(0.0);
    var best_seed = vec2<f32>(0.0);
    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            let neighbor = vec2<f32>(f32(dx), f32(dy));
            let cell = i + neighbor;
            let jitter = hash22(cell);
            let seed = neighbor + jitter;
            let d = length(seed - f);
            if (d < min1) {
                min2 = min1;
                min1 = d;
                best_cell = cell;
                best_seed = i + seed;
            } else if (d < min2) {
                min2 = d;
            }
        }
    }
    return Worley(min1, min2, best_cell, best_seed);
}

// --------- crown palette ---------
// Mostly greens, occasional warm tones (rust / orange / yellow), like
// the reference image.
fn pick_leaf_color(r: f32) -> vec3<f32> {
    if (r > 0.97) {
        return vec3<f32>(0.78, 0.36, 0.16);    // rust
    } else if (r > 0.94) {
        return vec3<f32>(0.88, 0.55, 0.18);    // orange-brown
    } else if (r > 0.91) {
        return vec3<f32>(0.78, 0.78, 0.26);    // yellow-green
    } else if (r > 0.80) {
        return vec3<f32>(0.50, 0.68, 0.22);    // bright lime
    } else if (r > 0.60) {
        return vec3<f32>(0.30, 0.55, 0.18);    // mid green
    } else if (r > 0.35) {
        return vec3<f32>(0.15, 0.40, 0.14);    // forest green
    } else if (r > 0.12) {
        return vec3<f32>(0.08, 0.28, 0.10);    // dark green
    } else {
        return vec3<f32>(0.04, 0.16, 0.06);    // shadow green
    }
}

// Per-crown directional shade: light from above-left so the upper face
// of each blob is brighter, the lower face darker.
fn crown_shade(local_xy: vec2<f32>) -> f32 {
    let light_dir = normalize(vec2<f32>(-0.4, -1.0)); // points upward & slightly left in fragment coords
    let n = -normalize(local_xy + vec2<f32>(0.0001));
    let d = clamp(dot(n, light_dir), -1.0, 1.0);
    return clamp(d * 0.45 + 0.65, 0.35, 1.10);
}

// Stamp one crown layer onto `dst`. Returns the new color.
fn stamp_crowns(
    dst: vec3<f32>,
    p: vec2<f32>,
    scale: f32,
    cell_offset: vec2<f32>,
    radius: f32,
    softness: f32,
    strength: f32,
) -> vec3<f32> {
    let w = worley(p * scale);
    if (w.f1 > radius) {
        return dst;
    }
    let mask = smoothstep(radius, radius - softness, w.f1) * strength;
    let r = hash21(w.cell_id + cell_offset);
    let leaf = pick_leaf_color(r);
    // Local position within the crown, in cell-space units.
    let local = (p * scale) - w.seed_pos;
    let shade = crown_shade(local / max(radius, 0.0001));
    // Darker rim along the Voronoi edge (where f2 ~= f1) — reads as
    // shadow between adjacent crowns.
    let edge = smoothstep(0.05, 0.0, w.f2 - w.f1);
    let rim_darken = 1.0 - edge * 0.45;
    return mix(dst, leaf * shade * rim_darken, mask);
}

// --------- main ---------

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let res = vec2<f32>(u.width, u.height);
    let uv  = frag_pos.xy / res;
    let aspect = u.width / u.height;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let t = u.time;

    // === LAYER 0: forest-floor base (deep shadow visible between crowns) ===
    var color = vec3<f32>(0.02, 0.08, 0.03);

    // === LAYER 1: STATIC crowns, three scales (back to front).  ===
    // Big background crowns — broad masses behind everything.
    color = stamp_crowns(color, p, 5.5,  vec2<f32>(0.00, 0.00), 0.62, 0.34, 1.00);
    // Medium crowns — the main visual layer.
    color = stamp_crowns(color, p, 11.0, vec2<f32>(7.13, 3.21), 0.55, 0.30, 0.95);
    // Small foreground detail crowns.
    color = stamp_crowns(color, p, 22.0, vec2<f32>(2.84, 9.07), 0.45, 0.22, 0.75);
    // Tiny scattered leaf-cluster highlights.
    color = stamp_crowns(color, p, 48.0, vec2<f32>(5.55, 1.41), 0.30, 0.10, 0.35);

    // === LAYER 2: animated cloud shadows ===
    // Slow, low-frequency FBM darkens patches as if clouds drift over.
    let cloud = fbm(p * 1.4 + vec2<f32>(t * 0.06, t * 0.025));
    let cloud_shadow = smoothstep(0.45, 0.68, cloud);
    color = color * (1.0 - cloud_shadow * 0.32);

    // === LAYER 3: animated sun pokes ===
    // Higher-frequency noise drifts the other direction — bright spots
    // that pass over the canopy like sunlight breaking through gaps.
    let sunny = fbm(p * 3.5 - vec2<f32>(t * 0.04, t * 0.02));
    let sun_mask = smoothstep(0.72, 0.90, sunny);
    color = color + vec3<f32>(0.45, 0.40, 0.18) * sun_mask * 0.55;

    // === LAYER 4: wind shimmer ===
    // Very high-frequency noise drifting fastest — subtle brightness
    // jitter that suggests leaves rustling in the wind.
    let shimmer = value_noise(p * 80.0 + vec2<f32>(t * 0.6, t * 0.4));
    color = color + vec3<f32>((shimmer - 0.5) * 0.05);

    return vec4<f32>(color, 1.0);
}
