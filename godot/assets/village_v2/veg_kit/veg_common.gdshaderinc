// 人間之里 V2 P9 R1：植被庫共用 shader 片段（veg_leaf.gdshader／veg_bark.gdshader include）。
// 頂點資料由 godot/assets/blender/village_v2/build_veg_kit.py 產生，不需要額外貼圖：
//   UV        ＝ 樹皮：沿枝 UV（1.2 m 一格）；葉卡：atlas UV
//   UV2       ＝ (階層風權重 0–1, 相位 0–1)：樹幹≈0（幾乎不動）→ 大枝弱 → 小枝中 → 葉叢強
//   COLOR.rgb ＝ 反照率乘數（叢內 AO、下層略暗、lobe 間克制色差、根部苔色）
//   COLOR.a   ＝ 葉卡內離附著點距離 0–1（葉片抖動權重；樹皮＝0）
// 風（Wind-ready）：wind_strength 預設 0＝靜止（審圖截圖可重現）；之後 Global Wind Manager 統一設
//   wind_dir／wind_strength／wind_speed／flutter 即可，不必改網格。
// LOD 換檔：Godot visibility range 只有 alpha 淡出（走透明管線、排序會亂），改用逐像素抖動交叉：
//   instance uniform lod_band＝(begin, end, begin 交叉寬, end 交叉寬)；begin／end＝0 表示該端不換檔。
//   lod_ref＝樹局部參考點（各級共用）。本級在 begin−寬/2 → begin 淡入、end → end＋寬/2 淡出（重疊交叉，見 veg_lod_reject）；
//   同一換檔距離兩側的級用同一寬度 → 帶內聯集覆蓋率 ≥ 100 %，不破洞、不變薄。
//   距離一律量主相機（陰影 pass 也一樣 → 影子跟著同一級換）。節點 visibility_range 只做粗剔除。
// 色彩空間：比照 _matlib/ground/ground.gdshader——Compatibility（OUTPUT_IS_SRGB）下取樣轉線性算完再編回。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float albedo_mul = 1.0;
uniform float normal_depth = 1.0;
uniform float roughness = 0.9;
uniform float specular = 0.3;
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.3);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.0;
uniform float flutter = 0.06;

instance uniform vec4 lod_band = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec3 lod_ref = vec3(0.0, 1.5, 0.0);
// 色彩變體（同網格、每棵樹各自設）：leaf_tint＝反照率乘數、leaf_sat＝飽和度（<1＝櫻／楓的非極端飽和版）
// 預設值見 tools/village_v2_veg_lib.gd COLOR_PRESETS（mature／young／yellow／deep／shade／muted）；樹皮不受影響。
instance uniform vec3 leaf_tint = vec3(1.0, 1.0, 1.0);
instance uniform float leaf_sat = 1.0;

varying float v_lod_d;

vec3 veg_s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 veg_l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

float veg_ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// 回傳世界空間位移（呼叫端轉回局部）
vec3 veg_wind(vec3 wp, vec2 uv2, float flut_w, vec3 nrm_w, float t) {
	float w = uv2.x;
	float ph = uv2.y * 6.2831853;
	vec3 wd = normalize(vec3(wind_dir.x, 0.0, wind_dir.z) + vec3(1e-4, 0.0, 0.0));
	float sway = sin(t * 0.9 + ph + dot(wp.xz, vec2(0.031, 0.027))) * 0.6 + sin(t * 2.1 + ph * 1.7) * 0.25 + 0.35;
	vec3 off = wd * (w * w) * wind_strength * sway;
	off.y -= length(off) * 0.25 * w;
	off += nrm_w * flut_w * flutter * wind_strength * sin(t * 7.3 + ph * 3.1 + wp.y * 1.3);
	return off;
}

// 回傳 LOD 距離（主相機→樹參考點）；varying 只能在 vertex() 本體賦值，由呼叫端寫 v_lod_d
float veg_vertex_common(inout vec3 vtx, vec3 nrm, vec2 uv2, float flut_w, mat4 model, mat4 cam_inv_view, float time) {
	float d = distance(cam_inv_view[3].xyz, (model * vec4(lod_ref, 1.0)).xyz);
	if (wind_strength > 0.0) {
		vec3 wp = (model * vec4(vtx, 1.0)).xyz;
		vec3 nw = normalize((model * vec4(nrm, 0.0)).xyz);
		vec3 off = veg_wind(wp, uv2, flut_w, nw, time * wind_speed);
		vtx += (inverse(model) * vec4(off, 0.0)).xyz;
	}
	return d;
}

// true＝這個像素不屬於本級（呼叫端 discard）
bool veg_lod_reject(vec2 fragcoord) {
	float d = v_lod_d;
	float h = veg_ign(fragcoord);
	// 重疊交叉（不是互補）：進來的級在換檔距離 s 之前 hb 內從 0 長到 100 %，出去的級在 s 之後 hb 內從 100 % 退到 0；
	// 兩級用互補的雜湊區段（進＝h ≥ 1−k_in、出＝h < k_out）→ 聯集覆蓋率＝min(1, k_in + k_out) ≥ 100 %，
	// 樹冠在交叉帶內不會變薄（兩級葉卡位置不同時，互補抖動會只剩半套 → 鬼影）。代價：帶內短暫重疊繪製。
	if (lod_band.x > 0.0) {
		float hb = max(lod_band.z, 0.01) * 0.5;
		float k_in = clamp((d - (lod_band.x - hb)) / hb, 0.0, 1.0);
		if (h < 1.0 - k_in) {
			return true;
		}
	}
	if (lod_band.y > 0.0) {
		float he = max(lod_band.w, 0.01) * 0.5;
		float k_out = clamp((lod_band.y + he - d) / he, 0.0, 1.0);
		if (h >= k_out) {
			return true;
		}
	}
	return false;
}
