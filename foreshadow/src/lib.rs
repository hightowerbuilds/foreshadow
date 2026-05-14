pub mod scenes;

pub use scenes::contouring_lines::ContouringLines;
pub use scenes::forest_canopy::ForestCanopy;
pub use scenes::space_orbit::SpaceOrbit;
pub use scenes::water::Water;

pub struct RenderTarget<'a> {
    pub view: &'a wgpu::TextureView,
    pub format: wgpu::TextureFormat,
    pub size: (u32, u32),
}
