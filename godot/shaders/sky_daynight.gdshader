shader_type sky;
// Day-night sky with stars, milky way, moon and weather-driven cloud cover.
//
// Everything here is procedural on purpose. A panorama texture (what slice.tscn
// used before) cannot change time of day, and swapping between several
// panoramas gives visible pops at dawn and dusk. Procedural costs a little more
// per-pixel but the sky is one draw at infinity, so it is cheap either way.
//
// Star field is hashed from the view direction, so stars sit at infinity and
// stay put as the camera moves — the giveaway of a fake starfield is stars that
// drift or swim.

render_mode use_debanding;

uniform vec3 sun_dir = vec3(0.0, 0.6, 0.8);
uniform vec3 moon_dir = vec3(0.0, -0.6, -0.8);
// 0 = full night, 1 = full day. Driven by the sun's height, not by the clock,
// so a low winter sun still reads as evening light.
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;
// Peaks only near the horizon; drives the warm band and its reach up the sky.
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.1;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.55;
uniform float milkyway : hint_range(0.0, 1.0) = 0.35;
uniform float moon_visible : hint_range(0.0, 1.0) = 1.0;

uniform vec3 zenith_day : source_color = vec3(0.18, 0.38, 0.72);
uniform vec3 horizon_day : source_color = vec3(0.68, 0.80, 0.92);
uniform vec3 zenith_night : source_color = vec3(0.012, 0.022, 0.055);
uniform vec3 horizon_night : source_color = vec3(0.045, 0.06, 0.11);
uniform vec3 golden_tint : source_color = vec3(1.0, 0.52, 0.24);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 cloud_shadow : source_color = vec3(0.42, 0.46, 0.55);

// ── painted cloud layer (option A) ──
// An equirect texture extracted from the 人里 concept skybox by
// tools/extract_sky_clouds.py. R = coverage, G = painted shading, A = above
// horizon. The shader keeps its procedural sky COLOUR and only borrows the
// painted cloud SHAPES, then relights them by sun position — so the same
// clouds go grey at dusk and dark at night instead of staying frozen at the
// painting's afternoon.
uniform sampler2D painted_clouds : source_color, filter_linear_mipmap, repeat_enable;
// 0 = ignore the texture (fully procedural), 1 = painted clouds replace the
// procedural ones. Mid values blend both.
uniform float painted_mix : hint_range(0.0, 1.0) = 1.0;
// Rotate the painting around the vertical axis (degrees) so its best cloud
// cluster can be placed where the scene composition wants it.
uniform float painted_yaw : hint_range(-180.0, 180.0) = 0.0;
// Slow drift so a static painting does not read as a poster.
uniform float painted_drift : hint_range(0.0, 0.02) = 0.0025;
// How strongly the painted clouds show in CLEAR weather. 1.0 = the painting at
// full strength regardless of weather; 0.0 = clear skies erase it entirely
// (the old hard-coded behaviour was 0.35, which read as "no clouds"). Weather
// still adds on top of this, so raising cloud_cover always thickens the sky.
uniform float painted_base : hint_range(0.0, 1.0) = 0.85;

// Equirectangular lookup for a view direction.
vec2 equirect_uv(vec3 d, float yaw_deg) {
	float yaw = radians(yaw_deg);
	float c = cos(yaw), s = sin(yaw);
	vec3 r = vec3(d.x * c - d.z * s, d.y, d.x * s + d.z * c);
	float u = atan(r.x, -r.z) / (2.0 * PI) + 0.5;
	float v = acos(clamp(r.y, -1.0, 1.0)) / PI;
	return vec2(u, v);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// A second hash with a much flatter distribution, used for star placement.
// hash13 above clusters hard: a CPU port of the star loop measured only
// 0.4% of sky directions lighting up regardless of cell size or threshold,
// because hash13's output is nowhere near uniform on [0,1]. This one is the
// standard 3D integer-mix hash and does distribute evenly, which is what makes
// a threshold like "top 4% of cells" mean what it says.
float hash_star(vec3 p) {
	vec3 q = floor(p);
	q = fract(q * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
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
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Stars: quantise the direction into cells and light at most one point per
// cell. Cell-based rather than a pure noise threshold so the stars are discrete
// points instead of a grainy haze.
//
// Cell scale matters more than it looks: at 220 the cells are far smaller than
// a pixel's angular footprint at typical FOV, so almost every star fell between
// samples and the sky came out empty. 46 puts roughly one cell per few pixels,
// which is what actually renders as visible points.
// Cube-face parameterisation: turn a view direction into a 2D coordinate plus a
// face id. Needed because the star grid must be TWO-dimensional.
vec2 cube_uv(vec3 d, out float face) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) {
		face = d.x > 0.0 ? 0.0 : 1.0;
		return vec2(d.z, d.y) / a.x;
	}
	if (a.y >= a.z) {
		face = d.y > 0.0 ? 2.0 : 3.0;
		return vec2(d.x, d.z) / a.y;
	}
	face = d.z > 0.0 ? 4.0 : 5.0;
	return vec2(d.x, d.y) / a.z;
}

// Stars on a 2D grid over the sky, NOT a 3D grid in space.
//
// The 3D version was the real bug behind three rounds of invisible stars. It
// placed each star at a random point inside a volumetric cell, but only the
// thin shell where the unit sphere crosses that cell is ever visible. A star
// sitting even 0.25 cells off that shell still contributes its radial offset to
// the distance term, so it renders at a few percent brightness — measured mean
// output was 0.008. The milky way survived because it is a smooth low-frequency
// band that never depended on hitting a point exactly.
//
// Parameterising by cube face makes every star lie ON the visible surface, so a
// cell that hosts a star always shows it at full brightness.
float starfield(vec3 dir, float density) {
	if (density <= 0.001) {
		return 0.0;
	}
	// Square the slider so the low end has usable resolution. The cell count is
	// huge (866 400), so a LINEAR mapping spends its whole bottom third in the
	// tens of thousands of stars — 密度 0.05 would still be 6 065 points, which
	// still reads as "far too many". Squared, 0.05 is 303 and 0.1 is 1 213,
	// so the sparse end is actually dialable; 1.0 is unchanged.
	float d2 = density * density;
	float face;
	vec2 uv = cube_uv(dir, face);
	vec2 p = uv * 190.0;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float best = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			vec3 key = vec3(cell + o, face);
			float seed = hash_star(key);
			// Threshold runs from 1.0 (density 0 = a genuinely empty sky) down
			// to 0.86 (density 1 = 14% of cells lit, ~121k stars).
			//
			// The top end used to be 0.955, which left a FLOOR of 4.5% of cells
			// always lit — about 39 000 stars — no matter how low the slider
			// went. 密度 0.01 measured 39 811 stars and 密度 0.00 still 38 988,
			// so the control appeared to do nothing at the low end and the sky
			// could never be cleared. The grid is 380x380 per cube face over
			// 6 faces = 866 400 cells, so a few percent is tens of thousands of
			// points; the top of this range has to be exactly 1.0 or "off" is
			// not reachable.
			if (seed > mix(1.0, 0.86, d2)) {
				vec2 pos = o + vec2(
					hash_star(key + 11.3),
					hash_star(key + 27.7));
				float d = length(f - pos);
				float mag = 0.35 + 0.65 * hash_star(key + 61.9);
				// Generous radius: a sub-pixel point is eaten by TAA, which is
				// enabled project-wide.
				float s = smoothstep(0.45, 0.0, d) * mag;
				best = max(best, s);
			}
		}
	}
	return best;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, -1.0, 1.0);
	float h = pow(clamp(1.0 - abs(up), 0.0, 1.0), 2.2);

	// ── base gradient ──
	vec3 day_col = mix(zenith_day, horizon_day, h);
	vec3 night_col = mix(zenith_night, horizon_night, h);
	vec3 col = mix(night_col, day_col, day_amount);

	// ── warm band near the sun at low elevation ──
	float sun_d = max(dot(dir, normalize(sun_dir)), 0.0);
	float band = pow(h, 1.4) * pow(sun_d * 0.5 + 0.5, 3.0);
	col = mix(col, golden_tint, clamp(band * golden * 1.35, 0.0, 0.85));

	// ── sun disc + glow ──
	float disc = smoothstep(0.9986, 0.9994, sun_d);
	float glow = pow(sun_d, 220.0) * 0.6 + pow(sun_d, 12.0) * 0.10;
	vec3 sun_col = mix(vec3(1.0, 0.98, 0.92), vec3(1.0, 0.55, 0.28), golden);
	// Cloud cover hides the disc, but not the glow — an overcast sky still has
	// a bright patch where the sun is.
	col += sun_col * (disc * 14.0 * (1.0 - cloud_cover * 0.9) + glow) * day_amount;

	// ── stars + milky way (night only) ──
	float night = 1.0 - day_amount;
	if (night > 0.01) {
		float clear_sky = 1.0 - cloud_cover * 0.95;
		float s = starfield(dir, star_density) * night * clear_sky;
		// Fewer stars low down, where haze eats them.
		s *= smoothstep(-0.02, 0.24, up);
		// Stars must clear the tonemapper and the glow threshold to read as
		// points; at 1.6 they were being crushed to nothing on an ACES curve.
		col += vec3(0.95, 0.96, 1.0) * s * 6.5;

		// A soft band across the sky rather than a texture: cheap, and it never
		// shows a seam.
		float mw_axis = abs(dot(dir, normalize(vec3(0.55, 0.30, -0.78))));
		float mw = smoothstep(0.42, 0.0, mw_axis);
		mw *= fbm(dir * 5.5) * 0.9 + 0.25;
		mw *= night * clear_sky * milkyway * smoothstep(-0.02, 0.30, up);
		col += vec3(0.55, 0.60, 0.85) * mw * 0.30;
	}

	// ── moon ──
	if (moon_visible > 0.5 && night > 0.01) {
		float md = max(dot(dir, normalize(moon_dir)), 0.0);
		float mdisc = smoothstep(0.9992, 0.9997, md);
		float mglow = pow(md, 400.0) * 0.5;
		// Faint surface mottling so it does not read as a flat white circle.
		float mottle = 0.82 + 0.18 * fbm(dir * 90.0);
		col += vec3(0.94, 0.95, 1.0) * (mdisc * mottle * 3.2 + mglow) * night;
	}

	// ── clouds ──
	// Both cloud sources share one lighting model so they respond to time of
	// day identically; only the SHAPE differs.
	vec3 lit = mix(cloud_lit, vec3(0.98, 0.72, 0.52), golden);
	vec3 dark = mix(cloud_shadow, vec3(0.30, 0.28, 0.34), overcast);
	// Clouds are backlit near the sun and dark away from it.
	vec3 cl = mix(dark, lit, clamp(sun_d * 0.6 + 0.4 * day_amount, 0.0, 1.0));
	cl *= mix(0.22, 1.0, day_amount);

	// Painted layer from the concept skybox.
	if (painted_mix > 0.001) {
		vec2 puv = equirect_uv(dir, painted_yaw + TIME * painted_drift * 57.2958);
		vec4 p = texture(painted_clouds, puv);
		float pcov = p.r * p.a;
		// The painting's own light/shadow shading modulates the relit colour,
		// so cloud tops still read brighter than their undersides.
		vec3 pcol = cl * mix(0.55, 1.15, p.g);
		// The painted layer is ART, not weather: those cloud shapes come from
		// the concept painting and are the look the sky is supposed to have,
		// so clear weather must not erase them. This used to read
		//   mix(0.35, 1.0, cloud_cover)
		// which, on 晴 (cloud_cover 0.10), capped the painted clouds at 41%
		// opacity — the painting was still being drawn, just washed out to a
		// faint haze, which reads as "there are no clouds".
		//
		// Weather now only ADDS on top: the painting always shows at
		// painted_base, and heavier cover thickens it toward full strength.
		// Overcast keeps its own thickening below.
		float pd = smoothstep(0.08, 0.55, pcov) * mix(painted_base, 1.0, cloud_cover);
		pd *= smoothstep(0.0, 0.10, up);
		col = mix(col, pcol, clamp(pd * painted_mix, 0.0, 0.97));
	}

	// Procedural layer, faded out as painted_mix rises.
	float proc_w = 1.0 - painted_mix;
	if (cloud_cover > 0.01 && proc_w > 0.001) {
		// Project onto a dome plane so clouds compress toward the horizon
		// instead of stretching to infinity.
		float t = 1.0 / max(up, 0.06);
		vec2 uv = dir.xz * t * 0.42;
		vec3 q = vec3(uv.x, uv.y, TIME * 0.008);
		float n = fbm(q * 1.1);
		// Detail layer drifting at a different rate stops the whole sheet from
		// sliding as one rigid texture.
		n = n * 0.72 + fbm(q * 3.3 + 17.0) * 0.28;

		float cover = mix(0.72, 0.16, cloud_cover);
		float density = smoothstep(cover, cover + 0.22, n);
		density *= smoothstep(0.0, 0.14, up);   // fade at the horizon
		col = mix(col, cl, clamp(density * (0.55 + 0.45 * cloud_cover) * proc_w, 0.0, 0.97));
	}

	// Overcast flattens everything toward a uniform grey sheet.
	vec3 flat_grey = mix(vec3(0.055, 0.060, 0.072), vec3(0.62, 0.64, 0.67), day_amount);
	col = mix(col, flat_grey, overcast * 0.55);

	COLOR = col;
}
