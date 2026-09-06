shader_type spatial;
// Sun-dragon flame body. Original procedural work: no third-party textures,
// no frames extracted from any anime or game footage.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform vec4 flame_color : source_color = vec4(1.0, 0.28, 0.02, 1.0);
// reveal sweeps the dragon into existence from tail (0) to head (1).
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.6;
uniform float flow_speed : hint_range(0.0, 6.0) = 2.4;
// Head sits at +X in model space; the tail wraps around behind it.
uniform vec3 head_anchor = vec3(2.05, 1.0, 0.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.6 + noise3(p * 2.1) * 0.26 + noise3(p * 4.3) * 0.14;
}

varying vec3 model_pos;
varying float sweep;

void vertex() {
	model_pos = VERTEX;
	// Angle around the actor: the arc is swept, so the phase orders the body.
	float ang = atan(VERTEX.z, VERTEX.x - 0.0);
	sweep = clamp((ang + 3.14159) / 6.28318, 0.0, 1.0);
	// Flames breathe outward along their own normal while alive.
	float alive = smoothstep(sweep - 0.12, sweep + 0.02, reveal);
	VERTEX += NORMAL * alive * (0.02 + 0.045 * sin(TIME * 7.0 + VERTEX.y * 3.0 + sweep * 12.0));
}

void fragment() {
	float head_d = distance(model_pos, head_anchor);
	// Flame flows along the body toward the head, plus a rising component.
	vec3 q = model_pos * 1.9;
	q.y -= TIME * flow_speed;
	q.x += TIME * flow_speed * 0.35;
	float n = fbm(q);
	float fine = fbm(model_pos * 5.5 + vec3(0.0, -TIME * flow_speed * 1.7, TIME * 0.7));

	// Birth: only the swept-in section exists yet.
	float born = smoothstep(sweep - 0.10, sweep + 0.03, reveal);
	// Death: tail dissolves first as burn advances toward the head.
	float died = smoothstep(burn - 0.05, burn + 0.15, sweep);
	float mask = born * died;
	// Ragged edges instead of a flat cut.
	float alpha = mask * smoothstep(0.32, 0.62, n * 0.55 + fine * 0.45 + 0.24);

	// Layered heat: gold at the core and along the head, crimson at the fringes.
	float heat = clamp(fine * 0.55 + n * 0.45, 0.0, 1.0);
	float core = smoothstep(0.62, 0.24, head_d) * 0.45 + heat * 0.55;
	vec3 tint = mix(flame_color.rgb, vec3(1.0, 0.86, 0.34), pow(core, 1.6));
	tint = mix(vec3(0.42, 0.02, 0.01), tint, smoothstep(0.05, 0.45, heat));
	// A bright leading edge marks where the dragon is being born right now.
	float front = smoothstep(0.06, 0.0, abs(reveal - sweep));
	tint += vec3(1.0, 0.75, 0.30) * front * 1.1;

	ALBEDO = tint;
	EMISSION = tint * intensity * (0.45 + core);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
