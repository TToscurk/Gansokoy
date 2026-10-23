extends SceneTree
## R7 握柄指形重解（只寫 R7 專用 res://characters/yoriichi/v24_r7/r7_grip.json；共用 r62_grip.json 不動）。
## 刀與手骨剛性相連（sock_new），所以在任一格 IK 後的手座標系解一次即通用：
## 每指 1→2→3 節繞屈曲軸座標下降，讓 2、3 節與指尖中心到刀柄表面 ≈ TARGET（指半徑），不低於 MIN（避免指頭陷進柄）。
const TARGET := 0.0075
const MIN_GAP := 0.0055
const HILT_R := 0.0153
const FINGERS := ["Index", "Middle", "Ring", "Pinky", "Thumb"]
var p
var sk: Skeleton3D
var fr := 0
var done := false

func _initialize():
	var g := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(50, 1, 50); cs.shape = bx; g.add_child(cs); g.position = Vector3(0, -0.5, 0); root.add_child(g)
	p = (load("res://characters/yoriichi/player_yoriichi_r7.tscn") as PackedScene).instantiate()
	root.add_child(p)

func _process(_d):
	if sk == null and p.get("_visual") != null:
		sk = p._visual.find_children("*", "Skeleton3D", true, false)[0]
		sk.skeleton_updated.connect(_on_skel)
	if fr == 4:
		p.call("request_draw")
	fr += 1
	return done or fr > 200

func _local(bn: String, q: Quaternion) -> Transform3D:
	var i := sk.find_bone(bn)
	return Transform3D(Basis(q), sk.get_bone_pose_position(i))

func _gap(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (pt - (a + ab * u)).length() - HILT_R

## 指鏈 FK：H = 手骨全域；qs = 各節局部旋轉；回傳 [節1..節4] 全域原點
func _chain(H: Transform3D, side: String, f: String, qs: Dictionary) -> Array:
	var out := []
	var T := H
	for k in [1, 2, 3, 4]:
		var bn := "mixamorig_%sHand%s%d" % [side, f, k]
		if sk.find_bone(bn) < 0:
			break
		T = T * _local(bn, qs.get(bn, sk.get_bone_pose_rotation(sk.find_bone(bn))))
		out.append(T)
	return out

func _cost(H: Transform3D, side: String, f: String, qs: Dictionary, a: Vector3, b: Vector3) -> float:
	var ch := _chain(H, side, f, qs)
	var c := 0.0
	for k in range(1, ch.size()):
		var gp := _gap(ch[k].origin, a, b)
		c += pow(gp - TARGET, 2)
		if gp < MIN_GAP:
			c += 40.0 * pow(MIN_GAP - gp, 2)
	return c

func _solve(H: Transform3D, side: String, base: Dictionary, a: Vector3, b: Vector3) -> Dictionary:
	var qs := base.duplicate()
	var rep := {}
	for f in FINGERS:
		var before := []
		for t in _chain(H, side, f, qs).slice(1):
			before.append(snappedf(_gap(t.origin, a, b) * 1000.0, 0.1))
		for _pass in 3:
			for k in [1, 2, 3]:
				var bn := "mixamorig_%sHand%s%d" % [side, f, k]
				if sk.find_bone(bn) < 0:
					continue
				var q0: Quaternion = qs.get(bn, sk.get_bone_pose_rotation(sk.find_bone(bn)))
				var best_q := q0
				var best := _cost(H, side, f, qs, a, b)
				for ax in [Vector3.RIGHT, Vector3.BACK]:
					for deg in range(-30, 61, 3):
						var q := q0 * Quaternion(ax, deg_to_rad(deg))
						qs[bn] = q
						var c := _cost(H, side, f, qs, a, b)
						if c < best - 1e-9:
							best = c
							best_q = q
				qs[bn] = best_q
		var after := []
		for t in _chain(H, side, f, qs).slice(1):
			after.append(snappedf(_gap(t.origin, a, b) * 1000.0, 0.1))
		rep[f] = {"before_mm": before, "after_mm": after}
	return {"q": qs, "rep": rep}

func _on_skel():
	if done or fr < 60 or p._r62_ik == null or p._r62_ik.right_weight < 0.999:
		return
	done = true
	var ik = p._r62_ik
	var hR := sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand"))
	var sword: Transform3D = hR * ik.sock_new
	var a := sword * Vector3(0, -0.35, 0)
	var b := sword * Vector3(0, -0.01, 0)
	var R := _solve(hR, "Right", ik.right_fingers, a, b)
	var hL: Transform3D = sword * ik.left_rel          # 雙手握時左手的目標握位（刀座標固定）
	var L := _solve(hL, "Left", ik.left_fingers, a, b)
	var out := {"source": "tools/yoriichi_r7/solve_grip_r7.gd (R7 only; base = v24_r62/r62_grip.json fingers)", "target_mm": TARGET * 1000.0,
		"min_mm": MIN_GAP * 1000.0, "right_fingers": {}, "left_fingers": {}, "report": {"right": R.rep, "left": L.rep}}
	for k in R.q:
		var q: Quaternion = R.q[k]; out.right_fingers[k] = [q.x, q.y, q.z, q.w]
	for k in L.q:
		var q: Quaternion = L.q[k]; out.left_fingers[k] = [q.x, q.y, q.z, q.w]
	var f := FileAccess.open("res://characters/yoriichi/v24_r7/r7_grip.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("GRIP_R ", JSON.stringify(R.rep))
	print("GRIP_L ", JSON.stringify(L.rep))
	quit()
