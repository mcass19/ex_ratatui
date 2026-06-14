use bytemuck::Zeroable;

use crate::camera::{Camera, Projection};
use crate::color::Rgb;
use crate::light::Light;
use crate::scene::Scene;
use wgpu::util::DeviceExt;

use super::Framebuffer;

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuUniforms {
    position: [f32; 4],
    forward: [f32; 4],
    right: [f32; 4],
    up: [f32; 4],
    params: [f32; 4],      // half_w, half_h, width, height
    counts: [u32; 4],      // num_triangles, num_lights, has_sky, 0
    background: [f32; 4],  // rgb (0-1) / zenith when sky
    sky_horizon: [f32; 4], // rgb (0-1), 0
    sky_ground: [f32; 4],  // rgb (0-1), 0
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuTriangle {
    v0: [f32; 4],
    v1: [f32; 4],
    v2: [f32; 4],
    n0: [f32; 4],
    n1: [f32; 4],
    n2_idx: [f32; 4], // xyz = normal, w = bitcast obj_idx
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuMaterial {
    color_ambient: [f32; 4], // rgb (0-255), ambient
    phong: [f32; 4],         // diffuse, specular, shininess, 0
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct GpuLight {
    type_intensity: [f32; 4], // type, intensity, 0, 0
    dir_pos: [f32; 4],
    color: [f32; 4], // rgb (0-255), 0
}

pub struct GpuRenderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    compute_pipeline: wgpu::ComputePipeline,
    bind_group_layout: wgpu::BindGroupLayout,
}

impl GpuRenderer {
    pub fn new() -> Self {
        pollster::block_on(Self::init())
    }

    async fn init() -> Self {
        let instance = wgpu::Instance::default();
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                ..Default::default()
            })
            .await
            .expect("No GPU adapter found");

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor::default(), None)
            .await
            .expect("Failed to create GPU device");

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("raytrace"),
            source: wgpu::ShaderSource::Wgsl(include_str!("raytrace.wgsl").into()),
        });

        let bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("rt_bgl"),
                entries: &[
                    bgl_entry(0, wgpu::BufferBindingType::Uniform, false),
                    bgl_entry(1, wgpu::BufferBindingType::Storage { read_only: true }, false),
                    bgl_entry(2, wgpu::BufferBindingType::Storage { read_only: true }, false),
                    bgl_entry(3, wgpu::BufferBindingType::Storage { read_only: true }, false),
                    bgl_entry(4, wgpu::BufferBindingType::Storage { read_only: false }, false),
                ],
            });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let compute_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("raytrace_pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });

        Self {
            device,
            queue,
            compute_pipeline,
            bind_group_layout,
        }
    }

    pub fn render(&self, scene: &Scene, camera: &Camera, fb: &mut Framebuffer) {
        if fb.width == 0 || fb.height == 0 {
            return;
        }

        let (gpu_tris, gpu_mats) = prepare_scene(scene);
        let gpu_lights = prepare_lights(scene);
        let gpu_uniforms = prepare_uniforms(
            camera,
            scene,
            fb.width,
            fb.height,
            gpu_tris.len() as u32,
            gpu_lights.len() as u32,
        );

        let pixel_count = (fb.width * fb.height) as usize;

        // Dummy elements for empty buffers (wgpu requires non-zero storage buffers)
        let dummy_tri = GpuTriangle::zeroed();
        let dummy_mat = GpuMaterial::zeroed();
        let dummy_light = GpuLight::zeroed();

        let tri_bytes: &[u8] = if gpu_tris.is_empty() {
            bytemuck::bytes_of(&dummy_tri)
        } else {
            bytemuck::cast_slice(&gpu_tris)
        };
        let mat_bytes: &[u8] = if gpu_mats.is_empty() {
            bytemuck::bytes_of(&dummy_mat)
        } else {
            bytemuck::cast_slice(&gpu_mats)
        };
        let light_bytes: &[u8] = if gpu_lights.is_empty() {
            bytemuck::bytes_of(&dummy_light)
        } else {
            bytemuck::cast_slice(&gpu_lights)
        };

        // Create buffers
        let uniform_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: bytemuck::bytes_of(&gpu_uniforms),
                usage: wgpu::BufferUsages::UNIFORM,
            });

        let tri_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: tri_bytes,
                usage: wgpu::BufferUsages::STORAGE,
            });

        let mat_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: mat_bytes,
                usage: wgpu::BufferUsages::STORAGE,
            });

        let light_buf = self
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: light_bytes,
                usage: wgpu::BufferUsages::STORAGE,
            });

        let output_size = (pixel_count * 4) as u64;
        let output_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: output_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let staging_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: output_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: tri_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: mat_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: light_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: output_buf.as_entire_binding(),
                },
            ],
        });

        // Dispatch
        let mut encoder = self
            .device
            .create_command_encoder(&Default::default());
        {
            let mut pass = encoder.begin_compute_pass(&Default::default());
            pass.set_pipeline(&self.compute_pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups((fb.width + 7) / 8, (fb.height + 7) / 8, 1);
        }
        encoder.copy_buffer_to_buffer(&output_buf, 0, &staging_buf, 0, output_size);
        self.queue.submit(Some(encoder.finish()));

        // Readback
        let buffer_slice = staging_buf.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });
        self.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().unwrap();

        {
            let data = buffer_slice.get_mapped_range();
            let pixels: &[u32] = bytemuck::cast_slice(&data);
            for (i, &packed) in pixels.iter().enumerate() {
                fb.color[i] = Rgb(
                    (packed & 0xFF) as u8,
                    ((packed >> 8) & 0xFF) as u8,
                    ((packed >> 16) & 0xFF) as u8,
                );
                fb.alpha[i] = ((packed >> 24) & 0xFF) as u8;
            }
        }
        staging_buf.unmap();
    }
}

fn bgl_entry(
    binding: u32,
    ty: wgpu::BufferBindingType,
    _read_write: bool,
) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer {
            ty,
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    }
}

fn prepare_uniforms(
    camera: &Camera,
    scene: &Scene,
    width: u32,
    height: u32,
    num_tris: u32,
    num_lights: u32,
) -> GpuUniforms {
    let Projection::Perspective { fov_y, .. } = camera.projection;
    let aspect = width as f32 / height as f32;
    let half_h = (fov_y / 2.0).tan();
    let half_w = half_h * aspect;

    let forward = (camera.target - camera.position).normalize();
    let right = forward.cross(camera.up).normalize();
    let up = right.cross(forward).normalize();

    let (bg, horizon, ground, has_sky) = if let Some(sky) = &scene.sky {
        (
            [sky.zenith.0 as f32 / 255.0, sky.zenith.1 as f32 / 255.0, sky.zenith.2 as f32 / 255.0, 0.0],
            [sky.horizon.0 as f32 / 255.0, sky.horizon.1 as f32 / 255.0, sky.horizon.2 as f32 / 255.0, 0.0],
            [sky.ground.0 as f32 / 255.0, sky.ground.1 as f32 / 255.0, sky.ground.2 as f32 / 255.0, 0.0],
            1u32,
        )
    } else {
        (
            [scene.background.0 as f32 / 255.0, scene.background.1 as f32 / 255.0, scene.background.2 as f32 / 255.0, 0.0],
            [0.0; 4],
            [0.0; 4],
            0u32,
        )
    };

    GpuUniforms {
        position: [camera.position.x, camera.position.y, camera.position.z, 0.0],
        forward: [forward.x, forward.y, forward.z, 0.0],
        right: [right.x, right.y, right.z, 0.0],
        up: [up.x, up.y, up.z, 0.0],
        params: [half_w, half_h, width as f32, height as f32],
        counts: [num_tris, num_lights, has_sky, 0],
        background: bg,
        sky_horizon: horizon,
        sky_ground: ground,
    }
}

fn prepare_scene(scene: &Scene) -> (Vec<GpuTriangle>, Vec<GpuMaterial>) {
    let mut tris = Vec::new();
    let mut mats = Vec::new();

    for (obj_idx, obj) in scene.objects.iter().enumerate() {
        mats.push(GpuMaterial {
            color_ambient: [
                obj.material.color.0 as f32,
                obj.material.color.1 as f32,
                obj.material.color.2 as f32,
                obj.material.ambient,
            ],
            phong: [
                obj.material.diffuse,
                obj.material.specular,
                obj.material.shininess,
                0.0,
            ],
        });

        if !obj.visible {
            continue;
        }

        let model = obj.transform.matrix();
        let normal_mat = model.inverse().transpose();
        let mesh = &obj.mesh;

        for tri in 0..mesh.triangle_count() {
            let i0 = mesh.indices[tri * 3] as usize;
            let i1 = mesh.indices[tri * 3 + 1] as usize;
            let i2 = mesh.indices[tri * 3 + 2] as usize;

            let v0 = model.transform_point3(mesh.vertices[i0].position);
            let v1 = model.transform_point3(mesh.vertices[i1].position);
            let v2 = model.transform_point3(mesh.vertices[i2].position);

            let n0 = normal_mat
                .transform_vector3(mesh.vertices[i0].normal)
                .normalize_or_zero();
            let n1 = normal_mat
                .transform_vector3(mesh.vertices[i1].normal)
                .normalize_or_zero();
            let n2 = normal_mat
                .transform_vector3(mesh.vertices[i2].normal)
                .normalize_or_zero();

            tris.push(GpuTriangle {
                v0: [v0.x, v0.y, v0.z, 0.0],
                v1: [v1.x, v1.y, v1.z, 0.0],
                v2: [v2.x, v2.y, v2.z, 0.0],
                n0: [n0.x, n0.y, n0.z, 0.0],
                n1: [n1.x, n1.y, n1.z, 0.0],
                n2_idx: [n2.x, n2.y, n2.z, f32::from_bits(obj_idx as u32)],
            });
        }
    }

    (tris, mats)
}

fn prepare_lights(scene: &Scene) -> Vec<GpuLight> {
    scene
        .lights
        .iter()
        .map(|light| match light {
            Light::Ambient { color, intensity } => GpuLight {
                type_intensity: [0.0, *intensity, 0.0, 0.0],
                dir_pos: [0.0; 4],
                color: [color.0 as f32, color.1 as f32, color.2 as f32, 0.0],
            },
            Light::Directional {
                direction,
                color,
                intensity,
            } => GpuLight {
                type_intensity: [1.0, *intensity, 0.0, 0.0],
                dir_pos: [direction.x, direction.y, direction.z, 0.0],
                color: [color.0 as f32, color.1 as f32, color.2 as f32, 0.0],
            },
            Light::Point {
                position,
                color,
                intensity,
            } => GpuLight {
                type_intensity: [2.0, *intensity, 0.0, 0.0],
                dir_pos: [position.x, position.y, position.z, 0.0],
                color: [color.0 as f32, color.1 as f32, color.2 as f32, 0.0],
            },
        })
        .collect()
}
