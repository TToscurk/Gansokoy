extends "res://tools/yoriichi_r7/test_r7_form13.gd"
## R7 P5d 探針：REF01 → 右鍵分支，真實 training_dummy（與 capture_r7 p5_rmb_* 同相對位置）下逐物理步量
## 膠囊淨空（水平距離 − 玩家半徑 0.30 − 木樁碰撞半徑 0.35）、骨骼／刀身到木樁軸的水平距離（樁身可見半徑 0.26）。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/probe_r7_rmb_clear.gd -- rmbclear [right fwd rmb_tick]
const BONES := ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Head", "mixamorig_LeftHand", "mixamorig_RightHand",
	"mixamorig_LeftForeArm", "mixamorig_RightForeArm", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
	"mixamorig_LeftLeg", "mixamorig_RightLeg", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftShoulder", "mixamorig_RightShoulder"]

var _grip_rows: Array = []
var _gd: Node3D = null

func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
	return (p - (a + ab * u)).length()

## 骨架＋IK 更新後：左手 vs 實際刀 × left_rel（同一骨架空間；left_rel 以手腕骨 LeftHand 原點定義）
func _on_skel_grip() -> void:
	if _p == null or _ref() != "REF01_RMB":
		return
	var ik = _p.get("_r62_ik")
	var sw: Node3D = _p.get("_sword_hand")
	var inv := _sk.global_transform.affine_inverse()
	var sword := inv * sw.global_transform
	var lg := _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftHand"))
	var lt: Transform3D = sword * ik.left_rel
	var ax: Vector3 = (sword.basis * Vector3(0, 1, 0)).normalized()
	var dv := lg.origin - lt.origin
	var along := dv.dot(ax)
	var radial := (dv - ax * along).length()
	var qa := lg.basis.orthonormalized().get_rotation_quaternion()
	var qb := lt.basis.orthonormalized().get_rotation_quaternion()
	var gx := _sk.global_transform
	var arms := 9.0
	if _gd != null:
		for cn in ["Visual/CrossArm1", "Visual/CrossArm2"]:
			var ca := _gd.get_node(cn) as Node3D
			var a: Vector3 = ca.global_transform * Vector3(-0.45, 0, 0)
			var b: Vector3 = ca.global_transform * Vector3(0.45, 0, 0)
			for bn in ["mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_LeftForeArm", "mixamorig_RightForeArm", "mixamorig_Spine2", "mixamorig_Hips"]:
				arms = minf(arms, _seg_d(gx * _sk.get_bone_global_pose(_sk.find_bone(bn)).origin, a, b) - 0.06)
	_grip_rows.append({"af": snappedf(_fr() * 0.5, 0.1), "along_mm": snappedf(along * 1000.0, 0.1), "radial_mm": snappedf(radial * 1000.0, 0.1),
		"deg": snappedf(rad_to_deg(qa.angle_to(qb)), 0.1), "lw": snappedf(float(ik._lw), 0.01), "left_on": bool(ik.left_enabled), "arm_clear": snappedf(arms, 0.003)})

func _sc_rmbclear() -> void:
	_sk.skeleton_updated.connect(_on_skel_grip)
	var args := OS.get_cmdline_user_args()
	var dr := float(args[1]) if args.size() > 1 else -1.17
	var dfw := float(args[2]) if args.size() > 2 else 1.98
	var rmb_tick := int(args[3]) if args.size() > 3 else 34
	var vis: Node3D = _p.get("_visual")
	var b := vis.global_transform.basis.orthonormalized()
	var fw: Vector3 = b * Vector3(0, 0, 1)
	fw.y = 0
	var rt: Vector3 = b * Vector3(-1, 0, 0)
	rt.y = 0
	print("P_PRE ", _p.global_position)
	var d: Node3D = (load("res://characters/combat/training_dummy.tscn") as PackedScene).instantiate()
	d.position = _p.global_position + rt.normalized() * dr + fw.normalized() * dfw
	_world.add_child(d)   # 先定位再入樹：避免木樁先在原點與玩家重疊造成去穿透推移
	d.add_to_group("enemies")
	_gd = d
	print("P_SET ", _p.global_position, " d ", d.global_position)
	await physics_frame
	print("P_BEFORE ", _p.global_position, " dummy ", d.global_position, " fw ", fw, " rt ", rt)
	var rows := []
	var worst := {"capsule": 9.0, "bone": 9.0, "blade": 9.0}
	_p.call("execute_form", 1, true)
	for i in 400:
		if i == rmb_tick:
			_p.call("request_heavy_cut")
		await physics_frame
		_tick()
		var pp: Vector3 = _p.global_position
		var hd := Vector2(pp.x - d.global_position.x, pp.z - d.global_position.z).length()
		var cap := hd - 0.30 - 0.35
		var bmin := 9.0
		var bname := ""
		for bn in BONES:
			var bi := _sk.find_bone(bn)
			var w: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(bi).origin
			var dd := Vector2(w.x - d.global_position.x, w.z - d.global_position.z).length() - 0.26
			if dd < bmin:
				bmin = dd
				bname = bn
		var blmin := 9.0
		var sh: Node3D = _p.get("_sword_hand")
		if sh != null:
			for lp in _p.get("R7_BLADE_LINE"):
				var w2: Vector3 = sh.global_transform * lp
				if w2.y > d.global_position.y and w2.y < d.global_position.y + 2.0:
					blmin = minf(blmin, Vector2(w2.x - d.global_position.x, w2.z - d.global_position.z).length() - 0.26)
		var row := {"i": i, "ref": _ref(), "af": snappedf(_fr(), 0.1), "cap_clear": snappedf(cap, 0.003), "bone_clear": snappedf(bmin, 0.003), "bone": bname,
			"blade_clear": snappedf(blmin, 0.003), "grp": _p.get("r7_hit_group"), "rootcap": snappedf(float(_p.get("r7_root_cap_used")), 0.001),
			"pos": [snappedf(pp.x, 0.001), snappedf(pp.z, 0.001)]}
		rows.append(row)
		worst.capsule = minf(worst.capsule, cap)
		if _ref() != "":
			worst.bone = minf(worst.bone, bmin)
		if int(row.grp) == 0:
			worst.blade = minf(worst.blade, blmin)
		if i > rmb_tick + 5 and int(_p.get("action_state")) == 0:
			break
	_case.rows = rows
	_case.worst = worst
	_case.dummy = [d.global_position.x, d.global_position.z]
	var hits := 0
	print("PROBE worst=", worst, " ticks=", rows.size())
	for r in rows:
		if r.i % 3 == 0 or r.grp > 0:
			print("  ", r.i, " ", r.ref, " af=", r.af, " cap=", r.cap_clear, " bone=", r.bone_clear, " ", r.bone, " blade=", r.blade_clear, " grp=", r.grp, " rootcap=", r.rootcap)
	_case.grip = _grip_rows
	var mx := {"along": 0.0, "radial": 0.0, "deg": 0.0, "arm_clear": 9.0}
	for g in _grip_rows:
		mx.along = maxf(mx.along, absf(g.along_mm)); mx.radial = maxf(mx.radial, g.radial_mm); mx.deg = maxf(mx.deg, g.deg); mx.arm_clear = minf(mx.arm_clear, g.arm_clear)
	print("GRIP_MAX ", mx, " rows=", _grip_rows.size())
	for g in _grip_rows:
		if int(g.af) % 6 == 0 or (g.af >= 40 and g.af <= 64 and int(g.af) % 2 == 0):
			print("  G ", g)
	_check(true, "probe")
