extends SceneTree
## 逐幀追蹤 SheathSocket / Sheath 的世界位置，找出 BoneAttachment 何時穩定，
## 以及「設定 Sheath.transform」會不會連帶動到原點。
## Run: godot --headless --path godot --script tools/probe_socket_settle.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)

	var body: Node3D = p.get_node("BodyVisual")
	var sock: Node3D = p.find_children("SheathSocket", "", true, false)[0]
	var sh: Node3D = p.find_children("Sheath", "", true, false)[0]
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var hi := skel.find_bone("Hips")

	for f in 8:
		await process_frame
		var binv := body.global_transform.affine_inverse()
		var so: Vector3 = binv * sock.global_transform.origin
		var sho: Vector3 = binv * sh.global_transform.origin
		var hip: Vector3 = binv * (skel.global_transform * skel.get_bone_global_pose(hi).origin)
		print("frame %d  Hips y=%+.3f | Socket %s | Sheath %s" % [
			f, hip.y,
			"x=%+.3f y=%+.3f z=%+.3f" % [so.x, so.y, so.z],
			"x=%+.3f y=%+.3f z=%+.3f" % [sho.x, sho.y, sho.z]])

	print("\nSheath local transform: origin %s" % sh.transform.origin)
	print("Sheath local basis scale %s" % sh.transform.basis.get_scale())
	print("Socket bone_name=%s bone_idx=%s override=%s" % [sock.get("bone_name"), sock.get("bone_idx"), sock.get("override_pose")])

	# 只改 basis，看原點會不會動
	var before: Vector3 = body.global_transform.affine_inverse() * sh.global_transform.origin
	sh.transform = Transform3D(Basis.IDENTITY, sh.transform.origin)
	await process_frame
	var after: Vector3 = body.global_transform.affine_inverse() * sh.global_transform.origin
	print("\n只改 basis 前後 Sheath 原點：%s → %s（差 %.4f m）" % [
		"y=%+.3f" % before.y, "y=%+.3f" % after.y, (after - before).length()])
	quit()
