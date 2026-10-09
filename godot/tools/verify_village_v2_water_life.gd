extends SceneTree
## P10 R5b Water Logic Pilot gate（回歸 tag WLF）。使用者 2026-10-09 D5（水車功能）／D10（主河一艘小舟）。
##   plan＋反向（headless，含物理射線）：Godot --headless --path . --script res://tools/verify_village_v2_water_life.gd
##   build（headless 可，無 MultiMesh）：… -- --build
##   attach：… -- --attach        （village_v2.tscn 加 root/WaterLifeP10，GroundPilotP10 之後）
##   scene（非 headless）：… -- --scene
## plan（ROUND 3＝水車 2 純動力）：
##   1 揚水部材なし：build する overlay に LiftBuckets／UkeToi／HeadBent／Pour／Spill／Splash／Spray／ChuteFlow／BucketWater が 0
##   2 水流と回転の向き：P5 RotorAnim を 0.5 s 進めたときの輪の下端の移動方向 · 水渠の下流方向（layout Canal 折線の順）≥ 0.9
##   3 葉板の浸かり：最下端の葉板先端が水面下 0.15–0.8 m、水渠底より ≥ 0.1 m 上
##   4 P8 limited correction（runtime 非表示）：隠すノード／碰撞形が実在し、P8 WaterSupply の「高架（地面＋0.9 m 以上）」の可視部材を全部含み、
##     DropBox 以下（上段土渠・伏越し・木槽・跨ぎ板）を 1 つも含まない
##   5 泡：主の泡＝輪心より下流（+z）・水面＋0.015
##   6 小舟：浮在水位（船底＝水位 − 吃水）、船體與世界碰撞體不相交、船底下水深 ≥ 0.15 m、離最下段石段 ≤ 1.6 m、
##     尺寸＝川舟（長 ≤ 8 m、寬 ≤ 1.8 m）、船首迎流（與流向夾角 ≤ 10°）
##   7 繫船杭：落地（地面差 ≤ 0.05 m、埋 0.35 m）、地上部分不撞其他碰撞體；綱長 ≤ 7 m
##   8 「届いた荷」：落地（≤ 0.05 m）、不撞其他碰撞體
const LIB := preload("res://tools/village_v2_water_life_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p10r5b_water_life"
const AFTER_NODE := "[node name=\"GroundPilotP10\" parent=\".\" instance=ExtResource(\"p10r5a_ground_pilot\")]"
var fails := 0
var quiet := false
var V: Node3D
var hero: Node3D
var excl: Array[RID] = []


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[WLF] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
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
		print("[WLF] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	# 已掛的 WaterLifeP10（重建時）不算世界碰撞
	var old := V.get_node_or_null(LIB.NODE_NAME)
	if old:
		for b in old.find_children("*", "CollisionObject3D", true, false):
			excl.append((b as CollisionObject3D).get_rid())
	hero = V.get_node(LIB.WHEEL) as Node3D
	_wheel_facts()
	var H := _heights()
	print("[WLF] heights ", JSON.stringify(H))
	var cfg := _cfg()
	_gates(cfg, H)
	if "--build" in args:
		_build(H)
	else:
		_negatives(H)
	print("[WLF] 結果：%d 項失敗" % fails)
	quit(fails)


## P5 水車 2 の実測：葉板の角度（Wheel 局部、先端 r ≥ 2.9 の頂点を 1° 単位で束ねる）、輪の材質と頂点色平均
var paddles: Array[float] = []
var wheel_mat := ""
var wheel_vc := 0.0


func _wheel_facts() -> void:
	var m := hero.get_node("Wheel/LOD0") as MeshInstance3D
	var arr := m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bins := {}
	for v0 in vs:
		var p: Vector3 = m.transform * v0
		if Vector2(p.y, p.z).length() >= 2.9:
			bins[int(round(rad_to_deg(atan2(p.z, p.y))))] = true
	var ks := bins.keys()
	ks.sort()
	# 隣り合う 1° ビン（例 −1, 1）は 1 枚の葉板 → 中心角
	var groups := []
	for k in ks:
		if not groups.is_empty() and absf(float(k) - float(groups[groups.size() - 1].back())) <= 2.0:
			groups[groups.size() - 1].append(k)
		else:
			groups.append([k])
	if groups.size() > 1 and float(groups[0][0]) <= -178.0 and float(groups[groups.size() - 1].back()) >= 178.0:
		groups[0].append_array(groups.pop_back().map(func(x): return x - 360))
	paddles.clear()
	for gp in groups:
		var sm := 0.0
		for x in gp:
			sm += float(x)
		paddles.append(sm / gp.size())
	var mat := m.get_active_material(0)
	wheel_mat = mat.resource_path if mat else ""
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var sum := 0.0
	for c in cs:
		sum += c.get_luminance()
	wheel_vc = sum / maxf(1.0, cs.size())
	print("[WLF] wheel facts: paddles %d %s、材質 %s、頂点色平均 %.3f" % [paddles.size(), str(paddles.map(func(a): return snappedf(a, 0.5))), wheel_mat.get_file(), wheel_vc])


func _cfg() -> Dictionary:
	return {"lift_parts": 0, "rot_sign": 1.0, "hub_dy": 0.0, "hide_vis": LIB.P8_HIDE_VIS.duplicate(), "hide_col": LIB.P8_HIDE_COL.duplicate(), "foam_dz": 0.0,
		"boat_off": LIB.BOAT_OFF, "boat_l": LIB.BOAT_L, "boat_b": LIB.BOAT_B, "post_dy": 0.0}


func _ray_y(p: Vector2, from_y := 40.0) -> float:
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, from_y, p.y), Vector3(p.x, -30.0, p.y))
	q.exclude = excl
	var h := sp.intersect_ray(q)
	return NAN if h.is_empty() else float(h["position"].y)


func _hits(xf: Transform3D, size: Vector3) -> Array:
	var sp := V.get_world_3d().direct_space_state
	var bs := BoxShape3D.new()
	bs.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bs
	q.transform = xf
	q.exclude = excl
	var out := []
	for r in sp.intersect_shape(q, 16):
		out.append(String(V.get_path_to(r["collider"])) if r["collider"] is Node and V.is_ancestor_of(r["collider"]) else str(r["collider"]))
	return out


func _heights() -> Dictionary:
	var hx := hero.global_transform
	var ms := LIB.mooring_specs(0.0)
	var pp: Vector2 = ms["post"]
	var best := {}
	for kg: Vector2 in LIB.kago_candidates():
		var ys := []
		for c in LIB.kago_corners(kg, ms["down"]):
			ys.append(_ray_y(c))
		if ys.any(func(y): return is_nan(float(y))):
			continue
		var spread: float = ys.max() - ys.min()
		var hh := _hits(Transform3D(Basis(), Vector3(kg.x, float(ys.max()) + 0.48, kg.y)), Vector3(1.2, 0.6, 0.75))
		if not hh.is_empty():
			continue
		if best.is_empty() or spread < float(best["kago_spread"]):
			best = {"kago_p": kg, "kago_ground": float(ys.max()) - 0.02, "kago_spread": spread}
	# 水車 2：水渠水面（P2 水面網格、輪心 4 m 內頂點の平均、Hero 局部）・輪の真下の水渠底（Hero 碰撞を除外）
	var hub_w := hx * LIB.HUB
	var wys := []
	var wnode := V.get_node_or_null("Water")
	if wnode:
		for mi in wnode.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			var gab := m3.global_transform * m3.mesh.get_aabb()
			if hub_w.x < gab.position.x - 4.0 or hub_w.x > gab.end.x + 4.0 or hub_w.z < gab.position.z - 4.0 or hub_w.z > gab.end.z + 4.0:
				continue
			var vs: PackedVector3Array = m3.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v0 in vs:
				var w: Vector3 = m3.global_transform * v0
				if Vector2(w.x - hub_w.x, w.z - hub_w.z).length() < 4.0:
					wys.append(w.y - hx.origin.y)
	var wy := NAN
	if not wys.is_empty():
		var sum := 0.0
		for y in wys:
			sum += float(y)
		wy = sum / wys.size()
	var hex: Array[RID] = excl.duplicate()
	for co in hero.find_children("*", "CollisionObject3D", true, false):
		hex.append((co as CollisionObject3D).get_rid())
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(hub_w + Vector3(0, 6, 0), hub_w + Vector3(0, -20, 0))
	q.exclude = hex
	var hb := sp.intersect_ray(q)
	var out := {"post_ground": _ray_y(pp), "water_y": wy, "water_n": wys.size(),
		"bed_wheel": (float(hb["position"].y) - hx.origin.y) if not hb.is_empty() else NAN}
	out.merge(best)
	# 水渠の下流方向（layout Canal 折線の順＝取水口→南）：輪心に最も近い区間
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var cp: Array = L["water"]["Canal"]["pts"]
	var hub2 := Vector2(hub_w.x, hub_w.z)
	var bd := INF
	var flow := Vector2.ZERO
	for i in cp.size() - 1:
		var a := Vector2(float(cp[i][0]), float(cp[i][1]))
		var b := Vector2(float(cp[i + 1][0]), float(cp[i + 1][1]))
		var d := hub2.distance_to(Geometry2D.get_closest_point_to_segment(hub2, a, b))
		if d < bd:
			bd = d
			flow = (b - a).normalized()
	out["flow"] = flow
	# 輪の回転：P5 RotorAnim を seek して、輪の下端（葉板先端）の点が 0.5 s でどちらへ動くか
	var rotor := V.get_node(LIB.ROTOR) as Node3D
	var ap: AnimationPlayer = null
	for c in hero.get_children():
		if c is AnimationPlayer:
			ap = c
	var dvec := Vector3.ZERO
	if ap:
		var an: String = String(ap.current_animation) if String(ap.current_animation) != "" else String(ap.get_animation_list()[0])
		ap.play(an)
		ap.seek(0.0, true)
		var r0 := rotor.global_transform
		var bot := hx * (LIB.HUB + Vector3(0, -LIB.PADDLE_R, 0))
		var loc := r0.affine_inverse() * bot
		ap.seek(0.5, true)
		dvec = rotor.global_transform * loc - bot
		out["anim"] = an
	out["bottom_move"] = dvec
	out["bottom_dot"] = Vector2(dvec.x, dvec.z).normalized().dot(flow) if Vector2(dvec.x, dvec.z).length() > 1e-4 else 0.0
	# P8 WaterSupply の可視部材：地面より 0.9 m 以上高い（高架）もの
	var sup := V.get_node_or_null(LIB.P8_SUPPLY)
	var elevated := []
	if sup:
		for c in sup.get_children():
			var top_off := -INF
			for mi in ([c] if c is MeshInstance3D else []) + c.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				var ab := m.global_transform * m.mesh.get_aabb()
				var cc := ab.get_center()
				var gy := _ray_y(Vector2(cc.x, cc.z))
				if not is_nan(gy):
					top_off = maxf(top_off, ab.position.y - gy)
			if top_off >= 0.9:
				elevated.append(String(c.name))
	out["p8_elevated"] = elevated
	out["p8_children"] = sup.get_children().map(func(n): return String(n.name)) if sup else []
	var colb := V.get_node_or_null(LIB.P8_COL)
	out["p8_shapes"] = colb.get_children().map(func(n): return String(n.name)) if colb else []
	# build した overlay の揚水部材数（メモリ上）
	var tmp := LIB.build(V, out)
	var n_lift := 0
	for nm in LIB.LIFT_PARTS:
		n_lift += tmp.find_children(nm, "", true, false).size()
	out["lift_parts"] = n_lift
	tmp.free()
	return out


func _gates(cfg: Dictionary, H: Dictionary) -> void:
	# 1 揚水部材なし
	var nl := int(H["lift_parts"]) + int(cfg["lift_parts"])
	_ok(nl == 0, "動力水車：overlay に揚水部材（柄杓・受け樋・架台・注ぎ・樋の流れ）%d 件" % nl)
	# 2 水流と回転の向き
	var dot := float(H["bottom_dot"]) * float(cfg["rot_sign"])
	var flow: Vector2 = H["flow"]
	_ok(dot >= 0.9, "回転の向き：輪の下端（葉板先端）の動き · 水渠の下流方向 (%.3f, %.3f) ＝ %.3f（≥ 0.9＝流れが葉板を押す下掛け；RotorAnim %s）" % [flow.x, flow.y, dot, str(H.get("anim", "?"))])
	# 3 葉板の浸かり
	var tip := LIB.HUB.y + float(cfg["hub_dy"]) - LIB.PADDLE_R
	var wy := float(H["water_y"])
	var bedw := float(H["bed_wheel"])
	var imm := wy - tip
	_ok(not is_nan(wy) and not is_nan(bedw) and imm >= float(LIB.IMMERSE[0]) and imm <= float(LIB.IMMERSE[1]) and tip - bedw >= 0.1,
		"葉板の浸かり：先端 %.2f（Hero 局部）、水面 %.2f → %.2f m（%.2f–%.2f）、水渠底 %.2f より %.2f m 上" % [tip, wy, imm, float(LIB.IMMERSE[0]), float(LIB.IMMERSE[1]), bedw, tip - bedw])
	# 4 P8 limited correction
	var hv: Array = cfg["hide_vis"]
	var hc: Array = cfg["hide_col"]
	var kids: Array = H["p8_children"]
	var shapes: Array = H["p8_shapes"]
	var missing := hv.filter(func(n): return not kids.has(n)) + hc.filter(func(n): return not shapes.has(n))
	var not_hidden := (H["p8_elevated"] as Array).filter(func(n): return not hv.has(n))
	var keep_hit := LIB.P8_KEEP.filter(func(n): return hv.has(n) or hc.has(n))
	_ok(missing.is_empty() and not_hidden.is_empty() and keep_hit.is_empty() and kids.size() > 0,
		"P8 水車 2 落とし樋（runtime 非表示）：可視 %d／碰撞 %d、P8 WaterSupply の高架部材 %s が全部対象（漏れ %s）、実在しない名 %s、DropBox 以下を含む %s"
		% [hv.size(), hc.size(), str(H["p8_elevated"]), str(not_hidden), str(missing), str(keep_hit)])
	# 5 泡
	var fs: Array = LIB.foam_specs(wy if not is_nan(wy) else 0.0)
	var f0: Vector3 = (fs[0]["c"] as Vector3) + Vector3(0, 0, float(cfg["foam_dz"]))
	_ok(f0.z > 0.8 and absf(f0.y - (wy + 0.015)) < 0.01, "泡：主の泡は輪心より下流 z %+.2f（葉板が水から出る側）、水面＋0.015" % f0.z)
	# 4 小舟
	var bxf := LIB.boat_xf(float(cfg["boat_off"]))
	var hull_c := bxf * Vector3(0, LIB.BOAT_H * 0.5 + 0.03, -0.2)
	var hits := _hits(Transform3D(bxf.basis, hull_c), Vector3(float(cfg["boat_b"]) - 0.1, LIB.BOAT_H - 0.06, float(cfg["boat_l"]) - 0.6))
	var bot := bxf.origin
	var bed_y := _ray_y(Vector2(bot.x, bot.z), bot.y + 0.05)
	var depth := bot.y - bed_y if not is_nan(bed_y) else INF
	var stair := Vector2(LIB.STAIR_BOT.x, LIB.STAIR_BOT.z)
	var near := stair.distance_to(Vector2(bot.x, bot.z)) - float(cfg["boat_b"]) * 0.5
	var fwd := bxf.basis.z
	var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(-LIB.FLOW))
	var float_ok := absf((bot.y + LIB.BOAT_DRAFT) - LIB.RIVER_WATER) < 0.005
	_ok(float_ok and hits.is_empty() and depth >= 0.15 and near <= 1.6 and float(cfg["boat_l"]) <= 8.0 and float(cfg["boat_b"]) <= 1.8 and absf(ang) <= 10.0,
		"小舟 %.1f×%.1f m：吃水 %.2f、船體碰撞 %s、船底下水深 %.2f m、離石段 %.2f m、船首與迎流夾角 %.1f°" % [float(cfg["boat_l"]), float(cfg["boat_b"]), LIB.BOAT_DRAFT, str(hits) if not hits.is_empty() else "0", depth, near, ang])
	# 5 繫船杭＋綱
	var ms := LIB.mooring_specs(float(H["post_ground"]))
	var pp: Vector2 = ms["post"]
	var pg := float(H["post_ground"]) + float(cfg["post_dy"])
	var g_here := _ray_y(pp)
	var ph := _hits(Transform3D(Basis(), Vector3(pp.x, pg + 0.55, pp.y)), Vector3(0.13, 0.8, 0.13))
	var rope_len := (ms["bow"] as Vector3).distance_to(Vector3(pp.x, pg + 0.78, pp.y))
	_ok(not is_nan(g_here) and absf(pg - g_here) <= 0.05 and ph.is_empty() and rope_len <= 7.0, "繫船杭：地面差 %.3f m、地上部碰撞 %s、綱長 %.2f m" % [pg - g_here, str(ph) if not ph.is_empty() else "0", rope_len])
	# 6 届いた荷
	var kg: Vector2 = H.get("kago_p", ms["kago"])
	var kgy := float(H.get("kago_ground", NAN))
	var g2 := _ray_y(kg)
	var spread := float(H.get("kago_spread", 0.0))
	var kh := _hits(Transform3D(Basis(), Vector3(kg.x, kgy + 0.18 + 0.30, kg.y)), Vector3(1.2, 0.6, 0.75))
	_ok(not is_nan(g2) and kgy - g2 <= 0.15 and kgy - g2 >= -0.05 and spread <= 0.15 and kh.is_empty(), "届いた荷（st_kago_tsumi 重用）：放在四角最高點 −0.02（中心地面差 %.3f、四角起伏 %.3f ≤ 0.15）、地上部碰撞 %s" % [kgy - g2, spread, str(kh) if not kh.is_empty() else "0"])


func _negatives(H: Dictionary) -> void:
	print("[WLF] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	var c1 := _cfg()
	c1["lift_parts"] = 1
	cases.append(["N1 揚水部材が残る（柄杓 1）", c1, H])
	var c2 := _cfg()
	c2["rot_sign"] = -1.0
	cases.append(["N2 輪が流れに逆らって回る", c2, H])
	var c3 := _cfg()
	c3["hub_dy"] = 0.6
	cases.append(["N3 葉板が水に届かない（輪を 0.6 m 上げる）", c3, H])
	var c4 := _cfg()
	c4["boat_off"] = -0.6
	cases.append(["N4 小舟壓上石段", c4, H])
	var c5 := _cfg()
	c5["boat_l"] = 14.0
	c5["boat_b"] = 3.0
	cases.append(["N5 船過大（14 × 3 m，港口船）", c5, H])
	var c6 := _cfg()
	c6["post_dy"] = 0.5
	cases.append(["N6 繫船杭浮空 0.5 m", c6, H])
	var c7 := _cfg()
	c7["hide_vis"] = LIB.P8_HIDE_VIS.filter(func(n): return n != "Chute_0")
	cases.append(["N7 高架落とし樋の一部（Chute_0）が残る", c7, H])
	var c8 := _cfg()
	c8["hide_vis"] = LIB.P8_HIDE_VIS + ["DropBox"]
	cases.append(["N8 DropBox まで隠す（P8 の範囲を越える）", c8, H])
	var c9 := _cfg()
	c9["foam_dz"] = -4.0
	cases.append(["N9 主の泡が上流側", c9, H])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(c[1], c[2])
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[WLF]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _build(H: Dictionary) -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build(V, H)
	for c in n.find_children("*", "", true, false):
		c.owner = n
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var nlift := 0
	for nm in LIB.LIFT_PARTS:
		nlift += rb.find_children(nm, "", true, false).size()
	_ok(nlift == 0 and rb.get_node_or_null("WW2_Power/WaterFX/Foam") != null and rb.get_node_or_null("BoatLanding/Boat/Hull") != null, "回讀：揚水部材 %d、泡 %s、小舟 %s" % [nlift, rb.get_node_or_null("WW2_Power/WaterFX/Foam") != null, rb.get_node_or_null("BoatLanding/Boat/Hull") != null])
	# ROUND 2：表裏（明示法線＝Godot の表）＋反向（r1–r12 の巻き順の四角は必ず検出）
	var wb := LIB.winding_bad(rb)
	var neg := LIB.old_winding_quad()
	var wn := LIB.winding_bad(neg)
	neg.free()
	_ok(int(wb[0]) == 0 and int(wb[1]) > 50 and int(wn[0]) == 2, "表裏：明示法線と表（時計回り）が逆の三角形 %d／%d（反向：r1–r12 の巻き順の四角 → 検出 %d／2）" % [int(wb[0]), int(wb[1]), int(wn[0])])
	rb.free()
	n.free()
	print("[WLF] build {\"output_sha256\":\"%s\"}" % FileAccess.get_sha256(LIB.OUTPUT))


func _scene() -> void:
	var nodes := V.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var gp := V.get_node_or_null("GroundPilotP10")
	_ok(gp != null and gp.get_index() == n.get_index() - 1, "順序：GroundPilotP10 之後（index %d）" % n.get_index())
	for i in 4:
		await process_frame
	var rotor := V.get_node(LIB.ROTOR) as Node3D
	var nlift := 0
	for nm in LIB.LIFT_PARTS:
		nlift += n.find_children(nm, "", true, false).size() + rotor.find_children(nm, "", true, false).size()
	_ok(nlift == 0, "動力水車：overlay・轉子に揚水部材 %d 件" % nlift)
	# 輪は回り、下端は下流へ（runtime）
	var hx := (V.get_node(LIB.WHEEL) as Node3D).global_transform
	var bot := hx * (LIB.HUB + Vector3(0, -LIB.PADDLE_R, 0))
	var loc := rotor.global_transform.affine_inverse() * bot
	for i in 30:
		await process_frame
	await create_timer(0.5).timeout
	var dv := rotor.global_transform * loc - bot
	var flow3 := hx.basis.z.normalized()
	_ok(dv.length() > 0.05 and Vector2(dv.x, dv.z).normalized().dot(Vector2(flow3.x, flow3.z)) >= 0.9, "輪が回り、下端は下流へ（移動 %.2f m、· 下流 %.3f）" % [dv.length(), Vector2(dv.x, dv.z).normalized().dot(Vector2(flow3.x, flow3.z))])
	# 水車 1／3 不動（揚水部材なし）
	for w in ["Landmarks/LANDMARK_WATERWHEEL_1/Hero/Wheel", "Landmarks/LANDMARK_WATERWHEEL_3/Hero/Wheel"]:
		var r := V.get_node_or_null(w)
		var nl2 := 0
		if r:
			for nm in LIB.LIFT_PARTS:
				nl2 += r.find_children(nm, "", true, false).size()
		_ok(r != null and nl2 == 0, "%s 不動（揚水部材 %d）" % [w.split("/")[1], nl2])
	# P8 limited correction：隠す対象だけ隠れ、DropBox 以下は表示・碰撞のまま
	var sup := V.get_node(LIB.P8_SUPPLY)
	var colb := V.get_node(LIB.P8_COL)
	var vis_bad := []
	for nm in LIB.P8_HIDE_VIS:
		if (sup.get_node(nm) as Node3D).visible:
			vis_bad.append(nm)
	for nm in LIB.P8_HIDE_COL:
		if not (colb.get_node(nm) as CollisionShape3D).disabled:
			vis_bad.append("col " + nm)
	for nm in LIB.P8_KEEP:
		var k := sup.get_node_or_null(nm) as Node3D
		if k and not k.visible:
			vis_bad.append("keep " + nm)
		var ks := colb.get_node_or_null(nm) as CollisionShape3D
		if ks and ks.disabled:
			vis_bad.append("keep col " + nm)
	_ok(vis_bad.is_empty() and int(n.get("p8_hidden")) == LIB.P8_HIDE_VIS.size() + LIB.P8_HIDE_COL.size(), "P8 水車 2 落とし樋：可視 %d・碰撞 %d を runtime 停止、DropBox 以下は不変%s" % [LIB.P8_HIDE_VIS.size(), LIB.P8_HIDE_COL.size(), "" if vis_bad.is_empty() else " ✗ " + str(vis_bad)])
	# 開關
	n.set("enabled", false)
	var hidden := true
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible:
			hidden = false
	var back := int(n.get("p8_hidden")) == 0
	for nm in LIB.P8_HIDE_VIS:
		if not (sup.get_node(nm) as Node3D).visible:
			back = false
	for nm in LIB.P8_HIDE_COL:
		if (colb.get_node(nm) as CollisionShape3D).disabled:
			back = false
	_ok(hidden and back, "enabled=false → overlay 全隱藏、P8 落とし樋は元どおり表示・碰撞（%s）" % back)
	n.set("enabled", true)
	_ok(not (sup.get_node("Chute_0") as Node3D).visible, "enabled=true → 再び非表示")
	# 碰撞體：舟 1＋杭 1
	var cols := n.find_children("*", "CollisionShape3D", true, false).size()
	_ok(cols == 2, "碰撞形 %d（舟 1、杭 1）" % cols)


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[WLF] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/GroundPilotP10")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("GroundPilotP10 節點後面不是空行，拒絕文字插入")
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
	print("[WLF] attach：加 root/%s（GroundPilotP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0
