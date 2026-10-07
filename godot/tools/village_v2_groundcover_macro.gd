extends RefCounted
## 人間之里 V2 P9 R5 Macro Pilot（Major Rework：Macro-readable Ground Dressing）。
##   三區だけ：A 村內大型空地（南の草地）／B 農田→村落交界（水渠北段）／C 住宅背面・後院（東北聚落）。
##   主役＝3–15 m 級の地面構圖（踏み固めた小径・踏み荒らし・作業場・雨落ち・渠／田の濕った草溝・枯れ草／濃い草の斑）＋縁だけの丈の高い草の塊。
##   小草・小花は近景の點綴だけ。Pilot（r10f）と封存區・P7 核心と構件・P8 農田內部・水面・建物・frontage は觸らない。
##   gc_macro.gdshader（gc_ground 衍生；CUSTOM0＝枯れ草・踏まれた草）。全村 r5 は三區の中を VL.MACRO_ZONES で譲る（緣 4 m 交叉淡化）。

const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SHADER := "res://assets/village_v2/groundcover/gc_macro.gdshader"
const SEED_M := 7301
const STEP := 0.33
const FADE := 4.0

## 小径（polyline と幅 m）・作業場／踏み荒らし（中心・半径・種類）——三區の實測（建物 OBB の背面・渠の取水點・橋頭・道路接點）から設計
const DESIGN := {
	"A": {
		"paths": [
			[[Vector2(250.9, 89.6), Vector2(258.0, 91.0), Vector2(266.0, 94.2), Vector2(277.0, 97.2), Vector2(289.5, 99.6)], 1.15],
			[[Vector2(251.6, 80.4), Vector2(256.5, 82.6), Vector2(261.0, 86.5), Vector2(265.5, 93.6)], 0.95],
			[[Vector2(245.2, 112.5), Vector2(252.0, 109.5), Vector2(259.0, 104.0), Vector2(265.0, 97.5)], 0.95],
			[[Vector2(297.0, 79.0), Vector2(294.0, 88.0), Vector2(291.5, 96.0), Vector2(289.0, 104.0), Vector2(286.5, 112.0), Vector2(284.5, 121.0)], 0.8],
		],
		"spots": [[Vector2(253.5, 89.3), 2.9, "work"], [Vector2(252.2, 79.6), 2.4, "work"], [Vector2(247.4, 120.6), 2.3, "work"],
			[Vector2(289.0, 99.4), 3.0, "trample"], [Vector2(266.0, 94.5), 1.8, "trample"]],
		"canal": true, "field": false, "lawn": true, "yard": false, "treeline": true,
	},
	"B": {
		"paths": [
			[[Vector2(341.2, -125.5), Vector2(340.6, -118.0), Vector2(339.6, -110.0), Vector2(338.6, -100.0), Vector2(337.8, -92.0), Vector2(337.4, -86.0)], 1.7],
			[[Vector2(330.2, -113.4), Vector2(333.5, -110.5), Vector2(338.4, -108.0)], 1.2],
			[[Vector2(322.6, -113.0), Vector2(325.5, -109.0), Vector2(331.0, -106.5), Vector2(338.0, -104.5)], 1.0],
		],
		## （m3）田側の農路は P8 外埂（常走＝踏み固め）と凍結農路が担う——平行な小径を足すと「2 本の道」に読める。田側は草溝と出入口の踏み荒らしだけ
		"spots": [[Vector2(322.6, -111.6), 2.7, "work"], [Vector2(330.4, -111.8), 2.3, "work"], [Vector2(341.0, -124.6), 2.8, "trample"],
			[Vector2(365.6, -129.4), 3.4, "trample"]],
		"canal": true, "field": true, "lawn": true, "yard": false, "treeline": false,
	},
	"C": {
		"paths": [
			[[Vector2(451.5, -209.3), Vector2(462.5, -213.8), Vector2(475.0, -217.6), Vector2(488.0, -217.0), Vector2(501.5, -212.5)], 1.25],
		],
		"spots": [],
		"canal": false, "field": false, "lawn": false, "yard": true, "treeline": false,
	},
}


# ─────────────────────────── 文脈 ───────────────────────────

class Wall:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var n := Vector2.ZERO
	var bld := ""
	var back := false


## 三區の文脈：背面の壁（道路向き・frontage でない面）、背戸、農田距離場、小径（背戸からの支線を自動追加）
static func context_m(CV: Dictionary) -> Dictionary:
	var M := {"zones": {}}
	var FS: RLib.TriSampler = CV["FS"]
	var fg := GC.DGrid.new()
	var fbb := (VL.MACRO_ZONES["B"] as Rect2).grow(12.0)
	fg.build(fbb, 0.4, func(q: Vector2) -> bool: return not is_nan(FS.h(q.x, q.y)))
	M["fgrid"] = fg
	for zn: String in VL.MACRO_ZONES:
		var r: Rect2 = VL.MACRO_ZONES[zn]
		var walls: Array = []
		var doors: Array = []
		for o: Dictionary in CV["obb"]:
			if not r.grow(8.0).has_point(o["o"]):
				continue
			var hh: Vector2 = o["h"]
			var front := -1
			var cn := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			var nrm_list := [-(o["bz"] as Vector2), (o["bx"] as Vector2), (o["bz"] as Vector2), -(o["bx"] as Vector2)]
			var half_list := [hh.y, hh.x, hh.y, hh.x]
			for e in 4:
				var q: Vector2 = (o["o"] as Vector2) + (nrm_list[e] as Vector2) * (float(half_list[e]) + 1.8)
				if VL.road_sd(CV, q) < 1.0 or VL.blocked_v(CV, q, false, 0.35, true) == "frontage":
					front = e
			for e in 4:
				# 面 e の両端（OBB の局所座標で：-z, +x, +z, -x の順）
				var c0: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][e]
				var c1: Vector2 = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)][e]
				var w := Wall.new()
				w.a = (o["o"] as Vector2) + (o["bx"] as Vector2) * c0.x * hh.x + (o["bz"] as Vector2) * c0.y * hh.y
				w.b = (o["o"] as Vector2) + (o["bx"] as Vector2) * c1.x * hh.x + (o["bz"] as Vector2) * c1.y * hh.y
				w.n = nrm_list[e]
				w.bld = o["name"]
				var mid := (w.a + w.b) * 0.5 + w.n * 1.8
				var bl := VL.blocked_v(CV, mid, false, 0.35, true)
				if e == front or bl == "frontage" or VL.road_sd(CV, mid) < 1.0:
					continue
				w.back = front >= 0 and e == (front + 2) % 4
				walls.append(w)
				if w.back and r.has_point(mid):
					doors.append([(w.a + w.b) * 0.5 + w.n * 0.4, w.n, o["name"]])
		M["zones"][zn] = {"walls": walls, "doors": doors}
	# 小径：設計＋背戸から最寄りの小径への支線（12 m 以内）
	for zn: String in VL.MACRO_ZONES:
		var Z: Dictionary = M["zones"][zn]
		var paths: Array = (DESIGN[zn]["paths"] as Array).duplicate(true)
		var spots: Array = (DESIGN[zn]["spots"] as Array).duplicate(true)
		for d: Array in Z["doors"]:
			var p0: Vector2 = d[0]
			var best := 99.0
			var bq := Vector2.ZERO
			for pl: Array in DESIGN[zn]["paths"]:
				var pts: Array = pl[0]
				for i in pts.size() - 1:
					var q := _closest(pts[i], pts[i + 1], p0)
					if q.distance_to(p0) < best:
						best = q.distance_to(p0)
						bq = q
			if best < 12.0 and best > 1.5:
				var mid: Vector2 = p0.lerp(bq, 0.5) + (d[1] as Vector2).orthogonal() * (0.15 * best * (1.0 if int(p0.x * 7.0) % 2 == 0 else -1.0))
				paths.append([[p0, mid, bq], 1.05])
			# 後場：小径から遠い背戸（と區 C の全背戸）は戸口に小さな作業場（木屑・薪割り・砂利）
			if zn == "C" or best >= 12.0:
				spots.append([p0 + (d[1] as Vector2) * 3.3, 2.1 + 0.7 * GC._n(p0, 1.0, 5.0), "work"])
		Z["paths"] = paths
		Z["spots"] = spots
	return M


## P4 院子地面（Districts/*/Yards・AuxYards、地形 +0.05 m）の sampler——町家の背面院子はこの面が見えている。
##   Macro の地面と 3D はこの面（と路面）の上に載せる：地形の上だけに描くと院子の下に隠れて見えない。
static func yard_sampler(v: Node3D) -> RLib.TriSampler:
	var s := RLib.TriSampler.new()
	for mi in v.get_node("Districts").find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) in ["Yards", "AuxYards"] and (mi as MeshInstance3D).mesh != null:
			s.add((mi as MeshInstance3D).mesh.get_faces(), RLib.rel_xf(mi, v))
	return s


## 見えている地表の高さ：地形・路面・P4 院子地面の最上面
static func top_h(P: Dictionary, p: Vector2) -> float:
	var CV: Dictionary = P["CV"]
	var h := (CV["S"] as RLib.TriSampler).h(p.x, p.y)
	var rh := (CV["R"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(rh):
		h = maxf(h, rh)
	var yh := (P["M"]["YS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(yh):
		h = maxf(h, yh)
	return h


static func _closest(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return a + ab * t


static func zone_of(p: Vector2) -> String:
	for zn: String in VL.MACRO_ZONES:
		if (VL.MACRO_ZONES[zn] as Rect2).has_point(p):
			return zn
	return ""


static func inset(zn: String, p: Vector2) -> float:
	var r: Rect2 = VL.MACRO_ZONES[zn]
	return minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))


## 低周波＋領域歪みの斑（3–15 m 級、非円形・非等間隔）
static func patch(p: Vector2, scale: float, seed: float) -> float:
	var q := p / scale
	var w := Vector2(GC._n(q * 0.7 + Vector2(3.1, 7.7), 1.0, seed + 11.0), GC._n(q * 0.7 + Vector2(9.2, 1.3), 1.0, seed + 23.0)) - Vector2(0.5, 0.5)
	q += w * 1.6
	var rot := Vector2(q.x * 0.8 - q.y * 0.6, q.x * 0.6 + q.y * 0.8)
	return 0.6 * GC._n(q, 1.0, seed) + 0.4 * GC._n(rot * 1.9, 1.0, seed + 5.0)


## 小径までの距離（縁は侵食：幅が沿線で ±25 % 変わる）。戻り値 [d − 半幅, 幅]
static func path_d(Z: Dictionary, p: Vector2) -> Vector2:
	var best := 99.0
	var bw := 1.0
	for pl: Array in Z["paths"]:
		var pts: Array = pl[0]
		var w: float = pl[1]
		for i in pts.size() - 1:
			var q := _closest(pts[i], pts[i + 1], p)
			var wv := w * (0.8 + 0.45 * GC._n(q * 0.25, 1.0, 13.0))
			var d := p.distance_to(q) - wv * 0.5
			if d < best:
				best = d
				bw = wv
	return Vector2(best, bw)


static func spot_k(Z: Dictionary, p: Vector2) -> Array:
	var best := 0.0
	var kind := ""
	for s: Array in Z["spots"]:
		var c: Vector2 = s[0]
		var d := p - c
		var ang := atan2(d.y, d.x)
		var rr: float = float(s[1]) * (0.75 + 0.5 * GC._n(Vector2(cos(ang), sin(ang)) * 2.2 + c * 0.1, 1.0, 17.0))
		var k := 1.0 - smoothstep(rr * 0.65, rr, d.length())
		if k > best:
			best = k
			kind = s[2]
	return [best, kind]


## 角・路地の度合い（0＝角／路地の奥、1 以上＝開けた壁沿い）——後院の草侵入の源
static func yard_corner(Z: Dictionary, p: Vector2) -> float:
	var wn := wall_near(Z, p)
	if wn[1] == null:
		return 9.0
	var w: Wall = wn[1]
	var along: float = wn[2]
	var wl := w.a.distance_to(w.b)
	var c := minf(along, wl - along) / 2.5
	for w2: Wall in Z["walls"]:
		if w2.bld != w.bld and w.n.dot(w2.n) < -0.5 and (p - _closest(w2.a, w2.b, p)).dot(w2.n) > 0.0:
			c = minf(c, (_closest(w2.a, w2.b, p).distance_to(p) - 2.0) / 2.5)
	return maxf(c, 0.0)


## 背面・側面の壁までの距離と、その壁の向き・壁沿いの座標
static func wall_near(Z: Dictionary, p: Vector2) -> Array:
	var best := 99.0
	var bw: Wall = null
	var bt := 0.0
	for w: Wall in Z["walls"]:
		var ab := w.b - w.a
		var t := clampf((p - w.a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var q := w.a + ab * t
		var side := (p - q).dot(w.n)
		if side < -0.05:
			continue
		var d := p.distance_to(q)
		if d < best:
			best = d
			bw = w
			bt = t * ab.length()
	return [best, bw, bt]


# ─────────────────────────── 地面 ───────────────────────────

## 地面重み：[Color(碎石, 濃草, 踏土, 落葉/木屑), Vector2(濕潤, 淡出), Vector2(泥, 卵石), Vector2(枯草, 踏まれた草)] または null
static func ground_m(P: Dictionary, p: Vector2) -> Variant:
	var CV: Dictionary = P["CV"]
	var M: Dictionary = P["M"]
	var zn := zone_of(p)
	if zn == "":
		return null
	var Z: Dictionary = M["zones"][zn]
	var D: Dictionary = DESIGN[zn]
	var fade := smoothstep(0.0, FADE, inset(zn, p))
	if fade < 0.002:
		return null
	var gv := 0.0
	var lu := 0.0
	var so := 0.0
	var li := 0.0
	var md := 0.0
	var pe := 0.0
	var dry := 0.0
	var worn := 0.0
	var wet := 0.0
	var gw := GC.grass_w(CV, p)
	var pd := path_d(Z, p)
	var en := 0.55 * (GC._n(p * 1.3, 1.0, 31.0) - 0.5) + 0.35 * (GC._n(p * 3.1, 1.0, 37.0) - 0.5)
	var dpe := pd.x + en
	# ① 小径：踏み固めた土（芯）＋踏まれて色の抜けた草の縁（1–1.8 m）
	var core := 1.0 - smoothstep(-0.25, 0.3, dpe)
	var on_dirt := 1.0 - smoothstep(0.35, 0.55, gw)
	so = maxf(so, 0.95 * core)
	gv = maxf(gv, 0.25 * core * (1.0 - on_dirt) * smoothstep(0.55, 0.75, GC._n(p * 0.9, 1.0, 41.0)))
	var halo_w := 0.7 + 0.4 * GC._n(p * 0.25, 1.0, 43.0)
	worn = maxf(worn, 0.45 * (1.0 - smoothstep(halo_w * 0.45, halo_w, pd.x)) * (1.0 - core) * smoothstep(0.35, 0.55, gw))
	# ② 作業場（土＋碎石＋木屑）／踏み荒らし（土＋踏まれた草）
	var sk := spot_k(Z, p)
	var k: float = sk[0]
	var wn0 := wall_near(Z, p)
	k *= smoothstep(1.5, 2.3, float(wn0[0]))
	if k > 0.0:
		if sk[1] == "work":
			# 材料の分かれ目は 3 m 級（1 m 未満の欠片を作らない）：木屑の溜まり／淡い踏み土／砂利
			var sub := patch(p, 3.2, 47.0)
			so = maxf(so, 0.9 * k)
			li = maxf(li, 0.95 * k * smoothstep(0.4, 0.5, sub))
			gv = maxf(gv, 0.6 * k * (1.0 - smoothstep(0.22, 0.3, sub)))
			wet = minf(wet, -0.18 * k * (1.0 - smoothstep(0.36, 0.46, sub)))
		else:
			so = maxf(so, 0.75 * k * smoothstep(0.3, 0.5, patch(p, 1.6, 59.0)))
			worn = maxf(worn, 0.9 * k)
	# ③ 背面・側面の壁：牆腳の裸土帯（0–1.2 m、壁沿いに途切れる）＋雨落ちの濕った碎石線（0.75 m 前後）
	var wn := wall_near(Z, p)
	var dw: float = wn[0]
	if dw < 2.2:
		var w: Wall = wn[1]
		var along: float = wn[2]
		var seg := smoothstep(0.3, 0.42, GC._n(Vector2(along * 0.3, float(w.bld.hash() % 97)), 1.0, 61.0))
		# 角は裸土を切る（角＝雑草の溜まり、edge_k と対）：どの建物も一周つながらない
		var wl := w.a.distance_to(w.b)
		seg *= smoothstep(0.5, 1.3, minf(along, wl - along))
		var backk := 1.0 if w.back else 0.7
		if P.has("_neg_ring"):
			seg = 1.0
			backk = 1.0
		# 小径が壁際を通る所は踏み跡が勝つ（雨落ち・軒下の帯は小径の芯で途切れる）
		backk *= 1.0 - core
		var eave := (1.0 - smoothstep(0.66, 0.8, dw)) * seg * backk
		so = maxf(so, 0.9 * eave)
		wet = minf(wet, -0.7 * eave)
		# 雨落ちは軒に沿ってほぼ連続（角でも切らない；長い波長で時々切れる）
		var seg_d := 1.0 if w.back else smoothstep(0.06, 0.16, GC._n(Vector2(along * 0.16, float(w.bld.hash() % 89)), 1.0, 63.0))
		var drip := smoothstep(0.74, 0.84, dw) * (1.0 - smoothstep(1.22, 1.34, dw)) * seg_d
		pe = maxf(pe, 1.0 * drip * backk)
		wet = maxf(wet, 1.0 * drip * backk)
		var splash := smoothstep(1.24, 1.36, dw) * (1.0 - smoothstep(1.75, 2.1, dw + 0.3 * (GC._n(Vector2(along * 0.9, 5.0), 1.0, 69.0) - 0.5))) * seg_d
		md = maxf(md, 0.5 * splash * backk)
		lu = maxf(lu, 0.35 * splash * backk)
		wet = maxf(wet, 0.5 * splash * backk)
	# ④ 渠の外緣：濕った濃い草の帯＋泥の斑（P7 核心の外 0–3 m、取水點では途切れる）
	if D["canal"]:
		var e := GC.wdist(CV, p) - GC.RB_CORE
		if e > -GC.RB_FADE and e < 4.0:
			var vk := smoothstep(-GC.RB_FADE, 0.2, e) * (1.0 - smoothstep(2.4, 4.0, e + 1.2 * (GC._n(p * 0.4, 1.0, 71.0) - 0.5)))
			lu = maxf(lu, 0.45 * vk * smoothstep(0.42, 0.62, patch(p, 5.5, 73.0)))
			md = maxf(md, 0.5 * vk * (1.0 - smoothstep(0.4, 1.4, e)) * smoothstep(0.45, 0.6, patch(p, 2.0, 79.0)))
			wet = maxf(wet, 0.45 * vk * (1.0 - smoothstep(0.2, 2.0, e)))
	# ⑤ 田の外緣：草溝（濕った濃い草＋泥、0.2–2.6 m）
	if D["field"] and not P.has("_neg_noditch"):
		var fd := (M["fgrid"] as GC.DGrid).at(p)
		if fd > 0.0 and fd < 3.5:
			var fk := smoothstep(0.0, 0.3, fd) * (1.0 - smoothstep(2.0, 3.5, fd + 0.8 * (GC._n(p * 0.5, 1.0, 83.0) - 0.5)))
			lu = maxf(lu, 0.75 * fk)
			md = maxf(md, 0.45 * fk * (1.0 - smoothstep(0.3, 1.2, fd)) * smoothstep(0.35, 0.55, patch(p, 1.6, 89.0)))
			wet = maxf(wet, 0.5 * fk * (1.0 - smoothstep(0.3, 1.6, fd)))
	# ⑥ 草地の大きな色の斑：枯れ草（6–15 m）／濃い草（低く濕った所・渠寄り）——小径・作業場・壁際を避け、中央に大きな無地を残す
	if D["lawn"] and gw >= 0.4:
		var busy := maxf(core, k)
		var open := smoothstep(5.0, 9.0, dw + 2.0 * (GC._n(p * 0.2, 1.0, 99.0) - 0.5))
		var damp := 0.0
		if D["canal"]:
			damp = 1.0 - smoothstep(2.0, 9.0, GC.wdist(CV, p) - GC.RB_CORE)
		damp = maxf(damp, 1.0 - smoothstep(-1.0, 5.0, GC.forest_d(CV, p)))
		var dk := smoothstep(0.5, 0.68, patch(p, 13.0, 97.0)) * open * (1.0 - damp) * (1.0 - busy) * smoothstep(0.4, 0.6, gw)
		var sub2 := patch(p, 3.0, 103.0)
		dry = maxf(dry, dk * (0.5 + 0.35 * smoothstep(0.3, 0.65, sub2)))
		lu = maxf(lu, 0.5 * damp * smoothstep(0.35, 0.6, patch(p, 6.0, 101.0)) * (1.0 - busy))
	# ⑦ 後院（土）：低使用區（小径・作業場から離れ、壁や縁に近い所）に 4–10 m の草の侵入斑
	if D["yard"] and gw < 0.5:
		var low := smoothstep(1.2, 3.0, pd.x) * (1.0 - k)
		var src := maxf((1.0 - smoothstep(1.0, 5.0, dw + 3.0 * (GC._n(p * 0.35, 1.0, 105.0) - 0.5))) * (1.0 - smoothstep(0.0, 1.0, yard_corner(Z, p))), 1.0 - smoothstep(1.0, 4.0, GC.gdist(CV, p)))
		var ik := smoothstep(0.52, 0.64, patch(p, 5.5, 107.0)) * low * src
		lu = maxf(lu, 0.5 * ik * smoothstep(0.3, 0.5, patch(p, 3.5, 113.0)))
	if P.has("_neg_speckle"):
		# 反向：色の斑を 0.5 m の市松（tiny speckle）にする
		var ck := (int(floor(p.x * 2.0)) + int(floor(p.y * 2.0))) % 2
		dry = 0.6 * float(ck)
		lu = 0.5 * float(1 - ck)
	var tot := gv + lu + so + li + md + pe + dry + worn
	if tot > 1.0:
		gv /= tot
		lu /= tot
		so /= tot
		li /= tot
		md /= tot
		pe /= tot
		dry /= tot
		worn /= tot
		tot = 1.0
	if tot < 0.02:
		return null
	return [Color(gv, lu, so, li), Vector2(clampf(wet, -1.0, 1.0), fade), Vector2(md, pe), Vector2(dry, worn)]


## 地面頂點を置いてよいか（建物・frontage・封存・P7 構件・水・農田・Pilot・路面の奧には描かない；P7 核心は外緣 0.5 m まで）
static func vertex_ok_m(P: Dictionary, p: Vector2) -> bool:
	var CV: Dictionary = P["CV"]
	var br := VL.blocked_v(CV, p, true, 0.8, true)
	if br == "riverbank":
		return GC.wdist(CV, p) >= GC.RB_CORE - GC.RB_FADE and not VL.p7_covered(CV, p)
	return br == "" or br == "road" or br == "obstacle" or br == "trunk"


static func ground_mesh_m(P: Dictionary, zn: String) -> ArrayMesh:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var r: Rect2 = VL.MACRO_ZONES[zn]
	var nx := int(ceil(r.size.x / STEP))
	var nz := int(ceil(r.size.y / STEP))
	var WG := {}
	for j in nz + 1:
		for i in nx + 1:
			var p := r.position + Vector2(i * STEP, j * STEP)
			if not vertex_ok_m(P, p):
				continue
			var w: Variant = ground_m(P, p)
			if w != null:
				WG[Vector2i(i, j)] = w
	var NB8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var nw := {}
	for g: Vector2i in WG:
		var acc := [WG[g][0] as Color * 4.0, WG[g][1] as Vector2 * 4.0, WG[g][2] as Vector2 * 4.0, WG[g][3] as Vector2 * 4.0]
		var ws := 4.0
		for d: Vector2i in NB8:
			if WG.has(g + d):
				var wt := 1.0 if (d.x != 0 and d.y != 0) else 2.0
				acc[0] += (WG[g + d][0] as Color) * wt
				acc[1] += (WG[g + d][1] as Vector2) * wt
				acc[2] += (WG[g + d][2] as Vector2) * wt
				acc[3] += (WG[g + d][3] as Vector2) * wt
				ws += wt
		nw[g] = [acc[0] / ws, acc[1] / ws, acc[2] / ws, acc[3] / ws]
	# 欠けたセルからの BFS 淡出（1 m）
	var dist := {}
	var front: Array = []
	for g: Vector2i in nw:
		for d: Vector2i in NB8:
			if not nw.has(g + d):
				dist[g] = 0
				front.append(g)
				break
	var nf := 3
	while not front.is_empty():
		var nxt: Array = []
		for g: Vector2i in front:
			if int(dist[g]) >= nf:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if nw.has(g + d) and not dist.has(g + d):
					dist[g + d] = int(dist[g]) + 1
					nxt.append(g + d)
		front = nxt
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U1 := PackedVector2Array()
	var U2 := PackedVector2Array()
	var CU := PackedFloat32Array()
	var idx := PackedInt32Array()
	var vid := {}
	for g: Vector2i in nw:
		var p := r.position + Vector2(g.x * STEP, g.y * STEP)
		var h := top_h(P, p)
		var dd := 0.4
		var nrm := Vector3(S.h(p.x - dd, p.y) - S.h(p.x + dd, p.y), 2.0 * dd, S.h(p.x, p.y - dd) - S.h(p.x, p.y + dd))
		var u2: Vector2 = nw[g][1]
		if dist.has(g):
			u2.y *= smoothstep(0.0, float(nf), float(dist[g]))
		vid[g] = V.size()
		V.append(Vector3(p.x, h + 0.016, p.y))
		N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
		Cc.append(nw[g][0])
		U2.append(u2)
		U1.append(nw[g][2])
		var c4: Vector2 = nw[g][3]
		CU.append_array([c4.x, c4.y, 0.0, 0.0])
	for g: Vector2i in nw:
		var k10: Variant = vid.get(g + Vector2i(1, 0))
		var k01: Variant = vid.get(g + Vector2i(0, 1))
		var k11: Variant = vid.get(g + Vector2i(1, 1))
		if k10 == null or k01 == null or k11 == null:
			continue
		var k00: int = vid[g]
		if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
			idx.append_array([k00, k10, k11, k00, k11, k01])
		else:
			idx.append_array([k00, k10, k01, k10, k11, k01])
	if idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV] = U1
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_CUSTOM0] = CU
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.resource_name = "gc_macro_" + zn
	return am


static func material_m() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	m.resource_name = "GC_Macro"
	return m


# ─────────────────────────── 3D（縁の丈の高い草の塊＋近景點綴） ───────────────────────────

## 縁の度合い（0–1）：渠の外緣・田の外緣・林緣・壁の角と路地・後院の縁・草と土の境
static func edge_k(P: Dictionary, zn: String, p: Vector2) -> float:
	var CV: Dictionary = P["CV"]
	var M: Dictionary = P["M"]
	var D: Dictionary = DESIGN[zn]
	var Z: Dictionary = M["zones"][zn]
	var k := 0.0
	if D["canal"]:
		var e := GC.wdist(CV, p) - GC.RB_CORE
		k = maxf(k, smoothstep(0.2, 0.6, e) * (1.0 - smoothstep(1.8, 3.2, e)))
	if D["field"]:
		var fd := (M["fgrid"] as GC.DGrid).at(p)
		var reach := 2.2 + 2.4 * GC._n(p * 0.12, 1.0, 139.0)
		k = maxf(k, smoothstep(0.3, 0.6, fd) * (1.0 - smoothstep(reach - 0.8, reach, fd)))
	if D["treeline"]:
		var td := GC.forest_d(CV, p)
		k = maxf(k, smoothstep(-1.5, -0.5, td) * (1.0 - smoothstep(1.5, 3.0, td)))
	var wn := wall_near(Z, p)
	var dw: float = wn[0]
	if dw < 3.0 and wn[1] != null:
		var w: Wall = wn[1]
		var L := w.a.distance_to(w.b)
		var along: float = wn[2]
		var corner := 1.0 - smoothstep(1.2, 2.6, minf(along, L - along))
		# 隣棟との路地（向かい合う 2 棟の壁に挟まれる所だけ）・壁の角
		var other := 99.0
		for w2: Wall in Z["walls"]:
			if w2.bld != w.bld and w.n.dot(w2.n) < -0.5 and (p - _closest(w2.a, w2.b, p)).dot(w2.n) > 0.0:
				other = minf(other, _closest(w2.a, w2.b, p).distance_to(p))
		var alley := 1.0 - smoothstep(2.5, 4.5, other)
		# 出隅（凸角）は開けて踏まれる：縁草は向かい合う壁の間（路地）だけ
		k = maxf(k, alley * smoothstep(0.35, 0.7, dw) * (1.0 - smoothstep(1.8, 3.0, dw)) * (0.6 + 0.4 * corner))
	return k


static func extend(P: Dictionary, v: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var M := context_m(CV)
	M["YS"] = yard_sampler(v)
	P["M"] = M
	P["n_village_items"] = (P["items"] as Array).size()
	P["n_village_nodes"] = (P["nodes"] as Array).size()
	var items: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_M
	for zn: String in VL.MACRO_ZONES:
		var r: Rect2 = VL.MACRO_ZONES[zn]
		var Z: Dictionary = M["zones"][zn]
		var tag := "m_" + zn
		var x := r.position.x
		while x < r.end.x:
			var z := r.position.y
			while z < r.end.y:
				var q := Vector2(x + rng.randf_range(0.0, 0.32), z + rng.randf_range(0.0, 0.32))
				z += 0.32
				if inset(zn, q) < 1.0 or VL.blocked_v(CV, q, false, 0.35, true) != "":
					continue
				var fz := smoothstep(1.0, FADE, inset(zn, q))
				var pd := path_d(Z, q)
				if pd.x < 0.3:
					continue
				var sk: Array = spot_k(Z, q)
				if float(sk[0]) > 0.5:
					continue
				# ① 縁の丈の高い草の塊（帯にしない：低周波の斑で途切れる、芯ほど高く密）
				var cl := patch(q, 7.0, 131.0)
				var clk := smoothstep(0.55, 0.66, cl)
				if DESIGN[zn]["field"]:
					var fdq := (M["fgrid"] as GC.DGrid).at(q)
					if fdq > 0.3 and fdq < 4.6:
						clk = maxf(clk, smoothstep(0.52, 0.64, patch(q, 6.0, 137.0)))
				var ek := edge_k(P, zn, q) * clk * fz * smoothstep(0.3, 1.2, pd.x)
				if DESIGN[zn]["yard"]:
					ek *= 0.5
				if ek > 0.05 and rng.randf() < ek * (0.45 + 0.5 * maxf(smoothstep(0.62, 0.75, cl), clk - 0.35)):
					var kk := GC.K_STEM if rng.randf() < 0.3 else GC.K_FINE
					var hgt := minf(lerpf(0.34, 0.7, ek) * rng.randf_range(0.8, 1.12), 0.68)
					if DESIGN[zn]["yard"]:
						hgt *= 0.7
					items.append(GC.gi(S, kk, q, hgt, rng.randf_range(1.0, 1.4), rng.randf() * TAU, GC.grass_col(rng, 0.2 + 0.35 * GC._n(q * 0.3, 1.0, 137.0)), tag, "rough"))
					continue
				var gw := GC.grass_w(CV, q)
				# ② （m2）乾草斑の中の立ち株は置かない——開けた草地の内部に散布すると「雑草の区画」に見える。斑は地面の色調だけで読ませる
				# ③ 小径の縁の踏まれた短い草（近景點綴）
				if pd.x > 0.3 and pd.x < 1.1 and gw >= 0.4 and rng.randf() < 0.035 * fz:
					items.append(GC.gi(S, GC.K_SHORT, q, rng.randf_range(0.1, 0.17), 1.1, rng.randf() * TAU, GC.grass_col(rng, 0.35), tag, "pathedge"))
					continue
				# ④ 後院の草の侵入斑に中くらいの草叢
				if DESIGN[zn]["yard"] and gw < 0.5:
					var ik := smoothstep(0.52, 0.64, patch(q, 5.5, 107.0)) * smoothstep(1.2, 3.0, pd.x) * (1.0 - float(sk[0])) * fz
					var dw: float = wall_near(Z, q)[0]
					ik *= maxf(1.0 - smoothstep(0.0, 1.0, yard_corner(Z, q)), 1.0 - smoothstep(1.0, 4.0, GC.gdist(CV, q)))
					ik *= 1.0 - smoothstep(2.0, 4.0, dw)
					if ik > 0.05 and rng.randf() < 0.1 * ik:
						var ky := GC.K_SHORT if rng.randf() < 0.65 else GC.K_FINE
						items.append(GC.gi(S, ky, q, rng.randf_range(0.12, 0.25), rng.randf_range(1.0, 1.3), rng.randf() * TAU, GC.grass_col(rng, 0.3), tag, "invade"))
						continue
				# ⑤ 雨落ちの線に小石
				var wn := wall_near(Z, q)
				if float(wn[0]) > 0.82 and float(wn[0]) < 1.25 and wn[1] != null and rng.randf() < 0.05 * fz:
					items.append(GC.gi(S, GC.K_PEBBLE, q, rng.randf_range(0.5, 0.9), 1.0, rng.randf() * TAU, Color(0.9, 0.9, 0.9), tag, "drip"))
			x += 0.32
	# 見えている地表（院子地面・路面）に載せる：GC.gi は地形基準なので差分だけ持ち上げる
	for it: Dictionary in items:
		var q: Vector2 = it["p"]
		it["y"] = float(it["y"]) + (top_h(P, q) - S.h(q.x, q.y))
	(P["items"] as Array).append_array(items)
	var stats: Dictionary = P["stats"]
	for it: Dictionary in items:
		var key := "%s/%s" % [it["zone"], it["tag"]]
		stats[key] = int(stats.get(key, 0)) + 1
	P["ms_macro"] = Time.get_ticks_msec() - t0


## bake_all の後に Macro 地面網格を足す
static func bake_macro(P: Dictionary, root: Node3D) -> int:
	var gnode := root.get_node("Ground")
	var mg := Node3D.new()
	mg.name = "Macro"
	gnode.add_child(mg)
	var mat := material_m()
	var nv := 0
	for zn: String in VL.MACRO_ZONES:
		var m := ground_mesh_m(P, zn)
		if m == null:
			continue
		m.surface_set_material(0, mat)
		var g := MeshInstance3D.new()
		g.name = "M_" + zn
		g.mesh = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 160.0
		mg.add_child(g)
		nv += m.surface_get_array_len(0)
	root.set_meta("macro_ground_verts", nv)
	return nv
