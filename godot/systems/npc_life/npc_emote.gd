extends SkeletonModifier3D
## 情緒身體反應（程序化疊加，不改角色資產）：在動畫與 LookAt 之後，對 Chest／Head 骨疊一點旋轉。
## 角度在 Skeleton 空間（模型正面＝+Z）：pitch 繞 +X（正＝低頭／前傾）、yaw 繞 +Y、roll 繞 +Z（歪頭）。
## play(emo, dur)：attack → hold（dur 秒，約等於這句語音長）→ release；osc＝短暫的搖頭／點頭／笑的晃動。

const PROFILES := {
	# 驚訝：上身後仰、抬頭，來得快
	"surprised": {"bones": {"Chest": [-11.0, 0.0, 0.0], "Head": [-15.0, 0.0, 0.0]}, "attack": 0.10, "hold_max": 1.0, "release": 0.7},
	# 疑惑：歪頭、稍微往前探
	"doubt": {"bones": {"Head": [3.0, 6.0, 13.0], "Chest": [2.0, 0.0, 0.0]}, "attack": 0.35, "release": 0.5},
	# 不滿：前傾、低一點頭、搖頭
	"annoyed": {"bones": {"Chest": [5.0, 0.0, 0.0], "Head": [5.0, 0.0, 0.0]}, "attack": 0.2, "release": 0.4,
		"osc": {"bone": "Head", "axis": 1, "amp": 7.0, "hz": 2.4, "dur": 0.9}},
	# 開心：抬頭、上身小幅晃（笑）
	"happy": {"bones": {"Head": [-4.0, 0.0, 0.0]}, "attack": 0.15, "release": 0.4,
		"osc": {"bone": "Chest", "axis": 0, "amp": 3.5, "hz": 4.0, "dur": 0.8}},
	# 無奈／嘆氣：慢慢低頭、垂肩
	"sigh": {"bones": {"Head": [13.0, 0.0, 0.0], "Chest": [6.0, 0.0, 0.0]}, "attack": 0.6, "release": 0.8},
	# 得意：抬下巴、微歪頭
	"smug": {"bones": {"Head": [-7.0, 0.0, 5.0], "Chest": [-3.0, 0.0, 0.0]}, "attack": 0.25, "release": 0.5},
	# 認真：微低頭、身體正面不動
	"serious": {"bones": {"Head": [4.0, 0.0, 0.0], "Chest": [2.0, 0.0, 0.0]}, "attack": 0.3, "release": 0.5},
	# 害羞／尷尬：低頭、別開臉
	"embarrassed": {"bones": {"Head": [9.0, 12.0, 0.0]}, "attack": 0.25, "release": 0.6},
	# 擔心：低頭、微歪
	"worried": {"bones": {"Head": [6.0, 0.0, -6.0], "Chest": [3.0, 0.0, 0.0]}, "attack": 0.35, "release": 0.6},
	# 思考（說話前的停頓）：歪頭、看旁邊
	"thinking": {"bones": {"Head": [2.0, -10.0, 8.0]}, "attack": 0.35, "release": 0.4},
	# 聆聽時點頭
	"nod": {"bones": {}, "attack": 0.05, "release": 0.1, "osc": {"bone": "Head", "axis": 0, "amp": 6.0, "hz": 2.2, "dur": 0.9}},
}

var _emo := ""
var _t := 0.0
var _hold := 0.0
var _amp := 0.0
var _w := 0.0          # 目前包絡（0..1）
var _p: Dictionary = {}
var _bone_idx := {}


## 開始一個情緒反應；dur＝持續（秒），intensity 0..1.5
func play(emo: String, dur := 1.0, intensity := 1.0) -> void:
	if not PROFILES.has(emo):
		return
	_emo = emo
	_p = PROFILES[emo]
	_t = 0.0
	_hold = minf(dur, float(_p.get("hold_max", 99.0)))
	_amp = intensity


func current() -> String:
	return _emo if not _p.is_empty() and _w > 0.01 else ""


func weight() -> float:
	return _w


func _process_modification_with_delta(dt: float) -> void:
	var sk := get_skeleton()
	if sk == null or _p.is_empty():
		return
	_t += dt
	var a := float(_p.attack)
	var r := float(_p.release)
	if _t < a:
		_w = _t / a
	elif _t < a + _hold:
		_w = 1.0
	elif _t < a + _hold + r:
		_w = 1.0 - (_t - a - _hold) / r
	else:
		_w = 0.0
	_w = smoothstep(0.0, 1.0, _w)
	var osc: Dictionary = _p.get("osc", {})
	var ow := 0.0
	if not osc.is_empty() and _t < float(osc.dur):
		ow = sin(_t * TAU * float(osc.hz)) * (1.0 - _t / float(osc.dur))
	if _w <= 0.001 and ow == 0.0:
		if _t > a + _hold + r + 0.1 and (osc.is_empty() or _t > float(osc.dur)):
			_p = {}
		return
	# 先 Chest 再 Head（Head 的全域姿勢要吃到 Chest 的改變）
	for bn in ["Chest", "Head"]:
		var e := Vector3.ZERO
		var b: Array = (_p.bones as Dictionary).get(bn, [])
		if b.size() == 3:
			e = Vector3(b[0], b[1], b[2]) * _w * _amp
		if not osc.is_empty() and String(osc.bone) == bn:
			e[int(osc.axis)] += float(osc.amp) * ow * _amp
		if e == Vector3.ZERO:
			continue
		var bi := _bone(sk, bn)
		if bi < 0:
			continue
		var gp := sk.get_bone_global_pose(bi)
		var q := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		sk.set_bone_global_pose(bi, Transform3D(Basis(q) * gp.basis, gp.origin))


func _bone(sk: Skeleton3D, bn: String) -> int:
	if not _bone_idx.has(bn):
		var i := sk.find_bone(bn)
		if i < 0 and bn == "Chest":
			i = sk.find_bone("UpperChest")
		if i < 0 and bn == "Chest":
			i = sk.find_bone("Spine")
		_bone_idx[bn] = i
	return int(_bone_idx[bn])
