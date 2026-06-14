use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::widgets::StatefulWidget;
use rustler::{Error, Term};

use ratatui_3d::render_mode::RenderMode;
use ratatui_3d::viewport::{Viewport3D, Viewport3DState};
use render3d::camera::{Camera, Projection};
use render3d::color::Rgb;
use render3d::light::Light;
use render3d::material::Material;
use render3d::math::{Quat, Vec3};
use render3d::mesh::{compute_normals, Mesh, Vertex};
use render3d::object::SceneObject;
use render3d::pipeline::Pipeline;
use render3d::primitives;
use render3d::scene::{Scene, Sky};
use render3d::transform::Transform;

use crate::decode::{
    decode_map, decode_optional, decode_required, invalid_field, missing_field, optional_term,
    TermMap,
};
use crate::widgets::block::{self, BlockData};

/// Decoded, engine-ready representation of a `viewport3d` widget.
pub struct Viewport3DData {
    pub scene: Scene,
    pub camera: Camera,
    pub render_mode: RenderMode,
    pub pipeline: Pipeline,
    pub block: Option<BlockData>,
}

pub fn render(buf: &mut Buffer, data: &Viewport3DData, area: Rect) {
    // Drive the stateful viewport with a transient state so the pipeline choice
    // is honored (Viewport3DStatic hardcodes the default rasterizer). The state
    // is rebuilt every frame, matching ex_ratatui's pure-data model.
    let mut state = Viewport3DState::new(data.camera.clone(), data.render_mode);
    state.pipeline = data.pipeline;

    let mut viewport = Viewport3D::new(&data.scene);
    if let Some(ref block_data) = data.block {
        viewport = viewport.block(block_data.to_block());
    }

    StatefulWidget::render(viewport, area, buf, &mut state);
}

pub fn decode(map: &TermMap<'_>) -> Result<Viewport3DData, Error> {
    let scene = decode_scene(map, "viewport3d")?;
    let camera = decode_camera(map, "viewport3d")?;

    let render_mode = parse_render_mode(
        &decode_optional::<String>(map, "render_mode", "viewport3d")?
            .unwrap_or_else(|| "braille".to_string()),
    )?;
    let pipeline = parse_pipeline(
        &decode_optional::<String>(map, "pipeline", "viewport3d")?
            .unwrap_or_else(|| "rasterize".to_string()),
    )?;

    let block = match optional_term(map, "block") {
        Some(term) => Some(block::decode_block(term)?),
        None => None,
    };

    Ok(Viewport3DData {
        scene,
        camera,
        render_mode,
        pipeline,
        block,
    })
}

pub fn parse_render_mode(value: &str) -> Result<RenderMode, Error> {
    match value {
        "half_block" => Ok(RenderMode::HalfBlock),
        "braille" => Ok(RenderMode::Braille),
        "ascii" => Ok(RenderMode::Ascii),
        other => Err(invalid_field(
            "viewport3d",
            "render_mode",
            &format!("unknown render mode '{other}'"),
        )),
    }
}

pub fn parse_pipeline(value: &str) -> Result<Pipeline, Error> {
    match value {
        "rasterize" => Ok(Pipeline::Rasterize),
        "raytrace" => Ok(Pipeline::Raytrace),
        other => Err(invalid_field(
            "viewport3d",
            "pipeline",
            &format!("unknown pipeline '{other}'"),
        )),
    }
}

fn decode_camera(map: &TermMap<'_>, ctx: &str) -> Result<Camera, Error> {
    let cmap = submap(map, "camera", ctx)?;
    let cctx = "viewport3d.camera";
    Ok(Camera {
        position: vec3_field(&cmap, "position", cctx)?,
        target: vec3_field(&cmap, "target", cctx)?,
        up: vec3_field(&cmap, "up", cctx)?,
        projection: Projection::Perspective {
            fov_y: required_f32(&cmap, "fov", cctx)?,
            near: required_f32(&cmap, "near", cctx)?,
            far: required_f32(&cmap, "far", cctx)?,
        },
    })
}

fn decode_scene(map: &TermMap<'_>, ctx: &str) -> Result<Scene, Error> {
    let smap = submap(map, "scene", ctx)?;
    let sctx = "viewport3d.scene";

    let objects = decode_list(&smap, "objects", sctx, decode_object)?;
    let lights = decode_list(&smap, "lights", sctx, decode_light)?;

    let background = match optional_term(&smap, "background") {
        Some(term) => decode_rgb(term, sctx, "background")?,
        None => Rgb::BLACK,
    };

    let sky = match optional_term(&smap, "sky") {
        Some(term) => decode_sky(term)?,
        None => None,
    };

    Ok(Scene {
        objects,
        lights,
        background,
        sky,
    })
}

fn decode_object(term: Term<'_>) -> Result<SceneObject, Error> {
    let map = decode_map(term, "viewport3d.scene.objects")?;
    let octx = "viewport3d.scene.objects";

    let mesh = decode_mesh(&map, octx)?;

    let material = match optional_term(&map, "material") {
        Some(term) => decode_material(&decode_map(term, octx)?)?,
        None => Material::default(),
    };

    let transform = match optional_term(&map, "transform") {
        Some(term) => decode_transform(&decode_map(term, octx)?)?,
        None => Transform::default(),
    };

    let visible = decode_optional::<bool>(&map, "visible", octx)?.unwrap_or(true);

    Ok(SceneObject {
        mesh,
        material,
        transform,
        visible,
    })
}

fn decode_mesh(map: &TermMap<'_>, ctx: &str) -> Result<Mesh, Error> {
    let mmap = submap(map, "mesh", ctx)?;
    let mctx = "viewport3d.scene.objects.mesh";
    let kind: String = decode_required(&mmap, "kind", mctx)?;

    match kind.as_str() {
        "cube" => Ok(primitives::cube()),
        "plane" => Ok(primitives::plane()),
        "sphere" => {
            let stacks: u32 = decode_required(&mmap, "stacks", mctx)?;
            let slices: u32 = decode_required(&mmap, "slices", mctx)?;
            Ok(primitives::sphere(stacks, slices))
        }
        "custom" => decode_custom_mesh(&mmap, mctx),
        other => Err(invalid_field(
            mctx,
            "kind",
            &format!("unknown mesh kind '{other}'"),
        )),
    }
}

fn decode_custom_mesh(map: &TermMap<'_>, ctx: &str) -> Result<Mesh, Error> {
    let positions = decode_vec3_list(map, "vertices", ctx)?;
    if positions.is_empty() {
        return Err(invalid_field(
            ctx,
            "vertices",
            "expected at least one vertex",
        ));
    }
    let vcount = positions.len();

    let indices_term =
        optional_term(map, "indices").ok_or_else(|| missing_field(ctx, "indices"))?;
    let indices_raw: Vec<i64> = indices_term
        .decode()
        .map_err(|_| invalid_field(ctx, "indices", "expected a list of integers"))?;
    if !indices_raw.len().is_multiple_of(3) {
        return Err(invalid_field(
            ctx,
            "indices",
            "length must be a multiple of 3",
        ));
    }

    let mut indices = Vec::with_capacity(indices_raw.len());
    for index in indices_raw {
        if index < 0 || index as usize >= vcount {
            return Err(invalid_field(ctx, "indices", "index out of range"));
        }
        indices.push(index as u32);
    }

    let normals = match optional_term(map, "normals") {
        Some(_) => {
            let normals = decode_vec3_list(map, "normals", ctx)?;
            if normals.len() != vcount {
                return Err(invalid_field(ctx, "normals", "must match the vertex count"));
            }
            Some(normals)
        }
        None => None,
    };

    let uvs = match optional_term(map, "uvs") {
        Some(term) => {
            let pairs: Vec<(f64, f64)> = term
                .decode()
                .map_err(|_| invalid_field(ctx, "uvs", "expected a list of {u, v}"))?;
            if pairs.len() != vcount {
                return Err(invalid_field(ctx, "uvs", "must match the vertex count"));
            }
            Some(pairs)
        }
        None => None,
    };

    let mut vertices: Vec<Vertex> = positions
        .iter()
        .enumerate()
        .map(|(i, position)| Vertex {
            position: *position,
            normal: normals.as_ref().map(|n| n[i]).unwrap_or(Vec3::ZERO),
            uv: uvs
                .as_ref()
                .map(|u| [u[i].0 as f32, u[i].1 as f32])
                .unwrap_or([0.0, 0.0]),
        })
        .collect();

    if normals.is_none() {
        compute_normals(&mut vertices, &indices);
    }

    Ok(Mesh { vertices, indices })
}

fn decode_material(map: &TermMap<'_>) -> Result<Material, Error> {
    let ctx = "viewport3d.scene.objects.material";
    let mut material = Material::default();

    if let Some(term) = optional_term(map, "color") {
        material.color = decode_rgb(term, ctx, "color")?;
    }
    material.ambient = optional_f32(map, "ambient", ctx, material.ambient)?;
    material.diffuse = optional_f32(map, "diffuse", ctx, material.diffuse)?;
    material.specular = optional_f32(map, "specular", ctx, material.specular)?;
    material.shininess = optional_f32(map, "shininess", ctx, material.shininess)?;

    Ok(material)
}

fn decode_transform(map: &TermMap<'_>) -> Result<Transform, Error> {
    let ctx = "viewport3d.scene.objects.transform";
    Ok(Transform {
        position: optional_vec3(map, "position", ctx, Vec3::ZERO)?,
        scale: optional_vec3(map, "scale", ctx, Vec3::ONE)?,
        rotation: match optional_term(map, "rotation") {
            Some(term) => decode_rotation(term, ctx)?,
            None => Quat::IDENTITY,
        },
    })
}

fn decode_rotation(term: Term<'_>, ctx: &str) -> Result<Quat, Error> {
    let map = decode_map(term, ctx)?;
    let kind: String = decode_required(&map, "kind", ctx)?;

    let quat = match kind.as_str() {
        "quat" => {
            let value = optional_term(&map, "value").ok_or_else(|| missing_field(ctx, "value"))?;
            let (x, y, z, w): (f64, f64, f64, f64) = value
                .decode()
                .map_err(|_| invalid_field(ctx, "value", "expected {x, y, z, w}"))?;
            Quat::from_xyzw(x as f32, y as f32, z as f32, w as f32)
        }
        "euler_xyz" => {
            let v = vec3_field(&map, "value", ctx)?;
            Quat::from_rotation_x(v.x) * Quat::from_rotation_y(v.y) * Quat::from_rotation_z(v.z)
        }
        "axis_angle" => {
            let axis = vec3_field(&map, "axis", ctx)?;
            if axis.length_squared() == 0.0 {
                return Err(invalid_field(ctx, "axis", "axis must be non-zero"));
            }
            Quat::from_axis_angle(axis.normalize(), required_f32(&map, "angle", ctx)?)
        }
        other => {
            return Err(invalid_field(
                ctx,
                "rotation",
                &format!("unknown rotation kind '{other}'"),
            ))
        }
    };

    Ok(quat.normalize())
}

fn decode_light(term: Term<'_>) -> Result<Light, Error> {
    let map = decode_map(term, "viewport3d.scene.lights")?;
    let ctx = "viewport3d.scene.lights";
    let kind: String = decode_required(&map, "kind", ctx)?;

    let color = match optional_term(&map, "color") {
        Some(term) => decode_rgb(term, ctx, "color")?,
        None => Rgb::WHITE,
    };
    let intensity = optional_f32(&map, "intensity", ctx, 1.0)?;

    match kind.as_str() {
        "ambient" => Ok(Light::Ambient { color, intensity }),
        "directional" => {
            let direction = vec3_field(&map, "direction", ctx)?;
            if direction.length_squared() == 0.0 {
                return Err(invalid_field(ctx, "direction", "must be non-zero"));
            }
            Ok(Light::Directional {
                direction: direction.normalize(),
                color,
                intensity,
            })
        }
        "point" => Ok(Light::Point {
            position: vec3_field(&map, "position", ctx)?,
            color,
            intensity,
        }),
        other => Err(invalid_field(
            ctx,
            "kind",
            &format!("unknown light kind '{other}'"),
        )),
    }
}

fn decode_sky(term: Term<'_>) -> Result<Option<Sky>, Error> {
    let map = decode_map(term, "viewport3d.scene.sky")?;
    let ctx = "viewport3d.scene.sky";
    Ok(Some(Sky {
        zenith: rgb_field(&map, "zenith", ctx)?,
        horizon: rgb_field(&map, "horizon", ctx)?,
        ground: rgb_field(&map, "ground", ctx)?,
    }))
}

// ---- shared field helpers -------------------------------------------------

fn submap<'a>(map: &TermMap<'a>, field: &'static str, ctx: &str) -> Result<TermMap<'a>, Error> {
    let term = optional_term(map, field).ok_or_else(|| missing_field(ctx, field))?;
    decode_map(term, &format!("{ctx}.{field}"))
}

fn decode_list<'a, T, F>(
    map: &TermMap<'a>,
    field: &'static str,
    ctx: &str,
    f: F,
) -> Result<Vec<T>, Error>
where
    F: Fn(Term<'a>) -> Result<T, Error>,
{
    match optional_term(map, field) {
        None => Ok(Vec::new()),
        Some(term) => {
            let items: Vec<Term<'a>> = term
                .decode()
                .map_err(|_| invalid_field(ctx, field, "expected a list"))?;
            items.into_iter().map(f).collect()
        }
    }
}

fn vec3_field(map: &TermMap<'_>, field: &'static str, ctx: &str) -> Result<Vec3, Error> {
    let term = optional_term(map, field).ok_or_else(|| missing_field(ctx, field))?;
    decode_vec3(term, ctx, field)
}

fn optional_vec3(
    map: &TermMap<'_>,
    field: &'static str,
    ctx: &str,
    default: Vec3,
) -> Result<Vec3, Error> {
    match optional_term(map, field) {
        Some(term) => decode_vec3(term, ctx, field),
        None => Ok(default),
    }
}

fn decode_vec3(term: Term<'_>, ctx: &str, field: &str) -> Result<Vec3, Error> {
    let (x, y, z): (f64, f64, f64) = term
        .decode()
        .map_err(|_| invalid_field(ctx, field, "expected {x, y, z}"))?;
    Ok(Vec3::new(x as f32, y as f32, z as f32))
}

fn decode_vec3_list(map: &TermMap<'_>, field: &'static str, ctx: &str) -> Result<Vec<Vec3>, Error> {
    let term = optional_term(map, field).ok_or_else(|| missing_field(ctx, field))?;
    let raw: Vec<(f64, f64, f64)> = term
        .decode()
        .map_err(|_| invalid_field(ctx, field, "expected a list of {x, y, z}"))?;
    Ok(raw
        .into_iter()
        .map(|(x, y, z)| Vec3::new(x as f32, y as f32, z as f32))
        .collect())
}

fn rgb_field(map: &TermMap<'_>, field: &'static str, ctx: &str) -> Result<Rgb, Error> {
    let term = optional_term(map, field).ok_or_else(|| missing_field(ctx, field))?;
    decode_rgb(term, ctx, field)
}

fn decode_rgb(term: Term<'_>, ctx: &str, field: &str) -> Result<Rgb, Error> {
    let (r, g, b): (u8, u8, u8) = term
        .decode()
        .map_err(|_| invalid_field(ctx, field, "expected {r, g, b} with values 0-255"))?;
    Ok(Rgb(r, g, b))
}

fn required_f32(map: &TermMap<'_>, field: &'static str, ctx: &str) -> Result<f32, Error> {
    let value: f64 = decode_required(map, field, ctx)?;
    Ok(value as f32)
}

fn optional_f32(
    map: &TermMap<'_>,
    field: &'static str,
    ctx: &str,
    default: f32,
) -> Result<f32, Error> {
    Ok(decode_optional::<f64>(map, field, ctx)?
        .map(|value| value as f32)
        .unwrap_or(default))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_to_string;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    fn cube_scene() -> Scene {
        let mut scene = Scene::new();
        scene.add_object(
            SceneObject::new(primitives::cube())
                .with_material(Material::default().with_color(Rgb(100, 150, 255))),
        );
        scene.add_light(Light::ambient(Rgb(255, 255, 255), 0.2));
        scene.add_light(Light::directional(
            Vec3::new(-1.0, -1.0, -1.0),
            Rgb(255, 255, 255),
        ));
        scene
    }

    fn data(scene: Scene, render_mode: RenderMode, pipeline: Pipeline) -> Viewport3DData {
        Viewport3DData {
            scene,
            camera: Camera::default(),
            render_mode,
            pipeline,
            block: None,
        }
    }

    fn render_to_terminal(data: &Viewport3DData, w: u16, h: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(w, h);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, w, h)))
            .unwrap();
        terminal
    }

    fn has_colored_cell(terminal: &Terminal<TestBackend>) -> bool {
        let buf = terminal.backend().buffer();
        (0..buf.area.width)
            .flat_map(|x| (0..buf.area.height).map(move |y| (x, y)))
            .filter_map(|(x, y)| buf.cell((x, y)))
            .any(|cell| !matches!(cell.fg, Color::Rgb(0, 0, 0) | Color::Reset))
    }

    #[test]
    fn renders_cube_braille() {
        let terminal = render_to_terminal(
            &data(cube_scene(), RenderMode::Braille, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(!buffer_to_string(&terminal).trim().is_empty());
        assert!(
            has_colored_cell(&terminal),
            "lit cube should color some cells"
        );
    }

    #[test]
    fn renders_cube_half_block() {
        let terminal = render_to_terminal(
            &data(cube_scene(), RenderMode::HalfBlock, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn renders_cube_ascii() {
        let terminal = render_to_terminal(
            &data(cube_scene(), RenderMode::Ascii, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn renders_sphere() {
        let mut scene = Scene::new();
        scene.add_object(SceneObject::new(primitives::sphere(8, 12)));
        scene.add_light(Light::directional(
            Vec3::new(-1.0, -1.0, -1.0),
            Rgb(255, 255, 255),
        ));
        let terminal = render_to_terminal(
            &data(scene, RenderMode::Braille, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn renders_plane() {
        // The plane's front face (by winding) is its -Y side. Rotate it about X by
        // -90 deg so that front faces the camera (+Z) and scale it into a billboard.
        let mut scene = Scene::new();
        scene.add_object(
            SceneObject::new(primitives::plane()).with_transform(Transform {
                rotation: Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2),
                scale: Vec3::new(3.0, 1.0, 3.0),
                ..Transform::default()
            }),
        );
        scene.add_light(Light::ambient(Rgb(255, 255, 255), 1.0));
        scene.add_light(Light::directional(
            Vec3::new(0.0, 0.0, -1.0),
            Rgb(255, 255, 255),
        ));
        let terminal = render_to_terminal(
            &data(scene, RenderMode::Braille, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn renders_custom_mesh() {
        let mut vertices = vec![
            Vertex::new(Vec3::new(-0.5, -0.5, 0.0), Vec3::ZERO),
            Vertex::new(Vec3::new(0.5, -0.5, 0.0), Vec3::ZERO),
            Vertex::new(Vec3::new(0.0, 0.7, 0.0), Vec3::ZERO),
        ];
        let indices = vec![0, 1, 2];
        compute_normals(&mut vertices, &indices);
        let mut scene = Scene::new();
        scene.add_object(SceneObject::new(Mesh::new(vertices, indices)));
        scene.add_light(Light::ambient(Rgb(255, 255, 255), 1.0));
        let terminal = render_to_terminal(
            &data(scene, RenderMode::Braille, Pipeline::Rasterize),
            30,
            15,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn raytrace_pipeline_renders() {
        let terminal = render_to_terminal(
            &data(cube_scene(), RenderMode::HalfBlock, Pipeline::Raytrace),
            20,
            10,
        );
        assert!(has_colored_cell(&terminal));
    }

    #[test]
    fn empty_scene_renders_without_colored_cells() {
        let terminal = render_to_terminal(
            &data(Scene::new(), RenderMode::Braille, Pipeline::Rasterize),
            20,
            10,
        );
        assert!(!has_colored_cell(&terminal));
    }

    #[test]
    fn renders_with_block() {
        let mut viewport = data(cube_scene(), RenderMode::Braille, Pipeline::Rasterize);
        viewport.block = Some(BlockData {
            title: Some(ratatui::text::Line::from("Scene")),
            borders: ratatui::widgets::Borders::ALL,
            ..Default::default()
        });
        let terminal = render_to_terminal(&viewport, 20, 8);
        assert!(buffer_to_string(&terminal).contains("Scene"));
    }

    #[test]
    fn parse_render_mode_accepts_known() {
        assert!(matches!(
            parse_render_mode("half_block"),
            Ok(RenderMode::HalfBlock)
        ));
        assert!(matches!(
            parse_render_mode("braille"),
            Ok(RenderMode::Braille)
        ));
        assert!(matches!(parse_render_mode("ascii"), Ok(RenderMode::Ascii)));
    }

    #[test]
    fn parse_render_mode_rejects_unknown() {
        assert!(parse_render_mode("wireframe").is_err());
    }

    #[test]
    fn parse_pipeline_accepts_known() {
        assert!(matches!(
            parse_pipeline("rasterize"),
            Ok(Pipeline::Rasterize)
        ));
        assert!(matches!(parse_pipeline("raytrace"), Ok(Pipeline::Raytrace)));
    }

    #[test]
    fn parse_pipeline_rejects_unknown() {
        assert!(parse_pipeline("raytrace_gpu").is_err());
    }
}
