// 博麗神社 r3 地形：terrain_pbr 的雙面投影版。
// 原版只用世界 xz 平面投影，陡坡（>30°）上貼圖會被沿坡向拉長成「橫紋」。
// 這版在坡度 20°~37° 之間逐步混入側面（x/z）投影的反照率，平地仍只取樣 1 次。
// 法線貼圖維持頂面投影（陡處把強度降下來）。其餘 uniform 與 terrain_pbr 相同，可直接互換材質。
shader_type spatial;

uniform sampler2D grass_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float dirt_amount = 1.0;
uniform float dirt_cover = 0.0;
uniform float dirt_tile = 0.9;
uniform vec3 dirt_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 dirt_base_color : source_color = vec3(0.0);
uniform float dirt_texture_strength : hint_range(0.0, 1.0) = 1.0;
uniform float dirt_normal_strength : hint_range(0.0, 1.0) = 0.45;
uniform float dirt_raw_texture : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform float tile = 0.12;
uniform float path_tile = 4.2;
uniform float forest_tile = 1.4;
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 forest_tint : source_color = vec3(0.78, 0.84, 0.66);
uniform float side_start = 0.06;
uniform float side_end = 0.20;
uniform vec3 path_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float dirt_var : hint_range(0.0, 0.5) = 0.0;   // 夯土的大尺度明暗與潮濕處（0＝關）
uniform sampler2D petal_mask : filter_linear, repeat_disable;   // R8：落花密度（世界矩形 petal_rect）
uniform vec4 petal_rect = vec4(0.0, 0.0, 1.0, 1.0);             // x0, z0, 寬, 深（世界公尺）
uniform float petal_amount : hint_range(0.0, 1.0) = 0.0;
// 玩家範圍外的地面改成與中景／遠景相同的林冠質感（近景邊緣與外圍山體接縫消失）
uniform sampler2D canopy_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float canopy_tile = 0.0045;
uniform vec4 canopy_play = vec4(-57.0, -66.0, 57.0, 80.0);   // 玩家範圍矩形 x0, z0, x1, z1
uniform vec2 canopy_fade = vec2(2.0, 22.0);                  // 離矩形多少 m 開始混、多少 m 全換
uniform float canopy_amount : hint_range(0.0, 1.0) = 0.0;
uniform float canopy_mul = 1.0;

varying vec3 wpos;
varying vec2 map_uv;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_uv = UV;
}

float _h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float _vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h21(i), _h21(i + vec2(1.0, 0.0)), u.x),
			mix(_h21(i + vec2(0.0, 1.0)), _h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 tri(sampler2D t, float sc, float sw, float wx) {
	vec3 top = texture(t, wpos.xz * sc).rgb;
	if (sw < 0.003) {
		return top;
	}
	vec3 sx = texture(t, vec2(wpos.z, wpos.y) * sc).rgb;
	vec3 sz = texture(t, vec2(wpos.x, wpos.y) * sc).rgb;
	return mix(top, mix(sz, sx, wx), sw);
}

void fragment() {
	vec2 duv = wpos.xz * tile;
	float pfw = length(fwidth(wpos.xz * 4.0));        // 花瓣格每像素跨度（導數必須在非分支處取）
	vec4 mk = texture(mask_tex, map_uv);
	vec3 m = mk.rgb;
	float tilt = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float sw = smoothstep(side_start, side_end, tilt);
	float wx = wnrm.x * wnrm.x / (wnrm.x * wnrm.x + wnrm.z * wnrm.z + 0.00001);

	vec3 col = tri(grass_diff, tile, sw, wx) * grass_tint;
	vec3 nor = texture(grass_nor, duv).rgb;
	// 林床
	if (m.g > 0.004) {
		col = mix(col, tri(forest_diff, tile * forest_tile, sw, wx) * forest_tint, m.g);
		nor = mix(nor, texture(forest_nor, duv * forest_tile).rgb, m.g);
	}
	// 夯土
	float global_dirt = clamp(dirt_cover, 0.0, 1.0);
	float dw = max(mk.a * dirt_amount, global_dirt);
	if (dw > 0.004) {
		float uvs = mix(dirt_tile, dirt_tile * 0.62, global_dirt);
		vec3 dcol_raw = tri(dirt_diff, tile * dirt_tile, sw, wx);
		vec3 dcol = tri(dirt_diff, tile * uvs, sw, wx);
		vec3 dcol_wide = texture(dirt_diff, duv * uvs * 0.41 + vec2(17.3, -9.1)).rgb;
		dcol = mix(dcol_wide, dcol, 0.50);
		dcol = mix(vec3(dot(dcol, vec3(0.299, 0.587, 0.114))), dcol, 0.45) * dirt_tint;
		dcol = mix(dirt_base_color, dcol, dirt_texture_strength);
		dcol = mix(dcol, dcol_raw, dirt_raw_texture);
		if (dirt_var > 0.001) {
			// 夯土的大尺度明暗：5 m / 2.3 m / 0.9 m / 0.27 m 四個八度（審圖：2–5 m 尺度的深淺／潮濕斑看不出來）。
			// value noise 多八度相加後分佈集中在 0.5 附近 → 先拉開再當明暗係數。
			float vn = _vn(wpos.xz * 0.19 + 11.3) * 0.36 + _vn(wpos.xz * 0.43) * 0.32 + _vn(wpos.xz * 1.1 + 7.7) * 0.22 + _vn(wpos.xz * 3.7 + 3.1) * 0.10;
			float vt = clamp((vn - 0.5) * 3.8 + 0.5, 0.0, 1.0);
			dcol *= mix(1.0 - dirt_var, 1.0 + dirt_var * 0.55, vt);
			// 潮濕斑：3–6 m 的不規則塊，偏暗偏綠褐（低對比）
			float dn = _vn(wpos.xz * 0.27 + 31.7) * 0.65 + _vn(wpos.xz * 0.61 + 5.5) * 0.35;
			float damp = smoothstep(0.50, 0.72, dn);
			dcol = mix(dcol, dcol * vec3(0.72, 0.84, 0.64), clamp(damp * dirt_var * 3.2, 0.0, 0.9));
		}
		dcol *= mix(1.0 + global_dirt * mix(-0.035, 0.10, m.r), 1.0, dirt_raw_texture);
		col = mix(col, dcol, dw);
		nor = mix(nor, texture(dirt_nor, duv * dirt_tile).rgb, dw);
	}
	// 路徑碎石土
	float path_w = m.r * (1.0 - global_dirt);
	if (path_w > 0.004) {
		col = mix(col, tri(path_diff, tile * path_tile, sw, wx) * path_tint, path_w);
		nor = mix(nor, texture(path_nor, duv * path_tile).rgb, path_w);
	}
	col *= mix(mix(0.82, 1.12, m.b), 1.0, dirt_raw_texture);
	// 落花：細碎花瓣點（約 3–6 cm），密度來自 petal_mask；遠處點小於 1 px 就淡出成整體粉白色調（避免閃爍）
	if (petal_amount > 0.001) {
		vec2 puv = (wpos.xz - petal_rect.xy) / petal_rect.zw;
		if (puv.x > 0.0 && puv.x < 1.0 && puv.y > 0.0 && puv.y < 1.0 && wnrm.y > 0.6) {
			float dens = texture(petal_mask, puv).r * petal_amount;
			if (dens > 0.01) {
				vec2 pc = wpos.xz * 4.0;                       // 格長 25 cm
				vec2 id = floor(pc);
				float r1 = _h21(id);
				vec2 jit = vec2(_h21(id + 3.7), _h21(id + 9.1)) * 0.46 + 0.27;
				vec2 q = fract(pc) - jit;
				q.x *= 0.7 + 0.6 * _h21(id + 1.9);              // 橢圓：長短軸不同
				float dd = length(q);
				float fade = 1.0 - smoothstep(0.10, 0.35, pfw);
				float petal = step(r1, dens * 0.5) * smoothstep(0.20, 0.10, dd);
				vec3 pcol = mix(vec3(0.80, 0.52, 0.60), vec3(0.90, 0.78, 0.79), _h21(id + 5.3));
				col = mix(col, pcol, petal * 0.85 * fade);
				col = mix(col, vec3(0.72, 0.52, 0.55), dens * 0.12 * (1.0 - fade));
			}
		}
	}
	// 玩家範圍外 → 林冠質感（與 shrine_vista.gdshader 同一張貼圖、同一尺度，近景邊緣與中景接縫消失）
	if (canopy_amount > 0.001) {
		vec2 dq = max(vec2(canopy_play.x - wpos.x, canopy_play.y - wpos.z), vec2(wpos.x - canopy_play.z, wpos.z - canopy_play.w));
		float dout = max(dq.x, dq.y);                      // >0＝在玩家矩形外
		float cw = smoothstep(canopy_fade.x, canopy_fade.y, dout) * canopy_amount;
		if (cw > 0.002) {
			vec3 c1 = texture(canopy_tex, wpos.xz * canopy_tile).rgb;
			vec3 c2 = texture(canopy_tex, wpos.xz * canopy_tile * 2.7 + vec2(0.37, 0.61)).rgb;
			col = mix(col, mix(c1, c2, 0.4) * canopy_mul, cw);
		}
	}
	ALBEDO = col;
	NORMAL_MAP = nor;
	NORMAL_MAP_DEPTH = mix(1.1, dirt_normal_strength, global_dirt) * (1.0 - 0.55 * sw);
	float dirt_roughness = mix(0.94, 0.98, m.b) - m.r * global_dirt * 0.02;
	ROUGHNESS = mix(mix(0.95, 0.9, m.r), dirt_roughness, global_dirt);
}
