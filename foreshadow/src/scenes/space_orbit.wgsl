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

fn fbm(p_in: vec2<f32>, octaves: i32) -> f32 {
    var total = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var p = p_in;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        total = total + amp * value_noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return total;
}

fn warped_fbm(p: vec2<f32>, warp_strength: f32, octaves: i32) -> f32 {
    let qx = fbm(p + vec2<f32>(0.0, 0.0), 4);
    let qy = fbm(p + vec2<f32>(5.2, 1.3), 4);
    let q = vec2<f32>(qx, qy);
    return fbm(p + q * warp_strength, octaves);
}

// --------- foreground star with asymmetric, color-gradient spikes ---------
// Each star fires N spikes at fully random angles (not the evenly-
// spaced 60° pattern). Per-spike length, intensity, and color
// gradient are hash-derived from the star's center, so two stars
// never look the same and no single star looks like a regular shape.

fn bright_star(p: vec2<f32>, center: vec2<f32>, scale: f32, tint: vec3<f32>) -> vec3<f32> {
    let d = p - center;
    let r = length(d);
    if (r > scale * 6.0) {
        return vec3<f32>(0.0);
    }
    let angle = atan2(d.y, d.x);

    // Core stays the same — that's the star itself, should still glow.
    let core = exp(-r * r / (scale * scale * 0.15));
    var result = tint * core;

    var spike_accum = vec3<f32>(0.0);
    let n_spikes: u32 = 5u;
    for (var i: u32 = 0u; i < n_spikes; i = i + 1u) {
        let idf = f32(i);

        // Random angle per spike — no enforced symmetry.
        let angle_hash = hash21(center + vec2<f32>(idf * 7.13, idf * 13.31));
        let target_angle = angle_hash * 6.2831;

        // Per-spike length: some short, some long.
        let len_h = hash21(center + vec2<f32>(idf * 11.7, idf * 19.4));
        let len = 0.45 + len_h * 1.10;

        // Per-spike intensity: some dim, some prominent.
        let bright_h = hash21(center + vec2<f32>(idf * 17.9, idf * 23.6));
        let bright = 0.35 + bright_h * 0.75;

        // Per-spike color gradient: spike fades from the star's tint at
        // the core into one of three outer hues (cool blue, warm orange,
        // green-tinged white) so spikes show different gradients.
        let color_h = hash21(center + vec2<f32>(idf * 29.5, idf * 31.7));
        var outer = tint * 0.50;
        if (color_h > 0.66) {
            outer = mix(tint, vec3<f32>(0.40, 0.65, 1.00), 0.65);
        } else if (color_h < 0.33) {
            outer = mix(tint, vec3<f32>(1.00, 0.55, 0.30), 0.65);
        } else {
            outer = mix(tint, vec3<f32>(0.65, 0.95, 0.70), 0.50);
        }

        // Narrow angular falloff — gives crisp beams, ~10° wide.
        let da = abs(angle - target_angle);
        let dw = min(da, 6.2831 - da);
        let angular = exp(-dw * dw * 180.0);

        // Radial falloff with per-spike length scalar.
        let spike_reach = scale * 1.4 * len;
        let radial = exp(-r / spike_reach);

        // Color along the spike length: tint near the core → outer
        // toward the tip.
        let along_t = smoothstep(0.0, 1.0, r / spike_reach);
        let along_color = mix(tint, outer, along_t);

        spike_accum = spike_accum + along_color * angular * radial * bright;
    }

    // Overall spike scalar — dropped from 0.30 to 0.15 (duller / less bright).
    return result + spike_accum * 0.15;
}

// --------- jittered flickering star field ---------
// Subdivide space into cells; each cell may contain a single star at a
// hash-randomized position within the cell. Sampling the 3×3 cell
// neighborhood around the current fragment means a star near a cell
// boundary still renders. Density and brightness are caller-tunable.
fn flickering_stars(
    p: vec2<f32>,
    t: f32,
    grid: f32,
    density: f32,
    star_radius: f32,
    brightness: f32,
    twinkle_speed: f32,
) -> vec3<f32> {
    let scaled = p * grid;
    let i = floor(scaled);
    let f = fract(scaled);
    var accum = vec3<f32>(0.0);

    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            let neighbor = vec2<f32>(f32(dx), f32(dy));
            let cell = i + neighbor;

            // Does this cell contain a star?
            let presence = hash21(cell + vec2<f32>(13.7, 91.2));
            if (presence < 1.0 - density) {
                continue;
            }

            // Random position within the cell.
            let pos = vec2<f32>(
                hash21(cell + vec2<f32>(7.1, 3.3)),
                hash21(cell + vec2<f32>(11.4, 27.1)),
            );
            let star_local = neighbor + pos;
            let d = length(f - star_local);

            // Tight gaussian core. Larger star_radius → bigger / softer.
            let intensity = exp(-d * d / (star_radius * star_radius));

            // Independent twinkle phase and speed per star.
            let phase = hash21(cell + vec2<f32>(31.7, 43.1)) * 6.2831;
            let speed = twinkle_speed * (0.6 + hash21(cell + vec2<f32>(53.3, 67.8)) * 0.8);
            let twinkle = sin(t * speed + phase) * 0.5 + 0.5;

            // Per-star tint: blue-white / pure / warm-white.
            let ct = hash21(cell + vec2<f32>(73.1, 17.9));
            var tint = vec3<f32>(1.00, 0.99, 0.96);
            if (ct > 0.70) {
                tint = vec3<f32>(0.85, 0.92, 1.00);
            } else if (ct < 0.20) {
                tint = vec3<f32>(1.00, 0.88, 0.78);
            }

            accum = accum + tint * intensity * twinkle * brightness;
        }
    }
    return accum;
}

// --------- main ---------

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let res = vec2<f32>(u.width, u.height);
    let uv  = frag_pos.xy / res;
    let aspect = u.width / u.height;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let t = u.time;

    // Very slow drift on the gas — features cross the screen on the
    // order of a minute. Different rates per layer so they don't move
    // in lockstep.
    let drift_gas     = vec2<f32>(t * 0.010, t * 0.005);
    let drift_pillars = vec2<f32>(t * 0.006, t * 0.0035);
    let drift_voids   = vec2<f32>(t * 0.008, -t * 0.004);

    // === LAYER 0: deep space ===
    var color = vec3<f32>(0.005, 0.008, 0.018);

    // === LAYER 1: cyan/teal nebula gas ===
    let bg_gas = warped_fbm((p + drift_gas) * 1.4, 1.2, 5);
    let bg_mask = smoothstep(0.30, 0.78, bg_gas);
    let cyan = vec3<f32>(0.20, 0.58, 0.82);
    color = mix(color, cyan, bg_mask * 0.78);

    // === LAYER 1b: complement-color sprays drifting through the gas ===
    // These only register where there's gas to recolor, so they read as
    // hue variations in the cloud rather than independent layers.
    let green_field = warped_fbm((p + drift_gas * 0.7) * 1.8 + vec2<f32>(20.0, 30.0), 1.0, 4);
    let green_mask = smoothstep(0.62, 0.84, green_field) * bg_mask;
    color = mix(color, vec3<f32>(0.30, 0.68, 0.38), green_mask * 0.55);

    let red_field = warped_fbm((p + drift_gas * 1.3) * 2.1 + vec2<f32>(50.0, 70.0), 1.2, 4);
    let red_mask = smoothstep(0.66, 0.86, red_field) * bg_mask;
    color = mix(color, vec3<f32>(0.78, 0.30, 0.32), red_mask * 0.50);

    // === LAYER 2: rust/orange pillar structures ===
    let pillars = warped_fbm((p + drift_pillars) * 3.2 + vec2<f32>(1.1, 2.7), 2.0, 6);
    let pillar_mask = smoothstep(0.50, 0.76, pillars);
    let center = vec2<f32>(aspect * 0.42, 0.55);
    let center_falloff = 1.0 - smoothstep(0.20, 0.95, length(p - center));
    let rust = vec3<f32>(0.72, 0.42, 0.20);
    let dark_rust = vec3<f32>(0.32, 0.16, 0.08);
    let pillar_color = mix(dark_rust, rust, pillars);
    color = mix(color, pillar_color, pillar_mask * center_falloff);

    // === LAYER 3: dark voids ===
    let voids = warped_fbm((p + drift_voids) * 2.0 + vec2<f32>(8.1, 4.4), 1.5, 5);
    let void_mask = smoothstep(0.55, 0.85, voids) * (1.0 - pillar_mask * center_falloff * 0.7);
    color = color * (1.0 - void_mask * 0.65);

    let edge = smoothstep(1.0, 0.4, distance(uv, vec2<f32>(0.5)));
    color = color * (0.55 + 0.45 * edge);

    // === LAYER 4: bright foreground stars (toned-down spikes) ===
    color = color + bright_star(p, vec2<f32>(aspect * 0.50, 0.12), 0.022, vec3<f32>(1.00, 0.95, 0.85));
    color = color + bright_star(p, vec2<f32>(aspect * 0.62, 0.50), 0.014, vec3<f32>(0.95, 0.95, 1.00));
    color = color + bright_star(p, vec2<f32>(aspect * 0.45, 0.78), 0.018, vec3<f32>(1.00, 0.97, 0.88));
    color = color + bright_star(p, vec2<f32>(aspect * 0.92, 0.42), 0.012, vec3<f32>(0.92, 0.95, 1.00));
    color = color + bright_star(p, vec2<f32>(aspect * 0.95, 0.88), 0.020, vec3<f32>(1.00, 0.96, 0.85));

    // === LAYER 5: ANIMATED jittered flickering star field ===
    // Dense tier — many tiny scattered stars.
    color = color + flickering_stars(p, t, /*grid=*/120.0, /*density=*/0.18,
                                     /*radius=*/0.06, /*brightness=*/0.85,
                                     /*twinkle_speed=*/3.5);
    // Sparse tier — fewer, brighter, slower twinkles for scale variation.
    color = color + flickering_stars(p, t, /*grid=*/45.0,  /*density=*/0.06,
                                     /*radius=*/0.04, /*brightness=*/0.75,
                                     /*twinkle_speed=*/2.0);

    return vec4<f32>(color, 1.0);
}
