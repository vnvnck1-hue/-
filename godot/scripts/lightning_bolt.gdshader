shader_type spatial;
// Lightning stroke on a camera-facing ribbon (Vfx._ribbon).
// UV.x runs across the ribbon (0..1, centre line at 0.5), UV.y along it (0 at the start .. 1 at the tip).
// The ribbon is wider than the bolt: its outer part only carries the soft halo.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 halo_color : source_color = vec4(0.25, 0.6, 1.0, 1.0);
uniform float intensity = 1.0;        // overall brightness
uniform float core_width = 0.13;      // share of the ribbon the white-hot core takes
uniform float reveal = 1.0;           // how far down the stroke has travelled (0..1)
uniform float burn = 0.0;             // 0 = full, 1 = thinned away and gone
uniform float length_m = 10.0;        // world length, keeps the noise scale even on long / short strokes
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i + seed), hash(i + 1.0 + seed), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float along = UV.y * length_m;
	// a faint shimmer of the edge, so the stroke is alive without looking ragged
	float wob = (noise(along * 3.0 + floor(TIME * 24.0) * 5.3) - 0.5) * 0.03;
	float d = abs(UV.x - 0.5 - wob) * 2.0;   // 0 on the stroke .. 1 at the ribbon edge
	// COLOR.r = brush thickness from the mesh / 3 (fat at kinks, pinched between; Vfx.THICK_MAX)
	float th = COLOR.r * 3.0;
	float cw = core_width * th * (1.0 - burn);
	float core = smoothstep(cw, cw * 0.65, d);   // crisp edge: reads as an ink stroke, not a tube
	float rim = smoothstep(cw * 1.9, cw * 1.1, d) - core;   // cyan band hugging the white core
	float halo = exp(-d * 5.0 / (0.6 + 0.4 * th)) * (1.0 - smoothstep(0.7, 1.0, d)) * (1.0 - burn * 0.6);
	float lit = 1.0 - smoothstep(reveal, reveal + 0.015, UV.y);
	float ends = smoothstep(0.0, 0.1, UV.y);
	vec3 col = core_color.rgb * core * 1.7 + rim_color.rgb * max(rim, 0.0) * 1.3 + halo_color.rgb * halo * 0.7;
	ALBEDO = col * intensity * lit * ends * (1.0 - burn * burn);
	ALPHA = 1.0;
}
