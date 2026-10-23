// FIRE_RESEARCH_V2 火舌（GPU 粒子的繪製材質）。程序化火焰，不是貼圖序列：
//   形狀＝淚滴形輪廓 × 往上流動的噪聲侵蝕。每顆粒子從生到滅：小而熱 → 長成完整火舌 → 侵蝕門檻上升，撕裂、分岔 → 變冷、變透明。
//   噪聲座標隨時間往上捲，所以火舌在畫面上持續變形，不是固定形狀放大縮小。
// INSTANCE_CUSTOM：x＝年齡（秒），y＝壽命（秒），z＝種子，w＝種類（0 刀路火舌、1 刀身小火、2 命中爆燃）。
// 粒子變換的 Y 軸＝火舌朝向（世界座標，通常是上方），長度＝火舌高度；X 軸長度＝寬度。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float fx_time = 0.0;          // 由腳本推進；Hit Stop 時不前進
uniform float brightness = 1.0;
uniform float occlusion = 0.80;       // 熱區擋掉背景的比例（0＝純加法）；顏色永遠是亮的，所以高覆蓋也不會變棕

varying float v_age;
varying float v_seed;
varying float v_kind;
varying float v_int;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.x / max(INSTANCE_CUSTOM.y, 0.01), 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	v_kind = INSTANCE_CUSTOM.w;
	v_int = COLOR.a;
	// 朝相機的面片，但「上」＝粒子 Y 軸投影到畫面（火舌永遠沿自己的方向竄，不會跟著相機轉）
	vec3 ax = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	vec2 up = ax.xy;
	up = length(up) > 1e-4 ? normalize(up) : vec2(0.0, 1.0);
	vec2 side = vec2(up.y, -up.x);
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	// 生長：出生時 55%，0.3 壽命內長到全高；命中爆燃長得更快、更大
	float grow = v_kind > 1.5 ? mix(0.5, 1.25, sqrt(v_age)) : mix(0.55, 1.0, smoothstep(0.0, 0.3, v_age));
	vec2 p = vec2(VERTEX.x * w, (VERTEX.y + 0.40) * h) * grow;      // 底部在粒子位置下方 0.1 高，火從那一點往上長
	VERTEX = vec3(side * p.x + up * p.y, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);                 // y：0 底、1 頂
	float a = v_age;
	float s = v_seed;
	float t = fx_time;
	float flip = fract(s * 13.7) > 0.5 ? 1.0 : -1.0;
	// 往上流動的噪聲（每顆粒子不同的起點與流速）
	float flow = mix(1.1, 1.8, fract(s * 5.3));
	vec2 q = vec2(uv.x * 0.55 * flip + s * 3.7, uv.y * 0.42 - t * flow * 0.55 - a * 0.25);
	vec3 nA = texture(noise_tex, q).rgb;
	vec3 nB = texture(noise_tex, q * vec2(1.9, 1.6) + vec2(0.31, -t * 0.35)).rgb;
	// 橫向扭動：越高扭得越多（火舌根部穩、尖端甩動）
	float lean = (fract(s * 7.1) - 0.5) * 0.5;
	float x = uv.x - 0.5 + (nA.r - 0.5) * 0.62 * uv.y + lean * uv.y * uv.y;
	// 淚滴輪廓：根部圓、往上收尖；高度隨年齡先長後縮
	float hmax = mix(0.62, 0.98, smoothstep(0.0, 0.35, a)) * mix(1.0, 0.78, smoothstep(0.55, 1.0, a));
	float yy = uv.y / hmax;
	float width = 0.34 * pow(clamp(1.0 - yy, 0.0, 1.0), 0.7) * smoothstep(-0.02, 0.16, yy);
	float shape = clamp(1.0 - abs(x) / max(width, 1e-3), 0.0, 1.0);
	// 侵蝕：Worley 細胞邊（G）負責撕開破口與分岔，fbm 負責柔和外形；年齡越大、位置越高，門檻越高
	float n = nA.r * 0.45 + nB.b * 0.30 + (1.0 - nA.g) * 0.25;
	float thr = mix(0.18, 0.80, a * a) + yy * 0.22;
	float field = shape * 0.85 + (n - 0.5) * 0.9 * (0.35 + yy);
	float dens = smoothstep(thr, thr + 0.20, field);
	// 熱度：根部、中心、年輕＝熱；尖端與外緣冷
	float core = clamp(1.0 - abs(x) / max(width * 0.55, 1e-3), 0.0, 1.0);
	float heat = dens * (0.25 + 0.75 * core) * (1.0 - yy * 0.6) * mix(0.84, 0.26, a) * (0.80 + 0.3 * nB.r);
	heat *= v_kind > 1.5 ? 1.12 : 1.0;
	float birth = smoothstep(0.0, 0.06, a);
	float death = 1.0 - smoothstep(0.78, 1.0, a);
	float cov = dens * birth * death * v_int;
	float soft = soft_depth(depth_tex, SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, 0.12);
	cov *= soft;
	ALBEDO = fire_ramp(heat) * cov * brightness;
	ALPHA = cov * occlusion * smoothstep(0.08, 0.40, heat);
}
