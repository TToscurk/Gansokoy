extends RefCounted
## TASK E FINAL（使用者 2026-10-18）：社寺取消。現行設計（HF_design.json v1 woodland）不再有 Ground／草株抑制；
## 下面的境內地面函式（design()／ground_mesh()）只在設計含 "ground" 時被 build_hf_precinct.gd 使用（E2 舊設計，保留供還原）。
## 丘腳社寺 E2（2026-10-17 使用者 TASK E2）：境內環境の地面・抑制の共通庫。
## 設計の幾何は res://data/district/HF_design.json（Blender 配置・verify と共通）。
## 重用：地面は P9 R4-2 神社周邊のシェーダ sg_ground（shrine_grove/sg_ground.gdshader・唯讀）＋ SG.sg_material()、地形は RLib.terrain_sampler（唯讀）。
##   新しい shader・材質・mesh 形状は作らない。重ね描きの Z-fight は『地形＋lift（既存の重ね層は ≤ +0.019）』で避ける。
## 抑制（既存 EnvironmentP9 の E082 垣断片＋境内の MeadowP9／GroundcoverP9 の草株）は overlay の script（hillfoot_precinct_e2.gd）が可逆に行う。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")

const DESIGN := "res://data/district/HF_design.json"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const NODE_NAME := "HillfootPrecinctE2"
const OUTPUT := "res://maps/village_v2/gen/hillfoot_precinct_e2.scn"
const SCRIPT := "res://maps/village_v2/scripts_p13/hillfoot_precinct_e2.gd"
const DISTRICT_NODE := "DistrictHF"
const ART_REVISION := "TASK E FINAL 丘腳林地（社寺取消→自然林；ART_REVIEW・未經使用者 ART_APPROVED）"

static var _D: Dictionary = {}
static var _noise: Dictionary = {}


static func design() -> Dictionary:
	if not _D.is_empty():
		return _D
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	var d := {}
	d["raw"] = j
	d["court"] = _pv(j["court"])
	d["app_pts"] = _pv(j["approach"]["pts"])
	d["app_hw"] = j["approach"]["half_w"]
	d["clear_margin"] = float(j["approach"]["clear_margin"])
	d["flanks"] = []
	for f: Dictionary in j["flank_paths"]:
		(d["flanks"] as Array).append({"name": f["name"], "pts": _pv(f["pts"]), "hw": float(f["half_w"])})
	d["gravel"] = []
	for g: Dictionary in j["gravel"]:
		(d["gravel"] as Array).append({"c": Vector2(g["center"][0], g["center"][1]), "rx": float(g["rx"]), "rz": float(g["rz"])})
	d["stair_foot"] = Vector2(j["stair_foot"][0], j["stair_foot"][1])
	var sb: Array = j["shrine_box"]
	d["box"] = Rect2(sb[0], sb[1], sb[2], sb[3])
	d["street_z"] = float(j["street_edge_z"])
	var gr: Dictionary = j["ground"]
	var rg: Array = gr["region"]
	d["region"] = Rect2(rg[0], rg[1], rg[2], rg[3])
	d["step"] = float(gr["step"])
	d["lift"] = float(gr["lift"])
	d["min_clear"] = float(gr["min_clear"])
	d["mm_polys"] = []
	for poly: Array in j["suppress"]["mm_polys"]:
		(d["mm_polys"] as Array).append(_pv(poly))
	d["mm_margin"] = float(j["suppress"]["mm_margin"])
	_D = d
	return _D


static func _pv(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


# ───────────────────────── 幾何 ─────────────────────────

static func seg_d(p: Vector2, a: Vector2, b: Vector2) -> Array:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 == 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return [p.distance_to(a + ab * t), t]


static func poly_d(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, float(seg_d(p, poly[i], poly[(i + 1) % poly.size()])[0]))
	return best


## 符号付き距離（内側が +）
static func sd(poly: PackedVector2Array, p: Vector2) -> float:
	var d := poly_d(poly, p)
	return d if Geometry2D.is_point_in_polygon(p, poly) else -d


## 折れ線までの [距離, 弧長 s]
static func line_info(pts: PackedVector2Array, p: Vector2) -> Array:
	var best := [INF, 0.0]
	var acc := 0.0
	for i in pts.size() - 1:
		var r := seg_d(p, pts[i], pts[i + 1])
		var l := pts[i].distance_to(pts[i + 1])
		if float(r[0]) < float(best[0]):
			best = [r[0], acc + float(r[1]) * l]
		acc += l
	return best


static func line_len(pts: PackedVector2Array) -> float:
	var acc := 0.0
	for i in pts.size() - 1:
		acc += pts[i].distance_to(pts[i + 1])
	return acc


static func app_hw_at(s: float) -> float:
	var hw: Array = design()["app_hw"]
	if s <= float(hw[0][0]):
		return float(hw[0][1])
	for i in hw.size() - 1:
		var s0 := float(hw[i][0])
		var s1 := float(hw[i + 1][0])
		if s >= s0 and s <= s1:
			return lerpf(float(hw[i][1]), float(hw[i + 1][1]), (s - s0) / (s1 - s0))
	return float(hw[hw.size() - 1][1])


## 参道の [中心線距離, s, 半幅, 内側距離（半幅 − 距離。内側が +）]（雑訊なし）
static func app_info(p: Vector2) -> Array:
	var li := line_info(design()["app_pts"], p)
	var hw := app_hw_at(float(li[1]))
	return [li[0], li[1], hw, hw - float(li[0])]


## 抑制多邊形（mm_polys）に margin 込みで入るか
static func in_mm_polys(p: Vector2, margin: float) -> bool:
	for poly: PackedVector2Array in design()["mm_polys"]:
		if Geometry2D.is_point_in_polygon(p, poly) or poly_d(poly, p) <= margin:
			return true
	return false


static func _n(i: int, p: Vector2, f: float) -> float:
	if not _noise.has(i):
		var nz := FastNoiseLite.new()
		nz.seed = 7100 + i * 31
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 1.0
		_noise[i] = nz
	return 0.5 + 0.5 * (_noise[i] as FastNoiseLite).get_noise_2d(p.x * f, p.y * f)


# ───────────────────────── 地面権重 ─────────────────────────
## sg_ground の頂點屬性：COLOR＝(玉砂利/細礫 gv, 苔 mo, 踏み固め土 so, 落葉 li)・UV2＝(湿 wet, 外縁淡出 fade)・残り＝草。
## 設計：『何でできているか（組成）』と『どこまで描くか（被覆＝fade）』を分ける。
##   · 被覆 fade＝3 つの形（前庭・参道・脇の踏み跡）の符号付き距離の最大 e_in から（外縁は shader が雜訊 dither で崩す）。
##   · 組成＝最も近い形の組成（土・細礫・苔…）を外縁の fade 帯の中でも保つ → 縁で残る画素は『草の濃い緑』ではなく『土の斑点』になる
##     （r1 実測：残余の草が地形の草より約 7 % 暗く、縁が暗い緑の面に見えた）。内側の草の残余は 3 % 未満。
## 戻り値＝[Color, Vector2, e_in]（fade ≤ 0 の所は null）。
static func ground_w(p: Vector2) -> Variant:
	var D := design()
	var n1 := _n(0, p, 0.18)
	var n2 := _n(1, p, 0.55)
	var n3 := _n(2, p, 1.7)
	var n4 := _n(3, p, 0.9)
	var court: PackedVector2Array = D["court"]
	var dc := sd(court, p) + (n1 - 0.5) * 1.3 + (n2 - 0.5) * 0.7 + (n3 - 0.5) * 0.35
	var ai := app_info(p)
	var hw_mod := 1.0 + (_n(4, Vector2(float(ai[1]) * 0.35, 3.1), 1.0) - 0.5) * 0.45
	var e_app := float(ai[2]) * hw_mod - float(ai[0]) + (n2 - 0.5) * 1.9 + (n3 - 0.5) * 1.0
	var e_fl := -99.0
	var fl_d := 99.0
	for f: Dictionary in D["flanks"]:
		var li := line_info(f["pts"], p)
		fl_d = minf(fl_d, float(li[0]))
		e_fl = maxf(e_fl, float(f["hw"]) * (1.0 + (n4 - 0.5) * 0.5) - float(li[0]) + (n3 - 0.5) * 0.5)
	var best := maxf(dc, maxf(e_app, e_fl))
	var fade := smoothstep(-2.9, -0.3, best)
	if fade <= 0.0:
		return null
	# 組成の配分（最も近い形が主）
	var wc := exp((dc - best) * 2.2)
	var wa := exp((e_app - best) * 2.2)
	var wf := exp((e_fl - best) * 2.2)
	var ws := wc + wa + wf
	wc /= ws
	wa /= ws
	wf /= ws
	# 前庭の組成：踏み固めた土を主に、細礫の斑。石段前は細礫が濃い
	var gz := 0.0
	for g: Dictionary in D["gravel"]:
		var q := p - (g["c"] as Vector2)
		var gq := (q.x / float(g["rx"])) * (q.x / float(g["rx"])) + (q.y / float(g["rz"])) * (q.y / float(g["rz"])) + (n2 - 0.5) * 1.5 + (n3 - 0.5) * 0.7
		gz = maxf(gz, 1.0 - smoothstep(0.45, 1.15, gq))
	var north := smoothstep(-174.0, -178.0, p.y)
	var so_c := (0.50 + (n3 - 0.5) * 0.26 + (n1 - 0.5) * 0.2)
	var gv_c := 0.20 + n4 * 0.26
	gv_c = lerpf(gv_c, 0.58, gz)
	so_c = lerpf(so_c, 0.32, gz)
	var mo_c := (0.06 + 0.34 * north) * (0.35 + 0.65 * n2)
	so_c *= 1.0 - mo_c * 0.5
	var wet_c := 0.10 * north
	# 参道の組成：踏み固めた土＋砂利っけ。縁は苔気
	var edge := 1.0 - smoothstep(0.0, 0.9, clampf(e_app, -2.0, 2.0))
	var so_a := 0.70 + (n3 - 0.5) * 0.22
	var gv_a := 0.10 + 0.20 * smoothstep(0.35, 0.8, n4)
	# 丘腳街との接ぎ：街路の明るい土色へつなぐため、口元（弧長 s の小さい側）は細礫が多い（路面からこぼれた砂利）
	var spill := 1.0 - smoothstep(0.6, 3.4, float(ai[1]))
	gv_a = lerpf(gv_a, 0.46, spill)
	so_a = lerpf(so_a, 0.48, spill)
	var mo_a := 0.12 * edge * n2
	var wear := 1.0 - smoothstep(0.0, 0.85, float(ai[0]))
	var wet_a := 0.09 * wear
	# 脇の踏み跡：濃い踏み固め土
	var so_f := 0.78 + (n3 - 0.5) * 0.2
	var gv_f := 0.06
	var wet_f := 0.07 * (1.0 - smoothstep(0.0, 0.7, fl_d))
	var so := wc * so_c + wa * so_a + wf * so_f
	var gv := wc * gv_c + wa * gv_a + wf * gv_f
	var mo := wc * mo_c + wa * mo_a
	var wet := wc * wet_c + wa * wet_a + wf * wet_f
	var li_w := 0.0
	# 外縁：林縁側に落葉
	if best < 0.5:
		var shade := smoothstep(-163.0, -170.0, p.y)
		li_w = (0.10 + 0.22 * n1) * smoothstep(0.5, -1.0, best) * (0.4 + 0.6 * shade)
	# 草の残余は 3 % 未満に（内側で草が斑に顔を出さない）。fade 帯の外では shader が dither で消す
	var tot := gv + mo + so + li_w
	var k := 0.97 / maxf(tot, 0.001)
	gv *= k
	mo *= k
	so *= k
	li_w *= k
	return [Color(gv, mo, so, li_w), Vector2(wet, fade), best]


# ───────────────────────── 地面メッシュ（地形に沿わせる・sg_ground 材質） ─────────────────────────
## 頂点は地形（RLib.TriSampler＝可視地形メッシュの重心座標）＋ lift。三角形の内部標本で地形に潜る所は『上にだけ』持ち上げる
## （P13 W6 の教訓：頂点だけで沿わせると三角形の内側で地形に潜り、地形の岩層が三角形で顔を出す）。
static func ground_mesh(S: RLib.TriSampler) -> Dictionary:
	var D := design()
	var R: Rect2 = D["region"]
	var step: float = D["step"]
	var lift: float = D["lift"]
	var clear: float = D["min_clear"]
	var box: Rect2 = (D["box"] as Rect2).grow(-0.15)
	var street_z: float = D["street_z"]
	var nx := int(ceil(R.size.x / step))
	var nz := int(ceil(R.size.y / step))
	var V := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var vid := {}
	# 先に全格点の重みを計算し、被覆のある格点の外側 1 周も頂点にする（被覆 0）：
	# 開放境界の頂点がすべて被覆 0 になり、shader の外縁淡出と合わせて『線』が出ない
	var Wt := {}
	for j in nz + 1:
		for i in nx + 1:
			var p0 := R.position + Vector2(i * step, j * step)
			var w0: Variant = ground_w(p0)
			if w0 != null:
				Wt[Vector2i(i, j)] = w0
	for j in nz + 1:
		for i in nx + 1:
			var key := Vector2i(i, j)
			var w: Variant = Wt.get(key)
			if w == null:
				var near := false
				for dj in range(-1, 2):
					for di in range(-1, 2):
						if Wt.has(Vector2i(i + di, j + dj)):
							near = true
				if not near:
					continue
			var p := R.position + Vector2(i * step, j * step)
			var h := S.h(p.x, p.y)
			if is_nan(h):
				continue
			vid[key] = V.size()
			V.append(Vector3(p.x, h + lift, p.y))
			if w == null:
				Cc.append(Color(0, 0, 1, 0))
				U2.append(Vector2(0, 0))
			else:
				Cc.append((w as Array)[0])
				# 区画の外周は fade＝0（外縁の淡出が効かない開放境界が『線』にならないように）
				var bd := minf(minf(p.x - R.position.x, R.end.x - p.x), minf(p.y - R.position.y, R.end.y - p.y))
				var uv: Vector2 = (w as Array)[1]
				U2.append(Vector2(uv.x, uv.y * smoothstep(0.0, 1.5, bd)))
	var idx := PackedInt32Array()
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			var c := R.position + Vector2((i + 0.5) * step, (j + 0.5) * step)
			if box.has_point(c):
				continue
			if c.y > street_z + 0.45:
				continue          # 街路（丘腳街）の中には描かない
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	# 三角形内部の標本で潜る所を持ち上げる
	var raised := 0
	var max_raise := 0.0
	for pass_i in 4:
		var need := {}
		for t in range(0, idx.size(), 3):
			var a := V[idx[t]]
			var b := V[idx[t + 1]]
			var cc := V[idx[t + 2]]
			for bc: Array in [[1.0 / 3.0, 1.0 / 3.0], [0.5, 0.5], [0.5, 0.0], [0.0, 0.5], [0.25, 0.25], [0.6, 0.2], [0.2, 0.6]]:
				var u: float = bc[0]
				var v: float = bc[1]
				var w := 1.0 - u - v
				var px := a.x * u + b.x * v + cc.x * w
				var pz := a.z * u + b.z * v + cc.z * w
				var oy := a.y * u + b.y * v + cc.y * w
				var th := S.h(px, pz)
				if is_nan(th):
					continue
				var d := th + clear - oy
				if d > 0.0005:
					for k in 3:
						need[idx[t + k]] = maxf(float(need.get(idx[t + k], 0.0)), d)
		if need.is_empty():
			break
		for k: int in need:
			var up := minf(float(need[k]) + 0.002, 0.14 - (V[k].y - S.h(V[k].x, V[k].z)) + 0.0)
			up = maxf(up, 0.0)
			V[k] = Vector3(V[k].x, V[k].y + up, V[k].z)
			max_raise = maxf(max_raise, up)
			raised += 1
	# 地形の凸部（岩肌・斜面の肩）では『持ち上げ過ぎ』と『なお地形に潜る』が出る：その頂点は被覆を 0 にして描かない
	#（足が 6.5 cm 以上『見えている地面』に埋まる所・地形面と Z-fight する所に、地面を張らない）。
	var faded := 0
	for k in V.size():
		var dk := V[k].y - S.h(V[k].x, V[k].z)
		var f_hi := 1.0 - smoothstep(0.065, 0.10, dk)
		if f_hi < 1.0:
			U2[k] = Vector2(U2[k].x, U2[k].y * f_hi)
			faded += 1
	for t in range(0, idx.size(), 3):
		var a2 := V[idx[t]]
		var b2 := V[idx[t + 1]]
		var c2 := V[idx[t + 2]]
		var dip := false
		for bc: Array in [[1.0 / 3.0, 1.0 / 3.0], [0.5, 0.5], [0.5, 0.0], [0.0, 0.5], [0.25, 0.25], [0.6, 0.2], [0.2, 0.6]]:
			var u2: float = bc[0]
			var v2: float = bc[1]
			var w2 := 1.0 - u2 - v2
			var th2 := S.h(a2.x * u2 + b2.x * v2 + c2.x * w2, a2.z * u2 + b2.z * v2 + c2.z * w2)
			if not is_nan(th2) and (a2.y * u2 + b2.y * v2 + c2.y * w2) - th2 < clear - 0.0009:
				dip = true
				break
		if dip:
			for k in 3:
				U2[idx[t + k]] = Vector2(U2[idx[t + k]].x, 0.0)
				faded += 1
	# 法線＝地形勾配
	var N := PackedVector3Array()
	N.resize(V.size())
	for k in V.size():
		var d := 0.5
		var nrm := Vector3(S.h(V[k].x - d, V[k].z) - S.h(V[k].x + d, V[k].z), 2.0 * d, S.h(V[k].x, V[k].z - d) - S.h(V[k].x, V[k].z + d))
		N[k] = nrm.normalized() if nrm.is_finite() else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := SG.sg_material()
	# 同じ shader の配色だけ境内用に寄せる：細礫を地形の土に近づける（既定の灰白く冷たい礫が帯に見えた）。shader・テクスチャは唯讀のまま
	mat.set_shader_parameter("gravel_tint", Vector3(1.19, 1.08, 0.88))
	mat.set_shader_parameter("gravel_contrast", 0.62)
	mat.resource_name = "HF_Precinct_Ground"
	am.surface_set_material(0, mat)
	am.resource_name = "hf_precinct_ground"
	return {"mesh": am, "verts": V.size(), "tris": idx.size() / 3, "raised": raised, "max_raise": max_raise, "faded": faded}
