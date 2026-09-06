extends SceneTree
## 香霖堂重做前的實地測量：本體在哪、佔多大、周圍地形長怎樣。
##
##   Godot --headless --path godot --script tools/probe_kourindou_site.gd
##
## 「周遭環境重做」要先知道保留區的邊界在哪，否則新植被會長進屋子裡、
## 或是把入口擋掉。這支量三件事：
##   1. Shop 子樹的世界 AABB（＝不可侵犯的保留區）
##   2. 地形的可用範圍與起伏（新資產要貼著地面放）
##   3. 現有植被的分布密度（作為新配置的參考基準）

func _init() -> void:
	var packed: PackedScene = load("res://maps/kourindou/kourindou.tscn")
	var src := packed.instantiate()

	print("[SITE] ===== 香霖堂場地測量 =====")

	# ── 1. 保留區：Shop ──
	var shop := src.get_node_or_null("Shop")
	if shop != null:
		var box: Variant = _subtree_aabb(shop as Node3D, src)
		if box != null:
			var b: AABB = box
			print("[SITE] 【保留】Shop 世界 AABB")
			print("[SITE]   中心 (%.1f, %.1f, %.1f)  尺寸 %.1f × %.1f × %.1f m" % [
				b.get_center().x, b.get_center().y, b.get_center().z,
				b.size.x, b.size.y, b.size.z])
			print("[SITE]   x %.1f~%.1f   z %.1f~%.1f   地板 y=%.2f 屋頂 y=%.2f" % [
				b.position.x, b.end.x, b.position.z, b.end.z,
				b.position.y, b.end.y])
			print("[SITE]   → 新植被至少離這個框 3 m，別長進屋裡或擋住門面")
		print("[SITE]   Shop 子節點：%d 個" % shop.get_child_count())

	# ── 2. 其他既有群組 ──
	print("[SITE] --- 現有的頂層群組 ---")
	for c in src.get_children():
		var n := _all(c).size()
		var box: Variant = _subtree_aabb(c as Node3D, src) if c is Node3D else null
		var span := ""
		if box != null:
			var b: AABB = box
			span = "x %.0f~%.0f z %.0f~%.0f" % [
				b.position.x, b.end.x, b.position.z, b.end.z]
		print("[SITE]   %-18s %-22s 子樹%4d  %s" % [c.name, c.get_class(), n, span])

	# ── 3. 地形 ──
	var terr := src.get_node_or_null("Terrain") as MeshInstance3D
	if terr != null and terr.mesh != null:
		var tb := terr.global_transform * terr.mesh.get_aabb()
		print("[SITE] --- 地形 ---")
		print("[SITE]   範圍 x %.0f~%.0f  z %.0f~%.0f（%.0f × %.0f m）" % [
			tb.position.x, tb.end.x, tb.position.z, tb.end.z, tb.size.x, tb.size.z])
		print("[SITE]   高度 %.2f ~ %.2f（起伏 %.2f m）" % [
			tb.position.y, tb.end.y, tb.size.y])
		print("[SITE]   三角面 %d" % _tris(terr.mesh))

	# ── 4. 現有植被密度 ──
	print("[SITE] --- 現有植被 ---")
	for nm in ["Forest", "GrassTall", "GrassShort", "GrassFlower", "VistaTrees", "Junk", "Lamps"]:
		var n := src.get_node_or_null(nm)
		if n == null:
			continue
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			print("[SITE]   %-12s MultiMesh %d 實例" % [nm, mm.instance_count if mm else 0])
		else:
			print("[SITE]   %-12s %d 個子節點" % [nm, n.get_child_count()])

	src.free()
	print("[SITE] done")
	quit(0)


func _subtree_aabb(node: Node3D, root_node: Node) -> Variant:
	var out: Variant = null
	for mi in _meshes(node):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var b := _xform(mi, root_node) * m.get_aabb()
		out = b if out == null else (out as AABB).merge(b)
	return out


func _xform(node: Node3D, root_node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root_node:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
