#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec4 in_tangent;

layout(push_constant) uniform Push {
    mat4 mvp;
    mat4 model;
} pc;

layout(location = 0) out vec3 out_world;
layout(location = 1) out vec3 out_normal;
layout(location = 2) out vec2 out_uv;
layout(location = 3) out vec4 out_tangent;

void main() {
    gl_Position = pc.mvp * vec4(in_position, 1.0);
    out_world = (pc.model * vec4(in_position, 1.0)).xyz;
    out_normal = mat3(pc.model) * in_normal;
    out_tangent = vec4(mat3(pc.model) * in_tangent.xyz, in_tangent.w);
    out_uv = in_uv;
}
