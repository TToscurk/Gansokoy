extends SceneTree
## 一時：W9 FIX の戸口・見世の『見た目』の実寸（walk 脚の期待値の根拠）＋ 前の P10 碰撞・NPC・互動の一覧（唯讀）
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS := 1 << 19


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	var space := (v as Node3D).get_world_3d().direct_space_state
	var ov := v.get_node("ArchW9R2P13")
	for id in ["B_P_MXC_004", "B_P_MXC_007", "B_P_MKT_025"]:
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		var bxf := body.global_transform
		var inv := bxf.affine_inverse()
		var faces := PackedVector3Array()
		var meshes: Array = []
		for mi in body.get_node("Kit/LOD0").get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
				meshes.append(mi)
		meshes.append(ov.get_node(id + "/L0"))
		for mi: MeshInstance3D in meshes:
			for p in mi.mesh.get_faces():
				faces.append(mi.global_transform * p)
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS
		vb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cp := ConcavePolygonShape3D.new()
		cp.set_faces(faces)
		cp.backface_collision = true
		cs.shape = cp
		vb.add_child(cs)
		root.add_child(vb)
		await physics_frame
		var d2: float = 5.46
		var lxs := {"B_P_MXC_004": [1.0, 1.2, 1.32, 1.5, 1.7], "B_P_MXC_007": [-2.6, -1.7, -0.8, 0.0, 0.35, 0.7, 1.5, 2.4], "B_P_MKT_025": [-2.4, -2.0, -1.2, 0.0, 1.0, 2.2]}
		for lx: float in lxs[id]:
			var row := ""
			for h in [0.25, 0.6, 1.0, 1.4]:
				var o := bxf * Vector3(lx, h, 9.0)
				var t := bxf * Vector3(lx, h, -6.0)
				var q := PhysicsRayQueryParameters3D.create(o, t, VIS)
				q.hit_back_faces = false
				var hit := space.intersect_ray(q)
				var z := (inv * (hit["position"] as Vector3)).z if not hit.is_empty() else NAN
				row += " h%.2f→z %.2f（立面 %+.2f）" % [h, z, z - d2]
			print("[W9MEAS] %s 見た目の最初の面 lx %.2f：%s" % [id, lx, row])
		if id == "B_P_MXC_004":
			for z in [4.3, 4.7, 5.1, 5.4]:
				var r2 := ""
				for dirx in [1.0, -1.0]:
					var o2 := bxf * Vector3(1.35, 1.0, z)
					var t2 := bxf * Vector3(1.35 + dirx * 3.0, 1.0, z)
					var q2 := PhysicsRayQueryParameters3D.create(o2, t2, VIS)
					q2.hit_back_faces = true
					var h2 := space.intersect_ray(q2)
					r2 += " %s x %.2f" % ["+x" if dirx > 0 else "-x", (inv * (h2["position"] as Vector3)).x if not h2.is_empty() else NAN]
				var o3 := bxf * Vector3(1.35, 0.5, z)
				var q3 := PhysicsRayQueryParameters3D.create(o3, bxf * Vector3(1.35, 8.0, z), VIS)
				q3.hit_back_faces = true
				var h3 := space.intersect_ray(q3)
				print("[W9MEAS] MXC_004 戸口 z %.2f：側柱%s・天井 y %.2f" % [z, r2, (inv * (h3["position"] as Vector3)).y if not h3.is_empty() else NAN])
		# 前の他の碰撞（P10 小物・NPC・互動）
		var center := bxf * Vector3(0, 1.0, 7.0)
		var qs := PhysicsShapeQueryParameters3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(10.0, 2.0, 5.0)
		qs.shape = bs
		qs.transform = Transform3D(bxf.basis, center)
		qs.collision_mask = 0xFFFFFFFF & ~VIS
		qs.collide_with_areas = true
		for r in space.intersect_shape(qs, 64):
			var co := r["collider"] as Node
			if co == null or co == body or co.name == "TerrainCollision":
				continue
			var sh: Node = co.shape_owner_get_owner(co.shape_find_owner(int(r["shape"]))) if co is CollisionObject3D else null
			var lp := inv * ((sh as Node3D).global_position if sh is Node3D else (co as Node3D).global_position)
			print("[W9MEAS] %s 前 5 m の碰撞／区域：%s/%s（%s）局部 (%.2f, %.2f, %.2f)" % [id, v.get_path_to(co), sh.name if sh else "", co.get_class(), lp.x, lp.y, lp.z])
		vb.queue_free()
		await physics_frame
	# NPC・互動（MXC_004 の戸口から 10 m 以内）
	var b4 := v.get_node(NodePath(String(L.SPECS["B_P_MXC_004"]["path"]))) as Node3D
	var door4 := b4.global_transform * Vector3(1.32, 0, 5.46)
	for n in v.find_children("*", "", true, false):
		if not (n is Node3D):
			continue
		var nm := String(n.name).to_lower()
		var hit := n is Area3D or nm.contains("npc") or nm.contains("interact") or nm.contains("quest") or n.is_in_group("npc") or n.is_in_group("interactable")
		if hit and (n as Node3D).global_position.distance_to(door4) < 10.0:
			print("[W9MEAS] MXC_004 戸口 10 m 以内：%s（%s）距離 %.2f" % [v.get_path_to(n), n.get_class(), (n as Node3D).global_position.distance_to(door4)])
	quit(0)
