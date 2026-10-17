extends SceneTree
## 一時（W9 FIX 最終驗收・相機の的を絞った修正の採寸）：開いた見世の『垂れ壁』（開口の上の見える壁）の範囲を見た目から量る（唯讀）。
##   -- <id> <face:front|left|right> <u0> <u1>   u＝面に沿う座標（front は lx、left/right は lz）
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS := 1 << 19


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	var space := (v as Node3D).get_world_3d().direct_space_state
	var ov := v.get_node("ArchW9R2P13")
	var cf: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(L.COLFIT)) as Dictionary)["buildings"]
	var k := 0
	while k + 3 < a.size():
		var id := a[k]
		var face := a[k + 1]
		var u0 := float(a[k + 2])
		var u1 := float(a[k + 3])
		k += 4
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		var bxf := body.global_transform
		var inv := bxf.affine_inverse()
		var o: Dictionary = (cf[id] as Dictionary)["orig"]
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
		var plane: float = float(o["z1"]) if face == "front" else (float(o["x0"]) if face == "left" else float(o["x1"]))
		var u := u0
		while u <= u1 + 1e-4:
			var row := ""
			var y := 0.5
			var prev_open := false
			var segs: Array = []
			var cur: Array = []
			while y <= 4.2 + 1e-4:
				var lo: Vector3
				var ld: Vector3
				match face:
					"front":
						lo = Vector3(u, y, plane + 3.0)
						ld = Vector3(0, 0, -1)
					"left":
						lo = Vector3(plane - 3.0, y, u)
						ld = Vector3(1, 0, 0)
					_:
						lo = Vector3(plane + 3.0, y, u)
						ld = Vector3(-1, 0, 0)
				var q := PhysicsRayQueryParameters3D.create(bxf * lo, bxf * (lo + ld * 8.0), VIS)
				var h := space.intersect_ray(q)
				var d := 99.0
				if not h.is_empty():
					var lp := inv * (h["position"] as Vector3)
					d = absf((lp.z if face == "front" else lp.x) - plane)
				var at_face := d <= 0.30
				row += "#" if at_face else ("." if d < 99.0 else " ")
				y += 0.05
			print("[W9HW] %s %s u %+.2f  y0.50→4.20  %s" % [id, face, u, row])
			u += 0.1
		vb.queue_free()
		await physics_frame
	quit(0)
