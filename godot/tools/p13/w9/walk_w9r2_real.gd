extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 2：実際の玩家入力による短距離歩行（三棟＝RSW_074／MKT_029／RSW_014 の周り）。唯読・場景ファイルは書かない。
##   godot --path . --script res://tools/p13/w9/walk_w9r2_real.gd -- <outdir/> <tag> [--disable=ArchW9R2P13]
## 正式 main.tscn → ReviewStart → village_v2（実際の玩家制御器・TPS 相機・Auto-Step）。玩家・相機・制御器は一切改変しない：
## Input.action_press("move_forward") と制御器自身の snap_yaw（向きを目標へ）だけで歩く（walk_w5c.gd と同じ方式）。
## capsule／BFS の標本ではなく、制御器の _physics_process（move_and_slide・自動跨ぎ）が実際に動いた結果を見る。
## 各脚（leg）：建物のローカル座標（lx＝立面に沿う、dz＝立面〔lz＝奥行/2〕から通り側へ）で出発点と目標点を与える。
##   along：立面に沿って建物の幅＋両側 3 m を端から端まで（near＝壁から 1.3 m〔小物帯 0.5 m の外〕／road＝3.0 m）
##   door ：入口の正面から壁へ向かって歩く（壁で止まるまで）。入口の前に障害がなければ、壁の手前 1.1 m 以内まで止まらずに着く
##   prop ：本ラウンドで碰撞を足した小物（薪・荷受け台・切り株など）の正面から壁へ向かって歩く。ON なら小物の手前で止まる（立面距離が大きい）／OFF なら壁まで
## 玩家の碰撞 capsule は main.tscn が実際に使う characters/yoriichi/player_yoriichi.tscn の半径（実行時に読む。scenes/player.tscn の 0.45 ではない）。
## 判定：along＝到達・接地喪失 0・停止（速度 < 0.3 m/s）の連続 12 フレーム以下／door＝最初の停止が立面距離 ≤ 1.1 m・接地喪失 0／
##        prop＝ON：停止の立面距離が『小物の碰撞箱の前面 + capsule 半径』（±0.08 m）で、小物の上へ登っていない（Δy ≤ 0.25 m）／
##             OFF（--disable）：小物の碰撞が無いので壁（碰撞 body の前面 = 立面）まで届く（停止 ≤ 半径 + 0.08 m）。
## 出力：<tag>_walk.json＋標準出力 [W9WALK] 行。--disable を付ければ同じ脚を overlay OFF（元の Kit）で歩く（比較用）。
## --shell-off：W9 FIX の外形碰撞箱（Shell）を無効にし body の元の箱を有効にする（修正前の碰撞・見た目は同じ）。
const B := {
	"074": {"pos": Vector2(230.58, -97.22), "yaw": -14.0, "w": 4.5013, "d": 10.92, "y": 1.52},
	"029": {"pos": Vector2(267.10, -70.26), "yaw": 73.3, "w": 6.9942, "d": 10.92, "y": 1.35},
	"014": {"pos": Vector2(191.09, -42.72), "yaw": 83.2, "w": 7.1971, "d": 10.92, "y": 1.18},
	# ── Phase 4（主街 7＋西巷 4・入口は Kit の door_cx）：pos＝bake の origin・yaw＝front_dir・y＝origin y ──
	"p4_RSW_024": {"pos": Vector2(211.654, -73.536), "yaw": -96.89, "w": 8.1000, "d": 10.92, "y": 1.370},
	"p4_RSW_025": {"pos": Vector2(210.499, -63.903), "yaw": -96.92, "w": 4.5000, "d": 10.92, "y": 1.303},
	"p4_RSW_026": {"pos": Vector2(209.620, -56.612), "yaw": -96.83, "w": 5.4000, "d": 10.92, "y": 1.262},
	"p4_RSW_012": {"pos": Vector2(193.316, -61.242), "yaw": 83.13, "w": 6.2900, "d": 10.92, "y": 1.290},
	"p4_MKT_001": {"pos": Vector2(244.821, 89.250), "yaw": -94.78, "w": 7.0000, "d": 10.92, "y": 0.390},
	"p4_MKT_004": {"pos": Vector2(255.576, 29.504), "yaw": -108.41, "w": 6.1000, "d": 10.92, "y": 0.758},
	"p4_MKT_005": {"pos": Vector2(258.311, 21.293), "yaw": -108.40, "w": 8.8000, "d": 10.92, "y": 0.815},
	"p4_MKT_015": {"pos": Vector2(293.443, -87.869), "yaw": -111.84, "w": 8.8100, "d": 10.92, "y": 1.473},
	"p4_MXC_001": {"pos": Vector2(298.659, -100.917), "yaw": -111.80, "w": 6.1000, "d": 10.92, "y": 1.544},
	"p4_MXC_002": {"pos": Vector2(301.167, -107.177), "yaw": -111.86, "w": 7.0000, "d": 10.92, "y": 1.584},
	"p4_MXC_004": {"pos": Vector2(306.424, -120.321), "yaw": -111.81, "w": 7.9000, "d": 10.92, "y": 1.700},
	# ── Phase 5（主街中段 2 棟）：pos／yaw＝body の実測（atan2(basis.z.x, basis.z.z)）・y＝body の y ──
	"p5_MKT_023": {"pos": Vector2(254.4828, -28.2123), "yaw": 73.21, "w": 5.2002, "d": 10.92, "y": 1.094},
	"p5_MKT_028": {"pos": Vector2(265.1548, -63.7873), "yaw": 73.32, "w": 6.1054, "d": 10.92, "y": 1.310},
	# ── W9 FIX（外形碰撞箱 Shell）：開いた見世・庭へ実際に歩いて入る（pos／yaw＝village_v2.tscn の body の transform）──
	"w9f_MXC_007": {"pos": Vector2(283.476, -114.419), "yaw": 68.19, "w": 7.9000, "d": 10.92, "y": 1.621},
	"w9f_MKT_025": {"pos": Vector2(258.776, -42.525), "yaw": 73.29, "w": 6.0960, "d": 10.92, "y": 1.182},
	"w9f_RSW_076": {"pos": Vector2(247.182, -93.074), "yaw": -14.06, "w": 6.3060, "d": 10.92, "y": 1.495},
}
## [名前, 建物, 種別, 出発 (lx, dz), 目標 (lx, dz), prop の碰撞箱の前面（立面から通り側へ m。Posts の z + 半幅 - 立面。generator の solid() と同じ値）]
const LEGS := [
	["074_along_near", "074", "along", Vector2(-5.2, 1.3), Vector2(5.2, 1.3), 0.0],
	["074_along_road", "074", "along", Vector2(-5.2, 3.0), Vector2(5.2, 3.0), 0.0],
	["074_door", "074", "door", Vector2(-0.45, 3.0), Vector2(-0.45, -0.6), 0.0],
	["074_woodpile", "074", "prop", Vector2(1.6, 3.0), Vector2(1.6, -0.6), 0.38],
	["074_tub", "074", "prop", Vector2(-1.8, 3.0), Vector2(-1.8, -0.6), 0.47],
	["029_along_near", "029", "along", Vector2(-6.5, 1.5), Vector2(6.5, 1.5), 0.0],
	["029_along_road", "029", "along", Vector2(-6.5, 3.2), Vector2(6.5, 3.2), 0.0],
	["029_door", "029", "door", Vector2(2.6, 3.2), Vector2(2.6, -0.6), 0.0],
	["029_platform", "029", "prop", Vector2(-2.0, 3.2), Vector2(-2.0, -0.6), 0.53],
	["014_along_near", "014", "along", Vector2(-6.6, 1.3), Vector2(6.6, 1.3), 0.0],
	["014_along_road", "014", "along", Vector2(-6.6, 3.0), Vector2(6.6, 3.0), 0.0],
	["014_door", "014", "door", Vector2(0.9, 3.0), Vector2(0.9, -0.6), 0.0],
	["014_anvil", "014", "prop", Vector2(-1.8, 3.0), Vector2(-1.8, -0.6), 0.47],
	["014_woodpile", "014", "prop", Vector2(2.6, 3.0), Vector2(2.6, -0.6), 0.33],
	# ── Phase 4：立面に沿う 2 本（壁際 1.3 m・道の中）＋入口の正面から壁へ ──
	["p4_RSW_024_along_near", "p4_RSW_024", "along", Vector2(-7.05, 1.3), Vector2(7.05, 1.3), 0.0],
	["p4_RSW_024_along_road", "p4_RSW_024", "along", Vector2(-7.05, 3.0), Vector2(7.05, 3.0), 0.0],
	["p4_RSW_024_door", "p4_RSW_024", "door", Vector2(1.35, 3.0), Vector2(1.35, -0.6), 0.0],
	["p4_RSW_025_along_near", "p4_RSW_025", "along", Vector2(-5.25, 1.3), Vector2(5.25, 1.3), 0.0],
	["p4_RSW_025_along_road", "p4_RSW_025", "along", Vector2(-5.25, 3.0), Vector2(5.25, 3.0), 0.0],
	["p4_RSW_025_door", "p4_RSW_025", "door", Vector2(-0.45, 3.0), Vector2(-0.45, -0.6), 0.0],
	["p4_RSW_026_along_near", "p4_RSW_026", "along", Vector2(-5.70, 1.3), Vector2(5.70, 1.3), 0.0],
	["p4_RSW_026_along_road", "p4_RSW_026", "along", Vector2(-5.70, 3.0), Vector2(5.70, 3.0), 0.0],
	["p4_RSW_026_door", "p4_RSW_026", "door", Vector2(1.8, 3.0), Vector2(1.8, -0.6), 0.0],
	["p4_RSW_012_along_near", "p4_RSW_012", "along", Vector2(-6.14, 1.3), Vector2(6.14, 1.3), 0.0],
	["p4_RSW_012_along_road", "p4_RSW_012", "along", Vector2(-6.14, 3.0), Vector2(6.14, 3.0), 0.0],
	["p4_RSW_012_door", "p4_RSW_012", "door", Vector2(-0.45, 3.0), Vector2(-0.45, -0.6), 0.0],
	["p4_MKT_001_along_near", "p4_MKT_001", "along", Vector2(-6.50, 1.3), Vector2(6.50, 1.3), 0.0],
	["p4_MKT_001_along_road", "p4_MKT_001", "along", Vector2(-6.50, 3.2), Vector2(6.50, 3.2), 0.0],
	["p4_MKT_001_door", "p4_MKT_001", "door", Vector2(0.88, 3.2), Vector2(0.88, -0.6), 0.0],
	["p4_MKT_004_along_near", "p4_MKT_004", "along", Vector2(-6.05, 1.3), Vector2(6.05, 1.3), 0.0],
	["p4_MKT_004_along_road", "p4_MKT_004", "along", Vector2(-6.05, 3.2), Vector2(6.05, 3.2), 0.0],
	["p4_MKT_004_door", "p4_MKT_004", "door", Vector2(2.18, 3.2), Vector2(2.18, -0.6), 0.0],
	["p4_MKT_005_along_near", "p4_MKT_005", "along", Vector2(-7.40, 1.3), Vector2(7.40, 1.3), 0.0],
	["p4_MKT_005_along_road", "p4_MKT_005", "along", Vector2(-7.40, 3.2), Vector2(7.40, 3.2), 0.0],
	["p4_MKT_005_door", "p4_MKT_005", "door", Vector2(-1.76, 3.2), Vector2(-1.76, -0.6), 0.0],
	["p4_MKT_015_along_near", "p4_MKT_015", "along", Vector2(-7.41, 1.3), Vector2(7.41, 1.3), 0.0],
	["p4_MKT_015_along_road", "p4_MKT_015", "along", Vector2(-7.41, 3.2), Vector2(7.41, 3.2), 0.0],
	["p4_MKT_015_door", "p4_MKT_015", "door", Vector2(-1.76, 3.2), Vector2(-1.76, -0.6), 0.0],
	["p4_MXC_001_along_near", "p4_MXC_001", "along", Vector2(-6.05, 1.3), Vector2(6.05, 1.3), 0.0],
	["p4_MXC_001_along_road", "p4_MXC_001", "along", Vector2(-6.05, 3.2), Vector2(6.05, 3.2), 0.0],
	["p4_MXC_001_door", "p4_MXC_001", "door", Vector2(0.44, 3.2), Vector2(0.44, -0.6), 0.0],
	["p4_MXC_002_along_near", "p4_MXC_002", "along", Vector2(-6.50, 1.3), Vector2(6.50, 1.3), 0.0],
	["p4_MXC_002_along_road", "p4_MXC_002", "along", Vector2(-6.50, 3.2), Vector2(6.50, 3.2), 0.0],
	["p4_MXC_002_door", "p4_MXC_002", "door", Vector2(-0.88, 3.2), Vector2(-0.88, -0.6), 0.0],
	["p4_MXC_004_along_near", "p4_MXC_004", "along", Vector2(-6.95, 1.3), Vector2(6.95, 1.3), 0.0],
	["p4_MXC_004_along_road", "p4_MXC_004", "along", Vector2(-6.95, 3.2), Vector2(6.95, 3.2), 0.0],
	# W9 FIX 最終驗收（Decision 2）：MXC_004 の戸口は立面から 1.46 m 凹み（見た目の側柱 lx 0.62／2.02・奥の壁 立面 −1.46）、
	# 凹みの床は地面から 0.41 m（step_height 0.35 より高い）。旧 'door'（立面 1.1 m 以内で止まれば合格・目標 −0.6）は凹みの実形と合わず
	# timeout していた。期待値は『見た目の面 ± 半径』±0.08（stopz／stopx）・凹みの中の脚は床の上に置く（7 番目 true）。
	["p4_MXC_004_door", "p4_MXC_004", "stopz", Vector2(1.32, 3.2), Vector2(1.32, -3.0), 0.0],
	["p4_MXC_004_recess_back", "p4_MXC_004", "stopz", Vector2(1.32, -0.35), Vector2(1.32, -3.0), -1.46, true],
	["p4_MXC_004_recess_left", "p4_MXC_004", "stopx", Vector2(1.32, -0.75), Vector2(-1.5, -0.75), 0.62, true],
	["p4_MXC_004_recess_right", "p4_MXC_004", "stopx", Vector2(1.32, -0.75), Vector2(4.0, -0.75), 2.02, true],
	["p4_MXC_004_recess_exit", "p4_MXC_004", "exit", Vector2(1.32, -0.75), Vector2(1.32, 3.2), 0.0, true],
	# ── Phase 4 R1b（B1）：木戸を宅間の奥へ移した後、巷の口（四つ目垣の切れ目）から庭へ実際に歩いて入れる（lx＝R1 の木戸の中心）
	["p4b_gap_024_025_in", "p4_RSW_025", "along", Vector2(-4.13, 3.0), Vector2(-4.13, -3.5), 0.0],
	["p4b_gap_014_013_in", "014", "along", Vector2(6.30, 3.0), Vector2(6.30, -3.5), 0.0],
	# ── Phase 5：023 の前は P10 封存の大幟（立面から 0.7–1.8 m）・看板・提灯綱の竿が立つので、沿う脚は 2.0 m／3.4 m ──
	["p5_MKT_023_along_near", "p5_MKT_023", "along", Vector2(-5.6, 2.0), Vector2(5.6, 2.0), 0.0],
	["p5_MKT_023_along_road", "p5_MKT_023", "along", Vector2(-5.6, 3.4), Vector2(5.6, 3.4), 0.0],
	["p5_MKT_023_door", "p5_MKT_023", "door", Vector2(0.0, 3.4), Vector2(0.0, -0.6), 0.0],
	["p5_MKT_028_along_near", "p5_MKT_028", "along", Vector2(-6.05, 1.3), Vector2(6.05, 1.3), 0.0],
	["p5_MKT_028_along_road", "p5_MKT_028", "along", Vector2(-6.05, 3.0), Vector2(6.05, 3.0), 0.0],
	["p5_MKT_028_door", "p5_MKT_028", "door", Vector2(0.436, 3.0), Vector2(0.436, -0.6), 0.0],
	# ── W9 FIX：見世の奥へ（台の間＝奥の壁 z 1.9／台の前 z 4.8）・開いた正面の台の前・裏庭へ横から ──
	["w9f_MXC_007_porch_gap", "w9f_MXC_007", "door", Vector2(0.35, 3.0), Vector2(0.35, -4.5), 0.0],
	["w9f_MXC_007_porch_table", "w9f_MXC_007", "door", Vector2(-1.7, 3.0), Vector2(-1.7, -4.5), 0.0],
	["w9f_MKT_025_front", "w9f_MKT_025", "door", Vector2(-2.0, 3.2), Vector2(-2.0, -4.0), 0.0],
	["w9f_RSW_076_yard_in", "w9f_RSW_076", "along", Vector2(-5.5, -8.5), Vector2(-1.7, -8.5), 0.0],
]
const STALL_FRAMES := 30          # 速度 < 0.3 m/s が連続してこの数に達したら、その脚は止まったとみなす（0.5 s）
const TIMEOUT_MS := 25000
const BLOCK_SPEED := 0.3

var _tag := ""
var _results: Array = []
var _fails := 0
var _off := false          # --disable 付き（overlay OFF = 元の Kit）
var _r := 0.3              # 玩家 capsule の半径（_run で実機の値を読む）


func _yaw(k: String) -> float:
	return deg_to_rad(float((B[k] as Dictionary)["yaw"]))


## 庇の板・屋根の下（戸口の凹みの中）へ置く：_tpw は y 80 から当てるので屋根の上に乗る。局部 +1.6 m から下へ当てた最初の面に置く
func _tpw_under(k: String, p: Vector2, face: Vector2) -> void:
	Input.action_release("move_forward")
	var sp := player.get_world_3d().direct_space_state
	var y0 := float((B[k] as Dictionary)["y"]) + 1.6
	var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, y0, p.y), Vector3(p.x, y0 - 4.0, p.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	var gy := float((r["position"] as Vector3).y) if not r.is_empty() else y0 - 1.6
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, gy + 0.1, p.y)
	player.call("snap_yaw", atan2(-face.x, -face.y))
	_fix_camera()
	await _frames(4)
	for i in 40:
		await physics_frame
	await _frames(20)


## 建物ローカル (lx, dz) → 世界 (x, z)。dz＝立面（lz＝奥行/2）から通り側へ。
func _w(k: String, lx: float, dz: float) -> Vector2:
	var b: Dictionary = B[k]
	var yaw := _yaw(k)
	var lz := float(b["d"]) * 0.5 + dz
	var o: Vector2 = b["pos"]
	return Vector2(o.x + lx * cos(yaw) + lz * sin(yaw), o.y - lx * sin(yaw) + lz * cos(yaw))


## 世界 (x, z) → 立面からの距離（通り側が +）と立面に沿う座標 lx
func _local(k: String, p: Vector2) -> Vector2:
	var b: Dictionary = B[k]
	var yaw := _yaw(k)
	var o: Vector2 = b["pos"]
	var d := p - o
	return Vector2(d.dot(Vector2(cos(yaw), -sin(yaw))), d.dot(Vector2(sin(yaw), cos(yaw))) - float(b["d"]) * 0.5)


func _leg(lg: Array) -> void:
	var name: String = lg[0]
	var k: String = lg[1]
	var kind: String = lg[2]
	var a: Vector2 = lg[3]
	var z: Vector2 = lg[4]
	var front: float = lg[5]
	var p0 := _w(k, a.x, a.y)
	var p1 := _w(k, z.x, z.y)
	if lg.size() > 6 and bool(lg[6]):
		await _tpw_under(k, p0, (p1 - p0).normalized())
	else:
		await _tpw(p0, (p1 - p0).normalized())
	var start := player.global_position
	var gy_off := start.y - float((B[k] as Dictionary)["y"])
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press("move_forward")
	var n := 0
	var blocked := 0
	var run := 0
	var max_run := 0
	var lost := 0
	var max_dy := 0.0
	var first_stall := Vector2(NAN, NAN)   # 最初に STALL_FRAMES 続けて止まった位置（lx, 立面距離）
	var reached := false
	var prev := start
	var t0 := Time.get_ticks_msec()
	var stop := ""
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var dv := p1 - q
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
				first_stall = _local(k, q)
		else:
			run = 0
		max_dy = maxf(max_dy, absf(pp.y - prev.y))
		prev = pp
		if not player.is_on_floor():
			lost += 1
		if (kind == "along" or kind == "exit") and d <= 0.35:
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
	var el := _local(k, Vector2(end.x, end.z))
	var ok := true
	var verdict := ""
	match kind:
		"along":
			ok = reached and lost == 0 and max_run <= 12 and max_dy <= 0.25
			verdict = "到達" if reached else "未到達（停止 lx %.2f 立面 %.2f）" % [el.x, el.y]
		"door":
			ok = lost == 0 and not is_nan(first_stall.y) and first_stall.y <= 1.1 and max_dy <= 0.25
			verdict = "壁の手前 %.2f m まで着いた" % el.y
		"stopz", "stopx":
			# 見た目の面（front）＋半径で止まる（進む向きの手前側）。±0.08
			var along_z := kind == "stopz"
			var dirs := signf((z.y - a.y) if along_z else (z.x - a.x))
			var want2 := front - dirs * _r
			var got: float = first_stall.y if along_z else first_stall.x
			ok = lost == 0 and not is_nan(got) and absf(got - want2) <= 0.08 and max_dy <= 0.25
			verdict = "最初の停止 %s %.2f（期待 見た目の面 %.2f %s 半径 %.2f ＝ %.2f ±0.08）" % ["立面" if along_z else "lx", got, front, "+" if dirs < 0 else "−", _r, want2]
		"exit":
			ok = reached and lost <= 30 and max_run <= 12
			verdict = "出られた（床から降りる間の非接地 %d フレーム）" % lost if reached else "出られない（停止 lx %.2f 立面 %.2f）" % [el.x, el.y]
		"prop":
			var climbed := end.y - start.y
			var want := _r if _off else front + _r         # OFF＝壁まで／ON＝小物の碰撞箱の前面で止まる
			ok = lost == 0 and climbed <= 0.25 and absf(el.y - want) <= 0.08
			verdict = "停止 立面 %.2f m・上昇 %+.2f m（期待 %.2f ±0.08：%s）" % [el.y, climbed, want, "OFF＝壁" if _off else "小物の前面 %.2f + 半径 %.2f" % [front, _r]]
	var row := {
		"leg": name, "kind": kind, "stop": stop, "ok": ok, "frames": n, "blocked_frames": blocked, "max_stall_run": max_run,
		"lost_floor": lost, "max_dy_frame": snappedf(max_dy, 0.0001), "end_lx": snappedf(el.x, 0.01), "end_facade_dist": snappedf(el.y, 0.01),
		"first_stall_lx": snappedf(first_stall.x, 0.01) if not is_nan(first_stall.x) else null,
		"first_stall_facade": snappedf(first_stall.y, 0.01) if not is_nan(first_stall.y) else null,
		"dy_total": snappedf(end.y - start.y, 0.001), "start_ground_vs_bldg": snappedf(gy_off, 0.01),
	}
	_results.append(row)
	if not ok:
		_fails += 1
	print("[W9WALK] %s %-16s %s stop=%s frames=%d blocked=%d max_run=%d lost=%d max_dy=%.4f end(lx %.2f, 立面 %.2f) start地面差 %+.2f  → %s" % [
		"PASS" if ok else "FAIL", name, kind, stop, n, blocked, max_run, lost, max_dy, el.x, el.y, gy_off, verdict])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag = args[1]
	var disables: Array = []
	var only: PackedStringArray = []
	for a: String in args:
		if a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
		elif a.begins_with("--only="):          # 脚名の接頭辞（カンマ区切り）で絞る（Phase 4 R1b）
			only = a.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	_off = not disables.is_empty()
	var cs := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		_r = (cs.shape as CapsuleShape3D).radius
		print("[W9WALK] 玩家 capsule 半径 %.2f・高さ %.2f（player_yoriichi.tscn）" % [_r, (cs.shape as CapsuleShape3D).height])
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			if "enabled" in dnode:
				dnode.set("enabled", false)
			else:
				(dnode as Node3D).visible = false
			print("[W9WALK] disabled ", dn)
		else:
			print("[W9WALK] disable: node not found ", dn)
	if "--shell-off" in args:
		# 修正前の碰撞構成（W9 FIX の Shell を無効・body の元の箱を有効。見た目は同じ W9R2）
		for b in vil.get_node("ArchW9R2P13").get_children():
			var sh := b.get_node_or_null("Shell")
			if sh == null:
				continue
			for c in vil.get_node(NodePath(String(b.get_meta("body_path")))).get_children():
				if c is CollisionShape3D:
					(c as CollisionShape3D).disabled = false
			for c in sh.get_children():
				(c as CollisionShape3D).disabled = true
		print("[W9WALK] shell-off（修正前の碰撞）")
	await _frames(6)
	var ov := vil.get_node_or_null("ArchW9R2P13")
	print("[W9WALK] tag=%s overlay=%s enabled=%s" % [_tag, "あり" if ov != null else "なし", str(ov.get("enabled")) if ov != null else "-"])
	for lg: Array in LEGS:
		if not only.is_empty() and not Array(only).any(func(pre: String) -> bool: return String(lg[0]).begins_with(pre)):
			continue
		await _leg(lg)
	var f := FileAccess.open(out + _tag + "_walk.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": _tag, "legs": _results, "fails": _fails}, "\t") + "\n")
	f.close()
	print("[W9WALK] 結果：%d 脚・FAIL %d" % [_results.size(), _fails])
	quit(1 if _fails > 0 else 0)
