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
// 風（Wind V1）：實際風場來自 global uniform（Wind autoload 每幀上傳），
// 這裡的 wind_strength 是「這個材質的倍率」——舊 .tres 存的 null＝用預設 1.0。
// wind_dir 只在 global 風場尚未建立時當退路（例如編輯器裡單獨預覽材質）。
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.3);
uniform float wind_strength = 1.0;
uniform float wind_speed = 1.0;
uniform float flutter = 0.06;
uniform float wind_gain = 1.0;

#include "res://assets/shaders/wind_field.gdshaderinc"

// Wind V1.2：物種與正規化高度（Wind autoload 在節點進場時依 mesh 名稱與 AABB 設定）。
//   x＝物種索引（-1＝未接線 → 闊葉高木、高度由 lod_ref 估）、y＝mesh 局部頂高、z＝mesh 局部樞軸高（根部）
instance uniform vec4 wind_sp = vec4(-1.0, 0.0, 0.0, 0.0);

instance uniform vec4 lod_band = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec3 lod_ref = vec3(0.0, 1.5, 0.0);
// 色彩變體（同網格、每棵樹各自設）：leaf_tint＝反照率乘數、leaf_sat＝飽和度（<1＝櫻／楓的非極端飽和版）
// 預設值見 tools/village_v2_veg_lib.gd COLOR_PRESETS（mature／young／yellow／deep／shade／muted）；樹皮不受影響。
instance uniform vec3 leaf_tint = vec3(1.0, 1.0, 1.0);
instance uniform float leaf_sat = 1.0;

varying float v_lod_d;
// 除錯熱圖（gw_ctrl.z==1）：vertex() 把位移長度寫進 COLOR.r（不另開 varying——葉卡／草的 overdraw 很重，多一個插值器有成本）

vec3 veg_s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 veg_l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

float veg_ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// 世界向量 → 模型局部向量。
// 不用 inverse(MODEL_MATRIX)：植被／草叢的實例都是「旋轉＋等比縮放＋平移」，
// 轉置 3x3 就是旋轉的逆（差一個 scale²，等於讓大棵的樹擺幅大一點，視覺上更合理）。
// 逐頂點 mat4 反矩陣是風 V1 第一版 +2–3 ms GPU 的主因；這裡換成 9 次乘加。
vec3 veg_to_local(vec3 v, mat4 m) {
	return vec3(dot(v, m[0].xyz), dot(v, m[1].xyz), dot(v, m[2].xyz));
}

// Wind V1.2：高度加權彎曲＋分層二次運動（回傳世界空間位移；呼叫端轉回局部）。
//
// 三層（同一個驅動力，wf_drive 一次算出主幹與樹冠；與 Wind.sample_field 同一個量）：
//   1. 主幹彎曲：bw＝pow(hn, tip_response)，hn＝mesh 局部高度 /（頂高−樞軸）——不是世界 Y；
//      根部 hn=0 → 0 位移（不脫根），樹梢最大。驅動力取樹冠高度的垂直剖面（整棵樹吃同一個風載）。
//      主幹只有很短的延遲（0.25×lag）＝慢、重。
//   2. 樹冠彈性：wf_drive 的 crown＝欠阻尼彈簧（物種 damping、sway_hz、lag）——陣風過後主幹開始回正時，
//      樹冠仍在擺、再過衝一下才停。只作用在 hn 上段 × 作者遮罩 UV2.x（低枝不會被高度單獨帶動）。
//   3. 葉片／細枝顫動：物種 flutter_hz，強度吃「該頂點高度」的剖面（樹頂亂流較強），權重 COLOR.a。
// 自然擺動：物種 sway_hz ＋不可通約的第二頻率，相位吃根部雜湊 → 相鄰樹不同步、不是單一正弦迴圈。
// 安全上限：總位移以 tanh 軟夾在物種 max_deform（× 實例縮放）內；長度保持：位移愈大樹梢略降（弧長近似）。
// V2 效能版（WIND_V2_PERF_REVIEW）：場量（風向、m、主幹／樹冠驅動力含行進陣風與樹冠彈簧）改從共用風場貼圖
//   gw_field 取樣（逐根部、每幀 GPU 重算，見 wind_field.gdshaderinc）——不再每頂點跑事件迴圈與查表。
//   場時間一律 gw_time（各材質的 wind_speed 只調本地擺動頻率；V2 之前把 wind_speed 乘進場時間，
//   wind_speed≠1 的竹子會錯開陣風時間軸、實際上吃不到行進陣風——一併修正）。
// 距離品質分級（d＝實例到主相機；陰影 pass 同值 → 影子同級，平滑混合不跳級）：
//   近（< 35 m）：完整——高度加權主幹、樹冠彈性、枝擺、葉片顫動。
//   中（35–50 m）：葉片顫動漸弱到 0（細節 < 1 px）；主幹／樹冠／枝擺完整。
//   遠（50–130 m）：主幹＋樹冠＋枝叢傾倒（慢、大尺度），沒有葉片顫動；100→130 m 漸弱
//     （130 m 處 1 px≈0.25 m@720p/70°，強陣風樹梢位移約 1 px；V2 之前 45→60 m 就整段靜止）。
//     220 m 版實測 forest_edge +3.6 ms、130 m 版 +2.3 ms（README）。
//   樹冠彈性在所有距離都保留（貼圖取樣成本與只取主幹相同）。
vec3 veg_wind(vec3 vtx, vec3 wp, mat4 model, vec2 uv2, float flut_w, vec3 nrm_w, float t, float gain, float d_cam) {
	vec3 root = model[3].xyz;
	float sc = length(model[1].xyz);
	// 物種與高度
	int sp = int(wind_sp.x + 0.5);
	float top = wind_sp.y;
	float piv = wind_sp.z;
	// 未接線（編輯器預覽、Wind 未啟動）：不做主幹彎曲，只留作者 UV2 階層的枝擺（＝V1 行為）。
	//   不能猜成高木——同一個 veg_bark 也用在四つ目垣／袖垣／蹲踞等庭園構件上。
	float wired = 1.0;
	if (wind_sp.x < -0.5) {
		sp = WF_SP_BROAD_TALL;
		top = max(lod_ref.y * 2.1, 1.0);
		piv = 0.0;
		wired = 0.0;
	}
	vec4 r0;
	vec4 r1;
	vec4 r2;
	wf_species(sp, r0, r1, r2);
	float stiff = r0.x;
	float bend_mult = r0.y;
	float tip_exp = r0.z;
	float lag = r0.w;
	float flut_hz = r1.y;
	float max_d = r1.z * sc;
	float crown_gain = r1.w;
	float sway_hz = r2.z;
	float h_loc = max(top - piv, 0.05);
	float hn = clamp((vtx.y - piv) / h_loc, 0.0, 1.0);
	float h_w = h_loc * sc;
	// 場（共用風場貼圖：方塊 0＝風向／m，物種方塊＝主幹／樹冠驅動力；env 線性 → 取樣後再乘）
	vec2 wd2;
	float fm;
	float trunk;
	float crown;
	wf_tex_tree(sp, root.xz, wd2, fm, trunk, crown);
	vec3 wd = vec3(wd2.x, 0.0, wd2.y);
	vec3 side = vec3(-wd2.y, 0.0, wd2.x);
	float env_c = wf_height_factor(0.7 * h_w) * wf_elev_factor(root.y)
		* wf_shelter(root.xz, root.y + 0.7 * h_w);
	trunk *= env_c;
	crown *= env_c;
	float ph_i = wf_hash(root.xz) * WF_TAU;
	float steady = env_c * gw_strength * fm;
	// 自然擺動：物種固有頻率、每棵樹自己的相位（根部雜湊）；順風 sin、橫風 cos（同一個角度 → 橢圓擺，
	// 不是平面來回）。疊在 front 波與行進陣風上 → 整體不是同步的單一正弦迴圈。
	float arg_n = t * WF_TAU * sway_hz + ph_i;
	float nat = sin(arg_n) * 0.12;
	float cross_ = cos(arg_n) * 0.07;
	// 主幹：每單位驅動力的樹梢位移（m）＝ K × bend_mult × (1 − 0.8 stiffness) × 樹高
	float amp = 0.0156 * bend_mult * (1.0 - 0.8 * stiff) * h_w * wired;
	float bw = pow(hn, tip_exp);
	float cm = smoothstep(0.3, 0.85, hn) * mix(0.35, 1.0, clamp(uv2.x, 0.0, 1.0));
	float d_main = amp * (bw * (trunk + steady * nat) + crown_gain * cm * (crown - trunk));
	vec3 off = wd * d_main + side * (amp * bw * steady * cross_);
	// 枝／葉叢層（作者階層權重 UV2.x）：沿用 V1 的枝擺，但驅動力換成樹冠彈簧響應（有延遲、有過衝）
	float w = clamp(uv2.x, 0.0, 1.0);
	float ph = uv2.y * WF_TAU;
	float sway_b = sin(t * 0.9 + ph + dot(root.xz, vec2(0.041, 0.033))) * 0.75;
	off += wd * (w * w) * gain * wind_strength * min(bend_mult, 1.0) * (0.05 * sway_b * steady + 0.06 * crown);
	// 葉片顫動：亂流隨樹內高度增強（樹冠頂 ×1.5；線性近似剖面，不做逐頂點 pow）；中距離漸弱、遠景沒有
	float fl_k = flut_w * (1.0 - smoothstep(35.0, 50.0, d_cam));
	if (fl_k > 0.0) {
		float turb = 1.0 + 0.5 * hn;
		off += nrm_w * fl_k * flutter * gain * crown * turb * gw_flutter * min(bend_mult, 1.0)
			* sin(t * WF_TAU * flut_hz + ph * 3.1 + wp.y * 1.3) * 0.5;
	}
	// 長度保持（弧長近似）＋安全上限
	float hv = max(wp.y - root.y, 0.3);
	off.y -= 0.5 * dot(off.xz, off.xz) / hv;
	return wf_soft_clamp(off, max_d);
}

// 遠景（V2 效能版）：同一個風場貼圖、同一組物種參數，只留大尺度運動——
//   主幹高度加權彎曲（pow(hn, tip_response)）＋樹冠彈性（crown−trunk）＋枝叢隨樹冠驅動力傾倒（UV2 階層權重）。
//   去掉：逐頂點自然擺動 sin／cos、枝擺 sin、葉片顫動、弧長修正、軟上限（遠景位移遠小於上限）。
//   與近景在 VEG_FAR_BEGIN–VEG_FAR_FULL 之間逐頂點混合（兩條都算）→ 沒有換檔跳動；風向、陣風時間與近景同一個場。
const float VEG_FAR_BEGIN = 50.0;
const float VEG_FAR_FULL = 65.0;
const float VEG_FADE_BEGIN = 100.0;
const float VEG_FAR_END = 130.0;
// 陰影 pass（正射影）裡超過這個距離的樹不加風：遠景影子的擺動小於陰影貼圖一格（forest_edge 實測 −0.4 ms）
const float VEG_SHADOW_WIND_END = 50.0;

vec3 veg_wind_far(vec3 vtx, mat4 model, vec2 uv2, float gain) {
	if (wind_sp.x < -0.5 || gw_species_n < 0.5) {
		return vec3(0.0);
	}
	int sp = int(wind_sp.x + 0.5);
	vec4 r0 = texelFetch(gw_species, ivec2(sp, 0), 0);
	vec4 r1 = texelFetch(gw_species, ivec2(sp, 1), 0);
	vec3 root = model[3].xyz;
	float sc = length(model[1].xyz);
	float h_loc = max(wind_sp.y - wind_sp.z, 0.05);
	float hn = clamp((vtx.y - wind_sp.z) / h_loc, 0.0, 1.0);
	float h_w = h_loc * sc;
	vec2 wd2;
	float fm;
	vec2 tc;
	wf_tex_tree(sp, root.xz, wd2, fm, tc.x, tc.y);
	tc *= wf_height_factor(0.7 * h_w) * wf_elev_factor(root.y);
	float amp = 0.0156 * r0.y * (1.0 - 0.8 * r0.x) * h_w;
	float w = clamp(uv2.x, 0.0, 1.0);
	float cm = smoothstep(0.3, 0.85, hn) * mix(0.35, 1.0, w);
	float dm = amp * (pow(hn, r0.z) * tc.x + r1.w * cm * (tc.y - tc.x))
		+ (w * w) * gain * wind_strength * min(r0.y, 1.0) * 0.06 * tc.y;
	return vec3(wd2.x, 0.0, wd2.y) * dm;
}

// 回傳 LOD 距離（主相機→樹參考點）；varying 只能在 vertex() 本體賦值，由呼叫端寫 v_lod_d（位移長度經 out wdisp 回傳）
float veg_vertex_common(inout vec3 vtx, vec3 nrm, vec2 uv2, float flut_w, mat4 model, mat4 cam_inv_view, float time, float gain, float ortho, out float wdisp) {
	float d = distance(cam_inv_view[3].xyz, (model * vec4(lod_ref, 1.0)).xyz);
	wdisp = 0.0;
	// 距離閘門（V2 效能版）：不再 60 m 外整段靜止；VEG_FADE_BEGIN→VEG_FAR_END 漸弱、之外跳過。
	// 每實例一致，不會有逐頂點分歧。
	if ((gw_strength > 0.0 || gw_ctrl.x * gw_ctrl.y > 0.001) && gain > 0.0 && d < VEG_FAR_END && wf_tex_ok()
			&& (ortho < 0.5 || d < VEG_SHADOW_WIND_END)) {
		float fade = 1.0 - smoothstep(VEG_FADE_BEGIN, VEG_FAR_END, d);
		float kf = smoothstep(VEG_FAR_BEGIN, VEG_FAR_FULL, d);
		vec3 off = vec3(0.0);
		if (kf < 1.0) {
			vec3 wp = (model * vec4(vtx, 1.0)).xyz;
			vec3 nw = vec3(0.0, 1.0, 0.0);
			if (flut_w > 0.0 && d < VEG_FAR_BEGIN) {
				nw = normalize((model * vec4(nrm, 0.0)).xyz);
			}
			off = veg_wind(vtx, wp, model, uv2, flut_w, nw, time * wind_speed, gain, d);
		}
		if (kf > 0.0) {
			off = mix(off, veg_wind_far(vtx, model, uv2, gain), kf);
		}
		off *= fade;
		wdisp = length(off);
		// 世界→局部：轉置 3×3 再除以 scale²（等比縮放實例的精確逆）
		vtx += veg_to_local(off, model) / max(dot(model[0].xyz, model[0].xyz), 1e-6);
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
