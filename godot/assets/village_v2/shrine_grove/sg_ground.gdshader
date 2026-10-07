// 人間之里 V2 P9 R4-2 神社周邊（鎮守之森／參道）地面 overlay。重用 P7 地面材質 Texture2DArray（只讀，層序＝matlib.json
// ground.layers：0 grass 1 street 2 trodden 3 gravel 4 mud 5 rock 6 forest）。
// 頂點權重：COLOR.r 玉砂利（gravel 細取樣、提亮）、COLOR.g 苔（grass 層細取樣＋深綠）、COLOR.b 踏み固め土、COLOR.a 落葉（forest 層）；
// 其餘＝草（與 P7 地形同 tile）。UV2.x 濕潤、UV2.y 外緣淡出（1＝內、0＝外緣；以雜湊 dither discard，與 P7 地形接縫不成直線）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.19;
uniform float gravel_tile = 0.42;
uniform vec3 gravel_tint = vec3(1.26, 1.14, 0.94);
uniform float gravel_contrast = 0.7;
uniform float gravel_sat = 0.6;
uniform float moss_tile = 0.8;
uniform vec3 moss_tint = vec3(0.42, 0.62, 0.3);
uniform float moss_contrast = 0.75;
uniform float soil_tile = 2.11;
uniform float litter_tile = 1.5;
uniform vec3 litter_tint = vec3(0.92, 0.88, 0.82);
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

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = wpos.xz;
	// 外緣淡出：雜湊＋低頻雜訊 dither（不是直線接縫）
	float nfade = texture(noise_tex, p / 5.0 + vec2(0.13, 0.41)).g;
	if (UV2.y < 0.999 && UV2.y + (nfade - 0.5) * 0.35 < hash12(floor(p * 18.0))) {
		discard;
	}
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec4 nm = texture(noise_tex, p / 9.0 + vec2(0.31, 0.77));
	float nf = texture(noise_tex, p / 2.3 + vec2(0.53, 0.11)).b;
	float pert = (nm.g - 0.5) * 0.9 + (nf - 0.5) * 0.4;
	vec4 w4 = clamp(COLOR + pert * COLOR * (1.0 - COLOR) * 2.0, 0.0, 1.0);
	float wg = w4.r;
	float wm = w4.g;
	float ws = w4.b;
	float wl = w4.a;
	float wgr = max(1.0 - wg - wm - ws - wl, 0.0);
	vec4 ng = nrh(3, p, gravel_tile, dpx, dpy);
	vec4 nmo = nrh(0, p, moss_tile, dpx, dpy);
	vec4 ns = nrh(2, p, soil_tile, dpx, dpy);
	vec4 nl = nrh(6, p, litter_tile, dpx, dpy);
	vec4 ngr = nrh(0, p, grass_tile, dpx, dpy);
	float sg = wg + ng.b * HB;
	float sm = wm + nmo.b * HB;
	float ss = ws + ns.b * HB;
	float sl = wl + nl.b * HB;
	float sr = wgr + ngr.b * HB;
	float smax = max(max(max(sg, sm), max(ss, sr)), sl);
	float bg = max(sg - (smax - HB_DEPTH), 0.0) * step(0.01, wg);
	float bm = max(sm - (smax - HB_DEPTH), 0.0) * step(0.01, wm);
	float bs = max(ss - (smax - HB_DEPTH), 0.0) * step(0.01, ws);
	float bl = max(sl - (smax - HB_DEPTH), 0.0) * step(0.01, wl);
	float br = max(sr - (smax - HB_DEPTH), 0.0) * step(0.01, wgr);
	float bsum = max(bg + bm + bs + bl + br, 1e-5);
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	if (bg > 0.0) {
		float f = bg / bsum;
		alb += grade(samp(3, p, gravel_tile, dpx, dpy), gravel_contrast, gravel_sat, gravel_tint) * f;
		nxy += (ng.rg * 2.0 - 1.0) * 0.5 * f;
		rough += 0.9 * f;
	}
	if (bm > 0.0) {
		float f = bm / bsum;
		alb += grade(samp(0, p, moss_tile, dpx, dpy), moss_contrast, 0.85, moss_tint) * f;
		nxy += (nmo.rg * 2.0 - 1.0) * 0.5 * f;
		rough += 0.95 * f;
	}
	if (bs > 0.0) {
		float f = bs / bsum;
		alb += samp(2, p, soil_tile, dpx, dpy) * f;
		nxy += (ns.rg * 2.0 - 1.0) * 0.8 * f;
		rough += 0.9 * f;
	}
	if (bl > 0.0) {
		float f = bl / bsum;
		alb += samp(6, p, litter_tile, dpx, dpy) * litter_tint * f;
		nxy += (nl.rg * 2.0 - 1.0) * 0.8 * f;
		rough += 0.95 * f;
	}
	if (br > 0.0) {
		float f = br / bsum;
		alb += samp(0, p, grass_tile, dpx, dpy) * f;
		nxy += (ngr.rg * 2.0 - 1.0) * 0.9 * f;
		rough += 0.95 * f;
	}
	float wet = UV2.x;
	alb *= mix(1.0, 0.66, wet);
	vec3 N = normalize(wnrm);
	vec3 nw = normalize(vec3(nxy.x, 0.0, -nxy.y) + N);
	vec3 lin_out = alb * ground_k;
	ALBEDO = OUTPUT_IS_SRGB ? l2s(lin_out) : lin_out;
	ROUGHNESS = clamp(rough * mix(1.0, 0.6, wet), 0.05, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
