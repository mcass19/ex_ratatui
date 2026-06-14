use crate::material::Material;
use crate::mesh::Mesh;
use crate::transform::Transform;

/// A renderable object in the scene.
#[derive(Debug, Clone)]
pub struct SceneObject {
    pub mesh: Mesh,
    pub material: Material,
    pub transform: Transform,
    pub visible: bool,
}

impl SceneObject {
    pub fn new(mesh: Mesh) -> Self {
        Self {
            mesh,
            material: Material::default(),
            transform: Transform::default(),
            visible: true,
        }
    }

    pub fn with_material(mut self, material: Material) -> Self {
        self.material = material;
        self
    }

    pub fn with_transform(mut self, transform: Transform) -> Self {
        self.transform = transform;
        self
    }
}
