extends SceneTree
## 掛角掃描 v3。修掉前兩版的兩個錯：
##  1) 設完 transform 只等 1 幀 → BoneAttachment3D 還沒更新，量到上一組數值
##     （上一版表格出現整列重複就是這個）。改成等 2 幀。
##  2) 自己算 parent.basis.inverse() * want → 骨架帶縮放時會把 scale 烙進 local
##     basis，方向也跟著歪。改成直接寫 global_transform，讓 Godot 反推 local。
## Run: godot --headless --path godot --script tools/sweep_sheath_v3.gd

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
	# sheath_sway.gd 每幀改寫 transform，量測期間必須關掉，否則寫進去的角度
	# 會被它用 _ready 時快取的 _rest 蓋回去（上一版整欄俯角卡在 ~42° 就是這個）
	sh.set_process(false)
	sws.set_process(false)

	var binv: Transform3D = body.global_transform.affine_inverse()
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftUpLeg")).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightUpLeg")).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	print("要求 外撇 | 實測俯角 | 鞘尾相對腳底 | 鞘尾在身後 | 刀背朝下 | local scale")
	for pitch_deg in [20.0, 28.0, 36.0, 44.0, 52.0]:
		for out_bias in [0.10, 0.18]:
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

			# 直接寫世界朝向，local 交給 Godot 反推
			sh.global_transform = Transform3D(want, sh.global_transform.origin)
			sws.global_transform = Transform3D(want, sws.global_transform.origin)
			await process_frame
			await process_frame

			var b2: Transform3D = body.global_transform.affine_inverse()
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
			var sc: Vector3 = sh.transform.basis.get_scale()
			print("%3.0f° %.2f | %5.1f° | %+.3f m | %+.3f m | %+.2f | %.2f" % [
				pitch_deg, out_bias,
				rad_to_deg(atan2(-td.y, Vector2(td.x, td.z).length())),
				far_pt.y - foot, rel.dot(-fwd), md.y, sc.x])
	quit()
