// 人間之里 V2 P9 R5-3 Upright Grass / Meadow Layer：立ち草の叢（MultiMesh、tools/village_v2_meadow_lib.gd が網格を生成）。
// 頂點資料：
//   COLOR.rgb ＝ 葉色（sRGB；基部の暗さ・葉先の明るさ・枯れ色は網格に焼いてある）× instance color（引擎が乘算）
//   UV.y      ＝ 葉の根元からの割合 0 根 → 1 葉先（風の重み・基部 AO）
//   UV2       ＝ (葉ごとの位相 0–1, 葉の剛さ 0–1：穂茎・羊歯の葉軸は硬い)
//   NORMAL    ＝ 葉面法線を上向きへ寄せたもの（両面とも同じ法線＝裏面が黒くならない）
// 風（Wind-ready）：wind_dir／wind_strength／wind_speed は veg_common と同名の uniform（Global Wind Manager が一括で設定できる）。
//   重みは 根元 0 → 葉先 1（UV.y²）；風向へ進む 12–20 m の草浪（gust）＋葉ごとの小さな揺れ。株全体を左右に振らない。
// 距離の三層：近級（全株）＝ near_fade の間で縮んで消え、中級（間引き・幅広の低面網格）＝ 同じ帯で伸びて現れ mid_fade で消える。
//   距離は主相機 → 株の根元（陰影 pass も同じ＝影も同じ級で消える）。縮小で消すので discard／透明管線を使わない。
// 色彩空間：veg_common と同じく Compatibility（OUTPUT_IS_SRGB）では線形で計算して戻す。
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.3);
// P9 最終値 0.7（2026-10-05 使用者裁定、R5-3 r6c wind review）：樹・竹（veg_common）は wind 0 のため 1.0 では草だけ動きすぎる。
//   将来の全域風系統で樹／竹／草を統一するときに再バランス（Global Wind Manager が同名 uniform を一括設定）
uniform float wind_strength = 0.7;
uniform float wind_speed = 1.0;
// 草浪の振幅（m、葉先・高さ 0.5 m の株あたり）と葉ごとの揺れ
uniform float gust_amp = 0.07;
uniform float flutter_amp = 0.024;
// (消え始め, 消え終わり)：x≥y なら無効。fade_in＝この距離から現れる（中級）、fade_out＝この距離で消える
uniform vec2 fade_in = vec2(0.0, 0.0);
uniform vec2 fade_out = vec2(22.0, 28.0);
// 基部の暗さ（地面との接地・叢の内側の自己遮蔽）
uniform float base_ao = 0.42;
uniform float roughness = 0.82;
uniform float specular = 0.28;
uniform float translucency = 0.2;
// 遠くで葉が 1 px 未満のちらつく點にならないよう、叢を 8→26 m で横に広げる（中級網格も同じ）
uniform float far_widen = 0.25;

varying vec3 v_wn;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

// 2D 値 noise（0–1、世界座標の位相・強さの揺らぎ用）
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float d = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, root);
	float f = 1.0;
	if (fade_in.y > fade_in.x) {
		f *= smoothstep(fade_in.x, fade_in.y, d);
	}
	if (fade_out.y > fade_out.x) {
		f *= 1.0 - smoothstep(fade_out.x, fade_out.y, d);
	}
	// 縮むときは高さを先に、幅は後から（遠くで「点」にならず低くなって消える）
	VERTEX.y *= f;
	VERTEX.xz *= mix(0.35, 1.0, f) * step(0.001, f) * (1.0 + far_widen * smoothstep(8.0, 26.0, d));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wind_strength > 0.0) {
		float k = UV.y * UV.y * (1.0 - 0.65 * UV2.y);
		vec3 wd = normalize(vec3(wind_dir.x, 0.0, wind_dir.z) + vec3(1e-4, 0.0, 0.0));
		vec2 wd2 = wd.xz;
		float t = TIME * wind_speed;
		// 風向へ流れる草浪：低周波 2 本の和を 0–1 に（強い所＝明るく倒れる帯）。世界座標の値 noise（~6 m、風下へ流れる）で
		//   波の強さを場所ごとに揺らす（隣の株とは相関するが、全面が同期して左右に揺れない）
		float along = dot(root.xz, wd2);
		float across = dot(root.xz, vec2(-wd2.y, wd2.x));
		// wind review r6：波頭を低周波 noise で歪める（~30 m・~11 m）＝15 m ごとに同じ縞が規則正しく並ばない（風下 32 m の相関 0.49 → 0.11）
		along += 9.0 * vnoise(root.xz * 0.035 + vec2(3.1, 7.7)) + 4.0 * vnoise(root.xz * 0.09);
		// 葉ごとに草浪の到達を最大 0.35 s 遅らせる（同じ叢の葉が完全に同期しない：相関 0.97 → 0.91）
		float tg = t + 0.35 * UV2.x;
		float gust = 0.5 + 0.32 * sin(along * 0.42 - tg * 1.6 + sin(across * 0.13) * 1.7) + 0.18 * sin(along * 0.95 + across * 0.31 - tg * 2.3);
		gust *= 0.55 + 0.9 * vnoise(root.xz * 0.17 - wd2 * t * 0.35);
		float ph = UV2.x * 6.2831853 + vnoise(root.xz * 0.8) * 4.0;
		float flut = sin(t * 4.1 + ph + root.x * 1.3 + root.z * 0.7);
		vec3 off = wd * (gust_amp * (0.35 + 0.65 * gust)) * k * wind_strength * 2.0;
		vec3 side = vec3(-wd.z, 0.0, wd.x);
		off += (side * 0.6 + wd * 0.4) * flutter_amp * flut * k * wind_strength;
		off.y -= length(off.xz) * 0.35 * UV.y;
		wp += off;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	}
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = s2l(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)));
	c *= mix(base_ao, 1.0, smoothstep(0.0, 0.45, UV.y));
	ALBEDO = OUTPUT_IS_SRGB ? l2s(c) : c;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	BACKLIGHT = c * translucency;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_wn, 0.0)).xyz);
}
