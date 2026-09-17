shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// 日之呼吸刀光 —— 外焰／主火弧層。
// 原創程序美術：不含任何第三方貼圖或動畫影格擷取。
//
// 為什麼是 blend_mix 而不是 blend_add：
//   動畫式火焰的辨識度來自「深赤色實色外輪廓」。純 ADD 會把暗色通通加成亮色，
//   輪廓被沖掉，結果看起來像一團光而不是火。實色邊必須靠 mix 保住。
//   白熱核心才走 ADD（見 sun_flame_core.gdshader）。
//
// UV 約定（由 sword_trail.gd 供給）：
//   UV.x = 刀尖累積行進距離（公尺）。用累積距離而非索引，舊取樣點淘汰時火焰不會重貼。
//   UV.y = 0 在刀根、1 在刀尖方向。火舌沿 +y 長出去。

// 五層色階：白熱核心 → 金黃 → 橙黃琥珀 → 朱紅 → 暗紅褐。
uniform vec4 core_color : source_color = vec4(1.000, 0.984, 0.910, 1.0);  // #FFFBE8
uniform vec4 gold_color : source_color = vec4(1.000, 0.847, 0.290, 1.0);  // #FFD84A
uniform vec4 amber_color : source_color = vec4(1.000, 0.616, 0.110, 1.0); // #FF9D1C
uniform vec4 crimson_color : source_color = vec4(0.914, 0.212, 0.110, 1.0); // #E9361C
uniform vec4 ember_color : source_color = vec4(0.231, 0.090, 0.075, 1.0); // #3B1713

// 火舌沿刀軌捲動的速度。捲動方向必須沿 u（刀軌向），
// 捲錯軸會看起來像「貼圖在飄」而不是「火在燒」。
uniform float flow_speed : hint_range(0.0, 6.0) = 1.9;
// 每公尺刀軌重複幾次火舌。越高火舌越密越碎。
uniform float tile : hint_range(0.5, 12.0) = 3.4;
uniform float emission_strength : hint_range(0.0, 6.0) = 2.2;
// 火舌邊緣的過渡帶寬。小 = 尖銳圖形化（動畫感），大 = 柔軟寫實。
// 參考圖是尖銳硬邊 + 外圍柔光，所以預設壓得很小。
uniform float edge_sharpness : hint_range(0.004, 0.30, 0.002) = 0.030;
// 火舌之間 V 形凹口的深度。0 = 平整色帶，1 = 深裂。
uniform float notch_depth : hint_range(0.0, 1.0) = 0.62;
// 火舌整體高度（佔 ribbon 寬度的比例）。
uniform float flame_height : hint_range(0.1, 1.2) = 0.86;
// 尖端被速度往後拖的量。這是「揮刀殘影」而不是「靜止火堆」的關鍵。
uniform float drag : hint_range(0.0, 1.5) = 0.55;
// 外緣的暗紅描邊厚度。0 = 無描邊（會變回一團光）。
uniform float rim_width : hint_range(0.0, 0.5) = 0.17;
// 整層透明度上限，給腳本分層控制。
uniform float layer_alpha : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

// 火舌高度輪廓：多頻尖峰疊加。
// pow(abs(sin),小指數) 給出的是「尖峰 + V 形凹口」，正是動畫火焰的剪影特徵；
// 純 sin 會得到圓滑波浪，讀起來像水不像火。
float tongue_profile(float x) {
	float a = pow(abs(sin(x * 1.00)), 0.45);
	float b = pow(abs(sin(x * 2.30 + 1.7)), 0.60) * 0.55;
	float c = pow(abs(sin(x * 4.70 + 0.3)), 0.80) * 0.28;
	float peaks = (a + b + c) / 1.83;
	return mix(1.0 - notch_depth, 1.0, peaks);
}

void fragment() {
	float y = clamp(UV.y, 0.0, 1.0);
	// 尖端比根部捲得快 —— 火舌被揮刀速度往後拉出傾斜。
	float x = UV.x * tile - TIME * flow_speed * (1.0 + y * drag);

	// 火舌上緣
	float edge = tongue_profile(x) * flame_height;
	// 細節侵蝕：讓邊緣不是完美數學曲線，並在尖端撕出少量細絲。
	float detail = noise2(vec2(x * 2.6, y * 3.2 + TIME * 0.6));
	edge += (detail - 0.5) * 0.10 * (0.35 + y);

	// 本體遮罩：根部貼齊刀身（硬切），上緣尖銳收邊。
	float root = smoothstep(0.0, 0.035, y);
	float body = root * (1.0 - smoothstep(edge - edge_sharpness, edge, y));

	// 火舌之間再挖一次橫向斷口，避免整條連成一片。
	float gap = pow(max(0.0, sin(x * 1.9 + 0.8)), 6.0);
	body *= 1.0 - gap * smoothstep(0.18, 0.75, y) * 0.75;

	// 沿火舌高度取色：根部白熱 → 尖端暗紅褐。
	float t = clamp(y / max(edge, 0.001), 0.0, 1.0);
	vec3 ink = core_color.rgb;
	ink = mix(ink, gold_color.rgb, smoothstep(0.04, 0.24, t));
	ink = mix(ink, amber_color.rgb, smoothstep(0.20, 0.52, t));
	ink = mix(ink, crimson_color.rgb, smoothstep(0.46, 0.80, t));
	ink = mix(ink, ember_color.rgb, smoothstep(0.80, 1.00, t));

	// 外緣描邊：最外側一圈壓成暗紅褐實色，這是動畫感的來源。
	float rim = smoothstep(edge - rim_width, edge - edge_sharpness, y);
	ink = mix(ink, ember_color.rgb, rim * 0.72);

	// 發光只給根部白熱區，外緣保持實色不進 bloom，輪廓才不會被泛光吃掉。
	float hot = 1.0 - smoothstep(0.0, 0.42, t);

	ALBEDO = ink;
	EMISSION = ink * emission_strength * (0.10 + hot * 0.90);
	ALPHA = clamp(body, 0.0, 1.0) * COLOR.a * layer_alpha;
}
