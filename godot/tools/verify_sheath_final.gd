extends SceneTree
## 最終驗收：同一個空間、同一幀、都用「網格頂點」比較。
## 骨頭最低點 ≠ 腳底（腳踝骨離地約 6 cm），所以地面基準一律取角色本體網格最低頂點。
## Run: godot --headless --path godot --script tools/verify_sheath_final.gd

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
	var b2: Transform3D = body.global_transform.affine_inverse()

	var lp: Vector3 = b2 * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftUpLeg")).origin)
	var rp: Vector3 = b2 * (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightUpLeg")).origin)
	var side := (lp - rp)
	side.y = 0.0
	side = side.normalized()
	var fwd := Vector3.UP.cross(side).normalized()

	var floor_y := 1e9
	var sheath_lo := 1e9
	var sheath_far := Vector3.ZERO
	var far_d := -1.0
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	var org: Vector3 = b2 * sh.global_transform.origin

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
		var g: Transform3D = b2 * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for vi in range(0, va.size(), 3):
				var w: Vector3 = g * va[vi]
				if gear:
					if mi.get_parent().name == "Sheath" or anc.name == "Sheath":
						sheath_lo = minf(sheath_lo, w.y)
						var d := (w - org).length()
						if d > far_d:
							far_d = d
							sheath_far = w
				else:
					floor_y = minf(floor_y, w.y)

	var td: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(0, 1, 0)).normalized()
	var md: Vector3 = (b2.basis * sh.global_transform.basis * Vector3(1, 0, 0)).normalized()
	var rel := sheath_far - org

	print("=== 刀鞘定版驗收（BodyVisual 空間，網格對網格）===")
	print("  角色身高       %.3f m" % (_top(body, b2) - floor_y))
	print("  俯角           %.1f°（改前 36.4° 且刀尖朝前）" % rad_to_deg(atan2(-td.y, Vector2(td.x, td.z).length())))
	print("  刀尖前後       %+.2f（+ = 朝後，改前 -0.80 朝前）" % td.dot(-fwd))
	print("  刀背朝下       %+.2f（負 = 刃朝上，打刀佩法）" % md.y)
	print("  鞘口離地       %.3f m" % (org.y - floor_y))
	print("  鞘尾離地       %.3f m" % (sheath_far.y - floor_y))
	print("  鞘身最低點離地 %.3f m  %s" % [sheath_lo - floor_y, ("★ 插進地面" if sheath_lo < floor_y else "OK，不觸地")])
	print("  鞘尾在身後     %.3f m、外撇 %.3f m" % [rel.dot(-fwd), rel.dot(side)])
	quit()


func _top(body: Node3D, b2: Transform3D) -> float:
	var hi := -1e9
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var g: Transform3D = b2 * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var va: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for vi in range(0, va.size(), 11):
				hi = maxf(hi, (g * va[vi]).y)
	return hi
