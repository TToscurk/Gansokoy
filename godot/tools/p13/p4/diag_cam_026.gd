extends SceneTree
## P13 W9 Phase 4 R1b B2 診断（唯読・場景は書かない）：RSW_026 のせり出し二階・屋根裏に TPS 相機が入り込むか（相機貫入）を BEFORE／AFTER の形で数える。
##   godot --headless --path godot --script res://tools/p13/p4/diag_cam_026.gd -- [--arm=8.5]
## 026 の body 碰撞は Kit の箱（局部 y −0.34..2.90）のまま。見える二階・せり出し・屋根裏は碰撞を持たないので、
## 巷の上の玩家位置（西巷の直線 s 0..50 m × 横 −2.4..2.4 m × 16 方位）から実際の SpringArm と同じ ray（起点 足元+1.70 m・仰角 sin 0.179・mask 1）を飛ばし、
## 相機の位置（腕の先 − margin 0.2 m ＋ 肩の offset (0.40, 0.10)）が 026 の『碰撞の外にある見える体積』の中（0.10 m の余裕込み）に入る件数を数える。
## 体積は build_w9p4_arch.py の値：R1＝せり出し 0.38 m・壁 4.7 m・勾配 0.62・せり出し下端 2.72 m／R1b＝0.90 m・5.1 m・0.80・下端 3.02 m（出桁の下端）。
## 相機の ray は 026 の見た目に依存しない（碰撞は不変）ので、同じ ray の結果を二つの体積で判定すれば BEFORE／AFTER の比較になる。
const BODY := "Districts/ResidentialWest/Buildings/B_P_RSW_026"
const W := 5.4
const ZF := 5.46
const COL_TOP := 2.90
const VOL := {"R1": {"out": 0.38, "ye": 4.7, "p": 0.62, "under": 2.72}, "R1b": {"out": 0.90, "ye": 5.1, "p": 0.80, "under": 3.02}}
const ARM_UP := 1.70
const ARM_SIN := 0.179
const MARGIN := 0.2
const SHOULDER := Vector3(0.40, 0.10, 0.0)
const INFL := 0.10
var LANE_O := Vector2(204.0, -80.0)
var LANE_S := Vector2(-0.119, 0.993).normalized()


func _init() -> void:
	_run.call_deferred()


func _inside(v: Dictionary, q: Vector3) -> bool:
	var hx := W * 0.5 + INFL
	if absf(q.x) > hx:
		return false
	var zc: float = ZF + float(v["out"])
	if q.z < -ZF - INFL or q.z > zc + INFL:
		return false
	var roof: float = float(v["ye"]) + float(v["p"]) * maxf(0.0, W * 0.5 - absf(q.x)) + INFL
	if q.y > roof:
		return false
	if q.z <= ZF:
		return q.y > COL_TOP - INFL          # 本体の上（碰撞の箱より上の二階・屋根裏）
	return q.y > float(v["under"]) - INFL     # せり出しの下端より上（碰撞の箱の前）


func _run() -> void:
	var arm_max := 8.5
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--arm="):
			arm_max = float(a.trim_prefix("--arm="))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var body := v.get_node(BODY) as Node3D
	var inv := body.global_transform.affine_inverse()
	var sp := v.get_world_3d().direct_space_state
	var n := 0
	var cnt := {"R1": 0, "R1b": 0}
	var cnt_band := {"R1": 0, "R1b": 0}
	var ex := {"R1": [], "R1b": []}
	var n_band := 0
	var n_prop := 0
	var near026 := 0
	var LANE_N := Vector2(-LANE_S.y, LANE_S.x)
	for yi in 16:
		var yaw := TAU * float(yi) / 16.0
		var fc := Vector2(sin(yaw), -cos(yaw))
		var cc := sqrt(1.0 - ARM_SIN * ARM_SIN)
		var back := Vector3(-fc.x * cc, ARM_SIN, -fc.y * cc)
		var right := Vector3(-fc.y, 0.0, fc.x).normalized()   # 玩家の右（相機の肩 offset の向き）
		for oi in 9:
			var o := -2.4 + 0.6 * oi
			for k in 101:
				var s := 0.5 * k
				var pw := LANE_O + LANE_S * s + LANE_N * o
				var rg := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(pw.x, 60.0, pw.y), Vector3(pw.x, -20.0, pw.y), 1))
				if rg.is_empty():
					continue
				var gpath := String(v.get_path_to(rg["collider"] as Node))
				if not (gpath.begins_with("Collision/") or gpath.begins_with("Roads")):
					n_prop += 1          # 小物・建物の上（立てない地点）は数えない
					continue
				var gy := float((rg["position"] as Vector3).y)
				var o3 := Vector3(pw.x, gy + ARM_UP, pw.y)
				var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o3, o3 + back * arm_max, 1))
				var ln := arm_max if r.is_empty() else o3.distance_to(r["position"] as Vector3)
				var cam := o3 + back * maxf(0.0, ln - MARGIN) + right * SHOULDER.x + Vector3.UP * SHOULDER.y
				n += 1
				var band := absf(o) <= 1.21
				if band:
					n_band += 1
				var ql := inv * cam
				if ql.length() < 12.0:
					near026 += 1
				for key: String in VOL:
					if _inside(VOL[key], ql):
						cnt[key] = int(cnt[key]) + 1
						if band:
							cnt_band[key] = int(cnt_band[key]) + 1
						if (ex[key] as Array).size() < 6:
							(ex[key] as Array).append({"p": [snappedf(pw.x, 0.01), snappedf(pw.y, 0.01)], "yaw": snappedf(rad_to_deg(yaw), 0.1), "cam_local": [snappedf(ql.x, 0.01), snappedf(ql.y, 0.01), snappedf(ql.z, 0.01)], "arm": snappedf(ln, 0.01)})
	print("[DC26] arm_max=%.1f  samples=%d（通行帯 ±1.2 m：%d・小物の上で除外 %d）  相機が 026 の 12 m 以内=%d" % [arm_max, n, n_band, n_prop, near026])
	for key: String in VOL:
		print("[DC26] %s 体積（%s）：相機が碰撞の外の見える体積に入る件数 全体 %d・通行帯（軸 ±1.2 m）%d  例 %s" % [key, JSON.stringify(VOL[key]), int(cnt[key]), int(cnt_band[key]), JSON.stringify((ex[key] as Array).slice(0, 3))])
	quit(0)
