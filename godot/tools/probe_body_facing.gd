extends SceneTree
## 量角色朝向（用腳尖/腳跟）與腰部布料表面，確認刀鞘該往哪垂、有沒有陷進衣服。
## Run: godot --headless --path godot --script tools/probe_body_facing.gd

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

	print("=== 骨架關鍵骨（角色空間，量朝向）===")
	for bn in ["Hips", "Spine", "Head", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftUpLeg", "RightUpLeg", "LeftHand", "RightHand"]:
		var i := skel.find_bone(bn)
		if i < 0:
			continue
		var gp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(i).origin)
		print("  %-14s x=%+.3f y=%+.3f z=%+.3f" % [bn, gp.x, gp.y, gp.z])

	# 腳尖 vs 腳跟：腳尖在前
	var it := skel.find_bone("LeftToeBase")
	var if_ := skel.find_bone("LeftFoot")
	if it >= 0 and if_ >= 0:
		var toe: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(it).origin)
		var ank: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(if_).origin)
		var fwd := (toe - ank)
		fwd.y = 0.0
		fwd = fwd.normalized()
		print("\n角色正面（腳踝→腳尖）: x=%+.3f z=%+.3f  → 正面是 %s" % [fwd.x, fwd.z, ("-Z" if fwd.z < 0 else "+Z")])

	# 左手 x 正負 → 確認左側
	var lh := skel.find_bone("LeftHand")
	if lh >= 0:
		var lp: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(lh).origin)
		print("左手 x=%+.3f  → 角色左側 = %s X" % [lp.x, ("+" if lp.x > 0 else "-")])

	# 腰部布料：取 y 在 0.90~1.05 的角色網格頂點，量水平半徑
	print("\n=== 腰部布料表面（角色空間）===")
	var pts: Array[Vector3] = []
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null or mi.name.begins_with("Sword") or mi.name.begins_with("Sheath"):
			continue
		var xf := binv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var va: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in va:
				var w: Vector3 = xf * v
				if w.y > 0.88 and w.y < 1.06:
					pts.append(w)
	print("  取樣頂點 %d" % pts.size())
	if pts.size() > 0:
		var maxr := 0.0
		var cx := 0.0
		var cz := 0.0
		for v in pts:
			cx += v.x
			cz += v.z
		cx /= pts.size()
		cz /= pts.size()
		# 往刀鞘掛點方向（左前）的表面半徑
		var dirs := {
			"左 (+X)": Vector3(1, 0, 0),
			"左前 (+X-Z)": Vector3(0.707, 0, -0.707),
			"前 (-Z)": Vector3(0, 0, -1),
			"左後 (+X+Z)": Vector3(0.707, 0, 0.707),
		}
		for k in dirs:
			var d: Vector3 = dirs[k]
			var best := -10.0
			for v in pts:
				var rel := Vector3(v.x - cx, 0, v.z - cz)
				if rel.normalized().dot(d) > 0.85:
					best = maxf(best, rel.length())
			print("  %-14s 表面半徑 %.3f m" % [k, best])
		print("  腰部中心 x=%+.3f z=%+.3f" % [cx, cz])
		# 刀鞘掛點目前 x=+0.201 z=+0.274 → 距中心
		var sx := 0.201 - cx
		var sz := 0.274 - cz
		print("  刀鞘掛點距腰心 %.3f m（方向 x=%+.2f z=%+.2f）" % [Vector2(sx, sz).length(), sx, sz])

	quit()
