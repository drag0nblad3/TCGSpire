shader_type canvas_item;
render_mode blend_add;
// Glitch foil: a program that compiled wrong in a way nobody can reproduce.
// Scanlines, RGB-split bands and the odd torn slice. Purely procedural.
uniform float strength = 0.6;
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 91.345 + seed) * 47453.5453); }

void fragment() {
	float t = TIME;
	// Torn slices: a few horizontal bands jump sideways now and then.
	float slice = floor(UV.y * 18.0);
	float tick = floor(t * 3.0);
	float tear = step(0.92, hash(slice + tick * 7.0)) * (hash(slice * 3.1 + tick) - 0.5) * 0.25;
	vec2 uv = UV + vec2(tear, 0.0);
	// RGB split bands sweeping down.
	float sweep = fract(uv.y * 1.5 - t * 0.35);
	float band = smoothstep(0.0, 0.08, sweep) * smoothstep(0.22, 0.08, sweep);
	vec3 split = vec3(
		0.5 + 0.5 * sin(uv.x * 18.0 + t * 2.0),
		0.5 + 0.5 * sin(uv.x * 18.0 + t * 2.0 + 2.1),
		0.5 + 0.5 * sin(uv.x * 18.0 + t * 2.0 + 4.2));
	float scan = 0.35 + 0.65 * step(0.5, fract(uv.y * 90.0));
	float a = (band * 0.85 + abs(tear) * 3.0 + 0.08) * scan * strength;
	COLOR = vec4(split * a, a);
}
