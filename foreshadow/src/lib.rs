pub mod scenes;

pub use scenes::water::Water;

pub struct RenderTarget<'a> {
    pub view: &'a wgpu::TextureView,
    pub format: wgpu::TextureFormat,
    pub size: (u32, u32),
}
