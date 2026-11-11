shader_type canvas_item;
// Slow drifting noise "nebula" behind everything. Tint per act/biome via uniforms.
uniform vec4 top_color : source_color = vec4(0.09, 0.07, 0.15, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform vec4 glow_color : source_color = vec4(0.55, 0.28, 0.85, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float n = noise(uv * vec2(3.0, 5.0) + vec2(TIME * 0.03, TIME * 0.02)) * 0.6
			+ noise(uv * vec2(7.0, 12.0) - TIME * 0.04) * 0.4;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, uv.y);
	col += glow_color.rgb * pow(n, 3.0) * 0.45;
	float vignette = smoothstep(1.15, 0.35, length((uv - vec2(0.5, 0.4)) * vec2(1.0, 0.8)));
	COLOR = vec4(col * vignette, 1.0);
}
