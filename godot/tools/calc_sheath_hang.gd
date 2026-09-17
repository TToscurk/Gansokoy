extends SceneTree
## 算出「刀鞘自然垂掛」的新 local 旋轉：刀尖朝後下、刀背朝下（刃朝上＝打刀佩法）。
## 印出 Sheath / Sword_Sheathed 要設的 rotation（度），不寫檔。
## Run: godot --headless --path godot --script tools/calc_sheath_hang.gd -- <pitch_deg> <back> <out>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pitch_deg := 50.0
	var out_bias := 0.16
	if args.size() >= 1:
		pitch_deg = float(args[0])
	if args.size() >= 2:
		out_bias = float(args[1])

	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	await process_frame
	await process_frame

	var body: Node3D = p.get_node("BodyVisual")
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var binv := body.global_transform.affine_inverse()

	var li := skel.find_bone("LeftUpLeg")
	var ri := skel.find_bone("RightUpLeg")
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(li).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(ri).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()                       # 角色左
	var fwd := Vector3.UP.cross(side).normalized() # 角色正面

	# 目標刀尖方向：後 + 下 + 一點外撇
	var horiz := cos(deg_to_rad(pitch_deg))
	var down := sin(deg_to_rad(pitch_deg))
	var back_amt := sqrt(maxf(horiz * horiz - out_bias * out_bias, 0.0))
	var tip := (-fwd * back_amt + side * out_bias - Vector3.UP * down).normalized()

	# 刀背（local +X，刀尖彎向那側）朝下外 → 刃朝上
	var mune_hint := (-Vector3.UP * 0.55 + side * 0.84).normalized()
	var mune := (mune_hint - tip * mune_hint.dot(tip)).normalized()
	var third := tip.cross(mune).normalized()

	# 本地軸：+Y=tip, +X=mune, +Z=third（右手系檢查）
	var basis_body := Basis(mune, tip, third)
	if basis_body.determinant() < 0.0:
		basis_body = Basis(mune, tip, -third)

	var sock: Node3D = p.find_children("SheathSocket", "", true, false)[0]
	var sock_body_basis := (binv.basis * sock.global_transform.basis).orthonormalized()
	var local_basis := sock_body_basis.inverse() * basis_body
	var euler := local_basis.get_euler(EULER_ORDER_YXZ)

	print("=== 目標（角色空間）===")
	print("  俯角 %.1f°   刀尖 x=%+.3f y=%+.3f z=%+.3f" % [pitch_deg, tip.x, tip.y, tip.z])
	print("  後向分量 %.2f（+=朝後）  外撇 %.2f" % [tip.dot(-fwd), tip.dot(side)])
	print("  刀背朝下分量 %.2f（負=朝下，刃朝上）" % mune.y)
	print("\n=== 要設的 local rotation（Godot Inspector，度，順序 YXZ）===")
	print("  rotation_order = 2 (YXZ)")
	print("  x=%.4f  y=%.4f  z=%.4f" % [rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)])
	print("  弧度 x=%.6f y=%.6f z=%.6f" % [euler.x, euler.y, euler.z])

	# 驗算：套回去量刀尖端點高度
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	sh.transform = Transform3D(local_basis, sh.transform.origin)
	await process_frame
	var tip_dir := (binv.basis * sh.global_transform.basis * Vector3(0, 1, 0)).normalized()
	var org: Vector3 = binv * sh.global_transform.origin
	var tip_pt: Vector3 = org + tip_dir * 0.952
	print("\n=== 驗算（套用後）===")
	print("  實測俯角 %.1f°  後向 %.2f  外撇 %.2f" % [
		rad_to_deg(atan2(-tip_dir.y, Vector2(tip_dir.x, tip_dir.z).length())),
		tip_dir.dot(-fwd), tip_dir.dot(side)])
	print("  鞘口 y=%.3f m → 鞘尾 y=%.3f m（地面 0，角色高約 1.75 m）" % [org.y, tip_pt.y])
	print("  鞘尾離身體中線水平 %.3f m" % Vector2(tip_pt.x, tip_pt.z).length())
	quit()
