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

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let res = vec2<f32>(u.width, u.height);
    let uv  = frag_pos.xy / res;
    let aspect = u.width / u.height;
    // p.y is flipped so the diagonal runs from top-left toward
    // bottom-right in screen coords.
    let p = vec2<f32>(uv.x * aspect, 1.0 - uv.y);
    let t = u.time;

    // `along` runs 0 at the top-left corner to 1 at the bottom-right
    // along the diagonal — this is the direction each line is drawn.
    let along = (p.x + p.y) / (aspect + 1.0);

    // `perp_shifted` is the perpendicular coordinate, shifted so the
    // first line at the top-left corner has index 0 and the line index
    // increases moving toward the bottom-right.
    let perp_shifted = (p.x - p.y) + 1.0;

    // Band frequency = one full white+black period per "line".
    let band_freq = 27.5;
    let line_pos = perp_shifted * band_freq;
    let my_line = floor(line_pos);
    let line_phase = fract(line_pos);
    // First half of the period: black gap. Second half: white stripe.
    let in_white_half = step(0.5, line_phase);

    // Total visible lines and animation timing.
    let total_lines = ceil((aspect + 1.0) * band_freq);
    let t_per_line = 2.0;                                  // seconds per line
    let cycle_duration = total_lines * t_per_line;         // ~2–3 min total
    let t_cycle = t - floor(t / cycle_duration) * cycle_duration;
    let current_line = floor(t_cycle / t_per_line);
    let progress = (t_cycle - current_line * t_per_line) / t_per_line;

    // Alternating direction: even lines draw left-to-right (along
    // increasing), odd lines draw right-to-left (along decreasing).
    let li = i32(my_line);
    let is_even = (li - (li / 2) * 2) == 0;

    // Soft edge for the moving "type head".
    let edge = 0.004;
    var revealed: f32;
    if (is_even) {
        revealed = 1.0 - smoothstep(progress - edge, progress + edge, along);
    } else {
        revealed = smoothstep(1.0 - progress - edge, 1.0 - progress + edge, along);
    }

    // Decide this fragment's value:
    //   - line already drawn → show the white stripe portion.
    //   - line being drawn   → reveal up to the moving head.
    //   - line not yet drawn → black.
    var value: f32;
    if (my_line < current_line) {
        value = in_white_half;
    } else if (my_line > current_line) {
        value = 0.0;
    } else {
        value = in_white_half * revealed;
    }

    return vec4<f32>(vec3<f32>(value), 1.0);
}
