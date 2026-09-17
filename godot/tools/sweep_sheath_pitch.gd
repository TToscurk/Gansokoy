extends SceneTree
## 掃描掛角，量「刀鞘實際網格最遠端」的離地高度，挑不會插進地面的角度。
## Run: godot --headless --path godot --script tools/sweep_sheath_pitch.gd

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
	var binv: Transform3D = body.global_transform.affine_inverse()

	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftUpLeg")).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightUpLeg")).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	# 腳底基準：取角色網格最低頂點（bind pose 夠用，站姿）
	var floor_y := 1e9
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null or mi.name.begins_with("Sword") or mi.name.begins_with("Sheath"):
			continue
		var anc: Node = mi
		var gear := false
		while anc != null:
			if anc.name.begins_with("Sword") or anc.name.begins_with("Sheath"):
				gear = true
				break
			anc = anc.get_parent()
		if gear:
			continue
		var g: Transform3D = p.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in va:
				floor_y = minf(floor_y, (g * v).y)
	print("角色腳底 y=%.3f（Player 空間）\n" % floor_y)
	print("pitch  外撇  鞘尾離地   鞘尾在身後   鞘口離地   刀背朝下")

	for pitch_deg in [18.0, 22.0, 26.0, 30.0, 34.0, 38.0, 42.0]:
		for out_bias in [0.12, 0.18]:
			var horiz := cos(deg_to_rad(pitch_deg))
			var down := sin(deg_to_rad(pitch_deg))
			var back_amt := sqrt(maxf(horiz * horiz - out_bias * out_bias, 0.0))
			var tip: Vector3 = (-fwd * back_amt + side * out_bias - Vector3.UP * down).normalized()
			var mune_hint: Vector3 = (-Vector3.UP * 0.55 + side * 0.84).normalized()
			var mune: Vector3 = (mune_hint - tip * mune_hint.dot(tip)).normalized()
			var third: Vector3 = tip.cross(mune).normalized()
			var bb := Basis(mune, tip, third)
			if bb.determinant() < 0.0:
				bb = Basis(mune, tip, -third)
			var want_world: Basis = body.global_transform.basis * bb
			var pbasis: Basis = sh.get_parent_node_3d().global_transform.basis
			var lb: Basis = pbasis.inverse() * want_world
			var xf := Transform3D(lb, sh.transform.origin)
			sh.transform = xf
			sws.transform = xf
			await process_frame

			var pinv: Transform3D = p.global_transform.affine_inverse()
			var org: Vector3 = pinv * sh.global_transform.origin
			var far_d := -1.0
			var far_pt := Vector3.ZERO
			for m in sh.find_children("*", "MeshInstance3D", true, false):
				var mi: MeshInstance3D = m
				if mi.mesh == null:
					continue
				var g: Transform3D = pinv * mi.global_transform
				for si in mi.mesh.get_surface_count():
					var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					for vi in range(0, va.size(), 5):
						var w: Vector3 = g * va[vi]
						var d := (w - org).length()
						if d > far_d:
							far_d = d
							far_pt = w
			var md := (pinv.basis * sh.global_transform.basis * Vector3(1, 0, 0)).normalized()
			print("%4.0f°  %.2f   %+.3f m   %+.3f m   %.3f m   %+.2f" % [
				pitch_deg, out_bias, far_pt.y - floor_y,
				(far_pt - org).dot(-fwd), org.y - floor_y, md.y])
	quit()
