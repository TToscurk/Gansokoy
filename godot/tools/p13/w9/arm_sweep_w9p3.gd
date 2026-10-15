extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 3 R2：SpringArm の悪化量を『巷全体』で測る＋ gate（場景は書かない）。
##   godot --path . --script res://tools/p13/w9/arm_sweep_w9p3.gd -- <out.json> [--s0=-17 --s1=17 --step=0.25]      ：巷全体の格子 sweep（JSON に保存）
##   godot --path . --script res://tools/p13/w9/arm_sweep_w9p3.gd -- <out.json> --gate                              ：sweep ＋ 071 の柴棚の gate ＋ 反向案例
##   godot --path . --script res://tools/p13/w9/arm_sweep_w9p3.gd -- <out.json> "--probe=x,z,yaw_deg;…"          ：その地点の腕の ray を詳しく出す（診断）
## 巷のフレーム（B3 と同じ）：O＝(234.8, −87.8)、s＝東へ(0.97, 0.24)、o＝南へ(−0.24, 0.97)。
## 玩家を 16 方位（22.5° 刻み）に向けて格子に置いたときの『腕の先端』を、実際の SpringArm と同じ条件
##   起点＝足元 +1.70 m（diag_arm の実測）、方向＝玩家の向きの背後・仰角 sin=0.179（既定の俯仰 −0.18 rad）、mask=1、玩家の RID を除外
## で ray 照会し、(a) 全碰撞あり と (b) ArchW9R2P13／EnrichW9P3 の碰撞を除いた基準（＝overlay が無い元の場景）を比べる。
##   悪化 = 基準の腕長 − 全碰撞ありの腕長。≥ 0.30 m を『目立つ悪化』として数え、原因の碰撞（建物 ID）別に集計する。
## 腕の最大長は 7.5 m 級（player_yoriichi.tscn の spring_length 既定）。カメラ・玩家・main は読むだけ。
const ARM_UP := 1.70
const ARM_SIN := 0.179
const ARM_MAX := 7.5
const WORSE := 0.30
var LANE_O := Vector2(234.8, -87.8)
var LANE_S := Vector2(0.97, 0.24)
var LANE_N := Vector2(-0.24, 0.97)
const BT3 := [Vector2(235.8, -87.6), Vector2(236.4, -90.1)]
const BT4 := [Vector2(245.2, -85.3), Vector2(245.9, -87.8)]
const BODY_071 := "Districts/ResidentialWest/Buildings/B_P_RSW_071"
const OV_071 := "ArchW9R2P13/B_P_RSW_071"
## R1 の庇柱（bce7cf4 の modules_blender.json の posts）：局部 x −3.3655／−1.94775／−0.53・z 6.53・top 2.478・w 0.14。
##   碰撞は build_w9r2.gd と同じ式：半幅＝max(w/2＋POST_PAD, 0.125)＝0.125（箱 0.25 m 角）・中心 (x, top/2, z)・layer／mask は建物 body と同じ。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const NEG_OWNER := "NEG/R1_posts"
const R1_POSTS := [[-3.3655, 6.53], [-1.94775, 6.53], [-0.53, 6.53]]

var _pass := 0
var _fail := 0
var _ov_rids: Array = []
var _pl_rid: RID
var _arm: SpringArm3D
var _space: PhysicsDirectSpaceState3D


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[ARMSW] PASS ", msg)
	else:
		_fail += 1
		print("[ARMSW] FAIL ", msg)


func _owner_of(col: Node) -> String:
	if col.name.begins_with("_neg_post"):
		return NEG_OWNER
	var p := String(vil.get_path_to(col))
	var seg := p.split("/")
	if seg.size() >= 2 and (seg[0] == "ArchW9R2P13" or seg[0] == "EnrichW9P3" or seg[0] == "EnrichW9P4"):
		return "%s/%s" % [seg[0], seg[1]]
	return "(base)"


func _back(yaw: float) -> Vector3:
	var fc := Vector2(sin(yaw), -cos(yaw))            # yaw=0 → −z（北）
	var cc := sqrt(1.0 - ARM_SIN * ARM_SIN)
	return Vector3(-fc.x * cc, ARM_SIN, -fc.y * cc)


## 1 地点の腕：[全碰撞の腕長, 誰, 基準の腕長]
func _arm_at(pw: Vector2, yaw: float) -> Array:
	var gy := _ground(pw)
	var o3 := Vector3(pw.x, gy + ARM_UP, pw.y)
	var to := o3 + _back(yaw) * ARM_MAX
	var r := _space.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, _arm.collision_mask, [_pl_rid]))
	var len_all := ARM_MAX
	var who := ""
	if not r.is_empty():
		len_all = o3.distance_to(r["position"] as Vector3)
		who = _owner_of(r["collider"] as Node)
	var ex: Array = [_pl_rid]
	ex.append_array(_ov_rids)
	var r2 := _space.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, _arm.collision_mask, ex))
	var len_base := ARM_MAX if r2.is_empty() else o3.distance_to(r2["position"] as Vector3)
	return [len_all, who, len_base]


func _sweep(s0: float, s1: float, step: float) -> Dictionary:
	var n_s := int((s1 - s0) / step) + 1
	var offs := [-1.2, -0.6, 0.0, 0.6, 1.2]
	var total := 0
	var worse := 0
	var worst: Array = []
	var by_owner := {}
	var sum_loss := 0.0
	for yi in 16:
		var yaw := TAU * float(yi) / 16.0
		for oi in offs:
			for k in n_s:
				var s := s0 + k * step
				var pw := LANE_O + LANE_S * s + LANE_N * float(oi)
				var a := _arm_at(pw, yaw)
				var loss: float = float(a[2]) - float(a[0])
				total += 1
				if loss > 0.001:
					sum_loss += loss
				if loss >= WORSE:
					worse += 1
					var who: String = String(a[1])
					var rec: Dictionary = by_owner.get(who, {"n": 0, "max": 0.0})
					rec["n"] = int(rec["n"]) + 1
					rec["max"] = maxf(float(rec["max"]), loss)
					by_owner[who] = rec
					worst.append({"loss": snappedf(loss, 0.001), "who": who, "p": [snappedf(pw.x, 0.01), snappedf(pw.y, 0.01)], "yaw_deg": snappedf(rad_to_deg(yaw), 0.1), "base": snappedf(float(a[2]), 0.001), "now": snappedf(float(a[0]), 0.001), "s": snappedf(s, 0.01), "o": oi})
	worst.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["loss"]) > float(y["loss"]))
	return {"samples": total, "worse_ge_%.2f" % WORSE: worse, "worse_pct": snappedf(100.0 * float(worse) / float(total), 0.01), "mean_loss_m": snappedf(sum_loss / float(total), 0.0001),
		"by_owner": by_owner, "worst10": worst.slice(0, 10), "lane": {"s0": s0, "s1": s1, "step": step, "offsets_o": offs, "yaws": 16}}


func _yaw_of(a: Vector2, b: Vector2) -> float:
	var d := b - a
	return atan2(d.x, -d.y)


func _print_summary(sm: Dictionary) -> void:
	print("[ARMSW] samples=%d  悪化(≥%.2f m)=%d (%.2f %%)  平均悪化=%.4f m" % [int(sm["samples"]), WORSE, int(sm["worse_ge_%.2f" % WORSE]), float(sm["worse_pct"]), float(sm["mean_loss_m"])])
	var bo: Dictionary = sm["by_owner"]
	for k: String in bo:
		print("[ARMSW]   原因 %-34s n=%d  最大 %.3f m" % [k, int((bo[k] as Dictionary)["n"]), float((bo[k] as Dictionary)["max"])])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_json: String = args[0]
	var s0 := -17.0
	var s1 := 17.0
	var step := 0.25
	var gate := false
	var probes := ""
	for a: String in args:
		if a.begins_with("--s0="):
			s0 = float(a.trim_prefix("--s0="))
		elif a.begins_with("--s1="):
			s1 = float(a.trim_prefix("--s1="))
		elif a.begins_with("--step="):
			step = float(a.trim_prefix("--step="))
		elif a == "--gate":
			gate = true
		elif a.begins_with("--probe="):
			probes = a.trim_prefix("--probe=")
		elif a.begins_with("--lane="):          # Phase 4：別の巷（直線区間）を測る。LANE_N は LANE_S を 90° 回した向き（既定の 071 の巷と同じ規約）
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
	for nm: String in ["ArchW9R2P13", "EnrichW9P3", "EnrichW9P4"]:
		var n := vil.get_node_or_null(nm)
		if n == null:
			continue
		for c in n.find_children("*", "CollisionObject3D", true, false):
			_ov_rids.append((c as CollisionObject3D).get_rid())
	print("[ARMSW] overlay collision objects: %d  arm.collision_mask=%d  spring_length(configured)=%.2f" % [_ov_rids.size(), _arm.collision_mask, _arm.spring_length])
	if probes != "":
		for it: String in probes.split(";", false):
			var c := it.split(",")
			var pw0 := Vector2(float(c[0]), float(c[1]))
			var a0 := _arm_at(pw0, deg_to_rad(float(c[2])))
			print("[ARMSW] probe (%.2f,%.2f) yaw %.1f  全碰撞 %.3f m (%s)  基準 %.3f m  悪化 %.3f m" % [pw0.x, pw0.y, float(c[2]), float(a0[0]), String(a0[1]), float(a0[2]), float(a0[2]) - float(a0[0])])
		quit(0)
		return
	var sm := _sweep(s0, s1, step)
	_print_summary(sm)
	for w: Dictionary in (sm["worst10"] as Array).slice(0, 5):
		print("[ARMSW]   worst %s" % JSON.stringify(w))
	if gate:
		await _run_gate(sm)
		sm["gate"] = {"pass": _pass, "fail": _fail}
	var f := FileAccess.open(out_json, FileAccess.WRITE)
	f.store_string(JSON.stringify(sm, "  ") + "\n")
	f.close()
	if gate:
		print("[ARMSW] PASS %d  FAIL %d" % [_pass, _fail])
		print("[ARMSW] 結果：%d 項失敗" % _fail)
		quit(1 if _fail > 0 else 0)
	else:
		quit(0)


func _run_gate(sm: Dictionary) -> void:
	var bo: Dictionary = sm["by_owner"]
	# ── G1 柴棚（071）の碰撞：庇柱が無い＝背の高い碰撞箱が無い（薪・切り株の低い箱だけ）
	var ov := vil.get_node_or_null(OV_071)
	_ok(ov != null, "G1 071 の overlay（%s）がある" % OV_071)
	var tall := 0
	var low_shapes := 0
	var body := vil.get_node_or_null(BODY_071) as Node3D
	if ov != null and body != null:
		for cs in ov.find_children("*", "CollisionShape3D", true, false):
			var sh := (cs as CollisionShape3D).shape
			if sh is BoxShape3D:
				var top_rel := (cs as CollisionShape3D).global_position.y + (sh as BoxShape3D).size.y * 0.5 - body.global_position.y
				if top_rel > 1.35:
					tall += 1
					print("[ARMSW]   背の高い碰撞箱 %s top(体基準)=%.2f" % [String((cs as Node).get_path()), top_rel])
				else:
					low_shapes += 1
	_ok(tall == 0 and low_shapes >= 5, "G1 071 の碰撞箱は薪・切り株の低い箱 %d 個だけ（1.35 m を超える柱 %d）" % [low_shapes, tall])
	# ── G2 巷全体の sweep：071 起因の『目立つ悪化』が 0（R1：188 件）
	var n071 := int((bo.get(OV_071, {"n": 0}) as Dictionary)["n"])
	_ok(n071 == 0, "G2 巷全体 %d 地点×16 方位の sweep：071 起因の SpringArm 悪化（≥ %.2f m）が %d 件（R1：188 件）" % [int(sm["samples"]) / 16, WORSE, n071])
	_ok(float(sm["worse_pct"]) <= 1.0, "G3 悪化の割合 %.2f %% ≤ 1.00 %%（R1：2.28 %%。残りは宅間の板塀・庭木の幹＝設計上の障害物）" % float(sm["worse_pct"]))
	# ── G4／G5 代表鏡位 bT3／bT4（正式 TPS の玩家位置・向き）：腕長が元の場景と 5 cm 以内
	for nm: String in ["bT3", "bT4"]:
		var pr: Array = BT3 if nm == "bT3" else BT4
		var yaw := _yaw_of(pr[0], pr[1])
		var a := _arm_at(pr[0], yaw)
		_ok(float(a[2]) - float(a[0]) <= 0.05, "G4 %s：腕長 %.3f m（元の場景 %.3f m・差 %.3f m ≤ 0.05）" % [nm, float(a[0]), float(a[2]), float(a[2]) - float(a[0])])
	# ── 反向案例：R1 の庇柱を（記憶の中だけで）戻すと検出できる
	if body != null:
		var inj: Array = []
		for pi in R1_POSTS.size():
			var pz: Array = R1_POSTS[pi]
			var sb := StaticBody3D.new()
			sb.name = "_neg_post%d" % pi          # 一意な名前（同名だと Godot が @StaticBody3D@N に改名し、持ち主が (base) になる）
			var cs2 := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			var half := maxf(0.14 / 2.0 + L.POST_PAD, 0.125)
			bx.size = Vector3(2.0 * half, 2.478, 2.0 * half)
			sb.collision_layer = int((body as CollisionObject3D).collision_layer)
			sb.collision_mask = int((body as CollisionObject3D).collision_mask)
			cs2.shape = bx
			sb.add_child(cs2)
			vil.add_child(sb)
			sb.global_transform = Transform3D(body.global_transform.basis, body.global_transform * Vector3(float(pz[0]), 1.239, float(pz[1])))
			inj.append(sb)
			_ov_rids.append(sb.get_rid())      # overlay が足したものとして『基準』の ray からも除く（さもないと差が 0 になる）
		for i in 4:
			await physics_frame      # 物理サーバーに新しい body が入るまで（ray 照会は物理 step の後の状態を見る）
		var yaw3 := _yaw_of(BT3[0], BT3[1])
		var an := _arm_at(BT3[0], yaw3)
		_ok(float(an[2]) - float(an[0]) >= 1.0, "N1 反向：R1 の庇柱を戻すと bT3 の腕が %.2f m 縮む（≥ 1.00 m＝この gate は R1 の問題を検出できる）" % (float(an[2]) - float(an[0])))
		var sm2 := _sweep(-4.0, 6.0, 0.25)
		var n_inj := int(((sm2["by_owner"] as Dictionary).get(NEG_OWNER, {"n": 0}) as Dictionary)["n"])
		_ok(n_inj >= 20, "N2 反向：柱を戻した sweep（s −4..6）の『目立つ悪化』が %d 件に増える（≥ 20・柱が無い今：071 起因 %d）" % [n_inj, n071])
		for sb2 in inj:
			_ov_rids.erase((sb2 as CollisionObject3D).get_rid())
			vil.remove_child(sb2 as Node)
			(sb2 as Node).free()
		for i in 4:
			await physics_frame
		var an2 := _arm_at(BT3[0], yaw3)
		_ok(float(an2[2]) - float(an2[0]) <= 0.05, "N3 戻した後：柱を外すと bT3 の腕長が元に戻る（差 %.3f m）" % (float(an2[2]) - float(an2[0])))
