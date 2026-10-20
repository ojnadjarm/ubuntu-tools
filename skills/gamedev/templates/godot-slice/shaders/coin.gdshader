shader_type spatial;
// Gold coin: metallic PBR with a pulsing rim glow.

uniform vec3 base : source_color = vec3(1.0, 0.76, 0.2);
uniform float pulse_speed = 3.0;

void fragment() {
	ALBEDO = base;
	METALLIC = 1.0;
	ROUGHNESS = 0.25;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * rim * (1.5 + sin(TIME * pulse_speed));
}
