extends "res://tools/p13/w6/w6_base.gd"
## [scratch：P13 W9 Blender-first B8P 試点] 実際の玩家入力による歩行（walk_w9r2_real.gd と同じ方式・唯読・場景ファイルは書かない）。
##   godot --path godot --script <this> -- <outdir/> <tag> [--mount=Name=res://path.scn]
## 正式 main.tscn → ReviewStart → village_v2（実際の玩家制御器・TPS 相機・Auto-Step）。Input.action_press("move_forward")＋制御器の snap_yaw だけで歩く。
## 脚の種類：along＝目標まで到達（0.35 m 以内）・接地喪失 0・停止 12 フレーム以下・1 フレームの上下 ≤ 0.25 m
##          to   ＝目標（戸口・木戸）の手前で止まってよい：最初の停止点が目標から ≤ stop_ok m・接地喪失 0
## 出力：<tag>_walk.json＋[B8PWALK] 行。--mount なし＝overlay OFF（比較用）。
const LEGS := [
	# [名前, 種別, 出発 (x, z), 目標 (x, z), stop_ok]
	# 巷（NELane）は折線 (438,-216)→(456,-236)→(486,-246)：曲がり角で 2 脚に分ける（直線で結ぶと 003 の正面へ切り込む）
	["lane_a", "along", Vector2(440.5, -218.5), Vector2(455.5, -235.4), 0.0],
	["lane_b", "along", Vector2(455.5, -235.4), Vector2(468.0, -239.8), 0.0],
	["lane_b_rev", "along", Vector2(468.0, -239.8), Vector2(455.5, -235.4), 0.0],
	["lane_a_rev", "along", Vector2(455.5, -235.4), Vector2(440.5, -218.5), 0.0],
	["nesouth", "along", Vector2(440.0, -215.3), Vector2(456.5, -208.7), 0.0],            # 分岐から NESouth へ（002 西壁の下屋・藁塚の脇）
	["nesouth_rev", "along", Vector2(456.5, -208.7), Vector2(440.0, -215.3), 0.0],
	["back_strip", "along", Vector2(453.6, -212.9), Vector2(474.0, -217.2), 0.0],        # 裏の共有地の帯（柴垣と薪場の間）
	["back_strip_rev", "along", Vector2(474.0, -217.2), Vector2(453.6, -212.9), 0.0],
	["yard004_in", "along", Vector2(466.0, -216.3), Vector2(470.6, -223.0), 0.0],         # 大根掛と畝の間を抜けて 004 の裏口へ
	["hoshiba_in", "along", Vector2(444.8, -228.6), Vector2(447.6, -235.0), 0.0],         # 巷から干し場へ
	["gate_kido", "to", Vector2(459.0, -217.6), Vector2(455.2, -221.7), 1.3],            # 踏石を通って木戸まで（木戸は閉じている＝手前で止まる）
	["door_002", "to", Vector2(445.6, -226.6), Vector2(448.3, -224.1), 1.1],
	["door_003", "to", Vector2(450.6, -232.3), Vector2(453.3, -229.8), 1.1],
	["door_004", "to", Vector2(465.0, -240.6), Vector2(466.2, -237.0), 1.1],
	["backdoor_002", "to", Vector2(459.6, -213.6), Vector2(456.3, -215.2), 1.1],
]
const STALL_FRAMES := 30
const TIMEOUT_MS := 25000
const BLOCK_SPEED := 0.3

var _tag := ""
var _results: Array = []
var _fails := 0


func _leg(lg: Array) -> void:
	var name: String = lg[0]
	var kind: String = lg[1]
	var p0: Vector2 = lg[2]
	var p1: Vector2 = lg[3]
	var stop_ok: float = lg[4]
	await _tpw(p0, (p1 - p0).normalized())
	var start := player.global_position
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press("move_forward")
	var n := 0
	var run := 0
	var max_run := 0
	var lost := 0
	var max_dy := 0.0
	var first_stall_d := NAN
	var reached := false
	var prev := start
	var t0 := Time.get_ticks_msec()
	var stop := ""
	var min_d := 1e9
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var dv := p1 - q
		var d := dv.length()
		min_d = minf(min_d, d)
		if d > 0.05:
			player.call("snap_yaw", atan2(-dv.x / d, -dv.y / d))
		if n % 8 == 1:
			_fix_camera()
		var sp := Vector2(pp.x - prev.x, pp.z - prev.z).length() / dt
		if n > 6 and sp < BLOCK_SPEED:
			run += 1
			max_run = maxi(max_run, run)
			if run == STALL_FRAMES and is_nan(first_stall_d):
				first_stall_d = d
		else:
			run = 0
		max_dy = maxf(max_dy, absf(pp.y - prev.y))
		prev = pp
		if not player.is_on_floor():
			lost += 1
		if d <= 0.35:
			reached = true
			stop = "reached"
			break
		if run >= STALL_FRAMES:
			stop = "stalled"
			break
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS:
			stop = "timeout"
			break
	Input.action_release("move_forward")
	var end := player.global_position
	var ok := true
	var verdict := ""
	if kind == "along":
		ok = reached and lost <= 2 and max_run <= 12 and max_dy <= 0.25
		verdict = "到達" if reached else "未到達（目標まで %.2f m で停止）" % Vector2(end.x, end.z).distance_to(p1)
	else:
		var sd := 0.0 if reached else (first_stall_d if not is_nan(first_stall_d) else Vector2(end.x, end.z).distance_to(p1))
		ok = lost <= 2 and sd <= stop_ok and max_dy <= 0.25
		verdict = "目標の手前 %.2f m（許容 %.2f）" % [sd, stop_ok]
	var row := {"leg": name, "kind": kind, "stop": stop, "ok": ok, "frames": n, "max_stall_run": max_run, "lost_floor": lost,
		"max_dy_frame": snappedf(max_dy, 0.0001), "end": [snappedf(end.x, 0.01), snappedf(end.y, 0.01), snappedf(end.z, 0.01)],
		"end_dist": snappedf(Vector2(end.x, end.z).distance_to(p1), 0.01), "min_dist": snappedf(min_d, 0.01), "dy_total": snappedf(end.y - start.y, 0.001)}
	_results.append(row)
	if not ok:
		_fails += 1
	print("[B8PWALK] %s %-14s %s stop=%s frames=%d max_run=%d lost=%d max_dy=%.3f end_dist=%.2f → %s" % [
		"PASS" if ok else "FAIL", name, kind, stop, n, max_run, lost, max_dy, row["end_dist"], verdict])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag = args[1]
	var mounts: Array = []
	for a: String in args:
		if a.begins_with("--mount="):
			var mt := a.trim_prefix("--mount=").split("=", false, 1)
			mounts.append([mt[0], mt[1]])
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var cs := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		print("[B8PWALK] 玩家 capsule 半径 %.2f・高さ %.2f" % [(cs.shape as CapsuleShape3D).radius, (cs.shape as CapsuleShape3D).height])
	for mt2: Array in mounts:
		var inst := (load(String(mt2[1])) as PackedScene).instantiate()
		inst.name = String(mt2[0])
		vil.add_child(inst)
		print("[B8PWALK] mounted (memory only) ", mt2[0])
	for i in 4:
		await physics_frame
	await _frames(6)
	for lg: Array in LEGS:
		await _leg(lg)
	var f := FileAccess.open(out + _tag + "_walk.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": _tag, "mounts": mounts, "legs": _results, "fails": _fails}, "\t") + "\n")
	f.close()
	print("[B8PWALK] 結果：%d 脚・FAIL %d" % [_results.size(), _fails])
	quit(1 if _fails > 0 else 0)
