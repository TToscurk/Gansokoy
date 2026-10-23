extends SceneTree
## v2.4 掛點與時機量測（headless 可）：
##  1) 拔刀 clip 中右手到「鞘中刀柄握點」的距離曲線 → t_unsheathe（抓到刀柄的時刻）
##  2) 依拔刀末格的手骨（手腕、食指根、中指根、小指根）推算握刀：柄軸＝小指根→食指根往指尖傾 30°，
##     刃朝指根（指節）方向、刀背朝虎口；刀的世界尺寸與鞘中刀相同 → 輸出 Sword_Hand 本地 transform
##  3) Run_Turn 首末格髖部 yaw 差
## 用法：godot --headless --path . -s tools/v24_anim/fit_v24_sockets.gd

var _p: CharacterBody3D
var _n := 0

func _initialize() -> void:
	_p = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(_p)

func _skel() -> Skeleton3D:
	return _p.find_children("*", "Skeleton3D", true, false)[0]

## AnimationPlayer 直接 seek（Tree 關閉），用 local pose 手算 FK（headless 下最可靠）。
func _pose_at(anim: String, t: float) -> Dictionary:
	var ap: AnimationPlayer = _p._anim
	ap.play(anim)
	ap.seek(t, true)
	var sk := _skel()
	var g := {}
	for i in sk.get_bone_count():
		var pi := sk.get_bone_parent(i)
		var lp := sk.get_bone_pose(i)
		g[i] = (g[pi] as Transform3D) * lp if pi >= 0 else lp
	return g

func _w(sk: Skeleton3D, g: Dictionary, bone: String) -> Transform3D:
	return sk.global_transform * (g[sk.find_bone(bone)] as Transform3D)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 5:
		return false
	(_p._tree as AnimationTree).active = false
	var sk := _skel()
	var sword_sh: Node3D = _p.find_child("Sword_Sheathed", true, false)
	var hips_bone := sk.find_bone("mixamorig_Hips")
	var draw: String = _p.draw_anim
	var a: Animation = _p._anim.get_animation(draw)
	# 1) 鞘中刀柄握點跟著 Hips 走：用每格的 Hips 世界矩陣 × (Hips→握點) 固定偏移。
	var g0 := _pose_at(draw, 0.0)
	var hips0 := _w(sk, g0, "mixamorig_Hips")
	var grab_local := hips0.affine_inverse() * (sword_sh.global_transform * Vector3(0, -0.15, 0))
	var best := 99.0
	var best_t := 0.0
	var curve := []
	var nf := int(a.length * 30.0)
	for fi in nf + 1:
		var t := fi / 30.0
		var g := _pose_at(draw, t)
		var grab := _w(sk, g, "mixamorig_Hips") * grab_local
		var hand := _w(sk, g, "mixamorig_RightHand").origin
		var d := hand.distance_to(grab)
		curve.append(snappedf(d, 0.01))
		if d < best:
			best = d
			best_t = t
	print("DRAW ", draw, " len=", a.length, " closest hand-grip ", best, " m at t=", best_t, " progress=", best_t / a.length)
	print("DRAW curve ", curve)
	# 2) 握刀
	var ge := _pose_at(draw, a.length)
	var H := _w(sk, ge, "mixamorig_RightHand").origin
	var I := _w(sk, ge, "mixamorig_RightHandIndex1").origin
	var M := _w(sk, ge, "mixamorig_RightHandMiddle1").origin
	var P := _w(sk, ge, "mixamorig_RightHandPinky1").origin
	var fingers := (M - H).normalized()
	var across := (I - P).normalized()
	var axis := across.rotated(across.cross(fingers).normalized(), deg_to_rad(30.0)).normalized()
	# 確認 30° 是往指尖方向傾：傾完後與 fingers 夾角要變小
	if axis.dot(fingers) < across.dot(fingers):
		axis = across.rotated(across.cross(fingers).normalized(), deg_to_rad(-30.0)).normalized()
	var edge := (fingers - axis * fingers.dot(axis)).normalized()
	var center := H.lerp(M, 0.8) + (fingers.cross(across)).normalized() * 0.0
	# 刀的世界尺寸照鞘中刀（每軸）
	var sb := sword_sh.global_transform.basis
	var sx := sb.x.length()
	var sy := sb.y.length()
	var sz := sb.z.length()
	var bx := -edge            # 刀本地 −X = 刃
	var by := axis             # 刀本地 +Y = 刀尖
	var bz := bx.cross(by).normalized()
	bx = by.cross(bz).normalized()
	var basis := Basis(bx * sx, by * sy, bz * sz)
	var origin := center - basis * Vector3(0, -0.12, 0)
	var want := Transform3D(basis, origin)
	var hand_xf := _w(sk, ge, "mixamorig_RightHand")
	var local := hand_xf.affine_inverse() * want
	print("GRIP Sword_Hand local = ", var_to_str(local))
	print("GRIP sword world len=", (basis * Vector3(0, 1.465, 0)).length(), " forearm angle=",
		rad_to_deg(axis.angle_to((H - _w(sk, ge, "mixamorig_RightForeArm").origin).normalized())))
	# 3) Run_Turn yaw
	if _p._anim.has_animation("Run_Turn"):
		var rt: Animation = _p._anim.get_animation("Run_Turn")
		var y0 := _w(sk, _pose_at("Run_Turn", 0.0), "mixamorig_Hips").basis.get_euler().y
		var y1 := _w(sk, _pose_at("Run_Turn", rt.length), "mixamorig_Hips").basis.get_euler().y
		print("RUN_TURN yaw delta deg=", rad_to_deg(wrapf(y1 - y0, -PI, PI)), " len=", rt.length)
	print("COMBAT_READY ", _p._combat_anims_ready, " anims=", _p._anim.get_animation_list().size())
	return true
