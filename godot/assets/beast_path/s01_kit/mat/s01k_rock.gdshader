// 獸道 S01 Blender 環境資產 Kit 的岩材質（R4 Demo）：從 bp_rock.gdshader（S04 共用，唯讀）複製出來改，S04 不受影響。
// 與 bp_rock 相同：P7 地面陣列第 5 層（lichen_rock）三平面兩尺度、雨痕、苔（COLOR.r）、環境遮蔽（COLOR.g）、色差（COLOR.b）、腳邊泥土（COLOR.a）。
// 改動（使用者 S01 R2/R3 審圖：「重複的短水平岩紋」）：
//   · 拿掉世界 Y 的層理明暗帶（S01 新岩的形狀已經有斜的節理面，不再靠水平色帶假裝岩層）；
//   · 改成沿岩面法線方向的低頻色斑（面與面之間有冷暖差，岩塊讀得出來）；
//   · 苔多一點、偏黃綠（避免藍天環境光下變青色）；瀑布濕潤保留參數但預設關（S01 沒有瀑布）。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.26;
uniform float tile = 2.0;
uniform vec3 moss_col : source_color = vec3(0.24, 0.33, 0.09);
uniform vec3 foot_col : source_color = vec3(0.16, 0.115, 0.075);
uniform vec4 wet_src = vec4(0.0, 0.0, 1.0, 0.0);           // 瀑布：xz 中心、半徑、強度（S01 沒有瀑布＝強度 0）
uniform float tone = 0.92;                                  // 岩色整體明度（相對崖面地形）

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 P = wpos;
	vec3 N = normalize(wnrm);
	vec3 dPx = dFdx(P);
	vec3 dPy = dFdy(P);
	vec3 tb = pow(abs(N), vec3(4.0));
	tb /= (tb.x + tb.y + tb.z);
	float T0 = tile;
	float T1 = tile * 2.65;
	// ---- 三平面 × 兩個尺度
	vec3 a0 = textureGrad(albedo_arr, vec3(P.zy / T0, 5.0), dPx.zy / T0, dPy.zy / T0).rgb * tb.x
			+ textureGrad(albedo_arr, vec3(P.xz / T0, 5.0), dPx.xz / T0, dPy.xz / T0).rgb * tb.y
			+ textureGrad(albedo_arr, vec3(P.xy / T0, 5.0), dPx.xy / T0, dPy.xy / T0).rgb * tb.z;
	vec3 a1 = textureGrad(albedo_arr, vec3(P.zy / T1 + 0.37, 5.0), dPx.zy / T1, dPy.zy / T1).rgb * tb.x
			+ textureGrad(albedo_arr, vec3(P.xz / T1 + 0.61, 5.0), dPx.xz / T1, dPy.xz / T1).rgb * tb.y
			+ textureGrad(albedo_arr, vec3(P.xy / T1 + 0.13, 5.0), dPx.xy / T1, dPy.xy / T1).rgb * tb.z;
	vec4 n0x = textureGrad(nrh_arr, vec3(P.zy / T0, 5.0), dPx.zy / T0, dPy.zy / T0);
	vec4 n0y = textureGrad(nrh_arr, vec3(P.xz / T0, 5.0), dPx.xz / T0, dPy.xz / T0);
	vec4 n0z = textureGrad(nrh_arr, vec3(P.xy / T0, 5.0), dPx.xy / T0, dPy.xy / T0);
	vec2 tx = (n0x.rg * 2.0 - 1.0);
	vec2 ty = (n0y.rg * 2.0 - 1.0);
	vec2 tz = (n0z.rg * 2.0 - 1.0);
	// UDN 重定向
	vec3 nx_ = vec3(N.x, tx.y + N.y, tx.x + N.z);
	vec3 ny_ = vec3(ty.x + N.x, N.y, -ty.y + N.z);
	vec3 nz_ = vec3(tz.x + N.x, tz.y + N.y, N.z);
	vec3 Nn = normalize(nx_ * tb.x + ny_ * tb.y + nz_ * tb.z);
	float hgt = n0x.b * tb.x + n0y.b * tb.y + n0z.b * tb.z;

	vec3 alb = mix(a0, a1, 0.38) * tone * vec3(1.07, 1.0, 0.86);        // 天空環境光偏藍 → 岩色預先往暖灰褐偏一點，陰影面才不會變成藍灰片
	vec4 nb = texture(noise_tex, P.xz / 47.0 + P.y / 83.0);
	vec4 nm = texture(noise_tex, P.xz / 11.0 + vec2(P.y / 7.0, 0.3));
	alb *= mix(0.80, 1.16, nb.r) * mix(0.92, 1.08, nm.r);

	// ---- 面的色差：依岩面朝向（法線）＋低頻斑，不依世界高度（不出水平色帶）
	float facet = dot(N, normalize(vec3(0.43, 0.21, -0.88))) * 0.5 + 0.5;
	alb *= mix(0.90, 1.08, facet) * mix(0.94, 1.06, vcol.b);
	alb = mix(alb, alb * vec3(1.06, 0.99, 0.90), smoothstep(0.35, 0.75, nm.g) * 0.5);

	// ---- 雨痕：垂直拉長的暗流痕（只在近垂直的面）
	vec2 sp = vec2(P.x + P.z, P.y * 0.10);
	float streak = texture(noise_tex, sp * 0.9 + vec2(0.27, 0.0)).b;
	float side = 1.0 - smoothstep(0.35, 0.85, N.y);
	alb *= 1.0 - 0.34 * smoothstep(0.52, 0.80, streak) * side;

	// ---- 瀑布濕潤：整面變暗、粗糙度降低
	float wd = distance(P.xz, wet_src.xy);
	float wet = (1.0 - smoothstep(wet_src.z * 0.35, wet_src.z, wd + (nm.g - 0.5) * 3.0)) * wet_src.w * smoothstep(0.0, 4.0, P.y - 10.5);
	wet = clamp(wet + 0.15 * smoothstep(0.62, 0.8, streak) * side, 0.0, 1.0);
	alb *= mix(1.0, 0.52, wet);

	// ---- 苔（上向面；vcol.r 為建造時算的苔量）
	float mm = vcol.r * (0.45 + 0.9 * nm.g) + (nb.b - 0.5) * 0.45 * vcol.r;
	float moss_m = smoothstep(0.26, 0.58, mm) * smoothstep(0.02, 0.6, N.y + (nm.g - 0.5) * 0.35);
	moss_m = max(moss_m, wet * 0.28 * smoothstep(0.3, 0.7, nm.b));
	vec3 mcol = moss_col * mix(0.62, 1.3, nm.b);
	alb = mix(alb, mcol * 3.4 * (0.4 + 0.6 * dot(alb, vec3(0.333))), moss_m * 0.85);

	// ---- 腳邊泥土
	float foot = vcol.a * smoothstep(0.15, 0.7, nb.g + 0.25 * hgt + 0.2);
	alb = mix(alb, foot_col * mix(0.8, 1.35, nm.r) / max(ground_k, 0.01) * 0.62, foot * 0.9);

	float rough = mix(0.84, 0.97, nb.g);
	rough = mix(rough, 0.97, moss_m);
	rough *= mix(1.0, 0.55, wet);

	ALBEDO = alb * ground_k;
	NORMAL = normalize((VIEW_MATRIX * vec4(Nn, 0.0)).xyz);
	ROUGHNESS = clamp(rough, 0.2, 1.0);
	SPECULAR = 0.25 + 0.25 * wet;
	AO = vcol.g;
	AO_LIGHT_AFFECT = 0.55;
}
