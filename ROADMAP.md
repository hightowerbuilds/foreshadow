# GPUI Shader Scenes — Roadmap

A public, open-source scene library for GPUI applications (and, by extension,
any wgpu-based Rust app). The thesis is to fill a gap that genuinely does
not exist in the ecosystem today: a curated, plug-and-play collection of
visually polished animated scenes that someone building on GPUI can drop
into their app without writing a fragment shader from scratch.

This document is the kickoff brief for a fresh session in this repo. It
captures (1) the research that motivated the project, (2) the two design
decisions that have already been raised and recommended on, and (3) the
open decisions that still need an explicit yes from the owner before any
code lands.

---

## Why this exists

Research summary (conducted 2026-05-14, audience-of-one for this project):

- **GPUI 0.2.x on crates.io has no public custom-shader extension point.**
  The official tracking issue is `zed-industries/zed#43273` (filed November
  2025 by Mikayla Maki). Zero comments, no PR, no implementation. Do not
  plan around this landing.
- **The `awesome-gpui` index lists zero shader / effects libraries** — only
  UI component kits and apps. Nobody is shipping what we're proposing to
  ship.
- **`ahkohd/ggpui`** (a 9-star fork) is the only thing in existence that
  exposes a user-shader API to GPUI consumers: `CustomPipeline`,
  `CustomBuffer`, `CustomTexture`, `CustomSampler`, plus ~24 demo files
  under `crates/gpui/examples/custom_draw_api_*.rs`. WGSL has to use
  `a0..` / `b0..` binding names instead of `@location` / `@group`. This is
  an API harness, not a scene library. Useful as a reference for how to
  glue custom WGSL into GPUI; not a credible long-term dependency.
- **`gpui-ce/gpui-ce`** (613 stars) is a community fork. Its
  differentiator is wgpu replatforming, not user shaders.
- **Zed's mainline `crates/gpui/examples/`** has CPU-built primitives
  (`gradient.rs`, `pattern.rs`, `painting.rs`, `shadow.rs`) — useful, but
  not fragment-shader work.
- **Adjacent corpora that could be ported** if scenes ever run dry:
  - `rust-gpu` Shadertoy port (Apr 2025) — Shadertoy scenes in Rust →
    SPIR-V. Most readily portable source material.
  - Bevy's `bevy_pbr` shader libraries — large, Bevy-coupled, extractable.
  - `linebender/vello` — the strongest "render arbitrary 2D" Rust stack.

Conclusion: a Shadertoy-style scene library for GPUI does not exist. This
is a real gap, the addressable audience is every shipping GPUI app, and
the barrier to entry is one disciplined OSS push.

---

## Two design decisions, with recommendations

These were raised and recommended on in the kickoff conversation but the
project owner has not formally signed off. Confirm or redirect at the
start of the next session.

### Decision 1 — Backend strategy

| Option | What it is | Reach | Tradeoff |
|---|---|---|---|
| **(a) Backend-agnostic wgpu crate + thin GPUI adapter** | Scenes are pure wgpu pipelines producing a `wgpu::Texture`. A separate `gpui-adapter` crate wraps the output as a GPUI image element. | Bevy + egui + raw winit + GPUI all consume it. | You're writing a wgpu shader library that happens to include GPUI glue; the marketing is "shader scenes for Rust" with GPUI as one adapter. |
| **(b) GPUI-native via the offscreen-texture trick** | Each scene is an `IntoElement` that paints into GPUI's image primitive via a backing wgpu surface. | Every GPUI user on crates.io today. | Awkward architecture (still doing wgpu, but laundering through the image path) and pure GPUI-only reach. |
| (c) Build on `ahkohd/ggpui`'s `CustomPipeline` API | Most native feel inside GPUI. | Every adopter has to switch their GPUI dependency to a 9-star fork. | Not recommended. |

**Recommended: (a) — backend-agnostic wgpu, with `gpui-shader-scenes` as the
adapter.** Positions the library as `wgpu-scenes` first, `gpui-scenes`
second. If GPUI's #43273 ever lands, write a second adapter and the scene
code doesn't move.

### Decision 2 — Scope of "scene" for v0.1

| Option | Examples | Why it wins |
|---|---|---|
| **Animated backgrounds** | gradients, plasma, noise fields, starfields, flow fields, smoke, fluid | Universal appeal, screenshots-write-themselves, tight scope. |
| Post-processing effects | CRT, bloom, chromatic aberration, film grain, vignette, scanlines | Narrow + useful; llnzy's `src/gpui_terminal/effects.rs` already has shipped versions to seed from. |
| Generative / procedural | ray-marched primitives, Voronoi, Mandelbrot, reaction-diffusion | Highest "wow" per scene, highest cost per scene. |

**Recommended: animated backgrounds for v0.1.** Best ratio of "screenshot
demo wins" to "implementation cost." Post-processing is the natural v0.2.

---

## Decisions

1. **Decision 1 (backend strategy):** confirmed — backend-agnostic wgpu
   core with a thin GPUI adapter.
2. **Decision 2 (v0.1 scope):** confirmed — animated backgrounds.
3. **Crate / repo name:** `foreshadow` (wgpu core). A `foreshadow-gpui`
   adapter crate is added later (see "Suggested first session" step 5).
4. **GitHub home:** `hightowerbuilds/foreshadow`.
5. **License:** MIT.
6. **API shape:** builder + render fn.
   `Plasma::default().render_to_texture(device, queue, target)` — most
   explicit, easiest to keep backend-agnostic, composes cleanly with
   both wgpu-direct consumers and the GPUI adapter.
7. **Launch catalog (v0.1):**
   - Water
   - Forest canopy
   - Space orbit
   - Fractals
   - Contouring lines animation

8. **API stability stance:** standard Rust convention — `0.x` = no
   guarantees, breaking changes accepted pre-1.0.
9. **Distribution:** GitHub-only for now. Revisit crates.io closer to a
   `0.1.0` tag once the API has stabilized through real use in `llnzy`.

---

## Suggested first session in this repo

1. Lock in the open decisions above.
2. `cargo init --lib` with the chosen crate name; add `wgpu`, `bytemuck`,
   `pollster` (or `futures-lite`) for blocking device init.
3. Stand up the `Scene` trait (or chosen API surface) plus one reference
   scene end-to-end — animated gradient is the lowest-friction choice.
4. Write a `cargo run --example gradient` that opens a wgpu/winit window
   and renders the gradient scene fullscreen. This is the "minimum
   shippable thing" — if this works, every subsequent scene is the same
   shape.
5. Once one scene works end-to-end, add the `gpui-` adapter crate (a
   second workspace member) and wire the same gradient scene into a
   minimal GPUI window. This proves the adapter pattern before the
   library has any size.
6. Then mass-produce scenes 2 through N against the now-stable API.

Do not write any second scene until step 4 + 5 are demonstrably working.

---

## Relationship to llnzy

llnzy is the first real consumer of this library. The decision to keep
the projects in separate repos is deliberate: keeping the scene library
GPUI-agnostic (Decision 1 option a) means it has to live somewhere that
isn't an editor. llnzy's existing post-processing effects in
`src/gpui_terminal/effects.rs` are a useful reference and a viable seed
for v0.2 scenes, but they should be re-implemented in the new repo, not
extracted — they're entangled with the terminal's CRT / background-image
machinery and the rewrite is faster than the surgery.

The two repos stay independent; llnzy depends on the library once it has
a tagged release. No code lives in both places.
