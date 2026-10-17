extends SceneTree
## P13 W9 FIX：碰撞箱を見た目に合わせるための形状プロファイル（唯讀）。
##   godot --headless --path godot --script res://tools/p13/w9/diag_w9fix_profile.gd -- --out=<json> --ids=B_P_MXC_007,B_P_MKT_025,...
## 各棟（body 局部・0.25 m 格子）：
##   side[s][h] = 外から内へ水平 ray で見た目に最初に当たる『局部の面座標』（front=+z なら z、left=−x なら x）。当たらなければ null。
##   roof[ix][iz] = 上から下への ray で見た目の最上面の局部 y（null＝屋根なし）。ceil[ix][iz] = 局部 y 1.2 から上への ray の最初の見た目（軒裏・天井）。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS_LAYER := 1 << 19
const STEP := 0.25
const HS := [0.6, 1.2, 1.6, 2.2]


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for s in OS.get_cmdline_user_args():
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return d


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	var space := (v as Node3D).get_world_3d().direct_space_state
	var ov := v.get_node("ArchW9R2P13")
	var out := {}
	for id: String in _arg("--ids", "").split(","):
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		var bxf := body.global_transform
		var inv := bxf.affine_inverse()
		var ov_b := ov.get_node(id)
		var faces := PackedVector3Array()
		var la := AABB()
		var first := true
		var meshes: Array = []
		var kit := body.get_node_or_null("Kit/LOD0")
		if kit:
			for mi in kit.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
					meshes.append(mi)
		for c in ov_b.get_children():
			if c is MeshInstance3D and String(c.name) == "L0":
				meshes.append(c)
		for mi: MeshInstance3D in meshes:
			for p in mi.mesh.get_faces():
				var wp := mi.global_transform * p
				faces.append(wp)
				var lp := inv * wp
				la = AABB(lp, Vector3.ZERO) if first else la.expand(lp)
				first = false
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS_LAYER
		vb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cp := ConcavePolygonShape3D.new()
		cp.backface_collision = true
		cp.set_faces(faces)
		cs.shape = cp
		vb.add_child(cs)
		root.add_child(vb)
		await physics_frame
		var box_xf := Transform3D.IDENTITY
		var box_size := Vector3.ZERO
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				box_xf = (c as CollisionShape3D).transform
				box_size = ((c as CollisionShape3D).shape as BoxShape3D).size
		var x0 := la.position.x - 0.5
		var x1 := la.end.x + 0.5
		var z0 := la.position.z - 0.5
		var z1 := la.end.z + 0.5
		var sides := {}
		for sname in ["front", "back", "left", "right"]:
			var per_h := {}
			for h: float in HS:
				var arr: Array = []
				var u := (x0 if sname in ["front", "back"] else z0)
				var u_end := (x1 if sname in ["front", "back"] else z1)
				while u <= u_end + 1e-4:
					var o := Vector3.ZERO
					var d := Vector3.ZERO
					match sname:
						"front":
							o = Vector3(u, h, z1 + 2.0)
							d = Vector3(0, 0, -1)
						"back":
							o = Vector3(u, h, z0 - 2.0)
							d = Vector3(0, 0, 1)
						"left":
							o = Vector3(x0 - 2.0, h, u)
							d = Vector3(1, 0, 0)
						"right":
							o = Vector3(x1 + 2.0, h, u)
							d = Vector3(-1, 0, 0)
					var wo := bxf * o
					var wt := bxf * (o + d * 40.0)
					var q := PhysicsRayQueryParameters3D.create(wo, wt, VIS_LAYER)
					q.hit_back_faces = true
					var hit := space.intersect_ray(q)
					if hit.is_empty():
						arr.append(null)
					else:
						var lp := inv * (hit["position"] as Vector3)
						arr.append(snappedf(lp.z if sname in ["front", "back"] else lp.x, 0.01))
					u += STEP
				per_h[str(h)] = arr
			sides[sname] = per_h
		var roof: Array = []
		var ceil: Array = []
		var x := x0
		while x <= x1 + 1e-4:
			var rrow: Array = []
			var crow: Array = []
			var z := z0
			while z <= z1 + 1e-4:
				var q := PhysicsRayQueryParameters3D.create(bxf * Vector3(x, la.end.y + 3.0, z), bxf * Vector3(x, -1.0, z), VIS_LAYER)
				q.hit_back_faces = true
				var hit := space.intersect_ray(q)
				rrow.append(null if hit.is_empty() else snappedf((inv * (hit["position"] as Vector3)).y, 0.01))
				var q2 := PhysicsRayQueryParameters3D.create(bxf * Vector3(x, 1.2, z), bxf * Vector3(x, la.end.y + 3.0, z), VIS_LAYER)
				q2.hit_back_faces = true
				var h2 := space.intersect_ray(q2)
				crow.append(null if h2.is_empty() else snappedf((inv * (h2["position"] as Vector3)).y, 0.01))
				z += STEP
			roof.append(rrow)
			ceil.append(crow)
			x += STEP
		out[id] = {"x0": x0, "z0": z0, "step": STEP, "hs": HS, "vis_aabb": [[la.position.x, la.position.y, la.position.z], [la.end.x, la.end.y, la.end.z]],
			"box_center": [box_xf.origin.x, box_xf.origin.y, box_xf.origin.z], "box_size": [box_size.x, box_size.y, box_size.z],
			"sides": sides, "roof": roof, "ceil": ceil}
		vb.queue_free()
		await physics_frame
		print("[W9PROF] ", id, " ok")
	var f := FileAccess.open(_arg("--out", "user://prof.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit(0)
