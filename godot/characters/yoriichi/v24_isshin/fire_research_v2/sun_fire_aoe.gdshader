shader_type spatial;
// R16 日之呼吸「招式主特效」（AOE 視覺）共用火焰著色器：sun_fire_aoe.gd 用。原創程序化（只用專案自己的 fire_noise_v2.png）。
// shape 0＝新月（大型弧形火焰斬）：網格只有參數 (u 沿弧, v 繞截面)，位置在這裡依時間算：角度依刀路掃出、半徑放大、往前推進、表面起伏。
// shape 1＝旋流（往前噴射的火焰龍捲；R16 第一版灼骨，保留）：UV2.x＝第幾道螺旋火帶（＝bands 時是中心火芯），前緣依 jet 時間推進，整體持續旋轉。
// shape 2＝爆燃：UV2.x＝第幾道火舌，方向由 seed 決定（半球內，flat 壓扁＝貼地）。
// shape 3＝一般網格（龍頭、龍身）：頂點不動；UV.x＝沿身體的位置（龍身：0 尾 → 1 頭），burn 由尾往頭燒掉。
// shape 4＝分離的旋渦火焰（R16b 灼骨炎陽等）：UV2.x＝第幾道火焰；每一道的半徑、相位、轉速、角度長度、推進距離、粗細、出生時間、壽命都不同，
//          頭沿自己的螺旋走（繞局部 +Z 轉、往 +Z 減速推進、半徑往外散開），尾巴＝頭在較早時刻的位置 → 一段螺旋弧，彼此之間留空隙、不合成封閉外殼。
//          sw_spin＝0 且半徑很小時＝沿 +Z 的直線火焰（一閃的光帶、陽華突的突刺）。sw_fling＝其中這個比例的火焰後半段往外甩出（擴大範圍）。
// core＝1：同一網格的內層（截面縮小、溫度加高）＝金黃火芯；core＝0：外層橘紅火焰。
// style（R16b 第二輪；profile.aoe.style）：0＝R16 原樣（菲涅耳管狀光帶，舊 profile 回退用，一律不變）；
//   1＝風格化火焰：新月／旋渦的外緣長出一根根火舌（長短、粗細、後傾、擺動、分岔都不同；火舌根部併進火體，不是三角形），火體邊緣起伏、
//     撕裂時由外往內破成碎塊；顏色依位置：火芯白金→火體金黃→外焰橘紅→火舌尖端淡粉紅（每道火舌各自決定有沒有，跟著火舌形狀長，不描邊）；
//     不透明度依覆蓋（不靠菲涅耳，所以尖端看得見）、亮度上限壓低（粉紅不被泛光洗成白色）。爆燃的火舌改成彎曲、粗細不均的火舌。
// 淡粉紅（pink）：style 0＝R16b 第一輪的低頻斑塊做法；style 1＝火舌尖端（profile 可調 0–1）。
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform int shape = 0;
uniform int style = 0;
uniform float core = 0.0;
uniform float age = 0.0;
uniform float life = 1.0;
uniform float fade = 1.0;
uniform float gain = 1.0;
uniform float seed = 0.0;
uniform float tear = 0.5;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col_core : source_color = vec4(1.0, 0.93, 0.66, 1.0);
uniform vec4 col_gold : source_color = vec4(1.0, 0.68, 0.16, 1.0);
uniform vec4 col_orange : source_color = vec4(1.0, 0.36, 0.05, 1.0);
uniform vec4 col_red : source_color = vec4(0.62, 0.07, 0.02, 1.0);
// 淡粉紅末端
uniform float pink = 0.0;
// R16b hot（profile.aoe.hot；1＝R16 原樣）：< 1 時白金核心只留最熱的一小段、整體亮度上限降低（避免大片白光）
uniform float hot = 1.0;
uniform vec4 col_pink : source_color = vec4(1.0, 0.63, 0.67, 1.0);
// style 1 的火舌尖端粉紅（比 col_pink 飽和一點、不發亮：在橘紅旁邊才分得出來）
uniform vec4 col_tip_pink : source_color = vec4(1.0, 0.7, 0.8, 1.0);
// style 1 火舌：間距（m）、長度（火舌區的比例）、後傾、分岔比例、有粉紅尖端的火舌比例、火體所佔截面比例
uniform float t_space = 0.3;
uniform float t_len = 1.0;
uniform float t_lean = 0.6;
uniform float t_fork = 0.3;
uniform float t_pinksel = 0.55;
uniform float t_body = 0.42;
// 新月
uniform float a0 = 0.0;
uniform float a1 = 3.0;
uniform float reveal_s = 0.15;
uniform float r0 = 1.2;
uniform float r1 = 2.4;
uniform float width = 0.6;
uniform float thick = 0.3;
uniform vec3 travel = vec3(0.0);
// 旋流
uniform float v_len = 7.0;
uniform float jet = 0.45;
uniform float vr0 = 0.4;
uniform float vr1 = 1.7;
uniform float turns = 2.5;
uniform float spin = 2.2;
uniform float bands = 4.0;
// 爆燃（flatten > 0＝貼地壓扁）
uniform float b_size = 1.6;
uniform float spread = 1.0;
uniform float flatten = 0.0;
uniform float erode = 0.0;
uniform float tongues = 14.0;
// 網格（龍）
uniform float burn = 0.0;
uniform float reveal = 1.0;
uniform float form_shade = 0.0;
uniform float flow = 1.2;
uniform float body_len = 6.0;
uniform float sway = 0.0;
// 分離的旋渦火焰（shape 4）
uniform float sw_n = 6.0;
uniform float sw_r0 = 0.45;
uniform float sw_r1 = 1.5;
uniform float sw_len = 3.2;
uniform float sw_jet = 0.35;
uniform float sw_spin = 1.5;
uniform float sw_span = 2.0;
uniform float sw_w = 0.3;
uniform float sw_stag = 0.12;
uniform float sw_var = 1.0;
uniform float sw_slow = 0.35;
uniform float sw_fling = 0.0;
// R16c（opt-in，預設＝原樣）：旋渦火焰截面 sw_th＝窄邊／寬邊；sw_band 1＝寬邊沿軸向（包住身體的火焰帶，從側面看是正面），火舌朝 +Z（推進方向）；
// heat_mul＝style 1 的溫度倍率（< 1 偏橘紅＝外焰層，> 1 亮部多一點）
uniform float sw_instant = 0.0; // opt-in: complete sparse arcs from first frame, no tail growth
uniform float sw_th = 0.55;
uniform float sw_band = 0.0;
uniform float heat_mul = 1.0;
// R16f opt-in enrichment: old wreath and every other profile retain zero enrichment.
uniform float wreath_enrich = 0.0;
uniform float wreath_speed = 1.0;
// R16g 灼骨炎陽「日輪渦」（shape 6，opt-in；其他 shape／profile 不經過）：星芒 → 白色日輪（燃燒外緣）→ 由中心打開成往內捲約兩圈的火焰渦（圈間留暗縫），
// 角色在渦心 → 高潮閃亮 → 撕成幾段捲鉤火焰往外散 → 侵蝕消失。ss_part 0＝cel 火焰片、1＝後面的柔光、2＝朝相機的星芒／日輪。
uniform int ss_part = 0;
uniform float ss_turns = 1.9;
uniform float ss_r_in = 0.8;
uniform float ss_r_out = 2.25;
uniform float ss_up = 0.92;
uniform float ss_w_in = 0.22;
uniform float ss_w_out = 0.56;
uniform float ss_z_in = 0.55;
uniform float ss_z_out = -0.45;
uniform float ss_spin = -2.8;
uniform float ss_th0 = 0.0;
uniform float ss_open0 = 0.08;
uniform float ss_open1 = 0.19;
uniform float ss_break = 0.5;
uniform float ss_flare = 0.18;
uniform float ss_ground = 0.0;
uniform float ss_gap = 0.16;
uniform float ss_flash = 2.6;
uniform vec4 ss_pale : source_color = vec4(1.0, 1.0, 0.44, 1.0);
uniform vec4 ss_yellow : source_color = vec4(1.0, 0.95, 0.24, 1.0);
uniform vec4 ss_orange : source_color = vec4(1.0, 0.41, 0.1, 1.0);
uniform vec4 ss_vermilion : source_color = vec4(0.93, 0.24, 0.094, 1.0);
uniform vec4 ss_deep : source_color = vec4(0.66, 0.14, 0.094, 1.0);
uniform vec4 ss_line : source_color = vec4(0.29, 0.09, 0.094, 1.0);

varying float v_u;
varying float v_v;
varying float v_k;
varying float v_band;
varying float v_edge;
varying float v_tip;
varying float v_sk;
varying vec3 v_obj;
varying float v_s;
varying float v_arc;
varying float v_w;
varying vec2 v_fq;

float h11(float x) { return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453); }
float nz(vec2 p) { return textureLod(noise_tex, p, 0.0).r; }

void vertex() {
	float t = age;
	v_k = clamp(t / max(life, 1e-3), 0.0, 1.0);
	v_sk = v_k;
	v_u = UV.x;
	v_v = UV.y;
	v_band = UV2.x;
	v_edge = 0.0;
	v_tip = 0.0;
	v_s = 0.5;
	v_arc = 0.0;
	float csc = core > 0.5 ? 0.42 : 1.0;
	if (shape == 0) {
		float u = UV.x;
		float ph = UV.y * TAU;
		float a = mix(a0, a1, u);
		float ke = 1.0 - pow(1.0 - v_k, 2.2);
		float R = mix(r0, r1, ke);
		float tp = pow(max(sin(3.14159 * u), 0.0), 0.55);
		float w = width * (0.65 + 0.5 * ke) * tp * csc;
		float h = thick * tp * csc * (0.8 + 0.4 * sin(u * 9.0 + seed));
		if (style == 1) {
			// 火體厚度沿弧起伏（大塊火體與細的地方）；兩端收尖但不是直線三角
			float lump = nz(vec2(u * 1.9 + seed * 0.17, 0.37 + seed * 0.05));
			w *= 0.72 + 0.56 * lump;
			h *= 0.6 + 0.6 * lump;
			tp = pow(max(sin(3.14159 * u), 0.0), 0.4);
		}
		vec3 rad = vec3(cos(a), sin(a), 0.0);
		vec3 n = normalize(rad * cos(ph) * h + vec3(0.0, 0.0, 1.0) * sin(ph) * w + vec3(1e-4));
		vec3 p = rad * (R + cos(ph) * w * 0.5) + vec3(0.0, 0.0, 1.0) * sin(ph) * h * 0.5;
		float d = nz(vec2(u * 2.7 + seed * 0.13, UV.y * 0.8 + t * 0.55));
		p += n * (d - 0.45) * (style == 1 ? 0.3 : 0.55) * w;
		p += travel * (1.0 - pow(1.0 - v_k, 1.7));
		VERTEX = p;
		NORMAL = n;
		v_edge = abs(cos(ph));
		v_tip = (1.0 - tp) * 0.95 + max(cos(ph), 0.0) * 0.55;
		v_s = 0.5 + 0.5 * cos(ph);
		v_arc = u * (a1 - a0) * r0;                  // 用起始半徑算：火焰放大時火舌一起變大，火舌編號不變（粉紅不閃）
	} else if (shape == 1) {
		float u = UV.x;
		float ph = UV.y * TAU;
		float fr = clamp(t / max(jet, 1e-3), 0.0, 1.0);
		fr = 1.0 - pow(1.0 - fr, 1.6);
		float z = u * v_len * fr;
		float rr = mix(vr0, vr1, pow(u, 0.7)) * (0.75 + 0.25 * fr) * (1.0 + 0.25 * v_k);
		if (UV2.x >= bands - 0.5) {
			float rc = rr * 0.36 * csc * (0.8 + 0.2 * sin(u * 22.0 - t * 15.0));
			VERTEX = vec3(cos(ph) * rc, sin(ph) * rc, z);
			NORMAL = normalize(vec3(cos(ph), sin(ph), 0.0));
		} else {
			float th = UV2.x / bands * TAU + turns * TAU * u * fr + spin * TAU * t + UV2.y * 0.6;
			vec3 er = vec3(cos(th), sin(th), 0.0);
			vec3 et = vec3(-sin(th), cos(th), 0.0);
			vec3 tg = normalize(et * TAU * rr * turns + vec3(0.0, 0.0, v_len * max(fr, 0.05)));
			vec3 wd = normalize(cross(er, tg));
			float tp = pow(max(sin(3.14159 * min(u * 1.15, 1.0)), 0.0), 0.5);
			float bw = rr * 0.62 * tp * csc;
			float bh = rr * 0.2 * tp * csc;
			vec3 n = normalize(wd * cos(ph) * bh + er * sin(ph) * bw + vec3(1e-4));
			vec3 p = er * rr + vec3(0.0, 0.0, z) + wd * cos(ph) * bw * 0.5 + er * sin(ph) * bh * 0.5;
			float d = nz(vec2(u * 3.1 + UV2.x * 0.31 + seed * 0.1, UV.y * 0.7 - t * 0.9));
			p += n * (d - 0.45) * 0.6 * bw;
			VERTEX = p;
			NORMAL = n;
			v_edge = abs(cos(ph));
			v_tip = (1.0 - tp) * 0.95 + max(sin(ph), 0.0) * 0.4;
		}
	} else if (shape == 2) {
		float k = UV2.x;
		float u = UV.x;
		float ph = UV.y * TAU;
		float az = h11(k * 1.7 + 0.3) * TAU;
		float el = acos(1.0 - spread * h11(k * 2.3 + 0.9));
		vec3 dir = normalize(vec3(sin(el) * cos(az), cos(el) * (1.0 - flatten), sin(el) * sin(az)));
		float lr = h11(k * 3.1 + 0.2);
		float ln = style == 1 ? b_size * (0.3 + 0.75 * lr * lr) : b_size * (0.45 + 0.45 * lr);
		float go = 1.0 - pow(1.0 - clamp(t / (0.22 + 0.15 * h11(k + 5.0)), 0.0, 1.0), 2.0);
		vec3 side = normalize(cross(dir, abs(dir.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 bin = cross(dir, side);
		float tp = pow(max(sin(3.14159 * min(u * 0.92 + 0.08, 1.0)), 0.0), 0.7) * (1.0 - 0.55 * u);
		float rad = ln * 0.34 * tp * csc * (1.0 + 0.5 * v_k);
		vec3 c = dir * ln * u * go + vec3(0.0, 1.0, 0.0) * u * u * 0.35 * v_k * b_size;
		if (style == 1) {
			// 彎曲的火舌：根部粗、中段膨、尖端細長（不是直線圓錐）；往上捲、往一側擺，長短差很多
			float bnd = (h11(k * 4.7 + 0.6) - 0.5) * 0.9;
			c += side * bnd * u * u * ln * 0.55 + vec3(0.0, 1.0, 0.0) * u * u * ln * 0.25 * go;
			float prof = pow(max(sin(3.14159 * min(u * 0.9 + 0.1, 1.0)), 0.0), 0.45) * pow(1.0 - u, 0.55);
			rad = ln * (0.2 + 0.16 * h11(k * 6.1 + 0.4)) * prof * csc * (1.0 + 0.35 * v_k);
		}
		vec3 n = normalize(side * cos(ph) + bin * sin(ph));
		float d = nz(vec2(u * 2.0 + k * 0.37, UV.y + t * 0.8));
		VERTEX = c + n * rad * (style == 1 ? (0.8 + 0.4 * d) : (0.75 + 0.5 * d));
		NORMAL = n;
		v_edge = u;
		v_tip = smoothstep(0.4, 1.0, u);
		v_s = u;
		v_arc = k;
	} else if (shape == 4) {
		float k = UV2.x;
		float u = UV.x;
		float ph = UV.y * TAU;
		float rf = 1.0 + (h11(k * 1.37 + 0.11) - 0.5) * 0.75 * sw_var;      // 半徑
		float sf = 1.0 + (h11(k * 3.07 + 0.29) - 0.5) * 0.8 * sw_var;       // 轉速
		float lf = 1.0 - h11(k * 5.19 + 0.41) * 0.42 * sw_var;              // 壽命
		float nf = 1.0 + (h11(k * 6.23 + 0.83) - 0.5) * 0.9 * sw_var;       // 角度長度（火焰長短）
		float zf = 1.0 + (h11(k * 7.31 + 0.17) - 0.5) * 0.7 * sw_var;       // 推進距離（＝螺距、彎曲度）
		float wf = 1.0 + (h11(k * 8.43 + 0.61) - 0.5) * 0.6 * sw_var;       // 粗細
		float flg = step(h11(k * 9.71 + 0.37), sw_fling);                   // 往外甩出的那幾道
		float birth = h11(k * 4.13 + 0.57) * sw_stag;
		float lifek = max(life * lf - birth, 0.05);
		float ts = max(t - birth, 0.0);
		v_sk = clamp(ts / lifek, 0.0, 1.0);
		float th0 = (k + 0.5) / max(sw_n, 1.0) * TAU + (h11(k * 2.11 + 0.73) - 0.5) * 1.7 * sw_var;
		float wang = TAU * sw_spin * sf;
		float lag = abs(wang) > 1e-3 ? sw_span * nf / abs(wang) : sw_span * nf * 0.12;
		float tu = ts - (1.0 - u) * lag;
		float tc = max(tu, 0.0);
		if (sw_instant > 0.5) { tc = ts + u * lag; tu = tc; }
		float jt = max(sw_jet, 1e-3);
		float zz = sw_len * zf * (1.0 - exp(-tc / jt));
		float rr = mix(sw_r0, sw_r1, smoothstep(0.0, 1.0, tc / lifek * 1.15)) * rf;
		rr *= 1.0 + flg * 0.85 * smoothstep(0.2, 1.0, tc / lifek);
		float th = th0 + wang * tc * (1.0 - sw_slow * smoothstep(0.0, lifek, tc));
		vec3 er = vec3(cos(th), sin(th), 0.0);
		vec3 et = vec3(-sin(th), cos(th), 0.0);
		vec3 c = er * rr + vec3(0.0, 0.0, zz);
		float dz = sw_len * zf * exp(-tc / jt) / jt;
		vec3 tg = normalize(et * rr * wang + vec3(0.0, 0.0, dz + 0.05));
		vec3 bn = cross(tg, er);
		bn = length(bn) > 1e-4 ? normalize(bn) : vec3(0.0, 1.0, 0.0);
		vec3 nr = normalize(cross(bn, tg));
		float tp = pow(max(sin(3.14159 * min(u * 1.08, 1.0)), 0.0), 0.6) * (0.3 + 0.7 * u);
		if (style == 1) {
			tp = pow(max(sin(3.14159 * min(u * 1.04, 1.0)), 0.0), 0.45) * (0.35 + 0.65 * u);
			tp *= 0.7 + 0.6 * nz(vec2(u * 1.7 + k * 0.53 + seed * 0.1, 0.71));      // 粗細不均（一節粗一節細）
		}
		float g2 = sw_instant > 0.5 ? 1.0 : smoothstep(0.0, 0.07, ts);
		float bw = sw_w * wf * tp * csc * g2 * (1.0 + 0.35 * v_sk);
		float bh = bw * sw_th;
		vec3 aw = nr;
		vec3 ah = bn;
		if (sw_band > 0.5) {
			aw = bn * (bn.z >= 0.0 ? 1.0 : -1.0);
			ah = nr;
		}
		vec3 n = normalize(aw * cos(ph) * bh + ah * sin(ph) * bw + vec3(1e-4));
		vec3 p = c + aw * cos(ph) * bw * 0.5 + ah * sin(ph) * bh * 0.5;
		float d = nz(vec2(u * 2.3 + k * 0.37 + seed * 0.1, UV.y * 0.8 - t * 1.1));
		p += n * (d - 0.45) * (style == 1 ? 0.4 : 0.7) * bw;
		VERTEX = tu < 0.0 ? c : p;
		NORMAL = n;
		v_edge = abs(cos(ph));
		v_tip = (1.0 - smoothstep(0.0, 0.42, u)) * 0.95 + max(cos(ph), 0.0) * 0.45 * smoothstep(0.3, 0.9, v_sk);
		v_s = 0.5 + 0.5 * cos(ph);
		v_arc = u * max(rr * sw_span * nf, 0.8) + k * 3.7;
	} else if (shape == 5) {
		// Shakkotsu reference sculpture: broad folded scrolls surrounding a real opening.
		// Not camera-facing quads, not three isolated vertical arcs. UV2.x selects the
		// outer scroll / inward fold; their radii and depth vary along the same form.
		float u = UV.x;
		float k = UV2.x;
		float inner = step(0.5, k);
		float ph = UV.y * TAU;
		float motion_age = age * wreath_speed;
		float turn_age = motion_age * (1.0 - 0.35 * smoothstep(0.15, life * wreath_speed, motion_age));
		float a = mix(-1.05 + u * 5.9, 1.0 + u * 4.65, inner) + turn_age * mix(3.6, 4.2, inner);
		float base_r = mix(2.05 - 0.32 * u, 1.38 - 0.12 * u, inner);
		float rr = base_r + 0.17 * sin(a * 2.0 + k) + 0.10 * sin(a * 5.0 - 0.4);
		rr += wreath_enrich * 0.07 * sin(u * 31.0 + k * 2.0 - motion_age * 4.0);
		float z = mix(-0.48 + 1.2 * u, 0.62 - 1.05 * u, inner) + 0.22 * sin(a * 1.5);
		z += wreath_enrich * 0.18 * sin(u * 13.0 + k * 3.0 + motion_age * 2.0);
		// Rip apart without shrinking the entire silhouette. Pieces fan outward only late.
		float scatter = smoothstep(0.38, 0.95, v_k);
		rr += scatter * (0.35 + 0.25 * sin(u * 11.0 + k));
		z += scatter * (0.35 * sin(u * 9.0 + k));
		vec3 er = vec3(cos(a), sin(a), 0.0);
		vec3 et = vec3(-sin(a), cos(a), 0.0);
		float taper = pow(max(sin(3.14159265 * u), 0.0), 0.25);
		float lump = 0.85 + 0.18 * sin(u * 17.0 + k * 3.0) + 0.10 * sin(u * 37.0);
		float bw = mix(1.28, 0.85, inner) * taper * lump * csc * (1.0 + 0.12 * wreath_enrich);
		float bh = mix(0.72, 0.58, inner) * taper * csc * (1.0 + 0.10 * wreath_enrich);
		vec3 ax = normalize(vec3(0.0, 0.0, 1.0) + et * (0.25 + wreath_enrich * 0.18 * sin(u * 9.0 + motion_age * 2.0)));
		vec3 c = er * rr + vec3(0.0, 0.0, z);
		vec3 n = normalize(er * cos(ph) * bh + ax * sin(ph) * bw + vec3(0.0001));
		vec3 p = c + er * cos(ph) * bw * 0.5 + ax * sin(ph) * bh * 0.5;
		float d = nz(vec2(u * 2.1 + k * 0.31, UV.y * 0.75 - age * 1.1));
		p += n * (d - 0.5) * bw * 0.22;
		VERTEX = p;
		NORMAL = n;
		v_s = 0.5 + 0.5 * cos(ph);
		v_edge = abs(cos(ph));
		v_tip = 1.0 - taper;
		v_arc = u * mix(11.0, 6.5, inner) + k * 4.7;
		v_sk = v_k;
	} else if (shape == 6) {
		// R16g Shakkotsu "sun spiral" (references: game j6xulWS7zdw 92.8-96.4 s, anime FeXwZmmmYFM 41.7-48.3 s).
		// part 2 = camera-facing star / sun disk at the eye; parts 0/1 = ONE ribbon winding inward ~2 turns
		// (UV2.x 0) plus two thin companion strips along short stretches (UV2.x 1 outside, 2 inside).
		float u = UV.x;
		float v = UV.y;
		float k = UV2.x;
		if (ss_part == 2) {
			mat3 mi = transpose(mat3(MODEL_MATRIX));
			vec3 cr = mi * INV_VIEW_MATRIX[0].xyz;
			vec3 cu = mi * INV_VIEW_MATRIX[1].xyz;
			v_fq = (vec2(u, v) * 2.0 - 1.0) * ss_flash;
			VERTEX = cr * v_fq.x + cu * v_fq.y;
			NORMAL = mi * INV_VIEW_MATRIX[2].xyz;
		} else {
			float um = u;
			float side = 0.0;
			float wk = 1.0;
			if (k > 1.5) {
				um = mix(0.16, 0.42, u);
				side = -1.0;
				wk = 0.32 * pow(max(sin(3.14159265 * u), 0.0), 0.7) * (0.55 + 0.9 * nz(vec2(u * 2.9 + seed * 0.05, 0.37)));
			} else if (k > 0.5) {
				um = mix(0.6, 0.9, u);
				side = 1.0;
				wk = 0.36 * pow(max(sin(3.14159265 * u), 0.0), 0.7) * (0.55 + 0.9 * nz(vec2(u * 2.3 + seed * 0.03, 0.91)));
			}
			float op = smoothstep(ss_open0, ss_open1, t);
			float bloom = mix(0.45, 1.0, 1.0 - pow(1.0 - op, 2.2));        // radial blossom out of the sun disk
			float kb = smoothstep(ss_break, 1.0, v_k);                       // unfurl / tear progress
			float rot = ss_spin * t * (1.0 - 0.45 * smoothstep(0.0, life, t));
			float th = ss_th0 + rot + ss_turns * TAU * um;                   // arms trail the rotation
			float lump = nz(vec2(um * 3.3 + seed * 0.013, 0.29));
			float w = mix(ss_w_in, ss_w_out, um) * (0.6 + 0.8 * lump);       // wide lobes and narrow necks
			w *= 1.0 + 0.35 * smoothstep(0.2, -0.85, sin(th)) * smoothstep(0.35, 0.7, um);   // broad lower sweep
			w *= pow(smoothstep(0.0, 0.07, um), 0.6) * pow(smoothstep(1.0, 0.955, um), 0.55);
			float rr = mix(ss_r_in, ss_r_out, um) * (0.94 + 0.12 * nz(vec2(um * 5.1 + seed * 0.021, 0.61)));
			rr -= 0.42 * ss_w_out * pow(smoothstep(0.9, 1.0, um), 1.5) + 0.25 * ss_r_in * smoothstep(0.08, 0.0, um);   // scroll-hook ends
			float piece = 0.0;
			for (int ci = 0; ci < 5; ci++) {
				float cc = 0.2 + 0.16 * float(ci) + 0.025 * sin(seed * 1.7 + float(ci) * 2.3);
				float dc = um - cc;
				float hs = clamp(1.0 - abs(dc) / 0.1, 0.0, 1.0);
				hs *= hs;
				rr -= 0.55 * kb * hs * sqrt(hs);                             // each torn end dips inward ...
				th += 0.5 * kb * hs * (dc < 0.0 ? -1.0 : 1.0) * sign(ss_turns);   // ... and turns back = hook
				piece += step(cc, um);
			}
			rr *= bloom * (1.0 + kb * (0.12 + 0.05 * piece));                // pieces drift apart
			th += kb * (piece - 2.5) * 0.07;
			vec3 er = vec3(cos(th), sin(th), 0.0);
			vec3 et = vec3(-sin(th), cos(th), 0.0);
			float zc = mix(ss_z_in, ss_z_out, um) + 0.12 * sin(th * 2.0 + seed) + kb * 0.06 * (piece - 2.5);
			vec3 c = er * rr + vec3(0.0, 0.0, zc);
			vec3 tg = normalize(et * sign(ss_turns) * max(abs(ss_turns) * TAU * rr, 0.3) + vec3(0.0, 0.0, ss_z_out - ss_z_in));
			vec3 wd = normalize(er * cos(0.42) - vec3(0.0, 0.0, 1.0) * sin(0.42));   // shallow funnel
			float tw = 0.3 * sin(um * 9.0 + seed * 0.37) * (0.6 + 0.4 * lump);
			wd = normalize(wd * cos(tw) + cross(tg, wd) * sin(tw));          // twists into narrow necks
			w *= 1.0 - 0.25 * kb;
			float wm = w * 1.45;                                             // body + tongue zone
			float wc = wm * wk;
			float off = side * (0.5 * wm + 0.06 + 0.5 * wc);
			float wv = wc * (ss_part == 1 ? 2.0 : 1.0);
			vec3 p = c + wd * (off + (v - 0.5) * wv);
			p += wd * (nz(vec2(um * 7.0 + k * 0.3, v * 0.8 - t * 0.9)) - 0.5) * 0.05;
			// floor: lower half squashed so the outer turn skims the ground, then a soft floor for tongues / drift
			vec3 wup = vec3(MODEL_MATRIX[0].y, MODEL_MATRIX[1].y, MODEL_MATRIX[2].y);
			float hc = MODEL_MATRIX[3].y - ss_ground;
			float sq = clamp((hc - ss_gap) / max(ss_r_out * 1.15 * max(MODEL_MATRIX[1].y, 0.2), 0.05), 0.3, 1.0);
			p.y *= p.y < 0.0 ? sq : ss_up;
			p += wup * kb * 0.15;
			float hv = hc + dot(wup, p);
			float hm = ss_gap * 0.5;
			float hn = hv > hm + 0.2 ? hv : hm + 0.2 * exp((hv - hm - 0.2) / 0.2);
			p += wup * (hn - hv);
			VERTEX = p;
			NORMAL = normalize(cross(tg, wd));
			v_u = um;
			v_s = v;
			v_w = wv;
			v_arc = ss_turns * TAU * (ss_r_in * um + 0.5 * (ss_r_out - ss_r_in) * um * um) + k * 7.3;
			v_tip = kb;
			v_edge = op;
		}
	} else {
		v_obj = VERTEX;
		if (sway > 0.0) {
			VERTEX += NORMAL * (nz(vec2(UV.x * body_len * 0.35 - t * 0.7, UV.y)) - 0.45) * sway;
		}
	}
}

// style 1：一片火焰（x＝沿邊的距離 m、s＝0 內緣 → 1 外緣），火體＋外緣火舌；回傳覆蓋率，tipk＝在火舌裡往尖端的位置（火體內＝-1），tsel＝這根火舌的亂數
float flame_sheet(float x, float s, float sb, float tl, float er, float lk, out float tipk, out float tsel) {
	float wob = nz(vec2(x * 0.45 + seed * 0.11, 0.21 + lk * 0.35 + age * 0.15));
	float sbl = clamp(sb + (wob - 0.5) * 0.32, 0.12, 0.85);        // 火體邊緣起伏
	float y = (s - sbl) / max(1.0 - sbl, 0.05);
	float xc = x / max(t_space, 0.05);
	xc += (nz(vec2(x * 0.17 + seed * 0.07, 0.83)) - 0.5) * 2.6;       // 間距不均（不是等距鋸齒）
	float yp = max(y, 0.0);
	xc += yp * yp * t_lean;                                          // 火舌往後傾（拖在動作後面），越近尖端越斜
	xc += (nz(vec2(x * 1.1 - age * 1.7, yp * 0.6 + seed * 0.3)) - 0.5) * 0.8 * yp;   // 流動的擺動（越近尖端越大）
	float id = floor(xc);
	float fx = fract(xc) - 0.5;
	float q1 = h11(id * 1.13 + 3.1);           // 這根火舌的長度／粗細／分岔亂數（不能叫 r1：和新月的 r1 uniform 同名）
	float q2 = h11(id * 2.71 + 7.3);
	float q3 = h11(id * 4.37 + 1.9);
	tsel = h11(id * 6.91 + 5.5);
	float Lk = tl * mix(0.3, 1.0, q1) * (1.0 - 0.4 * er);          // 長短不一
	float yn = y / max(Lk, 0.04);
	float hw = mix(0.2, 0.46, q2) * pow(clamp(1.0 - yn, 0.0, 1.0), mix(0.35, 0.85, q3));   // 由粗到尖（曲線，不是直線三角；每根曲線不同）
	hw *= 1.0 + 0.25 * sin(yn * 7.0 + q1 * 6.0) * yn;              // 火舌中段一節粗一節細
	hw *= step(0.16, q1);                                           // 少數位置沒有火舌（空隙）
	hw = max(hw, 0.5 * (1.0 - smoothstep(0.0, 0.22, y)));             // 根部和火體連在一起（沒有三角形的底邊）
	float dd = abs(fx) - hw;
	if (q3 < t_fork && yn > 0.5) {                                   // 分岔：長火舌在後半段分成兩股
		float sep = (yn - 0.5) * 0.5 * mix(0.16, 0.4, q2);
		dd = abs(abs(fx) - sep) - hw * 0.62;
	}
	float aa = fwidth(xc) * 0.8 + 0.012;
	float tongue = y > 0.0 && yn < 1.0 ? 1.0 - smoothstep(-aa, aa, dd) : 0.0;
	float body = 1.0 - smoothstep(-0.04, 0.02, y);
	tipk = y > 0.0 ? clamp(yn, 0.0, 1.0) : -1.0;
	return max(body, tongue);
}

// R16g（shape 6）：火焰片＋到輪廓的有號距離（m，> 0 在內）：火體、往後掃的外緣火舌（長短粗細不一、部分分岔、少數空隙）、有缺口的內緣
void sun_sheet(float x, float s, float sb, float tl, float er, float W, out float tipk, out float tsel, out float sd) {
    float wob = nz(vec2(x * 0.45 + seed * 0.11, 0.21 + age * 0.15));
    float sbl = clamp(sb + (wob - 0.5) * 0.3, 0.15, 0.85);
    float y = (s - sbl) / max(1.0 - sbl, 0.05);
    float xc = x / max(t_space, 0.05);
    xc += (nz(vec2(x * 0.17 + seed * 0.07, 0.83)) - 0.5) * 2.6;
    float yp = max(y, 0.0);
    xc += yp * yp * t_lean;
    xc += (nz(vec2(x * 1.1 - age * 1.7, yp * 0.6 + seed * 0.3)) - 0.5) * 0.8 * yp;
    float id = floor(xc);
    float fx = fract(xc) - 0.5;
    float q1 = h11(id * 1.13 + 3.1);
    float q2 = h11(id * 2.71 + 7.3);
    float q3 = h11(id * 4.37 + 1.9);
    tsel = h11(id * 6.91 + 5.5);
    float Lk = tl * mix(0.3, 1.0, q1) * (1.0 - 0.4 * er);
    float yn = y / max(Lk, 0.04);
    float hw = mix(0.2, 0.46, q2) * pow(clamp(1.0 - yn, 0.0, 1.0), mix(0.35, 0.85, q3));
    hw *= 1.0 + 0.25 * sin(yn * 7.0 + q1 * 6.0) * yn;
    hw *= step(0.16, q1);
    hw = max(hw, 0.5 * (1.0 - smoothstep(0.0, 0.22, y)));
    float dd = abs(fx) - hw;
    if (q3 < t_fork && yn > 0.5) {
        float sep = (yn - 0.5) * 0.5 * mix(0.16, 0.4, q2);
        dd = abs(abs(fx) - sep) - hw * 0.62;
    }
    float d_tongue = (y > 0.0 && yn < 1.0) ? -dd * t_space : -1.0;
    float d_body = (sbl - s) * W;
    float s_in = 0.04 + 0.1 * nz(vec2(x * 0.33 + seed * 0.19, 0.47));
    float d_in = (s - s_in) * W;
    sd = min(max(d_body, d_tongue), d_in);
    tipk = y > 0.0 ? clamp(yn, 0.0, 1.0) : -1.0;
}

void fragment() {
	vec3 Nn = normalize(NORMAL);
	float fres = abs(dot(Nn, normalize(VIEW)));
	vec2 q;
	float flowv = flow;
	if (shape == 3) {
		q = vec2(v_u * body_len * 0.55 - age * flowv, v_v * 1.3 + seed);
	} else if (shape == 1) {
		q = vec2(v_u * 4.0 - age * 1.6 + v_band * 0.27, v_v * 1.1 + seed * 0.1);
	} else if (shape == 4 || shape == 5) {
		q = vec2(v_u * 3.0 - age * 1.7 + v_band * 0.41, v_v * 1.1 + seed * 0.1);
	} else {
		q = vec2(v_u * 3.2 - age * 1.1 + seed * 0.07, v_v * 1.2 + age * 0.35);
	}
	float n1 = nz(q);
	float n2 = nz(q * 2.4 + vec2(0.37, age * 0.9));
	float n = n1 * 0.62 + n2 * 0.38;
	float grow = shape == 5 ? smoothstep(0.0, 0.025, age) : ((shape == 4 && sw_instant > 0.5) ? 1.0 : smoothstep(0.0, 0.07, age));
	if (shape == 6) {
		// ---------------------------------------------------------------- R16g 灼骨炎陽「日輪渦」（cel 風格；其他 shape 不經過這裡）
		float a_out = 0.0;
		vec3 col = vec3(0.0);
		if (ss_part == 2) {
			// 星芒（冷白→暖白，十字光，橫長直短）＋白色日輪（燃燒外緣）由中心打開成渦的內圈
			vec2 q2 = v_fq;
			float r = length(q2);
			float sg = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.16, 0.3, age));
			float lh = mix(0.3, 2.4, smoothstep(0.015, 0.11, age)) * mix(1.0, 0.3, smoothstep(0.1, 0.24, age));
			float lv = lh * 0.55;
			float fh = max(1.0 - abs(q2.x) / lh, 0.0);
			float fv = max(1.0 - abs(q2.y) / lv, 0.0);
			float rh = pow(fh, 1.8) * exp(-abs(q2.y) / (0.006 + 0.014 * fh));
			float rv = pow(fv, 1.8) * exp(-abs(q2.x) / (0.006 + 0.012 * fv));
			float core_s = exp(-r * r / 0.012);
			float star = sg * clamp(max(rh, rv) + core_s, 0.0, 1.0);
			star *= smoothstep(0.04, 0.12, star);                            // no faint white veil over the ribbons
			vec3 scol = mix(vec3(0.65, 0.71, 1.0), vec3(1.0, 0.97, 0.86), smoothstep(0.03, 0.09, age));
			scol = mix(scol, vec3(1.0), clamp(core_s + max(rh, rv) * 0.6 - 0.2, 0.0, 1.0));
			float rd = mix(0.15, ss_r_in * 1.02, smoothstep(0.02, 0.11, age));
			float ang = atan(q2.y, q2.x);
			float rimn = nz(vec2(ang * 0.48 + seed * 0.01, age * 2.2 + 0.17));
			float rim_w = rd * (0.16 + 0.12 * rimn);
			float dsk = smoothstep(0.02, 0.04, age) * (1.0 - smoothstep(0.12, 0.17, age));
			float clear_r = rd * smoothstep(0.085, 0.15, age);
			float in_disk = 1.0 - smoothstep(rd - 0.02, rd + 0.01, r);
			float hole = smoothstep(clear_r - 0.05, clear_r + 0.02, r);
			float rim = smoothstep(rd - rim_w, rd - rim_w * 0.4, r) * (1.0 - smoothstep(rd + rim_w * 0.6 * rimn, rd + rim_w * (0.6 + 0.9 * rimn), r));
			float disk_a = dsk * max(in_disk * hole, rim);
			float rk = clamp((r - (rd - rim_w)) / max(rim_w * 1.6, 1e-3), 0.0, 1.0);
			vec3 rcol = mix(ss_pale.rgb, ss_yellow.rgb, smoothstep(0.15, 0.4, rk));
			rcol = mix(rcol, ss_orange.rgb, smoothstep(0.45, 0.7, rk));
			rcol = mix(rcol, ss_vermilion.rgb, smoothstep(0.75, 0.95, rk));
			vec3 dcol = mix(vec3(1.0, 0.98, 0.9), rcol, rim * smoothstep(rd - rim_w, rd, r)) * 1.1;
			a_out = star + disk_a * (1.0 - star);
			col = (scol * 1.25 * star + dcol * disk_a * (1.0 - star)) / max(a_out, 1e-3);
		} else {
			float kb = v_tip;
			// 由內圈（日輪外緣）往外展開
			float rev = clamp((age - ss_open0 * 0.85) / max(ss_open1 - ss_open0 * 0.85, 1e-3), 0.0, 1.0);
			float vis = smoothstep(-0.015, 0.03, rev * 1.08 - v_u + (n - 0.5) * 0.05);
			float W = max(v_w, 0.02);
			if (ss_part == 1) {
				// 火焰片後面的柔光（不描邊、低不透明度）
				float hx = abs(v_s - 0.5) * 2.0;
				float hal = pow(max(1.0 - hx, 0.0), 1.6) * (0.6 + 0.4 * n);
				a_out = 0.22 * hal * vis * (1.0 - smoothstep(0.5, 0.95, v_k)) * smoothstep(0.0, 0.03, age);
				col = mix(ss_deep.rgb, ss_vermilion.rgb, 0.25 + 0.35 * n * hal) * 0.85;
			} else {
				float body = v_band > 0.5 ? 0.7 : t_body;
				float tl = v_band > 0.5 ? 0.6 : t_len;
				float tipk;
				float tsel;
				float sd;
				sun_sheet(v_arc, v_s, body, tl, kb * 0.9, W, tipk, tsel, sd);
				float aa = min(fwidth(sd) * 0.9 + 0.002, 0.015);
				float cov = smoothstep(-aa, aa, sd);
				// 撕開：三個斷點的缺口隨 kb 張開（每段的端點在頂點裡往內捲成鉤）
				float g = kb * 0.02 + kb * kb * 0.015;
				for (int ci = 0; ci < 5; ci++) {
					float cc = 0.2 + 0.16 * float(ci) + 0.025 * sin(seed * 1.7 + float(ci) * 2.3);
					cov *= smoothstep(g, g + 0.01, abs(v_u - cc) + (n - 0.5) * 0.02 * kb);
				}
				float brk = nz(vec2(v_arc * 0.31 + seed * 0.3 - age * 0.5, v_s * 0.9 - age * 0.3)) * 0.7 + n * 0.3;
				float ero = kb * kb * (0.5 + 0.35 * v_s);
				cov *= smoothstep(ero - 0.08, ero + 0.08, brk * 0.9 + 0.1);
				// cel 色塊：橘色火體裡沿流動方向的長條黃色紋路；邊緣朱紅／深紅；部分輪廓深褐紅線
				float st1 = nz(vec2(v_arc * 0.19 - age * 1.1 + seed * 0.05, v_s * 1.3 + v_band * 0.31));
				float st2 = nz(vec2(v_arc * 0.47 - age * 1.9, v_s * 2.6 + 0.4));
				float mid = 1.0 - clamp(abs(v_s / max(body, 0.1) - 0.45) * 1.9, 0.0, 1.0);
				float heat = 0.38 * mid + 0.42 * st1 + 0.2 * st2;
				heat = tipk < 0.0 ? heat : mix(heat * 0.85, 0.12, pow(tipk, 0.9));
				heat += 0.06 * smoothstep(0.55, 0.0, v_u);
				heat += 0.16 * smoothstep(0.07, 0.0, abs(age - ss_flare));
				heat -= FRONT_FACING ? 0.0 : 0.08;
				heat -= 0.18 * kb;
				heat *= v_band > 0.5 ? 0.8 : 1.0;
				float hw = min(fwidth(heat) * 0.7 + 0.004, 0.03);
				vec3 c2 = ss_deep.rgb;
				c2 = mix(c2, ss_vermilion.rgb, smoothstep(0.24 - hw, 0.24 + hw, heat));
				c2 = mix(c2, ss_orange.rgb, smoothstep(0.38 - hw, 0.38 + hw, heat));
				c2 = mix(c2, ss_yellow.rgb, smoothstep(0.56 - hw, 0.56 + hw, heat));
				c2 = mix(c2, ss_pale.rgb, smoothstep(0.76 - hw, 0.76 + hw, heat));
				float lum = mix(0.84, 1.1, smoothstep(0.5, 0.75, heat));
				float lw = 0.035 + 0.02 * n;
				float edge_ln = (1.0 - smoothstep(lw - aa, lw + aa, sd)) * cov;
				float lsel = smoothstep(0.42, 0.55, nz(vec2(v_arc * 0.09 + seed * 0.07, 0.83 + v_band * 0.2)));
				lsel = max(lsel, tipk > 0.55 ? 1.0 : 0.0);
				c2 = mix(c2, ss_line.rgb, edge_ln * lsel * 0.85);
				lum = mix(lum, 0.75, edge_ln * lsel);
				float pk = pink * step(1.0 - t_pinksel, tsel) * (tipk < 0.0 ? 0.0 : smoothstep(0.35, 0.8, tipk)) * (1.0 - edge_ln * lsel);
				c2 = mix(c2, col_tip_pink.rgb, clamp(pk, 0.0, 0.8));
				a_out = cov * vis * smoothstep(0.0, 0.02, age) * (1.0 - smoothstep(0.9, 1.0, v_k)) * 0.97;
				col = c2 * lum;
			}
		}
		if (a_out < 0.02) {
			discard;
		}
		ALBEDO = col * gain;
		ALPHA = clamp(a_out * fade, 0.0, 1.0);
	} else if (style == 1 && (shape == 0 || shape == 2 || shape == 4 || shape == 5)) {
		// ---------------------------------------------------------------- style 1：風格化火焰
		float lk = shape == 4 ? v_sk : v_k;
		float er = max(smoothstep(tear, 1.0, lk) * 1.1, erode);
		float vis = 1.0;
		float tipk = -1.0;
		float tsel = 0.0;
		float cov = 1.0;
		float heat = 0.5;
		float sel_base = 0.0;
		if (shape == 0 || shape == 4 || shape == 5) {
			float sb = core > 0.5 ? 0.62 : t_body;
			float tl = core > 0.5 ? 0.45 : t_len;
			cov = flame_sheet(v_arc, v_s, sb, tl, er, lk, tipk, tsel);
			float bodyk = clamp(v_s / max(sb, 0.05), 0.0, 1.0);          // 火體內：0 內緣 → 1 火體邊緣
			heat = tipk < 0.0 ? mix(0.88, 0.5, bodyk * bodyk) : mix(0.46, 0.2, pow(tipk, 0.8));
			if (core > 0.5) {
				heat = tipk < 0.0 ? mix(1.12, 0.78, bodyk) : mix(0.74, 0.5, tipk);
			}
			if (shape == 0) {
				float revu = clamp(age / max(reveal_s, 1e-3), 0.0, 1.0);
				float lead = revu * 1.06 - v_u;
				vis = smoothstep(-0.02, 0.06, lead + (n - 0.5) * 0.06);
				heat += smoothstep(0.1, 0.0, abs(lead - 0.03)) * 0.25 * (1.0 - v_k);
			} else {
				// 旋渦火焰：頭熱尾冷；尾巴後段碎成一塊一塊（拉長、撕裂、消散）
				heat *= 0.72 + 0.5 * smoothstep(0.1, 0.95, v_u);
				heat += smoothstep(0.8, 1.0, v_u) * 0.18 * (1.0 - v_sk);
				float frag = nz(vec2(v_arc * 0.9 - age * 1.3, 0.53 + v_band * 0.17));
				float thr = 0.62 * (1.0 - smoothstep(0.0, 0.42, v_u));
				cov *= smoothstep(thr - 0.08, thr + 0.08, frag);
				sel_base = 1.0 - smoothstep(0.0, 0.2, v_u);                  // 尾端（火焰的末梢）
			}
		} else {
			// 爆燃的火舌：根部金黃 → 尖端橘紅；尖端粗糙撕裂
			heat = mix(core > 0.5 ? 1.08 : 0.9, 0.22, pow(v_u, 0.75));
			tipk = v_u > 0.35 ? (v_u - 0.35) / 0.65 : -1.0;
			tsel = h11(v_arc * 5.3 + 2.2);
			er = max(er, smoothstep(0.35, 1.0, v_k) * (0.4 + 0.6 * v_u));
			cov = smoothstep(0.06, 0.38, fres) * (1.0 - smoothstep(0.7, 1.0, v_u) * smoothstep(0.35, 0.65, 1.0 - n));   // 輪廓柔、尖端破碎（不是硬三角片）
		}
		// 撕裂：外側先破成碎塊、慢慢透明（不是整片一起淡掉）
		float brk = nz(vec2(v_arc * 0.42 + seed * 0.3 - age * 0.45, v_s * 0.9 - age * 0.25)) * 0.7 + n * 0.3;
		float ero = er * (0.75 + 0.45 * v_s);
		cov *= smoothstep(ero - 0.1, ero + 0.1, brk * 0.9 + 0.1);
		heat += (n - 0.5) * 0.16;
		heat *= 1.0 - 0.32 * smoothstep(0.25, 1.0, lk);                  // 冷卻：越接近消散越偏橘紅
		heat *= heat_mul;
		float life_k = grow * (1.0 - smoothstep(0.82, 1.0, lk));
		vec3 col = mix(col_red.rgb, col_orange.rgb, smoothstep(0.12, 0.38, heat));
		col = mix(col, col_gold.rgb, smoothstep(0.38, 0.7, heat));
		col = mix(col, col_core.rgb, smoothstep(0.86 + 0.18 * (1.0 - hot), 1.1 + 0.12 * (1.0 - hot), heat));
		// 淡粉紅火舌尖端：選中的火舌（t_pinksel 比例）尖端 40% 漸變成淡粉紅；其他火舌只在最尖一點點；消散的碎塊也帶一點
		float sel = step(1.0 - t_pinksel, tsel);
		float tipz = tipk < 0.0 ? 0.0 : smoothstep(0.3, 0.78, tipk);
		float pk = pink * tipz * mix(0.18, 1.0, sel);
		pk = max(pk, pink * 0.8 * sel_base * step(0.5, h11(v_band * 2.9 + 0.7)));
		pk = max(pk, pink * 0.45 * smoothstep(0.6, 0.95, lk) * smoothstep(0.45, 0.85, v_s) * sel);
		pk *= 1.0 - core * 0.85;
		pk = clamp(pk, 0.0, 0.92);
		col = mix(col, col_tip_pink.rgb, pk);
		float a = cov * vis * fade * life_k * (tipk < 0.0 ? 0.95 : mix(0.95, 0.84, tipk));
		if (a < 0.02) {
			discard;
		}
		float lum = 0.8 + 0.85 * hot * smoothstep(0.5, 1.1, heat);      // 金黃 ~1.0、火芯 ~1.3（hot 0.6）；橘紅與粉紅 < 0.95（不進泛光）
		lum = mix(lum, 0.93, pk);                                       // 淡粉紅：亮但在泛光門檻（0.95）以下，不被洗白
		ALBEDO = col * gain * lum;
		ALPHA = clamp(a, 0.0, 1.0);
	} else {
		// ---------------------------------------------------------------- style 0：R16 原樣（回退用）
		float heat = pow(fres, 0.75) * (0.5 + 0.8 * n) + core * 0.42;
		// 第一個 0.08 s 長出來；撕裂：tear 之後侵蝕門檻往上（不規則地裂開、碎散），最後整體熄滅
		float er = max(smoothstep(tear, 1.0, v_k) * 1.15, erode);
		float vis = 1.0;
		float lk = v_k;
		if (shape == 0) {
			// 角度依刀路揭露：前緣是最亮的地方
			float revu = clamp(age / max(reveal_s, 1e-3), 0.0, 1.0);
			float lead = revu * 1.06 - v_u;
			vis = smoothstep(-0.02, 0.06, lead + (n - 0.5) * 0.06);
			heat += smoothstep(0.12, 0.0, abs(lead - 0.03)) * 0.35 * (1.0 - v_k);
			heat *= 0.8 + 0.35 * (1.0 - v_edge);
		} else if (shape == 1) {
			float fr = clamp(age / max(jet, 1e-3), 0.0, 1.0);
			heat *= 0.75 + 0.5 * (1.0 - v_u * 0.6);
			heat += smoothstep(0.06, 0.0, abs(v_u - 0.97)) * 0.3 * (1.0 - fr * 0.5);
		} else if (shape == 2) {
			heat *= 1.15 - 0.6 * v_edge;
			er = max(er, smoothstep(0.35, 1.0, v_k) * (0.5 + 0.6 * v_edge));
		} else if (shape == 4) {
			// 每一道火焰自己的生命：頭熱尾冷、頭端白熱，各自在不同時間撕裂、熄滅
			heat *= 0.8 + 0.55 * v_u;
			heat += smoothstep(0.72, 1.0, v_u) * 0.3 * (1.0 - v_sk);
			er = max(smoothstep(tear, 1.0, v_sk) * 1.15, erode);
			lk = v_sk;
		} else {
			vis = smoothstep(burn - 0.06, burn + 0.06, v_u + (n - 0.5) * 0.15) * smoothstep(-0.03, 0.03, reveal - v_u);
			heat += form_shade * (dot(Nn, normalize((VIEW_MATRIX * vec4(0.35, 0.9, 0.25, 0.0)).xyz)) * 0.5 + 0.5) - form_shade * 0.5;
		}
		float mask = smoothstep(er - 0.1, er + 0.1, n * 0.85 + heat * 0.3);
		float life_k = grow * (1.0 - smoothstep(0.82, 1.0, lk));
		heat *= life_k;
		vec3 col = mix(col_red.rgb, col_orange.rgb, smoothstep(0.12, 0.42, heat));
		col = mix(col, col_gold.rgb, smoothstep(0.42, 0.72, heat));
		col = mix(col, col_core.rgb, smoothstep(0.8 + 0.3 * (1.0 - hot), 1.08 + 0.25 * (1.0 - hot), heat));
		// 淡粉紅火舌末端：只在尖端（v_tip 高）的低溫外焰；低頻斑塊噪聲 pz 決定哪幾段火舌有（沿 u、隨生命分 4 段跳變＝若隱若現），
		// 不是沿整條外緣的均勻描邊；消散時稍多；火芯層不上
		float pz = texture(noise_tex, vec2(v_u * 0.85 + seed * 0.173, 0.31 + seed * 0.291 + floor(lk * 4.0) * 0.237)).g;
		float pk = pink * smoothstep(0.5, 0.95, v_tip) * smoothstep(0.5, 0.7, pz) * smoothstep(0.46, 0.7, n + 0.18 * lk)
			* (1.0 - smoothstep(0.28, 0.62, heat)) * (0.4 + 0.6 * smoothstep(0.2, 0.85, lk)) * (1.0 - core * 0.9);
		col = mix(col, col_pink.rgb, clamp(pk, 0.0, 0.75));
		float a = clamp(heat * (core > 0.5 ? 2.2 : (shape == 2 ? 1.15 : 1.6)), 0.0, 1.0) * mask * vis * fade;
		if (a < 0.01) {
			discard;
		}
		ALBEDO = col * gain * (0.75 + 1.25 * hot * clamp(heat, 0.0, 1.2));
		ALPHA = a;
	}
}
