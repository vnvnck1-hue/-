// Inverted-hull outline with a constant on-screen width (used as next_pass for hover / drag highlight).
// energy > 1 pushes the colour into HDR so the glow pass gives it a neon halo.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform float energy = 1.0;
uniform float width_px = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 off = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	if (length(off) > 0.0001) {
		off = normalize(off);
	}
	clip.xy += off * width_px * clip.w * 2.0 / VIEWPORT_SIZE;
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb * energy;
}
