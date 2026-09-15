shader_type spatial;
// 山犬跑步／撲擊風線：沿曲線 trim 的速度線。
//
// 與 wolf_vortex.gdshader 同一套原理（Blender 的 NURBS bevel trim → UV.y 開窗），
// 差別在視覺調性：風線是細長的白色速度線，比旋風更淡、更銳利，
// 用來讀「跑很快」而不是「有能量在旋轉」。
//
// trim_start / trim_end 對應 Blender 的 bevel_factor_start / bevel_factor_end。
// ⚠ 風線的 trim 區間會**跨越端點回繞**（start > end，例如 start=0.69 / end=1.0
//   接著下一循環從 0 開始）—— 這是它做出「一條條往後掃過去」的關鍵。
//   所以判定不能只寫 t < start || t > end，必須處理回繞情形。

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float trim_start : hint_range(0.0, 1.0) = 0.0;
uniform float trim_end : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// 速度線顏色：頭端偏白、尾端偏淡藍，尾巴淡出
uniform vec3 color_head : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 color_tail : source_color = vec3(0.62, 0.80, 1.0);
// 兩端軟收邊（佔 trim 長度比例）
uniform float edge_softness : hint_range(0.0, 0.5) = 0.25;
// 整體不透明度上限。風線要淡，太實會糊成一片白
uniform float opacity : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float t = UV.y;
	float s = trim_start;
	float e = trim_end;

	float span;
	float local;
	if (e >= s) {
		// 一般區間
		span = e - s;
		if (span <= 0.0001 || t < s || t > e) {
			discard;
		}
		local = (t - s) / span;
	} else {
		// 回繞區間：[s, 1] ∪ [0, e]
		span = (1.0 - s) + e;
		if (span <= 0.0001) {
			discard;
		}
		if (t >= s) {
			local = (t - s) / span;
		} else if (t <= e) {
			local = ((1.0 - s) + t) / span;
		} else {
			discard;
		}
	}

	float soft = max(edge_softness, 0.001);
	float fade = smoothstep(0.0, soft, local) * smoothstep(0.0, soft, 1.0 - local);

	// 管周方向中間亮、邊緣暗
	float rim = sin(UV.x * 3.14159265);

	vec3 col = mix(color_tail, color_head, local);
	float a = fade * rim * intensity * opacity;

	ALBEDO = col * a;
	ALPHA = a;
}
