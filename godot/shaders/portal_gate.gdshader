shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 gate_color : source_color = vec4(0.15, 0.65, 1.0, 1.0);
uniform float speed : hint_range(0.0, 3.0) = 0.8;
uniform float intensity : hint_range(0.0, 5.0) = 1.2;

void vertex() {
	// Camera-facing glow: readable from either side, no opaque column.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = TIME * speed;
	float wave = sin(angle * 3.0 - t * 2.0) * 0.018 + sin(angle * 7.0 + t) * 0.009;
	float rim_distance = abs(r - 0.72 - wave);
	float rim = exp(-rim_distance * 95.0);
	float halo = exp(-rim_distance * 15.0) * 0.40;
	float inside = (1.0 - smoothstep(0.60, 0.74, r));
	float spiral = pow(0.5 + 0.5 * sin(angle * 3.0 + r * 19.0 - t * 3.0), 7.0);
	float veil = inside * (0.055 + spiral * 0.12) * smoothstep(0.0, 0.2, r);
	float motes = pow(0.5 + 0.5 * sin(angle * 19.0 - t * 1.8), 30.0) * exp(-abs(r - 0.85) * 55.0);
	float fade = 1.0 - smoothstep(0.90, 0.99, r);
	float glow = (rim + halo + veil + motes * 0.55) * fade;
	ALBEDO = mix(gate_color.rgb, vec3(0.80, 0.96, 1.0), rim);
	EMISSION = ALBEDO * intensity;
	ALPHA = clamp(glow * intensity, 0.0, 1.0);
}
