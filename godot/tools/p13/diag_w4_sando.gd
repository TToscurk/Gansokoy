extends SceneTree
## P13 Wave 4：r8 參道の「規則度」診断（唯讀、headless 可）。
##   godot --headless --path . --script res://tools/p13/diag_w4_sando.gd
## 出力：(1) 中心線の主要位置（s→x,z,y）(2) 石段計畫（kind 別段數）(3) 蹴上／踏面の離散度・隣との相関 (4) 正式 overlay の石段メッシュから、
##   踏面の端（横方向）の直線度・段ごとの鼻先の前後ずれ（メッシュ実測）。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	var s := 0.0
	for v in a:
		s += float(v)
	var m := s / a.size()
	var q := 0.0
	var lo := INF
	var hi := -INF
	for v in a:
		q += (float(v) - m) * (float(v) - m)
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var sd := sqrt(q / a.size())
	return {"n": a.size(), "mean": m, "sd": sd, "cv": sd / maxf(m, 1e-9), "min": lo, "max": hi}


func _lag1(a: Array) -> float:
	if a.size() < 3:
		return 0.0
	var st := _stats(a)
	var m: float = st["mean"]
	var num := 0.0
	var den := 0.0
	for i in a.size():
		den += (float(a[i]) - m) * (float(a[i]) - m)
		if i > 0:
			num += (float(a[i]) - m) * (float(a[i - 1]) - m)
	return num / maxf(den, 1e-9)


func _fmt(d: Dictionary, k := 100.0, unit := "cm") -> String:
	if int(d["n"]) == 0:
		return "n=0"
	return "n=%d 平均 %.1f %s・標準偏差 %.1f %s・変動係数 %.1f %%・範囲 %.1f–%.1f %s" % [d["n"], float(d["mean"]) * k, unit, float(d["sd"]) * k, unit, float(d["cv"]) * 100.0, float(d["min"]) * k, float(d["max"]) * k, unit]


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	for i in 4:
		await physics_frame
	var sa := v.get_node(SA.NODE_NAME)
	var ramp := sa.get_node("RampCollision/Ramp") as CollisionShape3D
	var cl := SA.centerline()
	ramp.disabled = true
	await physics_frame
	await physics_frame
	var H := SA.ramp_profile(v, cl)
	ramp.disabled = false
	var st := SA.steps(cl, H)
	print("[W4D] 中心線 %d 点（0.05 m 間隔）＝全長 %.1f m・石段計畫 %d 件" % [cl.size(), (cl.size() - 1) * 0.05, st.size()])
	for s in [7.0, 37.0, 50.0, 51.5, 62.6, 64.2, 75.6, 77.1, 90.0, 100.0]:
		var k := int(round(s / 0.05))
		if k < cl.size():
			var t := SA.tangent(cl, k)
			print("[W4D]   s=%.1f → (%.2f, %.2f) 地形y %.2f 向き(%.3f, %.3f) 勾配 %.1f°" % [s, cl[k].x, cl[k].y, H[k], t.x, t.y, SA._slope_deg(H, k, 10)])
	var kinds := {}
	for a: Dictionary in st:
		kinds[a["kind"]] = int(kinds.get(a["kind"], 0)) + 1
	print("[W4D] kind 別：", JSON.stringify(kinds))
	# 蹴上＝その段の踏面頂 − 前の段の踏面頂（step／long のみ連続している区間）、踏面＝(k1−k0)*0.05
	var risers: Array = []
	var treads: Array = []
	var prev_y := NAN
	for a: Dictionary in st:
		var kd := String(a["kind"])
		if kd == "step":
			treads.append((int(a["k1"]) - int(a["k0"])) * 0.05)
			if not is_nan(prev_y):
				risers.append(float(a["y0"]) - prev_y)
		if kd == "step" or kd == "landing" or kd == "long":
			prev_y = float(a["y1"])
		else:
			prev_y = NAN
	print("[W4D] 蹴上 ", _fmt(_stats(risers)))
	print("[W4D] 踏面 ", _fmt(_stats(treads)))
	print("[W4D] 蹴上の隣接相関 lag-1 = %.2f（0 に近い＝ランダム、負＝交互。連続した高低のまとまりは正）" % _lag1(risers))
	var near := 0
	var rm: float = _stats(risers)["mean"]
	for r in risers:
		if absf(float(r) - rm) <= 0.1 * rm:
			near += 1
	print("[W4D] 蹴上が平均の ±10 %% 以内の段 %d／%d（%.0f %%）" % [near, risers.size(), 100.0 * near / maxf(risers.size(), 1)])
	# 石段メッシュ（正式 overlay）の実測：各 step の踏面の端の横位置（踏面頂の三角形のみ）
	var mi := sa.get_node("StoneSteps") as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	print("[W4D] StoneSteps 頂点 %d（三角形 %d）" % [vs.size(), vs.size() / 3])
	# 中心線の最近点インデックス（0.05 m 間隔）を粗く引く（段の範囲で絞る）
	var umax: Array = []
	var umin: Array = []
	var nose_dev: Array = []
	for a: Dictionary in st:
		if String(a["kind"]) != "step":
			continue
		var k0 := int(a["k0"])
		var k1 := int(a["k1"])
		var y0 := float(a["y0"])
		var lo := INF
		var hi := -INF
		for i in range(0, vs.size() - 2, 3):
			var c := (vs[i] + vs[i + 1] + vs[i + 2]) / 3.0
			if absf(c.y - y0) > 0.03:
				continue
			var nrm := ns[i]
			if nrm.y < 0.95:
				continue
			# 色が苔／土の薄い貼り物（緑・茶の暗い面）ではなく石（灰）
			var cc := cols[i]
			if cc.g > cc.r * 1.18 or cc.r > cc.b * 1.5:
				continue
			# c を中心線へ射影
			var kk := clampi(k0 + int((c.x - cl[k0].x) * 0.0), 0, cl.size() - 1)
			var best := INF
			var bk := k0
			for q in range(maxi(k0 - 4, 0), mini(k1 + 4, cl.size() - 1) + 1):
				var dd := Vector2(c.x, c.z).distance_squared_to(cl[q])
				if dd < best:
					best = dd
					bk = q
			if bk < k0 or bk > k1:
				continue
			var t := SA.tangent(cl, bk)
			var u := (Vector2(c.x, c.z) - cl[bk]).dot(Vector2(-t.y, t.x))
			lo = minf(lo, u)
			hi = maxf(hi, u)
		if lo < INF:
			umin.append(lo)
			umax.append(hi)
	var wsp: Array = []
	for i in umax.size():
		wsp.append(float(umax[i]) - float(umin[i]))
	print("[W4D] 踏面（石の重心）の横の最大位置 u_max ", _fmt(_stats(umax), 100.0, "cm"))
	print("[W4D] 踏面（石の重心）の横の最小位置 u_min ", _fmt(_stats(umin), 100.0, "cm"))
	print("[W4D] 踏面の横幅（重心の範囲） ", _fmt(_stats(wsp), 100.0, "cm"))
	print("[W4D] ※ 重心は石の外縁ではなく中心なので幅は実際より小さい。直線度（標準偏差）を見るための指標")
	quit(0)
