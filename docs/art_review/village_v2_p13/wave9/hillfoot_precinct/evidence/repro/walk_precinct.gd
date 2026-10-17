extends "res://tools/p13/w6/w6_base.gd"
## [TASK E2：丘腳社寺境內環境 實走＋SpringArm] 唯讀・場景檔不寫（只在記憶體內切 HillfootPrecinctE2.enabled 取 BEFORE）。
## （由 hillfoot_temple/evidence/repro/hillfoot_walk.gd 擴充：_leg 不變；新增參道多路線・踏石串走・SpringArm 掃描 BEFORE|AFTER）
##   godot --path godot --script <this> -- <outdir/> HILLFOOT --map=village_v2
## 正式 main.tscn → village_v2（磁碟上的場景，Hero 已掛）、實際玩家控制器＋TPS SpringArm、真輸入（move_forward＋snap_yaw）。
## 每幀記：接地、單幀上下、卡住（< 0.3 m/s 連續 45 幀 → 記碰撞對象）、SpringArm 實長；
## 石段範圍內：腳底（玩家原點）與「腳下可見網格」（Hero LOD0 三角網格，自腳底上方 0.8 m 往下射）的高差。

const STALL := 45
var _rows: Array = []
var _hero: Node3D
var _tm: TriangleMesh
var _arm: SpringArm3D


func _vis_y(p: Vector3) -> float:
	var inv := _hero.global_transform.affine_inverse()
	var a := inv * (p + Vector3(0, 0.8, 0))
	var r: Dictionary = _tm.intersect_ray(a, Vector3.DOWN)
	if r.is_empty():
		return NAN
	return (_hero.global_transform * (r["position"] as Vector3)).y


func _in_steps(p: Vector3) -> bool:
	var l := _hero.global_transform.affine_inverse() * p
	return absf(l.x) <= 1.6 and l.z >= 2.76 and l.z <= 4.6


func _leg(name: String, wps: Array, kind: String, shots: Array = []) -> void:
	await _tpw(wps[0], (wps[1] - wps[0]).normalized())
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var idx := 1
	var n := 0
	var run := 0
	var lost := 0
	var max_dy := 0.0
	var stalls: Array = []
	var feet: Array = []        # 石段上：腳底 − 可見面
	var arm_min := 99.0
	var prev := player.global_position
	var stop := ""
	var t0 := Time.get_ticks_msec()
	var shot_i := 0
	Input.action_press("move_forward")
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var tgt: Vector2 = wps[idx]
		var dv := tgt - q
		var d := dv.length()
		if d < 0.8 and idx < wps.size() - 1:
			idx += 1
			continue
		if d > 0.05:
			player.call("snap_yaw", atan2(-dv.x / d, -dv.y / d))
		if n % 8 == 1:
			_fix_camera()
		if _arm != null and n > 20:
			arm_min = minf(arm_min, _arm.get_hit_length())
		var sp := Vector2(pp.x - prev.x, pp.z - prev.z).length() / dt
		max_dy = maxf(max_dy, absf(pp.y - prev.y))
		prev = pp
		if not player.is_on_floor():
			lost += 1
		if _in_steps(pp) and player.is_on_floor():
			var vy := _vis_y(pp)
			if not is_nan(vy):
				feet.append(pp.y - vy)
		if shot_i < shots.size() and Vector2(pp.x, pp.z).distance_to(shots[shot_i][1]) < 0.5:
			Input.action_release("move_forward")
			await _frames(30)
			await _shot("%s_%s" % [_tag_name, shots[shot_i][0]], 10)
			shot_i += 1
			Input.action_press("move_forward")
		if idx == wps.size() - 1 and d <= 0.5:
			stop = "reached"
			break
		run = run + 1 if (n > 8 and sp < 0.3) else 0
		if run >= STALL:
			var col := ""
			var kc := player.get_last_slide_collision()
			if kc != null and kc.get_collider() is Node:
				col = String((kc.get_collider() as Node).get_path()).replace("/root/Main/", "")
			var l := _hero.global_transform.affine_inverse() * pp
			stalls.append({"x": snappedf(pp.x, 0.01), "y": snappedf(pp.y, 0.01), "z": snappedf(pp.z, 0.01),
				"local": [snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01)], "collider": col, "wp": idx, "dist": snappedf(d, 0.01)})
			stop = "stalled"
			break
		if Time.get_ticks_msec() - t0 > 40000:
			stop = "timeout"
			break
	Input.action_release("move_forward")
	for i in 10:
		await physics_frame
	var fmax := -99.0
	var fmin := 99.0
	var fsum := 0.0
	for f: float in feet:
		fmax = maxf(fmax, f)
		fmin = minf(fmin, f)
		fsum += f
	var row := {"leg": name, "kind": kind, "stop": stop, "frames": n, "lost_floor": lost, "max_dy": snappedf(max_dy, 0.001),
		"stall": stalls, "arm_min": snappedf(arm_min, 0.01), "steps_samples": feet.size(),
		"feet_minus_visible": {"min": snappedf(fmin, 0.001), "max": snappedf(fmax, 0.001), "mean": snappedf(fsum / maxf(1, feet.size()), 0.001)} if feet.size() > 0 else {},
		"end": [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.y, 0.01), snappedf(player.global_position.z, 0.01)]}
	_rows.append(row)
	print("[PREC] %s %s frames=%d lost=%d max_dy=%.3f arm_min=%.2f stall=%s feet=%s end=%s" % [name, stop, n, lost, max_dy, arm_min,
		str(stalls), str(row["feet_minus_visible"]), str(row["end"])])


var _tag_name := "HILL"


func _arm_len(p: Vector2, yaw_face: Vector2) -> float:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, _ground(p) + 0.05, p.y)
	player.call("snap_yaw", atan2(-yaw_face.x, -yaw_face.y))
	for i in 6:
		await physics_frame
	return _arm.get_hit_length() if _arm != null else NAN


func _sweep(tag: String) -> Array:
	# 境內・參道の代表 18 点 × 8 方位の SpringArm 実長（長さ＝壓縮されなかった長さ。小さいほど壓縮）
	var pts: Array = [Vector2(228, -152.6), Vector2(228, -155), Vector2(228.2, -158), Vector2(228.3, -161), Vector2(228, -163.6),
		Vector2(224.5, -161.5), Vector2(231.5, -161.5), Vector2(222.0, -164.5), Vector2(234.5, -164.5), Vector2(221.2, -170), Vector2(234.8, -170),
		Vector2(222.5, -176.5), Vector2(228, -177.5), Vector2(233.5, -176.5), Vector2(224.0, -157.5), Vector2(232.0, -157.5), Vector2(225.5, -153.0), Vector2(231.0, -153.0)]
	var rows: Array = []
	for p: Vector2 in pts:
		for k in 8:
			var a := TAU * k / 8.0
			var L := await _arm_len(p, Vector2(sin(a), cos(a)))
			rows.append({"p": [p.x, p.y], "k": k, "len": snappedf(L, 0.01)})
	print("[PREC] sweep %s n=%d" % [tag, rows.size()])
	return rows


func _stone_wps() -> Array:
	var wps: Array = []
	var dh := vil.get_node_or_null("DistrictHF")
	if dh != null and dh.get_node_or_null("approach_stones") != null:
		var xs: Array = []
		for it in dh.get_node("approach_stones").get_children():
			var n3 := it as Node3D
			if n3 != null:
				xs.append(Vector2(n3.global_position.x, n3.global_position.z))
		xs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y)
		wps = xs
	return wps


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag_name = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	_hero = vil.get_node_or_null("Landmarks/LANDMARK_HILLFOOT_TEMPLE/Hero") as Node3D
	var ov := vil.get_node_or_null("HillfootPrecinctE2")
	print("[PREC] hero=%s overlay=%s enabled=%s" % [_hero != null, ov != null, ov.get("enabled") if ov else "-"])
	if _hero == null or ov == null:
		quit(2)
		return
	var lod0 := _hero.get_node("LOD0") as MeshInstance3D
	_tm = lod0.mesh.generate_triangle_mesh()
	var arms := player.find_children("*", "SpringArm3D", true, false)
	_arm = arms[0] as SpringArm3D if arms.size() > 0 else null
	# A：丘腳街 → 参道 → 石段腳 → 登石段，到被社殿本體擋住（舊版本得繞過四目垣；現在直走）
	await _leg("A_street_straight_to_stairs", [Vector2(227.0, -150.6), Vector2(227.9, -156.0), Vector2(228.3, -161.0), Vector2(228.0, -164.4), Vector2(228.0, -168.0)], "to",
		[["stepfoot", Vector2(228.0, -164.4)], ["midstair", Vector2(228.0, -166.0)]])
	await _shot("%s_top" % _tag_name, 10)
	await _leg("B_down_steps", [Vector2(228.0, -166.7), Vector2(228.0, -163.9), Vector2(224.6, -160.5)], "along")
	# A2/A3：参道の斜め進入（西寄り・東寄り）。四目垣があった側（西）も含む
	await _leg("A2_west_diagonal", [Vector2(223.6, -150.6), Vector2(225.4, -156.0), Vector2(227.0, -161.5), Vector2(228.0, -164.2)], "to")
	await _leg("A3_east_diagonal", [Vector2(232.6, -150.6), Vector2(231.0, -156.0), Vector2(229.5, -161.5), Vector2(228.2, -164.2)], "to")
	# S：踏石を順に踏んで歩く（碰撞なしの kit 石で引っかからない・段差で跳ねない）
	var sw := _stone_wps()
	if sw.size() >= 2:
		await _leg("S_stepping_stones", [Vector2(228.0, -150.8)] + sw + [Vector2(228.0, -164.2)], "along")
	await _leg("C_front_cross", [Vector2(220.5, -163.8), Vector2(236.3, -163.8)], "along")
	await _leg("C2_front_far", [Vector2(221.2, -160.6), Vector2(234.8, -160.6)], "along")
	await _leg("D_west", [Vector2(221.0, -163.8), Vector2(221.0, -176.6)], "along")
	await _leg("D_back", [Vector2(221.0, -176.6), Vector2(235.0, -176.6)], "along")
	await _leg("D_east", [Vector2(235.0, -176.6), Vector2(235.0, -163.8)], "along")
	# SpringArm 掃描：AFTER（現狀）→ 切 enabled=false（＝BEFORE：垣・草在、新植栽・踏石隱藏）→ 再切回
	var s_after: Array = await _sweep("AFTER")
	ov.set("enabled", false)
	for i in 4:
		await physics_frame
	var s_before: Array = await _sweep("BEFORE")
	ov.set("enabled", true)
	for i in 4:
		await physics_frame
	var worse := 0
	var severe_after := 0
	var severe_before := 0
	var worst_delta := 0.0
	var worst_where := ""
	var min_after := 99.0
	var min_before := 99.0
	for i in s_after.size():
		var la: float = s_after[i]["len"]
		var lb: float = s_before[i]["len"]
		min_after = minf(min_after, la)
		min_before = minf(min_before, lb)
		if la < 2.0:
			severe_after += 1
		if lb < 2.0:
			severe_before += 1
		if la < lb - 0.25:
			worse += 1
		if la - lb < worst_delta:
			worst_delta = la - lb
			worst_where = "(%.1f,%.1f) k=%d %.2f→%.2f" % [s_after[i]["p"][0], s_after[i]["p"][1], s_after[i]["k"], lb, la]
	print("[PREC] SpringArm：樣本 %d・AFTER 最短 %.2f／BEFORE 最短 %.2f・< 2.0 m（重壓縮）AFTER %d／BEFORE %d・比 BEFORE 短 > 0.25 m 的樣本 %d・最大退步 %.2f（%s）" % [
		s_after.size(), min_after, min_before, severe_after, severe_before, worse, worst_delta, worst_where])
	var f := FileAccess.open(out.path_join(_tag_name + "_walk.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": _rows, "sweep_after": s_after, "sweep_before": s_before,
		"sweep_summary": {"n": s_after.size(), "min_after": min_after, "min_before": min_before, "severe_after": severe_after, "severe_before": severe_before, "worse_025": worse, "worst_delta": worst_delta, "worst_where": worst_where}}, " "))
	f.close()
	print("[PREC] done")
	quit(0)
