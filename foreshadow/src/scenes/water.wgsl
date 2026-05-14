struct Ripple {
    x: f32,
    y: f32,
    start_time: f32,
    _pad: f32,
};

struct Uniforms {
    time: f32,
    width: f32,
    height: f32,
    _pad: f32,
    ripples: array<Ripple, 8>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) vid: u32) -> @builtin(position) vec4<f32> {
    let x = f32((vid << 1u) & 2u);
    let y = f32(vid & 2u);
    return vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
}

// Cheap 2D hash for per-region color variation.
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let res = vec2<f32>(u.width, u.height);
    let uv  = frag_pos.xy / res;
    let t = u.time;

    // Four-stop gradient: shallow cyan → teal (green hint) → mid blue → deep navy.
    let shallow  = vec3<f32>(0.55, 0.86, 0.95);
    let teal     = vec3<f32>(0.18, 0.62, 0.72);
    let mid_blue = vec3<f32>(0.08, 0.32, 0.65);
    let deep     = vec3<f32>(0.01, 0.10, 0.32);

    let c1 = mix(shallow, teal,     smoothstep(0.0,  0.33, uv.y));
    let c2 = mix(c1,      mid_blue, smoothstep(0.33, 0.66, uv.y));
    var color = mix(c2,   deep,     smoothstep(0.66, 1.0,  uv.y));

    // Counter-wave overlay: a few broad parallel crests sweeping at an
    // angle opposite the grid drift — reads as the wake of an
    // out-of-frame boat crossing the surface. Sharpened with pow() so
    // most of the surface stays calm and the crests pulse through.
    let wake_dir = vec2<f32>(-0.94, 0.34);
    let wake_phase = dot(uv, wake_dir) * 7.0 - t * 0.55;
    let wake = sin(wake_phase) * 0.5 + 0.5;
    let crest  = pow(wake,        3.0);
    let trough = pow(1.0 - wake, 4.0);
    color = color + vec3<f32>(0.12, 0.18, 0.22) * crest;
    color = color - vec3<f32>(0.00, 0.03, 0.05) * trough;

    // Second wake at a different angle, green-tinted — like a wake
    // from a boat crossing in a different direction.
    let wake2_dir = vec2<f32>(0.50, 0.866);    // ~60°, distinct from wake 1
    let wake2_phase = dot(uv, wake2_dir) * 5.5 + t * 0.42;
    let wake2 = sin(wake2_phase) * 0.5 + 0.5;
    let crest2  = pow(wake2,        3.0);
    let trough2 = pow(1.0 - wake2, 4.0);
    color = color + vec3<f32>(0.05, 0.20, 0.10) * crest2;
    color = color - vec3<f32>(0.02, 0.00, 0.04) * trough2;

    // Grid 1: axis-aligned, ~5× denser than the previous version.
    let g1 = sin(uv.x * 2600.0 + t * 2.0) * sin(uv.y * 2300.0 - t * 1.7);

    // Grid 2: rotated 30°, same density, makes the cross-hatch.
    let angle: f32 = 0.5236;
    let ca = cos(angle);
    let sa = sin(angle);
    let rx = uv.x * ca - uv.y * sa;
    let ry = uv.x * sa + uv.y * ca;
    let g2 = sin(rx * 2500.0 + t * 1.5) * sin(ry * 2400.0 - t * 2.1);

    let g1p = max(g1, 0.0);
    let g2p = max(g2, 0.0);

    // Sparkles = where both grids reinforce. Powered to keep only the
    // brightest crossings.
    let sparkle = pow(g1p * g2p, 1.4);

    // Per-region warm-color lottery so most glints stay neutral but a
    // few cells pick up orange or red.
    let region = floor(uv * vec2<f32>(22.0, 16.0));
    let r = hash21(region);
    var glint_color = vec3<f32>(1.00, 1.00, 1.00);
    if (r > 0.94) {
        glint_color = vec3<f32>(1.00, 0.55, 0.15); // orange
    } else if (r > 0.88) {
        glint_color = vec3<f32>(0.95, 0.25, 0.15); // red
    } else if (r > 0.85) {
        glint_color = vec3<f32>(1.00, 0.90, 0.25); // yellow (tiny bit)
    }

    color = color + glint_color * sparkle * 0.65;

    // Soft cross-hatch texture from the two grids themselves.
    color = color + vec3<f32>(g1p) * 0.07;
    color = color + vec3<f32>(g2p) * 0.06;

    // Click-driven ripples: each slot is an expanding ring centered on
    // (ripple.x, ripple.y) in UV space, born at ripple.start_time. The
    // ring is localized near a leading edge that expands at constant
    // speed and fades out over ~3 seconds.
    let aspect = u.width / u.height;
    let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
    for (var i: u32 = 0u; i < 8u; i = i + 1u) {
        let r = u.ripples[i];
        let age = u.time - r.start_time;
        if (age < 0.0 || age > 3.0) {
            continue;
        }
        let origin = vec2<f32>(r.x * aspect, r.y);
        let dist = length(p_aspect - origin);
        let ring_speed = 0.35;
        let lead = ring_speed * age;
        // Bell curve around the leading edge — only the active ring is bright.
        let band = exp(-pow((dist - lead) * 8.0, 2.0));
        // Overall life decay so the wave fades.
        let life = exp(-age * 0.9);
        // Multiple oscillations within the ring so it looks like a
        // crest + trough train, not a single bright circle.
        let phase = dist * 90.0 - age * 16.0;
        let ring = sin(phase) * 0.5 + 0.5;
        let bright = ring * band * life;
        color = color + vec3<f32>(0.45, 0.60, 0.65) * bright * 0.9;
    }

    return vec4<f32>(color, 1.0);
}
