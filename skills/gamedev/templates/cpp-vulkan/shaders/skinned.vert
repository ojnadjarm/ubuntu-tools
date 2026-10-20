#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec4 in_tangent;
layout(location = 4) in uvec4 in_joints;
layout(location = 5) in vec4 in_weights;

layout(push_constant) uniform Push {
    mat4 mvp;
    mat4 model;
} pc;

layout(set = 2, binding = 0) readonly buffer Joints {
    mat4 joints[];
};

layout(location = 0) out vec3 out_world;
layout(location = 1) out vec3 out_normal;
layout(location = 2) out vec2 out_uv;
layout(location = 3) out vec4 out_tangent;

void main() {
    mat4 skin = in_weights.x * joints[in_joints.x] + in_weights.y * joints[in_joints.y] +
                in_weights.z * joints[in_joints.z] + in_weights.w * joints[in_joints.w];
    vec4 local = skin * vec4(in_position, 1.0);
    mat3 normal_matrix = mat3(pc.model) * mat3(skin);
    gl_Position = pc.mvp * local;
    out_world = (pc.model * local).xyz;
    out_normal = normal_matrix * in_normal;
    out_tangent = vec4(normal_matrix * in_tangent.xyz, in_tangent.w);
    out_uv = in_uv;
}
