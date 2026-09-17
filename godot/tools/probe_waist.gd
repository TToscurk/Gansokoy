extends SceneTree
## 乾淨版：用 Hips 骨的基底量朝向，只取腰帶高度且靠近髖心的頂點量布面半徑，
## 並檢查刀鞘網格有沒有埋進衣服。
## Run: godot --headless --path godot --script tools/probe_waist.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	await process_frame
	await process_frame

	var body: Node3D = p.get_node("BodyVisual")
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var binv := body.global_transform.affine_inverse()
	var hi := skel.find_bone("Hips")
	var hips_xf: Transform3D = binv * (skel.global_transform * skel.get_bone_global_pose(hi))
	print("Hips 基底（角色空間）")
	print("  X 軸 %s" % _fmt(hips_xf.basis.x.normalized()))
	print("  Y 軸 %s" % _fmt(hips_xf.basis.y.normalized()))
	print("  Z 軸 %s" % _fmt(hips_xf.basis.z.normalized()))
	print("  原點 %s" % _fmt(hips_xf.origin))

	# 角色正面：脊椎橫軸 × 上方向
	var li := skel.find_bone("LeftUpLeg")
	var ri := skel.find_bone("RightUpLeg")
	var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(li).origin)
	var rp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(ri).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()
	print("\n左右軸（右髖→左髖）= %s" % _fmt(side))
	print("正面（= up × side）  = %s" % _fmt(fwd))

	# 腰部布面：y 0.88~1.06 且距髖心水平 < 0.35 m（排除手臂）
	var hc := Vector3(hips_xf.origin.x, 0, hips_xf.origin.z)
	var pts: Array[Vector3] = []
	var sheath_pts: Array[Vector3] = []
	for m in p.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var is_gear := false
		var n: Node = mi
		while n != null:
			if n.name.begins_with("Sword") or n.name.begins_with("Sheath"):
				is_gear = true
			n = n.get_parent()
		var xf := binv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var va: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for vi in range(0, va.size(), 3):
				var w: Vector3 = xf * va[vi]
				if is_gear:
					if mi.name.begins_with("Sheath") or (n != null):
						pass
					sheath_pts.append(w)
				elif w.y > 0.88 and w.y < 1.06:
					if Vector3(w.x - hc.x, 0, w.z - hc.z).length() < 0.35:
						pts.append(w)
	print("\n腰部布料取樣 %d 點（髖心 x=%+.3f z=%+.3f）" % [pts.size(), hc.x, hc.z])
	var dirs := {
		"左  ": side,
		"左前": (side + fwd).normalized(),
		"前  ": fwd,
		"左後": (side - fwd).normalized(),
	}
	for k in dirs:
		var d: Vector3 = dirs[k]
		var best := -1.0
		for v in pts:
			var rel := Vector3(v.x - hc.x, 0, v.z - hc.z)
			if rel.length() > 0.001 and rel.normalized().dot(d) > 0.9:
				best = maxf(best, rel.length())
		print("  %s 方向 布面半徑 %.3f m" % [k, best])

	# 刀鞘掛點相對髖心
	var sh := p.find_children("Sheath", "", true, false)
	if not sh.is_empty():
		var sn: Node3D = sh[0]
		var sp: Vector3 = binv * sn.global_transform.origin
		var rel := Vector3(sp.x - hc.x, 0, sp.z - hc.z)
		print("\n刀鞘掛點 %s" % _fmt(sp))
		print("  距髖心水平 %.3f m；側向分量 %.3f、前後分量 %.3f（+前）" % [rel.length(), rel.dot(side), rel.dot(fwd)])
		var dir_body := (binv.basis * sn.global_transform.basis * Vector3(0, 1, 0)).normalized()
		print("  刀尖方向 %s" % _fmt(dir_body))
		print("  俯角 %.1f°；側向 %.2f、前後 %.2f（+前）" % [rad_to_deg(atan2(-dir_body.y, Vector2(dir_body.x, dir_body.z).length())), dir_body.dot(side), dir_body.dot(fwd)])

	quit()


func _fmt(v: Vector3) -> String:
	return "x=%+.3f y=%+.3f z=%+.3f" % [v.x, v.y, v.z]
