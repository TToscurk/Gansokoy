extends SceneTree
## 算刀鞘掛角 + 量有沒有陷進衣服。每幀重算 BodyVisual 逆矩陣（角色會自由落體，
## 快取 binv 會讓高度讀數整個歪掉）。
## Run: godot --headless --path godot --script tools/fit_sheath_hang.gd -- <pitch> <out> <push>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pitch_deg := 55.0
	var out_bias := 0.16
	var push := 0.0
	if args.size() >= 1:
		pitch_deg = float(args[0])
	if args.size() >= 2:
		out_bias = float(args[1])
	if args.size() >= 3:
		push = float(args[2])

	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	for i in 4:
		await process_frame

	var body: Node3D = p.get_node("BodyVisual")
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var sock: Node3D = p.find_children("SheathSocket", "", true, false)[0]
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	var sws: Node3D = p.find_children("Sword_Sheathed", "", true, false)[0]

	var binv := body.global_transform.affine_inverse()
	var li := skel.find_bone("LeftUpLeg")
	var ri := skel.find_bone("RightUpLeg")
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(li).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(ri).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	var horiz := cos(deg_to_rad(pitch_deg))
	var down := sin(deg_to_rad(pitch_deg))
	var back_amt := sqrt(maxf(horiz * horiz - out_bias * out_bias, 0.0))
	var tip := (-fwd * back_amt + side * out_bias - Vector3.UP * down).normalized()
	var mune_hint := (-Vector3.UP * 0.55 + side * 0.84).normalized()
	var mune := (mune_hint - tip * mune_hint.dot(tip)).normalized()
	var third := tip.cross(mune).normalized()
	var basis_body := Basis(mune, tip, third)
	if basis_body.determinant() < 0.0:
		basis_body = Basis(mune, tip, -third)

	# 世界目標 basis → local（用「真實」父 basis，不做 orthonormalize，
	# 因為 FBX 骨架帶 0.01 縮放，orthonormalize 會讓角度算歪 5°）
	var want_world := body.global_transform.basis * basis_body
	var parent_basis: Basis = sh.get_parent_node_3d().global_transform.basis
	var local_basis := parent_basis.inverse() * want_world

	# 往外推，脫離衣服表面
	var new_origin: Vector3 = sh.transform.origin
	if push != 0.0:
		var push_local: Vector3 = parent_basis.inverse() * (body.global_transform.basis * side) * push
		new_origin += push_local

	var xf := Transform3D(local_basis, new_origin)
	sh.transform = xf
	sws.transform = xf
	await process_frame
	await process_frame

	# 每幀重算 binv 再量
	binv = body.global_transform.affine_inverse()
	var tip_dir := (binv.basis * sh.global_transform.basis * Vector3(0, 1, 0)).normalized()
	var mune_dir := (binv.basis * sh.global_transform.basis * Vector3(1, 0, 0)).normalized()
	var org: Vector3 = binv * sh.global_transform.origin
	var tip_pt: Vector3 = org + tip_dir * 0.952
	var hipy: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin)

	print("=== pitch=%.0f out=%.2f push=%.3f ===" % [pitch_deg, out_bias, push])
	print("  俯角 %.1f°（原本 36.4）  後向 %+.2f（原本 -0.80 即朝前）  外撇 %+.2f" % [
		rad_to_deg(atan2(-tip_dir.y, Vector2(tip_dir.x, tip_dir.z).length())),
		tip_dir.dot(-fwd), tip_dir.dot(side)])
	print("  刀背朝下 %+.2f（負=刃朝上，打刀佩法）" % mune_dir.y)
	print("  髖心 y=%.3f | 鞘口 y=%.3f | 鞘尾 y=%.3f m" % [hipy.y, org.y, tip_pt.y])
	print("  鞘尾在身後 %.3f m、離中線側向 %.3f m" % [(tip_pt - org).dot(-fwd), absf(tip_pt.dot(side))])

	# 穿模檢查：角色身體頂點落在刀鞘 OBB 內的數量
	var sxf: Transform3D = sh.global_transform
	var sinv := sxf.affine_inverse()
	var inside := 0
	var total := 0
	var min_gap := 99.0
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		# 排除刀／鞘自己（它們掛在 BodyVisual 底下，不排除就是拿刀鞘量刀鞘）
		var is_gear := false
		var anc: Node = mi
		while anc != null:
			if anc.name.begins_with("Sword") or anc.name.begins_with("Sheath"):
				is_gear = true
				break
			anc = anc.get_parent()
		if is_gear:
			continue
		var g := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var va: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for vi in range(0, va.size(), 7):
				var w: Vector3 = g * va[vi]
				var l: Vector3 = sinv * w
				if l.y < -0.02 or l.y > 0.95:
					continue
				total += 1
				var r := Vector2(l.x, l.z).length()
				min_gap = minf(min_gap, r)
				if r < 0.028:
					inside += 1
	print("  穿模：鞘身走廊內身體頂點 %d / %d（最近 %.3f m，鞘半徑約 0.030）" % [inside, total, min_gap])
	print("\n  local rotation 度 (YXZ): x=%.4f y=%.4f z=%.4f" % [
		rad_to_deg(local_basis.get_euler(EULER_ORDER_YXZ).x),
		rad_to_deg(local_basis.get_euler(EULER_ORDER_YXZ).y),
		rad_to_deg(local_basis.get_euler(EULER_ORDER_YXZ).z)])
	print("  Transform3D(%s, %s)" % [_b(local_basis), _v(new_origin)])
	quit()


func _b(b: Basis) -> String:
	return "%.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f" % [
		b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


func _v(v: Vector3) -> String:
	return "%.6f, %.6f, %.6f" % [v.x, v.y, v.z]
