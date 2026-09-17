extends SceneTree
## 量刀鞘掛角：刀鞘長軸相對角色（BodyVisual）的方向與俯角。
## Run: godot --headless --path godot --script tools/probe_sheath.gd

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
	print("=== 角色基準（BodyVisual 空間）===")
	print("  Skeleton3D 路徑: %s" % skel.get_path())

	for nm in ["Sheath", "Sword_Sheathed", "Sword_Hand"]:
		var found := p.find_children(nm, "", true, false)
		if found.is_empty():
			print("%s: 不存在" % nm)
			continue
		var n: Node3D = found[0]
		var aabb := _aabb_of(n)
		if aabb.size == Vector3.ZERO:
			print("%s: 無網格" % nm)
			continue
		# 長軸（本地）→ 世界方向
		var gx := n.global_transform
		var local_axis := Vector3.ZERO
		var mx := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if is_equal_approx(mx, aabb.size.x):
			local_axis = Vector3(1, 0, 0)
		elif is_equal_approx(mx, aabb.size.y):
			local_axis = Vector3(0, 1, 0)
		else:
			local_axis = Vector3(0, 0, 1)
		# 從 aabb 中心往「離原點較遠」那端當刀尖方向
		var tip_sign := signf((aabb.position + aabb.size * 0.5).dot(local_axis))
		if tip_sign == 0.0:
			tip_sign = 1.0
		var dir_world := (gx.basis * (local_axis * tip_sign)).normalized()
		var dir_body := (body.global_transform.basis.inverse() * dir_world).normalized()
		var horiz := Vector2(dir_body.x, dir_body.z).length()
		var pitch_deg := rad_to_deg(atan2(-dir_body.y, horiz))
		var world_pos := gx.origin
		var body_pos := body.global_transform.affine_inverse() * world_pos
		print("\n%s" % nm)
		print("  長度 %.3f m   本地長軸 %s (tip %+.0f)" % [mx, local_axis, tip_sign])
		print("  掛點原點（角色空間） x=%+.3f y=%+.3f z=%+.3f" % [body_pos.x, body_pos.y, body_pos.z])
		print("  刀尖方向（角色空間） x=%+.3f y=%+.3f z=%+.3f" % [dir_body.x, dir_body.y, dir_body.z])
		print("  俯角 = %.1f° 低於水平（0=水平、90=垂直向下）" % pitch_deg)
		print("  前後 = %s（角色正面 = -Z）" % ("朝前" if dir_body.z < -0.15 else ("朝後" if dir_body.z > 0.15 else "側向")))
		print("  左右 = %s" % ("角色左側" if body_pos.x > 0.02 else ("角色右側" if body_pos.x < -0.02 else "正中")))
		var tip_body: Vector3 = body_pos + dir_body * mx
		print("  刀尖端點（角色空間） y=%+.3f m（地面 0）" % tip_body.y)

	quit()


func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var a := mi.mesh.get_aabb()
		var rel := n.global_transform.affine_inverse() * mi.global_transform
		a = rel * a
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out
