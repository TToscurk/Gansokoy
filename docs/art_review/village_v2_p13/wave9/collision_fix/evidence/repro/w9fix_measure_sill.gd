extends SceneTree
## 一時：W9 FIX の新しい『pen』（立面 z 5.46・高さ約 0.4 m）の所の見た目の上面の高さ（唯讀）
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
	var terrain := v.get_node("Collision/TerrainCollision") as CollisionObject3D
	var spots := {"B_P_MXC_004": [[1.16, [5.7, 5.4, 5.2, 5.0, 4.6, 4.2]], [1.41, [5.4, 4.6]]],
		"B_P_MXC_007": [[-1.74, [5.7, 5.4, 5.0, 4.6]], [-0.74, [5.4, 5.0]]],
		"B_P_MKT_030": [[-0.51, [5.7, 5.4, 5.0, 4.6]]],
		"B_P_RSW_014": [[-0.75, [5.7, 5.4, 5.0, 4.6]]]}
	for id: String in spots:
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
		cs.shape = cp
		vb.add_child(cs)
		root.add_child(vb)
		await physics_frame
		for sp: Array in spots[id]:
			var lx: float = sp[0]
			for z: float in sp[1]:
				var o := bxf * Vector3(lx, 2.2, z)
				var t := bxf * Vector3(lx, -1.0, z)
				var qv := PhysicsRayQueryParameters3D.create(o, t, VIS)
				var hv := space.intersect_ray(qv)
				var qt := PhysicsRayQueryParameters3D.create(o + Vector3(0, 20, 0), t, 0xFFFFFFFF & ~VIS)
				var ht := {}
				var ex: Array[RID] = []
				for k in 8:
					qt.exclude = ex
					ht = space.intersect_ray(qt)
					if ht.is_empty() or ht["rid"] == terrain.get_rid():
						break
					ex.append(ht["rid"])
				var gy := (inv * (ht["position"] as Vector3)).y if not ht.is_empty() else NAN
				var vy := (inv * (hv["position"] as Vector3)).y if not hv.is_empty() else NAN
				print("[W9SILL] %s lx %.2f z %.2f：見た目の上面 y %.2f・地面 y %.2f → 地面からの高さ %.2f" % [id, lx, z, vy, gy, vy - gy])
		vb.queue_free()
		await physics_frame
	quit(0)
