shader_type canvas_item;
render_mode blend_add;
// Glitch foil: a program that compiled wrong in a way nobody can reproduce.
// Big torn slices, stuck pixel blocks, a wide RGB-split sweep and a chromatic
// fringe on the edges. Purely procedural. Sized to read on a phone without shouting: the
// effect is loud on the art and frame and damped over the rules text box.
uniform float strength = 1.0;
uniform float seed = 0.0;

const vec3 CYAN = vec3(0.1, 0.95, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.15, 0.85);
const vec3 LIME = vec3(0.55, 1.0, 0.2);

float hash(float n) { return fract(sin(n * 91.345 + seed) * 47453.5453); }
float hash2(vec2 p) { return hash(p.x * 17.13 + p.y * 131.7); }

vec3 pick(float h) {
	return h < 0.45 ? CYAN : (h < 0.9 ? MAGENTA : LIME);
}

void fragment() {
	float t = TIME;
	float tick = floor(t * 4.0);
	// Torn slices: thick horizontal bands (9 per card, ~1 in 6 per tick) jump sideways; about one in four each tick.
	float slice = floor(UV.y * 9.0);
	float torn = step(0.84, hash(slice + tick * 7.0));
	float shift = (hash(slice * 3.1 + tick) - 0.5) * 0.35 * torn;
	vec2 uv = UV + vec2(shift, 0.0);
	// A torn slice is a solid colour sheet with hard bright edges where it was cut.
	vec3 slice_col = pick(hash(slice * 5.7 + tick * 1.3));
	float sy = fract(UV.y * 9.0);
	float cut_edge = (step(sy, 0.05) + step(0.95, sy)) * torn;
	float sheet = torn * (0.12 + 0.14 * step(0.5, fract(uv.x * 6.0 + hash(slice + tick))));
	// Stuck pixel blocks: a coarse grid where a few cells light up for a tick.
	vec2 cell = floor(vec2(UV.x * 6.0, UV.y * 11.0));
	float block = step(0.96, hash2(cell + vec2(tick * 3.0, tick)));
	vec3 block_col = pick(hash2(cell + 0.5));
	// RGB split sweep: a wide band rolling down, magenta and cyan pulled apart.
	float sweep = fract(uv.y * 1.2 - t * 0.45);
	float band = smoothstep(0.0, 0.06, sweep) * smoothstep(0.3, 0.1, sweep);
	float off = 0.035 * band;
	float r = 0.5 + 0.5 * sin((uv.x - off) * 14.0 + t * 3.0);
	float b = 0.5 + 0.5 * sin((uv.x + off) * 14.0 + t * 3.0 + 3.14);
	vec3 split = mix(CYAN * b, MAGENTA * r, 0.5) * 1.6;
	// Chromatic fringe on the left/right edges: cyan on one side, magenta on the other.
	float fringe_w = 0.05 + 0.05 * torn;
	float left = smoothstep(fringe_w, 0.0, uv.x);
	float right = smoothstep(1.0 - fringe_w, 1.0, uv.x);
	vec3 fringe = CYAN * left + MAGENTA * right;
	// Scanlines, chunky enough to survive phone downscaling.
	float scan = 0.55 + 0.45 * step(0.5, fract(UV.y * 48.0));
	// Keep the rules text readable: damp everything over the text box.
	float text_box = step(0.47, UV.y) * step(UV.y, 0.92) * step(0.06, UV.x) * step(UV.x, 0.94);
	float damp = mix(1.0, 0.35, text_box);
	vec3 col = split * band * 0.42 * scan
		+ slice_col * (sheet * scan + cut_edge * 0.55)
		+ block_col * block * 0.35
		+ fringe * 0.45
		+ vec3(0.04, 0.06, 0.08) * scan;
	col *= damp * strength;
	COLOR = vec4(col, 1.0);
}
