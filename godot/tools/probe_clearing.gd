extends SceneTree
## 大空地的內容物盤點：古樹、水潭、地藏、燈籠、遺留物到底在不在？
##   Godot --headless --path godot --script tools/probe_clearing.gd

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var g := root.get_node_or_null("獸道大空地")
	if g == null:
		print("[CL] 找不到「獸道大空地」節點")
		root.free(); quit(1); return
	print("[CL] 空地子節點 %d" % g.get_child_count())
	for c in g.get_children():
		var extra := ""
		if c is Node3D:
			var box: Variant = null
			for m in _mesh_nodes(c):
				var b: AABB = _rel(m, root) * (m as MeshInstance3D).get_aabb()
				box = b if box == null else (box as AABB).merge(b)
			if box != null:
				var bb := box as AABB
				extra = "  世界AABB 高%.1f 寬%.1f  y %.1f→%.1f" % [bb.size.y, bb.size.x, bb.position.y, bb.end.y]
			else:
				extra = "  (無網格)"
			extra += "  pos=%s scale=%s" % [(c as Node3D).position, (c as Node3D).scale]
		print("[CL] %-24s %s%s" % [c.name, c.get_class(), extra])
	root.free()
	quit(0)

func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_mesh_nodes(c))
	return o

func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D: t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
