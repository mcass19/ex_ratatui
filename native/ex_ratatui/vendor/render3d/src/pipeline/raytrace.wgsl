struct Uniforms {
    position: vec4<f32>,
    forward: vec4<f32>,
    right: vec4<f32>,
    up: vec4<f32>,
    params: vec4<f32>,      // half_w, half_h, width, height
    counts: vec4<u32>,      // num_triangles, num_lights, has_sky, 0
    background: vec4<f32>,  // rgb (0-1), unused
    sky_horizon: vec4<f32>, // rgb (0-1), unused
    sky_ground: vec4<f32>,  // rgb (0-1), unused
};

struct Triangle {
    v0: vec4<f32>,
    v1: vec4<f32>,
    v2: vec4<f32>,
    n0: vec4<f32>,
    n1: vec4<f32>,
    n2_idx: vec4<f32>,  // xyz = normal, w = bitcast obj_idx
};

struct Material {
    color_ambient: vec4<f32>,  // rgb (0-255), ambient
    phong: vec4<f32>,          // diffuse, specular, shininess, 0
};

struct Light {
    type_intensity: vec4<f32>,  // type (0=ambient,1=dir,2=point), intensity, 0, 0
    dir_pos: vec4<f32>,         // direction or position
    color: vec4<f32>,           // rgb (0-255), 0
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var<storage, read> triangles: array<Triangle>;
@group(0) @binding(2) var<storage, read> materials: array<Material>;
@group(0) @binding(3) var<storage, read> lights: array<Light>;
@group(0) @binding(4) var<storage, read_write> output: array<u32>;

const EPSILON: f32 = 0.0001;

fn ray_tri(origin: vec3<f32>, dir: vec3<f32>, idx: u32) -> vec3<f32> {
    let tri = triangles[idx];
    let e1 = tri.v1.xyz - tri.v0.xyz;
    let e2 = tri.v2.xyz - tri.v0.xyz;
    let h = cross(dir, e2);
    let a = dot(e1, h);
    if abs(a) < EPSILON { return vec3<f32>(-1.0, 0.0, 0.0); }
    let f = 1.0 / a;
    let s = origin - tri.v0.xyz;
    let uu = f * dot(s, h);
    if uu < 0.0 || uu > 1.0 { return vec3<f32>(-1.0, 0.0, 0.0); }
    let q = cross(s, e1);
    let vv = f * dot(dir, q);
    if vv < 0.0 || uu + vv > 1.0 { return vec3<f32>(-1.0, 0.0, 0.0); }
    let t = f * dot(e2, q);
    if t > EPSILON { return vec3<f32>(t, uu, vv); }
    return vec3<f32>(-1.0, 0.0, 0.0);
}

fn closest_hit(origin: vec3<f32>, dir: vec3<f32>) -> vec4<f32> {
    var min_t: f32 = 1e30;
    var best = vec4<f32>(-1.0, 0.0, 0.0, -1.0);
    let n = u.counts.x;
    for (var i: u32 = 0u; i < n; i++) {
        let r = ray_tri(origin, dir, i);
        if r.x > 0.0 && r.x < min_t {
            min_t = r.x;
            best = vec4<f32>(r, f32(i));
        }
    }
    return best;
}

fn any_hit(origin: vec3<f32>, dir: vec3<f32>, max_t: f32) -> bool {
    let n = u.counts.x;
    for (var i: u32 = 0u; i < n; i++) {
        let r = ray_tri(origin, dir, i);
        if r.x > 0.0 && r.x < max_t { return true; }
    }
    return false;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let w = u32(u.params.z);
    let h = u32(u.params.w);
    if id.x >= w || id.y >= h { return; }

    let half_w = u.params.x;
    let half_h = u.params.y;
    let ndc_x = (2.0 * (f32(id.x) + 0.5) / f32(w)) - 1.0;
    let ndc_y = 1.0 - (2.0 * (f32(id.y) + 0.5) / f32(h));

    let origin = u.position.xyz;
    let dir = normalize(u.forward.xyz + u.right.xyz * (ndc_x * half_w) + u.up.xyz * (ndc_y * half_h));

    let hit = closest_hit(origin, dir);

    var color: vec3<f32>;
    var alpha: u32 = 255u;
    if hit.x < 0.0 {
        alpha = 0u;
        if u.counts.z == 1u {
            // Sky gradient
            let dy = dir.y;
            if dy > 0.0 {
                color = mix(u.sky_horizon.xyz, u.background.xyz, min(dy, 1.0));
            } else {
                color = mix(u.sky_horizon.xyz, u.sky_ground.xyz, min(-dy, 1.0));
            }
        } else {
            color = u.background.xyz;
        }
    } else {
        let t = hit.x;
        let uu = hit.y;
        let vv = hit.z;
        let tri_idx = u32(hit.w);
        let ww = 1.0 - uu - vv;

        let tri = triangles[tri_idx];
        let pos = origin + dir * t;
        var normal = normalize(tri.n0.xyz * ww + tri.n1.xyz * uu + tri.n2_idx.xyz * vv);
        if dot(normal, dir) > 0.0 { normal = -normal; }

        let obj_idx = bitcast<u32>(tri.n2_idx.w);
        let mat = materials[obj_idx];
        let mat_color = mat.color_ambient.xyz;
        let ambient_k = mat.color_ambient.w;
        let diffuse_k = mat.phong.x;
        let specular_k = mat.phong.y;
        let shininess = mat.phong.z;
        let view_dir = normalize(-dir);
        let shadow_o = pos + normal * EPSILON;

        var total = vec3<f32>(0.0);
        let nl = u.counts.y;
        for (var li: u32 = 0u; li < nl; li++) {
            let light = lights[li];
            let ltype = u32(light.type_intensity.x);
            let intensity = light.type_intensity.y;
            let lcol = light.color.xyz / 255.0;

            if ltype == 0u {
                total += lcol * intensity * ambient_k;
            } else if ltype == 1u {
                let ldir = -light.dir_pos.xyz;
                if !any_hit(shadow_o, ldir, 1e30) {
                    let diff = max(dot(normal, ldir), 0.0) * diffuse_k * intensity;
                    let halfway = normalize(ldir + view_dir);
                    let spec = pow(max(dot(normal, halfway), 0.0), shininess) * specular_k * intensity;
                    total += lcol * (diff + spec);
                }
            } else {
                let to_l = light.dir_pos.xyz - pos;
                let dist = length(to_l);
                let ldir = to_l / dist;
                if !any_hit(shadow_o, ldir, dist) {
                    let atten = intensity / (1.0 + 0.09 * dist + 0.032 * dist * dist);
                    let diff = max(dot(normal, ldir), 0.0) * diffuse_k * atten;
                    let halfway = normalize(ldir + view_dir);
                    let spec = pow(max(dot(normal, halfway), 0.0), shininess) * specular_k * atten;
                    total += lcol * (diff + spec);
                }
            }
        }
        color = clamp(total * mat_color / 255.0, vec3<f32>(0.0), vec3<f32>(1.0));
    }

    let r = u32(color.x * 255.0);
    let g = u32(color.y * 255.0);
    let b = u32(color.z * 255.0);
    output[id.y * w + id.x] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
