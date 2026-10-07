// 人間之里 V2 P9 R5 Macro Pilot 地面 overlay（gc_ground.gdshader 衍生；gc_ground 與 Pilot r10f 畫面不動）。
// 3–15 m 級の地面構圖用：草地そのものの色調を大きく変える 2 通道を追加（CUSTOM0）。
//   COLOR.r 碎石／COLOR.g 濃い草（grass 層×lush_tint）／COLOR.b 踏み固め土／COLOR.a 落葉・木屑（forest 層）
//   UV.x 濕泥／UV.y 卵石／CUSTOM0.x 枯れ草（grass 層を藁色に）／CUSTOM0.y 踏まれた草（grass 層を色抜き・土寄せ）
//   CUSTOM0.z 路の色の踏み広げ（street 層；P9 R5 Macro Expansion。Macro Pilot の網格は 0＝畫面不變）
//   UV2.x 濕潤（正＝暗く・艶／負＝乾いて白っぽい：軒下・作業場）／UV2.y 淡出
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.19;
uniform float gravel_tile = 0.55;
uniform vec3 gravel_tint = vec3(1.16, 1.11, 1.03);
uniform float gravel_contrast = 0.95;
uniform float gravel_sat = 0.4;
uniform float grass_tile = 0.8;
uniform vec3 lush_tint = vec3(0.55, 0.78, 0.40);
uniform float lush_contrast = 0.85;
uniform vec3 dry_tint = vec3(1.68, 1.47, 0.88);
uniform float dry_sat = 0.36;
uniform float dry_contrast = 0.85;
uniform vec3 worn_tint = vec3(0.95, 0.86, 0.62);
uniform float worn_sat = 0.25;
uniform float soil_tile = 2.11;
uniform vec3 soil_tint = vec3(1.12, 1.06, 0.95);   // 踏み固め：地の土より少し淡く
uniform float soil_nrm = 0.45;                      // 踏み固め：滑らか
uniform float litter_tile = 1.5;
uniform vec3 litter_tint = vec3(0.92, 0.88, 0.82);
uniform float mud_tile = 1.3;
uniform vec3 mud_tint = vec3(1.0, 1.0, 1.0);
uniform float pebble_tile = 1.9;
uniform vec3 pebble_tint = vec3(1.0, 1.0, 1.0);
uniform float alpha_gain = 1.25;
uniform float street_tile = 2.07;
uniform vec3 street_tint = vec3(1.0, 1.0, 1.0);

const float HB = 0.5;
const float HB_DEPTH = 0.2;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cus;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cus = CUSTOM0;
}

vec3 samp(int layer, vec2 p, float tile, vec2 dpx, vec2 dpy) {
	vec3 c = textureGrad(albedo_arr, vec3(p / tile, float(layer)), dpx / tile, dpy / tile).rgb;
	if (OUTPUT_IS_SRGB) {
		c = s2l(c);
	}
	return c;
}

vec4 nrh(int layer, vec2 p, float tile, vec2 dpx, vec2 dpy) {
	return textureGrad(nrh_arr, vec3(p / tile, float(layer)), dpx / tile, dpy / tile);
}

vec3 grade(vec3 c, float contrast, float sat, vec3 tint) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	c = mix(vec3(0.33), c, contrast);
	return max(c * tint, vec3(0.0));
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec4 nm = texture(noise_tex, p / 9.0 + vec2(0.31, 0.77));
	float nf = texture(noise_tex, p / 2.3 + vec2(0.53, 0.11)).b;
	float pert = (nm.g - 0.5) * 0.9 + (nf - 0.5) * 0.4;
	vec4 w4 = clamp(COLOR + pert * COLOR * (1.0 - COLOR) * 2.0, 0.0, 1.0);
	vec2 w2 = clamp(UV + pert * UV * (1.0 - UV) * 2.0, 0.0, 1.0);
	vec2 wc = clamp(cus.xy + pert * cus.xy * (1.0 - cus.xy) * 2.0, 0.0, 1.0);
	float wst = clamp(cus.z + pert * cus.z * (1.0 - cus.z) * 2.0, 0.0, 1.0);
	float cov = w4.r + w4.g + w4.b + w4.a + w2.x + w2.y + wc.x + wc.y + wst;
	vec4 ng = nrh(3, p, gravel_tile, dpx, dpy);
	vec4 nmo = nrh(0, p, grass_tile, dpx, dpy);
	vec4 ns = nrh(2, p, soil_tile, dpx, dpy);
	vec4 nl = nrh(6, p, litter_tile, dpx, dpy);
	vec4 nmd = nrh(4, p, mud_tile, dpx, dpy);
	vec4 npb = nrh(3, p, pebble_tile, dpx, dpy);
	vec4 nst = nrh(1, p, street_tile, dpx, dpy);
	// 高さ混合（各層の高さ＝重み＋テクスチャ高さ）：境界がテクスチャに沿って崩れる
	float h[9];
	h[0] = w4.r > 0.01 ? w4.r + ng.b * HB : -1.0;
	h[1] = w4.g > 0.01 ? w4.g + nmo.b * HB : -1.0;
	h[2] = w4.b > 0.01 ? w4.b + ns.b * HB : -1.0;
	h[3] = w4.a > 0.01 ? w4.a + nl.b * HB : -1.0;
	h[4] = w2.x > 0.01 ? w2.x + nmd.b * HB : -1.0;
	h[5] = w2.y > 0.01 ? w2.y + npb.b * HB : -1.0;
	h[6] = wc.x > 0.01 ? wc.x + nmo.b * HB : -1.0;
	h[7] = wc.y > 0.01 ? wc.y + (nmo.b * 0.5 + ns.b * 0.5) * HB : -1.0;
	h[8] = wst > 0.01 ? wst + nst.b * HB : -1.0;
	float smax = -1.0;
	for (int i = 0; i < 9; i++) {
		smax = max(smax, h[i]);
	}
	float b[9];
	float bsum = 0.0;
	for (int i = 0; i < 9; i++) {
		b[i] = h[i] > -0.5 ? max(h[i] - (smax - HB_DEPTH), 0.0) : 0.0;
		bsum += b[i];
	}
	if (bsum < 1e-4) {
		discard;
	}
	vec3 grass = samp(0, p, grass_tile, dpx, dpy);
	vec3 soil = samp(2, p, soil_tile, dpx, dpy);
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	float f = b[0] / bsum;
	alb += grade(samp(3, p, gravel_tile, dpx, dpy), gravel_contrast, gravel_sat, gravel_tint) * f;
	nxy += (ng.rg * 2.0 - 1.0) * 0.5 * f;
	rough += 0.9 * f;
	f = b[1] / bsum;
	alb += grade(grass, lush_contrast, 0.9, lush_tint) * f;
	nxy += (nmo.rg * 2.0 - 1.0) * 0.5 * f;
	rough += 0.95 * f;
	f = b[2] / bsum;
	alb += soil * soil_tint * f;
	nxy += (ns.rg * 2.0 - 1.0) * soil_nrm * f;
	rough += 0.9 * f;
	f = b[3] / bsum;
	alb += samp(6, p, litter_tile, dpx, dpy) * litter_tint * f;
	nxy += (nl.rg * 2.0 - 1.0) * 0.8 * f;
	rough += 0.95 * f;
	f = b[4] / bsum;
	alb += samp(4, p, mud_tile, dpx, dpy) * mud_tint * f;
	nxy += (nmd.rg * 2.0 - 1.0) * 0.6 * f;
	rough += 0.7 * f;
	f = b[5] / bsum;
	alb += grade(samp(3, p, pebble_tile, dpx, dpy), 1.1, 0.3, pebble_tint) * f;
	nxy += (npb.rg * 2.0 - 1.0) * 0.9 * f;
	rough += 0.85 * f;
	f = b[6] / bsum;
	alb += grade(grass, dry_contrast, dry_sat, dry_tint) * f;
	nxy += (nmo.rg * 2.0 - 1.0) * 0.5 * f;
	rough += 0.95 * f;
	f = b[7] / bsum;
	alb += mix(grade(grass, 0.8, worn_sat, worn_tint), soil, 0.35) * f;
	nxy += (mix(nmo.rg, ns.rg, 0.5) * 2.0 - 1.0) * 0.6 * f;
	rough += 0.92 * f;
	f = b[8] / bsum;
	alb += samp(1, p, street_tile, dpx, dpy) * street_tint * f;
	nxy += (nst.rg * 2.0 - 1.0) * 0.6 * f;
	rough += 0.9 * f;
	float wet = max(UV2.x, 0.0);
	float dust = max(-UV2.x, 0.0);
	alb *= mix(1.0, 0.5, wet);
	alb = mix(alb, alb * vec3(1.32, 1.28, 1.2) + vec3(0.012), dust);
	vec3 N = normalize(wnrm);
	vec3 nw = normalize(vec3(nxy.x, 0.0, -nxy.y) + N);
	vec3 lin_out = alb * ground_k;
	ALBEDO = OUTPUT_IS_SRGB ? l2s(lin_out) : lin_out;
	ROUGHNESS = clamp(rough * mix(1.0, 0.5, wet), 0.05, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float hb = (ns.b + nl.b + nmo.b) / 3.0;
	ALPHA = clamp(smoothstep(0.0, 1.0, cov * alpha_gain + (hb - 0.5) * 0.35 * cov), 0.0, 1.0) * UV2.y;
}
