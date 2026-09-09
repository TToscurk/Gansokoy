shader_type spatial;
// 牙通牙旋鑽 —— 山犬 Gatsuga 突進時「取代」本體的不透明鑽體。
//
// ⚠ 第一版用 blend_add 半透明渦流「包住」本體，失敗了：加法混合本質是透明的，
//   條紋加密到 30、加底噪、加內層殼、前端收尖，狼的頭尾照樣穿透出來（四輪都沒救回）。
//   README 早就寫了「本體動畫是側翻而非真正捲成鑽頭，必須遮蔽」——
//   正解是**不要遮，是換掉**：旋轉段把狼的網格整個隱藏，只顯示這個鑽。
//   這也是這類招式在遊戲裡的實際做法，看不見角色本人才對。
//
// 純程序化，無外部貼圖。
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.80, 0.87, 0.96, 1.0);
// 槽底要夠暗才看得出溝；太亮整根會糊成一片白錐
uniform vec4 groove_color : source_color = vec4(0.12, 0.18, 0.28, 1.0);
uniform vec4 rim_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
// 0–1：整體顯現。0 時完全不畫（用 discard，不留半透明殘影）
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// 螺旋槽的旋轉速度（轉/秒）
uniform float spin_speed : hint_range(0.0, 30.0) = 11.0;
// 螺旋槽數量
uniform float grooves : hint_range(2.0, 24.0) = 12.0;
// 槽的傾斜（沿軸前進幾圈）。
// ⚠ 這個值要**小於** grooves，否則沿軸的相位變化蓋過繞圈的相位，
//   螺旋會退化成一圈圈垂直橫紋（實測 grooves=9 / twist=4.5 就已經是橫紋）。
//   但也不能太小：grooves=5 / twist=1.1 時槽淺到幾乎看不見（一根光滑錐）。
//   12 / 3.0 實測是「明顯斜螺旋」的甜蜜點。
uniform float twist : hint_range(0.1, 8.0) = 3.0;
uniform float noise_scale : hint_range(1.0, 30.0) = 9.0;

varying vec2 uv;
varying vec3 vnormal;
varying vec3 vview;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	uv = UV;
	vnormal = NORMAL;
	vview = VERTEX;
}

void fragment() {
	if (intensity < 0.02) {
		discard;
	}
	float around = uv.x;
	float along = uv.y;
	float t = TIME * spin_speed;

	// 螺旋槽：around 乘 grooves 決定幾條槽；along 只乘 twist（不再乘 grooves），
	// 這樣沿軸的扭轉才是「傾斜」而不是「加密」。
	float helix = fract(around * grooves + along * twist + t);
	float groove = abs(helix - 0.5) * 2.0;          // 0 = 槽底、1 = 脊頂
	// ⚠ 不要用 pow 做斷面：0.65 太平、1.5 又把對比壓沒了（實測兩次都糊成白錐）。
	//   用 smoothstep 給硬一點的邊，槽與脊之間才有明確落差。
	groove = smoothstep(0.12, 0.62, groove);

	// 高速旋轉的塵土質感
	float grit = vnoise(vec3(around * noise_scale * 4.0, along * noise_scale, t * 2.5));

	vec3 col = mix(groove_color.rgb, base_color.rgb, groove);
	col = mix(col, col * (0.85 + grit * 0.3), 0.45);

	// 槽底的高速光紋：讓鑽看起來在轉，不是一根靜止的錐
	float spark = smoothstep(0.82, 1.0, vnoise(vec3(around * 26.0, along * 9.0 - t * 3.0, t * 4.0)));
	col = mix(col, rim_color.rgb, spark * (1.0 - groove) * 0.7);

	// 邊緣光：側面輪廓打亮，讓鑽體在暗背景也讀得出剪影
	float fres = pow(1.0 - abs(dot(normalize(vnormal), normalize(-vview))), 2.2);
	col = mix(col, rim_color.rgb, fres * 0.55);

	ALBEDO = col;
	ROUGHNESS = 0.45;
	METALLIC = 0.0;
	// 槽底與邊緣微微自發光，暗處才有速度感；不要整體發光（第一版就是這樣爆白）
	EMISSION = rim_color.rgb * (fres * 0.35 + (1.0 - groove) * 0.12 + spark * 0.5) * intensity;
	// 淡入淡出靠 alpha scissor，避免半透明排序問題
	ALPHA = intensity;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}
