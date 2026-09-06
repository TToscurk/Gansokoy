extends SceneTree
## shrine.tscn 進場後量測：每個主要節點的世界 AABB、落地誤差、與地形高度比對。
##
##   Godot --headless --path godot --script tools/audit_shrine_placement.gd

const SCENE := "res://maps/shrine/shrine.tscn"


func _init() -> void:
	var ps := load(SCENE) as PackedScene
	var root := ps.instantiate() as Node3D
	var terrain := _find_terrain(root)
	print("[AUDIT] 場景 %s，節點 %d" % [SCENE, _count(root)])
	# 倉庫已取消（使用者 2026-09-05），本殿改用委製資產，兩者都不再是灰量體。
	var names: Array[String] = ["主鳥居", "拜殿", "本殿", "社務所", "手水舍", "陰陽玉"]
	for n in names:
		var node := root.find_child(n, true, false) as Node3D
		if node == null:
			print("[AUDIT] %-10s ✗ 找不到" % n)
			continue
		var bb: Variant = _world_aabb(node, root)
		if bb == null:
			print("[AUDIT] %-10s 無網格" % n)
			continue
		var b: AABB = bb
		var gy := _ground_y(terrain, b.get_center().x, b.get_center().z)
		var gap := b.position.y - gy
		var flag := "OK" if absf(gap) < 0.15 else ("浮空 +%.2f" % gap if gap > 0 else "陷地 %.2f" % gap)
		print("[AUDIT] %-10s 尺寸 %6.2f x %6.2f x %6.2f  底 y %7.2f  地面 %7.2f  %s"
			% [n, b.size.x, b.size.y, b.size.z, b.position.y, gy, flag])
	root.free()
	quit(0)


func _find_terrain(root: Node) -> MeshInstance3D:
	for m in _meshes(root):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		if a.size.x > 100.0 and a.size.z > 100.0:
			return mi
	return null


## 用地形網格的頂點做最近點查詢（夠精確，且不依賴 height_at）
func _ground_y(terrain: MeshInstance3D, x: float, z: float) -> float:
	if terrain == null:
		return NAN
	var arr := terrain.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var best := 1e9
	var by := 0.0
	for v in vs:
		var d: float = (v.x - x) * (v.x - x) + (v.z - z) * (v.z - z)
		if d < best:
			best = d
			by = v.y
	return by + terrain.position.y


func _world_aabb(node: Node3D, root: Node3D) -> Variant:
	var box: Variant = null
	for m in _meshes(node):
		var mi := m as MeshInstance3D
		var b := _rel(mi, root) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	return box


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
