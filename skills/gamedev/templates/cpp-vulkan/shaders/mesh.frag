#version 450

layout(location = 0) in vec3 in_world;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec4 in_tangent;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D base_color_map;
layout(set = 0, binding = 1) uniform sampler2D normal_map;
layout(set = 0, binding = 2) uniform sampler2D orm_map;
layout(set = 0, binding = 3) uniform Material {
    vec4 base_color_factor;
    vec4 params;  // metallic, roughness, normal scale, occlusion strength
    vec4 eye;
} mat;
layout(set = 1, binding = 0) uniform sampler2DShadow shadow_map;
layout(set = 1, binding = 1) uniform Frame {
    mat4 light_view_proj;
    vec4 light_dir;  // w: image-based lighting strength, 0 keeps the hemisphere sky
} frame;
layout(set = 1, binding = 2) uniform samplerCube prefiltered;  // GGX-prefiltered radiance, roughness = mip / 4
layout(set = 1, binding = 3) uniform sampler2D brdf_lut;
layout(set = 1, binding = 4) uniform Sh {
    vec4 c[9];
} sh;

const float PI = 3.14159265;

float ggx(float n_h, float a2) {
    float d = n_h * n_h * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

float smith_visibility(float n_v, float n_l, float a2) {
    float v = n_l * sqrt(n_v * n_v * (1.0 - a2) + a2);
    float l = n_v * sqrt(n_l * n_l * (1.0 - a2) + a2);
    return 0.5 / max(v + l, 1e-5);
}

/** Diffuse radiance per unit albedo from the SH9 irradiance (ibl_prefilter.comp's basis). */
vec3 irradiance(vec3 d) {
    return sh.c[0].rgb * 0.282095 + (sh.c[1].rgb * d.y + sh.c[2].rgb * d.z + sh.c[3].rgb * d.x) * 0.488603 +
           (sh.c[4].rgb * d.x * d.y + sh.c[5].rgb * d.y * d.z + sh.c[7].rgb * d.x * d.z) * 1.092548 +
           sh.c[6].rgb * 0.315392 * (3.0 * d.z * d.z - 1.0) + sh.c[8].rgb * 0.546274 * (d.x * d.x - d.y * d.y);
}

// 3x3 PCF over hardware 2x2 compare taps: 1 lit, 0 in shadow.
float shadow(vec3 world) {
    vec3 p = (frame.light_view_proj * vec4(world, 1.0)).xyz;
    vec2 uv = p.xy * 0.5 + 0.5;
    vec2 texel = 1.0 / vec2(textureSize(shadow_map, 0));
    float lit = 0.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++) lit += texture(shadow_map, vec3(uv + vec2(x, y) * texel, p.z));
    return lit / 9.0;
}

void main() {
    vec3 base = texture(base_color_map, in_uv).rgb * mat.base_color_factor.rgb;
    vec3 orm = texture(orm_map, in_uv).rgb;
    float ao = mix(1.0, orm.r, mat.params.w);
    float roughness = clamp(orm.g * mat.params.y, 0.045, 1.0);
    float metallic = orm.b * mat.params.x;

    vec3 tn = texture(normal_map, in_uv).xyz * 2.0 - 1.0;
    tn.xy *= mat.params.z;
    vec3 n = normalize(in_normal);
    vec3 t = in_tangent.xyz - n * dot(n, in_tangent.xyz);
    // Palette-textured meshes have zero-area UVs, so MikkTSpace leaves no tangent: keep the vertex normal.
    if (dot(t, t) > 1e-8) n = normalize(mat3(normalize(t), cross(n, normalize(t)) * in_tangent.w, n) * tn);

    vec3 v = normalize(mat.eye.xyz - in_world);
    vec3 l = frame.light_dir.xyz;
    vec3 h = normalize(v + l);
    float n_l = max(dot(n, l), 0.0);
    float n_v = max(dot(n, v), 1e-4);
    float a2 = pow(roughness, 4.0);
    vec3 f0 = mix(vec3(0.04), base, metallic);
    vec3 f = f0 + (1.0 - f0) * pow(1.0 - max(dot(v, h), 0.0), 5.0);
    vec3 specular = ggx(max(dot(n, h), 0.0), a2) * smith_visibility(n_v, n_l, a2) * f;
    vec3 diffuse = (1.0 - f) * (1.0 - metallic) * base / PI;
    vec3 ambient;
    if (frame.light_dir.w > 0.0) {
        // Split-sum specular (Karis 2013) with roughness-aware Fresnel, SH9 diffuse.
        vec3 f_amb = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - n_v, 5.0);
        vec2 ab = texture(brdf_lut, vec2(n_v, roughness)).rg;
        vec3 spec = textureLod(prefiltered, reflect(-v, n), roughness * 4.0).rgb * (f0 * ab.x + ab.y);
        ambient = ((1.0 - f_amb) * (1.0 - metallic) * base * max(irradiance(n), 0.0) + spec) * ao * frame.light_dir.w;
    } else {
        ambient = mix(vec3(0.08, 0.07, 0.06), vec3(0.20, 0.24, 0.30), n.y * 0.5 + 0.5) * ao * base;
    }
    vec3 linear = (diffuse + specular) * PI * n_l * shadow(in_world) + ambient;
    out_color = vec4(linear, 1.0);
}
