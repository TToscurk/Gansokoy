extends SceneTree
## Wind V2 Phase E：主河水面場＋浮物驗證（headless 可跑：水面 API 與浮物都是 CPU）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/water_verify.gd
## E1 接線  E2 流向／流速剖面  E3 風不改水流  E4 靜止時水面仍在動  E5 風大漣漪大
## E6 浮物貼水面、不落水  E7 輕重響應不同  E8 繫留  E9 無瞬移  E10 回收是淡出不是瞬切
## 任何 FAIL → quit(1)

var fails := 0
var w: Node
var v: Node


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _run() -> void:
	w = root.get_node("Wind")
	var ps := load("res://maps/village_v2/village_v2.tscn") as PackedScene
	v = ps.instantiate()
	root.add_child(v)
	for i in 20:
		await process_frame
	print("\n[E1] 主河接線")
	var mr := v.get_node_or_null("Water/MainRiver") as MeshInstance3D
	var sm := mr.material_override as ShaderMaterial if mr else null
	_ok(w.has_water(), "Wind 有水面場（%s）" % str(w.water.name if w.water else ""))
	_ok(sm != null and sm.shader.resource_path.ends_with("water.gdshader") and float(sm.get_shader_parameter("vc_albedo")) == 1.0,
		"主河換成 water.gdshader 人里主河模式（重用既有河水 shader）")
	_ok(mr != null and mr.get_meta("wind_orig_material") is StandardMaterial3D, "原 P2 材質保存在 meta（可還原）")

	print("\n[E2] 流向與流速剖面")
	var a := Vector2(414, -168)
	var b := Vector2(430, -151)
	var tan := (b - a).normalized()
	var mid := (a + b) * 0.5
	var nrm := Vector2(-tan.y, tan.x)
	var f_c: Vector3 = w.sample_water_flow(Vector3(mid.x, 0, mid.y))
	var f_b: Vector3 = w.sample_water_flow(Vector3(mid.x + nrm.x * 12.0, 0, mid.y + nrm.y * 12.0))
	var f_out: Vector3 = w.sample_water_flow(Vector3(mid.x + nrm.x * 40.0, 0, mid.y + nrm.y * 40.0))
	_ok(Vector2(f_c.x, f_c.z).dot(tan) > 0.35, "中央流向下游 %.2f m/s（中心線方向分量）" % Vector2(f_c.x, f_c.z).dot(tan))
	_ok(f_b.length() < f_c.length() * 0.7, "近岸較慢：岸邊 %.2f < 中央 %.2f m/s" % [f_b.length(), f_c.length()])
	_ok(f_out.length() < 0.01 and float(w.sample_water_mask(Vector3(mid.x + nrm.x * 40.0, 0, mid.y + nrm.y * 40.0))) < 0.05,
		"岸上 40 m：流速 0、不在水中（%.3f m/s，mask %.2f）" % [f_out.length(), float(w.sample_water_mask(Vector3(mid.x + nrm.x * 40.0, 0, mid.y + nrm.y * 40.0)))])

	print("\n[E3] 風不改水流")
	w.set_frozen(true)
	w.set_wind(rad_to_deg(atan2(-tan.y, -tan.x)), 1.5)   # 逆流強風
	for i in 120:
		w.debug_advance(1.0 / 30.0)
	var f_c2: Vector3 = w.sample_water_flow(Vector3(mid.x, 0, mid.y))
	_ok(f_c2.is_equal_approx(f_c), "逆流強風下流速不變（%s → %s）" % [f_c, f_c2])

	print("\n[E4] 靜止時水面仍在動（calm）")
	w.clear_override()
	w.set_preset(0)
	for i in 150:
		w.debug_advance(1.0 / 30.0)
	var pp := Vector3(mid.x, 0, mid.y)
	var hs := []
	for i in 120:
		w.debug_advance(0.1)
		hs.append(float(w.sample_water_height(pp)))
	var sd_calm := _std(hs)
	_ok(sd_calm > 0.004 and sd_calm < 0.04, "calm 水面高 std %.1f mm（長波；不是死水、也不是海浪）" % (sd_calm * 1000.0))

	print("\n[E5] 風大漣漪大")
	var rip_calm := _ripple_std(pp)
	w.set_preset(3)
	for i in 240:
		w.debug_advance(1.0 / 30.0)
	var rip_gust := _ripple_std(pp)
	_ok(rip_gust > rip_calm * 3.0, "漣漪斜率 std：calm %.4f → gust %.4f（×%.1f）" % [rip_calm, rip_gust, rip_gust / maxf(rip_calm, 1e-6)])
	var hs2 := []
	for i in 120:
		w.debug_advance(0.1)
		hs2.append(float(w.sample_water_height(pp)))
	_ok(_std(hs2) < 0.06, "強陣風水面高 std %.1f mm（< 60 mm：河不是海）" % (_std(hs2) * 1000.0))

	print("\n[E6–E10] 浮物（實時物理 60 Hz，breeze → gust）")
	w.set_frozen(false)
	w.set_preset(1)
	var demo := v.get_node_or_null("WindRiverDemo")
	if demo:
		demo.call("spawn_debris")   # 正式遊玩不生成；驗證工具明確要求
	for i in 30:
		await process_frame
	var fl: Array = demo.call("floatables") if demo else []
	var leaves := fl.filter(func(n): return String(n.name).begins_with("LEAF"))
	var tarus := fl.filter(func(n): return String(n.name).begins_with("Taru"))
	var boat: Node = demo.get_node_or_null("../WaterLifeP10/BoatLanding/Boat/BoatTether") if demo else null
	_ok(leaves.size() == 8 and tarus.size() == 2, "落葉 proxy %d、酒樽 %d" % [leaves.size(), tarus.size()])
	_ok(boat != null, "小舟繫留元件已掛（Hull 視覺節點）")
	var prev := {}
	for n in fl:
		prev[n] = (n.call("state") as Dictionary)["pos"]
	var max_step := 0.0
	var prev_fade := {}
	var max_err := 0.0
	var worst_n := ""
	var below := 0
	var leaf_resp := []
	var taru_resp := []
	var leaf_yaw := []
	var taru_yaw := []
	var boat_max := 0.0
	var boat_anchor: Vector3 = boat.get("_anchor") if boat else Vector3.ZERO
	var fade_min := 1.0
	var fade_jump := 0.0
	var probe_leaf: Node = leaves[0] if leaves.size() > 0 else null
	if probe_leaf:
		probe_leaf.set("recycle_distance", 4.0)   # 讓這一片一定會觸發回收
	var fade_prev := 1.0
	var fade_seq := []
	var frames := 60 * 40
	for i in frames:
		if i == 60 * 15:
			w.set_preset(3)
			w.trigger_gust(1.0, 3.0)
		await physics_frame
		for n in fl:
			var st: Dictionary = n.call("state")
			var p: Vector3 = st["pos"]
			# 只算看得見的步（回收重生發生在縮放 0、離相機 > 25 m 時，不算瞬移）
			if float(st["fade"]) > 0.01 and float(prev_fade.get(n, 1.0)) > 0.01:
				max_step = maxf(max_step, p.distance_to(prev[n]))
			prev[n] = p
			prev_fade[n] = float(st["fade"])
			if not bool(st["in_water"]):
				continue
			var wh := float(w.sample_water_height(p))
			if not is_nan(wh) and i > 120:
				var err := absf(p.y - (wh - float(n.get("draft_m"))))
				if err > max_err:
					max_err = err
					worst_n = "%s@%d" % [n.name, i]
				if p.y < wh - float(n.get("draft_m")) - 0.15:
					below += 1
			fade_min = minf(fade_min, float(st["fade"]))
		for n in leaves:
			leaf_yaw.append(float((n.call("state") as Dictionary)["yaw_rate"]))
		for n in tarus:
			taru_yaw.append(float((n.call("state") as Dictionary)["yaw_rate"]))
		if probe_leaf:
			var fd := float((probe_leaf.call("state") as Dictionary)["fade"])
			fade_jump = maxf(fade_jump, absf(fd - fade_prev))
			fade_prev = fd
			fade_seq.append(fd)
		if boat:
			var bp: Vector3 = (boat.call("state") as Dictionary)["pos"]
			boat_max = maxf(boat_max, Vector2(bp.x - boat_anchor.x, bp.z - boat_anchor.z).length())
	_ok(max_err < 0.05, "貼水面：浮物高度與（水面−吃水）最大誤差 %.1f mm（%s）" % [max_err * 1000.0, worst_n])
	_ok(below == 0, "不落水：低於水面 15 cm 以上的樣本 %d" % below)
	_ok(max_step < 0.2, "無瞬移：可見時最大單步位移 %.3f m（1/60 s）" % max_step)
	var ly := _std(leaf_yaw)
	var ty := _std(taru_yaw)
	_ok(ly > ty * 2.0, "偏航變化：落葉 std %.3f rad/s > 酒樽 %.3f 的 2 倍（輕的轉得快）" % [ly, ty])
	if boat:
		_ok(boat_max < float(boat.get("tether_length")) + 0.08, "繫留：小舟離錨點最大 %.2f m（繩長 %.2f）" % [boat_max, float(boat.get("tether_length"))])
	# E7 響應時間：從靜止放進同一點，量到達當地流速 63 % 的時間
	var tl := await _response_time(0)
	var th := await _response_time(1)
	_ok(tl > 0.0 and th > tl * 3.0, "加速響應：落葉 %.2f s、酒樽 %.2f s（重的慢）" % [tl, th])
	var faded: float = float(fade_seq.min()) if fade_seq.size() > 0 else 1.0
	_ok(faded < 0.05 and fade_jump < 0.05, "回收走淡出：縮放最低 %.2f、每幀最大變化 %.3f（漂離 4 m 後逐幀縮小，不是瞬切）" % [faded, fade_jump])
	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _ripple_std(p: Vector3) -> float:
	var s := []
	for i in 60:
		w.debug_advance(0.05)
		var n: Vector3 = w.sample_water_normal(p)
		s.append(n.x)
	return _std(s)


func _response_time(preset: int) -> float:
	var f: Node3D = load("res://scripts/water/floatable.gd").new()
	f.set("preset", preset)
	var p := Vector3(422, 0, -159.5)
	f.position = Vector3(p.x, float(w.sample_water_height(p)), p.z)
	v.add_child(f)
	await physics_frame
	var target: Vector3 = w.sample_water_flow(p)
	var tsp := Vector2(target.x, target.z).length()
	var t := 0.0
	for i in 600:
		await physics_frame
		t += 1.0 / 60.0
		var vel: Vector3 = (f.call("state") as Dictionary)["vel"]
		if Vector2(vel.x, vel.z).length() >= 0.63 * tsp:
			f.queue_free()
			return t
	f.queue_free()
	return 99.0


func _std(a: Array) -> float:
	var m := 0.0
	for x in a:
		m += float(x)
	m /= maxf(a.size(), 1)
	var s := 0.0
	for x in a:
		s += (float(x) - m) * (float(x) - m)
	return sqrt(s / maxf(a.size(), 1))
