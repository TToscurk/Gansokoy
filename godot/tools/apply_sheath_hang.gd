extends SceneTree
## 定版：設定掛角，量「相對角色網格最低點（真地面）」的鞘尾高度，印出要寫進
## .tscn 的 local Transform3D。
## Run: godot --headless --path godot --script tools/apply_sheath_hang.gd -- <pitch> <out>

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pitch_deg := 38.0
	var out_bias := 0.14
	if args.size() >= 1:
		pitch_deg = float(args[0])
	if args.size() >= 2:
		out_bias = float(args[1])

	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	for i in 4:
		await process_frame

	var body: Node3D = p.get_node("BodyVisual")
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	var sws: Node3D = p.find_children("Sword_Sheathed", "", true, false)[0]
	sh.set_process(false)
	sws.set_process(false)

	var binv: Transform3D = body.global_transform.affine_inverse()
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftUpLeg")).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightUpLeg")).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	var horiz := cos(deg_to_rad(pitch_deg))
	var down := sin(deg_to_rad(pitch_deg))
	var back_amt := sqrt(maxf(horiz * horiz - out_bias * out_bias, 0.0))
	var tip: Vector3 = (-fwd * back_amt + side * out_bias - Vector3.UP * down).normalized()
	var mh: Vector3 = (-Vector3.UP * 0.55 + side * 0.84).normalized()
	var mune: Vector3 = (mh - tip * mh.dot(tip)).normalized()
	var third: Vector3 = tip.cross(mune).normalized()
	var bb := Basis(mune, tip, third)
	if bb.determinant() < 0.0:
		bb = Basis(mune, tip, -third)
	var want: Basis = body.global_transform.basis.orthonormalized() * bb
	sh.global_transform = Transform3D(want, sh.global_transform.origin)
	sws.global_transform = Transform3D(want, sws.global_transform.origin)
	await process_frame
	await process_frame

	# 真地面 = 角色本體網格最低頂點（同幀、排除刀與鞘）
	var b2: Transform3D = body.global_transform.affine_inverse()
	var floor_y := 1e9
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var gear := false
		var anc: Node = mi
		while anc != null:
			if anc.name.begins_with("Sword") or anc.name.begins_with("Sheath"):
				gear = true
				break
			anc = anc.get_parent()
		if gear:
			continue
		var g: Transform3D = b2 * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for vi in range(0, va.size(), 3):
				floor_y = minf(floor_y, (g * va[vi]).y)

	var org: Vector3 = b2 * sh.global_transform.origin
	var far_d := -1.0
	var far_pt := Vector3.ZERO
	var lo := 1e9
	for m in sh.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var g: Transform3D = b2 * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in va:
				var w: Vector3 = g * v
				lo = minf(lo, w.y)
				var d := (w - org).length()
				if d > far_d:
					far_d = d
					far_pt = w
	var td: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(0, 1, 0)).normalized()
	var md: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(1, 0, 0)).normalized()
	var rel := far_pt - org

	print("=== pitch=%.0f out=%.2f ===" % [pitch_deg, out_bias])
	print("  實測俯角 %.1f°（原本 36.4° 但朝前）" % rad_to_deg(atan2(-td.y, Vector2(td.x, td.z).length())))
	print("  鞘尾在身後 %+.3f m、外撇 %+.3f m" % [rel.dot(-fwd), rel.dot(side)])
	print("  刀背朝下 %+.2f（負=刃朝上）" % md.y)
	print("  角色網格最低 y=%.3f（真地面）" % floor_y)
	print("  鞘口 y=%.3f → 離地 %.3f m" % [org.y, org.y - floor_y])
	print("  鞘身最低 y=%.3f → 離地 %+.3f m %s" % [lo, lo - floor_y, ("★插進地面" if lo < floor_y else "OK")])
	print("\n  local Transform3D =")
	var b: Basis = sh.transform.basis
	var o: Vector3 = sh.transform.origin
	print("Transform3D(%.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f)" % [
		b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z])
	quit()
