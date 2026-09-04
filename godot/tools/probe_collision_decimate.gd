extends SceneTree
## 碰撞代理簡化評估：格點分群（vertex clustering）能把三角面砍到多少，
## 表面偏差多大。
##
##   Godot --headless --path godot --script tools/probe_collision_decimate.gd
##
## 為什麼不是凸包：這些 Meshy 網格是**非封閉殼體**，probe_hull_fidelity.gd 的
## 射線奇偶法對開放網格無效（石牆也算出 67% 膨脹），所以凸包保真度無法用那個
## 方法判定。格點分群不需要封閉性，而且偏差有上界保證：把頂點吸附到邊長 CELL
## 的格點上，任何頂點位移不超過 CELL*sqrt(3)/2。
##
## 對碰撞而言這正是我們要的：玩家站立面的高度誤差＝格點大小的一半，
## 選 CELL 就等於選「玩家會浮起／陷入幾公分」。

const CELLS := [0.04, 0.06, 0.10, 0.15]

const TARGETS := [
	"MachiCanal/Waterworks/田泵水口_南/output_unwrapped",
	"MachiCanal/Waterworks/分水堰/output_unwrapped",
	"MachiCanal/Waterworks/石造堰檻/mesh_node",
	"MachiCanal/Waterworks/水車/mesh_node",
	"MachiCanal/Waterworks/濱水平台/mesh_node",
	"MachiCanal/Waterworks/親水階梯/mesh_node",
	"MachiCanal/VillageStoneBank/牆_01/mesh_node",
]


func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	print("[DEC] %-30s %9s %s" % ["網格", "原三角面", "  ".join(_headers())])
	var totals := {}
	for c in CELLS:
		totals[c] = 0
	var orig_total := 0

	for path in TARGETS:
		var mi := src.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			print("[DEC] 找不到 %s" % path)
			continue
		var faces := mi.mesh.get_faces()
		# ⚠ 必須在**世界座標**分群。這些網格帶縮放（石造堰檻 mesh AABB 僅
		# 1.0×0.13 m，世界上卻是 9×1.2 m，放大約 9 倍），在本地空間用 10cm
		# 格點等於世界上的 90cm —— 第一版就是這樣量出「石造堰檻剩 4 面」的
		# 假象。格點大小的物理意義是「玩家腳下誤差幾公分」，只有世界座標成立。
		var xf := _global_xform(mi, src)
		var world := PackedVector3Array()
		world.resize(faces.size())
		for i in faces.size():
			world[i] = xf * faces[i]
		faces = world
		orig_total += faces.size() / 3
		var cols := PackedStringArray()
		for c in CELLS:
			var out := _cluster(faces, c)
			totals[c] += out.size() / 3
			cols.append("%7d" % [out.size() / 3])
		print("[DEC] %-30s %9d %s" % [
			path.get_slice("/", 2) + "/" + path.get_file(), faces.size() / 3,
			"  ".join(cols)])

	var sum_cols := PackedStringArray()
	for c in CELLS:
		sum_cols.append("%7d" % totals[c])
	print("[DEC] %-30s %9d %s" % ["合計", orig_total, "  ".join(sum_cols)])
	print("[DEC] 頂點最大位移上界：%s" % [
		"  ".join(_bounds())])

	src.free()
	print("[DEC] done")
	quit(0)


func _headers() -> PackedStringArray:
	var h := PackedStringArray()
	for c in CELLS:
		h.append("%4.0fcm" % (c * 100.0))
	return h


func _bounds() -> PackedStringArray:
	var b := PackedStringArray()
	for c in CELLS:
		b.append("%4.0fcm→±%.1fcm" % [c * 100.0, c * sqrt(3.0) * 0.5 * 100.0])
	return b


## 頂點吸附到格點，然後丟掉退化（三頂點落到同格）的三角形，並去重。
func _cluster(faces: PackedVector3Array, cell: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seen := {}
	for i in range(0, faces.size(), 3):
		var a := _snap(faces[i], cell)
		var b := _snap(faces[i + 1], cell)
		var c := _snap(faces[i + 2], cell)
		if a == b or b == c or a == c:
			continue
		# 排序後當 key，避免同一個三角形以不同繞序重複收錄。
		var key := _tri_key(a, b, c)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(a)
		out.append(b)
		out.append(c)
	return out


func _snap(v: Vector3, cell: float) -> Vector3:
	return Vector3(roundf(v.x / cell) * cell, roundf(v.y / cell) * cell,
		roundf(v.z / cell) * cell)


func _tri_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var arr := [a, b, c]
	arr.sort_custom(func(p, q):
		if p.x != q.x: return p.x < q.x
		if p.y != q.y: return p.y < q.y
		return p.z < q.z)
	return "%v|%v|%v" % arr


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
