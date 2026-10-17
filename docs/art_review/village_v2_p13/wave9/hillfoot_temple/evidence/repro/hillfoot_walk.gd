extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺掛載後實走] 唯讀・場景檔不寫。
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
	print("[HILLWALK] %s %s frames=%d lost=%d max_dy=%.3f arm_min=%.2f stall=%s feet=%s end=%s" % [name, stop, n, lost, max_dy, arm_min,
		str(stalls), str(row["feet_minus_visible"]), str(row["end"])])


var _tag_name := "HILL"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag_name = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	_hero = vil.get_node_or_null("Landmarks/LANDMARK_HILLFOOT_TEMPLE/Hero") as Node3D
	print("[HILLWALK] hero=%s block=%s" % [_hero != null, vil.get_node_or_null("Landmarks/LANDMARK_HILLFOOT_TEMPLE/Block") != null])
	if _hero == null:
		quit(2)
		return
	var lod0 := _hero.get_node("LOD0") as MeshInstance3D
	_tm = lod0.mesh.generate_triangle_mesh()
	var arms := player.find_children("*", "SpringArm3D", true, false)
	_arm = arms[0] as SpringArm3D if arms.size() > 0 else null
	# A：丘腳街 → 繞過正面的四目垣斷片 → 石段腳 → 登石段，直到被社殿本體（向拝柱線）擋住
	await _leg("A_street_to_steps_top", [Vector2(222.0, -150.5), Vector2(224.0, -158.0), Vector2(225.0, -163.6),
		Vector2(228.0, -164.4), Vector2(228.0, -168.0)], "to",
		[["stepfoot", Vector2(228.0, -164.4)], ["midstair", Vector2(228.0, -166.0)]])
	await _shot("%s_top" % _tag_name, 10)
	# B：下石段 → 回到前庭
	await _leg("B_down_steps", [Vector2(228.0, -166.7), Vector2(228.0, -163.9), Vector2(224.6, -160.5)], "along")
	# C：正面橫走（石段腳前、四目垣後）：不得有看不見的障礙
	await _leg("C_front_cross", [Vector2(220.5, -163.8), Vector2(236.3, -163.8)], "along")
	# D：繞社殿一周（西 → 後 → 東）：石燈籠、台基外緣的碰撞與可見一致
	await _leg("D_west", [Vector2(221.0, -163.8), Vector2(221.0, -176.6)], "along")
	await _leg("D_back", [Vector2(221.0, -176.6), Vector2(235.0, -176.6)], "along")
	await _leg("D_east", [Vector2(235.0, -176.6), Vector2(235.0, -163.8)], "along")
	# E：朝台基側面直走（應被台基擋住；停點離可見石積 ≤ 0.35 m）
	await _leg("E_into_west_wall", [Vector2(219.5, -171.0), Vector2(226.0, -171.0)], "to")
	var f := FileAccess.open(out.path_join(_tag_name + "_walk.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": _rows}, " "))
	f.close()
	print("[HILLWALK] done")
	quit(0)
