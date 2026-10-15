extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 3：実際の玩家入力による短距離歩行（A 主街の北ブロック・B 住宅巷 MidLane・C 農家 A1／A2）。唯読・場景ファイルは書かない。
##   godot --path . --script res://tools/p13/w9/walk_w9p3_real.gd -- <outdir/> <tag> [--disable=EnrichW9P3,ArchW9R2P13] [--baseline=<OFF の *_walk.json>]
## 正式 main.tscn → ReviewStart → village_v2（実際の玩家制御器・TPS 相機・Auto-Step）。玩家・相機・制御器は一切改変しない：
## Input.action_press("move_forward") と制御器自身の snap_yaw だけで歩く（walk_w9r2_real.gd と同じ方式）。碰撞 capsule は player_yoriichi.tscn の実測半径。
## 脚の種別：
##   reach ：waypoint を順に通って最後の点へ。判定＝到達・連続停止 ≤ 12 フレーム・1 フレームの段差 ≤ 0.25 m。
##           接地喪失（lost）は元の地形の段差・水路で出る脚がある → 絶対値では判定せず、--baseline（overlay OFF の同じ脚）より悪くないことで判定
##   door  ：建物の戸口（W9.context の door_poly の中心）の通り側 3.5 m から壁へ向かって歩く。最初の停止が立面から ≤ 1.1 m（戸口の前が塞がれていない）
##   block ：新しい実体（柴棚の奥壁・薪の積み・幹・板塀）へ向かって歩く。ON＝目標の手前で止まる（到達しない・上に登らない）。
##           expect.short があれば「目標までの残り」が期待値 ±tol（碰撞箱の寸法＋capsule 半径から導く）。OFF では判定しない（skip）
## --disable を付けると同じ脚を overlay OFF で歩く（EnrichW9P3 は node を外す＝碰撞ごと消える。ArchW9R2P13 は enabled=false）。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")

const STALL_FRAMES := 30
const TIMEOUT_MS := 30000
const BLOCK_SPEED := 0.3

var _tag := ""
var _results: Array = []
var _fails := 0
var _off := false
var _r := 0.3
var _base := {}
var _cmp_rows: Array = []


func _facade_dist(b: Dictionary, q: Vector2) -> float:
	return (q - (b["o"] as Vector2)).dot(b["az"] as Vector2) - float(b["d"]) * 0.5


func _leg(name: String, kind: String, pts: Array, expect := {}) -> void:
	if kind == "block" and _off:
		_results.append({"leg": name, "kind": kind, "skipped": true})
		print("[W9P3WALK] SKIP %-24s block（OFF では新しい実体が無い）" % name)
		return
	var p0: Vector2 = pts[0]
	var face: Vector2 = ((pts[1] as Vector2) - p0).normalized()
	await _tpw(p0, face)
	var start := player.global_position
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press("move_forward")
	var n := 0
	var blocked := 0
	var run := 0
	var max_run := 0
	var lost := 0
	var max_dy := 0.0
	var first_stall := Vector2(NAN, NAN)
	var prev := start
	var t0 := Time.get_ticks_msec()
	var stop := ""
	var wi := 1
	var reached := false
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var goal: Vector2 = pts[wi]
		var dv := goal - q
		var d := dv.length()
		if d > 0.05:
			player.call("snap_yaw", atan2(-dv.x / d, -dv.y / d))
		if n % 8 == 1:
			_fix_camera()
		var sp := Vector2(pp.x - prev.x, pp.z - prev.z).length() / dt
		if n > 6 and sp < BLOCK_SPEED:
			blocked += 1
			run += 1
			max_run = maxi(max_run, run)
			if run == STALL_FRAMES and is_nan(first_stall.x):
				first_stall = q
		else:
			run = 0
		max_dy = maxf(max_dy, absf(pp.y - prev.y))
		prev = pp
		if not player.is_on_floor():
			lost += 1
		if kind == "reach" and d <= 0.4:
			if wi == pts.size() - 1:
				reached = true
				stop = "reached"
				break
			wi += 1
		if run >= STALL_FRAMES:
			stop = "stalled"
			break
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS:
			stop = "timeout"
			break
	Input.action_release("move_forward")
	var end := player.global_position
	var qe := Vector2(end.x, end.z)
	var ok := true
	var verdict := ""
	match kind:
		"reach":
			ok = reached and max_run <= 12 and max_dy <= 0.25
			verdict = "到達" if reached else "未到達（停止 (%.1f, %.1f)、waypoint %d/%d）" % [qe.x, qe.y, wi, pts.size() - 1]
		"door":
			var b: Dictionary = expect["b"]
			var fd := _facade_dist(b, first_stall if not is_nan(first_stall.x) else qe)
			ok = lost == 0 and not is_nan(first_stall.x) and fd <= 1.1 and max_dy <= 0.25
			verdict = "壁の手前 %.2f m まで着いた" % fd
		"block":
			var goal2: Vector2 = pts[pts.size() - 1]
			var climbed := end.y - start.y
			var stopped_before := qe.distance_to(goal2) >= float(expect.get("min_short", 0.4))
			ok = stop == "stalled" and stopped_before and climbed <= 0.25
			if expect.has("short"):
				var short := qe.distance_to(goal2)
				ok = ok and absf(short - float(expect["short"])) <= float(expect.get("tol", 0.12))
				verdict = "目標の %.2f m 手前で停止（期待 %.2f ±%.2f＝碰撞箱の前面＋半径 %.2f）・上昇 %+.2f m" % [short, float(expect["short"]), float(expect.get("tol", 0.12)), _r, climbed]
			elif expect.has("center"):
				var dc := qe.distance_to(expect["center"] as Vector2)
				var want := float(expect["radius"]) + _r
				ok = ok and absf(dc - want) <= float(expect.get("tol", 0.12))
				verdict = "停止 中心から %.2f m（期待 %.2f ±%.2f）・上昇 %+.2f m" % [dc, want, float(expect.get("tol", 0.12)), climbed]
			else:
				verdict = "目標の %.2f m 手前で停止・上昇 %+.2f m" % [qe.distance_to(goal2), climbed]
	var cmp_txt := ""
	if kind != "block" and not _off and _base.has(name):
		var bl: Dictionary = _base[name]
		var bend := Vector2(float(bl["end"][0]), float(bl["end"][1]))
		var no_worse := lost <= int(bl["lost_floor"]) and max_dy <= float(bl["max_dy_frame"]) + 0.02 and max_run <= int(bl["max_stall_run"])
		ok = ok and no_worse
		cmp_txt = " ｜OFF 比 lost %d→%d・max_dy %.3f→%.3f・最長停止 %d→%d・終点差 %.2f m → %s" % [int(bl["lost_floor"]), lost, float(bl["max_dy_frame"]), max_dy, int(bl["max_stall_run"]), max_run, qe.distance_to(bend), "同等以下" if no_worse else "悪化"]
		_cmp_rows.append({"leg": name, "off": {"lost": int(bl["lost_floor"]), "max_dy": float(bl["max_dy_frame"]), "max_run": int(bl["max_stall_run"]), "end": bl["end"]}, "on": {"lost": lost, "max_dy": snappedf(max_dy, 0.0001), "max_run": max_run, "end": [snappedf(qe.x, 0.01), snappedf(qe.y, 0.01)]}, "end_diff": snappedf(qe.distance_to(bend), 0.001), "no_worse": no_worse})
	var row := {"leg": name, "kind": kind, "stop": stop, "ok": ok, "frames": n, "blocked_frames": blocked, "max_stall_run": max_run, "lost_floor": lost,
		"max_dy_frame": snappedf(max_dy, 0.0001), "end": [snappedf(qe.x, 0.01), snappedf(qe.y, 0.01)], "dy_total": snappedf(end.y - start.y, 0.001)}
	_results.append(row)
	if not ok:
		_fails += 1
	print("[W9P3WALK] %s %-24s %s stop=%s frames=%d blocked=%d max_run=%d lost=%d max_dy=%.4f end(%.1f, %.1f) → %s%s" % [
		"PASS" if ok else "FAIL", name, kind, stop, n, blocked, max_run, lost, max_dy, qe.x, qe.y, verdict, cmp_txt])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag = args[1]
	var disables: Array = []
	for a: String in args:
		if a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
	for a: String in args:
		if a.begins_with("--baseline="):
			var bj: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--baseline=")))
			if bj is Dictionary:
				for r: Dictionary in (bj as Dictionary)["legs"]:
					_base[String(r["leg"])] = r
			print("[W9P3WALK] baseline 脚 %d 本を読み込み" % _base.size())
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	_off = not disables.is_empty()
	var cs := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		_r = (cs.shape as CapsuleShape3D).radius
		print("[W9P3WALK] 玩家 capsule 半径 %.2f・高さ %.2f（player_yoriichi.tscn）" % [_r, (cs.shape as CapsuleShape3D).height])
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			if "enabled" in dnode:
				dnode.set("enabled", false)
			else:
				vil.remove_child(dnode)
				dnode.queue_free()
			print("[W9P3WALK] disabled ", dn)
		else:
			print("[W9P3WALK] disable: node not found ", dn)
	await _frames(8)
	P3.register_dims()
	var C := W9.context(vil, PackedVector2Array())
	var own := vil.get_node_or_null("EnrichW9P3")
	print("[W9P3WALK] tag=%s EnrichW9P3=%s ArchW9R2P13=%s" % [_tag, "あり" if own != null else "なし", str(vil.get_node_or_null("ArchW9R2P13").get("enabled")) if vil.get_node_or_null("ArchW9R2P13") != null else "なし"])
	# ── A：主街の北ブロック（西側）の 5 棟
	var A_IDS := ["B_P_MKT_030", "B_P_MKT_031", "B_P_MXC_005", "B_P_MXC_006", "B_P_MXC_007"]
	var fc := Vector2.ZERO
	var nrm := Vector2.ZERO
	for id: String in ["B_P_MKT_031", "B_P_MXC_005", "B_P_MXC_006", "B_P_MXC_007"]:
		var b := W9.bld(C, id)
		fc += (b["o"] as Vector2) + (b["az"] as Vector2) * float(b["d"]) * 0.5
		nrm += b["az"] as Vector2
	fc /= 4.0
	nrm = nrm.normalized()
	var tan := Vector2(nrm.y, -nrm.x)
	await _leg("A_street_a", "reach", [fc + nrm * 4.6 - tan * 24.0, fc + nrm * 4.6 + tan * 24.0])
	await _leg("A_street_b", "reach", [fc + nrm * 4.6 + tan * 24.0, fc + nrm * 4.6 - tan * 24.0])
	for id: String in A_IDS:
		var b := W9.bld(C, id)
		var dp := SL.door_poly(b)
		var dc := (dp[0] + dp[1] + dp[2] + dp[3]) * 0.25
		await _leg("A_door_" + id.trim_prefix("B_P_"), "door", [dc + (b["az"] as Vector2) * 3.5, dc - (b["az"] as Vector2) * 0.6], {"b": b})
	# ── B：住宅巷 MidLane
	await _leg("B_lane_east", "reach", [P3.lane(-14.0, 0.0), P3.lane(16.0, 0.0)])
	await _leg("B_lane_west", "reach", [P3.lane(16.0, 0.4), P3.lane(-14.0, 0.4)])
	for id: String in ["B_P_RSW_071", "B_P_RSW_075", "B_P_RSW_076"]:
		var b := W9.bld(C, id)
		var dp := SL.door_poly(b)
		var dc := (dp[0] + dp[1] + dp[2] + dp[3]) * 0.25
		await _leg("B_door_" + id.trim_prefix("B_P_"), "door", [dc + (b["az"] as Vector2) * 3.0, dc - (b["az"] as Vector2) * 0.6], {"b": b})
	await _leg("B_gap_fence_075_076", "block", [P3.lane(5.65, -1.0), P3.lane(5.65, -6.5)], {"min_short": 1.0})
	# ── C：農家 A1／A2
	await _leg("C_road_west", "reach", [Vector2(357.0, 70.4), Vector2(329.6, 70.4)])
	await _leg("C_plank_to_door", "reach", [Vector2(329.6, 70.4), Vector2(326.4, 70.9), Vector2(324.9, 76.0), Vector2(322.9, 81.6), Vector2(323.4, 84.3)])
	await _leg("C_yard_to_garden", "reach", [Vector2(326.0, 88.6), Vector2(316.6, 88.0)])
	await _leg("C_south_corridor", "reach", [Vector2(319.6, 99.5), Vector2(319.6, 92.6)])
	await _leg("C_north_approach", "reach", [Vector2(320.0, 56.5), Vector2(320.0, 62.0)])
	if own != null or _off:
		# 柴棚：右の開口（local x＋1.0＝world z−1.0）から奥壁まで入れる／薪の積み・中柱で止まる
		var sh := _find(own, "farm_shed")
		if sh != null:
			var gt := sh.global_transform
			var ba := gt.basis.orthonormalized()
			var f := Vector2(ba.z.x, ba.z.z).normalized()      # 前（開口）の向き（局部 +z）
			var rt := Vector2(ba.x.x, ba.x.z).normalized()     # 局部 +x
			var c := Vector2(gt.origin.x, gt.origin.z)
			var back: Array = P3.SHED_COLL[0]                  # 奥壁の箱（局部 z＝−1.30・一辺 0.96＋0.06）
			var wp: Array = P3.SHED_COLL[P3.SHED_COLL.size() - 1]   # 外の薪の積み（局部 x＝−0.50・z＝1.88）
			# 1) 開口の右の隙間（局部 x＝＋1.0）から入り、奥壁の前で止まる：奥壁の前面 z＝−1.30＋0.51 → 止まる中心 z＝前面＋半径
			var back_stop_z: float = float(back[1]) + (float(back[2]) + 0.06) * 0.5 + _r
			await _leg("C_shed_enter_to_back", "block", [c + f * 3.6 + rt * 1.0, c + rt * 1.0 - f * 1.2], {"short": absf(back_stop_z - (-1.2)), "tol": 0.12})
			# 2) 外の薪の積み（局部 x＝−1.3・z＝＋1.88）に正面から：積みの前面 z＝1.88＋0.44 → 止まる中心 z＝前面＋半径
			var wp_stop_z: float = float(wp[1]) + (float(wp[2]) + 0.06) * 0.5 + _r
			var wpx: float = float(P3.SHED_COLL[P3.SHED_COLL.size() - 2][0])
			await _leg("C_shed_woodpile_out", "block", [c + f * 5.0 + rt * wpx, c + rt * wpx + f * 0.8], {"short": absf(wp_stop_z - 0.8), "tol": 0.12})
		var tr := _find(own, "keyaki_a")
		if tr != null:
			var tc := Vector2(tr.global_position.x, tr.global_position.z)
			var rr := 0.60 * tr.global_transform.basis.x.length() * 0.9
			await _leg("C_keyaki_trunk", "block", [tc + Vector2(6.0, 0.0), tc], {"min_short": 0.2, "center": tc, "radius": rr, "tol": 0.14})
	var f := FileAccess.open(out + _tag + "_walk.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": _tag, "legs": _results, "fails": _fails, "baseline_compare": _cmp_rows}, "\t") + "\n")
	f.close()
	print("[W9P3WALK] 結果：%d 脚・FAIL %d" % [_results.size(), _fails])
	quit(1 if _fails > 0 else 0)


func _find(own: Node, id: String) -> Node3D:
	if own == null:
		return null
	for n in own.find_children("*", "Node3D", true, false):
		if n.has_meta("w9_id") and String(n.get_meta("w9_id")) == id:
			return n as Node3D
	return null
