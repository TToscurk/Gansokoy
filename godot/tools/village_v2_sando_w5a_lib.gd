extends RefCounted
## P13 W5B production integration of ART_APPROVED W5A stonework. P1 remains read-only.
## integrated=true: bounded bands in the existing W4 overlay; false: historical s≈59–64.2 sample.
## 呼び出し：village_v2_sando_w4_lib.gd の build_meshes が、試作区間の石垣 run〔s=58.95–64.20〕を旧経路〔scratch へ出力して乱数列だけ進める〕で処理しつつ記録し、
## build_sides の後で finish() を呼ぶ。W4B の他の幾何〔踏面・縫・平台・区間外〕は 1 ビットも変わらない。
## 構成（側 sd ごとに 1 つの連続した壁）：
##   ① 笠石：不規則な平面の薄い石〔W4.stone〕を継ぎ目をずらして並べる
##   ② 壁面：(s, h) 平面のボロノイ〔行ごとの大きさ・千鳥・割り石〕→ 角を丸めた「枕」形の石〔中心が膨らむ・石ごとに出入り〕＋縫の奥に土の裏打ち
##   ③ 土坡：壁の根元から外側地形へ、幅 0.9–1.7 m・高さは壁際で 0〜0.42 m の参差〔石が土から突き出る〕、外縁は地形の −2 cm に潜り、地形と同じ材質・同じウェイト
##   ④ 根石・転がり石：少量。燈籠の足元は避ける
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const ART_REVISION := "P13 W5B integration r1"  # W5A direction ART_APPROVED; integration ART_REVIEW
const SEED := 130510
const DS := 0.05
const K_LO := 1179                 # s=58.95 m：両側とも run の境界
const K_HI := 1284                 # s=64.20 m：試作区間の端＝踊り場の端（石垣が山坡に収まる）
const EXT := 20                    # 土坡が試作区間の外へ延びてテーパーする長さ〔k〕＝1.0 m
const CAP_W := 0.12                # 笠石の外面〔壁面の上端〕の内縁からの幅
const BATTER := 0.13               # 石垣の控え勾配〔深さ 1 m で外へ 0.13 m〕
const BACK := 0.022                # 縫の奥の裏打ちの深さ〔浅い＝縫の中が暗く沈まない〕
const BASE_DEEP := 0.22
const MAX_COVER := 0.36            # 土の盛り高さ／壁の露出量の上限〔石垣を覆う土壁にしない〕            # 壁面の最下端＝地形の下
const LANTERN_U_MAX := 1.46        # 燈籠の足元〔内縁 1.61 m〕に食い込ませない
const EARTH := Color(0.66, 0.57, 0.45)   # 牆腳の土染め〔石の頂点色を土色へ寄せる＝石と土の境界を連続させる〕

static var enabled := true
static var integrated := true       # false = historical W5A local sample
static var scope_lo := 744          # s=37.20 m
static var scope_hi := 1284         # s=64.20 m; upper extension sets this after compatibility audit
static var sampler := Callable()   # func(Vector2 xz) -> float：P1 TerrainCollision の高さ。無効なら外側地形の線形外挿
static var wsampler := Callable()  # func(Vector2 xz, float y) -> [COLOR, UV, UV2]：その場所の地形の頂点ウェイト〔土坡の外縁を地形と逐点で一致させる〕
static var runs := {}              # sd(float) -> Array[{ka,kb,edge,ta,tb}]
static var stats := {}
static var plants: Array = []      # [{id,p:Vector3,yaw,s}]：土坡の上の少量の草叢〔既存 veg_kit の fern_a／sasa_a をそのまま使う〕
const PLANT_SCENES := {"fern_a": "res://assets/village_v2/veg_kit/trees/fern_a.tscn", "sasa_a": "res://assets/village_v2/veg_kit/trees/sasa_a.tscn"}


# ───────────────────────────── 入口 ─────────────────────────────

static func reset() -> void:
	runs = {}
	stats = {}
	plants = []


## overlay ノードに草叢を足す〔既存 veg_kit の PackedScene を instance。LOD・風の instance shader parameter は scene 側が持つ〕
static func add_plants(root: Node3D) -> void:
	if not enabled or plants.is_empty():
		return
	var g := Node3D.new()
	g.name = "W5Plants"
	root.add_child(g)
	g.owner = root
	var cache := {}
	var n := 0
	for it: Dictionary in plants:
		var id := String(it["id"])
		if not cache.has(id):
			cache[id] = load(String(PLANT_SCENES[id])) as PackedScene
		var node := (cache[id] as PackedScene).instantiate() as Node3D
		node.name = "%02d_%s" % [n, id]
		var sc: float = it["s"]
		node.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])).scaled(Vector3(sc, sc, sc)), it["p"])
		g.add_child(node)
		node.owner = root
		n += 1


static func in_sample(ka: int, kb: int) -> bool:
	return enabled and ka >= (scope_lo if integrated else K_LO) and kb <= (scope_hi if integrated else K_HI)


static func record_run(sd: float, e: Dictionary) -> void:
	if not runs.has(sd):
		runs[sd] = []
	(runs[sd] as Array).append({"ka": int(e["ka"]), "kb": int(e["kb"]), "edge": float(e["edge"]), "ta": float(e["ta"]), "tb": float(e["tb"])})


static func make_sampler(sp: PhysicsDirectSpaceState3D) -> Callable:
	return func(p: Vector2) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
		var ex: Array[RID] = []
		for t in 12:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				return float(h["position"].y)
			ex.append(h["rid"])
		return NAN


## 呼び出し側の初期化：sp＝physics 空間、vil＝VillageV2 のルート。P1 は読むだけ
static func setup(vil: Node3D, sp: PhysicsDirectSpaceState3D, cl: PackedVector2Array) -> void:
	sampler = make_sampler(sp)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in range(maxi((scope_lo if integrated else K_LO) - 40, 0), mini((scope_hi if integrated else K_HI) + 40, cl.size() - 1), 4):
		lo = Vector2(minf(lo.x, cl[k].x), minf(lo.y, cl[k].y))
		hi = Vector2(maxf(hi.x, cl[k].x), maxf(hi.y, cl[k].y))
	var rc := Rect2(lo - Vector2(7.0, 7.0), (hi - lo) + Vector2(14.0, 14.0))
	wsampler = make_weight_sampler(vil.get_node_or_null("Terrain"), rc)


## 地形メッシュ〔NorthHill・MainTerrain〕のうち region に掛かる三角形から、重心座標で頂点ウェイトを補間する。複数の面が重なる所は高さが y に最も近いもの
static func make_weight_sampler(terrain: Node, region: Rect2) -> Callable:
	var tris: Array = []
	if terrain == null:
		return Callable()
	for nm in ["NorthHill", "MainTerrain"]:
		var mi := terrain.get_node_or_null(nm) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var xf := mi.global_transform
		var n := ids.size() if ids.size() > 0 else vs.size()
		for t in range(0, n, 3):
			var i0 := ids[t] if ids.size() > 0 else t
			var i1 := ids[t + 1] if ids.size() > 0 else t + 1
			var i2 := ids[t + 2] if ids.size() > 0 else t + 2
			var a := xf * vs[i0]
			var b := xf * vs[i1]
			var c := xf * vs[i2]
			var mn := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var mx := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			if mx.x < region.position.x or mn.x > region.end.x or mx.y < region.position.y or mn.y > region.end.y:
				continue
			tris.append([a, b, c, [cols[i0], uv[i0], uv2[i0]], [cols[i1], uv[i1], uv2[i1]], [cols[i2], uv[i2], uv2[i2]]])
	if tris.is_empty():
		return Callable()
	return func(p: Vector2, y: float) -> Array:
		var best: Array = []
		var bd := INF
		for t: Array in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var v0 := Vector2(b.x - a.x, b.z - a.z)
			var v1 := Vector2(c.x - a.x, c.z - a.z)
			var v2 := Vector2(p.x - a.x, p.y - a.z)
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 1e-9:
				continue
			var wb := (v2.x * v1.y - v1.x * v2.y) / den
			var wc := (v0.x * v2.y - v2.x * v0.y) / den
			var wa := 1.0 - wb - wc
			if wa < -0.001 or wb < -0.001 or wc < -0.001:
				continue
			var yi: float = a.y * wa + b.y * wb + c.y * wc
			var d := absf(yi - y)
			if d < bd:
				bd = d
				var ta: Array = t[3]
				var tb: Array = t[4]
				var tc: Array = t[5]
				best = [(ta[0] as Color) * wa + (tb[0] as Color) * wb + (tc[0] as Color) * wc,
					(ta[1] as Vector2) * wa + (tb[1] as Vector2) * wb + (tc[1] as Vector2) * wc,
					(ta[2] as Vector2) * wa + (tb[2] as Vector2) * wb + (tc[2] as Vector2) * wc]
		return best


# ───────────────────────────── 小道具 ─────────────────────────────

static func _hash1(i: int, seed: int) -> float:
	var x: int = (i * 374761393 + seed * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


static func _vnoise(x: float, seed: int) -> float:
	var i0: int = int(floor(x))
	var f: float = x - float(i0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash1(i0, seed), _hash1(i0 + 1, seed), f)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, hint: Vector3) -> void:
	var n := (c - a).cross(b - a)            # Godot の表＝時計回り：front の法線は (c−a)×(b−a)
	if n.length() < 1e-9:
		return
	n = n.normalized()
	var vs := [a, b, c]
	var cs := [ca, cb, cc]
	if n.dot(hint) < 0.0:
		vs = [a, c, b]
		cs = [ca, cc, cb]
		n = -n
	for i in 3:
		st.set_color(cs[i])
		st.set_normal(n)
		st.set_uv(W4._uv(vs[i], n))
		st.add_vertex(vs[i])


static func _soil_tri(hm: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, wa: Array, wb: Array, wc: Array, hint: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length() < 1e-9:
		return
	n = n.normalized()
	var vs := [a, b, c]
	var ws := [wa, wb, wc]
	if n.dot(hint) < 0.0:
		vs = [a, c, b]
		ws = [wa, wc, wb]
		n = -n
	for i in 3:
		var w: Array = ws[i]
		hm.set_color(w[0])
		hm.set_uv(w[1])
		hm.set_uv2(w[2])
		hm.set_normal(n)
		hm.add_vertex(vs[i])
	W4.soil_n += 1


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in p:
		c += q
	return c / float(maxi(p.size(), 1))


# ───────────────────────────── 側ごとの文脈 ─────────────────────────────

## 補間付きの配列参照（k の小数）
static func _at(C: Dictionary, key: String, kf: float) -> float:
	var arr: PackedFloat32Array = C[key]
	var x: float = clampf(kf - float(C["k0"]), 0.0, float(arr.size() - 1) - 0.0001)
	var i: int = int(floor(x))
	return lerpf(arr[i], arr[i + 1], x - float(i))


static func _frame_at(C: Dictionary, kf: float) -> Array:
	var x: float = clampf(kf - float(C["k0"]), 0.0, float((C["pos"] as PackedVector2Array).size() - 1) - 0.0001)
	var i: int = int(floor(x))
	var f: float = x - float(i)
	var pos: PackedVector2Array = C["pos"]
	var nrm: PackedVector2Array = C["nrm"]
	return [pos[i].lerp(pos[i + 1], f), nrm[i].lerp(nrm[i + 1], f).normalized()]


static func _ucap(C: Dictionary, kf: float) -> float:
	var s: float = kf * DS
	var m := 99.0
	for ls in C["lanterns"]:
		var d: float = absf(s - float(ls))
		if d < 1.2:
			m = minf(m, lerpf(LANTERN_U_MAX, 3.0, smoothstep(0.7, 1.2, d)))
	return m


## 壁面の上の点：s_rel〔試作の始点から m〕、h〔笠石頂線から下へ m〕、off〔面からの出入り m〕
static func _pos(C: Dictionary, s_rel: float, h: float, off: float) -> Vector3:
	var kf: float = float(C["ka"]) + s_rel / DS
	var fr := _frame_at(C, kf)
	var u: float = minf(_at(C, "u_top", kf) + BATTER * h, _ucap(C, kf)) + off
	var p: Vector2 = (fr[0] as Vector2) + (fr[1] as Vector2) * float(C["sd"]) * u
	return Vector3(p.x, _at(C, "line", kf) - h, p.y)


static func _terr(C: Dictionary, p: Vector2, kf: float, u: float) -> float:
	if sampler.is_valid():
		return float(sampler.call(p))
	var ti: PackedFloat32Array = C["tout"]
	var tf: PackedFloat32Array = C["tfar"]
	var k: int = clampi(int(round(kf)), 0, ti.size() - 1)
	if is_nan(ti[k]) or is_nan(tf[k]):
		return NAN
	return ti[k] + (tf[k] - ti[k]) / (W4.U_FAR - W4.U_TERR) * (u - W4.U_TERR)


static func _make_ctx(cl: PackedVector2Array, sd: float, rl: Array, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array) -> Dictionary:
	var ka := 999999
	var kb := -1
	for r: Dictionary in rl:
		ka = mini(ka, int(r["ka"]))
		kb = maxi(kb, int(r["kb"]))
	var k0 := maxi(ka - EXT, 0)
	var n := (kb - k0 + 1) + EXT
	var C := {"cl": cl, "sd": sd, "ka": ka, "kb": kb, "k0": k0, "n": n, "lanterns": lanterns, "tout": tout, "tfar": tfar}
	var pos := PackedVector2Array()
	var nrm := PackedVector2Array()
	var e_raw := PackedFloat32Array()
	var l_raw := PackedFloat32Array()
	pos.resize(n)
	nrm.resize(n)
	e_raw.resize(n)
	l_raw.resize(n)
	e_raw.fill(NAN)
	for i in n:
		var k := clampi(k0 + i, 0, cl.size() - 1)
		var t := SA.tangent(cl, k)
		pos[i] = cl[k]
		nrm[i] = Vector2(-t.y, t.x)
	for r: Dictionary in rl:
		for k in range(int(r["ka"]), int(r["kb"]) + 1):
			var i := k - k0
			var f := clampf(float(k - int(r["ka"])) / float(maxi(int(r["kb"]) - int(r["ka"]), 1)), 0.0, 1.0)
			var e := float(r["edge"])
			var l := lerpf(float(r["ta"]), float(r["tb"]), f)
			if is_nan(e_raw[i]):
				e_raw[i] = e
				l_raw[i] = l
			else:
				e_raw[i] = maxf(e_raw[i], e)
				l_raw[i] = maxf(l_raw[i], l)
	for i in range(0, EXT):                       # 区間の外は端の値を延ばす
		e_raw[i] = e_raw[EXT]
		l_raw[i] = l_raw[EXT]
	for i in range(n - EXT, n):
		e_raw[i] = e_raw[n - EXT - 1]
		l_raw[i] = l_raw[n - EXT - 1]
	# 笠石の内縁の包絡：±8 k〔0.4 m〕の最大 → ±8 k の平均（≥ 各 k の run の edge を保つ）
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var m := 0.0
		for d in range(-8, 9):
			m = maxf(m, e_raw[clampi(i + d, 0, n - 1)])
		env[i] = m
	var e_s := PackedFloat32Array()
	e_s.resize(n)
	for i in n:
		var s := 0.0
		for d in range(-8, 9):
			s += env[clampi(i + d, 0, n - 1)]
		e_s[i] = s / 17.0
	var line := PackedFloat32Array()
	line.resize(n)
	for i in n:
		var s := 0.0
		for d in range(-4, 5):
			s += l_raw[clampi(i + d, 0, n - 1)]
		line[i] = maxf(l_raw[i], s / 9.0)         # 平滑化して持ち上げるだけ＝各踏面の前縁より ≥ 1 cm 上を保つ
	var u_top := PackedFloat32Array()
	u_top.resize(n)
	for i in n:
		u_top[i] = e_s[i] + CAP_W + 0.02 * (_vnoise(float(k0 + i) * 0.035, SEED + 3) - 0.5)
	C["pos"] = pos
	C["nrm"] = nrm
	C["e_s"] = e_s
	C["line"] = line
	C["u_top"] = u_top
	# 壁面の位置〔u_top + 0.10〕の地形高と露出量
	var tface := PackedFloat32Array()
	var ex := PackedFloat32Array()
	tface.resize(n)
	ex.resize(n)
	for i in n:
		var k := k0 + i
		# 壁面〔u_top ＋ 0〜0.20 m〕の 3 点の地形高の最大＝保守的〔壁の底を深く取る。平台の端のように外へ向かって地形が上がる所でも底が浮かない〕
		var th := NAN
		for du in [0.0, 0.10, 0.20]:
			var p: Vector2 = pos[i] + nrm[i] * sd * (u_top[i] + float(du))
			var t1 := _terr(C, p, float(k), u_top[i] + float(du))
			if not is_nan(t1):
				th = t1 if is_nan(th) else maxf(th, t1)
		if is_nan(th):
			th = line[i] - 0.6
		tface[i] = th
		ex[i] = line[i] - th
	C["tface"] = tface
	C["ex"] = ex
	return C


# ───────────────────────────── 壁面 ─────────────────────────────

static func _wall_tiles(sm: SurfaceTool, hm: SurfaceTool, C: Dictionary, rng: RandomNumberGenerator) -> void:
	var ka: int = C["ka"]
	var kb: int = C["kb"]
	var L: float = float(kb - ka) * DS
	var ex: PackedFloat32Array = C["ex"]
	var H0 := 0.05                                              # 壁面の石は笠石の裏へ潜る〔笠石の厚み 0.11 以上〕＝笠石の下縁と壁面の間に隙間を作らない
	var hmax := 0.0
	for k in range(ka, kb + 1):
		hmax = maxf(hmax, _at(C, "ex", float(k)) + BASE_DEEP)
	hmax += 0.05
	# 行：高さは 0.20–0.36 m で下へ行くほど大きく。行ごとに千鳥〔間隔 0.42→0.88 m〕
	var rows_h: Array = [H0]
	var hh := H0
	while hh < hmax:
		hh += rng.randf_range(0.16, 0.29) * (1.0 + 0.09 * float(rows_h.size() - 1))
		rows_h.append(hh)
	var seeds: Array = []
	var nrows: int = rows_h.size() - 1
	for r in nrows:
		var h0: float = rows_h[r]
		var h1: float = rows_h[r + 1]
		var sp: float = lerpf(0.30, 0.66, float(r) / float(maxi(nrows - 1, 1))) * rng.randf_range(0.9, 1.15)
		var s := -rng.randf() * sp
		while s < L + sp:
			seeds.append(Vector2(s + rng.randf_range(-0.28, 0.28) * sp, (h0 + h1) * 0.5 + rng.randf_range(-0.30, 0.30) * (h1 - h0)))
			s += sp * rng.randf_range(0.8, 1.25)
		if r < nrows - 1:                                       # 行の境に割り石〔詰め石〕
			var sf := rng.randf() * 0.6
			while sf < L:
				if rng.randf() < 0.7:
					seeds.append(Vector2(sf, h1 + rng.randf_range(-0.05, 0.05)))
				sf += rng.randf_range(0.5, 1.1)
	var dom := Rect2(Vector2(-0.6, H0), Vector2(L + 1.2, hmax - H0))
	var cells: Array = W4._voronoi(dom, seeds)
	for it in 12:                                               # 小さすぎる種は捨てて再計算〔穴を作らない〕
		var wi := -1
		var wa := 0.035
		for ci in cells.size():
			var ar := _poly_area(cells[ci])
			if ar < wa:
				wa = ar
				wi = ci
		if wi < 0 or seeds.size() <= 6:
			break
		seeds.remove_at(wi)
		cells = W4._voronoi(dom, seeds)
	for pass_i in 2:                                            # 大きすぎる石は 2 つに割る〔詰め石を作る〕
		var added := 0
		for ci in cells.size():
			var cc: PackedVector2Array = cells[ci]
			if _poly_area(cc) > 0.13:
				var cn := _centroid(cc)
				if cn.x > 0.1 and cn.x < L - 0.1:
					seeds.append(cn + Vector2(rng.randf_range(-0.10, 0.10), rng.randf_range(-0.06, 0.06)))
					added += 1
		if added == 0:
			break
		cells = W4._voronoi(dom, seeds)
	var n_st := 0
	var n_base := 0
	var area_sum := 0.0
	var sizes: Array = []
	for ci in cells.size():
		var cell: PackedVector2Array = cells[ci]
		cell = W4._clip_half(cell, Vector2(-1, 0), 0.0)
		cell = W4._clip_half(cell, Vector2(1, 0), L)
		if cell.size() < 3 or _poly_area(cell) < 0.02:
			continue
		var gap := rng.randf_range(0.003, 0.007)
		var inner := Geometry2D.offset_polygon(cell, -gap, Geometry2D.JOIN_MITER)
		if inner.is_empty():
			continue
		var pc: PackedVector2Array = W4._largest(inner)
		var rc := minf(rng.randf_range(0.035, 0.085), 0.27 * sqrt(_poly_area(pc)))
		var shr := Geometry2D.offset_polygon(pc, -rc, Geometry2D.JOIN_MITER)
		if not shr.is_empty():
			var rnd := Geometry2D.offset_polygon(W4._largest(shr), rc, Geometry2D.JOIN_ROUND)
			if not rnd.is_empty():
				pc = W4._largest(rnd)
		if pc.size() < 3:
			continue
		# 下端：地形の −BASE_DEEP の線へ切り詰める
		var clamped := false
		var q2 := PackedVector2Array()
		for q in pc:
			var kf: float = float(ka) + q.x / DS
			var hb: float = _at(C, "ex", kf) + BASE_DEEP
			if q.y > hb:
				clamped = true
			q2.append(Vector2(q.x, minf(q.y, hb)))
		# 連続する重複点を除く
		var q3 := PackedVector2Array()
		for q in q2:
			if q3.is_empty() or q3[q3.size() - 1].distance_to(q) > 0.004:
				q3.append(q)
		if q3.size() >= 2 and q3[0].distance_to(q3[q3.size() - 1]) <= 0.004:
			q3.remove_at(q3.size() - 1)
		if q3.size() < 3 or _poly_area(q3) < 0.012:
			continue
		var cen := _centroid(q3)
		var hb_c: float = _at(C, "ex", float(ka) + cen.x / DS) + BASE_DEEP
		if cen.y > hb_c - 0.04:
			continue
		var ar := _poly_area(q3)
		sizes.append(sqrt(ar))
		area_sum += ar
		var depth_f := clampf((cen.y - H0) / maxf(hb_c - H0, 0.2), 0.0, 1.0)
		var top_f := smoothstep(0.08, 0.5, cen.y)
		var prot := clampf(rng.randfn(0.0, 0.006), -0.012, 0.012) * top_f + 0.020 * smoothstep(0.55, 1.0, depth_f)
		var bulge := rng.randf_range(0.022, 0.055) * lerpf(0.3, 1.0, top_f) * clampf(sqrt(ar) / 0.4, 0.5, 1.2)
		var tilt := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.03) * top_f
		var base: Color = W4._tone(rng, false)
		base = W4._mul(base, lerpf(1.04, 0.95, depth_f) * rng.randf_range(0.94, 1.06))       # 同じ光で W4B の壁より平均 ~8 % 暗かった〔baseR の ROI 輝度 0.303→0.278〕ので、深さの暗化を弱め全体を持ち上げる
		var face_col := base
		if rng.randf() < 0.28:                                  # 苔・地衣の斑
			var mt := rng.randf_range(0.8, 1.05)
			face_col = base.lerp(Color(0.34 * mt, 0.44 * mt, 0.22 * mt), rng.randf_range(0.25, 0.5))
		W4.uv_k = 1.5
		W4._uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		_pillow(sm, C, q3, cen, prot, bulge, tilt, face_col, base)
		n_st += 1
		if clamped:
			n_base += 1
			var kmid: float = float(ka) + cen.x / DS
			# 接地の最悪点：切り詰めた底の頂点ごとに『地形 − 底』を実測し、最小のもの〔位置と高さ〕を記録する〔地形は沿路方向に 0.5–0.8 m/m で上がる＝中心の地形と比べると誤差が出る〕
			var worst_clear := INF
			var worst_p := Vector2.ZERO
			var worst_y := 0.0
			for q in q3:
				if q.y >= _at(C, "ex", float(ka) + q.x / DS) + BASE_DEEP - 0.002:
					var pq := _pos(C, q.x, q.y, 0.0)
					var tq := _terr(C, Vector2(pq.x, pq.z), float(ka) + q.x / DS, _at(C, "u_top", float(ka) + q.x / DS))
					if is_nan(tq):
						continue
					var cq: float = tq - pq.y
					if cq < worst_clear:
						worst_clear = cq
						worst_p = Vector2(pq.x, pq.z)
						worst_y = pq.y
			if worst_clear < INF:
				W4.diag.append({"k": int(round(kmid)), "sd": C["sd"], "u": minf(_at(C, "u_top", kmid) + BATTER * cen.y, 9.0) + prot, "p": worst_p,
					"ybot": worst_y, "top": _at(C, "line", kmid) - cen.y, "off": 0.3, "base": true})
	# 縫の奥の裏打ち〔地形と同じ材質・暗い土〕。0.25 m ごとの帯
	var wb := [Color(0.78, 0.04, 0.26, 0.04), Vector2(0.18, 0.0), Vector2(0.08, 0.0)]
	var s0 := 0.0
	while s0 < L - 0.001:
		var s1 := minf(s0 + (DS if integrated else 0.25), L)  # conform backing to 5 cm cap-line samples; 25 cm chords left two real under-cap openings
		var hb0: float = _at(C, "ex", float(ka) + s0 / DS) + BASE_DEEP
		var hb1: float = _at(C, "ex", float(ka) + s1 / DS) + BASE_DEEP
		var a := _pos(C, s0, H0 - 0.04, -BACK)
		var b := _pos(C, s1, H0 - 0.04, -BACK)
		var c := _pos(C, s1, hb1, -BACK)
		var d := _pos(C, s0, hb0, -BACK)
		var out_h := _out_dir(C, (s0 + s1) * 0.5)
		_soil_tri(hm, a, b, c, wb, wb, wb, out_h)
		_soil_tri(hm, a, c, d, wb, wb, wb, out_h)
		s0 = s1
	C["stats"]["stones"] = n_st
	C["stats"]["base_stones"] = n_base
	C["stats"]["size_mean"] = 0.0 if sizes.is_empty() else float(sizes.reduce(func(a, b): return a + b)) / float(sizes.size())
	sizes.sort()
	C["stats"]["size_p10"] = 0.0 if sizes.is_empty() else float(sizes[int(sizes.size() * 0.1)])
	C["stats"]["size_p90"] = 0.0 if sizes.is_empty() else float(sizes[int(sizes.size() * 0.9)])


static func _out_dir(C: Dictionary, s_rel: float) -> Vector3:
	var fr := _frame_at(C, float(C["ka"]) + s_rel / DS)
	var n: Vector2 = (fr[1] as Vector2) * float(C["sd"])
	return Vector3(n.x, 0.0, n.y)


## 枕形の石 1 個：縁〔面取り〕→ 内輪〔膨らみの 55 %〕→ 中心〔膨らみ〕。縁から裏打ちまで「スカート」
## 壁面の共有起伏〔全部の石が同じ面を共有する＝隣り合う石の縁が交界で食い違わない。食い違うと高い側の側壁が黒い楔になる〕
static func _undul(q: Vector2) -> float:
	return 0.03 * (2.0 * _vnoise(q.x * 1.5 + q.y * 1.1, SEED + 31) - 1.0) * smoothstep(0.1, 0.5, q.y)


## 牆腳の土染め：地面〔=ex(s) − h が 0〕に近いほど頂点色を土色へ寄せる
static func _soil_tint(C: Dictionary, col: Color, s_rel: float, h: float) -> Color:
	var ha: float = _at(C, "ex", float(C["ka"]) + s_rel / DS) - h
	var t: float = 1.0 - smoothstep(-0.05, 0.52, ha)
	return col.lerp(EARTH, 0.40 * t)


static func _pillow(sm: SurfaceTool, C: Dictionary, poly: PackedVector2Array, cen: Vector2, prot: float, bulge: float, tilt: Vector2, face_col: Color, base: Color) -> void:
	var n := poly.size()
	var rim: Array = []
	var mid: Array = []
	var back: Array = []
	var cr: Array = []
	var cm: Array = []
	var cs: Array = []
	var rmax := 0.05
	for q in poly:
		rmax = maxf(rmax, q.distance_to(cen))
	for q in poly:
		var d: Vector2 = q - cen
		rim.append(_pos(C, q.x, q.y, prot + tilt.dot(d) - 0.016 + _undul(q)))
		var qi: Vector2 = cen + d * 0.62
		mid.append(_pos(C, qi.x, qi.y, prot + tilt.dot(d) * 0.62 + 0.55 * bulge + _undul(qi)))
		back.append(_pos(C, q.x, q.y, -BACK))
		cr.append(_soil_tint(C, W4._mul(base, 0.94), q.x, q.y))
		cm.append(_soil_tint(C, W4._mul(face_col, 1.0), qi.x, qi.y))
		cs.append(_soil_tint(C, W4._mul(base, 0.86), q.x, q.y))
	var ctr := _pos(C, cen.x, cen.y, prot + bulge + _undul(cen))
	var c_ctr := _soil_tint(C, face_col, cen.x, cen.y)
	var out := _out_dir(C, cen.x)
	for i in n:
		var j := (i + 1) % n
		_tri(sm, ctr, mid[i], mid[j], c_ctr, cm[i], cm[j], out)
		_tri(sm, mid[i], rim[i], rim[j], cm[i], cr[i], cr[j], out)
		_tri(sm, mid[i], rim[j], mid[j], cm[i], cr[j], cm[j], out)
		# スカート：縁 → 裏打ち。外向きは石の中心から縁の中点への向き
		var em: Vector3 = ((rim[i] as Vector3) + (rim[j] as Vector3)) * 0.5
		var hint: Vector3 = em - ctr
		_tri(sm, rim[i], rim[j], back[j], cs[i], cs[j], W4._mul(cs[j], 0.85), hint)
		_tri(sm, rim[i], back[j], back[i], cs[i], W4._mul(cs[j], 0.85), W4._mul(cs[i], 0.85), hint)


# ───────────────────────────── 笠石 ─────────────────────────────

static func _caps(sm: SurfaceTool, C: Dictionary, rng: RandomNumberGenerator) -> void:
	var ka: int = C["ka"]
	var kb: int = C["kb"]
	var L: float = float(kb - ka) * DS
	var sd: float = C["sd"]
	var s := 0.0
	var prev_shear := rng.randf_range(-0.05, 0.05)
	var n_cap := 0
	while s < L - 0.05:
		var ln := rng.randf_range(0.30, 0.70)
		var sb := minf(s + ln, L)
		if L - sb < 0.28:
			sb = L
		var kmid: float = float(ka) + (s + sb) * 0.5 / DS
		var ex_m: float = _at(C, "ex", kmid)
		var shear_b := rng.randf_range(-0.05, 0.05)
		if ex_m > 0.08:
			var u_in: float = _at(C, "e_s", kmid) - 0.03
			var u_top: float = _at(C, "u_top", kmid)
			var u_out: float = minf(u_top + rng.randf_range(0.02, 0.045), _ucap(C, kmid) + 0.06)
			var pts_su: Array = [Vector2(s, u_in), Vector2(s + prev_shear, u_out), Vector2((s + sb) * 0.5 + rng.randf_range(-0.05, 0.05), u_out + rng.randf_range(0.0, 0.03)),
				Vector2(sb + shear_b, u_out), Vector2(sb, u_in)]
			var P: Array = []
			var ht: Array = []
			var sh := 0.0
			for q: Vector2 in pts_su:
				var kf: float = float(ka) + clampf(q.x, 0.0, L) / DS
				var fr := _frame_at(C, kf)
				P.append((fr[0] as Vector2) + (fr[1] as Vector2) * sd * q.y)
				var hh: float = _at(C, "line", kf) + rng.randf_range(-0.006, 0.006)
				ht.append(hh)
				sh += hh
			var thick := 0.14 + 0.05 * (_vnoise(kmid * 0.045, SEED + 41) - 0.5) + rng.randf_range(-0.004, 0.004)     # 沿 s に緩変〔相鄰の笠石の厚み差 ≤ 1 cm＝下へ凸出する側壁の楔を作らない〕
			var hc: float = sh / float(ht.size()) + rng.randf_range(0.002, 0.006)
			var tone: Color = W4._mul(W4._tone(rng, false), rng.randf_range(0.95, 1.08))
			var top_col := Color(-1.0, 0.0, 0.0, 1.0)
			if rng.randf() < 0.45:
				var mt := rng.randf_range(0.8, 1.05)
				top_col = Color(mt * 0.42, mt * 0.50, mt * 0.26)
			W4.uv_k = 0.9
			W4._uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
			var pm: Vector2 = P[2]
			var top_mean: float = sh / float(ht.size())
			W4.side_lift = 0.7
			W4.stone(sm, P, ht, hc, top_mean - thick, rng.randf_range(0.016, 0.03), tone, 0, top_col)
			W4.side_lift = 0.0
			W4.diag.append({"k": int(round(kmid)), "sd": sd, "u": u_out, "p": pm, "ybot": top_mean - thick, "top": top_mean, "off": 0.0, "base": false})
			n_cap += 1
		prev_shear = shear_b                       # 次の笠石の始端は前の笠石の終端と平行〔r7 までは符号が逆で、外縁に最大約 10 cm の楔形の隙間が開き、奥の暗い壁が見えていた〕
		s = sb + rng.randf_range(0.004, 0.012)
	C["stats"]["caps"] = n_cap


# ───────────────────────────── 丸い石（根石・転がり石）─────────────────────────────

## 低ポリの楕円体〔緯度 5 段 × 経度 8〕に頂点ノイズ。下半分は地面の下〔描かない〕。直方体に見えない
static func _boulder(sm: SurfaceTool, c: Vector3, rx: float, ry: float, rz: float, yaw: float, tone: Color, ground_y: float, rng: RandomNumberGenerator) -> void:
	var lats: Array = [-0.30, -0.12, 0.06, 0.22, 0.35, 0.5]          # ×π。-0.5π〔底〕は地面の下なので省く。頂〔0.5π〕は平らにつぶす
	var nlon := 8
	var ring: Array = []
	for li in lats.size():
		var lat: float = float(lats[li]) * PI
		var row: Array = []
		var nn := 1 if li == lats.size() - 1 else nlon
		for j in nn:
			var lon: float = yaw + TAU * float(j) / float(nlon)
			var rn: float = 1.0 + rng.randf_range(-0.13, 0.13)
			var pv := Vector3(cos(lat) * cos(lon) * rx, sin(lat) * ry * (0.97 if li == lats.size() - 1 else 1.0), cos(lat) * sin(lon) * rz) * rn
			var col: Color = W4._mul(tone, 0.80 + 0.28 * sin(lat) + rng.randf_range(-0.04, 0.04))
			var vy: float = c.y + pv.y
			col = col.lerp(EARTH, 0.45 * (1.0 - smoothstep(0.0, 0.22, vy - ground_y)))       # 土に近い所は土染め
			row.append([c + pv, col])
		ring.append(row)
	for li in lats.size() - 1:
		var a: Array = ring[li]
		var b: Array = ring[li + 1]
		var top := (li == lats.size() - 2)
		for j in nlon:
			var j2 := (j + 1) % nlon
			if top:
				var t0: Array = b[0]
				_tri(sm, (a[j] as Array)[0], (a[j2] as Array)[0], t0[0], (a[j] as Array)[1], (a[j2] as Array)[1], t0[1], (a[j][0] as Vector3) - c)
			else:
				var q0: Vector3 = (a[j] as Array)[0]
				var q1: Vector3 = (a[j2] as Array)[0]
				var q2: Vector3 = (b[j2] as Array)[0]
				var q3: Vector3 = (b[j] as Array)[0]
				_tri(sm, q0, q1, q2, (a[j] as Array)[1], (a[j2] as Array)[1], (b[j2] as Array)[1], (q0 + q1 + q2) / 3.0 - c)
				_tri(sm, q0, q2, q3, (a[j] as Array)[1], (b[j2] as Array)[1], (b[j] as Array)[1], (q0 + q2 + q3) / 3.0 - c)


# ───────────────────────────── 土坡 ─────────────────────────────

## 壁際の土の盛り高さ〔壁の根元に沿った参差の輪郭〕
static func _amp(C: Dictionary, kf: float) -> float:
	var ex: float = _at(C, "ex", kf)
	var n1: float = 0.6 * _vnoise(kf * 0.045, SEED + 11) + 0.4 * _vnoise(kf * 0.16 + 3.1, SEED + 12)
	var a: float = smoothstep(0.22, 0.56, n1)
	a *= 0.70 + 0.60 * _vnoise(kf * 0.22, SEED + 13)
	a = 0.40 * a + 0.05 + 0.055 * _vnoise(kf * 0.38, SEED + 14)       # 常に 5–10 cm の土の肩〔石際の直線接触線を石の輪郭に沿って折る〕
	a = minf(a, MAX_COVER * maxf(ex, 0.0))
	# 区間の外へテーパー
	var ka: int = C["ka"]
	var kb: int = C["kb"]
	var out_d: float = maxf(float(ka) - kf, kf - float(kb))
	if out_d > 0.0:
		a *= 1.0 - smoothstep(0.0, float(EXT), out_d)
	# 燈籠の足元には盛らない
	var s: float = kf * DS
	for ls in C["lanterns"]:
		var d: float = absf(s - float(ls))
		if d < 0.95:
			a *= smoothstep(0.5, 0.95, d)
	# 壁が山坡に収まる端〔露出が 0 に近い〕では盛らない
	a *= smoothstep(0.04, 0.22, ex)
	return a


static func _mound_w(C: Dictionary, kf: float) -> float:
	return 0.9 + 0.9 * _vnoise(kf * 0.05, SEED + 21)


static func _mound(hm: SurfaceTool, C: Dictionary, rng: RandomNumberGenerator) -> void:
	var sd: float = C["sd"]
	var k0: int = C["k0"]
	var n: int = C["n"]
	var XS: Array = [0.0, 0.05, 0.13, 0.27, 0.45, 0.65, 0.84, 1.0]
	var rows: Array = []
	var amp_sum := 0.0
	var amp_cnt := 0
	var bare := 0
	var indices: Array = range(0, n, 2)
	if integrated:
		indices = range(int(C["ka"]) - k0, int(C["kb"]) - k0, 2)
		indices.append(int(C["kb"]) - k0)  # shared endpoint; no missing soil strip at odd k
	for i: int in indices:
		var kf: float = float(k0 + i)
		if integrated and kf < float(C["ka"]):
			continue
		if kf > float(C["kb"]) + 0.5:
			continue                         # 試作区間の上端〔s=64.2 m〕より先へは出さない
		var amp := _amp(C, kf)
		amp *= 1.0 + rng.randf_range(-0.10, 0.10)
		amp_sum += amp
		amp_cnt += 1
		if amp < 0.03:
			bare += 1
		var W := _mound_w(C, kf)
		var ex: float = _at(C, "ex", kf)
		var fr := _frame_at(C, kf)
		var u_g: float = minf(_at(C, "u_top", kf) + BATTER * clampf(ex, 0.1, 1.3), _ucap(C, kf))
		var row: Array = []
		var ok := true
		# 内縁〔石の体積の中〕
		var cols: Array = [[-0.07, amp + 0.02, 0.0]]
		for x: float in XS:
			cols.append([x * W, amp * pow(1.0 - x, 2.0) * (1.0 + rng.randf_range(-0.12, 0.12)) - 0.02 * smoothstep(0.78, 1.0, x), x])
		for c: Array in cols:
			var u: float = u_g + float(c[0])
			var p: Vector2 = (fr[0] as Vector2) + (fr[1] as Vector2) * sd * u
			var th := _terr(C, p, kf, u)
			if is_nan(th):
				ok = false
				break
			var wmix: Array = _mw(float(c[2]), rng)
			if wsampler.is_valid() and float(c[2]) > 0.25:
				var tw: Array = wsampler.call(p, th)
				if not tw.is_empty():
					var tt: float = smoothstep(0.30, 0.95, float(c[2]))      # 外縁〔x=1〕では地形そのもの
					wmix = [(wmix[0] as Color).lerp(tw[0] as Color, tt), (wmix[1] as Vector2).lerp(tw[1] as Vector2, tt), (wmix[2] as Vector2).lerp(tw[2] as Vector2, tt)]
			row.append([Vector3(p.x, th + float(c[1]), p.y), float(c[2]), wmix])
		rows.append(row if ok else null)
	# ウェイト：内縁＝湿った暗い土〔泥・落ち葉・小石〕→ 外縁＝周囲の地形と同じ〔trodden 0.85・rock 0.04・forest 0.06〕
	for r in rows.size() - 1:
		if rows[r] == null or rows[r + 1] == null:
			continue
		var ra: Array = rows[r]
		var rb: Array = rows[r + 1]
		for j in ra.size() - 1:
			var a0: Vector3 = (ra[j] as Array)[0]
			var a1: Vector3 = (ra[j + 1] as Array)[0]
			var b0: Vector3 = (rb[j] as Array)[0]
			var b1: Vector3 = (rb[j + 1] as Array)[0]
			var wa0: Array = (ra[j] as Array)[2]
			var wa1: Array = (ra[j + 1] as Array)[2]
			var wb0: Array = (rb[j] as Array)[2]
			var wb1: Array = (rb[j + 1] as Array)[2]
			_soil_tri(hm, a0, b0, b1, wa0, wb0, wb1, Vector3.UP)
			_soil_tri(hm, a0, b1, a1, wa0, wb1, wa1, Vector3.UP)
	C["stats"]["amp_mean"] = amp_sum / float(maxi(amp_cnt, 1))
	var cov_max := 0.0
	for i2 in range(0, n, 2):
		var kf2: float = float(k0 + i2)
		if kf2 < float(C["ka"]) or kf2 > float(C["kb"]):
			continue
		var ex2: float = _at(C, "ex", kf2)
		if ex2 > 0.2:
			cov_max = maxf(cov_max, _amp(C, kf2) / ex2)
	C["stats"]["cover_max"] = cov_max
	C["stats"]["bare_rows"] = float(bare) / float(maxi(amp_cnt, 1))


static func _mw(x: float, rng: RandomNumberGenerator) -> Array:
	# x＝0〔内縁〕…1〔外縁〕
	var t := smoothstep(0.0, 1.0, x)
	var gravel := rng.randf_range(0.0, 0.34) * (1.0 - t)
	var rock := lerpf(rng.randf_range(0.06, 0.22), 0.04, t)
	var mud := lerpf(rng.randf_range(0.10, 0.26), 0.0, t)
	var tro := lerpf(0.62, 0.85, t)
	var forest := lerpf(rng.randf_range(0.18, 0.36), 0.06, t)
	var wet := lerpf(rng.randf_range(0.03, 0.10), 0.0, t)
	return [Color(tro, gravel, mud, rock), Vector2(forest, 0.0), Vector2(wet, 0.0)]


## 転がり石：土坡の上に少量〔根石の脇・端〕。接地は土面の −7 cm に潜る
static func _rocks(sm: SurfaceTool, C: Dictionary, rng: RandomNumberGenerator) -> void:
	var ka: int = C["ka"]
	var kb: int = C["kb"]
	var L: float = float(kb - ka) * DS
	var sd: float = C["sd"]
	var s := rng.randf_range(0.2, 0.8)
	var n_r := 0
	var n_foot := 0
	# 根石：壁の根元に据わった大きめの石〔半分埋まる〕。地面との接触線を折る
	var sf := rng.randf_range(0.5, 1.1)
	while sf < L - 0.45:
		var kk0: float = float(ka) + sf / DS
		var ex0: float = _at(C, "ex", kk0)
		var near_lantern := false
		for ls in C["lanterns"]:
			if absf(kk0 * DS - float(ls)) < 0.9:
				near_lantern = true
		if ex0 > 0.25 and not near_lantern and rng.randf() < 0.85:
			var fr0 := _frame_at(C, kk0)
			var u_g0: float = minf(_at(C, "u_top", kk0) + BATTER * clampf(ex0, 0.1, 1.3), _ucap(C, kk0))
			var u0: float = u_g0 + rng.randf_range(-0.02, 0.12)
			var p0: Vector2 = (fr0[0] as Vector2) + (fr0[1] as Vector2) * sd * u0
			var th0 := _terr(C, p0, kk0, u0)
			if not is_nan(th0):
				var surf0: float = th0 + _amp(C, kk0) * 0.8
				var rad0 := rng.randf_range(0.13, 0.23)
				var tg: Vector2 = (fr0[1] as Vector2).rotated(PI * 0.5)
				W4.uv_k = 1.2
				W4._uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
				var tone0: Color = W4._mul(W4._tone(rng, true), rng.randf_range(0.82, 1.0))
				_boulder(sm, Vector3(p0.x, surf0 + rad0 * 0.10, p0.y), rad0 * rng.randf_range(1.0, 1.5), rad0 * rng.randf_range(0.65, 0.9), rad0 * rng.randf_range(0.85, 1.1), atan2(tg.y, tg.x), tone0, surf0, rng)
				n_foot += 1
		sf += rng.randf_range(0.9, 1.7)
	while s < L:
		var kf: float = float(ka) + s / DS
		var count := 1 + int(rng.randf() < 0.45) + int(rng.randf() < 0.2)
		for q in count:
			var kk: float = clampf(kf + rng.randf_range(-6.0, 6.0), float(ka) + 5.0, float(kb) - 5.0)
			var fr2 := _frame_at(C, kk)
			var W := _mound_w(C, kk)
			var x: float = rng.randf_range(0.04, 0.8)
			var ex: float = _at(C, "ex", kk)
			if ex < 0.2:
				continue
			var u_g: float = minf(_at(C, "u_top", kk) + BATTER * clampf(ex, 0.1, 1.3), _ucap(C, kk))
			var u: float = u_g + x * W + 0.05
			var nl := false
			for ls in C["lanterns"]:
				if absf(kk * DS - float(ls)) < 0.9:
					nl = true
			if nl:
				continue
			var p: Vector2 = (fr2[0] as Vector2) + (fr2[1] as Vector2) * sd * u
			var th := _terr(C, p, kk, u)
			if is_nan(th):
				continue
			var surf: float = th + _amp(C, kk) * pow(1.0 - x, 2.0)
			var rad := rng.randf_range(0.045, 0.11)
			W4.uv_k = 0.9
			W4._uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
			var tone1: Color = W4._mul(W4._tone(rng, true), rng.randf_range(0.82, 1.0))
			_boulder(sm, Vector3(p.x, surf + rad * 0.05, p.y), rad * rng.randf_range(0.9, 1.4), rad * rng.randf_range(0.6, 0.9), rad * rng.randf_range(0.8, 1.1), rng.randf_range(0.0, TAU), tone1, surf, rng)
			n_r += 1
		s += rng.randf_range(0.6, 1.5)
	C["stats"]["rocks"] = n_r
	C["stats"]["foot_stones"] = n_foot
	# 草叢：土坡の上に少量〔fern_a 7 割／sasa_a 3 割〕。燈籠の足元は避ける
	var sp2 := rng.randf_range(0.4, 0.9)
	var n_pl := 0
	while sp2 < L - 0.35:
		var kp: float = float(ka) + sp2 / DS
		var exp: float = _at(C, "ex", kp)
		var nl2 := false
		for ls in C["lanterns"]:
			if absf(kp * DS - float(ls)) < 0.95:
				nl2 = true
		if exp > 0.2 and not nl2 and rng.randf() < 0.35:
			var frp := _frame_at(C, kp)
			var Wp := _mound_w(C, kp)
			var xp: float = rng.randf_range(0.45, 0.9)
			var u_gp: float = minf(_at(C, "u_top", kp) + BATTER * clampf(exp, 0.1, 1.3), _ucap(C, kp))
			var up: float = u_gp + xp * Wp
			var pp: Vector2 = (frp[0] as Vector2) + (frp[1] as Vector2) * sd * up
			var thp := _terr(C, pp, kp, up)
			if not is_nan(thp):
				var yp: float = thp + _amp(C, kp) * pow(1.0 - xp, 2.0) - 0.03
				var is_fern := rng.randf() < 0.7
				plants.append({"id": "fern_a" if is_fern else "sasa_a", "p": Vector3(pp.x, yp, pp.y), "yaw": rng.randf_range(0.0, TAU), "s": rng.randf_range(0.42, 0.65) if is_fern else rng.randf_range(0.32, 0.46)})
				n_pl += 1
		sp2 += rng.randf_range(1.0, 2.2)
	C["stats"]["plants"] = n_pl


# ───────────────────────────── 組み立て ─────────────────────────────

## build_sides の後で呼ぶ。runs に記録のある側ごとに、連続した 1 つの壁を作る
static func finish(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, touts: Array, tfars: Array, lanterns: Array) -> void:
	if not enabled:
		return
	var uvk0: float = W4.uv_k
	var tot := {}
	for si in 2:
		var sd: float = [-1.0, 1.0][si]
		if not runs.has(sd):
			continue
		var rl: Array = runs[sd]
		rl.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["ka"]) < int(b["ka"]))
		var C := _make_ctx(cl, sd, rl, touts[si], tfars[si], lanterns)
		C["stats"] = {}
		var bands: Array = []
		if integrated:
			# Same W5A machinery in bounded bands; shared envelope prevents cap-line steps.
			# No second stone system. Split at existing run boundaries, <=5.4 m.
			var start := int(C["ka"])
			var last := start
			for r: Dictionary in rl:
				if int(r["kb"]) - start > 108 and last > start:
					bands.append(Vector2i(start, last))
					start = last
				last = int(r["kb"])
			bands.append(Vector2i(start, last))
		else:
			bands.append(Vector2i(int(C["ka"]), int(C["kb"])))
		var aggregate := {"stones": 0, "base_stones": 0, "caps": 0, "rocks": 0, "foot_stones": 0, "plants": 0, "cover_max": 0.0}
		var records := []
		for band: Vector2i in bands:
			var B := C.duplicate()
			B["ka"] = band.x
			B["kb"] = band.y
			B["stats"] = {}
			var rng := RandomNumberGenerator.new()
			rng.seed = SEED + (101 if sd > 0.0 else 7) + (band.x * 17 if integrated else 0)
			_wall_tiles(sm, hm, B, rng)
			_caps(sm, B, rng)
			_mound(hm, B, rng)
			_rocks(sm, B, rng)
			for key: String in ["stones", "base_stones", "caps", "rocks", "foot_stones", "plants"]:
				aggregate[key] = int(aggregate[key]) + int(B["stats"].get(key, 0))
			aggregate["cover_max"] = maxf(float(aggregate["cover_max"]), float(B["stats"].get("cover_max", 0.0)))
			records.append({"ka": band.x, "kb": band.y, "stats": B["stats"]})
		C["stats"] = aggregate if integrated else records[0]["stats"]
		tot[sd] = {"stats": C["stats"], "bands": records, "ka": C["ka"], "kb": C["kb"], "ex": C["ex"], "k0": C["k0"]}
	stats = tot
	W4.uv_k = uvk0
	W4._uvo = Vector2.ZERO
