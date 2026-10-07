// 人間之里 V2 P9 R4 稗田邸庭園 地面（garden_kit）。重用 P7 地面材質 Texture2DArray（只讀，層序＝matlib.json ground.layers），
// 但以庭園尺度取樣：白砂利（gravel 層，0.42 m 一格 → 粒徑 1–3 cm、提亮降彩降對比＋砂紋）、苔（grass 層細取樣＋深綠低對比）、
// 踏み固め土（trodden 層）、其餘＝草（grass 層，與 P7 地形同 tile）。
// 頂點權重：COLOR.r 砂利、COLOR.g 苔、COLOR.b 土、COLOR.a 砂紋遮罩；UV2.x 濕潤、UV2.y 砂紋方向（弧度）。
// CUSTOM0＝環紋場（R4 r2）：x＝苔島／主景石外緣からの距離、y＝環紋範圍（0＝無）、zw＝外向き勾配。
//   範圍內＝同心の環紋（石を回る）、範圍外＝直線砂紋；境目は 1 本ぶん空けて直線が環にぶつかって止まる（枯山水の定石）。
// 交界：高度混合＋世界座標雜訊（不成直線），與 ground.gdshader 同法；P7 ground.gdshader 不改。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.19;
uniform float gravel_tile = 0.42;
uniform vec3 gravel_tint = vec3(1.42, 1.38, 1.30);
uniform float gravel_contrast = 0.3;
uniform float gravel_sat = 0.35;
uniform float rake_spacing = 0.16;
uniform float rake_depth = 1.0;
uniform float moss_tile = 0.7;
uniform vec3 moss_tint = vec3(0.40, 0.62, 0.30);
uniform float moss_contrast = 0.75;
uniform float soil_tile = 2.11;
uniform float grass_tile = 2.51;

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
varying vec4 ringf;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ringf = CUSTOM0;
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
	float wg = w4.r;
	float wm = w4.g;
	float ws = w4.b;
	float wgr = max(1.0 - wg - wm - ws, 0.0);
	// 高度混合
	vec4 ng = nrh(3, p, gravel_tile, dpx, dpy);
	vec4 nmo = nrh(0, p, moss_tile, dpx, dpy);
	vec4 ns = nrh(2, p, soil_tile, dpx, dpy);
	vec4 ngr = nrh(0, p, grass_tile, dpx, dpy);
	float sg = wg + ng.b * HB;
	float sm = wm + nmo.b * HB;
	float ss = ws + ns.b * HB;
	float sr = wgr + ngr.b * HB;
	float smax = max(max(sg, sm), max(ss, sr));
	float bg = max(sg - (smax - HB_DEPTH), 0.0) * step(0.01, wg);
	float bm = max(sm - (smax - HB_DEPTH), 0.0) * step(0.01, wm);
	float bs = max(ss - (smax - HB_DEPTH), 0.0) * step(0.01, ws);
	float br = max(sr - (smax - HB_DEPTH), 0.0) * step(0.01, wgr);
	float bsum = max(bg + bm + bs + br, 1e-5);
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	// 砂紋：沿 UV2.y 方向的平行溝（間距 rake_spacing），只在 COLOR.a 遮罩內
	float ang = UV2.y;
	vec2 rd = vec2(-sin(ang), cos(ang));
	float rk = dot(p, rd) / rake_spacing + (nf - 0.5) * 0.08;
	float rw = sin(rk * 6.28318);
	float rake = w4.a;
	// 環紋：範圍內は距離場の等値線（外向き勾配で溝の法線）、範圍の外 1 本ぶんは平ら（直線がここで止まる）
	float rr = ringf.y;
	if (rr > 0.0 && ringf.x > -0.05) {
		float dd = max(ringf.x, 0.0);
		vec2 g = normalize(ringf.zw + vec2(1e-5));
		float ring_on = 1.0 - smoothstep(rr - 0.03, rr + 0.02, dd);
		float gap = smoothstep(rr - 0.02, rr + 0.04, dd) * (1.0 - smoothstep(rr + 0.1, rr + 0.2, dd));
		float rwr = sin((dd / rake_spacing + 0.25 + (nf - 0.5) * 0.18) * 6.28318);
		rw = mix(rw, rwr, ring_on);
		rd = normalize(mix(rd, g, ring_on));
		rake *= 1.0 - gap * 0.9;
	}
	if (bg > 0.0) {
		vec3 c = grade(samp(3, p, gravel_tile, dpx, dpy), gravel_contrast, gravel_sat, gravel_tint);
		c *= 1.0 - rake * rake_depth * 0.3 * (0.5 - 0.5 * rw);
		float f = bg / bsum;
		alb += c * f;
		nxy += ((ng.rg * 2.0 - 1.0) * 0.3 + rd * rw * rake * rake_depth * 0.6) * f;
		rough += 0.9 * f;
	}
	if (bm > 0.0) {
		vec3 c = grade(samp(0, p, moss_tile, dpx, dpy), moss_contrast, 0.85, moss_tint);
		float f = bm / bsum;
		alb += c * f;
		nxy += (nmo.rg * 2.0 - 1.0) * 0.5 * f;
		rough += 0.95 * f;
	}
	if (bs > 0.0) {
		vec3 c = samp(2, p, soil_tile, dpx, dpy);
		float f = bs / bsum;
		alb += c * f;
		nxy += (ns.rg * 2.0 - 1.0) * 0.8 * f;
		rough += 0.9 * f;
	}
	if (br > 0.0) {
		vec3 c = samp(0, p, grass_tile, dpx, dpy);
		float f = br / bsum;
		alb += c * f;
		nxy += (ngr.rg * 2.0 - 1.0) * 0.9 * f;
		rough += 0.95 * f;
	}
	float wet = UV2.x;
	alb *= mix(1.0, 0.62, wet);
	vec3 N = normalize(wnrm);
	vec3 nw = normalize(vec3(nxy.x, 0.0, -nxy.y) + N);
	vec3 lin_out = alb * ground_k;
	ALBEDO = OUTPUT_IS_SRGB ? l2s(lin_out) : lin_out;
	ROUGHNESS = clamp(rough * mix(1.0, 0.55, wet), 0.05, 1.0);
	SPECULAR = 0.33;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
