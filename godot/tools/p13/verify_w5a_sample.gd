extends SceneTree
## P13 Wave 5A の局所 gate（headless、唯讀）。サンプル s=58.95–64.20 m の石垣と土坡の融合が「非破壊・範囲内・接地・覆いすぎなし」を守ること。
##   godot --headless --path . --script res://tools/p13/verify_w5a_sample.gd
## 守るもの：
##   G1 範囲：W5A が除いた旧 W4B の三角形・足した三角形がすべて s=58.95–64.20 m の中〔土坡の下端側は 1.0 m のテーパーまで〕。区間外の幾何は 1 三角形も変わらない
##   G2 接地：土坡の上向きの面の頂点が地形から −6 cm〜+62 cm の範囲〔地中に沈まない・空中に浮かない〕。草叢・根石も地面から離れない
##   G3 覆いすぎなし：土の盛り高さ／壁の露出量 ≤ MAX_COVER（石垣を覆う土壁にしない）
##   G4 燈籠：足した石の頂点は燈籠の ±0.5 m で中心線から 1.62 m 以内〔内縁 1.61 m〕
##   G5 最下段の石の底は地形より ≥ 8 cm 下（浮空なし）
##   G6 表裏・碰撞：overlay の巻き順不正 0・碰撞体 0・scene の W4Steps／W4Soil＝生成器の再出力
## 反向（わざと壊したデータを同じ関数に渡すと落ちる）も確かめる。
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const W5 := preload("res://tools/village_v2_sando_w5a_lib.gd")
const S_LO := 58.95
const S_HI := 64.20
var fails := 0
var cl: PackedVector2Array
var sp: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _ok(c: bool, msg: String) -> void:
	print("[W5G] %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _k(v: Vector3) -> String:
	return "%d,%d,%d" % [int(round(v.x * 1000.0)), int(round(v.y * 1000.0)), int(round(v.z * 1000.0))]


## mesh → {key: [a,b,c]}（頂点の丸め座標を並べ替えた key＝同じ三角形かどうかの判定）
func _tris(mesh: Mesh) -> Dictionary:
	var out := {}
	if mesh == null:
		return out
	var vs: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, vs.size() - 2, 3):
		var ks := [_k(vs[i]), _k(vs[i + 1]), _k(vs[i + 2])]
		ks.sort()
		out["|".join(ks)] = [vs[i], vs[i + 1], vs[i + 2]]
	return out


func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if not b.has(k):
			out[k] = a[k]
	return out


## 中心線上の最も近い点の s〔m〕と、そこからの水平距離〔m〕
func _s_lat(p: Vector3) -> Vector2:
	var best := INF
	var bk := 0
	for k in range(1000, 1420):
		var d := cl[k].distance_squared_to(Vector2(p.x, p.z))
		if d < best:
			best = d
			bk = k
	return Vector2(bk * 0.05, sqrt(best))


func _terr(p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
	var ex: Array[RID] = []
	for t in 12:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


# ── 検査関数（反向でも同じものを使う）──
func _scope_bad(tris: Dictionary, lo: float, hi: float) -> int:
	var bad := 0
	for key in tris:
		var t: Array = tris[key]
		var c: Vector3 = ((t[0] as Vector3) + (t[1] as Vector3) + (t[2] as Vector3)) / 3.0
		var r := _s_lat(c)
		if r.x < lo or r.x > hi or r.y > 4.5:
			bad += 1
	return bad


func _ground_bad(tris: Dictionary, dy_lo: float, dy_hi: float) -> int:
	var bad := 0
	for key in tris:
		var t: Array = tris[key]
		var n := ((t[2] as Vector3) - (t[0] as Vector3)).cross((t[1] as Vector3) - (t[0] as Vector3))
		if n.length() < 1e-9 or n.normalized().y < 0.5:
			continue                                   # 垂直の裏打ち〔地中まで届く〕は対象外
		for v: Vector3 in t:
			var th := _terr(Vector2(v.x, v.z))
			if is_nan(th):
				continue
			var dy: float = v.y - th
			if dy < dy_lo or dy > dy_hi:
				bad += 1
				break
	return bad


func _lantern_bad(tris: Dictionary, lanterns: Array, lim: float) -> int:
	var bad := 0
	for key in tris:
		for v: Vector3 in (tris[key] as Array):
			var r := _s_lat(v)
			for ls in lanterns:
				if absf(r.x - float(ls)) < 0.5 and r.y > lim:
					bad += 1
					break
	return bad


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await physics_frame
		await process_frame
	cl = SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var kr := W4.pilot_k_range(st)
	var plan := W4.replan(cl, H, st, rp)
	sp = v.get_world_3d().direct_space_state
	W5.setup(v, sp, cl)
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var lanterns := []
	for ls in SA.lantern_specs(cl, H, st, sp):
		var s_l := float(ls["s"])
		if s_l >= kr.x * 0.05 - 2.0 and s_l <= kr.y * 0.05 + 2.0 and not lanterns.has(s_l):
			lanterns.append(s_l)
	W4.flags = {"w5a": false}
	var off := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	W4.flags = {}
	var off_steps := _tris(off["steps"])
	var off_soil := _tris(off["soil"])
	var on := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	var on_steps := _tris(on["steps"])
	var on_soil := _tris(on["soil"])
	var diag := W4.diag.duplicate(true)
	var plants := W5.plants.duplicate(true)
	var stats := W5.stats.duplicate(true)
	print("[W5G] INFO W4B 石 %d・土 %d 三角形 → W5A 石 %d・土 %d 三角形｜草叢 %d" % [off_steps.size(), off_soil.size(), on_steps.size(), on_soil.size(), plants.size()])
	# ── G1 範囲 ──
	var rm_steps := _diff(off_steps, on_steps)
	var ad_steps := _diff(on_steps, off_steps)
	var rm_soil := _diff(off_soil, on_soil)
	var ad_soil := _diff(on_soil, off_soil)
	print("[W5G] INFO 除いた W4B の三角形：石 %d・土 %d｜足した W5A の三角形：石 %d・土 %d" % [rm_steps.size(), rm_soil.size(), ad_steps.size(), ad_soil.size()])
	_ok(rm_steps.size() > 0 and ad_steps.size() > 0, "W5A が実際に石垣を差し替えている（除いた %d・足した %d）" % [rm_steps.size(), ad_steps.size()])
	_ok(_scope_bad(rm_steps, S_LO - 0.1, S_HI + 0.1) == 0, "G1 除いた旧石垣の三角形 %d 個はすべて s=%.2f–%.2f m の中" % [rm_steps.size(), S_LO, S_HI])
	_ok(_scope_bad(ad_steps, S_LO - 0.1, S_HI + 0.1) == 0, "G1 足した石の三角形 %d 個はすべて s=%.2f–%.2f m の中（s=64.2 m より先へ出ない）" % [ad_steps.size(), S_LO, S_HI])
	_ok(_scope_bad(rm_soil, S_LO - 0.1, S_HI + 0.1) == 0, "G1 除いた旧い土の裾の三角形 %d 個は範囲内" % rm_soil.size())
	_ok(_scope_bad(ad_soil, S_LO - 1.1, S_HI + 0.1) == 0, "G1 足した土坡の三角形 %d 個は s=%.2f–%.2f m〔下端側は 1.0 m のテーパー〕の中" % [ad_soil.size(), S_LO - 1.0, S_HI])
	# ── G2 接地 ──
	var gb := _ground_bad(ad_soil, -0.06, 0.62)
	_ok(gb == 0, "G2 土坡の上向きの面の頂点は地形から −6 cm〜+62 cm（地中に沈まない・空中に浮かない）：違反 %d" % gb)
	var pl_bad := 0
	var pl_min := INF
	var pl_max := -INF
	for it: Dictionary in plants:
		var th := _terr(Vector2((it["p"] as Vector3).x, (it["p"] as Vector3).z))
		var dy: float = (it["p"] as Vector3).y - th
		pl_min = minf(pl_min, dy)
		pl_max = maxf(pl_max, dy)
		if dy < -0.12 or dy > 0.45:
			pl_bad += 1
	_ok(pl_bad == 0, "G2 草叢 %d 株は地面〔土坡の上〕に据わる（地面との差 %.2f〜%.2f m）" % [plants.size(), pl_min, pl_max])
	# ── G3 覆いすぎなし ──
	var cmax := 0.0
	for sd in stats:
		cmax = maxf(cmax, float((stats[sd]["stats"] as Dictionary).get("cover_max", 0.0)))
	_ok(cmax <= W5.MAX_COVER + 0.01, "G3 土の盛り高さ／壁の露出量の最大 %.2f ≤ %.2f（石垣を覆う土壁にしない）" % [cmax, W5.MAX_COVER])
	# ── G4 燈籠 ──
	_ok(_lantern_bad(ad_steps, lanterns, 1.62) == 0, "G4 燈籠 %s の ±0.5 m では、足した石の頂点が中心線から 1.62 m 以内（燈籠の内縁 1.61 m）" % str(lanterns))
	# ── G5 浮空なし ──
	var nb := 0
	var worst := INF
	var fl := 0
	for d: Dictionary in diag:
		if not bool(d.get("base", false)):
			continue
		var tv := _terr(d["p"])
		if is_nan(tv):
			continue
		nb += 1
		var clear: float = tv - float(d["ybot"])
		worst = minf(worst, clear)
		if clear < 0.08:
			fl += 1
			if fl <= 6:
				var rr := _s_lat(Vector3((d["p"] as Vector2).x, 0.0, (d["p"] as Vector2).y))
				print("[W5G] INFO 浮空の疑い #%d：s=%.2f 側 %+.0f 中心線から %.2f m｜地形 %.3f・底 %.3f・差 %.3f m" % [fl, rr.x, float(d["sd"]), rr.y, tv, float(d["ybot"]), clear])
	_ok(nb >= 20 and fl == 0, "G5 地面に接する最下段の石 %d 個の底はすべて地形より ≥ 8 cm 下（最小 %.2f m）" % [nb, worst])
	# ── G6 表裏・碰撞・scene ──
	var ov := v.get_node_or_null(W4.NODE_NAME)
	_ok(ov != null, "overlay が掛載されている")
	if ov != null:
		var wb := SA.winding_bad(ov)
		_ok(int(wb[0]) == 0, "G6 巻き順不正の三角形 0／%d" % int(wb[1]))
		_ok(ov.find_children("*", "CollisionObject3D", true, false).is_empty(), "G6 overlay は碰撞体を持たない〔斜坡碰撞・Auto-Step・相機・通行は W4B のまま〕")
		var sv: PackedVector3Array = ((ov.get_node("W4Steps") as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var rv: PackedVector3Array = (on["steps"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var md := 0.0
		var same := sv.size() == rv.size()
		if same:
			for i in sv.size():
				md = maxf(md, sv[i].distance_to(rv[i]))
		_ok(same and md < 1e-4, "G6 scene の W4Steps ＝ 生成器の再出力（頂点 %d・最大差 %.6f m）" % [sv.size(), md])
		var sv2: PackedVector3Array = ((ov.get_node("W4Soil") as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var rv2: PackedVector3Array = (on["soil"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var md2 := 0.0
		var same2 := sv2.size() == rv2.size()
		if same2:
			for i in sv2.size():
				md2 = maxf(md2, sv2[i].distance_to(rv2[i]))
		_ok(same2 and md2 < 1e-4, "G6 scene の W4Soil ＝ 生成器の再出力（頂点 %d・最大差 %.6f m）" % [sv2.size(), md2])
		var pn := ov.get_node_or_null("W5Plants")
		_ok(pn != null and pn.get_child_count() == plants.size(), "G6 草叢ノード %d 個＝生成器の記録 %d 株" % [pn.get_child_count() if pn != null else 0, plants.size()])
	# ── 反向（壊したデータで必ず落ちる）──
	print("[W5G] 反向")
	var f1 := ad_steps.duplicate(true)
	var k0 = f1.keys()[0]
	var t0: Array = f1[k0]
	var far := Vector3(cl[1500].x, (t0[0] as Vector3).y, cl[1500].y)           # s=75 m の点
	f1["fake"] = [far, far + Vector3(0.1, 0, 0), far + Vector3(0, 0.1, 0)]
	_ok(_scope_bad(f1, S_LO - 0.1, S_HI + 0.1) > 0, "N1 s=75 m に三角形を 1 つ足す → 範囲 gate が落ちる")
	var f2 := ad_soil.duplicate(true)
	var sk = f2.keys()[0]
	var st2: Array = f2[sk]
	var th0 := _terr(Vector2((st2[0] as Vector3).x, (st2[0] as Vector3).z))
	# 上向きの三角形を地形の 20 cm 下へ沈める
	var sunk := {}
	for key in f2:
		var tt: Array = f2[key]
		var nn := ((tt[2] as Vector3) - (tt[0] as Vector3)).cross((tt[1] as Vector3) - (tt[0] as Vector3))
		if nn.length() > 1e-9 and nn.normalized().y > 0.5:
			sunk["s"] = [(tt[0] as Vector3) - Vector3(0, 0.45, 0), (tt[1] as Vector3) - Vector3(0, 0.45, 0), (tt[2] as Vector3) - Vector3(0, 0.45, 0)]
			break
	_ok(_ground_bad(sunk, -0.06, 0.62) > 0, "N2 土坡の面を地形の 45 cm 下へ沈める → 接地 gate が落ちる")
	var fl2 := {}
	for key in f2:
		var tt2: Array = f2[key]
		var nn2 := ((tt2[2] as Vector3) - (tt2[0] as Vector3)).cross((tt2[1] as Vector3) - (tt2[0] as Vector3))
		if nn2.length() > 1e-9 and nn2.normalized().y > 0.5:
			fl2["f"] = [(tt2[0] as Vector3) + Vector3(0, 1.2, 0), (tt2[1] as Vector3) + Vector3(0, 1.2, 0), (tt2[2] as Vector3) + Vector3(0, 1.2, 0)]
			break
	_ok(_ground_bad(fl2, -0.06, 0.62) > 0, "N3 土坡の面を地形の 1.2 m 上へ浮かせる → 接地 gate が落ちる")
	_ok(0.80 > W5.MAX_COVER + 0.01, "N4 盛り高さ／露出量 0.80（土壁）→ 覆いすぎ gate が落ちる")
	var f5 := {}
	var lp := 61.7
	for ls2 in lanterns:
		if float(ls2) > 55.0 and float(ls2) < 66.0:
			lp = float(ls2)                                     # サンプル区間の中の燈籠
	var kl := int(round(lp / 0.05))
	var tl := SA.tangent(cl, kl)
	var pl := cl[kl] + Vector2(-tl.y, tl.x) * 1.95
	var pv := Vector3(pl.x, 10.0, pl.y)
	f5["f"] = [pv, pv + Vector3(0.05, 0, 0), pv + Vector3(0, 0.05, 0)]
	_ok(_lantern_bad(f5, lanterns, 1.62) > 0, "N5 燈籠の脇〔中心線から 1.95 m〕に石を置く → 燈籠 gate が落ちる")
	print("[W5G] 結果：%d 項失敗" % fails)
	quit(1 if fails > 0 else 0)
