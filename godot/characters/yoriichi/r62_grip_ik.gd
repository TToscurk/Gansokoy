extends SkeletonModifier3D
## R6.2 握刀 IK（只給 player_yoriichi_r62.tscn 的候選控制器使用；正式角色、R6、R6.1 都不掛）。
## 在動畫之後、SpringBone 之前執行（控制器把它放在 Skeleton3D 第一個子節點）：
##  右手：刀在手時，刀的位置＝「動畫手 × 舊插槽」— 每個片段原本的刀路、命中判定幾何、刀光完全不變；
##        再用 R6.2 新插槽（刀柄斜過掌心、掌根貼柄、虎口在柄上）反解右手，兩骨 IK 帶動上臂／前臂，
##        手肘繞「肩→腕」軸的旋轉角逐格挑腕角最自然的（屈 −30…25°、尺偏 −10…35°、扭 ±25°），
##        手腕新增的扭轉移到前臂；手指換成 R6.2 在真刀柄上解出的握形。
##  左手：雙手握時（動畫左手掌心離刀柄軸 < left_d1），左手貼到「刀座標下固定的左手握位」，同樣的 IK／腕角／手指，
##        權重隨距離平滑淡入淡出。
## right_weight 由控制器每格寫入（拔刀前預先爬升，刀出現在手上的那一格＝1）。

@export var right_weight := 0.0
@export var left_enabled := true
@export var left_d0 := 0.045            ## 掌心離刀柄軸 ≤ d0：左手完全貼柄
@export var left_d1 := 0.09             ## ≥ d1：不動左手
@export var left_blend_time := 0.12     ## 左手貼柄權重最短淡入／淡出秒數（避免一格貼上／彈開）
@export var twist_to_forearm := 1.0     ## IK 新增的手腕扭轉移到前臂的比例
@export var swivel_search := true
@export var swivel_min := -60.0
@export var swivel_max := 20.0
@export var swivel_step := 10.0
@export var swivel_rate := 6.0          ## 手肘角平滑（每秒追上的比例）
var sock_old := Transform3D.IDENTITY    ## 原插槽（片段作者用的刀↔手關係）
var sock_new := Transform3D.IDENTITY    ## R6.2 新插槽（場景裡 Sword_Hand 的 transform）
var left_rel := Transform3D.IDENTITY    ## 左手在刀座標下的握位
var right_fingers := {}                 ## bone name -> Quaternion（局部旋轉）
var left_fingers := {}
var axes := {}                          ## side -> {"f","flex","ulnar"}：手骨局部座標的指向／屈軸／尺偏軸
var qd_on := false                     ## 居合：鞘＋刀繞鞘口的剛體旋轉（出鞘段水平化）
var qd_rot_h := Transform3D.IDENTITY    ## 該旋轉（Hips 骨空間＝SheathSocket 空間，與鞘 offset 同一空間）
var qd_left := true                     ## 居合時左手（握鞘口）跟著同一旋轉
var last_left_weight := 0.0
var last_err := [0.0, 0.0]               ## 右手 IK 後實際刀 vs 目標刀（mm, deg；權重 1 時應 ≈ 0）
var last_wrist := {}                    ## side -> {flex, ulnar, twist, swivel}（量測用）
var last_wrist_anim := {}               ## side -> 動畫原本（IK 前）的腕角
var _swv := {"Right": 0.0, "Left": 0.0}
var _lw := 0.0
var _ix := {}


func _bone(n: String) -> int:
	if not _ix.has(n):
		_ix[n] = get_skeleton().find_bone(n)
	return _ix[n]


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var wr := clampf(right_weight, 0.0, 1.0)
	last_left_weight = 0.0
	# 居合出鞘段：鞘（控制器改 offset）、鞘中／手上的刀、握鞘的左手一起繞鞘口轉 → 刀仍在鞘軸上，只是更平
	var rsk := Transform3D.IDENTITY
	if qd_on:
		var hips := sk.get_bone_global_pose(_bone("mixamorig_Hips"))
		rsk = hips * qd_rot_h * hips.affine_inverse()
		if qd_left:
			var lg0 := sk.get_bone_global_pose(_bone("mixamorig_LeftHand"))
			var lt0 := rsk * lg0
			if lt0.origin.distance_to(lg0.origin) > 1e-4:
				_solve_arm(sk, "Left", lt0, 1.0, delta, false)
	if wr <= 0.001:
		_swv["Right"] = 0.0
		_lw = 0.0
		if not qd_on:
			_swv["Left"] = 0.0
		return
	var h := _bone("mixamorig_RightHand")
	var hg := sk.get_bone_global_pose(h)
	var sword := rsk * hg * sock_old                        # 動畫原本的刀（骨架空間；居合出鞘段再繞鞘口轉）
	var ht := sword * sock_new.affine_inverse()
	var tgt := Transform3D(hg.basis.orthonormalized().slerp(ht.basis.orthonormalized(), wr), hg.origin.lerp(ht.origin, wr))
	_solve_arm(sk, "Right", tgt, wr, delta)
	_set_fingers(sk, right_fingers, wr)
	var got := sk.get_bone_global_pose(h) * sock_new
	var qa := got.basis.orthonormalized().get_rotation_quaternion()
	var qb := sword.basis.orthonormalized().get_rotation_quaternion()
	last_err = [got.origin.distance_to(sword.origin) * 1000.0, rad_to_deg(qa.angle_to(qb))]
	if not left_enabled or left_rel == Transform3D.IDENTITY:
		_lw = 0.0
		return
	# 左手：用實際（IK 後）的刀
	var sword_now := sk.get_bone_global_pose(h) * sock_new
	var lh := _bone("mixamorig_LeftHand")
	var lg := sk.get_bone_global_pose(lh)
	var lm := sk.get_bone_global_pose(_bone("mixamorig_LeftHandMiddle1"))
	var palm := (lg.origin + lm.origin) * 0.5
	var a := sword_now * Vector3(0, -0.35, 0)
	var b := sword_now * Vector3(0, -0.005, 0)
	var ab := b - a
	var u := clampf((palm - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
	var d := (palm - (a + ab * u)).length()
	_lw = move_toward(_lw, (1.0 - smoothstep(left_d0, left_d1, d)) * wr, delta / maxf(0.01, left_blend_time))
	var wl := _lw
	last_left_weight = wl
	if wl <= 0.001:
		_swv["Left"] = 0.0
		return
	var lt := sword_now * left_rel
	var ltgt := Transform3D(lg.basis.orthonormalized().slerp(lt.basis.orthonormalized(), wl), lg.origin.lerp(lt.origin, wl))
	_solve_arm(sk, "Left", ltgt, wl, delta)
	_set_fingers(sk, left_fingers, wl)


func _wrist(side: String, fb: Basis, hb: Basis, rest_h: Basis) -> Dictionary:
	# 手相對「前臂×手的 rest」的旋轉，做 swing–twist 分解（twist 繞手的長軸 f）；swing 投影到屈曲／尺偏軸。
	# 大角度時 axis-angle 直接投影會失真（前臂自身 roll 大的片段會讀出 100°+ 的假值），所以先拆 twist。
	var ax: Dictionary = axes.get(side, {})
	if ax.is_empty():
		return {"flex": 0.0, "ulnar": 0.0, "twist": 0.0}
	var q := ((fb * rest_h).inverse() * hb).orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var fa: Vector3 = ax["f"]
	var p := Vector3(q.x, q.y, q.z).dot(fa)
	var tw := Quaternion(fa.x * p, fa.y * p, fa.z * p, q.w)
	var twist := 0.0
	if tw.length_squared() > 1e-12:
		tw = tw.normalized()
		twist = rad_to_deg(2.0 * atan2(Vector3(tw.x, tw.y, tw.z).dot(fa), tw.w))
		twist = wrapf(twist, -180.0, 180.0)
	else:
		tw = Quaternion.IDENTITY
	var sw := q * tw.inverse()
	if sw.w < 0.0:
		sw = -sw
	var sa := rad_to_deg(sw.get_angle())
	var v := sw.get_axis() * sa if sa > 1e-4 else Vector3.ZERO
	return {"flex": v.dot(ax["flex"]), "ulnar": v.dot(ax["ulnar"]), "twist": twist}


static func _wpen(w: Dictionary) -> float:
	return pow(maxf(0.0, w["flex"] - 25.0), 2) + pow(maxf(0.0, -30.0 - w["flex"]), 2) + pow(maxf(0.0, w["ulnar"] - 35.0), 2) \
		+ pow(maxf(0.0, -10.0 - w["ulnar"]), 2) + pow(maxf(0.0, absf(w["twist"]) - 25.0), 2)


## 兩骨 IK（保留原彎曲平面，再讓手肘繞肩→腕軸轉 phi 度），手放到目標；前臂吸收 IK 新增的手腕扭轉。
func _arm_pose(U: Transform3D, F: Transform3D, H: Transform3D, target: Transform3D, phi: float, side: String,
		rest_h: Basis, w_anim: Dictionary) -> Array:
	var A := U.origin
	var B := F.origin
	var C := H.origin
	var l1 := (B - A).length()
	var l2 := (C - B).length()
	var dv := target.origin - A
	var dist := clampf(dv.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var udir := dv.normalized()
	var n := (B - A).cross(C - A)
	if n.length() < 1e-8:
		n = (B - A).cross(Vector3.UP)
	n = n.normalized()
	var v := n.cross(udir).normalized()
	if v.dot(B - A) < 0.0:
		v = -v
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sa := sqrt(maxf(0.0, 1.0 - ca * ca))
	var B2 := A + (udir * ca + v * sa) * l1
	if phi != 0.0:
		B2 = A + Basis(udir, deg_to_rad(phi)) * (B2 - A)
	var T2 := A + udir * dist
	var r1 := Quaternion((B - A).normalized(), (B2 - A).normalized())
	var cdir := (Basis(r1) * (C - B)).normalized()
	var r2 := Quaternion(cdir, (T2 - B2).normalized())
	var fb := Basis(r2) * Basis(r1) * F.basis
	var w := _wrist(side, fb, target.basis, rest_h)
	if twist_to_forearm > 0.0:
		var dtw: float = wrapf(w["twist"] - w_anim["twist"], -180.0, 180.0)
		fb = Basis((T2 - B2).normalized(), deg_to_rad(twist_to_forearm * dtw)) * fb
		w = _wrist(side, fb, target.basis, rest_h)
	return [Transform3D(Basis(r1) * U.basis, A), Transform3D(fb, B2), Transform3D(target.basis, T2), w]


func _solve_arm(sk: Skeleton3D, side: String, target: Transform3D, weight: float, delta: float, allow_swivel := true) -> void:
	var iu := _bone("mixamorig_%sArm" % side)
	var i_f := _bone("mixamorig_%sForeArm" % side)
	var ih := _bone("mixamorig_%sHand" % side)
	var U := sk.get_bone_global_pose(iu)
	var F := sk.get_bone_global_pose(i_f)
	var H := sk.get_bone_global_pose(ih)
	if (target.origin - U.origin).length() < 1e-6:
		return
	var rest_h := sk.get_bone_rest(ih).basis
	var w_anim := _wrist(side, F.basis, H.basis, rest_h)
	last_wrist_anim[side] = w_anim
	var phi_t := 0.0
	if allow_swivel and swivel_search and axes.has(side):
		var best := INF
		var p := swivel_min
		while p <= swivel_max + 0.01:
			var res: Array = _arm_pose(U, F, H, target, p, side, rest_h, w_anim)
			var c := _wpen(res[3]) + 0.02 * p * p
			if c < best:
				best = c
				phi_t = p
			p += swivel_step
	var cur: float = lerpf(_swv[side], phi_t * weight, clampf(delta * swivel_rate, 0.0, 1.0))
	_swv[side] = cur
	var out: Array = _arm_pose(U, F, H, target, cur, side, rest_h, w_anim)
	sk.set_bone_global_pose(iu, out[0])
	sk.set_bone_global_pose(i_f, out[1])
	sk.set_bone_global_pose(ih, out[2])
	var wd: Dictionary = out[3]
	wd["swivel"] = cur
	last_wrist[side] = wd


func _set_fingers(sk: Skeleton3D, fingers: Dictionary, w: float) -> void:
	for bn in fingers:
		var i := _bone(bn)
		if i < 0:
			continue
		var q0 := sk.get_bone_pose_rotation(i)
		var q1: Quaternion = fingers[bn]
		if q0.dot(q1) < 0.0:
			q1 = -q1
		sk.set_bone_pose_rotation(i, q0.slerp(q1, w))
