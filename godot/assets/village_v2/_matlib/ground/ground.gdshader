// 人間之里 V2 P7 地面材質（Ground Material / Transition）。
// 由 tools/build_village_v2_textures.py --ground 產生，勿手改；層序＝matlib.json ground.layers：
// 0 grass 1 street 2 trodden 3 gravel 4 mud 5 rock 6 forest
// mode 0：權重來自頂點（COLOR＝trodden,gravel,mud,rock；UV＝forest,farm；UV2＝wet,street；grass＝其餘）；
//         use_vertex_weights=false → 改用 fix_a／fix_b（院子等固定配比）。
// mode 1：道路帶——UV.x＝橫向（−1…1，相對半寬）、UV.y＝沿路 m、UV2.x＝半寬 m；路面層→路肩層＋車轍／中央草帶。
// 高度混合（nrh.b）＋世界座標雜訊擾動 → 土石交界不規則、不成直線；遠處雙尺度取樣壓平鋪重複感。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.19;
uniform int mode = 0;
uniform bool use_vertex_weights = true;
uniform vec4 fix_a = vec4(0.0);
uniform vec4 fix_b = vec4(0.0);
uniform int road_layer = 1;
uniform int shoulder_layer = 2;
uniform float shoulder_start = 0.8;
uniform float edge_gravel = 0.0;
uniform float center_grass = 0.0;
uniform float wear_center = 0.0;
uniform float rut_offset = 0.0;
uniform float rut_strength = 0.0;
uniform vec4 paddy = vec4(350.0, -140.0, 24.0, 16.0);
uniform float bund_w = 1.2;

const float TILE[7] = float[7](2.51, 2.07, 2.11, 2.16, 1.3, 2.0, 1.5);
const vec2 ROUGH[7] = vec2[7](vec2(0.82, 0.98), vec2(0.8, 0.96), vec2(0.82, 0.97), vec2(0.62, 0.92), vec2(0.45, 0.85), vec2(0.7, 0.95), vec2(0.85, 0.98));
const float NSTR[7] = float[7](0.9, 0.8, 0.8, 1.0, 0.7, 1.0, 0.8);
const float HB = 0.55;
const float HB_DEPTH = 0.22;

// 色彩空間：Forward+／Mobile 以線性空間算光，source_color 取樣已轉線性；Compatibility（OUTPUT_IS_SRGB）
// 以 sRGB 空間算光、取樣不轉換、ALBEDO 視為 sRGB 值 → 取樣先轉線性、以線性算完再編回 sRGB，
// 兩個渲染器的地面亮度才與 StandardMaterial3D（albedo_color／頂點色）的行為一致（P7 探針實測：
// 未處理時 Compatibility 下同一線性 ALBEDO 比 StandardMaterial3D 暗約 2.3 倍 sRGB 值）。
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

void fragment() {
	vec2 p = wpos.xz;
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec4 nb = texture(noise_tex, p / 61.0);
	vec4 nm = texture(noise_tex, p / 13.0 + vec2(0.31, 0.77));
	float nf = texture(noise_tex, p / 3.7 + vec2(0.53, 0.11)).b;
	float w[7] = float[7](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	float wet = 0.0;
	float rut = 0.0;
	if (mode == 1) {
		float ax = abs(UV.x);
		float hw = max(UV2.x, 0.5);
		float xm = ax * hw;
		float edge = smoothstep(shoulder_start, 1.0, ax + (nm.g - 0.5) * 0.30 + (nf - 0.5) * 0.14);
		w[road_layer] += 1.0 - edge;
		w[shoulder_layer] += edge;
		w[3] += edge_gravel * smoothstep(0.5, 0.95, ax) * smoothstep(0.45, 0.75, nf);
		w[0] += center_grass * (1.0 - smoothstep(0.22, 0.42, xm + (nf - 0.5) * 0.2));
		if (rut_offset > 0.0) {
			rut = rut_strength * exp(-(xm - rut_offset) * (xm - rut_offset) / 0.035);
		}
		rut += wear_center * (1.0 - smoothstep(0.25, 0.55, ax + (nm.b - 0.5) * 0.2)) * 0.5;
	} else {
		vec4 a = use_vertex_weights ? COLOR : fix_a;
		vec4 b = use_vertex_weights ? vec4(UV.x, UV.y, UV2.x, UV2.y) : fix_b;
		float pert = (nm.g - 0.5) * 1.1 + (nf - 0.5) * 0.45;
		a = clamp(a + pert * a * (1.0 - a) * 2.2, 0.0, 1.0);
		b.r = clamp(b.r + pert * b.r * (1.0 - b.r) * 2.2, 0.0, 1.0);
		b.a = clamp(b.a + pert * b.a * (1.0 - b.a) * 2.2, 0.0, 1.0);
		w[2] = a.r;
		w[3] = a.g;
		w[4] = a.b;
		w[5] = a.a;
		w[6] = b.r;
		w[1] = b.a;
		wet = b.b;
		if (b.g > 0.001) {
			// 田（P7 底色；水面／稻作屬 P8）：田面＝草（秧苗綠）＋泥（高度混合落在低處），畦＝踏み固め土。
			// 畦寬 = bund_w（P2 灰模頂點色以 2 m 網格取樣，實際讀成約 2 m 寬帶）→ 這裡加寬 0.6 m、
			// 並讓畦幾乎全是土（草不再從畦中長出），俯視網格與灰模同等可讀（r3 俯視審圖：網格變弱）。
			vec2 q = mod(p - paddy.xy, paddy.zw);
			float bd = min(min(q.x, paddy.z - q.x), min(q.y, paddy.w - q.y));
			float bh = bund_w * 0.5 + 0.3;
			float bund = 1.0 - smoothstep(bh - 0.12, bh + 0.12, bd + (nf - 0.5) * 0.14);
			w[4] += b.g * (1.0 - bund) * 0.35;
			w[2] += b.g * bund * 1.6;
			wet = max(wet, b.g * (1.0 - bund) * 0.12);
		}
	}
	float s = 0.0;
	for (int i = 1; i < 7; i++) {
		s += w[i];
	}
	w[0] += max(1.0 - s, 0.0);
	vec4 nv[7];
	float sc[7];
	float smax = -10.0;
	for (int i = 0; i < 7; i++) {
		sc[i] = -10.0;
		nv[i] = vec4(0.5, 0.5, 0.5, 0.0);
		if (w[i] > 0.015) {
			vec2 uv = p / TILE[i];
			nv[i] = textureGrad(nrh_arr, vec3(uv, float(i)), dpx / TILE[i], dpy / TILE[i]);
			sc[i] = w[i] + nv[i].b * HB;
			smax = max(smax, sc[i]);
		}
	}
	float bw[7];
	float bsum = 0.0;
	for (int i = 0; i < 7; i++) {
		bw[i] = max(sc[i] - (smax - HB_DEPTH), 0.0);
		bsum += bw[i];
	}
	bsum = max(bsum, 1e-5);
	float fd = smoothstep(14.0, 55.0, length(wpos - CAMERA_POSITION_WORLD));
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	for (int i = 0; i < 7; i++) {
		if (bw[i] > 0.0) {
			float f = bw[i] / bsum;
			vec2 uv = p / TILE[i];
			vec3 c = textureGrad(albedo_arr, vec3(uv, float(i)), dpx / TILE[i], dpy / TILE[i]).rgb;
			if (OUTPUT_IS_SRGB) {
				c = s2l(c);
			}
			if (fd > 0.0) {
				vec2 uv2 = uv * 0.29 + vec2(0.37, 0.61);
				vec3 c2 = textureGrad(albedo_arr, vec3(uv2, float(i)), dpx / TILE[i] * 0.29, dpy / TILE[i] * 0.29).rgb;
				if (OUTPUT_IS_SRGB) {
					c2 = s2l(c2);
				}
				c = mix(c, (c + c2) * 0.5, fd);
			}
			alb += c * f;
			nxy += (nv[i].rg * 2.0 - 1.0) * NSTR[i] * f;
			rough += mix(ROUGH[i].x, ROUGH[i].y, clamp(0.5 + (nf - 0.5) * 0.8, 0.0, 1.0)) * f;
		}
	}
	float g0 = bw[0] / bsum;
	alb *= mix(0.9, 1.09, nb.r) * (1.0 - rut * 0.22);
	alb = mix(alb, alb * vec3(1.09, 1.03, 0.84), g0 * smoothstep(0.55, 0.85, nb.a) * 0.55);
	alb *= mix(1.0, 0.6, wet);
	vec3 N = normalize(wnrm);
	vec3 nw = normalize(vec3(nxy.x, 0.0, -nxy.y) + N);
	nw = normalize(mix(nw, N, clamp(rut * 0.6, 0.0, 1.0)));
	vec3 lin_out = alb * ground_k;
	ALBEDO = OUTPUT_IS_SRGB ? l2s(lin_out) : lin_out;
	ROUGHNESS = clamp(rough * mix(1.0, 0.5, wet) * (1.0 - rut * 0.25), 0.05, 1.0);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
