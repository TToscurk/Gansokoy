extends SceneTree
## P13 W5A：樣本區間（s≈57–65）の現場幾何を読む（唯讀、headless）。run の範囲・左右・露出量・笠石頂線・外側地形（u=1.5／1.95）。
##   godot --headless --path . --script res://tools/p13/probe_w5a_sample.gd
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const S_LO := 57.0
const S_HI := 65.0


func _init() -> void:
	_run.call_deferred()


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
	W4.build_meshes(cl, H, plan, touts, tfars, [43.2, 61.7])
	print("[W5P] 計画の要素（s=%.1f–%.1f）：" % [S_LO, S_HI])
	for a: Dictionary in plan:
		var s0 := int(a["k0"]) * 0.05
		if s0 >= S_LO - 0.5 and s0 <= S_HI:
			print("[W5P]   %s s=%.2f–%.2f y0=%.3f y1=%.3f eL=%.2f eR=%.2f" % [String(a["kind"]), s0, int(a["k1"]) * 0.05, float(a["y0"]), float(a["y1"]), float(a.get("eL", 0.0)), float(a.get("eR", 0.0))])
	print("[W5P] 石垣の run（左＝-1／右＝+1）：")
	for e: Dictionary in W4.side_log:
		var s0 := int(e["ka"]) * 0.05
		var s1 := int(e["kb"]) * 0.05
		if s1 >= S_LO and s0 <= S_HI:
			var si := 0 if float(e["sd"]) < 0.0 else 1
			var tout: PackedFloat32Array = touts[si]
			var tfar: PackedFloat32Array = tfars[si]
			var ex_min := INF
			var ex_max := -INF
			var sl_min := INF
			var sl_max := -INF
			for k in range(int(e["ka"]), int(e["kb"]) + 1):
				if is_nan(tout[k]) or is_nan(tfar[k]):
					continue
				var line := lerpf(float(e["ta"]), float(e["tb"]), clampf(float(k - int(e["ka"])) / float(maxi(int(e["kb"]) - int(e["ka"]), 1)), 0.0, 1.0))
				var ex := line - tout[k]
				ex_min = minf(ex_min, ex)
				ex_max = maxf(ex_max, ex)
				var slope := (tfar[k] - tout[k]) / (W4.U_FAR - W4.U_TERR)
				sl_min = minf(sl_min, slope)
				sl_max = maxf(sl_max, slope)
			print("[W5P]   side=%+.0f %s s=%.2f–%.2f（%.2f m）mode=%s edge=%.3f 笠石頂線 %.3f→%.3f｜露出（頂線−地形@1.5m）%.2f–%.2f｜地形外向き勾配 %.2f–%.2f" % [float(e["sd"]), String(e["kind"]), s0, s1, s1 - s0, String(e["mode"]), float(e["edge"]), float(e["ta"]), float(e["tb"]), ex_min, ex_max, sl_min, sl_max])
	quit(0)
