shader_type canvas_item;
render_mode blend_add;
// Moving rainbow sheen for rare/foil cards. Purely procedural, no textures.
uniform float strength = 0.35;
uniform float speed = 1.2;

void fragment() {
	float band = sin((UV.x * 1.4 + UV.y) * 5.0 - TIME * speed);
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (UV.x * 0.7 + UV.y * 0.4 + TIME * 0.08 + vec3(0.0, 0.33, 0.67)));
	float a = smoothstep(0.55, 1.0, band) * strength;
	COLOR = vec4(rainbow * a, a);
}
