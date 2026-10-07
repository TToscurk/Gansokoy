// 人間之里 V2 P9 R5 Groundcover 地面 overlay（由 R4-2 sg_ground.gdshader 衍生；原檔封存不動）。
// 重用 P7 地面材質 Texture2DArray（只讀，層序＝matlib.json ground.layers：0 grass 1 street 2 trodden 3 gravel 4 mud 5 rock 6 forest）。
// 頂點權重：COLOR.r 碎石、COLOR.g 苔／濃い草（grass 層＋moss_tint）、COLOR.b 踏み固め土、COLOR.a 落葉・枯れ草（forest 層）。
// 與 sg_ground 的差異：沒有「其餘＝草」——不透明度＝權重和×UV2.y（alpha 混合到 P1／P7 地形上），
// 所以權重低的地方是透明（不把草 tile 蓋到林床或裸土上），外緣也不用 dither（不出像素顆粒）。UV2.x 濕潤。
// R5-1 rework：UV.x 濕泥／腐植（mud 層）、UV.y 卵石（gravel 層・粗 tile）。兩通道權重 0 時不參與高度混合（舊區畫面不變）。
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
uniform float moss_tile = 0.8;
uniform vec3 moss_tint = vec3(0.42, 0.62, 0.3);
uniform float moss_contrast = 0.75;
uniform float soil_tile = 2.11;
uniform float litter_tile = 1.5;
uniform vec3 litter_tint = vec3(0.92, 0.88, 0.82);
uniform float alpha_gain = 1.25;
uniform float mud_tile = 1.3;
uniform vec3 mud_tint = vec3(1.0, 1.0, 1.0);
uniform float pebble_tile = 1.9;
uniform vec3 pebble_tint = vec3(1.0, 1.0, 1.0);
uniform float pebble_contrast = 1.0;
uniform float litter_rot = 0.0;   // 落葉を回轉した UV で取る（地形林床層の tile 格子と揃わない）；0＝舊區と同一

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	float cov = w4.r + w4.g + w4.b + w4.a + w2.x + w2.y;
	vec4 ng = nrh(3, p, gravel_tile, dpx, dpy);
	vec4 nmo = nrh(0, p, moss_tile, dpx, dpy);
	vec4 ns = nrh(2, p, soil_tile, dpx, dpy);
	mat2 lr = mat2(vec2(cos(litter_rot), sin(litter_rot)), vec2(-sin(litter_rot), cos(litter_rot)));
	vec2 pl = litter_rot == 0.0 ? p : lr * p;
	vec2 dlx = litter_rot == 0.0 ? dpx : lr * dpx;
	vec2 dly = litter_rot == 0.0 ? dpy : lr * dpy;
	vec4 nl = nrh(6, pl, litter_tile, dlx, dly);
	float sg = w4.r + ng.b * HB;
	float sm = w4.g + nmo.b * HB;
	float ss = w4.b + ns.b * HB;
	float sl = w4.a + nl.b * HB;
	float smax = max(max(sg, sm), max(ss, sl));
	vec4 nmd = nrh(4, p, mud_tile, dpx, dpy);
	vec4 npb = nrh(3, p, pebble_tile, dpx, dpy);
	float smd = w2.x > 0.01 ? w2.x + nmd.b * HB : -1.0;
	float spb = w2.y > 0.01 ? w2.y + npb.b * HB : -1.0;
	smax = max(smax, max(smd, spb));
	float bg = max(sg - (smax - HB_DEPTH), 0.0) * step(0.01, w4.r);
	float bm = max(sm - (smax - HB_DEPTH), 0.0) * step(0.01, w4.g);
	float bs = max(ss - (smax - HB_DEPTH), 0.0) * step(0.01, w4.b);
	float bl = max(sl - (smax - HB_DEPTH), 0.0) * step(0.01, w4.a);
	float bmd = max(smd - (smax - HB_DEPTH), 0.0) * step(0.01, w2.x);
	float bpb = max(spb - (smax - HB_DEPTH), 0.0) * step(0.01, w2.y);
	float bsum = bg + bm + bs + bl + bmd + bpb;
	if (bsum < 1e-4) {
		discard;
	}
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	float f = bg / bsum;
	alb += grade(samp(3, p, gravel_tile, dpx, dpy), gravel_contrast, gravel_sat, gravel_tint) * f;
	nxy += (ng.rg * 2.0 - 1.0) * 0.5 * f;
	rough += 0.9 * f;
	f = bm / bsum;
	alb += grade(samp(0, p, moss_tile, dpx, dpy), moss_contrast, 0.85, moss_tint) * f;
	nxy += (nmo.rg * 2.0 - 1.0) * 0.5 * f;
	rough += 0.95 * f;
	f = bs / bsum;
	alb += samp(2, p, soil_tile, dpx, dpy) * f;
	nxy += (ns.rg * 2.0 - 1.0) * 0.8 * f;
	rough += 0.9 * f;
	f = bl / bsum;
	alb += samp(6, pl, litter_tile, dlx, dly) * litter_tint * f;
	nxy += (nl.rg * 2.0 - 1.0) * 0.8 * f;
	rough += 0.95 * f;
	if (bmd > 0.0) {
		f = bmd / bsum;
		alb += samp(4, p, mud_tile, dpx, dpy) * mud_tint * f;
		nxy += (nmd.rg * 2.0 - 1.0) * 0.6 * f;
		rough += 0.7 * f;
	}
	if (bpb > 0.0) {
		f = bpb / bsum;
		alb += grade(samp(3, p, pebble_tile, dpx, dpy), pebble_contrast, 0.8, pebble_tint) * f;
		nxy += (npb.rg * 2.0 - 1.0) * 0.9 * f;
		rough += 0.85 * f;
	}
	float wet = UV2.x;
	alb *= mix(1.0, 0.62, wet);
	vec3 N = normalize(wnrm);
	vec3 nw = normalize(vec3(nxy.x, 0.0, -nxy.y) + N);
	vec3 lin_out = alb * ground_k;
	ALBEDO = OUTPUT_IS_SRGB ? l2s(lin_out) : lin_out;
	ROUGHNESS = clamp(rough * mix(1.0, 0.55, wet), 0.05, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 不透明度：權重和（高度混合後的邊緣隨 tile 的高度圖破碎，不是平滑的圓斑）
	float hb = (ns.b + nl.b + nmo.b) / 3.0;
	ALPHA = clamp(smoothstep(0.0, 1.0, cov * alpha_gain + (hb - 0.5) * 0.35 * cov), 0.0, 1.0) * UV2.y;
}
