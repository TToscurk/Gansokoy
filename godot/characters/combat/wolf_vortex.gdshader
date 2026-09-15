shader_type spatial;
// 山犬撲擊旋風：沿曲線長度 trim 的能量帶。
//
// 這是 Blender 端 NURBS 曲線 + 逐幀 bevel_factor_start/end 動畫的 Godot 重現。
// glTF 沒有曲線型別、也沒有 bevel_factor，所以曲線在 Blender 被轉成「全長管狀
// 靜態網格」匯出，掃出／消失的動態改由本 shader 在 GPU 上做。
//
// 關鍵：Blender 曲線轉網格時，UV.y 天生就是「沿曲線長度 0→1」，
//       UV.x 是環繞管周。所以 trim 只要對 UV.y 開窗即可，不需要額外資料。
//
// trim_start / trim_end 對應 Blender 的 bevel_factor_start / bevel_factor_end：
//   只有 UV.y 落在 [trim_start, trim_end] 區間的片段會被畫出來。
//   兩者相等（預設 0.0）時整條完全不可見 —— 與 Blender frame 0 的狀態一致。

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// 沿曲線長度的顯示區間（0–1）。由 wolf_vortex_fx.gd 逐幀餵入。
uniform float trim_start : hint_range(0.0, 1.0) = 0.0;
uniform float trim_end : hint_range(0.0, 1.0) = 0.0;
// 整體亮度。收招淡出時降到 0。
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// 能量帶顏色（頭亮尾暗）
uniform vec3 color_head : source_color = vec3(0.86, 0.95, 1.0);
uniform vec3 color_tail : source_color = vec3(0.35, 0.62, 1.0);
// 兩端的軟收邊寬度（佔 trim 長度比例），避免硬切斷面
uniform float edge_softness : hint_range(0.0, 0.5) = 0.18;
// 沿長度流動的細紋速度與密度，讓帶子看得出在「跑」
uniform float flow_speed = 2.4;
uniform float flow_density = 14.0;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float t = UV.y;

	// trim 區間外整個丟掉 —— 這是「還沒掃到 / 已經消失」的部分
	float span = trim_end - trim_start;
	if (span <= 0.0001 || t < trim_start || t > trim_end) {
		discard;
	}

	// 區間內的正規化位置：0 = 尾端，1 = 頭端
	float local = (t - trim_start) / span;

	// 兩端軟收邊，讓斷面不是硬切
	float soft = max(edge_softness, 0.001);
	float fade = smoothstep(0.0, soft, local) * smoothstep(0.0, soft, 1.0 - local);

	// 沿長度流動的細紋
	float flow = sin((t * flow_density - TIME * flow_speed) * 6.2831853) * 0.5 + 0.5;
	float energy = mix(1.0, flow, flow_strength);

	// 管周方向（UV.x）中間亮、邊緣暗，做出圓柱體積感
	float rim = sin(UV.x * 3.14159265);

	vec3 col = mix(color_tail, color_head, local);
	float a = fade * energy * rim * intensity;

	ALBEDO = col * a;
	ALPHA = a;
}
