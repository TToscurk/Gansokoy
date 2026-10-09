extends RefCounted
## P10 R6b.1 Shrine Approach Redesign — 代表区間の石段 Kit Pilot（使用者 2026-10-09 ROUND 3 FINAL：r8 は不 ART_APPROVED、細かい苔・ひび・落葉の追加は止め、
## 「整體形體」へ：186 段の模組の繰り返しを避ける・明確な比例差のある石段 Kit・踏面／鼻先／踊り場と地形の自然な関係・上り下りの可読性・樸素な歴史感）。
## 一小段だけ（s 38–68 m：踊り場 1・2 を含む 1 区間）。参道全体は作り直さない。r8（ShrineApproachP10）は比較候補として残す（場景・overlay は不変）。
## 段の計画（各段の k0／k1／踏面高さ）は r8 と同じ＝斜坡碰撞・SWALK はそのまま有効；変えるのは見える石の形だけ（visual-only Pilot、審圖用に記憶體内で生成）。
## Kit の考え方（r8 との違い）：
##   ・石の比例を 3 類に分ける：L＝一枚の長石（幅 1.9–2.4 m・厚い・鼻先が丸く減っている・中央が踏み減り）／P＝二つ割り（幅の違う 2 石、鼻先の出・高さが石ごとに違う）／
##     N＝自然石混じり（3 石、うち 1 石は 5 角の不整形）。r8 は全段が同じ厚さ・同じ直線の鼻先・同じ面取りの「板」だった。
##   ・段の両端を揃えない（片側 1.0–1.25 m、前後でも ±8 cm 斜め）→ 袖石の直線帯をやめ、段の端は土・落葉の法面（区間で連続した帯）に埋まって地形へ下りる。
##   ・鼻先の線は石ごとに左右で ±3 cm 前後（揃った直線にしない）。
##   ・4–7 段ごとに片側へ据え石（自然石の大きな塊、0.45–0.75 m）＝地形を押さえる石垣の名残り。
##   ・踊り場＝大小の不整形の敷石（0.5–1.0 m）と土の目地、前縁は厚い框石（踊り場の縁がはっきり読める＝下りで「ここで平ら」が分かる）。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const S_RANGE := Vector2(38.0, 68.0)

static var _vc := Color.WHITE
static var _uvo := Vector2.ZERO


static func _uv(v: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.6:
		return Vector2(v.x, v.z) * 0.9 + _uvo
	return Vector2(v.x + v.z, v.y) * 0.9 + _uvo


## 外向き（center から離れる向き）が表になる四角（Godot の表＝(c−a)×(b−a)）。ca／cd＝上側／下側の頂点色（y で判定）
static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3, ca := Color(), cd := Color()) -> void:
	_tri_out(st, a, b, c, center, ca, cd, (a.y + b.y + c.y + d.y) * 0.25)
	_tri_out(st, a, c, d, center, ca, cd, (a.y + b.y + c.y + d.y) * 0.25)


static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, ca := Color(), cd := Color(), ymid := NAN) -> void:
	var n := (c - a).cross(b - a)
	if n.length() < 1e-10:
		return
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var use_c := ca != Color() and cd != Color()
	var ym := ymid if not is_nan(ymid) else (a.y + b.y + c.y) / 3.0
	for v: Vector3 in [a, b, c]:
		st.set_color(_vc if not use_c else (ca if v.y >= ym else cd))
		st.set_normal(n)
		st.set_uv(_uv(v, n))
		st.add_vertex(v)


static func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var vs := [a, b, c]
	if (c - a).cross(b - a).y < 0.0:
		vs = [a, c, b]
	var n: Vector3 = (vs[2] - vs[0]).cross(vs[1] - vs[0]).normalized()
	for v: Vector3 in vs:
		st.set_color(_vc)
		st.set_normal(n)
		st.set_uv(_uv(v, n))
		st.add_vertex(v)


## 石 1 個：上面の多角形 top（前縁→…→後縁の順、xz＋y）、底 ybot、鼻先の丸み r（前縁 2 点 top[0]・top[1] の辺に 2 段の面取り）
static func _block(st: SurfaceTool, top: Array, ybot: float, fwd: Vector2, r: float, base: Color) -> void:
	var c := Vector3.ZERO
	for p: Vector3 in top:
		c += p
	c /= top.size()
	var center := Vector3(c.x, ybot, c.z)
	# 鼻先（前縁 0–1）の面取り：上面の前縁を r だけ奥へ、r·0.45 下に中間線
	var t2 := top.duplicate()
	var f0: Vector3 = top[0]
	var f1: Vector3 = top[1]
	var back := Vector3(fwd.x, 0, fwd.y) * -1.0   # fwd＝下り方向（前）；奥＝-fwd
	t2[0] = f0 + back * r
	t2[1] = f1 + back * r
	var m0 := f0 + back * r * 0.35 + Vector3(0, -r * 0.45, 0)
	var m1 := f1 + back * r * 0.35 + Vector3(0, -r * 0.45, 0)
	var e0 := f0 + Vector3(0, -r, 0)
	var e1 := f1 + Vector3(0, -r, 0)
	_vc = base
	for i in range(1, t2.size() - 1):
		_tri_up(st, t2[0], t2[i], t2[i + 1])
	_vc = SA._mul(base, 1.08)
	_quad_out(st, t2[0], t2[1], m1, m0, center + Vector3(0, -1.0, 0) + back * 0.3)
	_vc = SA._mul(base, 0.92)
	_quad_out(st, m0, m1, e1, e0, center + back * 0.5)
	# 蹴上（前面）：上明 → 下暗
	var b0 := Vector3(f0.x, ybot, f0.z)
	var b1 := Vector3(f1.x, ybot, f1.z)
	_vc = SA._mul(base, 0.72)
	_quad_out(st, e0, e1, b1, b0, center + back * 0.5, SA._mul(base, 0.74), SA._mul(base, 0.45))
	# 側面・背面
	_vc = SA._mul(base, 0.66)
	for i in range(1, t2.size()):
		var a: Vector3 = t2[i]
		var b: Vector3 = t2[(i + 1) % t2.size()]
		if i == t2.size() - 1:
			b = t2[0]
		_quad_out(st, a, b, Vector3(b.x, ybot, b.z), Vector3(a.x, ybot, a.z), center)
	# 前の左右の端（面取りの断面＋前の下端）：t2[0]→m0→e0→b0→(t2[0] の底) の扇
	var tb0 := Vector3(t2[0].x, ybot, t2[0].z)
	var tb1 := Vector3(t2[1].x, ybot, t2[1].z)
	_tri_out(st, t2[0], m0, e0, center)
	_tri_out(st, t2[0], e0, b0, center)
	_tri_out(st, t2[0], b0, tb0, center)
	_tri_out(st, t2[1], m1, e1, center)
	_tri_out(st, t2[1], e1, b1, center)
	_tri_out(st, t2[1], b1, tb1, center)


static func terrain_y(sp: PhysicsDirectSpaceState3D, terrain: Object, p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 90, p.y), Vector3(p.x, -30, p.y))
	var ex: Array[RID] = []
	for t in 16:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["collider"] == terrain:
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


static func build_pilot(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, sp: PhysicsDirectSpaceState3D, terrain: Object) -> MeshInstance3D:
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 610001
	var k_lo := int(S_RANGE.x / 0.05)
	var k_hi := int(S_RANGE.y / 0.05)
	var prev_top := NAN
	var since_boulder := 0
	var boulder_side := 1.0
	var counts := {"L": 0, "P": 0, "N": 0, "landing": 0, "boulder": 0, "berm": 0}
	for i in st.size():
		var a: Dictionary = st[i]
		var k0 := int(a["k0"])
		var k1 := int(a["k1"])
		var y0 := float(a["y0"])
		if k1 < k_lo or k0 > k_hi:
			prev_top = float(a["y1"])
			continue
		var kind := String(a["kind"])
		var rise := (y0 - prev_top) if not is_nan(prev_top) else 0.15
		var ybot := minf(H[k0], H[k1]) - 0.35
		if not is_nan(prev_top):
			ybot = minf(ybot, prev_top - 0.12)
		prev_top = float(a["y1"])
		var ta := SA.tangent(cl, k0)
		var tb := SA.tangent(cl, k1)
		var na := Vector2(-ta.y, ta.x)
		var nb := Vector2(-tb.y, tb.x)
		var fwd := -ta   # 下り方向
		# 段の両端（揃えない）
		var uL := -rng.randf_range(1.0, 1.25)
		var uR := rng.randf_range(1.0, 1.25)
		var sk := rng.randf_range(-0.08, 0.08)
		if kind == "landing":
			counts["landing"] += 1
			_landing(sm, cl, k0, k1, y0, ybot, uL - 0.1, uR + 0.1, rng)
		else:
			var rr := rng.randf()
			var typ := "L" if rr < 0.4 else ("P" if rr < 0.8 else "N")
			counts[typ] += 1
			var cuts := [uL]
			if typ == "P":
				cuts.append(lerpf(uL, uR, rng.randf_range(0.35, 0.65)))
			elif typ == "N":
				var c1 := rng.randf_range(0.25, 0.4)
				cuts.append(lerpf(uL, uR, c1))
				cuts.append(lerpf(uL, uR, rng.randf_range(c1 + 0.2, 0.75)))
			cuts.append(uR)
			var n_irreg := rng.randi_range(0, cuts.size() - 2) if typ == "N" else -1
			for j in cuts.size() - 1:
				var u0 := float(cuts[j]) + (0.012 if j > 0 else 0.0)
				var u1 := float(cuts[j + 1]) - (0.012 if j < cuts.size() - 2 else 0.0)
				var nose := rng.randf_range(0.0, 0.05) if typ != "L" else rng.randf_range(0.02, 0.06)
				var dy := rng.randf_range(-0.012, 0.012) if typ != "L" else 0.0
				var tilt := rng.randf_range(0.004, 0.016)
				var r := rng.randf_range(0.05, 0.09) if typ == "L" else rng.randf_range(0.03, 0.06)
				var base := SA._stone_tone(rng, j == 0 or j == cuts.size() - 2)
				if typ == "L":
					base = SA._mul(base, 0.97)
				var pf := cl[k0] + fwd * nose
				var pb := cl[k1] + tb * 0.012
				var yf := y0 + dy - tilt
				var yb := y0 + dy
				# 鼻先の線を石ごとに少し斜めに（左右の端で前後 ±3 cm）＝据え直し・摩耗で揃っていない
				var dl := rng.randf_range(-0.03, 0.03)
				var dr := rng.randf_range(-0.03, 0.03)
				var top := [Vector3((pf + fwd * dl + na * u0).x, yf, (pf + fwd * dl + na * u0).y), Vector3((pf + fwd * dr + na * u1).x, yf, (pf + fwd * dr + na * u1).y)]
				var bu1 := u1 + sk * (1.0 if j == cuts.size() - 2 else 0.0)
				var bu0 := u0 + sk * (1.0 if j == 0 else 0.0)
				if j == n_irreg:
					# 不整形：右側に膨らみ、後ろの角をずらす
					var mid := pb.lerp(pf, 0.5)
					top.append(Vector3((pb + nb * bu1).x + rng.randf_range(-0.04, 0.04), yb, (pb + nb * bu1).y))
					top.insert(2, Vector3((mid + na * (u1 + rng.randf_range(0.03, 0.1))).x, lerpf(yf, yb, 0.5), (mid + na * (u1 + 0.06)).y))
					top.append(Vector3((pb + nb * (bu0 + rng.randf_range(0.0, 0.08))).x, yb, (pb + nb * (bu0 + 0.04)).y))
				else:
					top.append(Vector3((pb + nb * bu1).x, yb, (pb + nb * bu1).y))
					top.append(Vector3((pb + nb * bu0).x, yb, (pb + nb * bu0).y))
				# 上面は front(0,1) → 右後 → 左後 の順（_block の多角形：0,1 が前縁）
				_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
				_block(sm, top, ybot, fwd, r, base)
				# L：中央の踏み減り（幅 0.6–0.9 m、前で 1.5 cm 低い暗い帯＝足跡の磨り減り）
				if typ == "L" and u1 - u0 > 1.4:
					var w := rng.randf_range(0.3, 0.45)
					var cu := rng.randf_range(-0.15, 0.15)
					var pa2 := cl[k0] + fwd * nose + ta * r
					_vc = SA._mul(base, 1.12)
					_tri_up(sm, Vector3((pa2 + na * (cu - w)).x, yf + 0.0012, (pa2 + na * (cu - w)).y), Vector3((pa2 + na * (cu + w)).x, yf + 0.0012, (pa2 + na * (cu + w)).y), Vector3((pb + nb * cu).x, yb + 0.0012, (pb + nb * cu).y))
			# 据え石：4–7 段ごとに片側
			since_boulder += 1
			if since_boulder >= rng.randi_range(4, 7):
				since_boulder = 0
				boulder_side *= -1.0
				var ue2 := (uL if boulder_side < 0.0 else uR) + boulder_side * rng.randf_range(0.15, 0.3)
				var bw := rng.randf_range(0.45, 0.75)
				var bc := cl[int((k0 + k1) / 2)] + na * (ue2 + boulder_side * bw * 0.5)
				var gy := terrain_y(sp, terrain, bc)
				if not is_nan(gy):
					var ht := y0 + rng.randf_range(0.05, 0.25)
					var poly := []
					var nseg := 7
					var rot := rng.randf() * TAU
					for q in nseg:
						var ang := rot + TAU * q / nseg
						var rad := bw * 0.5 * rng.randf_range(0.75, 1.0)
						poly.append(bc + Vector2(cos(ang), sin(ang)) * rad)
					# 丸みのある自然石：上面（0.72 倍に縮めた輪）＋肩の輪（1.0 倍、上面 −0.10〜0.16）＋地中の輪（0.92 倍）
					var col := Color(0.55, 0.58, 0.47) if rng.randf() < 0.5 else Color(0.62, 0.62, 0.58)
					var drop := rng.randf_range(0.10, 0.16)
					var ring_t := []
					var ring_m := []
					var ring_b := []
					for q in nseg:
						var pp: Vector2 = poly[q]
						var dv := pp - bc
						var yt := ht - rng.randf_range(0.0, 0.05)
						ring_t.append(Vector3(bc.x + dv.x * 0.72, yt, bc.y + dv.y * 0.72))
						ring_m.append(Vector3(pp.x, yt - drop, pp.y))
						ring_b.append(Vector3(bc.x + dv.x * 0.92, gy - 0.25, bc.y + dv.y * 0.92))
					var cen := Vector3(bc.x, (ht + gy) * 0.5 - 0.1, bc.y)
					_vc = col
					for q in range(1, nseg - 1):
						_tri_up(sm, ring_t[0], ring_t[q], ring_t[q + 1])
					for q in nseg:
						var q2 := (q + 1) % nseg
						_vc = SA._mul(col, 0.9)
						_quad_out(sm, ring_t[q], ring_t[q2], ring_m[q2], ring_m[q], cen)
						_vc = SA._mul(col, 0.68)
						_quad_out(sm, ring_m[q], ring_m[q2], ring_b[q2], ring_b[q], cen)
					counts["boulder"] += 1
	# 両脇の法面（土・落葉）：区間全体で 1 本の連続した帯。内縁＝各段の鼻先（踏面 −0.06）を結ぶ滑らかな線（段の石の端は土に半分埋まる）、
	# 外縁＝横 0.55–0.95 m 先の地形＋0.02。r1 の「段ごとの四角」は段差ごとに縦の三角の隙間（鋸歯）を作った。
	var fronts := []   # [k, y]
	for a2: Dictionary in st:
		var kk0 := int(a2["k0"])
		var kk1 := int(a2["k1"])
		if kk1 < k_lo or kk0 > k_hi:
			continue
		fronts.append([kk0, float(a2["y0"]) - 0.06])
		if String(a2["kind"]) == "landing":
			fronts.append([kk1, float(a2["y1"]) - 0.06])
	if fronts.size() >= 2:
		for sd: float in [-1.0, 1.0]:
			var prev_in := Vector3.ZERO
			var prev_out := Vector3.ZERO
			var have := false
			var kk := int(fronts[0][0])
			var kend := int(fronts[fronts.size() - 1][0])
			var fi := 0
			var wv := rng.randf_range(0.55, 0.95)
			while kk <= kend:
				while fi < fronts.size() - 2 and int(fronts[fi + 1][0]) <= kk:
					fi += 1
				var ka3 := int(fronts[fi][0])
				var kb3 := int(fronts[fi + 1][0])
				var yin := lerpf(float(fronts[fi][1]), float(fronts[fi + 1][1]), clampf(float(kk - ka3) / maxf(kb3 - ka3, 1), 0.0, 1.0))
				var t3 := SA.tangent(cl, kk)
				var n3 := Vector2(-t3.y, t3.x)
				wv = clampf(wv + rng.randf_range(-0.08, 0.08), 0.5, 1.0)
				var pin := cl[kk] + n3 * sd * 0.98
				var pout := cl[kk] + n3 * sd * (0.98 + wv)
				var go := terrain_y(sp, terrain, pout)
				if is_nan(go):
					go = yin - 0.3
				var vin := Vector3(pin.x, yin, pin.y)
				var vout := Vector3(pout.x, minf(go + 0.02, yin - 0.02), pout.y)
				if have:
					var lt := rng.randf_range(0.85, 1.05)
					_vc = Color(0.36 * lt, 0.33 * lt, 0.24 * lt) if rng.randf() < 0.6 else Color(0.30 * lt, 0.36 * lt, 0.20 * lt)
					_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
					var mid := (vin + prev_in) * 0.5
					_quad_out(sm, prev_in, vin, vout, prev_out, Vector3(mid.x, mid.y - 3.0, mid.z))
					counts["berm"] += 1
				prev_in = vin
				prev_out = vout
				have = true
				kk += 10
	_uvo = Vector2.ZERO
	sm.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "R6b1PilotSteps"
	mi.mesh = sm.commit()
	var stm := (load(SA.STONE) as StandardMaterial3D).duplicate() as StandardMaterial3D
	stm.albedo_color = SA.STONE_ALBEDO
	mi.material_override = stm
	mi.set_meta("counts", counts)
	return mi


## 踊り場：不整形の敷石（0.5–1.0 m）＋土の目地（下に土の板）、前縁は厚い框石
static func _landing(sm: SurfaceTool, cl: PackedVector2Array, k0: int, k1: int, y: float, ybot: float, uL: float, uR: float, rng: RandomNumberGenerator) -> void:
	var ta := SA.tangent(cl, k0)
	var na := Vector2(-ta.y, ta.x)
	var tb := SA.tangent(cl, k1)
	var nb := Vector2(-tb.y, tb.x)
	# 土の板（目地の色）
	_vc = Color(0.34, 0.31, 0.24)
	var s0 := cl[k0] + na * uL
	var s1 := cl[k0] + na * uR
	var s2 := cl[k1] + nb * uR
	var s3 := cl[k1] + nb * uL
	_tri_up(sm, Vector3(s0.x, y - 0.025, s0.y), Vector3(s1.x, y - 0.025, s1.y), Vector3(s2.x, y - 0.025, s2.y))
	_tri_up(sm, Vector3(s0.x, y - 0.025, s0.y), Vector3(s2.x, y - 0.025, s2.y), Vector3(s3.x, y - 0.025, s3.y))
	# 框石（前縁：厚く長い、鼻先の丸み大）
	var fwd := -ta
	var kf := k0 + int(round(rng.randf_range(0.35, 0.45) / 0.05))
	var tf := SA.tangent(cl, kf)
	var nf := Vector2(-tf.y, tf.x)
	var pf := cl[k0] + fwd * 0.04
	var top := [Vector3((pf + na * (uL + 0.05)).x, y - 0.01, (pf + na * (uL + 0.05)).y), Vector3((pf + na * (uR - 0.05)).x, y - 0.01, (pf + na * (uR - 0.05)).y),
		Vector3((cl[kf] + nf * (uR - 0.1)).x, y, (cl[kf] + nf * (uR - 0.1)).y), Vector3((cl[kf] + nf * (uL + 0.1)).x, y, (cl[kf] + nf * (uL + 0.1)).y)]
	_block(sm, top, ybot, fwd, 0.08, SA._mul(SA._stone_tone(rng, false), 0.95))
	# 敷石：奥行方向に 2–3 列 × 横 2–3 枚、角を ±5 cm ずらした不整形四角
	var depth := (k1 - kf) * 0.05
	var rows := maxi(1, int(round(depth / rng.randf_range(0.55, 0.8))))
	var kr := [kf + 1]
	for r in range(1, rows):
		kr.append(kf + int(round((k1 - kf) * float(r) / rows)))
	kr.append(k1)
	for r in rows:
		var ka := int(kr[r])
		var kb := int(kr[r + 1])
		var t0 := SA.tangent(cl, ka)
		var n0 := Vector2(-t0.y, t0.x)
		var t1 := SA.tangent(cl, kb)
		var n1 := Vector2(-t1.y, t1.x)
		var ncol := 2 + (1 if rng.randf() < 0.5 else 0)
		var cuts := [uL + 0.08]
		for c in range(1, ncol):
			cuts.append(lerpf(uL, uR, float(c) / ncol + rng.randf_range(-0.08, 0.08)))
		cuts.append(uR - 0.08)
		for c in ncol:
			var u0 := float(cuts[c]) + 0.025
			var u1 := float(cuts[c + 1]) - 0.025
			var j := func() -> float: return rng.randf_range(-0.05, 0.05)
			var pa := cl[ka] + t0 * 0.025
			var pb := cl[kb] - t1 * 0.025
			var yy := y + rng.randf_range(-0.01, 0.008)
			var q := [Vector3((pa + n0 * (u0 + j.call())).x, yy, (pa + n0 * u0).y), Vector3((pa + n0 * (u1 + j.call())).x, yy, (pa + n0 * u1).y),
				Vector3((pb + n1 * (u1 + j.call())).x, yy, (pb + n1 * u1).y), Vector3((pb + n1 * (u0 + j.call())).x, yy, (pb + n1 * u0).y)]
			_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
			_block(sm, q, y - 0.12, fwd, 0.02, SA._stone_tone(rng, c == 0 or c == ncol - 1))


## r8 の StoneSteps から pilot 区間の三角形を除いた mesh（比較用：区間外は r8 のまま）
static func r8_without_range(mesh: ArrayMesh, cl: PackedVector2Array) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tri_n := idx.size() / 3 if idx.size() > 0 else vs.size() / 3
	var keep := PackedInt32Array()
	for t in tri_n:
		var i0 := idx[t * 3] if idx.size() > 0 else t * 3
		var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
		var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
		var c := (vs[i0] + vs[i1] + vs[i2]) / 3.0
		var best := INF
		var bk := 0
		for k in range(0, cl.size(), 4):
			var d := cl[k].distance_squared_to(Vector2(c.x, c.z))
			if d < best:
				best = d
				bk = k
		var s := bk * 0.05
		if s >= S_RANGE.x and s <= S_RANGE.y:
			continue
		keep.append_array(PackedInt32Array([i0, i1, i2]))
	arr[Mesh.ARRAY_INDEX] = keep
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mesh.surface_get_material(0))
	return m
