extends SceneTree
## P13 Wave 4：r8 參道の階緣と地形の関係（穿插／浮空の定量、唯讀、headless）。
##   godot --headless --path . --script res://tools/p13/diag_w4_edges.gd
## 各 step／landing の中央で横方向 u＝±0.6／±1.2（石段の端）／±1.44（袖石の外）の地形高 Ht を取り、
##   poke＝Ht − 踏面頂（正＝地形が踏面より高い＝石の端が土に埋まる／地形が踏面を突き破って見える）
##   gap ＝(石の底＝中心の地形 − 0.45) − Ht（正＝端で地形が石底より低い＝石の下に空きが見える〔浮空〕）
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")


func _init() -> void:
	_run.call_deferred()


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


func _stat(a: Array) -> String:
	if a.is_empty():
		return "n=0"
	var s := 0.0
	var lo := INF
	var hi := -INF
	for v in a:
		s += float(v)
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var n := 0
	for v in a:
		if float(v) > 0.0:
			n += 1
	return "n=%d 平均 %+.1f cm・最小 %+.1f・最大 %+.1f・正(>0)の割合 %.0f %%" % [a.size(), s / a.size() * 100.0, lo * 100.0, hi * 100.0, 100.0 * n / a.size()]


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
	var st := SA.steps(cl, H)
	var sp := v.get_world_3d().direct_space_state
	var res := {}
	for u in [-1.44, -1.2, -0.6, 0.6, 1.2, 1.44]:
		res[u] = {"poke": [], "gap": []}
	var cross: Array = []
	for a: Dictionary in st:
		if String(a["kind"]) == "slab":
			continue
		var km := (int(a["k0"]) + int(a["k1"])) / 2
		var t := SA.tangent(cl, km)
		var n := Vector2(-t.y, t.x)
		var yc := H[km]
		var ytop := float(a["y0"])
		var hl := _terr(sp, cl[km] + n * -1.2)
		var hr := _terr(sp, cl[km] + n * 1.2)
		if not is_nan(hl) and not is_nan(hr):
			cross.append(atan2(hr - hl, 2.4))
		for u in res:
			var ht := _terr(sp, cl[km] + n * float(u))
			if is_nan(ht):
				continue
			(res[u]["poke"] as Array).append(ht - ytop)
			(res[u]["gap"] as Array).append((yc - 0.45) - ht)
	print("[W4E] 段 %d 件（slab を除く）の階緣と地形" % [st.size()])
	for u in res:
		print("[W4E] u=%+.2f m  poke(地形−踏面頂): %s" % [float(u), _stat(res[u]["poke"])])
	for u in res:
		print("[W4E] u=%+.2f m  gap(石底−地形)  : %s" % [float(u), _stat(res[u]["gap"])])
	var cs := 0.0
	var cmax := 0.0
	for c in cross:
		cs += absf(float(c))
		cmax = maxf(cmax, absf(float(c)))
	print("[W4E] 横断勾配（±1.2 m の地形差から）：平均 %.1f°・最大 %.1f°（n=%d）" % [rad_to_deg(cs / maxf(cross.size(), 1)), rad_to_deg(cmax), cross.size()])
	# 踊り場前縁の盛土（踏面 − 地形）
	for a: Dictionary in st:
		if String(a["kind"]) == "landing":
			var k0 := int(a["k0"])
			print("[W4E] 踊り場 s=%.1f–%.1f：前縁の地形 %.2f・踏面 %.2f → 盛土(前縁の立ち上がり) %.2f m" % [k0 * 0.05, int(a["k1"]) * 0.05, H[k0], float(a["y0"]), float(a["y0"]) - H[k0]])
	# 墊高プロファイル：各段の中央で（踏面頂 − 中心線地形）と、両端〔±1.3 m〕の地形に対する外側面の露出高
	var line := ""
	var n_lo := 0
	var n_mid := 0
	var n_hi := 0
	for a: Dictionary in st:
		var km := (int(a["k0"]) + int(a["k1"])) / 2
		var t := SA.tangent(cl, km)
		var nn := Vector2(-t.y, t.x)
		var fl := float(a["y0"]) - _terr(sp, cl[km] + nn * -1.3)
		var fr := float(a["y0"]) - _terr(sp, cl[km] + nn * 1.3)
		var fe := maxf(fl, fr)
		if fe > 0.60:
			n_hi += 1
		elif fe > 0.30:
			n_mid += 1
		else:
			n_lo += 1
		if int(a["k0"]) % 12 == 0 or String(a["kind"]) == "landing":
			line += "s%.0f:%s%.2f/%.2f  " % [km * 0.05, "L" if String(a["kind"]) == "landing" else "", float(a["y0"]) - H[km], fe]
	print("[W4E] 墊高(中心/端の外側面露出) 抜粋  s:中心/端 →  ", line)
	print("[W4E] 端の外側面露出高 ≤ 0.30 m：%d 段、0.30–0.60 m：%d 段、> 0.60 m：%d 段（全 %d 段）" % [n_lo, n_mid, n_hi, st.size()])
	quit(0)
