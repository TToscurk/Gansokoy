extends SceneTree
## R7 握柄量測（只讀）：逐格記錄 IK 之後的右手指關節到刀柄軸距離、Sword_Hand 與「手骨×插槽」的偏差、右手權重。
## godot --path . --fixed-fps 30 -s res://tools/yoriichi_r7/probe_grip_r7.gd
const FING := ["Index", "Middle", "Ring", "Pinky", "Thumb"]
var p: CharacterBody3D
var sk: Skeleton3D
var rows: Array = []
var t := 0.0
var fr := 0

func _initialize():
	var g := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(50, 1, 50); cs.shape = bx; g.add_child(cs); g.position = Vector3(0, -0.5, 0); root.add_child(g)
	p = (load("res://characters/yoriichi/player_yoriichi_r7.tscn") as PackedScene).instantiate()
	root.add_child(p)

func _ev(a: String, on: bool):
	var e := InputEventAction.new(); e.action = a; e.pressed = on; Input.parse_input_event(e)

func _process(d: float) -> bool:
	t += d
	if sk == null and p.get("_visual") != null:
		sk = p._visual.find_children("*", "Skeleton3D", true, false)[0]
		sk.skeleton_updated.connect(_on_skel)
	if fr == 6: p.call("request_draw")
	if fr == 70 or fr == 76 or fr == 84:
		_ev("attack_light", true); _ev("attack_light", false)
	if fr == 140:
		_ev("attack_heavy", true); _ev("attack_heavy", false)
	fr += 1
	if fr > 200:
		_report(); return true
	return false

func _on_skel():
	if fr < 30 or p._sword_hand == null or not p._sword_hand.visible:
		return
	var sx: Transform3D = p._sword_hand.global_transform
	var a := sx * Vector3(0, -0.35, 0)
	var b := sx * Vector3(0, -0.01, 0)
	var row := {"f": fr, "atk": str(p._active_attack_name), "w": p._r62_ik.right_weight if p._r62_ik else -1.0}
	var hb := sk.find_bone("mixamorig_RightHand")
	var expect: Transform3D = sk.global_transform * sk.get_bone_global_pose(hb) * p._r62_ik.sock_new
	row["socket_lag_mm"] = snappedf(sx.origin.distance_to(expect.origin) * 1000.0, 0.1)
	var gaps := {}
	for f in FING:
		for k in [1, 2, 3]:
			var bi := sk.find_bone("mixamorig_RightHand%s%d" % [f, k])
			if bi < 0: continue
			var pt := sk.global_transform * sk.get_bone_global_pose(bi).origin
			var ab := b - a
			var u := clampf((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			gaps["%s%d" % [f, k]] = snappedf(((pt - (a + ab * u)).length() - 0.0153) * 1000.0, 0.1)
	row["gap_mm"] = gaps
	var palm := sk.global_transform * ((sk.get_bone_global_pose(hb).origin + sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHandMiddle1")).origin) * 0.5)
	var ab2 := b - a
	var u2 := clampf((palm - a).dot(ab2) / ab2.length_squared(), 0.0, 1.0)
	row["palm_mm"] = snappedf(((palm - (a + ab2 * u2)).length() - 0.0153) * 1000.0, 0.1)
	row["along"] = snappedf(u2, 0.01)
	rows.append(row)

func _report():
	var f := FileAccess.open("user://r7_grip_probe.json", FileAccess.WRITE); f.store_string(JSON.stringify(rows)); f.close()
	print("ROWS ", rows.size())
	quit()
