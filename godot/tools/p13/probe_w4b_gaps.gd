extends SceneTree
## P13 W4B：「実際の間隙」の幾何検査（唯讀、headless）。黒い石縫が本当の穴・隙間かを切り分ける。
##   godot --headless --path . --script res://tools/p13/probe_w4b_gaps.gd
## ① 石の上面だけ〔土の床・貼り物なし〕で、踏面の範囲を 5 cm × 2.5 cm の格子で見て、上向きの面が無い点（＝下の地面や暗い底が覗く隙間）の割合と幅
## ② 全部入りの mesh で、横断面〔u 方向〕に沿って目地の V 溝を拾い、幅と深さの分布（「等幅」かどうか）
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const WS := preload("res://tools/p13/w4_walk_surface.gd")


func _init() -> void:
	_run.call_deferred()


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(b.size() * q), 0, b.size() - 1)])


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await physics_frame
		await process_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var kr := W4.pilot_k_range(st)
	var plan := W4.replan(cl, H, st, rp)
	var sp := v.get_world_3d().direct_space_state
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var lanterns := []
	# ── ① 石だけの被覆 ──
	W4.flags = {"no_bed": true, "no_decals": true}
	var ms := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	W4.flags = {}
	var g := WS.TopGrid.new()
	g.add_mesh(ms["steps"])
	if ms["soil"] != null:
		g.add_mesh(ms["soil"])          # 継ぎ目の詰め物〔砂利まじりの土〕の帯。床〔no_bed で除外〕は含めない
	var tot := 0
	var miss := 0
	var runs := []
	var where := []      # [幅, s, u 始点]
	for k in range(kr.x + 10, kr.y - 10):
		var t := SA.tangent(cl, k)
		var nn := Vector2(-t.y, t.x)
		var run_start := NAN
		var u := -0.95
		while u <= 0.95:
			var p: Vector2 = cl[k] + nn * u
			tot += 1
			var yv := g.top_at(p.x, p.y)
			if is_nan(yv):
				miss += 1
				if is_nan(run_start):
					run_start = u
			else:
				if not is_nan(run_start):
					runs.append(u - run_start)
					where.append([u - run_start, k * 0.05, run_start])
					run_start = NAN
			u += 0.0125
		if not is_nan(run_start):
			runs.append(0.95 - run_start)
			where.append([0.95 - run_start, k * 0.05, run_start])
	print("[W4G] ① 石の上面＋継ぎ目の詰め物（土の床・貼り物なし）：中心から ±0.95 m・s=%.1f–%.1f m の格子 %d 点中、上向きの面が無い点 %d（%.3f %%）" % [(kr.x + 10) * 0.05, (kr.y - 10) * 0.05, tot, miss, 100.0 * miss / tot])
	if not runs.is_empty():
		print("[W4G]    その隙間の u 方向の幅（格子 1.25 cm 刻み）：本数 %d・中央値 %.1f cm・p90 %.1f cm・最大 %.1f cm" % [runs.size(), _pct(runs, 0.5) * 100.0, _pct(runs, 0.9) * 100.0, _pct(runs, 1.0) * 100.0])
	where.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var st_desc := []
	for c: Dictionary in plan:
		st_desc.append("%s s=%.2f–%.2f" % [String(c["kind"]), int(c["k0"]) * 0.05, int(c["k1"]) * 0.05])
	for i in mini(10, where.size()):
		var w: Array = where[i]
		var kk := int(round(float(w[1]) / 0.05))
		var inside := ""
		for c: Dictionary in plan:
			if kk >= int(c["k0"]) and kk <= int(c["k1"]):
				inside = "%s（s=%.2f–%.2f）" % [String(c["kind"]), int(c["k0"]) * 0.05, int(c["k1"]) * 0.05]
		print("[W4G]    大きい隙間 #%d：幅 %.1f cm・s=%.2f・u=%+.2f 〜 %+.2f｜%s" % [i + 1, float(w[0]) * 100.0, float(w[1]), float(w[2]), float(w[2]) + float(w[0]), inside])
	# ── ② V 溝の幅・深さ（全部入り、横断面）──
	var ms2 := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	var g2 := WS.TopGrid.new()
	g2.add_mesh(ms2["steps"])
	var widths := []
	var depths := []
	for k in range(kr.x + 10, kr.y - 10, 4):
		var t := SA.tangent(cl, k)
		var nn := Vector2(-t.y, t.x)
		var prof := []
		var us := []
		var u := -0.95
		while u <= 0.95:
			var p: Vector2 = cl[k] + nn * u
			prof.append(g2.top_at(p.x, p.y))
			us.append(u)
			u += 0.005
		var n := prof.size()
		var i := 6
		while i < n - 6:
			var yv: float = prof[i]
			if is_nan(yv):
				i += 1
				continue
			var lmax := -INF
			var rmax := -INF
			for q in range(maxi(i - 12, 0), i):
				if not is_nan(prof[q]):
					lmax = maxf(lmax, float(prof[q]))
			for q in range(i + 1, mini(i + 13, n)):
				if not is_nan(prof[q]):
					rmax = maxf(rmax, float(prof[q]))
			var shoulder := minf(lmax, rmax)
			var depth := shoulder - yv
			if depth > 0.006 and yv <= float(prof[i - 1]) and yv <= float(prof[i + 1]):
				# 谷の幅＝谷底から左右に、谷底 + depth/2 を超えるまで
				var thr := yv + depth * 0.5
				var a := i
				while a > 0 and not is_nan(prof[a]) and float(prof[a]) < thr:
					a -= 1
				var b := i
				while b < n - 1 and not is_nan(prof[b]) and float(prof[b]) < thr:
					b += 1
				widths.append((b - a) * 0.005)
				depths.append(depth)
				i = b + 1
			else:
				i += 1
	print("[W4G] ② V 溝（石の上面の谷、深さ > 6 mm）：本数 %d｜幅（半深さで測る）中央値 %.1f cm・p10 %.1f・p90 %.1f｜深さ 中央値 %.1f cm・p90 %.1f cm" % [widths.size(), _pct(widths, 0.5) * 100.0, _pct(widths, 0.1) * 100.0, _pct(widths, 0.9) * 100.0, _pct(depths, 0.5) * 100.0, _pct(depths, 0.9) * 100.0])
	var mw := 0.0
	for w in widths:
		mw += float(w)
	mw /= maxf(widths.size(), 1)
	var vw := 0.0
	for w in widths:
		vw += (float(w) - mw) * (float(w) - mw)
	print("[W4G]    幅の変動係数 %.2f（小さいほど『等幅』）" % [sqrt(vw / maxf(widths.size(), 1)) / maxf(mw, 1e-6)])
	quit(0)
