extends SceneTree
## P10 R5a ROUND 2 Road Base Regeneration Pilot gate（回歸 tag RDB）。使用者 2026-10-09 ROUND 2 §3（D3 CONDITIONAL）。
##   plan＋反向（headless，物理射線）：Godot --headless --path . --script res://tools/verify_village_v2_road_base.gd
##   build：… -- --build（plan 全過才寫 gen/road_base_p10.scn；元の road_*.res の sha256 を build 前後で照合）
##   attach：… -- --attach（village_v2.tscn に root/RoadBaseP10、PropFixP10 之後）
##   scene（非 headless）：… -- --scene
## plan：
##   1 小範囲：対象＝ROADS の 3 本だけ、再生した長さ合計 ≤ 450 m
##   2 元の路幅の中：新しい頂点の折線からの横距離 ≤ 元の半幅（P8 田・P9 地被・P6 店先の取り決めを越えない）
##   3 地形なり：芯（|u| ≤ 0.66）＝地形＋0.02–0.07、縁（|u|＝1）＝地形 −0.03–0.0（境目 8 m を除く）；元の帯の浮き（参考）も出力
##   4 定規の直線でない：半幅の最大／最小 ≥ 1.12、蛇行 ≥ 0.12 m（南橫街 ≥ 0.2）、縁線の横ぶれ標準偏差 ≥ 0.04 m
##   5 元の網格が切れている所（水の上）は切れたまま：新網格の s 区間 ⊆ 元の s 区間
##   6 南橫街の境目：町の区間の三角形＝元のまま（數・頂点 ≤ 1 mm）、境目の行＝元の左右頂点（≤ 1 cm）
##   7 交差点の上下：FarmPath_1 − FarmPath_4 ≥ 0.012、CrossStreetSouth − FarmPath_1 ≥ 0.012（同じ高さの重なり＝ちらつき防止）
##   8 NPC：再生道の近く（元の半幅＋1 m）の NPC は地形の上（|足−地形| ≤ 0.05）、新しい路面との差 ≤ 0.08（元の帯は 0.10 埋まる）
##   9 元の road_*.res は不変（sha256 を build 前後で照合）
##   T（ROUND 3：P7 地形の踩み固め重みの局部修正）：変える頂点＝対象 3 本の旧い帯が支配する頂点だけ（ほかの道・水辺・建物の塗りは不変）、
##     COLOR.r 以外（位置・法線・UV・UV2・索引・COLOR.gba）は完全一致、旧い帯（trodden ≥ 0.3 相当の頂点）が 0.6 倍以下に細る、
##     terrain_farmlandterrain.res は不変
const LIB := preload("res://tools/village_v2_road_base_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p10r5a_road_base"
const AFTER_NODE := "[node name=\"PropFixP10\" parent=\".\" instance=ExtResource(\"p10r4c_prop_fix\")]"
const RS := preload("res://tools/village_v2_rehab_seal.gd")
const SEAL := "res://data/village_v2_p10r5a_seal.json"   # 使用者 2026-10-09 ROUND 3 FINAL：R5a Road Base 416 m Pilot＝ART_APPROVED
var fails := 0
var quiet := false
var V: Node3D


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[RDB] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if RS.refuse_write(args, SEAL, "RDB_ALLOW_REBAKE", "RDB"):
		quit(1)
		return
	if "--seal" in args:
		quit(await RS.new().run(self, SEAL, "RDB", LIB.NODE_NAME, _seal_extra))
		return
	if "--attach" in args:
		quit(_attach())
		return
	V = (load(SCENE) as PackedScene).instantiate()
	root.add_child(V)
	await process_frame
	await physics_frame
	await physics_frame
	if "--scene" in args:
		await _scene()
		print("[RDB] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	# 既に掛かっていたら元の mesh で計画する
	var old := V.get_node_or_null(LIB.NODE_NAME)
	if old:
		old.call("apply", false)
	var src_sha := _src_sha()
	var plans := {}
	for k in LIB.ROADS:
		plans[k] = LIB.plan_road(V, k, LIB.ROADS[k])
	_gates(plans)
	_terrain_gates(LIB.terrain_fix(V, plans), {})
	if "--build" in args:
		_build(src_sha)
	else:
		_negatives(plans)
	print("[RDB] 結果：%d 項失敗" % fails)
	quit(fails)


func _src_sha() -> Dictionary:
	var out := {}
	for k in LIB.ROADS.keys() + [LIB.TERRAIN_NODE]:
		var mi := V.get_node(k) as MeshInstance3D
		out[k] = [mi.mesh.resource_path, FileAccess.get_sha256(mi.mesh.resource_path)]
	return out


func _seg_d(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


func _gates(plans: Dictionary, quiet_detail := false) -> void:
	var sp := V.get_world_3d().direct_space_state
	# 1 小範囲
	var total := 0.0
	for k in plans:
		var rows: Array = plans[k]["rows"]
		if rows.size() > 1:
			total += float(rows[rows.size() - 1]["s"]) - float(rows[0]["s"])
	_ok(plans.size() == 3 and total <= 450.0, "小範囲：再生 %d 本（FarmPath_1／FarmPath_4／南橫街の田の区間）、長さ合計 %.0f m（≤ 450）" % [plans.size(), total])
	# 2–4, 6
	var bad2 := []
	var bad3 := []
	var bad4 := []
	var bad6 := []
	var stats := []
	for k in plans:
		var pl: Dictionary = plans[k]
		var cfg: Dictionary = LIB.ROADS[k]
		var lr := LIB.layout_road(String(cfg["name"]))
		var hw0 := float(pl["hw0"])
		var seam := float(pl["seam_s"])
		var hmin := INF
		var hmax := 0.0
		var omax := 0.0
		var edge_d := []
		var core_lo := INF
		var core_hi := -INF
		var edge_lo := INF
		var edge_hi := -INF
		var old_float := []
		for r: Dictionary in pl["rows"]:
			var s := float(r["s"])
			var pts: Array = r["pts"]
			for ui in pts.size():
				var q: Vector3 = pts[ui]
				var d := _seg_d(Vector2(q.x, q.z), lr["pts"])
				if d > hw0 + 0.01:
					bad2.append("%s s %.0f u %.2f 離折線 %.2f" % [cfg["name"], s, float(LIB.US[ui]), d])
				if seam >= 0.0 and s < seam + LIB.SEAM_BLEND:
					continue
				var ty := LIB.terrain_y(sp, q.x, q.z)
				var dy := q.y - ty
				var u := absf(float(LIB.US[ui]))
				if u <= 0.66:
					core_lo = minf(core_lo, dy)
					core_hi = maxf(core_hi, dy)
				elif u >= 0.999:
					edge_lo = minf(edge_lo, dy)
					edge_hi = maxf(edge_hi, dy)
			if seam >= 0.0 and s < seam + LIB.SEAM_BLEND:
				continue
			hmin = minf(hmin, float(r["hw"]))
			hmax = maxf(hmax, float(r["hw"]))
			omax = maxf(omax, absf(float(r["off"])))
			var lpt: Vector3 = pts[pts.size() - 1]
			edge_d.append(_seg_d(Vector2(lpt.x, lpt.z), lr["pts"]))
		if core_lo < 0.02 or core_hi > 0.07 or edge_lo < -0.03 or edge_hi > 0.0:
			bad3.append("%s 芯 %+.3f〜%+.3f／縁 %+.3f〜%+.3f" % [cfg["name"], core_lo, core_hi, edge_lo, edge_hi])
		var mean := 0.0
		for e in edge_d:
			mean += float(e)
		mean /= maxf(1.0, edge_d.size())
		var sd := 0.0
		for e in edge_d:
			sd += (float(e) - mean) * (float(e) - mean)
		sd = sqrt(sd / maxf(1.0, edge_d.size()))
		var need_o := 0.2 if String(cfg["name"]) == "CrossStreetSouth" else 0.12
		if hmax / maxf(hmin, 0.01) < 1.12 or omax < need_o or sd < 0.04:
			bad4.append("%s 半幅 %.2f–%.2f（比 %.2f）蛇行 %.2f 縁ぶれ σ %.3f" % [cfg["name"], hmin, hmax, hmax / maxf(hmin, 0.01), omax, sd])
		# 元の帯の浮き（参考）：元の網格の頂点 − 地形
		var mi := V.get_node(k) as MeshInstance3D
		var ovs: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var of_sum := 0.0
		var of_max := 0.0
		var of_n := 0
		for i in range(0, ovs.size(), 9):
			var w: Vector3 = mi.global_transform * ovs[i]
			if seam >= 0.0 and w.x < float(cfg["seam_x"]):
				continue
			var ty2 := LIB.terrain_y(sp, w.x, w.z)
			if not is_nan(ty2):
				of_sum += w.y - ty2
				of_max = maxf(of_max, w.y - ty2)
				of_n += 1
		stats.append("%s：元の帯 地形＋%.3f（最大 %.3f）→ 新 芯 %+.3f〜%+.3f・縁 %+.3f〜%+.3f、半幅 %.2f→%.2f–%.2f、蛇行 ≤ %.2f" % [cfg["name"], of_sum / maxf(1, of_n), of_max, core_lo, core_hi, edge_lo, edge_hi, hw0, hmin, hmax, omax])
		# 6 境目
		if seam >= 0.0:
			var oi := LIB.orig_info(mi.mesh as ArrayMesh)
			var ovs2: PackedVector3Array = oi["vs"]
			var ouv: PackedVector2Array = oi["uv"]
			var n_keep := 0
			for tt in ovs2.size() / 3:
				var ok := true
				for kk in 3:
					if ouv[tt * 3 + kk].y > seam + 0.001:
						ok = false
				if ok:
					n_keep += 1
			var keep: Array = pl["keep"]
			var maxd := 0.0
			for tt in mini(keep.size(), 200):
				for kk in 3:
					var kv: Vector3 = keep[tt][0][kk]
					var best := INF
					for i in ovs2.size():
						best = minf(best, kv.distance_to(ovs2[i]))
						if best < 0.0005:
							break
					maxd = maxf(maxd, best)
			var row0: Dictionary = (pl["rows"] as Array)[0]
			var inv: Transform3D = pl["inv"]
			var p0: Vector3 = inv * (row0["pts"][0] as Vector3)
			var p6: Vector3 = inv * (row0["pts"][6] as Vector3)
			var dl := INF
			var dr := INF
			for i in ovs2.size():
				if absf(ouv[i].y - seam) < 0.01:
					dl = minf(dl, p6.distance_to(ovs2[i]))
					dr = minf(dr, p0.distance_to(ovs2[i]))
			if keep.size() != n_keep or maxd > 0.001 or dl > 0.01 or dr > 0.01:
				bad6.append("%s 町の三角形 %d／%d、頂点差 %.4f、境目 左 %.3f 右 %.3f" % [cfg["name"], keep.size(), n_keep, maxd, dl, dr])
			elif not quiet:
				print("[RDB]   境目 %s：町の区間の三角形 %d＝元のまま（頂点差 %.4f m）、境目の行＝元の左右頂点（%.3f／%.3f m）" % [cfg["name"], keep.size(), maxd, dl, dr])
	if not quiet:
		for s in stats:
			print("[RDB]   ", s)
	_ok(bad2.is_empty(), "元の路幅の中（横距離 ≤ 元の半幅）%s" % ("" if bad2.is_empty() else " ✗ " + str(bad2.slice(0, 4))))
	_ok(bad3.is_empty(), "地形なり：芯＝地形＋0.02–0.07、縁＝地形 −0.03–0.00（元の帯は＋0.10 の平板）%s" % ("" if bad3.is_empty() else " ✗ " + str(bad3)))
	_ok(bad4.is_empty(), "定規の直線でない：半幅比 ≥ 1.12、蛇行 ≥ 0.12（南橫街 0.2）、縁ぶれ σ ≥ 0.04%s" % ("" if bad4.is_empty() else " ✗ " + str(bad4)))
	_ok(bad6.is_empty(), "南橫街の境目：町の区間は元の三角形のまま、境目の行＝元の左右頂点%s" % ("" if bad6.is_empty() else " ✗ " + str(bad6)))
	# 5 切れ目（水の上）
	var bad5 := []
	for k in plans:
		var pl: Dictionary = plans[k]
		var m := LIB.make_mesh(pl)
		var oi := LIB.orig_info(m)
		var orig_cover: Array = LIB.orig_info((V.get_node(k) as MeshInstance3D).mesh as ArrayMesh)["cover"]
		for c in oi["cover"]:
			if not LIB.covered(orig_cover, float(c[0]), float(c[1])):
				bad5.append("%s 新 %.1f–%.1f ⊄ 元" % [LIB.ROADS[k]["name"], float(c[0]), float(c[1])])
		if not quiet:
			print("[RDB]   %s：元の区間 %s → 新 %s" % [LIB.ROADS[k]["name"], str((pl["cover"] as Array).map(func(c): return "%.0f–%.0f" % [c[0], c[1]])), str((oi["cover"] as Array).map(func(c): return "%.0f–%.0f" % [c[0], c[1]]))])
	_ok(bad5.is_empty(), "元の網格の切れ目（水の上＝橋）は切れたまま%s" % ("" if bad5.is_empty() else " ✗ " + str(bad5)))
	# 7 交差点の上下
	var f1 := float(plans["Roads/FarmPaths/FarmPath_1"]["lift"])
	var f4 := float(plans["Roads/FarmPaths/FarmPath_4"]["lift"])
	var cs := float(plans["Roads/SecondaryRoads/CrossStreetSouth"]["lift"])
	_ok(f1 - f4 >= 0.012 and cs - f1 >= 0.012, "交差点の上下：FarmPath_1 %.3f − FarmPath_4 %.3f ≥ 0.012、南橫街 %.3f − FarmPath_1 ≥ 0.012" % [f1, f4, cs])
	# 8 NPC
	var bad8 := []
	var n8 := 0
	var pop := V.get_node_or_null("Population")
	if pop:
		for b in pop.find_children("*", "AnimatableBody3D", true, false):
			var np := (b as Node3D).global_position
			for k in plans:
				var cfg: Dictionary = LIB.ROADS[k]
				var lr := LIB.layout_road(String(cfg["name"]))
				if _seg_d(Vector2(np.x, np.z), lr["pts"]) > float(lr["half_w"]) + 1.0:
					continue
				n8 += 1
				var ty := LIB.terrain_y(sp, np.x, np.z)
				var surf := ty + float(plans[k]["lift"])
				if absf(np.y - ty) > 0.05 or surf - np.y > 0.08:
					bad8.append("%s 足 %.2f 地形 %.2f 新路面 %.2f" % [b.name, np.y, ty, surf])
	_ok(bad8.is_empty(), "NPC：再生道の近く %d 人は地形の上・新しい路面との差 ≤ 0.08（NPC 不搬）%s" % [n8, "" if bad8.is_empty() else " ✗ " + str(bad8.slice(0, 4))])


func _terrain_gates(tf: Dictionary, inj: Dictionary) -> void:
	var mi := V.get_node(LIB.TERRAIN_NODE) as MeshInstance3D
	var a0 := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var a1 := (tf["mesh"] as ArrayMesh).surface_get_arrays(0)
	var v1: PackedVector3Array = a1[Mesh.ARRAY_VERTEX]
	if bool(inj.get("move", false)):
		v1 = v1.duplicate()
		v1[100] = v1[100] + Vector3(0, 0.05, 0)
	var diffs := []
	for e in [["VERTEX", v1, a0[Mesh.ARRAY_VERTEX]], ["NORMAL", a1[Mesh.ARRAY_NORMAL], a0[Mesh.ARRAY_NORMAL]], ["UV", a1[Mesh.ARRAY_TEX_UV], a0[Mesh.ARRAY_TEX_UV]],
			["UV2", a1[Mesh.ARRAY_TEX_UV2], a0[Mesh.ARRAY_TEX_UV2]], ["INDEX", a1[Mesh.ARRAY_INDEX], a0[Mesh.ARRAY_INDEX]], ["TANGENT", a1[Mesh.ARRAY_TANGENT], a0[Mesh.ARRAY_TANGENT]]]:
		if e[1] != e[2]:
			var md := -1.0
			if e[1] != null and e[2] != null and e[1].size() == e[2].size() and (e[1] is PackedVector3Array or e[1] is PackedVector2Array or e[1] is PackedFloat32Array):
				md = 0.0
				for i in e[1].size():
					var dd = e[1][i] - e[2][i]
					md = maxf(md, absf(dd) if dd is float else (dd as Variant).length())
			# 法線・接線は元と同じ圧縮フラグで再量子化される分（≤ 1e-3）だけ許す；位置・UV・索引は完全一致
			if e[0] in ["NORMAL", "TANGENT"] and md >= 0.0 and md <= 1e-3:
				continue
			diffs.append("%s %s" % [e[0], ("max %.6f" % md) if md >= 0.0 else "size/型"])
	var same: bool = diffs.is_empty()
	var c0: PackedColorArray = a0[Mesh.ARRAY_COLOR]
	var c1: PackedColorArray = a1[Mesh.ARRAY_COLOR]
	var gba_bad := 0
	var nchg := 0
	for i in c0.size():
		if not is_equal_approx(c0[i].g, c1[i].g) or not is_equal_approx(c0[i].b, c1[i].b) or not is_equal_approx(c0[i].a, c1[i].a):
			gba_bad += 1
		if absf(c0[i].r - c1[i].r) > 1e-4:
			nchg += 1
	var ch: PackedInt32Array = tf["changed"]
	_ok(same and gba_bad == 0 and nchg == ch.size() and ch.size() > 0, "T1 地形 %s：頂点 %d のうち COLOR.r だけ %d 個を変更（予定 %d）（位置・UV・UV2・索引 完全一致／法線・接線 ≤ 1e-3（圧縮の再量子化）%s%s、COLOR.gba の差 %d）" % [LIB.TERRAIN_NODE, int(tf["verts"]), nchg, ch.size(), same, "" if same else " ✗ " + str(diffs), gba_bad])
	_ok(int(tf["mismatch"]) == 0, "T2 変えた頂点はすべて「対象 3 本の旧い帯が支配」（tr0＝0.85·max(対象, ほか) ±%.2f、対象 ＞ ほか）：外れ %d" % [LIB.MATCH_TOL, int(tf["mismatch"])])
	var bo := int(tf["band_old"])
	var bn := int(tf["band_new"])
	_ok(bo > 0 and float(bn) <= 0.6 * bo, "T3 旧い路寬の帯（踩み固め ≥ 0.3 相当の頂点）%d → 再生道の帯 %d（≤ 0.6 倍）、最大変化 %.2f" % [bo, bn, float(tf["max_delta"])])


func _negatives(plans: Dictionary) -> void:
	print("[RDB] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	var c1 := plans.duplicate()
	c1["Roads/FarmPaths/FarmPath_4"] = LIB.plan_road(V, "Roads/FarmPaths/FarmPath_4", LIB.ROADS["Roads/FarmPaths/FarmPath_4"], {"lift": 0.10})
	cases.append(["N1 元の浮き（地形＋0.10 の平板）", c1])
	var c2 := plans.duplicate()
	c2["Roads/FarmPaths/FarmPath_1"] = LIB.plan_road(V, "Roads/FarmPaths/FarmPath_1", LIB.ROADS["Roads/FarmPaths/FarmPath_1"], {"hw_k": [1.06, 1.15]})
	cases.append(["N2 元の路幅を越える（P8 田・P9 地被に食い込む）", c2])
	var c3 := plans.duplicate()
	c3["Roads/FarmPaths/FarmPath_4"] = LIB.plan_road(V, "Roads/FarmPaths/FarmPath_4", LIB.ROADS["Roads/FarmPaths/FarmPath_4"], {"meander": 0.0, "hw_k": [0.9, 0.9]})
	cases.append(["N3 定規の直線・幅一定（ROUND 1 の帯）", c3])
	var c4 := plans.duplicate()
	var css := "Roads/SecondaryRoads/CrossStreetSouth"
	var cfg4: Dictionary = (LIB.ROADS[css] as Dictionary).duplicate()
	cfg4["seam_x"] = 300.0   # 境目を橋より西へ → 再生区間が水の上（元の切れ目 144–158 m）を含む
	var p4: Dictionary = LIB.plan_road(V, css, cfg4).duplicate()
	p4["cover"] = [[-1.0, 1.0e9]]   # 元の切れ目を無視して全部敷く
	c4[css] = p4
	cases.append(["N4 元に無い切れ目を跨ぐ（水の上に道を敷く相当）", c4])
	var c5 := plans.duplicate()
	c5["Roads/FarmPaths/FarmPath_1"] = LIB.plan_road(V, "Roads/FarmPaths/FarmPath_1", LIB.ROADS["Roads/FarmPaths/FarmPath_1"], {"lift": 0.03})
	cases.append(["N5 交差点で FarmPath_1 と FarmPath_4 が同じ高さ（ちらつき）", c5])
	var neg_fail := 0
	# ROUND 3：地形の重みの反向
	var tcases := [["N6 判定を緩める（ほかの道・水辺の塗りまで書き換える）", {"tol": 1.0}], ["N7 頂点を 1 つ動かす（位置は不変のはず）", {"move": true}]]
	for c in tcases:
		var f1 := fails
		quiet = true
		_terrain_gates(LIB.terrain_fix(V, plans, float(c[1].get("tol", LIB.MATCH_TOL))), c[1])
		quiet = false
		var tr := fails > f1
		fails = f1
		print("[RDB]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tr else "FAIL（gate 沒抓到）"])
		if not tr:
			neg_fail += 1
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(c[1])
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[RDB]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() + 2 - neg_fail, cases.size() + 2])


func _build(src_sha: Dictionary) -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build(V)
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var ms: Array = rb.get("road_meshes")
	var nt := 0
	for m in ms:
		nt += (m as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	_ok(ms.size() == 4 and nt > 1000, "回讀：再生 mesh %d（道 3＋地形 1）、三角形 %d" % [ms.size(), nt])
	var after := _src_sha()
	var same := true
	for k in src_sha:
		if src_sha[k][1] != after[k][1]:
			same = false
	_ok(same, "元の road_*.res・terrain_farmlandterrain.res は不変（sha256 build 前後一致）：%s" % str(after.values().map(func(x): return "%s %s" % [String(x[0]).get_file(), String(x[1]).substr(0, 12)])))
	rb.free()
	n.free()
	print("[RDB] build {\"output_sha256\":\"%s\"}" % FileAccess.get_sha256(LIB.OUTPUT))


func _scene() -> void:
	var nodes := V.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0]
	var pf := V.get_node_or_null("PropFixP10")
	_ok(pf != null and pf.get_index() == n.get_index() - 1, "順序：PropFixP10 之後（index %d）" % n.get_index())
	for i in 4:
		await process_frame
	var gp := V.get_node_or_null("GroundPilotP10")
	var bad := []
	for k in LIB.ROADS:
		var mi := V.get_node(k) as MeshInstance3D
		if mi.mesh == null or not String(mi.mesh.resource_name).begins_with("RoadBase_"):
			bad.append("%s mesh %s" % [LIB.ROADS[k]["name"], mi.mesh.resource_name if mi.mesh else "null"])
		var m := mi.material_override as ShaderMaterial
		if m == null or not m.shader.resource_path.ends_with("ground_p10_pilot.gdshader"):
			bad.append("%s 材質が pilot shader でない" % LIB.ROADS[k]["name"])
	var tmi := V.get_node(LIB.TERRAIN_NODE) as MeshInstance3D
	if tmi.mesh == null or String(tmi.mesh.resource_name) != "RoadBase_FarmlandTerrain":
		bad.append("地形 mesh %s" % (tmi.mesh.resource_name if tmi.mesh else "null"))
	_ok(bad.is_empty() and int(n.get("applied")) == 4 and gp != null, "再生 mesh 3 本＋地形 1 が差し替わり、道の材質は GroundPilotP10 の pilot shader のまま%s" % ("" if bad.is_empty() else " ✗ " + str(bad)))
	# 道に碰撞なし（差し替えは見た目だけ）
	var nc := 0
	for k in LIB.ROADS:
		nc += V.get_node(k).find_children("*", "CollisionObject3D", true, false).size()
	_ok(nc == 0, "対象の道に碰撞なし（差し替えは見た目だけ、歩行＝P1 地形碰撞）")
	# P9 地被・立ち草：元の路幅の中で、新しい路面より外側（露出した地形）に浮いた株がないか（非 headless で MultiMesh を読む）
	var floating := 0
	var near := 0
	var sp := V.get_world_3d().direct_space_state
	for grp in ["Vegetation/GroundcoverP9", "Vegetation/MeadowP9"]:
		var g := V.get_node_or_null(grp)
		if g == null:
			continue
		for mm in g.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := mm as MultiMeshInstance3D
			if mmi.multimesh == null:
				continue
			var gab := mmi.global_transform * mmi.get_aabb()
			if gab.end.x < 330 or gab.position.x > 560 or gab.end.z < -40 or gab.position.z > 140:
				continue
			for i in mmi.multimesh.instance_count:
				var w: Vector3 = mmi.global_transform * mmi.multimesh.get_instance_transform(i).origin
				for k in LIB.ROADS:
					var lr := LIB.layout_road(String(LIB.ROADS[k]["name"]))
					if _seg_d(Vector2(w.x, w.z), lr["pts"]) > float(lr["half_w"]):
						continue
					near += 1
					var ty := LIB.terrain_y(sp, w.x, w.z)
					if w.y - ty > 0.06:
						floating += 1
	_ok(floating == 0, "P9 地被・立ち草：元の路幅の中の株 %d、地形から 6 cm 以上浮く株 %d（元の帯の上に置かれた株があれば浮く）" % [near, floating])
	# 開關
	var orig_paths := []
	n.set("enabled", false)
	var back := true
	for k in LIB.ROADS:
		var mi := V.get_node(k) as MeshInstance3D
		if mi.mesh == null or String(mi.mesh.resource_name).begins_with("RoadBase_") or not mi.mesh.resource_path.begins_with("res://maps/village_v2/gen/road_"):
			back = false
		orig_paths.append(mi.mesh.resource_path.get_file() if mi.mesh else "null")
	var tm2 := V.get_node(LIB.TERRAIN_NODE) as MeshInstance3D
	if not tm2.mesh.resource_path.ends_with("terrain_farmlandterrain.res"):
		back = false
	_ok(back and int(n.get("applied")) == 0, "enabled=false → 元の mesh（道 3＋地形）に戻る（%s、地形 %s）" % [str(orig_paths), tm2.mesh.resource_path.get_file()])
	n.set("enabled", true)
	_ok(int(n.get("applied")) == 4, "enabled=true → 重新套用")


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[RDB] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/PropFixP10")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("PropFixP10 節點後面不是空行，拒絕文字插入")
		return 1
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [LIB.OUTPUT, EXT_ID])
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[RDB] attach：加 root/%s（PropFixP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


## --seal 固有：再現性＝現在の生成器（lib）で記憶體内に再生成した道 3 本＋地形（COLOR.r 局部修正）が、封存した overlay の mesh と配列一致
## （頂点・法線・UV・UV2・索引・COLOR；地形は COLOR.r の変更頂点数も）。元の road_*.res／terrain_farmlandterrain.res は不変（frozen の sha）。
func _seal_extra(v: Node3D) -> Array:
	V = v
	var n := v.get_node(LIB.NODE_NAME)
	var baked_paths: PackedStringArray = n.get("road_paths")
	var baked: Array = n.get("road_meshes")
	n.call("apply", false)
	await physics_frame
	await physics_frame
	var plans := {}
	for k in LIB.ROADS:
		plans[k] = LIB.plan_road(v, k, LIB.ROADS[k])
	var fresh := {}
	for k in LIB.ROADS:
		fresh[k] = LIB.make_mesh(plans[k])
	var tf := LIB.terrain_fix(v, plans)
	fresh[LIB.TERRAIN_NODE] = tf["mesh"]
	var bad := []
	for i in baked_paths.size():
		var key := String(baked_paths[i])
		if not fresh.has(key):
			bad.append("%s 生成器に無い" % key)
			continue
		var a := (baked[i] as ArrayMesh).surface_get_arrays(0)
		var b := (fresh[key] as ArrayMesh).surface_get_arrays(0)
		for ai in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX, Mesh.ARRAY_COLOR]:
			if a[ai] != b[ai]:
				bad.append("%s array %d" % [key.get_file(), ai])
	n.call("apply", true)
	await physics_frame
	var nchg := (tf["changed"] as PackedInt32Array).size()
	return [[bad.is_empty() and baked_paths.size() == 4, "再現性：生成器で記憶體内に再生成した道 3 本＋地形 FarmlandTerrain が封存 overlay の mesh と配列一致（%d 本、不一致 %s）" % [baked_paths.size(), str(bad.slice(0, 4))]],
		[nchg == 577, "地形 COLOR.r の局部修正 %d 頂点（＝ART_APPROVED 時の 577）" % nchg],
		[int(n.get("applied")) == 4, "RoadBaseP10 再適用 %d（道 3＋地形 1）" % int(n.get("applied"))]]
