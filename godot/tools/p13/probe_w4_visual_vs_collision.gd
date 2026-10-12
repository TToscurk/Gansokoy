extends SceneTree
## P13 W4：試作の「見える踏面」と「歩ける面（斜坡碰撞）」のずれの実測（唯讀、headless）。
##   godot --headless --path . --script res://tools/p13/probe_w4_visual_vs_collision.gd
## 測定は tools/p13/w4_walk_surface.gd（verify_w4_pilot.gd と共用）。符号：d = 見える石の上面 − 斜坡碰撞。正＝足が石に沈む／負＝浮く。
## Before＝r8 の StoneSteps（gen/shrine_approach_p10.scn）、After＝区間外の r8（rest_mesh）＋ W4Steps。
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const WS := preload("res://tools/p13/w4_walk_surface.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const R8_SCN := "res://maps/village_v2/gen/shrine_approach_p10.scn"


func _init() -> void:
	_run.call_deferred()


## 見える面の前縁が計画の境界〔踏面 k0〕よりどれだけ前（k の小さい側）へ出ているか（石面が y0 − 6 cm 以上になる最も前の点、0.05 m 刻み）
func _front_protrusion(label: String, ga: WS.TopGrid, cl: PackedVector2Array, plan: Array) -> void:
	var diffs := []
	for c: Dictionary in plan:
		if String(c["kind"]) != "step":
			continue
		var k0 := int(c["k0"])
		var y0 := float(c["y0"])
		for u in [0.0, 0.4, -0.4, 0.8, -0.8]:
			var found := NAN
			for dk in range(0, 6):
				var kk := k0 - dk
				var t := SA.tangent(cl, kk)
				var p: Vector2 = cl[kk] + Vector2(-t.y, t.x) * float(u)
				var top := ga.top_at(p.x, p.y)
				if not is_nan(top) and top >= y0 - 0.06:
					found = float(dk) * 0.05
			if not is_nan(found):
				diffs.append(found)
	diffs.sort()
	if diffs.is_empty():
		return
	var sm := 0.0
	for v in diffs:
		sm += float(v)
	print("[W4X] 前縁の突出 %s（計画の k0 より前へ）n=%d｜平均 %.1f cm・中央値 %.1f・p90 %.1f・最大 %.1f" % [label, diffs.size(), sm / diffs.size() * 100.0, float(diffs[diffs.size() / 2]) * 100.0, float(diffs[int(diffs.size() * 0.9)]) * 100.0, float(diffs[diffs.size() - 1]) * 100.0])


func _plan_dev(label: String, cells: Array, rd: PackedFloat32Array, y_start: float) -> void:
	var yp := y_start
	var n := 0
	var v3 := 0
	var worst := 0.0
	var worst_over := -INF
	var offs := []
	for c: Dictionary in cells:
		if String(c["kind"]) == "step":
			var r := float(c["y0"]) - yp
			var dev := 0.0
			for kk in range(int(c["k0"]), int(c["k1"]) + 1):
				if not is_nan(rd[kk]):
					dev = maxf(dev, absf(rd[kk] - float(c["y0"])))
			n += 1
			worst = maxf(worst, dev)
			worst_over = maxf(worst_over, dev - 0.5 * r)
			if dev - 0.5 * r > 0.03 + 1e-6:
				v3 += 1
			var km := (int(c["k0"]) + int(c["k1"])) / 2
			if not is_nan(rd[km]):
				offs.append(float(c["y0"]) - rd[km])
		yp = float(c["y1"])
	offs.sort()
	var sm := 0.0
	for v in offs:
		sm += float(v)
	print("[W4X] 計画 %s：踏面 %d 段｜最大 |ramp−踏面| %.1f cm｜（|ramp−踏面| − 半蹴上）の最大 %+.1f cm｜既存 SWALK の帯 +3 cm 超え %d 段｜踏面中央の (踏面高 − 斜坡) 平均 %+.1f cm" % [label, n, worst * 100.0, worst_over * 100.0, v3, sm / maxf(offs.size(), 1) * 100.0])


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await physics_frame
		await process_frame
	var ov := v.get_node_or_null(W4.NODE_NAME)
	if ov == null:
		print("[W4X] overlay なし")
		quit(1)
		return
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var rd := W4.ramp_dense(rp, cl.size())
	var rg := W4.pilot_indices(st)
	var kr := W4.pilot_k_range(st)
	var y0 := H[int(st[rg.x]["k0"])]
	var plan_a := W4.replan(cl, H, st, rp)
	_plan_dev("After（試作）", plan_a, rd, y0)
	_plan_dev("Before（r8）", st.slice(rg.x, rg.y + 1), rd, y0)
	var ss := v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D
	print("[W4X] StoneSteps は rest_mesh に差し替え済み：%s" % str(ss.mesh == ov.get("rest_mesh")))
	var gb := WS.TopGrid.new()
	var orig := (load(R8_SCN) as PackedScene).instantiate()
	gb.add_mesh((orig.get_node("StoneSteps") as MeshInstance3D).mesh)
	orig.free()
	var ga := WS.TopGrid.new()
	ga.add_mesh(ss.mesh)
	ga.add_mesh((ov.get_node("W4Steps") as MeshInstance3D).mesh)
	var soil_node := ov.get_node_or_null("W4Soil") as MeshInstance3D
	if soil_node != null and soil_node.mesh != null:
		ga.add_mesh(soil_node.mesh)            # 縫の底〔土〕も見える面（r11 から）
	print("[W4X] 上向き三角形：Before %d・After %d" % [gb.tri.size() / 3, ga.tri.size() / 3])
	_front_protrusion("Before", gb, cl, st.slice(rg.x, rg.y + 1))
	_front_protrusion("After ", ga, cl, plan_a)
	var sp := v.get_world_3d().direct_space_state
	var lats := [0.0, 0.5, -0.5, 0.85, -0.85]
	var res := WS.measure(sp, cl, kr.x + 8, kr.y - 8, lats, [gb, ga])
	print("[W4X] 見える石の上面 − 斜坡碰撞（足の高さ）：正＝足が石に沈む／負＝足が石から浮く｜s=%.1f–%.1f m・0.05 m ごと" % [(kr.x + 8) * 0.05, (kr.y - 8) * 0.05])
	for u in lats:
		var sb := WS.summarize((res[0] as Dictionary)[u])
		var sa := WS.summarize((res[1] as Dictionary)[u])
		print("[W4X] ", WS.fmt("横 %+.2f m  Before" % float(u), sb))
		print("[W4X] ", WS.fmt("横 %+.2f m  After " % float(u), sa))
		print("[W4X]   gate（After が Before の水準内）：%s" % ("OK" if WS.gate_ok(sa, sb) else "NG"))
	# 最悪点の位置（中心線）：どの段・平台のどこで石面が碰撞面から外れるか
	var worst := []
	for k in range(kr.x + 8, kr.y - 8):
		var p: Vector2 = cl[k]
		var yr := WS.ramp_y(sp, p)
		var ya := ga.top_at(p.x, p.y)
		if is_nan(yr) or is_nan(ya):
			continue
		worst.append([ya - yr, k])
	worst.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for i in 6:
		var w: Array = worst[i]
		var kk := int(w[1])
		var where := ""
		for c: Dictionary in plan_a:
			if kk >= int(c["k0"]) and kk <= int(c["k1"]):
				where = "%s s=%.2f–%.2f" % [String(c["kind"]), int(c["k0"]) * 0.05, int(c["k1"]) * 0.05]
		print("[W4X] 最も低い #%d：d=%+.1f cm・s=%.2f｜%s" % [i + 1, float(w[0]) * 100.0, kk * 0.05, where])
	for i in 4:
		var w: Array = worst[worst.size() - 1 - i]
		var kk := int(w[1])
		var where := ""
		for c: Dictionary in plan_a:
			if kk >= int(c["k0"]) and kk <= int(c["k1"]):
				where = "%s s=%.2f–%.2f" % [String(c["kind"]), int(c["k0"]) * 0.05, int(c["k1"]) * 0.05]
		print("[W4X] 最も高い #%d：d=%+.1f cm・s=%.2f｜%s" % [i + 1, float(w[0]) * 100.0, kk * 0.05, where])
	quit(0)
