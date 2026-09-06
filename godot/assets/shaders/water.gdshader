// 河水 —— 雙層法線捲動（速度/方向不同才不會看出平舖）、
// 深淺兩色依視角混合、岸邊靠頂點色 R 做泡沫。
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D wave_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.36, 0.52, 0.50);
uniform vec3 deep_color : source_color = vec3(0.10, 0.20, 0.26);
uniform float flow_speed = 0.05;
uniform float wave_scale = 0.25;
uniform float alpha = 0.86;
// 沒有頂點色的 mesh（CylinderMesh 池塘）COLOR 預設是白的 →
// bank=1 → 整片判定成岸邊泡沫 → 看起來像鐵板。這個係數設 0 就純深水。
uniform float bank_scale = 1.0;
// 岸邊的清透帶寬度（頂點色 R = 靠岸程度）。
// ⚠ 別再拿 hint_depth_texture 算水深：這個材質是 depth_draw 的，
// 深度貼圖裡讀到的是水面自己，算出來的水深恆為 0 → 整片變成白泡沫。
uniform vec3 sky_tint : source_color = vec3(0.62, 0.74, 0.86);
// 1 = 頂點色 GB 帶有流向（東大河：gen_terrain_river.gd 烘進去的下游方向，
// 0.5 為零點）。舊 mesh（池塘、白色 COLOR）GB=1 會解碼成假流向，所以
// 預設 0 走舊的固定軸捲動，只有東大河的材質把它設成 1。
uniform float use_flow_vc = 0.0;
uniform float flow_strength = 1.0;
// 岸邊清透帶的不透明度下限。太低的話淺水帶幾乎全透，波紋法線沒有
// 顏色可以打亮，讀起來就是一片平的淺色。預設 0.42 維持東大河原樣，
// 幹渠材質調高到 0.6 左右讓岸邊也看得出起伏。
uniform float shore_alpha : hint_range(0.0, 1.0) = 0.42;
// 泡沫的粗糙度上限。ROUGHNESS 一被推高，反射就糊掉、波紋跟著消失；
// 岸邊 bank 高的地方永遠被泡沫壓住，是「淺水帶沒有波紋」的主因。
uniform float foam_roughness : hint_range(0.0, 1.0) = 0.30;
// ⚠ 落水／跌水專用：alpha 的噪聲撕裂強度。0 = 關（大河、幹渠維持原樣）。
// 為什麼需要它：不論 mesh 做成矩形、梯形還是毛邊扇形，只要 ALPHA 是頂點
// 色的平滑內插，輪廓就是一條連續曲線，永遠讀成「一片硬邊板子／布料」。
// 撕裂必須發生在 fragment 上。這裡拿波紋貼圖當噪聲源沿流向捲動，把
// alpha 打散成斷續的水絲與飛沫，順便讓邊緣逐點消失而不是整條收邊。
uniform float shred : hint_range(0.0, 1.0) = 0.0;
uniform float shred_scale = 3.0;
uniform float shred_speed = 1.0;

varying float bank;      // 頂點色 R：1=岸邊、0=中央
varying vec2 flow_dir;   // 頂點色 GB：局部下游方向

// 自製 value noise。⚠ 不要拿 wave_nor 當噪聲源：實測那張法線貼圖
// R/G 的 std 只有 0.07、B（法線 Z）mean=0.962，任何門檻都會讓 99% 的
// 像素落在同一側 —— 撕裂看起來「沒生效」正是這個原因，不是參數沒調對。
float _h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h21(i), _h21(i + vec2(1.0, 0.0)), u.x),
	           mix(_h21(i + vec2(0.0, 1.0)), _h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	bank = COLOR.r * bank_scale;
	flow_dir = COLOR.gb * 2.0 - 1.0;
	// 水面微微起伏（河不是鏡子）
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 0.9 + wp.x * 0.6 + wp.z * 0.4) * 0.025
		+ sin(TIME * 1.7 + wp.z * 1.1) * 0.015;
}

void fragment() {
	vec2 uv = (NODE_POSITION_WORLD.xz + VERTEX.xz) * wave_scale;
	vec3 n1;
	vec3 n2;
	if (use_flow_vc > 0.5) {
		// Flow-map 捲動：沿頂點色裡的下游方向推 UV。單相位會把貼圖越拉越
		// 遠，所以用兩個相位交錯採樣、鋸齒權重交叉淡入淡出（經典 flow map
		// 手法）——貼圖永遠只位移半個週期內，不會糊掉。
		vec2 fdir = normalize(flow_dir + vec2(1e-5)) * flow_strength;
		float cycle = 6.0;
		float t1 = fract(TIME * flow_speed / cycle);
		float t2 = fract(TIME * flow_speed / cycle + 0.5);
		float w1 = abs(t1 * 2.0 - 1.0);
		vec2 push1 = fdir * t1 * cycle;
		vec2 push2 = fdir * t2 * cycle;
		vec3 a1 = texture(wave_nor, uv - push1 * wave_scale).rgb;
		vec3 b1 = texture(wave_nor, uv - push2 * wave_scale).rgb;
		n1 = mix(a1, b1, w1);
		vec3 a2 = texture(wave_nor, uv * 1.7 - push1 * wave_scale * 1.55).rgb;
		vec3 b2 = texture(wave_nor, uv * 1.7 - push2 * wave_scale * 1.55).rgb;
		n2 = mix(a2, b2, w1);
	} else {
		n1 = texture(wave_nor, uv + vec2(0.0, TIME * flow_speed)).rgb;
		n2 = texture(wave_nor, uv * 1.7 + vec2(TIME * flow_speed * 0.6, TIME * flow_speed * 1.3)).rgb;
	}
	NORMAL_MAP = normalize(n1 + n2 * 0.7);
	NORMAL_MAP_DEPTH = 0.55;

	// 「水深」用頂點色代替：bank=1 是岸、0 是中央。
	float dfac = clamp(1.0 - bank, 0.0, 1.0);
	dfac = dfac * dfac;                             // 岸邊那一小段才清透

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.5);
	// 淺處偏清透、深處偏濃，再依視角疊一層天光反射 ——
	// 少了這層反射，水就是一塊固定顏色的色板（「像鐵板」）
	vec3 col = mix(shallow_color, deep_color, dfac);
	col = mix(col, sky_tint, fres * 0.45);
	// 岸邊泡沫：不再是一條連續死白帶（之前的「水線亮邊」就是它）。
	// 拿波紋貼圖沿流向捲一層雜訊把它撕成斷續的舔岸段，並整體壓暗。
	float foam = smoothstep(0.90, 1.0, bank);
	if (use_flow_vc > 0.5) {
		vec2 fdir2 = normalize(flow_dir + vec2(1e-5));
		float lap = texture(wave_nor, uv * 0.55 - fdir2 * TIME * flow_speed * 2.2).g;
		foam *= smoothstep(0.30, 0.75, lap);
	}
	ALBEDO = mix(col, vec3(0.82, 0.87, 0.85), foam * 0.40);
	ROUGHNESS = mix(0.05, foam_roughness, foam);
	METALLIC = 0.0;
	SPECULAR = 0.75;
	// 岸邊半透（看得到淺灘），中央接近不透明
	ALPHA = clamp(mix(shore_alpha, alpha, dfac) + foam * 0.22, 0.0, 1.0);
	// 落水撕裂：兩層不同尺度/速度的噪聲相乘，得到斷續的水絲。
	// bank 越高（越靠落點/邊緣）撕得越兇，中心的水體保持完整，
	// 所以水舌不會整片消失，只有外圍散成飛沫。
	if (shred > 0.001) {
		vec2 sdir = normalize(flow_dir + vec2(1e-5));
		// ⚠ 用 xz 當噪聲 UV 對「水舌」是錯的：水舌近乎垂直，整段下墜
		// 的 XZ 幾乎不變 → 噪聲沿高度是常數 → 只會整體變淡（羽化），
		// 撕不出斷續水絲。把 y 併進 UV，垂直面才有變化。
		vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 suv = vec2(wpos.x + wpos.z, wpos.y * 2.0 - wpos.z) * shred_scale;
		float t = TIME * shred_speed;
		// 三個八度，各自沿流向漂移。用自製 value noise（滿 0..1），
		// 不是法線貼圖——後者對比不足，門檻永遠只落在一側。
		float n = _vnoise(suv - sdir * t * 0.7) * 0.55
		        + _vnoise(suv * 2.3 + sdir.yx * t * 0.5) * 0.30
		        + _vnoise(suv * 5.1 - sdir * t * 1.6) * 0.15;
		// 陡峭門檻 → 接近二值，才會斷成一塊一塊而不是一層均勻薄膜。
		float mask = smoothstep(0.44, 0.56, n);
		// 邊緣（bank→1）全力撕，內部只輕微擾動。
		float bite = shred * mix(0.20, 1.0, clamp(bank, 0.0, 1.0));
		ALPHA *= mix(1.0, mask, bite);
		// 撕開的邊緣同時提亮，讀成飛沫而不是破洞。
		ALBEDO = mix(ALBEDO, vec3(0.94, 0.96, 0.97), (1.0 - mask) * bite * 0.6);
	}
}
