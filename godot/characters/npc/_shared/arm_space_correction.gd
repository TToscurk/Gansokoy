extends SkeletonModifier3D
## 上臂姿勢修正層（Pose Correction Layer）：動畫之後、袖子骨鏈之前，依「手臂貼不貼身體」自動把上臂往外張一點。不改動畫資源。
## 做法：每側算上臂方向在胸口座標系的「垂下程度」h（1＝筆直往下）與「已外張角」φ（0＝貼著身體側面往下）。
##   需要的修正＝max_deg × smoothstep(h_lo, h_hi, h) × (1 − smoothstep(free_lo, free_hi, φ))
##     × (1 − smoothstep(fore_lo, fore_hi, 前臂往上程度))
##   → 手垂著貼身體時修正最大；上臂已抬起、已張開、或前臂往上（托腮、揮手、拿到胸前）時漸漸不修，手的位置優先。
##   修正角隨時間平滑（rate 度／秒），繞胸口前後軸往外轉（左右各自決定正負號）。
## 必須是 Skeleton3D 底下的第一個修改器（在 SleeveDrape／SpringBoneSimulator3D 之前），彈簧才吃到修正後的手臂。
## 共用：骨名用 bone_* 設定（小鈴＝mixamorig_*；GeneralSkeleton 角色＝LeftUpperArm 等）。

@export var max_deg := 12.0
@export var h_lo := 0.35        # 手臂往下程度低於此＝不修（手抬起來了）
@export var h_hi := 0.75
@export var free_lo := 14.0     # 已外張角（度）超過此開始少修
@export var free_hi := 30.0
@export var rate := 90.0        # 修正角變化速度上限（度／秒），避免袖子骨鏈被甩
@export var fore_lo := 0.0      # 前臂往上程度（前臂方向·上）超過 fore_lo 開始少修，到 fore_hi 不修（托腮、揮手、拿東西到胸前：手的位置優先）
@export var fore_hi := 0.6
@export var bone_l := "mixamorig_LeftArm"
@export var bone_r := "mixamorig_RightArm"
@export var bone_l2 := "mixamorig_LeftForeArm"
@export var bone_r2 := "mixamorig_RightForeArm"
@export var bone_hand_l := "mixamorig_LeftHand"
@export var bone_hand_r := "mixamorig_RightHand"
@export var bone_chest := "mixamorig_Spine2"
@export var bone_hips := "mixamorig_Hips"
@export var bone_head := "mixamorig_Head"

var applied := {"L": 0.0, "R": 0.0}     # 目前套用的修正角（度），量測工具讀
var _ix := {}
var _up0 := Vector3.UP
var _left0 := Vector3.RIGHT
var _fwd0 := Vector3.BACK
var _chest_rest_inv := Basis()
var _ready_ok := false
var _last_us := 0


func _setup(sk: Skeleton3D) -> void:
	for n in [bone_l, bone_r, bone_l2, bone_r2, bone_hand_l, bone_hand_r, bone_chest, bone_hips, bone_head]:
		_ix[n] = sk.find_bone(n)
		if _ix[n] < 0:
			push_warning("ArmSpaceCorrection：找不到骨頭 " + n); return
	_up0 = (sk.get_bone_global_rest(_ix[bone_head]).origin - sk.get_bone_global_rest(_ix[bone_hips]).origin).normalized()
	var l := sk.get_bone_global_rest(_ix[bone_l]).origin - sk.get_bone_global_rest(_ix[bone_r]).origin
	_left0 = (l - _up0 * l.dot(_up0)).normalized()
	_fwd0 = _left0.cross(_up0)
	_chest_rest_inv = sk.get_bone_global_rest(_ix[bone_chest]).basis.orthonormalized().inverse()
	_ready_ok = true


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ready_ok:
		_setup(sk)
		if not _ready_ok: return
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1e6, 0.0, 0.1) if _last_us > 0 else 0.0
	_last_us = now
	var cr := sk.get_bone_global_pose(_ix[bone_chest]).basis.orthonormalized() * _chest_rest_inv
	var up := (cr * _up0).normalized(); var left := (cr * _left0).normalized(); var fwd := (cr * _fwd0).normalized()
	for side in ["L", "R"]:
		var bi: int = _ix[bone_l if side == "L" else bone_r]
		var b2: int = _ix[bone_l2 if side == "L" else bone_r2]
		var a := sk.get_bone_global_pose(b2).origin - sk.get_bone_global_pose(bi).origin
		if a.length() < 1e-6:
			continue
		a = a.normalized()
		var out := left if side == "L" else -left
		var h := -a.dot(up)
		var phi := rad_to_deg(atan2(a.dot(out), maxf(h, 1e-4)))
		var hb: int = _ix[bone_hand_l if side == "L" else bone_hand_r]
		var fa := (sk.get_bone_global_pose(hb).origin - sk.get_bone_global_pose(b2).origin).normalized()
		var want := max_deg * smoothstep(h_lo, h_hi, h) * (1.0 - smoothstep(free_lo, free_hi, phi)) * (1.0 - smoothstep(fore_lo, fore_hi, fa.dot(up)))
		var cur: float = applied[side]
		cur = want if dt == 0.0 else move_toward(cur, want, rate * dt)
		applied[side] = cur
		if absf(cur) < 1e-3:
			continue
		# 往外轉：繞胸口前後軸，取讓上臂方向更往 out 的那個正負號（左右各自決定）
		var ang := deg_to_rad(cur)
		if (Basis(fwd, ang) * a).dot(out) < (Basis(fwd, -ang) * a).dot(out):
			ang = -ang
		var pg := sk.get_bone_global_pose(sk.get_bone_parent(bi)).basis.orthonormalized()
		var g := pg * sk.get_bone_pose(bi).basis.orthonormalized()
		var ng := Basis(fwd, ang) * g
		sk.set_bone_pose_rotation(bi, (pg.inverse() * ng).get_rotation_quaternion())
