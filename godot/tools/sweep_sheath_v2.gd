extends SceneTree
## 掛角掃描（同幀取樣版）。角色在無地板場景會自由落體，所以腳底與鞘尾必須在
## 同一幀讀出來，否則差值會隨落下距離漂移。全部改成相對 Hips 骨，並在設完
## transform 後同一幀內完成量測。
## Run: godot --headless --path godot --script tools/sweep_sheath_v2.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	for i in 4:
		await process_frame

	var body: Node3D = p.get_node("BodyVisual")
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	var sws: Node3D = p.find_children("Sword_Sheathed", "", true, false)[0]

	# 靜態方向基準（bind pose，站姿，不隨落下改變）
	var binv: Transform3D = body.global_transform.affine_inverse()
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftUpLeg")).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightUpLeg")).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	print("pitch 外撇 | 鞘尾低於腳底 | 鞘尾在身後 | 鞘尾外撇 | 刀背朝下 | 俯角實測")
	for pitch_deg in [16.0, 20.0, 24.0, 28.0, 32.0]:
		for out_bias in [0.10, 0.16]:
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
			var want: Basis = body.global_transform.basis * bb
			var lb: Basis = (sh.get_parent_node_3d().global_transform.basis).inverse() * want
			var xf := Transform3D(lb, sh.transform.origin)
			sh.transform = xf
			sws.transform = xf
			await process_frame

			# ↓↓↓ 以下全部在同一幀內取樣 ↓↓↓
			var b2: Transform3D = body.global_transform.affine_inverse()
			# 腳底：骨架最低骨（同幀）
			var foot := 1e9
			for bi in skel.get_bone_count():
				foot = minf(foot, (b2 * (skel.global_transform * skel.get_bone_global_pose(bi).origin)).y)
			var org: Vector3 = b2 * sh.global_transform.origin
			var far_d := -1.0
			var far_pt := Vector3.ZERO
			for m in sh.find_children("*", "MeshInstance3D", true, false):
				var mi: MeshInstance3D = m
				if mi.mesh == null:
					continue
				var g: Transform3D = b2 * mi.global_transform
				for si in mi.mesh.get_surface_count():
					var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					for vi in range(0, va.size(), 5):
						var w: Vector3 = g * va[vi]
						var d := (w - org).length()
						if d > far_d:
							far_d = d
							far_pt = w
			var md: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(1, 0, 0)).normalized()
			var td: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(0, 1, 0)).normalized()
			var rel := far_pt - org
			print("%3.0f° %.2f | %+.3f m | %+.3f m | %+.3f m | %+.2f | %.1f°" % [
				pitch_deg, out_bias,
				far_pt.y - foot,
				rel.dot(-fwd), rel.dot(side), md.y,
				rad_to_deg(atan2(-td.y, Vector2(td.x, td.z).length()))])
	quit()
