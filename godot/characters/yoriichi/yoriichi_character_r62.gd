extends "res://characters/yoriichi/yoriichi_character_r61.gd"
## R6.2 候選控制器（只給 player_yoriichi_r62.tscn 用；正式、R5、R6、R6.1 控制器一行不改）。
## R6.2 變更：
##   - 握刀 IK（r62_grip_ik.gd，掛在 Skeleton3D 第一個子節點＝動畫之後、SpringBone 之前）：
##     右手換新插槽（刀柄斜過掌心、掌根貼柄、拇指包覆、虎口在柄背），刀在世界中的位置由「動畫手 × 舊插槽」決定，
##     所以每個片段的刀路、命中判定幾何、刀光都和 R6.1 相同；手臂用兩骨 IK 自動跟上。
##     左手在雙手握時貼到刀座標下固定的左手握位（柄尾），權重隨掌心離柄距離平滑。
##   - 右手權重：拔刀過程在出鞘門檻前先爬升（刀出現在手上的那一格權重＝1，刀不跳）；居合依片段每格的「手上刀可見」
##     表預先爬升／延後淡出。
## 其餘（跳躍、居合、取消接續、重斬時序）沿用 R6.1。
const R62_GRIP_JSON := "res://characters/yoriichi/v24_r62/r62_grip.json"
const R62_IK_SCRIPT := preload("res://characters/yoriichi/r62_grip_ik.gd")
@export var r62_grip_ik_enabled := true
@export var r62_left_grip_enabled := true
## 握刀 IK 的手肘旋轉搜尋（手肘繞肩→腕軸轉，挑腕角最自然的）。開啟：重斬右腕尺偏 p95 75°→45°、居合腕角變差的格 32→4，
## 代價是右手肘平均偏離原動畫約 88 mm（重斬實測）。同場景 IK 關／開 A/B（含 SpringBone）袖候選 2544→2662 頂點·格（+5%）；
## 關閉手肘旋轉則 2544→2777（+9%）。關閉時手肘留在原動畫的彎曲平面，只做兩骨 IK 伸縮。
@export var r62_ik_swivel := true
@export_range(0.0, 1.0) var r62_ik_twist_to_forearm := 1.0   ## IK 新增的手腕扭轉移到前臂的比例
@export var r62_lead_frames := 8          ## 居合：握柄前幾格開始把右手轉到新握位
@export var r62_ramp_time := 0.15         ## 一般拔刀／收刀：權重淡入淡出秒數
## 居合出鞘段水平化（鞘＋刀繞鞘口轉平）——實驗，預設關閉：R6.1 拔刀時右臂已伸到臂長 95–97%，轉平後右手目標超出臂長
## （q36 量測：設計 14–21° 只剩 0.8–2° 可達；強行開啟 IK 誤差 48–100 mm，刀會偏離鞘軸）。要做到需重做片段的軀幹扭轉／鞘引き量。
@export var r62_qd_horizontal := false
var _r62_ik = null                        # r62_grip_ik.gd instance
var _r62_has_left := false
var _r62_w := 0.0
var _r62_qd_w := PackedFloat32Array()
var _r62_qd_fr := -1.0
var _r62_qd_rh := PackedFloat32Array()     # 居合出鞘段：每格鞘＋刀繞鞘口的旋轉（Hips 空間，12 floats/格，column-major）


func _ready():
	super._ready()
	_r62_install()


static func _r62_xf(rows: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]),
		Vector3(rows[0][2], rows[1][2], rows[2][2])), Vector3(rows[0][3], rows[1][3], rows[2][3]))


static func _r62_quats(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var q: Array = d[k]
		out[k] = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	return out


func _r62_install() -> void:
	if not r62_grip_ik_enabled or _visual == null:
		return
	if not FileAccess.file_exists(R62_GRIP_JSON):
		push_warning("R6.2 grip json missing: " + R62_GRIP_JSON)
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R62_GRIP_JSON))
	var sks := _visual.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var ik = R62_IK_SCRIPT.new()
	ik.name = "R62GripIK"
	sk.add_child(ik)
	sk.move_child(ik, 0)
	ik.sock_old = _r62_xf(d["sock_old"])
	ik.sock_new = _r62_xf(d["sock_new"])
	if d.has("left_rel"):
		ik.left_rel = _r62_xf(d["left_rel"])
	ik.right_fingers = _r62_quats(d.get("right_fingers", {}))
	ik.left_fingers = _r62_quats(d.get("left_fingers", {}))
	_r62_has_left = d.has("left_rel")
	ik.left_enabled = false
	ik.swivel_search = r62_ik_swivel
	ik.twist_to_forearm = r62_ik_twist_to_forearm
	var axd: Dictionary = d.get("axes", {})
	for side in axd:
		var a: Dictionary = axd[side]
		ik.axes[side] = {"f": Vector3(a["f"][0], a["f"][1], a["f"][2]), "flex": Vector3(a["flex"][0], a["flex"][1], a["flex"][2]),
			"ulnar": Vector3(a["ulnar"][0], a["ulnar"][1], a["ulnar"][2])}
	if r62_qd_horizontal and d.has("qd_rh"):
		for col in d["qd_rh"]:
			for x in col:
				_r62_qd_rh.append(float(x))
	if _sword_hand:
		_sword_hand.transform = ik.sock_new
	_r62_ik = ik


func _r5_install() -> void:
	super._r5_install()
	# 居合：每格權重＝手上有刀 1；握柄前 lead 格線性爬升（提前 2 格到 1，避免一格延遲），放刀後 lead 格淡出
	_r62_qd_w = PackedFloat32Array()
	var n := _r5_vis.size()
	_r62_qd_w.resize(n)
	var L := maxi(2, r62_lead_frames)
	for f in n:
		var w := 1.0 if _r5_vis[f] == 1 else 0.0
		if w < 1.0:
			for k in range(1, L + 3):
				if f + k < n and _r5_vis[f + k] == 1:
					w = maxf(w, clampf(1.0 - float(k - 2) / float(L), 0.0, 1.0))
					break
			for k in range(1, L + 1):
				if f - k >= 0 and _r5_vis[f - k] == 1:
					# 刀隱藏後的第一格仍是 1：最後一個可見格內插時權重不會先掉（原本收刀最後一格刀尖偏 7.5 mm）
					w = maxf(w, 1.0 - float(k - 1) / float(L))
					break
		_r62_qd_w[f] = w


func _r5_apply(fr: float) -> void:
	_r62_qd_fr = fr
	super._r5_apply(fr)


func _r62_rh(f: int) -> Transform3D:
	var o := f * 12
	if o + 11 >= _r62_qd_rh.size():
		return Transform3D.IDENTITY
	var s := _r62_qd_rh
	return Transform3D(Basis(Vector3(s[o], s[o + 1], s[o + 2]), Vector3(s[o + 3], s[o + 4], s[o + 5]), Vector3(s[o + 6], s[o + 7], s[o + 8])),
		Vector3(s[o + 9], s[o + 10], s[o + 11]))


## 鞘 offset（父類每格套到鞘與鞘中刀）前面再乘上出鞘段的旋轉
func _r5_offset(f: int) -> Transform3D:
	return _r62_rh(f) * super._r5_offset(f)


func _r62_qd_rot(fr: float) -> Transform3D:
	var n := _r62_qd_rh.size() / 12
	if n <= 0:
		return Transform3D.IDENTITY
	var f0 := clampi(int(floor(fr)), 0, n - 1)
	var f1 := mini(f0 + 1, n - 1)
	return _r62_rh(f0).interpolate_with(_r62_rh(f1), clampf(fr - float(f0), 0.0, 1.0))


func _r5_end() -> void:
	_r62_qd_fr = -1.0
	super._r5_end()


func _r62_target() -> float:
	if _r5_active and _r62_qd_fr >= 0.0 and _r62_qd_w.size() > 0:
		var f0 := clampi(int(floor(_r62_qd_fr)), 0, _r62_qd_w.size() - 1)
		var f1 := mini(f0 + 1, _r62_qd_w.size() - 1)
		return lerpf(_r62_qd_w[f0], _r62_qd_w[f1], clampf(_r62_qd_fr - float(f0), 0.0, 1.0))
	if _sword_in_hand():
		return 1.0
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return smoothstep(t_unsheathe - 0.25, t_unsheathe, _draw_t)
	return 0.0


func _physics_process(delta):
	super._physics_process(delta)
	if _r62_ik == null:
		return
	var tw := _r62_target()
	if _sword_in_hand() or (_r5_active and _r62_qd_fr >= 0.0):
		_r62_w = tw                               # 刀在手上／居合表：照表，不延遲
	else:
		_r62_w = move_toward(_r62_w, tw, delta / maxf(0.01, r62_ramp_time))
	_r62_ik.right_weight = _r62_w
	var qd_now := _r5_active and _r62_qd_fr >= 0.0 and _r62_qd_rh.size() > 0
	_r62_ik.qd_on = qd_now
	_r62_ik.qd_rot_h = _r62_qd_rot(_r62_qd_fr) if qd_now else Transform3D.IDENTITY
	# 左手貼柄只在刀完全拔出、且不在居合（左手握鞘口）時啟用；拔刀／收刀期間左手在鞘上
	_r62_ik.left_enabled = r62_left_grip_enabled and _r62_has_left and sword_state == SwordState.DRAWN and not _r5_active
