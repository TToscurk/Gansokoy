extends SceneTree
## 大鳥居的原始比例 vs 規格 §2 —— 等比縮放能不能同時滿足高與寬？
##
##   Godot --headless --path godot --script tools/probe_torii_fit.gd
##
## §2 Main Torii：height 6.0–7.5 m、clear opening width 4.5–6.0 m
##
## blockout 用高度定 scale（9.359）得到高 6.80、寬 9.36 —— 寬度超標 56%。
## 這支算出三種取法的結果，讓使用者用數字決定，不是我猜。
## 註：資產 AABB 的 x 是**整體寬**（含柱外側與笠木出簷），
##     規格說的 clear opening 是兩柱內側淨距，要另外量。

const PATH := "res://assets/landmark/大鳥居.glb"


func _init() -> void:
	var ps := load(PATH) as PackedScene
	if ps == null:
		print("[TORII] 載入失敗 %s" % PATH)
		quit(1)
		return
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var meshes := _mesh_nodes(inst)
	for m in meshes:
		var b: AABB = _rel(m, inst) * (m as MeshInstance3D).get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	var bb := box as AABB
	print("[TORII] 原始 AABB  寬 %.4f  高 %.4f  深 %.4f  （%d 個 mesh）"
		% [bb.size.x, bb.size.y, bb.size.z, meshes.size()])
	print("[TORII] 寬高比 %.3f" % (bb.size.x / bb.size.y))

	# 量「兩柱內側淨距」：在柱高一半處掃 x，找左右兩根柱子的內緣
	var y_probe := bb.position.y + bb.size.y * 0.45
	var xs := []
	for m in meshes:
		var mi := m as MeshInstance3D
		var xf := _rel(mi, inst)
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in vs:
			var w: Vector3 = xf * v
			if absf(w.y - y_probe) < bb.size.y * 0.05:
				xs.append(w.x)
	xs.sort()
	if xs.size() > 20:
		# 柱在兩側，中間是空的：找最大的 x 間隙就是淨開口
		var gap := 0.0
		var g0 := 0.0
		for i in range(1, xs.size()):
			var d: float = xs[i] - xs[i - 1]
			if d > gap:
				gap = d
				g0 = xs[i - 1]
		print("[TORII] 柱間淨開口（原始單位）%.4f  → 佔整體寬 %.1f%%"
			% [gap, gap / bb.size.x * 100.0])
		print("[TORII] %8s %8s %10s %10s %10s" % ["取法", "scale", "高 m", "整體寬 m", "淨開口 m"])
		var plans := [
			["高=6.8", 6.8 / bb.size.y],
			["高=6.0", 6.0 / bb.size.y],
			["淨開口=5.2", 5.2 / gap],
			["淨開口=6.0", 6.0 / gap],
			["整體寬=6.0", 6.0 / bb.size.x],
		]
		for p in plans:
			var s: float = p[1]
			var h := bb.size.y * s
			var w := bb.size.x * s
			var o := gap * s
			var ok_h := "✓" if (h >= 6.0 and h <= 7.5) else "✗"
			var ok_o := "✓" if (o >= 4.5 and o <= 6.0) else "✗"
			print("[TORII] %-12s %6.3f  %6.2f %s  %8.2f  %6.2f %s"
				% [p[0], s, h, ok_h, w, o, ok_o])
	else:
		print("[TORII] 取樣點不足（%d），無法量淨開口" % xs.size())
	inst.free()
	quit(0)


func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_mesh_nodes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
