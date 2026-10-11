extends SceneTree
## P11 R2D（只讀、headless）：支線探索で道路格になった点がどの道路か（Roads ribbon の三角形に入るか）と路面高。
const PTS := [Vector2(346, 0), Vector2(354, -33), Vector2(332, 40)]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	for p in PTS:
		var hits := []
		for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var f := mi.mesh.get_faces()
			var xf := mi.global_transform
			for t in range(0, f.size(), 3):
				var a := xf * f[t]
				var b := xf * f[t + 1]
				var c := xf * f[t + 2]
				if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
					hits.append("%s y≈%.2f" % [v.get_path_to(mi), (a.y + b.y + c.y) / 3.0])
					break
		print("[RDN] %s %s" % [p, str(hits)])
	quit(0)
