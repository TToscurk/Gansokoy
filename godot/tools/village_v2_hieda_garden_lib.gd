extends RefCounted
## 人間之里 V2 P9 R4 Garden／Hero Surroundings 第一包：稗田邸庭園（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/hieda_garden_p9.scn → village_v2.tscn 掛 Vegetation/HiedaGardenP9。
##   R1 樹庫（veg_kit trees prefab 實例）、R3 竹材貼圖（BK_Culm_dead）、P7 河岸 Kit 石材（rb_bld／rb_cob）只讀重用；
##   新構件＝garden_kit（build_garden_kit.py）。P0–P8／R1–R3 已核准內容（地形、本屋、大宅門、圍牆、林帶、竹林）不改。
##
## 構成（宅內 x 384.5–421.5、z −10.3–−59.8；本屋 x 390–416、z −31.6（簷）–−47.3；大宅門 (398, −10)；玄關 (403, −32.7)）：
##   1 主軸：大宅門 → 前庭 → 玄關。門與玄關左右錯開 5 m → 延段（切石＋自然石）直進 10 m 後以一段斜行「鉤の手」接回玄關軸，
##     轉折處春日燈籠＋景石（從門口第一眼看到的焦點），玄關前左右不對稱各一株庭園松／修剪躑躅。
##   2 前庭正式感與留白：主軸西側＝一整片白砂利（只有一株枝垂櫻＋伏石＋兩團躑躅，其餘空著）；門內東側門冠り松；
##     玄關前砂利 apron、雨落ち縁石。前庭大部分面積刻意不放東西（gate 量「留白率」）。
##   3 側庭池泉／曲水：主軸東側池（約 15 × 10 m，中島＋雪見燈籠＋護岸石組＋州浜），池北岸飛石往東側沿本屋東側走到後庭；
##     曲水自後庭東北角滝石組湧出 → 後庭蛇行（石橋、沢飛び）→ 本屋東側 → 池東北角入池。
##   4 後庭自然植栽：楓（庭園／山）、自然形赤松、次生闊葉、灌木、蕨、笹；蹲踞＋織部燈籠在本屋背面。
##   5 接地與細節：所有構件以環 8 點地面最低值接地；牆腳砂利帶、雨落ち（砂利帶＋縁石）、池岸 skirt、溪岸石。
## 地形不改（P1 凍結）：池面＝池內地形最高＋0.03（池岸 skirt＋護岸石遮住 ≤ 0.12 m 的高差）；曲水水面＝橫斷面最高地形＋0.03。

const TreeLib := preload("res://tools/village_v2_veg_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/hieda_garden_p9.scn"
const NODE_NAME := "HiedaGardenP9"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const RB := "res://assets/village_v2/riverbank_kit/mesh/"
const TREES := "res://assets/village_v2/veg_kit/trees/"
const GROUND_SHADER := "res://assets/village_v2/_matlib/ground/ground.gdshader"
const STONE_MAT := "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres"
const WATER_MAT := "res://assets/village_v2/garden_kit/GK_Water.tres"
const POND_WATER_MAT := "res://assets/village_v2/garden_kit/GK_PondWater.tres"
const FALLS2_MAT := "res://assets/village_v2/garden_kit/GK_FallSheet.tres"
const SEED := 4404
const LOD_SWITCH := 38.0

## 宅邸幾何（world，量自已核准資產：圍牆內面、本屋碰撞＋台基、大宅門）
const ESTATE := Rect2(384.55, -59.75, 36.9, 49.45)          # 牆內面（x 384.55–421.45、z −59.75–−10.30）
const HOUSE_BASE := Rect2(390.65, -46.25, 24.7, 11.65)      # 本屋台基 z −46.25–−34.6
const GENKAN := Rect2(398.3, -34.6, 9.4, 2.55)               # 玄關台基＋踏石 z −34.6–−32.05
const HOUSE_COL := Rect2(390.57, -45.9, 24.86, 11.81)       # 本屋碰撞 Wings
const EAVE := Rect2(389.9, -47.3, 26.2, 15.7)                # 本屋簷外框（z −47.3–−31.6）
const GATE := Vector2(398.0, -10.0)
const CHERRY := Vector2(388.6, -21.4)
## 前庭主景石（砂利中、枝垂櫻苔島の南東）：[中心, yaw, 半長, 半幅]（環紋用；件は plan で置く）
const RAKE_STONES := [[Vector2(391.9, -24.4), 2.3, 0.68, 0.49], [Vector2(392.65, -23.8), 0.9, 0.23, 0.18]]
const GENKAN_STEP := Vector2(403.0, -30.95)                  # 本屋踏石前端（walkway 外緣）

## 1 主軸（延段）：直進 → 鉤の手 → 玄關軸
const MAIN_PATH := [Vector2(398.0, -11.05), Vector2(398.0, -21.2), Vector2(403.0, -26.0), Vector2(403.0, -31.95)]
const MAIN_W := 1.3
## 3 池（world，逆時針後再平滑）／中島／曲水（寬度沿程）
const POND := [Vector2(404.6, -15.4), Vector2(406.8, -13.3), Vector2(410.4, -12.7), Vector2(414.2, -13.0),
	Vector2(417.6, -13.6), Vector2(419.5, -15.6), Vector2(419.3, -18.6), Vector2(418.2, -20.4), Vector2(419.0, -22.6),
	Vector2(418.2, -24.4), Vector2(416.0, -24.6), Vector2(413.6, -23.2), Vector2(411.0, -23.8), Vector2(408.6, -22.6),
	Vector2(406.6, -22.9), Vector2(405.4, -21.0), Vector2(406.2, -18.8), Vector2(404.8, -17.6)]
## 中島：偏池西（不放池心，避免「靶心」）
const ISLAND := [Vector2(408.0, -18.0), Vector2(408.6, -17.0), Vector2(409.9, -16.9), Vector2(410.6, -17.9),
	Vector2(410.3, -19.3), Vector2(409.1, -19.8), Vector2(408.2, -19.2)]
## 曲水：本屋東側 5 m 窄帶內蛇行（x 418.8–420.2）、寬窄變化，不是直溝
const STREAM := [Vector2(419.6, -58.0), Vector2(417.6, -56.3), Vector2(415.2, -55.2), Vector2(413.9, -53.4),
	Vector2(414.9, -51.4), Vector2(417.4, -50.2), Vector2(419.4, -48.0), Vector2(420.1, -44.6), Vector2(418.8, -41.2),
	Vector2(419.9, -37.4), Vector2(420.2, -33.6), Vector2(418.9, -30.2), Vector2(419.2, -27.0), Vector2(418.1, -24.0)]
const STREAM_W := [1.5, 0.95, 0.75, 0.7, 0.7, 0.7, 0.65, 0.85, 0.55, 0.75, 0.9, 0.6, 0.8, 0.9]
## 前庭／側庭の仕切り：四つ目垣（x 403.7、z −12.6–−23.4）＋刈込み → 前庭（正式・留白）と池泉側庭を分ける
const DIVIDER_X := 403.7
const DIVIDER_Z := [-12.6, -23.4]
const YUKIMI := Vector2(414.6, -23.7)
## 滝：水落石（伏石、築山上）中心；水從其前緣落到滝壺（曲水起點）
const FALL_LIP := Vector2(419.45, -58.85)
## 州浜（南岸緩坡卵石）
const BEACH := Rect2(407.0, -14.0, 6.5, 2.0)
## 曲水水面站距（沿平滑中心線）
const STREAM_STEP := 0.4
## 前庭砂紋：環紋範圍（苔島／主景石外緣起算）＝ 5 道 × 0.16 m
const RING_EXT := 0.88
## 枝垂櫻陰面偏藍（天光 × 近白花卡）：R4 場景層級 instance tint（R1 shader／COLOR_PRESETS 不改）
const SAKURA_WARM := [Vector3(1.02, 0.9, 0.86), 1.0]
## 枝垂櫻の陰面補光（場景層級・可逆）：櫻だけに効く暖色 Omni（cull_mask＝VIS_LAYER_SAKURA のみ、影なし）
const VIS_LAYER_SAKURA := 1 << 11
const SAKURA_FILL := {"pos": Vector3(0.0, 2.2, 0.0), "range": 4.8, "energy": 0.3, "color": Color(1.0, 0.92, 0.88)}
## 飛石路線（前庭池北岸 → 本屋東側 → 沢飛び → 石橋 → 後庭 → 蹲踞）
const TOBI := [Vector2(403.9, -25.3), Vector2(405.4, -26.4), Vector2(407.4, -26.9), Vector2(409.6, -27.0),
	Vector2(412.0, -26.9), Vector2(414.4, -27.0), Vector2(416.0, -28.0), Vector2(416.9, -29.6), Vector2(417.0, -33.0),
	Vector2(417.0, -40.0), Vector2(417.0, -46.4), Vector2(416.7, -48.6)]
const SAWATOBI := [Vector2(416.25, -50.75)]
const TOBI_REAR := [Vector2(416.0, -51.9), Vector2(415.6, -53.2)]        # 曲水內側半島 → 石橋
const TOBI_W := [Vector2(412.6, -55.3), Vector2(410.4, -55.2), Vector2(408.1, -54.4), Vector2(405.6, -53.4),
	Vector2(403.0, -52.4), Vector2(400.3, -51.6), Vector2(397.6, -51.0)]
const TSUKUBAI := Vector2(395.0, -51.4)

const MOSS := {}


# ─────────────────────────── 幾何工具 ───────────────────────────

static func chaikin(pts: Array, it := 2) -> PackedVector2Array:
	var p := PackedVector2Array(pts)
	for k in it:
		var q := PackedVector2Array()
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			q.append(a.lerp(b, 0.25))
			q.append(a.lerp(b, 0.75))
		p = q
	return p


static func resample(pts: Array, step: float) -> Array:
	## 開折線等距重取樣：回傳 [[Vector2, 方向, 累積長], ...]
	var out: Array = []
	var acc := 0.0
	var carry := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		var d := (b - a) / maxf(L, 1e-6)
		var t := carry
		while t <= L:
			out.append([a + d * t, d, acc + t])
			t += step
		carry = t - L
		acc += L
	return out


static func poly_d(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best


static func line_d(pts: Array, p: Vector2) -> Vector2:
	## 回傳 (距離, 沿程索引 i + t)
	var best := Vector2(INF, 0.0)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			best = Vector2(d, i + t)
	return best


static func stream_w(si: float) -> float:
	var i := clampi(int(si), 0, STREAM_W.size() - 2)
	return lerpf(float(STREAM_W[i]), float(STREAM_W[i + 1]), si - i)


## 開折線 Chaikin（端點保留）：曲水中心線平滑 → 水面帶不再有折線急轉
static func open_chaikin(pts: Array, it := 2) -> Array:
	var p: Array = pts.duplicate()
	for k in it:
		var q: Array = [p[0]]
		for i in p.size() - 1:
			q.append((p[i] as Vector2).lerp(p[i + 1], 0.25))
			q.append((p[i] as Vector2).lerp(p[i + 1], 0.75))
		q.append(p[-1])
		p = q
	return p


## 水際コンテキスト：[池 signed 距離（+＝池外）, 曲水 (中心距離 − 半幅)（+＝岸上）, 曲水水面 y, 池岸侵蝕 0..1, 溪岸侵蝕 0..1]
static func wctx(P: Dictionary, p: Vector2) -> Array:
	var dp := INF
	var e_p := 0.0
	if (P["pond_bb"] as Rect2).grow(2.7).has_point(p):
		var pond: PackedVector2Array = P["pond"]
		dp = poly_d(pond, p)
		if Geometry2D.is_point_in_polygon(p, pond):
			dp = -dp
		var c: Vector2 = P["pond_c"]
		var a := atan2(p.y - c.y, p.x - c.x)
		e_p = clampf(0.5 + 0.38 * sin(a * 3.0 + 1.3) + 0.22 * sin(a * 7.0 + 0.4), 0.0, 1.0)
	var o := INF
	var sy := 0.0
	var e_s := 0.0
	if (P["sline_bb"] as Rect2).grow(1.9).has_point(p):
		var sl: Array = P["sline"]
		var ld := line_d(sl, p)
		var i := clampi(int(ld.y), 0, sl.size() - 2)
		var t := ld.y - i
		var cum: PackedFloat32Array = P["sline_cum"]
		var sw: PackedFloat32Array = P["sline_w"]
		var arc := lerpf(cum[i], cum[i + 1], t)
		o = ld.x - lerpf(sw[i], sw[i + 1], t) * 0.5
		var sya: Array = P["stream_y"]
		var kf := clampf(arc / STREAM_STEP, 0.0, sya.size() - 1.001)
		sy = lerpf(float(sya[int(kf)]), float(sya[int(kf) + 1]), kf - int(kf))
		e_s = clampf(0.5 + 0.35 * sin(arc * 1.3 + 0.7) + 0.25 * sin(arc * 3.1 + 2.0), 0.0, 1.0)
	return [dp, o, sy, e_p, e_s]


## 庭園地面 overlay 的絕對高度（P1 地形不改；盛り／岸／滝壺／海の凹み都只在 overlay）
static func surf(P: Dictionary, p: Vector2, w: Array = []) -> float:
	var S: RLib.TriSampler = P["S"]
	var t := S.h(p.x, p.y)
	if w.is_empty():
		w = wctx(P, p)
	var wl: float = P["water_y"]
	var dp: float = w[0]
	var o: float = w[1]
	var beach := BEACH.has_point(p)
	if dp < 0.0 or o < 0.0:
		# 水中：岸坡往下（池 0.42、州浜 0.14、溪 0.5 斜率），底不低於地形（淺水；底＝濕土／卵石）
		var hb := INF
		if dp < 0.0:
			hb = minf(hb, wl + (0.012 if beach else lerpf(0.075, 0.015, w[3])) + dp * (0.14 if beach else 0.42))
		if o < 0.0:
			hb = minf(hb, float(w[2]) + lerpf(0.06, 0.012, w[4]) + o * 0.5)
		return maxf(hb, t + 0.01)
	# 築山は滝壺より下流の溪沿いでは削る（溪が丘を切って流れ出る）
	var mk := lerpf(1.0, smoothstep(0.0, 1.4, o), smoothstep(-58.95, -58.4, p.y)) if o < INF else 1.0
	var base := t + 0.012 + mound(p) * mk
	var h := base
	if dp < 2.7:
		var L0 := 0.012 if beach else lerpf(0.075, 0.015, w[3])
		var Lm := 0.045 if beach else lerpf(0.16, 0.07, w[3])
		h = maxf(h, lerpf(wl + L0 + (Lm - L0) * smoothstep(0.0, 0.5, dp), base, smoothstep(0.5, 2.7, dp)))
	if o < 1.7:
		var L0 := lerpf(0.06, 0.012, w[4])
		var Lm := lerpf(0.13, 0.05, w[4])
		h = maxf(h, lerpf(float(w[2]) + L0 + (Lm - L0) * smoothstep(0.0, 0.35, o), base, smoothstep(0.35, 1.7, o)))
	return h


static func mound(p: Vector2) -> float:
	var dt := p.distance_to(Vector2(TSUKIYAMA.x, TSUKIYAMA.y))
	if dt >= TSUKIYAMA.z:
		return 0.0
	var t := 1.0 - dt / TSUKIYAMA.z
	return TSUKIYAMA_H * t * t * (3.0 - 2.0 * t)


## 前庭砂紋の環紋場：[苔島／主景石外緣からの距離, 範囲, 勾配 x, 勾配 z]
static func ring_f(p: Vector2) -> Array:
	var v := p - CHERRY
	var r := v.length()
	var best := r - (2.9 + 0.35 * sin(atan2(v.y, v.x) * 3.0 + 0.7))
	var g := v / maxf(r, 1e-4)
	for st: Array in RAKE_STONES:
		var c: Vector2 = st[0]
		var yaw: float = st[1]
		var a: float = st[2]
		var b: float = st[3]
		var ax := Vector2(cos(yaw), -sin(yaw))
		var az := Vector2(sin(yaw), cos(yaw))
		var q := Vector2((p - c).dot(ax), (p - c).dot(az))
		var n := sqrt((q.x / a) * (q.x / a) + (q.y / b) * (q.y / b))
		var d := (n - 1.0) * q.length() / maxf(n, 1e-4)
		if d < best:
			best = d
			var gl := Vector2(q.x / (a * a), q.y / (b * b))
			g = (ax * gl.x + az * gl.y).normalized()
	return [best, RING_EXT if best < RING_EXT + 1.2 else 0.0, g.x, g.y]


static func ground(S: RLib.TriSampler, p: Vector2, r: float) -> float:
	var y := S.h(p.x, p.y)
	for k in 8:
		var a := k * TAU / 8.0
		var h := S.h(p.x + cos(a) * r, p.y + sin(a) * r)
		if not is_nan(h):
			y = minf(y, h)
	return y


static func ground_max(S: RLib.TriSampler, p: Vector2, r: float) -> float:
	var y := S.h(p.x, p.y)
	for k in 8:
		var a := k * TAU / 8.0
		var h := S.h(p.x + cos(a) * r, p.y + sin(a) * r)
		if not is_nan(h):
			y = maxf(y, h)
	return y


# ─────────────────────────── 規劃 ───────────────────────────

## 構件接地半徑（環 8 點取最低）與埋入（origin 再下沉）
const FOOT := {"gk_toro_kasuga": [0.38, 0.0], "gk_toro_yukimi": [0.46, 0.0], "gk_toro_oribe": [0.15, 0.0],
	"gk_tsukubai": [0.4, 0.0], "gk_nobe": [0.6, 0.0], "gk_tobi": [0.25, 0.0], "gk_kei": [0.3, 0.02],
	"gk_yotsume": [0.0, 0.0], "gk_sodegaki": [0.0, 0.0], "gk_bridge": [0.0, 0.0], "gk_amaochi": [0.35, 0.0],
	"rb_bld": [0.3, 0.02], "rb_cob": [0.4, 0.01], "tree": [0.4, 0.05]}


static func _foot(id: String) -> Array:
	for k: String in FOOT:
		if id.begins_with(k):
			return FOOT[k]
	return [0.3, 0.0]


static func item(S: RLib.TriSampler, kind: String, id: String, p: Vector2, yaw: float, sc: Variant, tag: String,
		extra := {}) -> Dictionary:
	var f: Array = _foot(id if kind == "mesh" else "tree")
	var s3: Vector3 = sc if sc is Vector3 else Vector3.ONE * float(sc)
	var y := ground(S, p, float(f[0]) * maxf(s3.x, s3.z)) - float(f[1])
	var it := {"kind": kind, "id": id, "p": p, "y": y, "yaw": yaw, "sc": s3, "tag": tag}
	it.merge(extra, true)     # extra 可覆寫 y（中島上的植栽）
	return it


static func plan(v: Node3D, _L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var S := RLib.terrain_sampler(v)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	var pond := chaikin(POND, 2)
	var island := chaikin(ISLAND, 2)
	# 池面：池內（含岸線）地形最高 + 0.03
	var wl := -INF
	var lo := -INF
	for q in pond:
		wl = maxf(wl, S.h(q.x, q.y))
	var bb := Rect2(pond[0], Vector2.ZERO)
	for q in pond:
		bb = bb.expand(q)
	var x := bb.position.x
	while x <= bb.end.x:
		var z := bb.position.y
		while z <= bb.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), pond):
				wl = maxf(wl, S.h(x, z))
			z += 0.5
		x += 0.5
	wl += 0.03
	# 水際コンテキスト（池／平滑曲水／水面高）：surf()／berm()／地面權重／水面網格共用
	var pc := Vector2.ZERO
	for q in pond:
		pc += q
	pc /= pond.size()
	var sline: Array = open_chaikin(STREAM, 2)
	var scum := PackedFloat32Array([0.0])
	var sw := PackedFloat32Array()
	var sbb := Rect2(sline[0], Vector2.ZERO)
	for i in sline.size():
		var q: Vector2 = sline[i]
		sbb = sbb.expand(q)
		if i > 0:
			scum.append(scum[i - 1] + q.distance_to(sline[i - 1]))
		sw.append(stream_w(line_d(STREAM, q).y))
	var st := resample(sline, STREAM_STEP)
	var sy: Array = []
	for k in st.size():
		var e: Array = st[k]
		var sp: Vector2 = e[0]
		var d: Vector2 = e[1]
		var w := stream_w(line_d(STREAM, sp).y)
		var nn := Vector2(-d.y, d.x)
		var hm := maxf(S.h(sp.x, sp.y), maxf(S.h(sp.x + nn.x * w * 0.5, sp.y + nn.y * w * 0.5), S.h(sp.x - nn.x * w * 0.5, sp.y - nn.y * w * 0.5)))
		sy.append(maxf(hm + 0.03, wl))
	# 溪水往下游不得升高（水往低處流；必要時讓上游等高）
	for k in range(sy.size() - 2, -1, -1):
		sy[k] = maxf(float(sy[k]), float(sy[k + 1]))
	var C := {"S": S, "pond": pond, "pond_bb": bb, "pond_c": pc, "water_y": wl, "sline": sline, "sline_cum": scum,
		"sline_w": sw, "sline_bb": sbb, "stream": st, "stream_y": sy}
	# ── 1 主軸延段：每段等分成 ≈1.4 m 的板（x 沿路、寬 MAIN_W），段與段在轉角處交疊（高度錯開 4 mm 避免 z-fight）
	var nobe := ["gk_nobe_a", "gk_nobe_b", "gk_nobe_c"]
	var kk := 0
	for si in MAIN_PATH.size() - 1:
		var a: Vector2 = MAIN_PATH[si]
		var b: Vector2 = MAIN_PATH[si + 1]
		var L := a.distance_to(b)
		var d := (b - a) / L
		var nseg := maxi(1, int(round(L / 1.4)))
		var pl := L / nseg
		for k in nseg:
			var p := a + d * (pl * (k + 0.5))
			var it := item(S, "mesh", nobe[kk % 3], p, atan2(-d.y, d.x), Vector3(pl / 1.4, 1.0, MAIN_W / 1.2), "path_main")
			it["y"] = S.h(p.x, p.y) - 0.005 - 0.004 * (si % 2)
			items.append(it)
			kk += 1
	# ── 2 前庭：門冠り松、枝垂櫻＋伏石＋躑躅、玄關前庭園松（不對稱）、春日燈籠＋景石（鉤の手焦點）
	items.append(item(S, "tree", "niwamatsu_a", Vector2(402.2, -14.0), deg_to_rad(205.0), 0.88, "front_tree"))
	items.append(item(S, "tree", "tsutsuji_a", Vector2(402.7, -12.4), 0.6, 0.7, "front_shrub"))
	items.append(item(S, "mesh", "gk_kei_low", Vector2(400.2, -13.3), 0.9, 0.8, "front_stone"))
	items.append(item(S, "tree", "sakura_shidare", CHERRY, 0.4, 0.86, "front_tree", {"tint": SAKURA_WARM}))
	# 主景石（砂利の中、苔島から 0.8 m 離す → 環紋が苔島と石の両方を回る）
	items.append(item(S, "mesh", "gk_kei_flat", RAKE_STONES[0][0], RAKE_STONES[0][1], 0.92, "front_stone"))
	items.append(item(S, "mesh", "gk_kei_low", RAKE_STONES[1][0], RAKE_STONES[1][1], 0.4, "front_stone"))
	items.append(item(S, "tree", "tsutsuji_a", CHERRY + Vector2(-1.6, -2.6), 1.7, 0.8, "front_shrub"))
	# 仕切り：四つ目垣 6 間＋垣前の刈込み 3 團（前庭側）
	var dz0: float = DIVIDER_Z[0]
	var nd := int(round(absf(float(DIVIDER_Z[1]) - dz0) / 1.8))
	for k in nd:
		items.append(item(S, "mesh", "gk_yotsume", Vector2(DIVIDER_X, dz0 - 0.9 - k * 1.8), PI * 0.5, 1.0, "fence"))
	for z: float in [-14.4, -18.0, -21.6]:
		items.append(item(S, "tree", "tsutsuji_a", Vector2(DIVIDER_X - 0.95, z), rng.randf() * TAU, rng.randf_range(0.62, 0.78),
			"front_shrub"))
	# 延段西緣の縁石（砂利／延段の見切り）
	var kz := -11.6
	while kz > -20.6:
		items.append(item(S, "mesh", "gk_amaochi", Vector2(398.0 - MAIN_W * 0.5 - 0.07, kz - 0.45), PI * 0.5, 1.0, "kerb"))
		kz -= 0.92
	items.append(item(S, "mesh", "gk_toro_kasuga", Vector2(400.9, -19.9), deg_to_rad(-12.0), 1.0, "lantern"))
	items.append(item(S, "mesh", "gk_kei_mid", Vector2(401.9, -18.8), 2.0, 0.62, "front_stone"))
	items.append(item(S, "tree", "tsutsuji_a", Vector2(400.0, -18.7), 0.3, 0.7, "front_shrub"))
	items.append(item(S, "tree", "niwamatsu_a", Vector2(405.4, -23.9), deg_to_rad(-40.0), 1.0, "front_tree"))
	items.append(item(S, "tree", "niwamatsu_a", Vector2(395.4, -30.0), deg_to_rad(120.0), 0.6, "front_tree"))
	items.append(item(S, "tree", "tsutsuji_a", Vector2(405.1, -29.1), 2.2, 0.55, "front_shrub"))
	# ── 3 池：中島、雪見燈籠、護岸石組、州浜、池畔植栽
	# 中島：景石＋小松（島面 y＝池面＋0.15）
	var isl_c := Vector2(409.2, -18.3)
	items.append(item(S, "mesh", "gk_kei_mid", isl_c + Vector2(0.7, -0.4), 0.5, 0.62, "pond_stone"))
	items.append(item(S, "mesh", "gk_kei_low", isl_c + Vector2(-0.6, 0.5), 2.1, 0.5, "pond_stone"))
	items.append(item(S, "tree", "niwamatsu_a", isl_c + Vector2(-0.1, -0.1), deg_to_rad(30.0), 0.55, "pond_island",
		{"on_island": true, "y": wl + 0.36}))
	for q: Array in [[Vector2(-1.1, -0.4), 0.7], [Vector2(0.9, 0.8), 0.62], [Vector2(-0.3, 1.2), 0.55], [Vector2(1.2, -0.6), 0.5]]:
		items.append(item(S, "mesh", "rb_bld_%s" % "abcde"[rng.randi() % 5], isl_c + (q[0] as Vector2), rng.randf() * TAU,
			float(q[1]), "pond_stone", {"on_island": true, "y": wl + 0.02}))
	items.append(item(S, "mesh", "gk_toro_yukimi", YUKIMI, deg_to_rad(15.0), 1.0, "lantern"))
	# 護岸石組：沿岸 6 組（主石半入水＋添石＋水際の卵石、組間は空岸＝濕土と苔の侵蝕面を見せる）；南岸州浜＝卵石が水中まで続く
	var shore := resample(Array(pond) + [pond[0]], 0.5)
	var L_sh: float = shore[-1][2]
	var groups := [0.04, 0.2, 0.36, 0.5, 0.66, 0.83]
	for k in shore.size():
		var e: Array = shore[k]
		var p: Vector2 = e[0]
		var d: Vector2 = e[1]
		var out := Vector2(d.y, -d.x)
		if Geometry2D.is_point_in_polygon(p + out * 0.3, pond):
			out = -out
		if p.distance_to(STREAM[-1]) < 1.6 or p.distance_to(TOBI[0]) < 1.4 or p.distance_to(YUKIMI) < 1.0:
			continue
		if BEACH.has_point(p):
			for o: float in [-0.35, 0.05]:
				if (k + int(o < 0.0)) % 2 == 0:
					items.append(item(S, "mesh", "rb_cob_%s" % "abc"[(k + int(o * 10.0)) % 3], p + out * o, rng.randf() * TAU,
						rng.randf_range(0.75, 1.1), "pond_beach", {"sink": 0.015}))
			continue
		var t: float = float(e[2]) / L_sh
		var gd := INF
		for g: float in groups:
			gd = minf(gd, absf(t - g) * L_sh)
		if gd < 0.26:
			# 主石（半入水、岸に食い込む）＋水際の卵石
			items.append(item(S, "mesh", "rb_bld_%s" % "abcde"[rng.randi() % 5], p - out * 0.12, rng.randf() * TAU,
				rng.randf_range(0.85, 1.15), "pond_stone", {"sink": 0.08}))
			items.append(item(S, "mesh", "rb_cob_%s" % "abc"[rng.randi() % 3], p - out * 0.55 + d * 0.4, rng.randf() * TAU,
				rng.randf_range(0.5, 0.7), "pond_beach", {"sink": 0.02}))
		elif gd < 1.6 and k % 2 == 0:
			var big := gd < 0.9
			var id := "gk_kei_low" if big else "gk_kei_flat"
			items.append(item(S, "mesh", id, p + out * 0.02, rng.randf() * TAU, rng.randf_range(0.5, 0.68) if big else rng.randf_range(0.38, 0.5),
				"pond_stone", {"sink": 0.05}))
		elif k % 6 == 0 and rng.randf() < 0.5:
			items.append(item(S, "mesh", "rb_cob_%s" % "abc"[rng.randi() % 3], p - out * 0.15, rng.randf() * TAU,
				rng.randf_range(0.5, 0.7), "pond_beach", {"sink": 0.02}))
	for q: Array in [[Vector2(416.6, -13.0), "momiji_a", 0.72], [Vector2(420.2, -14.6), "tsutsuji_a", 0.8],
			[Vector2(409.4, -11.4), "sasa_a", 0.7], [Vector2(405.6, -11.6), "sasa_a", 0.6], [Vector2(413.8, -11.3), "tsutsuji_a", 0.7],
			[Vector2(420.4, -24.8), "momiji_a", 0.55], [Vector2(420.6, -21.6), "fern_a", 0.9]]:
		items.append(item(S, "tree", String(q[1]), q[0], rng.randf() * TAU, float(q[2]), "pond_plant"))
	# ── 飛石（前庭池北岸 → 東側 → 沢飛び → 半島 → 石橋 → 後庭 → 蹲踞）
	var tob := ["gk_tobi_a", "gk_tobi_b", "gk_tobi_c", "gk_tobi_d"]
	var route: Array = []
	for pr: Array in [TOBI, TOBI_W]:
		var rs := resample(pr, 0.92)
		for k in rs.size():
			var e: Array = rs[k]
			var d: Vector2 = e[1]
			var side := Vector2(d.y, -d.x) * (0.1 if k % 2 == 0 else -0.1)
			route.append([(e[0] as Vector2) + side, d])
	for e: Array in route:
		var d: Vector2 = e[1]
		items.append(item(S, "mesh", tob[rng.randi() % 4], e[0], atan2(-d.y, d.x) + rng.randf_range(-0.4, 0.4),
			rng.randf_range(0.95, 1.15), "path_tobi"))
	# ── 曲水：沢飛び、石橋、溪石（水面高＝C["stream_y"]，沿平滑中心線）
	for p: Vector2 in SAWATOBI:
		var k := 0
		var best := INF
		for i in st.size():
			var dd := (st[i][0] as Vector2).distance_to(p)
			if dd < best:
				best = dd
				k = i
		var it := item(S, "mesh", "gk_tobi_c", p, 0.4, 1.05, "path_tobi", {"in_water": true})
		it["y"] = float(sy[k]) - 0.01
		items.append(it)
	for p: Vector2 in TOBI_REAR:
		items.append(item(S, "mesh", tob[rng.randi() % 4], p, rng.randf() * TAU, 1.05, "path_tobi"))
	# 石橋：橫跨曲水 (415.2,−55.2)–(413.9,−53.4) 段中點
	var ba: Vector2 = STREAM[2]
	var bb2: Vector2 = STREAM[3]
	var bc := (ba + bb2) * 0.5
	var bd := (bb2 - ba).normalized()
	var bp := Vector2(bd.y, -bd.x)
	var bridge := item(S, "mesh", "gk_bridge", bc, atan2(-bp.y, bp.x), 1.0, "bridge")
	bridge["y"] = maxf(ground_max(S, bc + bp * 0.85, 0.2), ground_max(S, bc - bp * 0.85, 0.2)) - 0.02
	items.append(bridge)
	# 溪石：外彎側岸石（半入水、食い込む）＋水中の卵石床（水面すれすれに頭を出す）；草の上に散らさない
	var sst := resample(sline, 0.8)
	for k in sst.size():
		var e: Array = sst[k]
		var sp: Vector2 = e[0]
		var d: Vector2 = e[1]
		var hw := stream_w(line_d(STREAM, sp).y) * 0.5
		var nn := Vector2(-d.y, d.x)
		if sp.distance_to(bc) < 1.4 or sp.distance_to(SAWATOBI[0]) < 0.8 or sp.distance_to(FALL_LIP) < 1.2:
			continue
		if GENKAN.grow(0.5).has_point(sp) or HOUSE_BASE.grow(0.3).has_point(sp):
			continue
		# 外彎：次站方向との外積で判定
		var d2: Vector2 = sst[mini(k + 1, sst.size() - 1)][1]
		var side := -signf(d.cross(d2)) if absf(d.cross(d2)) > 0.04 else (1.0 if k % 2 == 0 else -1.0)
		if k % 2 == 0:
			items.append(item(S, "mesh", "rb_cob_%s" % "abc"[k % 3], sp + nn * rng.randf_range(-0.25, 0.25) * hw, atan2(-d.y, d.x),
				rng.randf_range(0.5, 0.62), "stream_bed", {"sink": 0.0}))
		var q := sp + nn * side * (hw + rng.randf_range(-0.14, 0.02))
		if GENKAN.grow(0.5).has_point(q) or HOUSE_BASE.grow(0.3).has_point(q):
			continue
		var r := rng.randf()
		if r < 0.42:
			items.append(item(S, "mesh", "rb_bld_%s" % "abcde"[rng.randi() % 5], q, rng.randf() * TAU,
				rng.randf_range(0.45, 0.68), "stream_stone", {"sink": 0.04}))
		elif r < 0.7:
			items.append(item(S, "mesh", "gk_kei_low", q, rng.randf() * TAU, rng.randf_range(0.4, 0.52), "stream_stone", {"sink": 0.03}))
		if k % 5 == 2:
			# 対岸の小さな添石
			var q2 := sp - nn * side * (hw + rng.randf_range(-0.08, 0.04))
			if not (GENKAN.grow(0.5).has_point(q2) or HOUSE_BASE.grow(0.3).has_point(q2)):
				items.append(item(S, "mesh", "rb_bld_%s" % "abcde"[rng.randi() % 5], q2, rng.randf() * TAU,
					rng.randf_range(0.3, 0.42), "stream_stone", {"sink": 0.03}))
	# 滝石組（曲水源頭）：主石（鏡石、左奥・最高・幅広）＞ 脇石（右、主石の約半分）＞ 水落石（中奥、天端から水が落ちる）
	#   ＞ 波分石（滝壺の中）＞ 添石（前・左右、低い）。背後は濃い刈込み＋楓で牆を消し、石の明るさを際立たせる
	items.append(item(S, "mesh", "gk_kei_tall", Vector2(420.45, -59.0), 0.5, Vector3(1.4, 1.15, 1.15), "fall_stone", {"sink": 0.05, "foot_r": 0.28}))
	items.append(item(S, "mesh", "gk_kei_mid", Vector2(418.35, -58.95), 2.6, Vector3(1.05, 1.0, 0.95), "fall_stone", {"sink": 0.05}))
	items.append(item(S, "mesh", "gk_kei_low", FALL_LIP + Vector2(0.0, -0.32), 0.0, Vector3(0.95, 1.25, 0.75), "fall_lip", {"sink": 0.02}))
	items.append(item(S, "mesh", "gk_kei_low", Vector2(419.35, -58.05), 1.1, 0.42, "fall_stone", {"sink": 0.1}))
	items.append(item(S, "mesh", "gk_kei_low", Vector2(420.95, -57.35), 1.3, 0.62, "fall_stone", {"sink": 0.05}))
	items.append(item(S, "mesh", "gk_kei_flat", Vector2(417.85, -57.55), 2.8, 0.5, "fall_stone", {"sink": 0.03}))
	# 背景：滝口に枝を差し掛ける庭松（暗い緑で明るい石と白い落水を際立たせる）＋刈込み
	items.append(item(S, "tree", "niwamatsu_a", Vector2(418.55, -59.1), deg_to_rad(160.0), 0.8, "fall_plant", {"foot_r": 0.3}))
	items.append(item(S, "tree", "shrub_a", Vector2(417.2, -59.1), 1.9, 1.0, "fall_plant"))
	# ── 4 後庭（自然）：楓、自然形赤松、次生闊葉、灌木、蕨、笹；蹲踞＋織部燈籠
	for q: Array in [[Vector2(407.4, -58.6), "momiji_a", 0.9], [Vector2(400.6, -57.3), "momiji_a", 0.9],
			[Vector2(387.6, -56.6), "akamatsu_b", 0.5], [Vector2(392.6, -58.4), "shrub_a", 1.1],
			[Vector2(405.2, -58.6), "shrub_a", 1.0], [Vector2(396.8, -58.6), "sasa_a", 0.9], [Vector2(414.0, -58.5), "sasa_a", 0.8],
			[Vector2(385.6, -52.4), "shrub_a", 0.9], [Vector2(415.4, -56.9), "fern_a", 1.0], [Vector2(411.8, -52.0), "fern_a", 0.9],
			[Vector2(403.4, -55.6), "fern_a", 0.8], [Vector2(389.4, -50.8), "fern_a", 0.9], [Vector2(393.2, -53.6), "tsutsuji_a", 0.7],
			[Vector2(416.6, -53.6), "tsutsuji_a", 0.6], [Vector2(420.5, -52.0), "fern_a", 0.9], [Vector2(420.4, -44.0), "sasa_a", 0.7],
			[Vector2(420.4, -37.2), "fern_a", 0.8], [Vector2(385.4, -40.5), "fern_a", 0.9], [Vector2(385.8, -44.6), "shrub_a", 0.8],
			[Vector2(386.6, -36.4), "tsutsuji_a", 0.7],
			# 中層群（不只沿北牆一列）：次生闊葉＋灌木＋蕨
			[Vector2(401.4, -53.8), "momiji_a", 0.62], [Vector2(399.6, -54.6), "shrub_a", 0.8], [Vector2(402.6, -54.9), "fern_a", 0.9],
			[Vector2(390.6, -55.2), "tsutsuji_a", 0.75], [Vector2(389.2, -53.0), "fern_a", 0.8]]:
		items.append(item(S, "tree", String(q[1]), q[0], rng.randf() * TAU, float(q[2]), "rear_plant"))
	items.append(item(S, "mesh", "gk_tsukubai", TSUKUBAI, 0.0, 1.0, "tsukubai"))
	items.append(item(S, "mesh", "gk_toro_oribe", TSUKUBAI + Vector2(-1.45, -0.9), 0.3, 1.0, "lantern"))
	items.append(item(S, "mesh", "gk_kei_mid", Vector2(406.6, -56.4), 1.1, 0.66, "rear_stone"))
	items.append(item(S, "mesh", "gk_kei_low", Vector2(388.9, -54.4), 2.7, 0.7, "rear_stone"))
	items.append(item(S, "mesh", "gk_kei_low", Vector2(415.8, -52.8), 0.5, 0.45, "rear_stone"))
	# ── 竹垣：西側通路の四つ目垣（前庭と裏の仕切り）、玄關東袖垣
	for k in 3:
		items.append(item(S, "mesh", "gk_yotsume", Vector2(385.9 + k * 1.8, -33.6), 0.0, 1.0, "fence"))
	items.append(item(S, "mesh", "gk_sodegaki", Vector2(408.75, -33.2), 0.0, 1.0, "fence"))
	# ── 5 雨落ち縁石（本屋前後、玄關前を除く）
	for run: Array in [[Vector2(390.6, -31.25), Vector2(397.7, -31.25)], [Vector2(408.3, -31.25), Vector2(415.6, -31.25)],
			[Vector2(390.6, -47.75), Vector2(415.6, -47.75)], [Vector2(389.45, -32.2), Vector2(389.45, -47.3)]]:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n := int(floor(a.distance_to(b) / 0.92))
		var d := (b - a).normalized()
		for k in n:
			var p := a + d * (0.46 + k * 0.92)
			if p.distance_to(TSUKUBAI) < 1.4:
				continue
			items.append(item(S, "mesh", "gk_amaochi", p, atan2(-d.y, d.x), 1.0, "amaochi"))
	# 庭園地面 overlay（築山・岸の盛り／岸坡・滝壺・海の凹み）に載せる：origin ＋＝ lift（環 8 點 overlay 最低 − 地形最低）− sink
	for it: Dictionary in items:
		if it.get("in_water", false) or it.get("on_island", false) or String(it["tag"]) == "path_main" or String(it["id"]) == "gk_bridge":
			continue
		var f: Array = _foot(String(it["id"]) if String(it["kind"]) == "mesh" else "tree")
		var s3: Vector3 = it["sc"]
		var fr := float(it.get("foot_r", float(f[0]) * maxf(s3.x, s3.z)))
		if it.has("foot_r"):
			it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y)
			for k in 8:
				var q: Vector2 = it["p"] + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * fr
				it["y"] = minf(float(it["y"]), S.h(q.x, q.y))
		it["y"] = float(it["y"]) + lift(C, it["p"], fr) - float(it.get("sink", 0.0))
	# 滝：水落石の天端前緣（落水の起點）
	for it: Dictionary in items:
		if String(it["tag"]) == "fall_lip":
			var s3: Vector3 = it["sc"]
			C["fall_lip_y"] = float(it["y"]) + 0.4575 * s3.y - 0.03
			C["fall_lip_z"] = (it["p"] as Vector2).y + 0.43 * s3.z - 0.02
	C["items"] = items
	C["island"] = island
	C["ms"] = Time.get_ticks_msec() - t0
	return C


# ─────────────────────────── 地面 overlay（砂利／苔／延段目地／雨落ち／牆腳） ───────────────────────────

## 庭園地面權重（hg_ground.gdshader）：回傳 [COLOR(砂利, 苔, 土, 砂紋), UV2(濕潤, 砂紋方向 rad)]；w＝wctx()
static func ground_w(P: Dictionary, p: Vector2, w: Array) -> Array:
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var rk := 0.0
	var ang := 0.0
	var wet := 0.08
	var dpath := line_d(MAIN_PATH, p).x
	var front := p.y > -31.6 and p.y < -10.3
	var cherry := p.distance_to(CHERRY) < 2.9 + 0.35 * sin(atan2(p.y - CHERRY.y, p.x - CHERRY.x) * 3.0 + 0.7)
	if front and p.x < 398.0 - MAIN_W * 0.5 + 0.02:
		# 前庭西：白砂利（直線砂紋與主軸平行；苔島／主景石周り＝環紋、shader 側で CUSTOM0 の距離場から）；枝垂櫻下＝苔島
		if cherry:
			mo = 1.0
			wet = 0.15
		else:
			gv = 1.0
			rk = 1.0
			ang = -PI * 0.5
			wet = 0.0
	elif front and p.y < -27.6 and p.x > 391.0 and p.x < 405.8:
		# 玄關前 apron：砂利（砂紋與本屋平行）
		gv = 1.0
		rk = 0.8
		ang = 0.0
		wet = 0.0
	elif front and p.x < DIVIDER_X + 0.3:
		mo = 0.9
		wet = 0.12
	elif front:
		mo = 0.85
		wet = 0.15
	elif p.y < -47.3:
		mo = 0.55
		so = 0.25
		wet = 0.22
	else:
		if p.x < GL_HOUSE_X0:
			so = 0.55
			mo = 0.3
		else:
			mo = 0.6
			wet = 0.15
	if dpath < MAIN_W * 0.5 + 0.1:
		so = 0.85
		gv = 0.0
		mo = 0.0
		rk = 0.0
		wet = 0.1
	if EAVE.grow(0.2).has_point(p) and not HOUSE_BASE.grow(0.05).has_point(p) and not GENKAN.grow(0.3).has_point(p):
		gv = 1.0
		mo = 0.0
		so = 0.0
		rk = 0.0
		wet = 0.32
	var dw := minf(minf(p.x - ESTATE.position.x, ESTATE.end.x - p.x), minf(p.y - ESTATE.position.y, ESTATE.end.y - p.y))
	if dw < 0.45:
		gv = maxf(gv, 0.8)
		mo *= 0.3
		rk = 0.0
	if p.distance_to(TSUKUBAI) < 0.7:
		gv = 1.0
		mo = 0.0
		so = 0.0
		rk = 0.0
		wet = 0.65
	# 水際：水中＝濕土（底）、水線〜0.3 m＝濕土＋卵石帶（侵蝕で幅が変わる）、〜1.1 m＝濕った苔、州浜＝砂利（玉石）
	var dp: float = w[0]
	var o: float = w[1]
	var d := minf(dp, o)
	var ero: float = w[3] if dp <= o else w[4]
	if d < 1.4:
		# 水際帯：水中＝濕った小石底（砂利＋土）、水線〜band＝濕土（侵蝕で 0.04–0.22 m）→ 苔（濕）→ 地被
		var band := lerpf(0.04, 0.22, ero)
		if BEACH.grow(0.4).has_point(p) and dp < 1.0:
			gv = 1.0
			mo = 0.0
			so = 0.15
			rk = 0.0
			wet = 0.75 if dp < 0.15 else 0.45
		elif d < 0.0:
			gv = 0.85
			so = 0.15
			mo = 0.0
			rk = 0.0
			wet = 0.9
		else:
			var ts := smoothstep(band * 0.5, band + 0.18, d)
			var tm := smoothstep(band + 0.1, 1.4, d)
			so = lerpf(1.0, so * tm, ts)
			gv = lerpf(0.25 * ero, gv * tm, ts)
			mo = lerpf(0.0, maxf(mo * tm, 1.0 - tm), ts)
			rk *= tm
			wet = maxf(wet, lerpf(0.85, lerpf(0.42, wet, tm), ts))
	var tot := gv + mo + so
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
	return [Color(gv, mo, so, rk), Vector2(wet, ang)]


const GL_HOUSE_X0 := 390.6
## 築山（滝の背）中心／半徑／高（P1 地形は不改：庭園地面 overlay だけ盛る）
const TSUKIYAMA := Vector3(419.6, -59.6, 3.2)
const TSUKIYAMA_H := 1.0


## overlay の地形からの持ち上げ量（中心）＝ 驗證用
static func berm(P: Dictionary, p: Vector2) -> float:
	var S: RLib.TriSampler = P["S"]
	return surf(P, p) - S.h(p.x, p.y)


## 構件を overlay に載せる持ち上げ量：環 8 點（＋中心）の overlay 最低 − 地形最低
static func lift(P: Dictionary, p: Vector2, r: float) -> float:
	var S: RLib.TriSampler = P["S"]
	var ls := surf(P, p)
	var lt := S.h(p.x, p.y)
	for k in 8:
		var a := k * TAU / 8.0
		var q := p + Vector2(cos(a), sin(a)) * r
		ls = minf(ls, surf(P, q))
		lt = minf(lt, S.h(q.x, q.y))
	return ls - lt


const HG_SHADER := "res://assets/village_v2/garden_kit/hg_ground.gdshader"
const GROUND_STEP := 0.3
const FALLS_MAT := "res://assets/village_v2/garden_kit/GK_Falls.tres"


static func hg_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(HG_SHADER)
	m.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	m.resource_name = "HG_Ground"
	return m


static func ground_mesh(P: Dictionary) -> ArrayMesh:
	## 牆內全面（池底・溪床も含む＝岸は連続した斜面、水面はその斜面と交わる → 水際は格子でなく地面の等高線）
	var S: RLib.TriSampler = P["S"]
	var step := GROUND_STEP
	var nx := int(ceil(ESTATE.size.x / step))
	var nz := int(ceil(ESTATE.size.y / step))
	var H := {}
	var W := {}
	for j in nz + 1:
		for i in nx + 1:
			var p := ESTATE.position + Vector2(minf(i * step, ESTATE.size.x), minf(j * step, ESTATE.size.y))
			if is_nan(S.h(p.x, p.y)):
				continue
			var w := wctx(P, p)
			W[Vector2i(i, j)] = w
			H[Vector2i(i, j)] = surf(P, p, w)
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var U2 := PackedVector2Array()
	var CU := PackedFloat32Array()
	var idx := PackedInt32Array()
	var vid := {}
	for key: Vector2i in H:
		var p := ESTATE.position + Vector2(minf(key.x * step, ESTATE.size.x), minf(key.y * step, ESTATE.size.y))
		var h: float = H[key]
		var hx0: float = H.get(key + Vector2i(-1, 0), h)
		var hx1: float = H.get(key + Vector2i(1, 0), h)
		var hz0: float = H.get(key + Vector2i(0, -1), h)
		var hz1: float = H.get(key + Vector2i(0, 1), h)
		var nrm := Vector3(hx0 - hx1, 2.0 * step, hz0 - hz1).normalized()
		vid[key] = V.size()
		V.append(Vector3(p.x, h, p.y))
		N.append(nrm if nrm.is_finite() else Vector3.UP)
		var gw: Array = ground_w(P, p, W[key])
		C.append(gw[0])
		U2.append(gw[1])
		var rf := ring_f(p) if (gw[0] as Color).a > 0.5 else [9.0, 0.0, 0.0, 1.0]
		CU.append_array([float(rf[0]), float(rf[1]), float(rf[2]), float(rf[3])])
	for j in nz:
		for i in nx:
			var c := ESTATE.position + Vector2((i + 0.5) * step, (j + 0.5) * step)
			if HOUSE_BASE.grow(-0.3).has_point(c):
				continue
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			# 對角線取高度差小的一邊（岸坡の折れ目を等高線方向に）
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_CUSTOM0] = CU
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.surface_set_material(0, hg_material())
	am.resource_name = "hg_ground"
	return am


# ─────────────────────────── 水（池＋中島＋曲水） ───────────────────────────

static func _tri(V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		col: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	for q in [a, b, c]:
		V.append(q)
		N.append(n)
		C.append(col)


static func water_mesh(P: Dictionary) -> ArrayMesh:
	## 水面＝池・曲水の外へ 0.3 m 張り出した平面 → 岸坡（ground overlay）と交わる線が水際（多角形の辺は地面の下に隠れる）。
	## 水は GK_PondWater（depth 差で淺瀬が透ける → 水際にグラデーション）。
	var wl: float = P["water_y"]
	var pond: PackedVector2Array = P["pond"]
	var Vw := PackedVector3Array()
	var Nw := PackedVector3Array()
	var Cw := PackedColorArray()
	var pond_x: PackedVector2Array = Geometry2D.offset_polygon(pond, 0.3, Geometry2D.JOIN_ROUND)[0]
	var tri := Geometry2D.triangulate_polygon(pond_x)
	for k in range(0, tri.size(), 3):
		var A := Vector3(pond_x[tri[k]].x, wl, pond_x[tri[k]].y)
		var B := Vector3(pond_x[tri[k + 1]].x, wl, pond_x[tri[k + 1]].y)
		var Cc := Vector3(pond_x[tri[k + 2]].x, wl, pond_x[tri[k + 2]].y)
		if (B - A).cross(Cc - A).y < 0.0:
			_tri(Vw, Nw, Cw, A, B, Cc, Color.WHITE)
		else:
			_tri(Vw, Nw, Cw, A, Cc, B, Color.WHITE)
	var SCOL := Color(1.0, 0.0, 1.0)      # 曲水：g＝0 → shader で淺さを ×6（溪は 3–5 cm しか深さがない）
	# 曲水水面（平滑中心線、半幅＋0.3；池の中に入る區間は池面に任せる）
	var st: Array = P["stream"]
	var sy: Array = P["stream_y"]
	for k in st.size() - 1:
		var p0: Vector2 = st[k][0]
		var p1: Vector2 = st[k + 1][0]
		if Geometry2D.is_point_in_polygon(p0, pond) and Geometry2D.is_point_in_polygon(p1, pond):
			continue
		var d0: Vector2 = st[k][1]
		var d1: Vector2 = st[k + 1][1]
		var w0 := stream_w(line_d(STREAM, p0).y) * 0.5 + 0.3
		var w1 := stream_w(line_d(STREAM, p1).y) * 0.5 + 0.3
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var a := Vector3(p0.x + n0.x * w0, sy[k], p0.y + n0.y * w0)
		var b := Vector3(p0.x - n0.x * w0, sy[k], p0.y - n0.y * w0)
		var c := Vector3(p1.x - n1.x * w1, sy[k + 1], p1.y - n1.y * w1)
		var d := Vector3(p1.x + n1.x * w1, sy[k + 1], p1.y + n1.y * w1)
		for t: Array in [[a, b, c], [a, c, d]]:
			var A: Vector3 = t[0]
			var B: Vector3 = t[1]
			var Cc: Vector3 = t[2]
			if (B - A).cross(Cc - A).y < 0.0:
				_tri(Vw, Nw, Cw, A, B, Cc, SCOL)
			else:
				_tri(Vw, Nw, Cw, A, Cc, B, SCOL)
	# 滝壺（曲水起點の円形淵、半徑＝起點半幅＋0.3）
	var s0: Vector2 = st[0][0]
	var r0 := stream_w(0.0) * 0.5 + 0.3
	for k in 14:
		var a0 := k * TAU / 14.0
		var a1 := (k + 1) * TAU / 14.0
		var A := Vector3(s0.x, float(sy[0]), s0.y)
		var B := Vector3(s0.x + cos(a0) * r0, float(sy[0]), s0.y + sin(a0) * r0)
		var Cc := Vector3(s0.x + cos(a1) * r0, float(sy[0]), s0.y + sin(a1) * r0)
		if (B - A).cross(Cc - A).y < 0.0:
			_tri(Vw, Nw, Cw, A, B, Cc, SCOL)
		else:
			_tri(Vw, Nw, Cw, A, Cc, B, SCOL)
	# 中島：池面から盛り上がる苔丘（側面は岸と同じく水中へ潜る）
	var isl: PackedVector2Array = P["island"]
	var ctr := Vector2.ZERO
	for q in isl:
		ctr += q
	ctr /= isl.size()
	var Vi := PackedVector3Array()
	var Ni := PackedVector3Array()
	var Ci := PackedColorArray()
	var U2i := PackedVector2Array()
	var top := Vector3(ctr.x, wl + 0.42, ctr.y)
	for i in isl.size():
		var a := isl[i]
		var b := isl[(i + 1) % isl.size()]
		var A := Vector3(a.x, wl + 0.1, a.y)
		var B := Vector3(b.x, wl + 0.1, b.y)
		var ao := ctr + (a - ctr) * 1.18
		var bo := ctr + (b - ctr) * 1.18
		var Ab := Vector3(ao.x, wl - 0.12, ao.y)
		var Bb := Vector3(bo.x, wl - 0.12, bo.y)
		for t: Array in [[top, B, A], [A, B, Bb], [A, Bb, Ab]]:
			var n := ((t[2] as Vector3) - (t[0] as Vector3)).cross((t[1] as Vector3) - (t[0] as Vector3)).normalized()
			for q: Vector3 in t:
				Vi.append(q)
				Ni.append(n)
				var low := q.y < wl + 0.05
				Ci.append(Color(0.0, 0.0, 1.0, 0.0) if low else Color(0.0, 1.0, 0.0, 0.0))
				U2i.append(Vector2(0.85 if low else 0.3, 0.0))
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = Vw
	arr[Mesh.ARRAY_NORMAL] = Nw
	arr[Mesh.ARRAY_COLOR] = Cw
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, load(POND_WATER_MAT))
	var ar3 := []
	ar3.resize(Mesh.ARRAY_MAX)
	ar3[Mesh.ARRAY_VERTEX] = Vi
	ar3[Mesh.ARRAY_NORMAL] = Ni
	ar3[Mesh.ARRAY_COLOR] = Ci
	ar3[Mesh.ARRAY_TEX_UV2] = U2i
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar3)
	am.surface_set_material(1, hg_material())
	# 落水（滝）：水落石の天端前緣 → 滝壺。主流＋副流の簾（UV：x＝幅 0..1、y＝落下 0..1；COLOR.r＝1 簾）
	#   ＋滝壺の白泡（UV＝放射座標 −1..1；COLOR.r＝0 泡）。shader（hg_falls）で筋・スクロール・縁のフェード。
	var sy0: float = sy[0]
	var Vf := PackedVector3Array()
	var Nf := PackedVector3Array()
	var Cf := PackedColorArray()
	var Uf := PackedVector2Array()
	var lip_y: float = P.get("fall_lip_y", sy0 + 0.74)
	var fz: float = P.get("fall_lip_z", FALL_LIP.y)
	for sh: Array in [[FALL_LIP.x - 0.04, 0.2, 0.0], [FALL_LIP.x + 0.23, 0.07, 0.04]]:
		var cx: float = sh[0]
		var hw: float = sh[1]
		var dz: float = sh[2]
		var rows: Array = []
		for k in 5:
			var tt := k / 4.0
			var yy := lerpf(lip_y - dz, sy0 + 0.01, tt)
			var zz := fz + 0.03 + 0.2 * tt * tt
			var ww := hw * (1.0 + 0.3 * tt)
			rows.append([Vector3(cx - ww, yy, zz), Vector3(cx + ww, yy, zz), tt])
		for k in 4:
			var a: Array = rows[k]
			var b: Array = rows[k + 1]
			var q := [a[0], a[1], b[1], b[0]]
			var uv := [Vector2(0, a[2]), Vector2(1, a[2]), Vector2(1, b[2]), Vector2(0, b[2])]
			for tr: Array in [[0, 2, 1], [0, 3, 2]]:
				var A: Vector3 = q[tr[0]]
				var B: Vector3 = q[tr[1]]
				var Cc: Vector3 = q[tr[2]]
				var n := (Cc - A).cross(B - A).normalized()
				for m in 3:
					Vf.append(q[tr[m]])
					Nf.append(n)
					Cf.append(Color(1, 1, 1))
					Uf.append(uv[tr[m]])
	var fc := Vector3(FALL_LIP.x + 0.04, sy0 + 0.016, fz + 0.36)
	for k in 12:
		var a0 := k * TAU / 12.0
		var a1 := (k + 1) * TAU / 12.0
		var q := [fc, fc + Vector3(cos(a1) * 0.62, 0, sin(a1) * 0.46), fc + Vector3(cos(a0) * 0.62, 0, sin(a0) * 0.46)]
		var uv := [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]
		for m in 3:
			Vf.append(q[m])
			Nf.append(Vector3.UP)
			Cf.append(Color(0, 1, 1))
			Uf.append(uv[m])
	var ar4 := []
	ar4.resize(Mesh.ARRAY_MAX)
	ar4[Mesh.ARRAY_VERTEX] = Vf
	ar4[Mesh.ARRAY_NORMAL] = Nf
	ar4[Mesh.ARRAY_COLOR] = Cf
	ar4[Mesh.ARRAY_TEX_UV] = Uf
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar4)
	am.surface_set_material(2, load(FALLS2_MAT))
	am.resource_name = "hg_water"
	return am


static func ground_mesh_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GROUND_SHADER)
	m.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	m.set_shader_parameter("ground_k", 0.19)
	m.set_shader_parameter("mode", 0)
	m.set_shader_parameter("use_vertex_weights", true)
	return m


# ─────────────────────────── 烘焙 ───────────────────────────

static func xf_of(it: Dictionary) -> Transform3D:
	var p: Vector2 = it["p"]
	var b := Basis(Vector3.UP, float(it["yaw"])).scaled(it["sc"])
	return Transform3D(b, Vector3(p.x, float(it["y"]), p.y))


## 構件碰撞（local）：[shape, local xf]；空＝無碰撞（可踩：延段、飛石、縁石、伏石、小石）
static func coll_of(id: String) -> Array:
	match id:
		"gk_toro_kasuga":
			return [_cyl(0.32, 1.9, 0.95)]
		"gk_toro_yukimi":
			return [_cyl(0.52, 1.0, 0.5)]
		"gk_toro_oribe":
			return [_cyl(0.25, 1.3, 0.65)]
		"gk_tsukubai":
			return [_cyl(0.38, 0.5, 0.25), _box(Vector3(0.12, 1.0, 0.12), Vector3(0.0, 0.5, -0.95))]
		"gk_kei_tall":
			return [_cyl(0.36, 1.45, 0.72)]
		"gk_kei_mid":
			return [_cyl(0.4, 0.95, 0.47)]
		"gk_kei_low":
			return [_cyl(0.45, 0.45, 0.22)]
		"gk_yotsume":
			return [_box(Vector3(1.86, 1.0, 0.12), Vector3(0.0, 0.5, 0.0))]
		"gk_sodegaki":
			return [_box(Vector3(1.06, 1.7, 0.1), Vector3(0.0, 0.85, 0.0))]
		"gk_bridge":
			return [_box(Vector3(1.8, 0.2, 0.55), Vector3(0.0, -0.04, 0.0))]
	if id.begins_with("rb_bld"):
		return [_cyl(0.42, 0.65, 0.32)]
	return []


static func _cyl(r: float, h: float, cy: float) -> Array:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return [c, Transform3D(Basis.IDENTITY, Vector3(0, cy, 0))]


static func _box(sz: Vector3, c: Vector3) -> Array:
	var b := BoxShape3D.new()
	b.size = sz
	return [b, Transform3D(Basis.IDENTITY, c)]


const NO_SHADOW_PREFIX := ["gk_nobe", "gk_tobi", "gk_amaochi", "rb_cob"]


static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = ground_mesh(P)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	var w := MeshInstance3D.new()
	w.name = "Water"
	w.mesh = water_mesh(P)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.set_meta("water_y", P["water_y"])
	root.add_child(w)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var plants := Node3D.new()
	plants.name = "Plants"
	root.add_child(plants)
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var groups := {}
	var meshes := {}
	var n := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var tag := String(it["tag"])
		var xf := xf_of(it)
		if String(it["kind"]) == "tree":
			var t: Node3D = (load(TREES + id + ".tscn") as PackedScene).instantiate()
			if it.has("tint"):
				# 色調：instance uniform は instanced scene の子に設定しても .scn に保存されない（R4 r1 實測 null）
				#   → tint 指定の樹は prefab を展開して自前の Node3D（LOD 複製・mesh 共有＋Collision 複製）にする。
				var tn: Array = it["tint"]
				var t2 := Node3D.new()
				for mi: MeshInstance3D in t.find_children("LOD*", "MeshInstance3D", false, false):
					var cp := MeshInstance3D.new()
					cp.name = mi.name
					cp.mesh = mi.mesh
					for prop in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin",
							"visibility_range_end_margin", "visibility_range_fade_mode", "cast_shadow"]:
						cp.set(prop, mi.get(prop))
					for u: String in ["lod_band", "lod_ref"]:
						var val: Variant = mi.get_instance_shader_parameter(u)
						if val != null:
							cp.set_instance_shader_parameter(u, val)
					cp.set_instance_shader_parameter("leaf_tint", tn[0])
					cp.set_instance_shader_parameter("leaf_sat", tn[1])
					t2.add_child(cp)
				var tc := t.get_node_or_null("Collision")
				if tc:
					var c2 := tc.duplicate()
					t2.add_child(c2)
				for cp: MeshInstance3D in t2.find_children("LOD*", "MeshInstance3D", false, false):
					cp.layers = 1 | VIS_LAYER_SAKURA
				var fl := OmniLight3D.new()
				fl.name = "WarmFill"
				fl.position = SAKURA_FILL["pos"]
				fl.omni_range = SAKURA_FILL["range"]
				fl.light_energy = SAKURA_FILL["energy"]
				fl.light_color = SAKURA_FILL["color"]
				fl.light_cull_mask = VIS_LAYER_SAKURA
				fl.shadow_enabled = false
				fl.light_specular = 0.0
				t2.add_child(fl)
				t2.set_meta("veg_id", id)
				t2.set_meta("tint", tn)
				t.free()
				t = t2
			t.name = "%03d_%s" % [n, id]
			t.transform = xf
			t.set_meta("garden_tag", tag)
			plants.add_child(t)
			if not it.has("tint"):
				var pr: Array = TreeLib.COLOR_PRESETS[String(it.get("preset", "mature"))]
				for mi in t.find_children("*", "MeshInstance3D", false, false):
					(mi as MeshInstance3D).set_instance_shader_parameter("leaf_tint", pr[0])
					(mi as MeshInstance3D).set_instance_shader_parameter("leaf_sat", pr[1])
			n += 1
			continue
		if not groups.has(tag):
			var gn := Node3D.new()
			gn.name = tag
			props.add_child(gn)
			groups[tag] = gn
		var node := Node3D.new()
		node.name = "%03d_%s" % [n, id]
		node.transform = xf
		node.set_meta("garden_id", id)
		node.set_meta("garden_tag", tag)
		(groups[tag] as Node).add_child(node)
		var dir := GK if id.begins_with("gk_") else RB
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 260.0
			var noshadow := false
			for pf: String in NO_SHADOW_PREFIX:
				if id.begins_with(pf):
					noshadow = true
			if noshadow or lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		for c: Array in coll_of(id):
			var cs := CollisionShape3D.new()
			cs.name = "%s_%d" % [node.name, ns]
			cs.shape = c[0]
			cs.transform = xf * (c[1] as Transform3D)
			# 縮放不進 shape：把縮放烘進尺寸（Godot 碰撞不支援非等比縮放）
			var s: Vector3 = it["sc"]
			cs.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), cs.transform.origin)
			if c[0] is CylinderShape3D:
				var cy := (c[0] as CylinderShape3D).duplicate() as CylinderShape3D
				cy.radius *= maxf(s.x, s.z)
				cy.height *= s.y
				cs.shape = cy
			elif c[0] is BoxShape3D:
				var bx := (c[0] as BoxShape3D).duplicate() as BoxShape3D
				bx.size *= s
				cs.shape = bx
			cs.set_meta("garden_id", id)
			col.add_child(cs)
			ns += 1
		n += 1
	# 池：擋人（池面三角柱，水面下 0.3 → 上 0.6）
	var pond: PackedVector2Array = P["pond"]
	var wl: float = P["water_y"]
	var tri := Geometry2D.triangulate_polygon(pond)
	for k in range(0, tri.size(), 3):
		var pts := PackedVector3Array()
		for q in [pond[tri[k]], pond[tri[k + 1]], pond[tri[k + 2]]]:
			pts.append(Vector3(q.x, wl - 0.3, q.y))
			pts.append(Vector3(q.x, wl + 0.6, q.y))
		var cv := ConvexPolygonShape3D.new()
		cv.points = pts
		var cs := CollisionShape3D.new()
		cs.name = "Pond_%d" % (k / 3)
		cs.shape = cv
		cs.set_meta("garden_id", "pond")
		col.add_child(cs)
		ns += 1
	var mound := PackedVector3Array()
	var S2: RLib.TriSampler = P["S"]
	for k in 12:
		var a := k * TAU / 12.0
		for rr: float in [TSUKIYAMA.z, TSUKIYAMA.z * 0.5]:
			var q := Vector2(TSUKIYAMA.x + cos(a) * rr, TSUKIYAMA.y + sin(a) * rr)
			q = q.clamp(ESTATE.position + Vector2(0.35, 0.35), ESTATE.end - Vector2(0.35, 0.35))
			mound.append(Vector3(q.x, S2.h(q.x, q.y) + berm(P, q), q.y))
			mound.append(Vector3(q.x, S2.h(q.x, q.y) - 0.3, q.y))
	var tc := Vector2(TSUKIYAMA.x, TSUKIYAMA.y).clamp(ESTATE.position + Vector2(0.35, 0.35), ESTATE.end - Vector2(0.35, 0.35))
	mound.append(Vector3(tc.x, S2.h(tc.x, tc.y) + berm(P, tc), tc.y))
	var cvm := ConvexPolygonShape3D.new()
	cvm.points = mound
	var csm := CollisionShape3D.new()
	csm.name = "Tsukiyama"
	csm.shape = cvm
	csm.set_meta("garden_id", "tsukiyama")
	col.add_child(csm)
	ns += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("water_y", wl)
	root.set_meta("art_revision", "P9 R4 稗田邸庭園 r2 targeted polish：池岸／曲水接地、滝石組、前庭環紋、蹲踞、枝垂櫻 tint（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)
