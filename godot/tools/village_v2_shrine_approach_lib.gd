extends RefCounted
## P10 R6b Shrine Approach Pilot（使用者 2026-10-09 D6 端景 Pilot／D7 石段＝視覺石段＋斜坡碰撞）。
## overlay `ShrineApproachP10`（gen/shrine_approach_p10.scn，root、WaterLifeP10 之後）。
## 根因（MASTER AUDIT R6b-01／03）：參道＝5 m secondary 道路 ribbon（車轍參數），s 37–100 m 約 30° 連續土坡，無踏面／蹴上；
##   主街第 5 段（(280,−80)→(300,−130)）的軸心盡頭是普通町家 MXC_018，沒有「往神社」的視覺終點。
## Pilot：
##   · 一の鳥居：sando_torii（P5 Hero 重用，扁額「龍神社」）立在參道起點 s 7 m（主街軸心盡頭的左前方、丘腳街路緣外），
##     讓主街終點＝神社入口；MXC_018 不動不刪。
##   · 石段：沿參道（平滑中心線）在坡度 > 16° 的段落鋪石段：蹴上 0.12–0.20、踏面依坡度 0.25–0.45、寬 3.0 m＋兩側袖石；
##     緩坡段（< 16°）＝順坡石疊（無蹴上）。踏面頂＝該段後緣的地形高＋0.02（石段整段在 P1 地形斜坡之上，地形不會蓋住踏面）。
##   · 碰撞＝平順斜坡（D7）：新的一條斜坡碰撞帶通過每段踏面中點（腳底與踏面差 ≤ 半個蹴上），起終點接回 P1 地形；
##     參道 ribbon 在石段範圍內挖掉中央（ground pilot shader 的 cut_s／cut_hw），兩側路肩保留。
##   · 石燈籠（garden_kit gk_toro_kasuga 重用）：石段沿線每 ≈ 20 m 一對（節奏點）。
## 不改封存（P1 地形、P3 道路、P5 鳥居資產、P9 R4-2 鎮守之森）；enabled=false 隱藏全部、停用碰撞。

const NODE_NAME := "ShrineApproachP10"
const OUTPUT := "res://maps/village_v2/gen/shrine_approach_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/shrine_approach.gd"
const ART_REVISION := "P10 R6b shrine approach pilot r3b（技術修正：一の鳥居の柱台に乗り上げ防止ガード）／r3（最終輪）：踏面明／立面暗（RISER_TONE 0.70）で段のリズム、石材 0.72；r2：石段色調（每段明暗差＋袖石苔味）、石材提亮（R6a 校正相當）、燈籠坐在坂に据えた水平基壇（ART_REVIEW）"
const TORII_SCN := "res://assets/village_v2/sando_torii/sando_torii.scn"
const LANTERN := "res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga.res"
const LANTERN_L1 := "res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga_l1.res"
const STONE := "res://assets/village_v2/_matlib/V2_Stone.tres"

const SANDO := [Vector2(300, -130), Vector2(292, -160), Vector2(280, -190), Vector2(266, -208), Vector2(258, -222)]
const SANDO_HW := 2.5
const TORII1_S := 7.0
const TORII1_SCALE := 1.0
const GUARD_R := 0.52       # 柱台 0.72 角の外接円（半対角 0.509）
const GUARD_H := 2.0
const HILL_TORII := Vector2(289.6, -166.0)
const STEP_W := 3.0
const CURB_W := 0.24
const CURB_UP := 0.10              # 袖石高出踏面
const RISER := [0.12, 0.20]
const TREAD := [0.25, 0.45]
const RISER_TARGET := 0.17
const SLOPE_MIN_DEG := 16.0        # 坡度 > 16° 鋪石段；之間的緩坡＝順坡石疊
const LANTERN_EVERY := 20.0
const LANTERN_OFF := STEP_W * 0.5 + CURB_W + 0.55
const PLINTH := 0.9          # 燈籠基壇（坂に据える水平の石台）邊長
const PLINTH_UP := 0.06
const RISER_TONE := 0.70     # 立面の明度（踏面＝1）
const OTHER_ROADS := {"HillFootStreet": [[200, -148], [250, -150], [300, -130], [342, -128], [372, -128]], "MainStreet": [[262, -20], [280, -80], [300, -130]]}
const OTHER_HW := {"HillFootStreet": 3.0, "MainStreet": 3.6}
const RIBBON := "Roads/SecondaryRoads/HillApproach"
const RIBBON_MESH := "res://maps/village_v2/gen/road_hillapproach.res"
const RIBBON_EDGE := {"edge_w": 0.35, "edge_irreg": 0.15, "edge_core": 0.35, "center_patch": 0.0}


## 平滑中心線（Chaikin 4 次，端點固定）→ 每 0.05 m 重新取樣
static func centerline() -> PackedVector2Array:
	var pts := PackedVector2Array(SANDO)
	for it in 4:
		var q := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			q.append(pts[i].lerp(pts[i + 1], 0.25))
			q.append(pts[i].lerp(pts[i + 1], 0.75))
		q.append(pts[pts.size() - 1])
		pts = q
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var t := 0.05 - acc
		while t <= L:
			out.append(a.lerp(b, t / L))
			t += 0.05
		acc = L - (t - 0.05)
	return out


static func s_at(cl: PackedVector2Array, k: int) -> float:
	return k * 0.05


static func tangent(cl: PackedVector2Array, k: int) -> Vector2:
	var a := cl[maxi(k - 6, 0)]
	var b := cl[mini(k + 6, cl.size() - 1)]
	return (b - a).normalized()


## 地形斜坡高度（只認 TerrainCollision；P1 碰撞＝玩家實際走的面）
static func ramp_profile(v: Node3D, cl: PackedVector2Array) -> PackedFloat32Array:
	var sp := v.get_world_3d().direct_space_state
	var out := PackedFloat32Array()
	out.resize(cl.size())
	for k in cl.size():
		var p := cl[k]
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
		var ex: Array[RID] = []
		var y := NAN
		for t in 12:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				y = float(h["position"].y)
				break
			ex.append(h["rid"])
		out[k] = y
	return out


## 石段：回傳 [{k0, k1, y0, y1, kind}]（k＝中心線索引）
##   step：踏面水平，y0＝y1＝[k0,k1] 內地形最高＋0.02（後緣）；slab：緩坡石疊，y0／y1＝兩端地形＋0.03
static func steps(cl: PackedVector2Array, H: PackedFloat32Array) -> Array:
	var out := []
	var n := cl.size()
	var slope := func(k: int) -> float:
		var a := maxi(k - 10, 0)
		var b := mini(k + 10, n - 1)
		return rad_to_deg(atan2(H[b] - H[a], (b - a) * 0.05))
	var SL: Callable = slope
	var k := 0
	while k < n - 1 and absf(float(SL.call(k))) < SLOPE_MIN_DEG:
		k += 1
	var k_start := k
	var k_end := n - 1
	while k_end > k_start and absf(float(SL.call(k_end))) < SLOPE_MIN_DEG:
		k_end -= 1
	# 逐段貪婪：踏面長 0.26–0.45 中挑「蹴上最接近 0.17」者；踏面頂＝段內地形最高＋0.02（不被地形蓋住）
	var t0 := int(round(TREAD[0] / 0.05))
	var t1 := int(round(TREAD[1] / 0.05))
	var y_prev := H[k_start]
	k = k_start
	while k < k_end:
		var best := {}
		for tk in range(t0, t1 + 1):
			var kn := k + tk
			if kn > k_end:
				break
			var hm := -INF
			for j in range(k, kn + 1):
				hm = maxf(hm, H[j])
			var y := hm + 0.02
			var r := y - y_prev
			var sc := absf(r - RISER_TARGET) + (0.0 if r <= RISER[1] else 1.0)
			if best.is_empty() or sc < float(best["sc"]):
				best = {"kn": kn, "y": y, "r": r, "sc": sc}
		if best.is_empty():
			break
		if float(best["r"]) < RISER[0]:
			# 緩坡：順坡石疊，延伸到坡度回到 16° 以上（或到頂）
			var kn2 := mini(k + t1, k_end)
			while kn2 < k_end and absf(float(SL.call(kn2))) < SLOPE_MIN_DEG:
				kn2 += 1
			var y0 := maxf(y_prev, H[k] + 0.03)
			var y1 := H[kn2] + 0.03
			var deficit := 0.0
			for j in range(k, kn2 + 1):
				var yl := lerpf(y0, y1, float(j - k) / float(maxi(kn2 - k, 1)))
				deficit = maxf(deficit, H[j] + 0.02 - yl)
			out.append({"k0": k, "k1": kn2, "y0": y0 + deficit, "y1": y1 + deficit, "kind": "slab"})
			y_prev = y1 + deficit
			k = kn2
			continue
		out.append({"k0": k, "k1": int(best["kn"]), "y0": float(best["y"]), "y1": float(best["y"]), "kind": "step"})
		y_prev = float(best["y"])
		k = int(best["kn"])
	return out


## 斜坡碰撞帶的中心線點：[s 索引, y]——起點＝第一段前緣地形、每段踏面中點（step）／兩端（slab）、終點＝最後一段後緣地形
static func ramp_points(st: Array, H: PackedFloat32Array) -> Array:
	var out := []
	if st.is_empty():
		return out
	var k0 := int(st[0]["k0"])
	var kl0 := maxi(k0 - 6, 0)   # 0.3 m 引き込み：第一段の蹴上前から斜坡を上げ始める
	out.append([kl0, H[kl0] + 0.02])
	var prev: Dictionary = {}
	for a: Dictionary in st:
		if String(a["kind"]) == "step":
			# 緩坡石疊の直後の段：斜坡を 0.3 m 手前から上げ始める（蹴上の前で足が段に埋まらない）
			if not prev.is_empty() and String(prev["kind"]) == "slab":
				var kb := int(a["k0"]) - 6
				var ka := int(prev["k0"])
				if kb > ka:
					var t := float(kb - ka) / float(maxi(int(prev["k1"]) - ka, 1))
					out[out.size() - 1] = [kb, lerpf(float(prev["y0"]), float(prev["y1"]), t)]
			out.append([(int(a["k0"]) + int(a["k1"])) / 2, float(a["y0"])])
		else:
			if int(out[out.size() - 1][0]) != int(a["k0"]):
				out.append([int(a["k0"]), float(a["y0"])])
			out.append([int(a["k1"]), float(a["y1"])])
		prev = a
	var kl := int(st[st.size() - 1]["k1"])
	out.append([kl, H[kl] + 0.02])
	return out


## 一の鳥居：參道 s＝TORII1_S 的點；+z（扁額面）朝參道下行（往村子）
static func torii1_xf(cl: PackedVector2Array, H: PackedFloat32Array, s_at_m := TORII1_S) -> Transform3D:
	var k := int(round(s_at_m / 0.05))
	var p := cl[k]
	var t := tangent(cl, k)
	var face := -t
	var yaw := atan2(face.x, face.y)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * TORII1_SCALE), Vector3(p.x, H[k], p.y))


static func lantern_specs(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, sp: PhysicsDirectSpaceState3D = null) -> Array:
	var out := []
	if st.is_empty():
		return out
	var s0 := float(st[0]["k0"]) * 0.05
	var s1 := float(st[st.size() - 1]["k1"]) * 0.05
	var s := s0 + 6.0
	while s < s1 - 3.0:
		# 坂の横の地面が一番平らな位置へ ±1.5 m だけずらす（基壇を低く）
		var best_s := s
		if sp != null:
			var best := INF
			for ds in [0.0, 0.75, -0.75, 1.5, -1.5]:
				var k2 := int(round((s + ds) / 0.05))
				var t2 := tangent(cl, k2)
				var n2 := Vector2(-t2.y, t2.x)
				var worst := 0.0
				for sd: float in [-1.0, 1.0]:
					var g := lantern_ground(sp, cl[k2] + n2 * sd * LANTERN_OFF)
					worst = maxf(worst, float(g[1]) - float(g[0]))
				if worst < best - 0.02:
					best = worst
					best_s = s + ds
		var k := int(round(best_s / 0.05))
		var t := tangent(cl, k)
		var nrm := Vector2(-t.y, t.x)
		for sd: float in [-1.0, 1.0]:
			var p: Vector2 = cl[k] + nrm * sd * LANTERN_OFF
			out.append({"p": p, "yaw": atan2(-nrm.x * sd, -nrm.y * sd), "s": best_s})
		s += LANTERN_EVERY
	return out


## 石段首尾 → ribbon 的沿路 s（UV.y）；ribbon 頂點每 2 m 一對，取最近頂點再線性內插
static func ribbon_cut_s(cl: PackedVector2Array, st: Array) -> Vector2:
	var m := load(RIBBON_MESH) as ArrayMesh
	var arr := m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var res := Vector2()
	for e in 2:
		var p: Vector2 = cl[int(st[0]["k0"])] if e == 0 else cl[int(st[st.size() - 1]["k1"])]
		var best := INF
		var bs := 0.0
		for i in vs.size():
			var d := Vector2(vs[i].x, vs[i].z).distance_to(p)
			# 只看中心線附近（左右頂點的中點）：用 |UV.x|·hw 估側距
			if d < best:
				best = d
				bs = uv[i].y
		res[e] = bs
	return Vector2(res.x - 0.6, res.y + 0.6)


static var _vc := Color(1, 1, 1)


## 燈籠基壇的四角地面：[最低, 最高]
static func lantern_ground(sp: PhysicsDirectSpaceState3D, p: Vector2) -> Array:
	var lo := INF
	var hi := -INF
	var hp := PLINTH * 0.5
	for c2 in [Vector2(0, 0), Vector2(hp, hp), Vector2(-hp, hp), Vector2(hp, -hp), Vector2(-hp, -hp)]:
		# 只認 P1 地形（TerrainCollision）：不要打到樹幹、已掛的本 overlay（舊燈籠／斜坡碰撞）
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x + c2.x, 80.0, p.y + c2.y), Vector3(p.x + c2.x, -20.0, p.y + c2.y))
		var ex: Array[RID] = []
		for t in 16:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				lo = minf(lo, float(h["position"].y))
				hi = maxf(hi, float(h["position"].y))
				break
			ex.append(h["rid"])
	return [lo, hi]


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_color(_vc)
		st.set_normal(n)
		st.set_uv(Vector2(v.x + v.z * 0.7, v.y))
		st.add_vertex(v)


## 方塊：底面四點（xz）＋底高 yb／頂高 yt（q[0],q[3]＝前緣、q[1],q[2]＝後緣；yt2＝後緣頂高，NAN＝水平）
static func _prism(st: SurfaceTool, q: Array, yb: float, yt: float, yt2 := NAN) -> void:
	var B := []
	var T := []
	var yb2 := yt if is_nan(yt2) else yt2
	for i in 4:
		var p: Vector2 = q[i]
		B.append(Vector3(p.x, yb, p.y))
		T.append(Vector3(p.x, yt if (i == 0 or i == 3) else yb2, p.y))
	_quad(st, T[0], T[1], T[2], T[3])
	# 立面（蹴上・側面）は踏面より暗く：目地の汚れ・日陰——遠くから「段」のリズムが読めるように（r3）
	var top_c := _vc
	_vc = Color(top_c.r * RISER_TONE, top_c.g * RISER_TONE, top_c.b * RISER_TONE)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, B[i], B[j], T[j], T[i])
	_vc = top_c


static func build(v: Node3D, cl: PackedVector2Array, H: PackedFloat32Array) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R6b pilot")
	var st := steps(cl, H)
	# 石段＋袖石（一個網格；無碰撞＝D7 斜坡碰撞）
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61007
	for i in st.size():
		var a: Dictionary = st[i]
		var k0 := int(a["k0"])
		var k1 := int(a["k1"])
		var t0 := tangent(cl, k0)
		var t1 := tangent(cl, k1)
		var n0 := Vector2(-t0.y, t0.x)
		var n1 := Vector2(-t1.y, t1.x)
		var p0 := cl[k0]
		var p1 := cl[k1] + t1 * 0.012   # 與下一段重疊 1.2 cm，不留縫
		var y0 := float(a["y0"])
		var y1 := float(a["y1"])
		var yb := minf(H[k0], H[k1]) - 0.45
		var hw := STEP_W * 0.5
		# 踏石：橫向分 2 枚（目地），頂面微差
		for j in 2:
			var u0 := -hw + STEP_W * j * 0.5
			var u1 := u0 + STEP_W * 0.5 - 0.012
			var dy := rng.randf_range(-0.005, 0.005)
			var tone := rng.randf_range(0.80, 1.0)
			_vc = Color(tone, tone * rng.randf_range(0.97, 1.0), tone * rng.randf_range(0.93, 0.98))
			_prism(sm, [p0 + n0 * u0, p1 + n1 * u0, p1 + n1 * u1, p0 + n0 * u1], yb, y0 + dy, y1 + dy)
		# 袖石（兩側，高出踏面 CURB_UP）
		for sd: float in [-1.0, 1.0]:
			var ia: float = hw * sd
			var ib: float = (hw + CURB_W) * sd
			var q := [p0 + n0 * minf(ia, ib), p1 + n1 * minf(ia, ib), p1 + n1 * maxf(ia, ib), p0 + n0 * maxf(ia, ib)]
			var mt := rng.randf_range(0.70, 0.86)
			_vc = Color(mt * 0.94, mt, mt * 0.86)   # 袖石：日陰側の苔味（緑寄り、彩度低）
			_prism(sm, q, yb, y0 + CURB_UP, y1 + CURB_UP)
	sm.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "StoneSteps"
	mi.mesh = sm.commit()
	var stm := (load(STONE) as StandardMaterial3D).duplicate() as StandardMaterial3D
	stm.albedo_color = Color(0.72, 0.72, 0.70)   # R6a 校正相當より少し明るく（新設の花崗岩、踏面の白さ）；立面は RISER_TONE で暗く
	stm.resource_name = "P10_SandoStone"
	mi.material_override = stm
	mi.visibility_range_end = 260.0
	mi.set_meta("steps", st.size())
	root.add_child(mi)
	# 斜坡碰撞帶（ConcavePolygonShape3D）：寬＝石段＋袖石
	var rp := ramp_points(st, H)
	var faces := PackedVector3Array()
	var half := STEP_W * 0.5 + CURB_W
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		var ta := tangent(cl, ka)
		var tb := tangent(cl, kb)
		var na := Vector2(-ta.y, ta.x) * half
		var nb := Vector2(-tb.y, tb.x) * half
		var ya := float(rp[i][1])
		var yb2 := float(rp[i + 1][1])
		var a0 := Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y)
		var a1 := Vector3(cl[ka].x + na.x, ya, cl[ka].y + na.y)
		var b0 := Vector3(cl[kb].x - nb.x, yb2, cl[kb].y - nb.y)
		var b1 := Vector3(cl[kb].x + nb.x, yb2, cl[kb].y + nb.y)
		faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	var shp := ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	shp.backface_collision = true
	var rb := StaticBody3D.new()
	rb.name = "RampCollision"
	var rcs := CollisionShape3D.new()
	rcs.name = "Ramp"
	rcs.shape = shp
	rb.add_child(rcs)
	root.add_child(rb)
	# 參道 ribbon 挖洞範圍（ribbon 自己的沿路 s＝UV.y）：石段首尾投影到 ribbon 頂點
	root.set("ribbon_path", NodePath(RIBBON))
	root.set("ribbon_params", RIBBON_EDGE)
	root.set("cut_s", ribbon_cut_s(cl, st))
	root.set("cut_hw", STEP_W * 0.5 + CURB_W - 0.05)
	# 一の鳥居（P5 Hero 實例）
	var tor := (load(TORII_SCN) as PackedScene).instantiate() as Node3D
	tor.name = "IchiNoTorii"
	tor.transform = torii1_xf(cl, H)
	tor.set_meta("asset", "sando_torii（P5 Hero 重用）")
	root.add_child(tor)
	# 柱台ガード：P5 鳥居の柱台碰撞（0.72 角・高 0.58）は膠囊が乗り上げられる → 斜めに歩くと柱台の縁に 0.5 m 浮いて引っかかる
	# （19-point walk で實測 dy 0.50–0.58）。資產は觸らず、柱台を包む円柱（r 0.52・地面〜1.55 m）を overlay 側に足して乗れなくする。
	var gd := StaticBody3D.new()
	gd.name = "IchiNoToriiGuard"
	gd.transform = tor.transform
	for sd: float in [-1.0, 1.0]:
		var gcs := CollisionShape3D.new()
		gcs.name = "Guard_%s" % ("L" if sd < 0.0 else "R")
		var cyl := CylinderShape3D.new()
		cyl.radius = GUARD_R
		cyl.height = GUARD_H
		gcs.shape = cyl
		gcs.position = Vector3(2.25 * sd, -0.45 + GUARD_H * 0.5, 0.0)
		gd.add_child(gcs)
	root.add_child(gd)
	# 石燈籠
	var lg := Node3D.new()
	lg.name = "Lanterns"
	root.add_child(lg)
	var sp := v.get_world_3d().direct_space_state
	var li := 0
	for ls in lantern_specs(cl, H, st, sp):
		var p: Vector2 = ls["p"]
		var g2 := lantern_ground(sp, p)
		var gy := float(g2[1]) + PLINTH_UP   # 基壇頂（水平）＝四角最高＋0.06
		# 基壇：0.9 × 0.9 石、底＝四角最低 −0.15（斜面に据える：坂側は埋まり、谷側は見える）
		var pst := SurfaceTool.new()
		pst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_vc = Color(0.86, 0.86, 0.82)
		var hp := PLINTH * 0.5
		_prism(pst, [p + Vector2(-hp, -hp), p + Vector2(-hp, hp), p + Vector2(hp, hp), p + Vector2(hp, -hp)], float(g2[0]) - 0.15, gy)
		pst.generate_tangents()
		var pmi := MeshInstance3D.new()
		pmi.name = "Plinth_%02d" % li
		pmi.mesh = pst.commit()
		pmi.material_override = stm
		pmi.visibility_range_end = 160.0
		lg.add_child(pmi)
		var ln := Node3D.new()
		ln.name = "Toro_%02d" % li
		li += 1
		ln.transform = Transform3D(Basis(Vector3.UP, float(ls["yaw"])), Vector3(p.x, gy, p.y))   # 坐在基壇頂
		for lod in 2:
			var m := MeshInstance3D.new()
			m.name = "LOD%d" % lod
			m.mesh = load(LANTERN if lod == 0 else LANTERN_L1)
			m.visibility_range_begin = 0.0 if lod == 0 else 45.0
			m.visibility_range_end = 45.0 if lod == 0 else 160.0
			ln.add_child(m)
		var body := StaticBody3D.new()
		body.name = "Collision"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.62, 1.9, 0.62)
		cs.shape = bs
		cs.position = Vector3(0, 0.95, 0)
		body.add_child(cs)
		ln.add_child(body)
		ln.set_meta("s", ls["s"])
		lg.add_child(ln)
	return root
