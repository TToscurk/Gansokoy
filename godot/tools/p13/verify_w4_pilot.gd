extends SceneTree
## P13 Wave 4 参道試作 overlay の gate（headless、唯讀）。
##   godot --headless --path . --script res://tools/p13/verify_w4_pilot.gd
## 守るもの：見える踏面と斜坡碰撞（足の高さ）のずれが r8 と同じ水準〔足が石に沈まない・浮かない〕／碰撞は r8 のまま（Auto-Step 0.35 m・相機・通行は碰撞と玩家コードに依存＝触れていない）／試作の踏面が斜坡碰撞の許容帯に収まる／
## 浮空なし（石垣の底が地形に埋まる）／不規則さが r8 より有意に大きい／巻き順・無碰撞・範囲／scene の生成物が生成器の出力と一致／enabled 切替で r8 に戻る。
## 反向（わざと壊したデータを渡すと gate が落ちる）も同じ関数で確かめる。
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const WS := preload("res://tools/p13/w4_walk_surface.gd")
var fails := 0


func _init() -> void:
	_run.call_deferred()


func _ok(c: bool, msg: String) -> void:
	print("[W4V] %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


## 計画の検査：戻り＝失敗理由の配列
func check_plan(plan: Array, H: PackedFloat32Array, rd: PackedFloat32Array) -> Array:
	var out := []
	var yp := H[int(plan[0]["k0"])]
	var first := true
	for c: Dictionary in plan:
		var kind := String(c["kind"])
		if kind == "step":
			var r := float(c["y0"]) - yp
			var rmin := W4.R_FIRST_MIN if first else W4.R_MIN
			if r < rmin - 1e-3 or r > W4.R_MAX + 1e-3:
				out.append("蹴上 %.3f m が範囲外（s=%.2f）" % [r, int(c["k0"]) * 0.05])
			var k0 := int(c["k0"])
			var k1 := int(c["k1"])
			var yc := SA._hmax(H, k0, k1) + 0.02
			if float(c["y0"]) < yc - 1e-3:
				out.append("踏面が地形に埋まる（中心線）s=%.2f" % (k0 * 0.05))
			var dev := 0.0
			for kk in range(k0, k1 + 1):
				if not is_nan(rd[kk]):
					dev = maxf(dev, absf(rd[kk] - float(c["y0"])))
			if dev > W4.dev_limit(r) + 1e-3:
				out.append("斜坡碰撞との差 %.3f m が許容帯 %.3f m を超える（s=%.2f）" % [dev, W4.dev_limit(r), k0 * 0.05])
			var tl := k1 - k0
			if tl < int(W4.D_K[0]) or tl > int(W4.D_K[W4.D_K.size() - 1]):
				out.append("踏面長 %d が範囲外" % tl)
			first = false
		elif kind == "landing":
			var r2 := float(c["y0"]) - yp
			if r2 < W4.R_MIN - 1e-3 or r2 > W4.R_MAX + 1e-3:
				out.append("踊り場への蹴上 %.3f m が範囲外（s=%.2f）" % [r2, int(c["k0"]) * 0.05])
		yp = float(c["y1"])
	return out


## 描画される三角形数（index があれば index、なければ頂点数／3）
func _tris(m: Mesh) -> int:
	var arr := m.surface_get_arrays(0)
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## 既存 SWALK W1 と同じ帯（|斜坡 − 踏面| ≤ 半蹴上 + 0.03）を超える踏面の数。SWALK は generator の計画〔LIB.steps〕を見る＝overlay の計画は対象外なので、ここで同じ式を適用する
func swalk_viol(plan: Array, H: PackedFloat32Array, rd: PackedFloat32Array) -> int:
	var n := 0
	var yp := H[int(plan[0]["k0"])]
	for c: Dictionary in plan:
		if String(c["kind"]) == "step":
			var r := float(c["y0"]) - yp
			var dev := 0.0
			for kk in range(int(c["k0"]), int(c["k1"]) + 1):
				if not is_nan(rd[kk]):
					dev = maxf(dev, absf(rd[kk] - float(c["y0"])))
			if dev > 0.5 * r + 0.03 + 1e-6:
				n += 1
		yp = float(c["y1"])
	return n


func _cv(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m := 0.0
	for v in a:
		m += float(v)
	m /= a.size()
	var q := 0.0
	for v in a:
		q += (float(v) - m) * (float(v) - m)
	return sqrt(q / a.size()) / maxf(m, 1e-6)


func _risers_treads(plan: Array, y0: float) -> Array:
	var r := []
	var t := []
	var yp := y0
	for c: Dictionary in plan:
		if String(c["kind"]) == "step":
			r.append(float(c["y0"]) - yp)
			t.append((int(c["k1"]) - int(c["k0"])) * 0.05)
		yp = float(c["y1"])
	return [r, t]


func _expected_ramp_faces(cl: PackedVector2Array, st: Array, H: PackedFloat32Array) -> PackedVector3Array:
	var rp := SA.ramp_points(st, H)
	var faces := PackedVector3Array()
	var half := SA.STEP_W * 0.5 + SA.CURB_W
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		var ta := SA.tangent(cl, ka)
		var tb := SA.tangent(cl, kb)
		var na := Vector2(-ta.y, ta.x) * half
		var nb := Vector2(-tb.y, tb.x) * half
		var ya := float(rp[i][1])
		var yb2 := float(rp[i + 1][1])
		var a0 := Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y)
		var a1 := Vector3(cl[ka].x + na.x, ya, cl[ka].y + na.y)
		var b0 := Vector3(cl[kb].x - nb.x, yb2, cl[kb].y - nb.y)
		var b1 := Vector3(cl[kb].x + nb.x, yb2, cl[kb].y + nb.y)
		faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	return faces


func _terr(sp: PhysicsDirectSpaceState3D, p: Vector2) -> float:
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


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 5:
		await physics_frame
	var ov := v.get_node_or_null(W4.NODE_NAME)
	# ── 構造 ──
	_ok(ov != null, "overlay %s が village_v2 に掛かっている" % W4.NODE_NAME)
	if ov == null:
		quit(1)
		return
	_ok(v.get_child(v.get_child_count() - 1) == ov, "root 直下の最後の子（既存 overlay の後ろ）")
	_ok(v.get_children().filter(func(c: Node) -> bool: return c.name == W4.NODE_NAME).size() == 1, "同名の重複なし")
	var cols := ov.find_children("*", "CollisionObject3D", true, false)
	_ok(cols.is_empty(), "overlay は碰撞体を持たない（%d 個）" % cols.size())
	_ok(ov.get("rest_mesh") != null, "rest_mesh（r8 から区間を除いた mesh）が入っている")
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var rd := W4.ramp_dense(rp, cl.size())
	var rg := W4.pilot_indices(st)
	var kr := W4.pilot_k_range(st)
	# ── 碰撞が r8 のまま ──
	var ramp := v.get_node("ShrineApproachP10/RampCollision/Ramp") as CollisionShape3D
	var faces := (ramp.shape as ConcavePolygonShape3D).get_faces()
	var exp_faces := _expected_ramp_faces(cl, st, H)
	var same := faces.size() == exp_faces.size()
	var maxd := 0.0
	if same:
		for i in faces.size():
			maxd = maxf(maxd, faces[i].distance_to(exp_faces[i]))
		same = maxd < 1e-4
	_ok(same, "斜坡碰撞 RampCollision/Ramp が r8 の生成式と一致（三角形 %d・最大差 %.6f m）" % [faces.size() / 3, maxd])
	_ok(not ramp.disabled, "斜坡碰撞は有効のまま")
	# ── 計画 ──
	var plan := W4.replan(cl, H, st, rp)
	var f0 := check_plan(plan, H, rd)
	_ok(f0.is_empty(), "試作計画 %d 要素：蹴上・踏面長・地形・斜坡碰撞との差がすべて許容内%s" % [plan.size(), "" if f0.is_empty() else "（" + str(f0.slice(0, 3)) + "）"])
	var y0 := H[int(st[rg.x]["k0"])]
	var rt := _risers_treads(plan, y0)
	var rt8 := _risers_treads(st.slice(rg.x, rg.y + 1), y0)
	var cvr := _cv(rt[0])
	var cvt := _cv(rt[1])
	var cvr8 := _cv(rt8[0])
	var cvt8 := _cv(rt8[1])
	print("[W4V] INFO 蹴上 変動係数 r8 %.3f → 試作 %.3f／踏面長 r8 %.3f → 試作 %.3f" % [cvr8, cvr, cvt8, cvt])
	_ok(cvr >= 0.12 and cvt >= 0.12, "不規則さ：蹴上・踏面長の変動係数がともに ≥ 0.12（r8 は %.2f／%.2f）" % [cvr8, cvt8])
	_ok(cvr8 < 0.10, "r8 の蹴上は節拍器（変動係数 %.3f < 0.10）＝試作の比較基準" % cvr8)
	# ── 反向（計画） ──
	var bad1: Array = plan.duplicate(true)
	bad1[3]["y0"] = float(bad1[3]["y0"]) - 0.5
	_ok(not check_plan(bad1, H, rd).is_empty(), "反向：踏面を 0.5 m 下げる → 落ちる")
	var bad2: Array = plan.duplicate(true)
	bad2[5]["y0"] = float(bad2[5]["y0"]) + 0.3
	_ok(not check_plan(bad2, H, rd).is_empty(), "反向：蹴上を +0.3 m → 落ちる")
	var rd_bad := rd.duplicate()
	for k in rd_bad.size():
		if not is_nan(rd_bad[k]):
			rd_bad[k] += 0.3
	_ok(not check_plan(plan, H, rd_bad).is_empty(), "反向：斜坡碰撞を 0.3 m ずらす → 許容帯違反で落ちる")
	var bad4: Array = plan.duplicate(true)
	bad4[2]["k1"] = int(bad4[2]["k1"]) + 12
	_ok(not check_plan(bad4, H, rd).is_empty(), "反向：踏面長を 0.6 m 延ばす → 落ちる")
	_ok(_cv(rt8[0]) < 0.12, "反向：r8 の計画は不規則さの gate（≥ 0.12）を満たさない＝gate が弁別する")
	var sv_a := swalk_viol(plan, H, rd)
	var sv_b := swalk_viol(st.slice(rg.x, rg.y + 1), H, rd)
	_ok(sv_a == 0 and sv_b == 0, "既存 SWALK W1 の帯（半蹴上 + 3 cm）を超える踏面：試作 %d 段・r8 %d 段（どちらも 0）" % [sv_a, sv_b])
	var bad5: Array = plan.duplicate(true)
	for ci in range(6, 40):
		if String(bad5[ci]["kind"]) == "step":
			bad5[ci]["y0"] = float(bad5[ci]["y0"]) + 0.06
	_ok(swalk_viol(bad5, H, rd) > 0, "反向：踏面を 6 cm 持ち上げる → SWALK 帯の違反が検出される（%d 段）" % swalk_viol(bad5, H, rd))
	# ── 生成物 ──
	var steps_mi := ov.get_node("W4Steps") as MeshInstance3D
	var soil_mi := ov.get_node_or_null("W4Soil") as MeshInstance3D
	var wb := SA.winding_bad(ov)
	_ok(int(wb[0]) == 0, "表裏：巻き順と法線が逆の三角形 0／%d" % int(wb[1]))
	var old_q := SA.old_winding_quad()
	var wbq := SA.winding_bad(old_q)
	_ok(int(wbq[0]) > 0, "反向：r1–r12 の巻き順の四角 → 表裏検査が落ちる（%d）" % int(wbq[0]))
	old_q.free()
	var arr := steps_mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var tri := vs.size() / 3
	var finite := true
	var out_of_zone := 0
	for p3 in vs:
		if not (is_finite(p3.x) and is_finite(p3.y) and is_finite(p3.z)):
			finite = false
	for i in range(0, vs.size(), 7):
		var best := INF
		for k in range(maxi(kr.x - 40, 0), mini(kr.y + 40, cl.size() - 1) + 1, 3):
			best = minf(best, cl[k].distance_squared_to(Vector2(vs[i].x, vs[i].z)))
		if best > 16.0:
			out_of_zone += 1
	_ok(finite, "頂点がすべて有限")
	_ok(out_of_zone == 0, "W4Steps は中心線から 4 m 以内（区間外へはみ出さない・標本のはみ出し %d）" % out_of_zone)
	_ok(tri <= 60000, "W4Steps %d 三角形 ≤ 60,000（試作区間 27 m の予算）" % tri)
	print("[W4V] INFO W4Steps %d 三角形・W4Soil %d 三角形" % [tri, (soil_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3 if soil_mi else 0])
	# ── 生成物＝生成器の出力 ──
	var sp := v.get_world_3d().direct_space_state
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var lanterns := []
	for ls in SA.lantern_specs(cl, H, st, sp):
		var s_l := float(ls["s"])
		if s_l >= kr.x * 0.05 - 2.0 and s_l <= kr.y * 0.05 + 2.0 and not lanterns.has(s_l):
			lanterns.append(s_l)
	var ms := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	var rebuilt: ArrayMesh = ms["steps"]
	var rv: PackedVector3Array = rebuilt.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mdiff := 0.0
	var same_n := rv.size() == vs.size()
	if same_n:
		for i in rv.size():
			mdiff = maxf(mdiff, rv[i].distance_to(vs[i]))
	_ok(same_n and mdiff < 1e-4, "scene の W4Steps ＝ 生成器の再出力（頂点 %d 個・最大差 %.6f m・generator が source of truth）" % [vs.size(), mdiff])
	# ── 浮空なし：石垣の底が地形に埋まる ──
	var n_blk := 0
	var floating := 0
	var worst := INF
	var exps := []
	for d: Dictionary in W4.diag:
		if float(d["off"]) < 0.06:                       # 笠石（最上段）：頂 − 地形＝その場所の外面の露出高
			var tc := _terr(sp, d["p"])
			if not is_nan(tc):
				exps.append(float(d["top"]) - tc)
	for d: Dictionary in W4.diag:
		if not bool(d.get("base", false)):
			continue          # 上の段の石は下の段の上に載る（地面に埋まる必要があるのは最下段だけ）
		var tv := _terr(sp, d["p"])
		if is_nan(tv):
			continue
		n_blk += 1
		var clear := tv - float(d["ybot"])      # 正＝底が地形より下（埋まっている）
		worst = minf(worst, clear)
		if clear < 0.08:
			floating += 1
	_ok(n_blk > 100 and floating == 0, "浮空なし：地面に接する最下段 %d ブロックの底はすべて地形より ≥ 8 cm 下（最小 %.2f m）" % [n_blk, worst])
	exps.sort()
	var n_lo := exps.filter(func(e: float) -> bool: return e <= 0.30).size()
	var n_mid := exps.filter(func(e: float) -> bool: return e > 0.30 and e <= 0.60).size()
	var n_hi := exps.filter(func(e: float) -> bool: return e > 0.60).size()
	print("[W4V] INFO 笠石 %d 個の外面露出（頂 − 地形）：最大 %.2f m・中央値 %.2f m｜≤ 0.30 m %d／0.30–0.60 m %d／> 0.60 m %d（石垣が必要な高さ）" % [exps.size(), exps[exps.size() - 1], exps[exps.size() / 2], n_lo, n_mid, n_hi])
	var fake := W4.diag.duplicate(true)
	fake[0]["ybot"] = _terr(sp, fake[0]["p"]) + 0.1
	_ok(float(_terr(sp, fake[0]["p"])) - float(fake[0]["ybot"]) < 0.08, "反向：底を地形より 10 cm 上げた記録 → 浮空判定が落ちる")
	# ── 見える面と歩ける面（斜坡碰撞）のずれ：足が石に沈む／浮く（既存 SWALK W1 の穴を埋める：W1 は overlay の見える面を見ない）──
	var ss0 := v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D
	var g_after := WS.TopGrid.new()
	g_after.add_mesh(ss0.mesh)
	g_after.add_mesh(steps_mi.mesh)
	if soil_mi != null and soil_mi.mesh != null:
		g_after.add_mesh(soil_mi.mesh)         # 縫の底〔砂利まじりの土、r11 から W4Soil〕も『見える面』。穿いて低い面を測ると縫の位置で偽の凹みになる
	var g_before := WS.TopGrid.new()
	var orig0 := (load("res://maps/village_v2/gen/shrine_approach_p10.scn") as PackedScene).instantiate()
	g_before.add_mesh((orig0.get_node("StoneSteps") as MeshInstance3D).mesh)
	orig0.free()
	var lats := [0.0, 0.5, -0.5, 0.85, -0.85]
	var meas := WS.measure(sp, cl, kr.x + 8, kr.y - 8, lats, [g_before, g_after])
	var all_ok := true
	var sum_a := {}
	var sum_b := {}
	for u in lats:
		var sb0 := WS.summarize((meas[0] as Dictionary)[u])
		var sa0 := WS.summarize((meas[1] as Dictionary)[u])
		print("[W4V] INFO 横 %+.2f m｜%s｜%s" % [float(u), WS.fmt("After ", sa0), WS.fmt("Before", sb0)])
		if int(sa0["n"]) < 400 or not WS.gate_ok(sa0, sb0):
			all_ok = false
		if float(u) == 0.0:
			sum_a = sa0
			sum_b = sb0
	_ok(all_ok, "見える石の上面 − 斜坡碰撞（5 本の横位置、各約 520 点）が r8 と同じ水準：最大偏差 ≤ r8 + 2 cm・|d|>10 cm の割合 ≤ r8 + 4 pt・>15 cm 0・平均 ±3 cm 以内")
	var d0: Array = (meas[1] as Dictionary)[0.0]
	var d_sink: Array = d0.map(func(x: float) -> float: return x + 0.06)
	_ok(not WS.gate_ok(WS.summarize(d_sink), sum_b), "反向：石面が一様に 6 cm 高い（足が沈む）→ 落ちる")
	var d_scale: Array = d0.map(func(x: float) -> float: return x * 1.7)
	_ok(not WS.gate_ok(WS.summarize(d_scale), sum_b), "反向：ずれを 1.7 倍にする（第 1 版相当の悪化）→ 落ちる")
	var d_float: Array = d0.map(func(x: float) -> float: return x - 0.06)
	_ok(not WS.gate_ok(WS.summarize(d_float), sum_b), "反向：石面が一様に 6 cm 低い（足が浮く）→ 落ちる")
	# ── enabled 切替 ──
	var ss := v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D
	var n_on := _tris(ss.mesh)
	ov.set("enabled", false)
	await process_frame
	await process_frame
	var n_off := _tris(ss.mesh)
	var orig := (load("res://maps/village_v2/gen/shrine_approach_p10.scn") as PackedScene).instantiate()
	var n_r8 := _tris((orig.get_node("StoneSteps") as MeshInstance3D).mesh)
	orig.free()
	_ok(n_off == n_r8, "enabled=false → StoneSteps は r8 の元の mesh に戻る（描画三角形 %d＝%d）" % [n_off, n_r8])
	_ok(not steps_mi.visible, "enabled=false → W4Steps は隠れる")
	_ok(n_on < n_r8, "enabled=true の StoneSteps は試作区間を除いた mesh（描画三角形 %d < r8 %d＝区間分 %d を除去）" % [n_on, n_r8, n_r8 - n_on])
	ov.set("enabled", true)
	await process_frame
	await process_frame
	var n_on2 := _tris(ss.mesh)
	_ok(n_on2 == n_on and steps_mi.visible, "enabled=true に戻すと再び試作（往復で一致）")
	# ── 反向：碰撞体を足すと検出される ──
	var tmp := StaticBody3D.new()
	ov.add_child(tmp)
	_ok(not ov.find_children("*", "CollisionObject3D", true, false).is_empty(), "反向：overlay に碰撞体を足す → 検出される")
	tmp.queue_free()
	print("[W4V] 結果：%d 項失敗" % fails)
	quit(1 if fails > 0 else 0)
