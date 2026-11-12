shader_type canvas_item;
// Procedural backdrop behind everything. Colors and style come from the theme:
// style 0 = drifting nebula, 1 = paper grain, 2 = neon grid, 3 = glass shards,
// 4 = glassnet: cracked holo-glass panes with neon data pulses in the cracks.
uniform int style = 0;
uniform float glass_intensity : hint_range(1.0, 2.0) = 1.0;
uniform float kiln_entrance = -1.0;
uniform vec4 kiln_color : source_color = vec4(1.0, 0.5, 0.18, 1.0);
uniform vec4 top_color : source_color = vec4(0.09, 0.07, 0.15, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform vec4 glow_color : source_color = vec4(0.55, 0.28, 0.85, 1.0);
uniform vec4 glow2_color : source_color = vec4(1.0, 0.17, 0.84, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance to nearest and second-nearest cell point (for glass leading).
vec2 voronoi(vec2 p) {
	vec2 g = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + vec2(hash(g + o), hash(g + o + 17.0)) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, uv.y);
	if (style == 0) {
		float n = noise(uv * vec2(3.0, 5.0) + vec2(TIME * 0.03, TIME * 0.02)) * 0.6
				+ noise(uv * vec2(7.0, 12.0) - TIME * 0.04) * 0.4;
		col += glow_color.rgb * pow(n, 3.0) * 0.45;
		// Sparse twinkling stars.
		vec2 sg = uv * vec2(60.0, 106.0);
		vec2 cell = floor(sg);
		vec2 jitter = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.6 + 0.2;
		float dot_ = smoothstep(0.16, 0.0, length(fract(sg) - jitter));
		float s = step(0.975, hash(cell)) * dot_ * (0.55 + 0.45 * sin(TIME * 2.0 + hash(cell) * 40.0));
		col += vec3(s) * 0.85;
	} else if (style == 1) {
		float grain = noise(uv * vec2(400.0, 700.0)) * 0.06 + noise(uv * vec2(8.0, 14.0)) * 0.08;
		col += vec3(grain) - 0.05;
		float stain = smoothstep(0.55, 0.9, noise(uv * 3.0 + 4.0));
		col = mix(col, glow_color.rgb, stain * 0.12);
	} else if (style == 2) {
		vec2 g = uv * vec2(14.0, 24.0);
		g.y += TIME * 0.4;
		vec2 f = abs(fract(g) - 0.5);
		float line = smoothstep(0.47, 0.5, max(f.x, f.y));
		col += glow_color.rgb * line * (0.25 + 0.75 * uv.y) * 0.5;
		col += glow_color.rgb * 0.15 * pow(1.0 - uv.y, 3.0);
	} else if (style == 4) {
		vec2 cells = vec2(5.0, 9.0);
		vec2 p = uv * cells + vec2(0.0, TIME * 0.01);
		vec2 v = voronoi(p);
		float gap = v.y - v.x;
		float id = hash(floor(p + v.x * 0.5));
		// Panes: dark glass faintly tinted cyan or magenta, with a diagonal sheen.
		vec3 tint = mix(glow_color.rgb, glow2_color.rgb, step(0.62, id));
		float sheen = smoothstep(0.0, 1.0, sin((uv.x + uv.y * 0.6) * 7.0 + id * 9.0 + TIME * 0.15) * 0.5 + 0.5);
		vec3 pane = mix(col, tint, (0.03 + 0.05 * id + 0.03 * sheen) * glass_intensity);
		// Digital rain inside a few panes.
		vec2 rg = vec2(floor(uv.x * 90.0), floor(uv.y * 64.0 - TIME * (3.0 + 4.0 * hash(vec2(floor(uv.x * 90.0), 1.0)))));
		float rain = step(0.93, hash(rg)) * step(0.7, id) * 0.5;
		pane += tint * rain * 0.18 * glass_intensity;
		// Cracks: heavy dark leading with a thin glowing core; pulses travel along it.
		float lead = 1.0 - smoothstep(0.0, 0.07, gap);
		float core = 1.0 - smoothstep(0.0, 0.018, gap);
		float pulse = pow(0.5 + 0.5 * sin(TIME * 1.6 - (uv.y * 14.0 + uv.x * 6.0) + id * 6.28), 6.0);
		vec3 neon = mix(glow_color.rgb, glow2_color.rgb, 0.5 + 0.5 * sin(uv.y * 3.0 + TIME * 0.3));
		col = mix(pane, vec3(0.0), lead * 0.85);
		col += neon * core * (0.25 + 0.9 * pulse) * glass_intensity;
		if (kiln_entrance > -0.5) {
			float heat_wave = 1.0 - smoothstep(0.0, 0.18, abs(uv.y - kiln_entrance));
			col += kiln_color.rgb * heat_wave * (core * 0.88 + lead * 0.14 + 0.035);
		}
		// Scanlines.
		col *= 0.93 + 0.07 * sin(FRAGCOORD.y * 2.1);
	} else {
		vec2 v = voronoi(uv * vec2(6.0, 10.0));
		float edge = 1.0 - smoothstep(0.0, 0.06, v.y - v.x);
		float shade = hash(floor(uv * vec2(6.0, 10.0) + v.x));
		vec3 glass = mix(col, glow_color.rgb, 0.035 + 0.09 * shade + 0.03 * sin(TIME * 0.5 + shade * 6.0));
		col = mix(glass, vec3(0.0), edge * 0.85);
	}
	float vignette = smoothstep(1.2, 0.35, length((uv - vec2(0.5, 0.42)) * vec2(1.0, 0.8)));
	COLOR = vec4(col * mix(0.75, 1.0, vignette), 1.0);
}
