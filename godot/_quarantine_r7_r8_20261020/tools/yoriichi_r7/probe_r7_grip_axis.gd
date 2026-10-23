extends SceneTree
## R7 P5c 左手握點量測（唯讀；由 probe_r7_grip_rt.gd 複製）。參照＝實際刀（Sword_Hand；地面 sock_new）× r62_grip_ik.left_rel；
## 在 skeleton_updated 後把「左手 − 參照握位」分解成沿刀軸（刀 +Y，+＝朝刀尖）與徑向距離（mm）、旋轉差（deg）。
## 格單位：f＝60 Hz 物理執行格；af＝action clock×60（60 Hz）；res_f＝af/2（30 fps 資源格，R7 以 2 倍播放）。
## 原說明：R7 P5 執行期握刀量測（唯讀）。跑一圈十三型，在 Skeleton3D.skeleton_updated（骨架＋握刀 IK 更新後）逐格記錄：
##   左手 vs 「實際刀 × left_rel」握位誤差（mm／deg）、左掌心離刀柄軸距離、右手 IK 殘差（last_err，IK 關時刀為手的子節點＝0）、
##   左右手肘位置、刀尖世界位置、IK 權重。刀＝場景中 Sword_Hand 節點的實際變換（地面＝sock_new／空中＝sock_old）。
##   R7C_SEAM_FIX=0|1 godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/probe_r7_grip_rt.gd -- <tag>
## 輸出 user://r7p5_grip_rt_<tag>.json
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
var _p: CharacterBody3D
var _sk: Skeleton3D
var _rows: Array = []
var _frame := 0
var _tip: Node3D
var _sw: Node3D
var _ik


func _initialize() -> void:
	call_deferred("_run")


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _on_sk() -> void:
	if _p == null or not bool(_p.call("r7c_running")):
		return
	var forms: Dictionary = _p.get("R7_FORMS")
	var f: int = _p.get("active_form")
	var inv := _sk.global_transform.affine_inverse()
	var sword := inv * _sw.global_transform
	var lg := _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftHand"))
	var lm := _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftHandMiddle1"))
	var palm := (lg.origin + lm.origin) * 0.5
	var a: Vector3 = sword * Vector3(0, -0.35, 0)
	var b: Vector3 = sword * Vector3(0, -0.005, 0)
	var ab := b - a
	var u := clampf((palm - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
	var d := (palm - (a + ab * u)).length()
	var lt: Transform3D = sword * _ik.left_rel
	var ax: Vector3 = sword.basis.y.normalized()
	var dd: Vector3 = lg.origin - lt.origin
	var axial := dd.dot(ax)
	var radial := (dd - ax * axial).length()
	var qa := lg.basis.orthonormalized().get_rotation_quaternion()
	var qb := lt.basis.orthonormalized().get_rotation_quaternion()
	var gx := _sk.global_transform
	_rows.append({"f": _frame, "ref": String(forms[f].ref) if forms.has(f) else "", "anim": str(_p.get("_active_attack_name")),
		"af": snappedf(float(_p.get("_action_elapsed")) * 60.0, 0.01),
		"ikr": snappedf(float(_ik.right_weight), 0.01), "ikl": snappedf(float(_ik._lw), 0.01), "left_on": bool(_ik.left_enabled),
		"l_mm": snappedf(lg.origin.distance_to(lt.origin) * 1000.0, 0.1), "l_deg": snappedf(rad_to_deg(qa.angle_to(qb)), 0.1),
		"l_axis_mm": snappedf(d * 1000.0, 0.1), "l_along_mm": snappedf(axial * 1000.0, 0.1), "l_radial_mm": snappedf(radial * 1000.0, 0.1), "res_f": snappedf(float(_p.get("_action_elapsed")) * 30.0, 0.01),
		"r_err": [snappedf(float(_ik.last_err[0]), 0.1), snappedf(float(_ik.last_err[1]), 0.1)] if float(_ik.right_weight) > 0.001 else [0.0, 0.0],
		"el_l": _v(gx * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftForeArm")).origin),
		"el_r": _v(gx * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_RightForeArm")).origin),
		"tip": _v(_tip.global_position), "pos": _v(_p.global_position), "seam": str(_p.get("r7c_seam_used"))})


func _run() -> void:
	var tag := "run"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = args[0]
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var w := Node3D.new()
	root.add_child(w)
	var g := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(200, 1, 200)
	cs.shape = bx
	g.add_child(cs)
	g.position = Vector3(0, -0.5, 0)
	w.add_child(g)
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	_p.set("form13_unlocked", true)
	w.add_child(_p)
	for i in 12:
		await physics_frame
	_p.call("request_draw")
	for i in 100:
		await physics_frame
	_sk = (_p.get("_visual") as Node).find_children("*", "Skeleton3D", true, false)[0]
	_tip = _p.get("_blade_tip")
	_sw = _p.get("_sword_hand")
	_ik = _p.get("_r62_ik")
	_sk.skeleton_updated.connect(_on_sk)
	_p.set("r7c_hold_to_continue", false)
	var ok := bool(_p.call("start_form13"))
	for i in 60 * 30:
		await physics_frame
		_frame += 1
		var n := 0
		for e in _p.get("r7c_log"):
			if e.ev == "start":
				n += 1
		if n >= 13:
			_p.call("r7c_request_stop")
		if not bool(_p.call("r7c_running")):
			break
	var fo := FileAccess.open("user://r7p5c_grip_axis_%s.json" % tag, FileAccess.WRITE)
	fo.store_string(JSON.stringify({"seam_fix": _p.get("r7c_seam_fix"), "started": ok, "log": _p.get("r7c_log"), "rows": _rows}))
	fo.close()
	print("R7P5C_GRIP_AXIS tag=", tag, " fix=", _p.get("r7c_seam_fix"), " rows=", _rows.size())
	quit(0)
