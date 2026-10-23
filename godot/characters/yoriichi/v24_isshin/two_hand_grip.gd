extends Node
## 雙手握刀（候選專用）：重用 R6.2 的握刀 IK（characters/yoriichi/r62_grip_ik.gd，只實例化、不修改）。
## - sock_old ＝ 單手持刀時 Sword_Hand 的 transform（一心動作是用這個關係重定向的 → 動畫刀＝動畫手 × sock_old）。
## - sock_new ＝ R6.2 雙手握位（右手在護手下方約 10 cm、虎口貼柄）；左手＝刀座標下的固定握位 left_rel。
## - weight 0 → 1：右手 IK 權重與 Sword_Hand 的 transform（單手 → 雙手）同步線性插值，刀在世界中的位置／朝向始終＝動畫刀。
## - 左手距離權重用大門檻強制貼柄（斬擊整段都是雙手握，起手那一格左手離柄遠，由 left_blend_time 淡入）。
const IK_SCRIPT := preload("res://characters/yoriichi/r62_grip_ik.gd")
const GRIP_JSON := "res://characters/yoriichi/v24_r62/r62_grip.json"
const RAMP_IN := 0.10
const RAMP_OUT := 0.16

var ik
var sword_hand: Node3D
var s_carry := Transform3D.IDENTITY
var s_two := Transform3D.IDENTITY
var target := 0.0
var cur := 0.0

static func _xf(rows: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]),
		Vector3(rows[0][2], rows[1][2], rows[2][2])), Vector3(rows[0][3], rows[1][3], rows[2][3]))

static func _quats(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var q: Array = d[k]
		out[k] = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	return out

func setup(sk: Skeleton3D, sword_hand_: Node3D, child_index := 2) -> void:
	sword_hand = sword_hand_
	s_carry = sword_hand.transform
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GRIP_JSON))
	ik = IK_SCRIPT.new()
	ik.name = "IsshinTwoHandGrip"
	sk.add_child(ik)
	sk.move_child(ik, child_index)
	ik.sock_old = s_carry
	s_two = _xf(d["sock_new"])
	ik.sock_new = s_two
	ik.left_rel = _xf(d["left_rel"])
	ik.right_fingers = _quats(d.get("right_fingers", {}))
	ik.left_fingers = _quats(d.get("left_fingers", {}))
	ik.left_enabled = true
	ik.left_d0 = 0.60
	ik.left_d1 = 0.70
	ik.left_blend_time = 0.10
	ik.swivel_search = true
	var axd: Dictionary = d.get("axes", {})
	for side in axd:
		var a: Dictionary = axd[side]
		ik.axes[side] = {"f": Vector3(a["f"][0], a["f"][1], a["f"][2]), "flex": Vector3(a["flex"][0], a["flex"][1], a["flex"][2]),
			"ulnar": Vector3(a["ulnar"][0], a["ulnar"][1], a["ulnar"][2])}

func step(delta: float) -> void:
	var rate := delta / (RAMP_IN if target > cur else RAMP_OUT)
	cur = move_toward(cur, target, rate)
	ik.right_weight = cur
	sword_hand.transform = s_carry.interpolate_with(s_two, cur)
