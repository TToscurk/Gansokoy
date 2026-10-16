extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 4 B1 診断（唯読・場景は書かない）：西巷の SpringArm の縮みを『どの構件の碰撞形状』が起こしたかを形状単位で集計する。
##   godot --headless --path godot --script res://tools/p13/p4/diag_lane_arm.gd -- <out.json> [--lane=ox,oz,sx,sz --s0=0 --s1=50 --step=0.5]
## 腕の ray は arm_sweep_w9p3.gd と同じ規約（起点＝足元 +1.70 m、背後・仰角 sin 0.179、最大 7.5 m、mask＝SpringArm、玩家 RID 除外）。
## 比較の基準は『Phase 4 の前』＝EnrichW9P4 の碰撞だけを除いた ray（同じ地点・同じ向き）。
const ARM_UP := 1.70
const ARM_SIN := 0.179
const ARM_MAX := 7.5
const OV := "EnrichW9P4"
var LANE_O := Vector2(204.0, -80.0)
var LANE_S := Vector2(-0.119, 0.993).normalized()
var LANE_N := Vector2(0.993, 0.119)
var _space: PhysicsDirectSpaceState3D
var _arm: SpringArm3D
var _pl_rid: RID
var _ov_rids: Array = []


func _back(yaw: float) -> Vector3:
	var fc := Vector2(sin(yaw), -cos(yaw))
	var cc := sqrt(1.0 - ARM_SIN * ARM_SIN)
	return Vector3(-fc.x * cc, ARM_SIN, -fc.y * cc)


func _shape_name(r: Dictionary) -> String:
	var co := r["collider"] as CollisionObject3D
	if co == null:
		return "?"
	var p := String(vil.get_path_to(co))
	if not p.begins_with(OV):
		return "(other)" + p.substr(0, 40)
	var own := co.shape_find_owner(int(r["shape"]))
	var n := co.shape_owner_get_owner(own) as Node
	return String(n.name) if n else "?"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_json: String = args[0]
	var s0 := 0.0
	var s1 := 50.0
	var step := 0.5
	for a: String in args:
		if a.begins_with("--s0="):
			s0 = float(a.trim_prefix("--s0="))
		elif a.begins_with("--s1="):
			s1 = float(a.trim_prefix("--s1="))
		elif a.begins_with("--step="):
			step = float(a.trim_prefix("--step="))
		elif a.begins_with("--lane="):
			var lq := a.trim_prefix("--lane=").split(",")
			LANE_O = Vector2(float(lq[0]), float(lq[1]))
			LANE_S = Vector2(float(lq[2]), float(lq[3])).normalized()
			LANE_N = Vector2(-LANE_S.y, LANE_S.x)
	out = ""
	await _boot()
	await _frames(8)
	_arm = player.get_node("Pivot/SpringArm3D") as SpringArm3D
	_space = player.get_world_3d().direct_space_state
	_pl_rid = player.get_rid()
	var ov := vil.get_node_or_null(OV)
	var shapes := {}
	if ov != null:
		for c in ov.find_children("*", "CollisionObject3D", true, false):
			_ov_rids.append((c as CollisionObject3D).get_rid())
		for cs in ov.find_children("*", "CollisionShape3D", true, false):
			var g := cs as CollisionShape3D
			var sz := Vector3.ZERO
			if g.shape is BoxShape3D:
				sz = (g.shape as BoxShape3D).size
			elif g.shape is CylinderShape3D:
				sz = Vector3((g.shape as CylinderShape3D).radius * 2.0, (g.shape as CylinderShape3D).height, 0.0)
			var gp := g.global_position
			var gy := _ground(Vector2(gp.x, gp.z))
			shapes[String(g.name)] = {"c": [snappedf(gp.x, 0.01), snappedf(gp.y, 0.01), snappedf(gp.z, 0.01)], "size": [snappedf(sz.x, 0.01), snappedf(sz.y, 0.01), snappedf(sz.z, 0.01)],
				"top_over_ground": snappedf(gp.y + sz.y * 0.5 - gy, 0.01), "yaw_deg": snappedf(rad_to_deg(g.global_transform.basis.get_euler().y), 0.1)}
	print("[DLA] EnrichW9P4 collision shapes: %d  arm mask=%d" % [shapes.size(), _arm.collision_mask])
	var offs := [-1.2, -0.6, 0.0, 0.6, 1.2]
	var n_s := int((s1 - s0) / step) + 1
	var by := {}
	var hist := {"0.3-1": 0, "1-2": 0, "2-3": 0, "3-4": 0, "4+": 0}
	var total := 0
	var samples: Array = []
	for yi in 16:
		var yaw := TAU * float(yi) / 16.0
		for oi in offs:
			for k in n_s:
				var s := s0 + k * step
				var pw := LANE_O + LANE_S * s + LANE_N * float(oi)
				var gy := _ground(pw)
				var o3 := Vector3(pw.x, gy + ARM_UP, pw.y)
				var to := o3 + _back(yaw) * ARM_MAX
				var r := _space.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, _arm.collision_mask, [_pl_rid]))
				var ex: Array = [_pl_rid]
				ex.append_array(_ov_rids)
				var r2 := _space.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, _arm.collision_mask, ex))
				var now := ARM_MAX if r.is_empty() else o3.distance_to(r["position"] as Vector3)
				var pre := ARM_MAX if r2.is_empty() else o3.distance_to(r2["position"] as Vector3)
				var loss := pre - now
				total += 1
				if loss < 0.30:
					continue
				var hk := "0.3-1" if loss < 1.0 else ("1-2" if loss < 2.0 else ("2-3" if loss < 3.0 else ("3-4" if loss < 4.0 else "4+")))
				hist[hk] = int(hist[hk]) + 1
				var nm := _shape_name(r)
				var rec: Dictionary = by.get(nm, {"n": 0, "n_ge2": 0, "max": 0.0, "worst": {}})
				rec["n"] = int(rec["n"]) + 1
				if loss >= 2.0:
					rec["n_ge2"] = int(rec["n_ge2"]) + 1
				var smp := {"p": [snappedf(pw.x, 0.01), snappedf(pw.y, 0.01)], "s": s, "o": oi, "yaw_deg": snappedf(rad_to_deg(yaw), 0.1), "pre": snappedf(pre, 0.01), "now": snappedf(now, 0.01), "loss": snappedf(loss, 0.01),
					"hit": [snappedf((r["position"] as Vector3).x, 0.01), snappedf((r["position"] as Vector3).y - gy, 0.01), snappedf((r["position"] as Vector3).z, 0.01)], "shape": nm}
				if loss > float(rec["max"]):
					rec["max"] = snappedf(loss, 0.01)
					rec["worst"] = smp
				by[nm] = rec
				samples.append(smp)
	print("[DLA] samples=%d  loss>=0.30: %d  hist=%s" % [total, samples.size(), JSON.stringify(hist)])
	var keys := by.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(by[a]["n"]) > int(by[b]["n"]))
	for k: String in keys:
		var rec: Dictionary = by[k]
		print("[DLA]  %-34s n=%3d  n>=2m=%3d  max=%.2f  shape=%s  worst=%s" % [k, int(rec["n"]), int(rec["n_ge2"]), float(rec["max"]), JSON.stringify(shapes.get(k, {})), JSON.stringify(rec["worst"])])
	var f := FileAccess.open(out_json, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"lane": {"o": [LANE_O.x, LANE_O.y], "s": [LANE_S.x, LANE_S.y], "s0": s0, "s1": s1, "step": step}, "total": total, "hist": hist, "by_shape": by, "shapes": shapes, "samples": samples}, "  ") + "\n")
		f.close()
	else:
		printerr("[DLA] cannot write ", out_json)
	quit(0)
