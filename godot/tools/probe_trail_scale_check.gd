extends SceneTree
## 檢查 trail.tscn 內各類地表植被實際佔的世界尺寸 —— 找出「比樹還大的花」
##   Godot --headless --path godot --script tools/probe_trail_scale_check.gd

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var cover := root.get_node("地表植被")
	for grp in cover.get_children():
		var mx := 0.0
		var mn := INF
		var sum := 0.0
		var cnt := 0
		var worst := ""
		for inst in grp.get_children():
			var box: Variant = null
			for m in _mesh_nodes(inst):
				var b: AABB = _rel(m, root) * (m as MeshInstance3D).get_aabb()
				box = b if box == null else (box as AABB).merge(b)
			if box == null: continue
			var h: float = (box as AABB).size.y
			var w: float = maxf((box as AABB).size.x, (box as AABB).size.z)
			var big := maxf(h, w)
			sum += h; cnt += 1
			if big > mx:
				mx = big; worst = "%s scale=%s" % [inst.name, (inst as Node3D).scale]
			mn = minf(mn, h)
		print("[SCALE] %-4s n=%4d  高 min %.2f avg %.2f  最大邊 %.2f  ← %s" % [grp.name, cnt, mn, sum / maxf(cnt, 1), mx, worst])
	root.free()
	quit(0)

func _mesh_nodes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: out.append(n)
	for c in n.get_children(): out.append_array(_mesh_nodes(c))
	return out

func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D: t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
