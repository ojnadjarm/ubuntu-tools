#version 450
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec2 in_uv;
layout(set = 0, binding = 0) uniform Camera { mat4 view_proj; } cam;
layout(location = 0) out vec2 v_uv;
void main() {
	v_uv = in_uv;
	gl_Position = cam.view_proj * vec4(in_pos, 1.0);
}
