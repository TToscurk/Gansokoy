extends SceneTree
## R4：實機量測持刀時右手指關節到刀柄軸距離（Godot runtime，與 Blender 稽核同一定義）。
##   godot --headless --path . -s res://tools/yoriichi_r4/r4_grip_probe.gd -- [player.tscn]
var _p: Node
var _t := 0.0
var _done := false
var _path := "res://characters/yoriichi/player_yoriichi_r4.tscn"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_path = a[0]
	_p = (load(_path) as PackedScene).instantiate()
	root.add_child(_p)
	var g := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(50, 1, 50)
	cs.shape = bs
	g.add_child(cs)
	g.position = Vector3(0, -0.5, 0)
	root.add_child(g)

func _process(delta: float) -> bool:
	_t += delta
	if _t > 0.2 and _t - delta <= 0.2:
		_p.call("request_draw")
	if _t > 2.5 and not _done:
		_done = true
		var sk: Skeleton3D = _p.find_children("*", "Skeleton3D", true, false)[0]
		var sh := _p.find_child("Sword_Hand", true, false) as Node3D
		var M := sh.global_transform
		var a0 := M * Vector3(0, -0.35, 0)
		var a1 := M * Vector3(0, -0.005, 0)
		var ax := (a1 - a0).normalized()
		var out := {}
		for fn in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var row := []
			for k in [1, 2, 3, 4]:
				var bi := sk.find_bone("mixamorig_RightHand%s%d" % [fn, k])
				if bi < 0:
					continue
				var p := sk.global_transform * sk.get_bone_global_pose(bi).origin
				var tt := (p - a0).dot(ax)
				row.append(snappedf((p - (a0 + ax * tt)).length() * 100.0, 0.01))
			out[fn] = row
		print("GRIP_PROBE ", _path, " sword_state=", _p.get("sword_state"), " dist_cm=", JSON.stringify(out),
			" sword_scale=", [M.basis.x.length(), M.basis.y.length(), M.basis.z.length()])
		quit()
	return false
