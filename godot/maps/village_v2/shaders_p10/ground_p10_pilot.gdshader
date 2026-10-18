// 人間之里 V2 P10 R5a GROUND PILOT（由 tools/village_v2_ground_pilot_lib.gd 從封存 ground.gdshader 文字補丁產生，勿手改）。
// 補丁：田格段→田邊耕土斑、道路帶外緣侵蝕、田埂道中央草帶斷續化、ROUND 2 再生道（UV2.y ≥ 1）の区間別の使われ方。其餘逐字＝ground.gdshader。
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
// P10 R5a pilot 參數（預設值＝不改變舊行為，除 farm_soil 外）
uniform float farm_soil = 0.32;
uniform float edge_w = 0.0;
uniform float edge_irreg = 0.0;
uniform float edge_core = 0.35;
uniform float center_patch = 0.0;
// P10 R6b：參道石段範圍挖掉 ribbon 中央（沿路 s 範圍＋半寬）；預設關閉
uniform vec2 cut_s = vec2(0.0);
uniform float cut_hw = 0.0;

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
		// P10 R5a pilot：外緣侵蝕——沿路低頻寬度起伏（edge_irreg）＋沿路拉長的草舌（edge_w，取樣座標＝沿路 m／離緣 m）
		// ＋細鋸齒；深度上限＝半寬×edge_core；切口內 0.4 m 先混草（edge_soft），不是一刀從土切到草。
		if (cut_s.y > cut_s.x && UV.y > cut_s.x && UV.y < cut_s.y && xm < cut_hw) {
			discard;
		}
		// 2026-10-18 道路接觸修正：草舌不再 discard（discard 讓可見地面掉到下方 6–10 cm 的地形、與道路碰撞不符），
		// 改成在路面高度直接畫草（bite_in → 只剩草層）。外形、位置、雜訊與原本相同；cut_s 參道石段仍 discard（碰撞另行扣除）。
		bool bite_in = false;
		float edge_soft = 0.0;
		if (edge_w > 0.0 || edge_irreg > 0.0) {
			float from_edge = hw - xm;
			float n_lo = texture(noise_tex, p / 11.0 + vec2(0.13, 0.57)).r;
			float n_mid = texture(noise_tex, vec2(UV.y / 4.3, from_edge / 1.3) + vec2(0.71, 0.29 + sign(UV.x) * 0.37)).g;
			float bite = edge_irreg * smoothstep(0.30, 0.75, n_lo) + edge_w * (smoothstep(0.35, 0.80, n_mid) * 0.7 + (nf - 0.5) * 0.6);
			float cut = min(max(bite, 0.0), hw * edge_core);
			bite_in = from_edge < cut;
			edge_soft = bite_in ? 1.0 : 1.0 - smoothstep(0.0, 0.40, from_edge - cut);
		}
		float edge = smoothstep(shoulder_start, 1.0, ax + (nm.g - 0.5) * 0.30 + (nf - 0.5) * 0.14);
		w[road_layer] += 1.0 - edge;
		w[shoulder_layer] += edge;
		w[3] += edge_gravel * smoothstep(0.5, 0.95, ax) * smoothstep(0.45, 0.75, nf);
		w[0] += edge_soft * 0.9;
		float cpat = mix(1.0, smoothstep(0.42, 0.66, texture(noise_tex, vec2(UV.y / 7.0, 0.37 + UV.x * 0.02)).b), center_patch);
		w[0] += center_grass * cpat * (1.0 - smoothstep(0.16 + 0.12 * cpat, 0.30 + 0.16 * cpat, xm + (nf - 0.5) * 0.2));
		if (rut_offset > 0.0) {
			rut = rut_strength * exp(-(xm - rut_offset) * (xm - rut_offset) / 0.035);
		}
		rut += wear_center * (1.0 - smoothstep(0.25, 0.55, ax + (nm.b - 0.5) * 0.2)) * 0.5;
		// P10 R5a ROUND 2：再生した道（RoadBaseP10、UV2.y ≥ 1）＝区間ごとの使われ方 traffic＝UV2.y − 1（0 田の奥 … 1 村の出入口）。
		// 旧網格は UV2.y＝0 → 何も変わらない。
		if (UV2.y > 0.5) {
			float traffic = clamp(UV2.y - 1.0, 0.0, 1.0);
			float rx = xm - hw * 0.45;
			float rk = exp(-rx * rx / 0.03);
			rut += traffic * 0.6 * rk;
			w[0] *= 1.0 - clamp(traffic * 1.5 * rk, 0.0, 0.9);
			w[0] += (1.0 - traffic) * 0.6 * (1.0 - smoothstep(0.10, 0.30 + 0.15 * (1.0 - traffic), xm + (nf - 0.5) * 0.25));
			w[0] += (1.0 - traffic) * 0.55 * smoothstep(0.55, 0.95, ax + (nm.g - 0.5) * 0.45);
			w[3] += traffic * 0.35 * smoothstep(0.6, 0.95, ax) * smoothstep(0.4, 0.7, nf);
		}
		if (bite_in) {
			for (int bi = 1; bi < 7; bi++) {
				w[bi] = 0.0;
			}
			w[0] = 1.0;
			rut = 0.0;
		}
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
			// P10 R5a pilot：田格屬 P8（每塊田有自己的 WetMudBottom／畦）。地形 farm 權重只給不規則「田邊耕土」斑，
			// 不畫規則格（舊 24×16 m 程序田格在 P8 田外的路肩／田間／羽化帶露出＝第二套田格）。
			float fpatch = smoothstep(0.40, 0.72, nb.g * 0.65 + nm.r * 0.35);
			float fs = b.g * farm_soil;
			w[2] += fs * (0.35 + 0.65 * fpatch);
			w[4] += fs * 0.30 * fpatch * smoothstep(0.45, 0.8, nf);
			wet = max(wet, fs * 0.10 * fpatch);
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
