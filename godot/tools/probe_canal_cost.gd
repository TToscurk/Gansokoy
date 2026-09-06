extends SceneTree
## B2_Canal collision cost: which meshes are worth their triangles?

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var src: Node = load("res://maps/slice/slice.tscn").instantiate()
	var canal := src.find_child("B2_Canal", true, false)
	var rows: Array = []
	for n in canal.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var tris: int = mi.mesh.get_faces().size() / 3
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var area: float = box.size.x * box.size.z
		# Path under B2_Canal for readability.
		var p := ""
		var cur: Node = mi
		while cur != null and cur != canal:
			p = "/" + String(cur.name) + p
			cur = cur.get_parent()
		rows.append([tris, p, area, box.size])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0
	for r in rows:
		total += r[0]
	print("[COST] B2_Canal 可見網格 %d 個，共 %d 三角面" % [rows.size(), total])
	for r in rows.slice(0, 20):
		print("[COST] %8d tris  %6.0f m²  %5.1f×%4.1f×%5.1f  %s" % [r[0], r[2], r[3].x, r[3].y, r[3].z, r[1]])
	quit(0)
