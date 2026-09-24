extends RefCounted
## 人間之里 V2 — P2 Water：河道形態（水線以下河床深度分布），產生器與驗證共用。
##
## 參數在 layout_v2.json 的 water_form（不在 Macro 凍結範圍；水位四鍵照舊凍結）。
## 做法：P1 核准的河床深度 d0（水位 − 地面，只在水面下 > 0）乘上形態倍率 m：
##   d1 = d0 · m_eff，m_eff 在水線附近（d0 < blend_d0[0]）＝1、到 blend_d0[1] 才全量。
##   → 水線位置、水線以上岸坡完全不動；岸線附近一個斜率連續的過渡；m > 0 → 不會出現負水深。
## 倍率不是噪訊，只由河道幾何決定：
##   沿河曲率 b（−1…1，符號＝彎心那側）：彎道 |b|→1 深潭、直段／反曲點 |b|→0 較淺的主槽；
##   深槽偏向外岸（彎心反側）thalweg_shift·b；內岸（彎心側）淺灘 bar。
##   西溪另加潭瀨節奏：每 pool_spacing 公尺一潭（約 6–7 倍河寬，自然溪流的潭瀨間距）。
##   水渠（人工）：工程深度穩定，只在彎角（小幅）與 pits（水車輪坑、取水口）加深。

## 折線每 1 m 一站的簽名曲率（1/m）：±win 公尺的走向差 ÷ 弧長。正＝往 cross > 0 那側轉。
static func curvature(pts: PackedVector2Array, win: float) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
	var total := cum[cum.size() - 1]
	var n := int(ceil(total)) + 1
	var head := PackedFloat32Array()
	head.resize(n)
	var prev := 0.0
	for i in n:
		var a := _along(pts, cum, maxf(float(i) - 1.0, 0.0))
		var b := _along(pts, cum, minf(float(i) + 1.0, total))
		var th := atan2(b.y - a.y, b.x - a.x)
		if i > 0:
			th = prev + wrapf(th - prev, -PI, PI)
		head[i] = th
		prev = th
	var out := PackedFloat32Array()
	out.resize(n)
	var w := int(round(win))
	for i in n:
		var i0 := maxi(i - w, 0)
		var i1 := mini(i + w, n - 1)
		out[i] = (head[i1] - head[i0]) / maxf(float(i1 - i0), 1.0)
	return out


## 弧長站號：cum＝折線累積長，r＝_near 的 (距離, 段, t)
static func station(cum: PackedFloat32Array, r: Vector3) -> float:
	var k := int(r.y)
	return cum[k] + r.z * (cum[k + 1] - cum[k])


static func cum_len(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
	return cum


## 彎道強度 b：曲率 × 全量彎道半徑，夾在 −1…1
static func bend(F: Dictionary, kap: PackedFloat32Array, s: float) -> float:
	var i := clampi(int(round(s)), 0, kap.size() - 1)
	return clampf(kap[i] * float(F["bend_r_full"]), -1.0, 1.0)


## 形態倍率 m（相對 P1 河床中央深度 nominal）。nu＝簽名橫向位置／半寬（+＝cross > 0 側）
static func factor(F: Dictionary, b: float, nu: float, s: float, nominal: float, p: Vector2) -> float:
	var pool := absf(b)
	if F.has("pool_spacing"):
		# 潭瀨節奏：cos 峰＝潭、谷＝瀨（淺灘）；彎道本身一定是潭
		var rhythm := 0.5 + 0.5 * cos(TAU * s / float(F["pool_spacing"]))
		pool = maxf(pool, float(F["rhythm_w"]) * rhythm)
	var axis := float(F["depth_shallow"]) + (float(F["depth_pool"]) - float(F["depth_shallow"])) * pool
	# 定點深槽（水渠：水車輪坑、取水口）：半徑 r 內加深到 depth
	for pit in F.get("pits", []):
		var d := p.distance_to(Vector2(float(pit["at"][0]), float(pit["at"][1])))
		axis = lerpf(axis, float(pit["depth"]), 1.0 - smoothstep(float(pit["r"]) * 0.5, float(pit["r"]), d))
	var nut := -float(F["thalweg_shift"]) * b
	var sh := float(F["shoulder"])
	var ch := sh + (1.0 - sh) * exp(-pow((nu - nut) / float(F["channel_w"]), 2.0))
	var inner := signf(b) * nu
	var bar := 1.0 - float(F["bar"]) * absf(b) * smoothstep(0.0, 0.8, inner)
	return clampf(axis * ch * bar / nominal, float(F["m_min"]), float(F["m_max"]))


## 水線附近淡入：d0 < blend_d0[0] 不改、> blend_d0[1] 全量；keep_clear 圈內不改（地標基座等）
static func blend(F: Dictionary, m: float, d0: float, p: Vector2) -> float:
	var bd: Array = F["blend_d0"]
	var w := smoothstep(float(bd[0]), float(bd[1]), d0)
	for kc in F.get("keep_clear", []):
		var r := float(kc["r"])
		w *= smoothstep(r, r + 3.0, p.distance_to(Vector2(float(kc["at"][0]), float(kc["at"][1]))))
	return lerpf(1.0, m, w)


static func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var seg := maxf(cum[k + 1] - cum[k], 1e-6)
			return pts[k].lerp(pts[k + 1], clampf((s - cum[k]) / seg, 0.0, 1.0))
	return pts[0]
