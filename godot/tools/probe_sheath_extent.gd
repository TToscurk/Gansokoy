extends SceneTree
## 直接量刀鞘「實際頂點」在 Player 空間的最低點與鞘尾位置，
## 不靠長軸假設（GLB 網格原點不在鞘口，差 0.15 m）。
## Run: godot --headless --path godot --script tools/probe_sheath_extent.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://characters/yoriichi/player_yoriichi.tscn", "PackedScene") as PackedScene
	var p := packed.instantiate()
	root.add_child(p)
	for i in 4:
		await process_frame

	# 角色腳底 = 骨架最低骨，當作地面基準
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var pinv: Transform3D = p.global_transform.affine_inverse()
	var foot := 99.0
	for bi in skel.get_bone_count():
		var y: float = (pinv * (skel.global_transform * skel.get_bone_global_pose(bi).origin)).y
		foot = minf(foot, y)
	print("骨架最低骨 y=%.3f（Player 空間）" % foot)

	for nm in ["Sheath", "Sword_Sheathed"]:
		var found := p.find_children(nm, "", true, false)
		if found.is_empty():
			continue
		var n: Node3D = found[0]
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var far_d := -1.0
		var far_pt := Vector3.ZERO
		var org: Vector3 = pinv * n.global_transform.origin
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			if mi.mesh == null:
				continue
			var g: Transform3D = pinv * mi.global_transform
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var va: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for v in va:
					var w: Vector3 = g * v
					lo = lo.min(w)
					hi = hi.max(w)
					var d := (w - org).length()
					if d > far_d:
						far_d = d
						far_pt = w
		print("\n%s（Player 空間，地面 y=0）" % nm)
		print("  鞘口/掛點 y=%.3f" % org.y)
		print("  網格 bbox  y %.3f .. %.3f" % [lo.y, hi.y])
		print("  最遠端（鞘尾）y=%.3f，距掛點 %.3f m" % [far_pt.y, far_d])
		print("  鞘尾離地 %.3f m（腳底 y=%.3f）" % [far_pt.y - foot, foot])
	quit()
