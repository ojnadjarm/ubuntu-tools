#version 450
layout(location = 0) in vec2 v_uv;
layout(set = 0, binding = 1) uniform sampler2D albedo;
layout(push_constant) uniform Push { vec4 tint; } pc;
layout(location = 0) out vec4 out_color;
void main() {
	out_color = texture(albedo, v_uv) * pc.tint;
}
