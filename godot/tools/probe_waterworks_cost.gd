extends SceneTree
## Waterworks 碰撞成本剖析：27 萬面到底來自哪些網格，哪些是玩家真的踩得到的。
##
##   Godot --headless --path godot --script tools/probe_waterworks_cost.gd
##
## 為什麼要先量：gen_ground_collision.gd 把 MachiCanal/Waterworks 整支子樹烘成
## 一個 ConcavePolygonShape3D，當初的目的只是「給筆刷靶面」。但後來 layer 改成
## 32|1，玩家也站在上面（親水階梯、水門平台）。所以不能整塊砍——要先分辨
## 「玩家會站的水平面」與「純裝飾的側面雕刻」。
##
## 輸出：每個網格的三角面數、世界 AABB、朝上面積佔比（法線 y>0.7 的面）。
## 朝上面積 = 可站立表面的量；面數多但朝上面積接近 0 的，就是純裝飾。

const SRC := "res://maps/slice/slice.tscn"
const SUBTREES := [
	"MachiCanal/Waterworks",
	"MachiCanal/VillageStoneBank",
	"MachiCanal/ChannelGeometry",
]


func _init() -> void:
	var packed: PackedScene = load(SRC)
	if packed == null:
		push_error("載入失敗")
		quit(1)
		return
	var src := packed.instantiate()

	for sub_path in SUBTREES:
		var group := src.get_node_or_null(sub_path)
		if group == null:
			print("[WW] 找不到 %s" % sub_path)
			continue
		print("[WW] ===== %s =====" % sub_path)
		var rows: Array = []
		var tot_tris := 0
		var tot_up := 0.0
		for mi in _meshes(group):
			if not mi.visible:
				continue
			if _excluded(mi):
				continue
			var m: Mesh = mi.mesh
			if m == null:
				continue
			var f := m.get_faces()
			if f.is_empty():
				continue
			var xf := _global_xform(mi, src)
			var tris := f.size() / 3
			var up_area := 0.0
			var all_area := 0.0
			var aabb := AABB()
			var first := true
			for i in range(0, f.size(), 3):
				var a := xf * f[i]
				var b := xf * f[i + 1]
				var c := xf * f[i + 2]
				if first:
					aabb = AABB(a, Vector3.ZERO)
					first = false
				aabb = aabb.expand(a).expand(b).expand(c)
				var cross := (b - a).cross(c - a)
				var area := cross.length() * 0.5
				all_area += area
				if area > 0.0 and cross.normalized().y > 0.7:
					up_area += area
			rows.append({
				"n": _path_of(mi, src), "t": tris, "up": up_area, "all": all_area,
				"y0": aabb.position.y, "y1": aabb.end.y,
				"x0": aabb.position.x, "x1": aabb.end.x,
				"z0": aabb.position.z, "z1": aabb.end.z,
			})
			tot_tris += tris
			tot_up += up_area

		rows.sort_custom(func(a, b): return a["t"] > b["t"])
		print("[WW] %-46s %8s %10s %10s  %s" % ["網格", "三角面", "朝上m²", "總面積m²", "世界 Y / XZ"])
		for r in rows:
			print("[WW] %-46s %8d %10.1f %10.1f  y %.2f~%.2f  x %.0f~%.0f z %.0f~%.0f" % [
				r["n"], r["t"], r["up"], r["all"],
				r["y0"], r["y1"], r["x0"], r["x1"], r["z0"], r["z1"]])
		print("[WW] 小計：%d 網格 %d 三角面，朝上面積 %.1f m²" % [rows.size(), tot_tris, tot_up])

	src.free()
	print("[WW] done")
	quit(0)


func _path_of(n: Node, root: Node) -> String:
	var parts := PackedStringArray()
	var cur: Node = n
	while cur != null and cur != root:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 與 gen_ground_collision.gd 完全相同的排除規則（複製，不是重寫）。
func _excluded(mi: MeshInstance3D) -> bool:
	var names := [mi.name]
	var p := mi.get_parent()
	if p != null:
		names.append(p.name)
	for nm in names:
		var s := str(nm)
		if s.contains("CanalWater") or s.contains("PaddyWater"):
			return true
		if s == "Water" or s.ends_with("_Water") or s.begins_with("Water_"):
			return true
		if s.contains("水面") or s.contains("水體"):
			return true
	return false


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
